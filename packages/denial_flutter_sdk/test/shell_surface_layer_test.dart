import 'package:denial_flutter_sdk/surfaces.dart';
import 'package:denial_flutter_sdk/surface_hosting.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a placement can select an environment-specific scene layer', () {
    const surface = _EnvironmentLayerSurface();
    final gamepad = resolveShellSurfaces(
      const <ShellSurface>[surface],
      <ShellSurfaceEnvironment>[_environment(gamepad: true)],
    ).single;
    final desktop = resolveShellSurfaces(
      const <ShellSurface>[surface],
      <ShellSurfaceEnvironment>[_environment(gamepad: false)],
    ).single;

    expect(gamepad.layer, ShellSurfaceLayer.aboveWindows);
    expect(desktop.layer, ShellSurfaceLayer.desktopControls);
  });
}

ShellSurfaceEnvironment _environment({required bool gamepad}) =>
    ShellSurfaceEnvironment(
      output: const DisplayOutput(
        monitorId: 1,
        name: 'eDP-1',
        logicalRect: Rect.fromLTWH(0, 0, 1200, 800),
        pixelSize: Size(1200, 800),
        scale: 1,
        refreshRate: 60,
      ),
      workArea: const Rect.fromLTWH(0, 0, 1200, 800),
      isMainOutput: true,
      workspaceId: 1,
      fullscreen: false,
      overview: false,
      desktopVisible: false,
      wallpaperSelectorVisible: false,
      locked: false,
      settings: const ShellSettings(),
      defaultOutputSelected: true,
      gamepad: gamepad,
    );

final class _EnvironmentLayerSurface implements ShellSurface {
  const _EnvironmentLayerSurface();

  @override
  String get id => 'test.environment-layer';

  @override
  ShellSurfaceLayer get layer => ShellSurfaceLayer.desktopControls;

  @override
  ShellSurfacePlacement place(ShellSurfaceEnvironment environment) =>
      ShellSurfacePlacement(
        bounds: environment.output.logicalRect,
        layer: environment.gamepad ? ShellSurfaceLayer.aboveWindows : null,
      );

  @override
  Widget build(BuildContext context, {required ShellSurfaceContext surface}) =>
      const SizedBox.shrink();
}
