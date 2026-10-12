//! Desktop-session environment publication and systemd target lifecycle.

use super::*;

const DENIAL_SESSION_TARGET: &str = "denial-session.target";
const GRAPHICAL_SESSION_TARGET: &str = "graphical-session.target";
const SYSTEMD_DBUS_NAME: &str = "org.freedesktop.systemd1";
/// Upper bound on waiting for the session targets to reach `inactive` after a
/// requested stop. The display manager is waiting on this process to exit, so a
/// stalled job must not hold the VT hostage indefinitely.
const SESSION_STOP_TIMEOUT: Duration = Duration::from_secs(5);
/// Environment variables Denial publishes into the systemd user manager and the
/// D-Bus activation environment. They describe *this* compositor's session, so
/// they must be withdrawn on exit; a fast Denial -> Plasma relogin can reuse the
/// running user manager, and a stale `WAYLAND_DISPLAY`/`XDG_CURRENT_DESKTOP`
/// makes the next session's portals and KDE init time out into a black screen.
const SESSION_ENVIRONMENT_KEYS: [&str; 7] = [
    "DESKTOP_SESSION",
    "DISPLAY",
    "QT_QPA_PLATFORMTHEME",
    "WAYLAND_DISPLAY",
    "XDG_CURRENT_DESKTOP",
    "XDG_SESSION_DESKTOP",
    "XDG_SESSION_TYPE",
];
const PORTAL_DESKTOP_NAMES: &str = "Denial:wlroots";

pub(super) fn preserves_predecessor_kms_state(
    runtime_limit: RuntimeLimit,
    no_predecessor: bool,
) -> bool {
    !no_predecessor && runtime_limit != RuntimeLimit::UntilLogout
}

fn session_activation_environment(
    wayland_display: &OsStr,
    x11_display: Option<&OsStr>,
    output_control_socket: Option<&OsStr>,
    qt_platform_theme: Option<&OsStr>,
    polkit_agent: bool,
) -> Result<BTreeMap<&'static str, String>, Box<dyn Error>> {
    let wayland_display = wayland_display
        .to_str()
        .ok_or("Wayland socket name is not valid UTF-8")?;
    let qt_platform_theme = qt_platform_theme
        .unwrap_or_else(|| OsStr::new(DEFAULT_QT_QPA_PLATFORMTHEME))
        .to_str()
        .ok_or("QT_QPA_PLATFORMTHEME is not valid UTF-8")?;
    let mut environment = BTreeMap::from([
        ("DESKTOP_SESSION", String::from("Denial")),
        ("QT_QPA_PLATFORMTHEME", qt_platform_theme.to_owned()),
        ("WAYLAND_DISPLAY", wayland_display.to_owned()),
        // xdg-desktop-portal-wlr still consults its portal metadata UseIn list
        // on supported releases. Keep Denial first for our portals.conf and
        // add the documented wlroots alias so the ScreenCast backend is
        // eligible. Launched applications still get XDG_CURRENT_DESKTOP=Denial.
        ("XDG_CURRENT_DESKTOP", PORTAL_DESKTOP_NAMES.to_owned()),
        ("XDG_SESSION_DESKTOP", String::from("Denial")),
        ("XDG_SESSION_TYPE", String::from("wayland")),
    ]);
    if !polkit_agent {
        // The session's agent service reads this and leaves PolicyKit to
        // whatever else the user runs.
        environment.insert("DENIAL_POLKIT_AGENT", String::from("0"));
    }
    if let Some(x11_display) = x11_display {
        environment.insert(
            "DISPLAY",
            x11_display
                .to_str()
                .ok_or("X11 display name is not valid UTF-8")?
                .to_owned(),
        );
    }
    if let Some(socket) = output_control_socket {
        environment.insert(
            "DENIAL_SOCKET",
            socket
                .to_str()
                .ok_or("Denial control socket path is not valid UTF-8")?
                .to_owned(),
        );
    }
    #[cfg(feature = "flutter")]
    if let Some(cursor_environment) = crate::xcursor_sentinel::environment() {
        environment.extend(
            cursor_environment
                .into_iter()
                .map(|(name, value)| (name, value.to_owned())),
        );
    }
    Ok(environment)
}

fn systemd_environment_assignments(environment: &BTreeMap<&'static str, String>) -> Vec<String> {
    environment
        .iter()
        .map(|(name, value)| format!("{name}={value}"))
        .collect()
}

