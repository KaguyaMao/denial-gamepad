# Gamepad touch desktop

`DENIAL_SHELL_PROFILE=gamepad` selects the shared desktop scene with touch
policy. It reuses the desktop plugin's windows, workspaces and overview, and
adds touch-first admission and resize behavior in the compositor.

## Architecture

Gamepad is a profile, not a second compositor. One shell bundle and one
`deniald` serve desktop and gamepad; the session launcher sets the profile.

```text
session entry
  denial-gamepad-test.desktop
    -> denial-gamepad-test-session
       DENIAL_SHELL_PROFILE=gamepad
       DENIAL_FLUTTER_BUNDLE=checkout release bundle
    -> ~/.local/share/denial-dev/bin/denial-session
       -> deniald
       -> libapp.so
```

KDE's "进入 Denial 手柄桌面" only writes that same session id and logs out.
It is not a separate implementation.

```text
native compositor                         Flutter plugins/denial_desktop
DENIAL_SHELL_PROFILE=gamepad              profile switch in denial_shell.dart
  wayland_frontend/window_layout.rs         features/gamepad/gamepad_shade_chrome.dart
    admission, exclusive restore, squeeze   desktop_overview_layout.dart
  wayland_frontend/touch_gestures.rs          arrangeUniformStrip
    home gesture, edge resize               desktop_workspace_controller.dart
  window_management.rs                      plugins/denial_top_bar
    split-group close                         touch Dock
  window_state.rs
    transient parent, hidden children
```

The overview strip stays in the desktop plugin. It reads that plugin's private
workspace controller, so a separate package would be a cycle, not a plugin.
Dwindle admission, edge-resize eviction, transient stacking and input capture
stay in `deniald`.

Gamepad lives on `main`. v0.5.1's rotation lock and shared touch routing are
part of the same tree, so the profile layers its policy on that routing instead
of carrying a second copy of `touch_gestures.rs`: three- and four-finger
navigation, the minimize swipe and the desktop swipe come from the shared
recognizer, while the gamepad border resize, the bottom-strip home gesture and
the exclusive/split admission stay profile-specific.

## Layout model

- The compositor's Dwindle layout owns native window placement. Flutter mirrors
  placements and publishes input routing.
- Every application opens as a tile. While the active workspace still has free
  space, a new application tiles in beside the existing ones and the layout
  assigns each a reasonable share.
- Once the workspace is full, the next application replaces every existing tile
  and owns the whole work area.
- Restoring a window from overview uses the same rule, with one exception: if
  the restored window already fills the work area and the foreground window
  does too, the foreground is replaced immediately. A split pane, or a lone
  tile that still leaves free space, goes through the free-space check instead
  of recreating the old split.
- Applications replaced or squeezed out are only minimized. Their process stays
  alive; the split node and its ratio are suspended rather than discarded, so
  they remain visible in overview and return to the same dimensions when restored.
- Explicit transient children stack over their declared parent. For clients
  that omit a parent, matching PID/application identity is only a secondary hint
  and is accepted only for a dialog-sized surface; ordinary second main windows
  remain independent tiles. Overlay geometry is configured before display, and
  oversized maximize requests are capped proportionally. Denial Settings gets
  the full work area.
- Window stacking follows the same back-to-front order for Flutter painting and
  pointer hit testing. Raising a protocol transient preserves its parent-first
  family order; matching app IDs alone never make two ordinary windows a family.
- Pane borders are draggable. Dragging a border until either tile has no room
  left backgrounds that tile and hands its space over. A split boundary is
  shared, so resizing one pane also resizes its neighbour. Squeezing the dragged
  app itself backgrounds it like the short home swipe; it does not terminate the
  app, and its previous size remains available from overview.
- A lone tile resizes freely from any edge, including the margin exposed to the
  screen border. Its size is remembered across activation changes until it joins
  a split.
- The work area does not reserve space for the Dock. A 16-logical-pixel outer
  margin keeps resize borders reachable without a pointer cursor.

## Touch Dock

The top bar presents a transient touch Dock: a short downward swipe from the
top edge reveals the launcher (Kaguya avatar), running/minimized window icons,
overview, battery, clock, and power entry. It overlays windows, reserves no
space, paints above application windows, and auto-hides after a short idle
period. Its hit region follows the same topmost plane. Dock controls render
without pill card backgrounds.

## Overview

The touch profile opens the original horizontally scrolling strip of
application windows, not a miniature of each workspace. Empty workspaces do
not occupy cards.

Every card has the work area's aspect ratio and is 60% of the overview
viewport's height, smaller than a maximized window so more than one card stays
readable. Inside that slot the window is drawn at its real size and position;
leftover space stays empty. A maximized window fills its card. Split panes keep
their true fractions and stay adjacent, so a split remains recognizable instead
of becoming two stretched fullscreen cards. The row scrolls when the cards do
not fit; it does not shrink them.

A window backgrounded by dragging its edge closed appears immediately at the
size it had when the drag began, not the squeezed sliver that crossed the
close threshold. A neighbour squeezed out by the same drag keeps its own
pre-drag size. The tile that remains in front shows its expanded size.

- Tapping a card, including its empty area, activates that application.
  Tapping outside the cards exits overview.
- An upward swipe on a card terminates that application and its native split
  peers.
- Horizontal dragging scrolls the strip.

## Input

- One-finger drag on a tile border resizes it. The border band is 16 logical
  pixels wide and includes the margin between the window and the work-area edge;
  the physical bottom edge is left to the home strip.
- The bottom strip drives the home gesture: a short upward swipe backgrounds the
  focused application, a long upward swipe opens overview.
- A three-finger swipe navigates between workspaces (left/right/up/down).
- A short pull-down from the top edge reveals the Dock; a longer pull continues
  to open the shade.
- Overview, the lock screen, the shade and other exclusive surfaces stay
  Flutter-owned; the compositor does not capture those contacts.

## Profiles

The gamepad profile forces nine workspaces and the Dwindle layout regardless of
stored desktop settings. Native work-area policy is applied at startup and on
every settings synchronization, so leaving the profile restores the user's
stored desktop configuration.

## Session handoff diagnostics

The return-to-KDE launcher records the selected target, detected desktop
manager, compositor PID/exit wait, and final script status in
`$XDG_STATE_HOME/denial-session-select.log` (normally
`~/.local/state/denial-session-select.log`). The `deniald` shutdown and DRM
handoff remain in the system journal under the `deniald` identifier.
