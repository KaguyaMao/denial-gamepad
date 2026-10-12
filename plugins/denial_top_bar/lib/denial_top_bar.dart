@Plugin()
library;

import 'package:denial_sdk/composition.dart';
import 'package:denial_flutter_sdk/surfaces.dart';
import 'package:flutter/widgets.dart';

import 'src/desktop_system_bar.dart';

export 'src/desktop_system_bar.dart'
    show
        DesktopSystemBar,
        DesktopSystemBarIndicatorSlot,
        systemBarBatteryButtonKey;

@Provides(ShellSurface)
final class TopBarPlugin implements ShellSurface {
  const TopBarPlugin();
  @override
  String get id => 'denial_top_bar.panel';
  @override
  ShellSurfaceLayer get layer => ShellSurfaceLayer.desktopControls;
  @override
  ShellSurfacePlacement? place(ShellSurfaceEnvironment environment) {
    final layout = environment.settings.layout;
    // The touch Dock is a transient overlay, independent of the stored desktop
    // bar settings. Its hidden edge handle stays mounted for pull-down input.
    if (environment.gamepad) {
      return ShellSurfacePlacement(
        bounds: ShellSurfacePlacement.edgeBounds(
          environment.output.logicalRect,
          PanelEdge.top,
          denialTouchSystemBarThickness,
        ),
        layer: ShellSurfaceLayer.aboveWindows,
        visible: !environment.locked && !environment.wallpaperSelectorVisible,
      );
    }
    if (layout.systemBarSide == PanelEdge.hidden ||
        !environment.outputSelected(layout.systemBarOutputNames)) {
      return null;
    }
    return ShellSurfacePlacement(
      bounds: ShellSurfacePlacement.edgeBounds(
        environment.output.logicalRect,
        layout.systemBarSide ?? PanelEdge.top,
        layout.systemBarThickness,
      ),
      visible:
          !environment.locked &&
          !environment.wallpaperSelectorVisible &&
          (!environment.fullscreen ||
              environment.overview ||
              environment.desktopVisible),
    );
  }

  @override
  Widget build(BuildContext context, {required ShellSurfaceContext surface}) =>
      DesktopSystemBar(
        monitorId: surface.environment.output.monitorId,
        side:
            surface.environment.settings.layout.systemBarSide ?? PanelEdge.top,
        services: surface.services,
        touch: surface.environment.gamepad,
      );
}

@Provides(ShellWorkArea)
final class TopBarWorkArea implements ShellWorkArea {
  const TopBarWorkArea();
  @override
  ShellWorkAreaReservation? reserve(ShellLayoutSettings settings) =>
      settings.systemBarSide == PanelEdge.hidden
      ? null
      : ShellWorkAreaReservation(
          edge: settings.systemBarSide ?? PanelEdge.top,
          thickness: settings.systemBarThickness,
          outputNames: settings.systemBarOutputNames,
        );
}
