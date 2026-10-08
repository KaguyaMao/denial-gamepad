import 'dart:async';
import 'dart:math' as math;

import 'package:denial_flutter_sdk/effects.dart';
import 'package:denial_flutter_sdk/input.dart';
import 'package:denial_flutter_sdk/panels.dart';
import 'package:denial_flutter_sdk/services.dart';
import 'package:denial_flutter_sdk/theme.dart';
import 'package:denial_sdk/system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

part 'desktop_system_bar_components.dart';
part 'desktop_system_bar_media.dart';
part 'desktop_workspace_indicator.dart';

/// The touch Dock strip height, mirroring native `GAMEPAD_SYSTEM_BAR_THICKNESS`.
const double denialTouchSystemBarThickness = 51.0;

/// The desktop system bar. Its strip is reserved from the window work area,
/// so windows maximize beside it while true fullscreen covers it.
///
/// The strip itself paints nothing: modules float as borderless pill cards
/// over the bare wallpaper, and every card follows the wallpaper's extracted
/// accent. Cards cluster at the trailing edge of the strip and spring in one
/// after another when the bar mounts.
const systemBarBatteryButtonKey = ValueKey<String>('system-bar-battery-button');

class _DesktopSystemBarContent extends ConsumerWidget {
  const _DesktopSystemBarContent({
    required this.monitorId,
    required this.side,
    required this.onOpenPowerSettings,
    this.touch = false,
  });

  static const double _edgePadding = 8.0;
  static const double _cardMargin = 5.0;
  static const double _cardGap = 8.0;