fn update_dbus_activation_environment(
    connection: &zbus::blocking::Connection,
    environment: &BTreeMap<&'static str, String>,
) -> Result<(), zbus::Error> {
    let proxy = zbus::blocking::Proxy::new(
        connection,
        "org.freedesktop.DBus",
        "/org/freedesktop/DBus",
        "org.freedesktop.DBus",
    )?;
    proxy.call("UpdateActivationEnvironment", environment)
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(super) enum SessionActivation {
    Dbus,
    Systemd,
}

impl SessionActivation {
    pub(super) fn starts_systemd_target(self) -> bool {
        self == Self::Systemd
    }
}

fn systemd_user_manager_runtime_available(runtime_dir: Option<&OsStr>) -> bool {
    let Some(runtime_dir) = runtime_dir else {
        return false;
    };
    let runtime_dir = Path::new(runtime_dir);
    runtime_dir.is_absolute() && runtime_dir.join("systemd").is_dir()
}

fn update_systemd_activation_environment(
    connection: &zbus::blocking::Connection,
    environment: &BTreeMap<&'static str, String>,
) -> Result<(), zbus::Error> {
    let proxy = zbus::blocking::Proxy::new(
        connection,
        SYSTEMD_DBUS_NAME,
        "/org/freedesktop/systemd1",
        "org.freedesktop.systemd1.Manager",
    )?;
    proxy.call(
        "SetEnvironment",
        &systemd_environment_assignments(environment),
    )
}

fn change_systemd_graphical_session(
    connection: &zbus::blocking::Connection,
    method: &'static str,
    target: &'static str,
) -> Result<zbus::zvariant::OwnedObjectPath, zbus::Error> {
    let proxy = zbus::blocking::Proxy::new(
        connection,
        SYSTEMD_DBUS_NAME,
        "/org/freedesktop/systemd1",
        "org.freedesktop.systemd1.Manager",
    )?;
    proxy.call(method, &(target, "replace"))
}

fn start_systemd_graphical_session(
    connection: &zbus::blocking::Connection,
) -> Result<zbus::zvariant::OwnedObjectPath, zbus::Error> {
    change_systemd_graphical_session(connection, "StartUnit", DENIAL_SESSION_TARGET)
}

/// Withdraws the session-description variables Denial published at startup.
fn clear_systemd_session_environment(connection: &zbus::blocking::Connection) {
    let Ok(proxy) = zbus::blocking::Proxy::new(
        connection,
        SYSTEMD_DBUS_NAME,
        "/org/freedesktop/systemd1",
        "org.freedesktop.systemd1.Manager",
    ) else {
        return;
    };
    if let Err(error) = proxy.call::<_, _, ()>("UnsetEnvironment", &(SESSION_ENVIRONMENT_KEYS,)) {
        debug!(%error, "could not withdraw the Denial session environment");
    }
}

fn clear_dbus_session_environment(connection: &zbus::blocking::Connection) {
    let Ok(proxy) = zbus::blocking::Proxy::new(
        connection,
        "org.freedesktop.DBus",
        "/org/freedesktop/DBus",
        "org.freedesktop.DBus",
    ) else {
        return;
    };
    let cleared = SESSION_ENVIRONMENT_KEYS.map(|name| (name, ""));
    if let Err(error) = proxy.call::<_, _, ()>("UpdateActivationEnvironment", &(cleared,)) {
        debug!(%error, "could not withdraw the Denial D-Bus activation environment");
    }
}

/// The unit's `ActiveState`, or `None` when the property cannot be read.
fn unit_active_state(connection: &zbus::blocking::Connection, unit: &str) -> Option<String> {
    let proxy = zbus::blocking::Proxy::new(
        connection,
        SYSTEMD_DBUS_NAME,
        "/org/freedesktop/systemd1",
        "org.freedesktop.systemd1.Manager",
    )
    .ok()?;
    let path: zbus::zvariant::OwnedObjectPath = proxy.call("GetUnit", &(unit,)).ok()?;
    let unit_proxy = zbus::blocking::Proxy::new(
        connection,
        SYSTEMD_DBUS_NAME,
        path.as_str(),
        "org.freedesktop.systemd1.Unit",
    )
    .ok()?;
    unit_proxy.get_property::<String>("ActiveState").ok()
}

/// Stops the shared graphical-session target and waits until it is gone.
///
/// `graphical-session.target` is a singleton with `RefuseManualStart=yes`. A
/// fast Denial -> Plasma relogin reuses the running systemd user manager, so
/// leaving this target active (with Denial's units still bound to it) makes the
/// next session's `plasma-workspace-wayland.target` dependencies appear already
/// satisfied; KDE init and the portals then time out against a dead
/// `WAYLAND_DISPLAY` and the VT stays black. Stopping the target and waiting for
/// `inactive` guarantees the next session establishes the target from scratch.
fn stop_and_wait_systemd_graphical_session(
    connection: &zbus::blocking::Connection,
) -> Result<(), zbus::Error> {
    // Stop Denial's own target first so its bound dependencies release before
    // the shared singleton is torn down.
    let _ = change_systemd_graphical_session(connection, "StopUnit", DENIAL_SESSION_TARGET);
    let _ = change_systemd_graphical_session(connection, "StopUnit", GRAPHICAL_SESSION_TARGET);

    let deadline = Instant::now() + SESSION_STOP_TIMEOUT;
    loop {
        match unit_active_state(connection, GRAPHICAL_SESSION_TARGET).as_deref() {
            // A missing or inactive unit both mean the singleton has released.
            None | Some("inactive") | Some("failed") => return Ok(()),
            Some(_) if Instant::now() >= deadline => {
                return Err(zbus::Error::Failure(format!(
                    "{GRAPHICAL_SESSION_TARGET} did not stop within {}s",
                    SESSION_STOP_TIMEOUT.as_secs()
                )));
            }
            Some(_) => std::thread::sleep(Duration::from_millis(25)),
        }
    }
}

pub(super) fn stop_systemd_graphical_session() -> Result<(), Box<dyn Error>> {
    let connection = zbus::blocking::Connection::session()?;
    stop_and_wait_systemd_graphical_session(&connection)?;
    clear_systemd_session_environment(&connection);
    clear_dbus_session_environment(&connection);
    Ok(())
}

pub(super) fn publish_session_activation_environment(
    wayland_display: &OsStr,
    x11_display: Option<&OsStr>,
    output_control_socket: Option<&OsStr>,
    polkit_agent: bool,
) -> Result<SessionActivation, Box<dyn Error>> {
    let qt_platform_theme = std::env::var_os("QT_QPA_PLATFORMTHEME");
    let environment = session_activation_environment(
        wayland_display,
        x11_display,
        output_control_socket,
        qt_platform_theme.as_deref(),
        polkit_agent,
    )?;
    let connection = zbus::blocking::Connection::session()?;
    update_dbus_activation_environment(&connection, &environment)?;

    if !systemd_user_manager_runtime_available(std::env::var_os("XDG_RUNTIME_DIR").as_deref()) {
        info!(
            wayland_display = ?wayland_display,
            x11_display = ?x11_display,
            "published the compositor session to D-Bus activation; no systemd user manager runtime is available"
        );
        return Ok(SessionActivation::Dbus);
    }

    // NameHasOwner is deliberately not used as a capability test here. The
    // user manager can already be running while its well-known D-Bus name is
    // still activatable or being acquired during an early login. Sending the
    // manager calls directly lets D-Bus synchronize that startup instead of
    // permanently selecting the D-Bus-only path from a transient snapshot.
    update_systemd_activation_environment(&connection, &environment).map_err(|error| {
        format!("could not publish the session environment to systemd: {error}")
    })?;
    let job = start_systemd_graphical_session(&connection).map_err(|error| {
        format!("could not start {DENIAL_SESSION_TARGET} through systemd: {error}")
    })?;
    info!(
        wayland_display = ?wayland_display,
        x11_display = ?x11_display,
        target = DENIAL_SESSION_TARGET,
        job = %job,
        "published the compositor session and queued its graphical-session target"
    );
    Ok(SessionActivation::Systemd)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn display_is_published_only_when_xwayland_is_active() {
        let wayland = OsStr::new("wayland-7");
        let x11 = OsStr::new(":3");
        let with_xwayland =
            session_activation_environment(wayland, Some(x11), None, None, true).unwrap();
        let without_xwayland =
            session_activation_environment(wayland, None, None, None, true).unwrap();

        assert_eq!(with_xwayland.get("DISPLAY").map(String::as_str), Some(":3"));
        assert!(!without_xwayland.contains_key("DISPLAY"));
        assert!(!without_xwayland.contains_key("DENIAL_POLKIT_AGENT"));
        let no_agent = session_activation_environment(wayland, None, None, None, false).unwrap();
        assert_eq!(
            no_agent.get("DENIAL_POLKIT_AGENT").map(String::as_str),
            Some("0")
        );
        assert_eq!(
            without_xwayland.get("WAYLAND_DISPLAY").map(String::as_str),
            Some("wayland-7")
        );
        assert_eq!(
            without_xwayland
                .get("XDG_CURRENT_DESKTOP")
                .map(String::as_str),
            Some(PORTAL_DESKTOP_NAMES)
        );
    }

    #[test]
    fn teardown_withdraws_every_published_session_variable() {
        // The environment Denial publishes at startup and the keys it withdraws
        // at teardown must stay in lockstep. A published key that is not
        // cleared leaks this compositor's session description into the next
        // session sharing the systemd user manager.
        let published = session_activation_environment(
            OsStr::new("wayland-7"),
            Some(OsStr::new(":3")),
            Some(OsStr::new("/run/denial.sock")),
            None,
            true,
        )
        .unwrap();
        for key in published.keys() {
            // DENIAL_SOCKET names this process's control socket and is not a
            // desktop-session descriptor; everything else must be withdrawn.
            if *key == "DENIAL_SOCKET" {
                continue;
            }
            assert!(
                SESSION_ENVIRONMENT_KEYS.contains(key),
                "{key} is published but never withdrawn on teardown"
            );
        }
    }
}