  final int monitorId;
  final PanelEdge side;
  final VoidCallback onOpenPowerSettings;
  final bool touch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (touch) {
      return _TouchSystemBar(monitorId: monitorId);
    }
    final accent = WallpaperAccent(
      ref.watch(context.presentationServices.accent),
    );
    final batteryVisible = ref.watch(
      context.telemetryServices.battery.select(
        (battery) => battery.capacity != null,
      ),
    );
    final cpuVisible = ref.watch(
      context.telemetryServices.cpu.select((cpu) => cpu.current != null),
    );
    final gpuCount = ref.watch(
      context.telemetryServices.gpus.select((gpus) => gpus.length),
    );
    final mediaVisible = ref.watch(
      context.mediaServices.media.select(
        (media) => media.value?.available ?? false,
      ),
    );
    final trayVisible = ref.watch(context.trayServices.trayVisible);
    final horizontal = side.isHorizontal;
    final modules = Flex(
      direction: horizontal ? Axis.horizontal : Axis.vertical,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (trayVisible)
          Expanded(
            child: Align(
              alignment: horizontal
                  ? Alignment.centerLeft
                  : Alignment.topCenter,
              child: SingleChildScrollView(
                scrollDirection: horizontal ? Axis.horizontal : Axis.vertical,
                child: _SystemBarEntrance(
                  key: const ValueKey('system-bar-tray'),
                  index: 0,
                  horizontal: horizontal,
                  child: _SystemBarCard(
                    accent: accent,
                    child: _SystemTrayStatusModule(horizontal: horizontal),
                  ),
                ),
              ),
            ),
          ),
        if (mediaVisible)
          _SystemBarEntrance(
            key: const ValueKey('system-bar-media'),
            index:
                (cpuVisible ? 1 : 0) + gpuCount + (batteryVisible ? 1 : 0) + 1,
            horizontal: horizontal,
            child: Padding(
              padding: horizontal
                  ? const EdgeInsets.only(right: _cardGap)
                  : const EdgeInsets.only(bottom: _cardGap),
              child: _SystemBarCard(
                accent: accent,
                child: _MediaStatusProviderModule(accent: accent, side: side),
              ),
            ),
          ),
        if (batteryVisible)
          _SystemBarEntrance(
            key: const ValueKey('system-bar-battery'),
            index: (cpuVisible ? 1 : 0) + gpuCount + 1,
            horizontal: horizontal,
            child: Padding(
              padding: horizontal
                  ? const EdgeInsets.only(right: _cardGap)
                  : const EdgeInsets.only(bottom: _cardGap),
              child: _BatteryStatusCard(
                accent: accent,
                onPressed: onOpenPowerSettings,
              ),
            ),
          ),
        if (gpuCount > 0)
          _GpuStatusCards(
            accent: accent,
            horizontal: horizontal,
            cpuVisible: cpuVisible,
          ),
        if (cpuVisible) _CpuStatusCard(accent: accent, horizontal: horizontal),
        _SystemBarEntrance(
          key: const ValueKey('system-bar-clock'),
          index: 0,
          horizontal: horizontal,
          child: _SystemBarCard(
            accent: accent,
            child: _ClockStatusModule(accent: accent),
          ),
        ),
      ],
    );
    final workspacesEnabled = ref.watch(
      context.workspaceServices.workspacesEnabled,
    );
    return Padding(
      padding: horizontal
          ? const EdgeInsets.symmetric(
              horizontal: _edgePadding,
              vertical: _cardMargin,
            )
          : const EdgeInsets.symmetric(
              horizontal: _cardMargin,
              vertical: _edgePadding,
            ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          modules,
          if (workspacesEnabled)
            Center(
              child: DesktopSystemBarIndicatorSlot(
                horizontal: horizontal,
                child: _WorkspaceIndicator(
                  monitorId: monitorId,
                  horizontal: horizontal,
                  accent: accent,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The touch Dock strip for the gamepad profile: launcher, running windows,
/// battery, clock, and the session power entry, without card backgrounds.
class _TouchSystemBar extends ConsumerWidget {
  const _TouchSystemBar({required this.monitorId});

  final int monitorId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final services = ShellServicesScope.of(context);
    final accent = WallpaperAccent(ref.watch(services.accent));
    final battery = ref.watch(services.battery);
    final now = ref.watch(services.clock).value ?? DateTime.now();
    final windows = ref.watch(services.windows(monitorId));
    final iconSize = 30.0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          _TouchBarButton(
            key: const ValueKey('touch-bar-launcher'),
            label: 'Applications',
            onTap: services.toggleLauncher,
            child: ClipOval(
              child: Image.asset(
                'packages/denial_flutter_sdk/assets/branding/kaguya-avatar.png',
                width: iconSize,
                height: iconSize,
                fit: BoxFit.cover,
              ),
            ),
          ),
          _TouchBarButton(
            key: const ValueKey('touch-bar-overview'),
            label: 'Overview',
            onTap: services.openOverview,
            child: Icon(
              Icons.view_carousel_rounded,
              size: iconSize * 0.8,
              color: context.shellColors.textPrimary,
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final window in windows)
                    _TouchBarButton(
                      key: ValueKey('touch-bar-window-${window.id}'),
                      label: window.title,
                      onTap: () => window.active && !window.minimized
                          ? services.minimizeWindow(window.id)
                          : services.activateWindow(window.id),
                      child: Opacity(
                        opacity: window.minimized ? 0.55 : 1.0,
                        child: SizedBox.square(
                          dimension: iconSize,
                          child: services.buildApplicationIcon(
                            context,
                            window.appId,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (battery.capacity != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: _BatteryModule(accent: accent, status: battery),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: _ClockModule(accent: accent, now: now),
          ),
          _TouchBarButton(
            key: const ValueKey('touch-bar-power'),
            label: 'Power',
            onTap: services.openPowerMenu,
            child: Icon(
              Icons.power_settings_new_rounded,
              size: iconSize * 0.8,
              color: context.shellColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// A bare touch target for one Dock control, without a card background.
class _TouchBarButton extends StatelessWidget {
  const _TouchBarButton({
    required this.label,
    required this.onTap,
    required this.child,
    super.key,
  });

  final String label;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(padding: const EdgeInsets.all(6), child: child),
      ),
    );
  }
}

/// Shrink-wraps the centered workspace pill along the bar's main axis.
///
/// System-bar cards intentionally fill the cross axis. Without this flex
/// boundary, the expanding [Stack] also gives the centered card a bounded main
/// axis, causing its backdrop-filter clip to cover the complete bar strip.
class DesktopSystemBarIndicatorSlot extends StatelessWidget {
  const DesktopSystemBarIndicatorSlot({
    required this.horizontal,
    required this.child,
    super.key,
  });

  final bool horizontal;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Flex(
      direction: horizontal ? Axis.horizontal : Axis.vertical,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[child],
    );
  }
}

/// Keeps changes to tray contents out of the complete system-bar build.
class _SystemTrayStatusModule extends ConsumerWidget {
  const _SystemTrayStatusModule({required this.horizontal});

  final bool horizontal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return context.trayServices.buildSystemTray(
      context,
      horizontal: horizontal,
    );
  }
}

/// Default bar presentation, supplied entirely by the plugin package.
class DesktopSystemBar extends StatelessWidget {
  const DesktopSystemBar({
    required this.monitorId,
    required this.side,
    required this.services,
    this.touch = false,
    super.key,
  });
  final int monitorId;
  final PanelEdge side;
  final ShellServices services;

  /// Touch Dock presentation for the gamepad profile.
  final bool touch;

  @override
  Widget build(BuildContext context) => ShellServicesScope(
    services: services,
    child: _DesktopSystemBarContent(
      monitorId: monitorId,
      side: side,
      touch: touch,
      onOpenPowerSettings: services.openPowerSettings,
    ),
  );
}

extension _PluginContext on BuildContext {
  ShellTelemetryServices get telemetryServices => ShellServicesScope.of(this);
  ShellMediaServices get mediaServices => ShellServicesScope.of(this);
  ShellWorkspaceServices get workspaceServices => ShellServicesScope.of(this);
  ShellPresentationServices get presentationServices =>
      ShellServicesScope.of(this);
  ShellTrayServices get trayServices => ShellServicesScope.of(this);
  ShellStrings get pluginStrings => presentationServices.strings(this);
}
