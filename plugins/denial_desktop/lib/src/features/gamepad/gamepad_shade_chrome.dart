import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:denial_desktop/src/state/reference_shell_controller.dart';
import 'package:denial_flutter_sdk/input.dart';

import '../../desktop/desktop_workspace.dart';
import '../../state/reference_shell_metrics.dart';
import '../../widgets/shade/system_shade_layer.dart';
import 'gamepad_side_panels.dart';

/// Height of the Dock overlay above the Gamepad quick-settings shade.
const double _gamepadDockHeight = 51.0;

/// Profile chrome for the touch-first desktop shell.
///
/// The desktop scene owns the top Dock and all window presentation. This layer
/// keeps the top-edge shade gesture available while hiding the status-bar
/// glyphs, which the Dock already shows, and hosts the two full-height edge
/// sheets the bottom corners open.
///
/// The dashboard sheet's "open settings" request is delivered as a shell action
/// instead of a callback, so this layer stays independent of the desktop
/// scene's launcher.
class GamepadShadeChrome extends ConsumerWidget {
  const GamepadShadeChrome({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final launchActive = ref.watch(
      referenceShellProvider.select((state) => state.launchRequest != null),
    );
    final media = MediaQuery.of(context);
    final shadeActive = ref.watch(
      referenceShellProvider.select(
        (state) =>
            state.quickSettingsVisible ||
            state.quickSettingsDragActive ||
            state.quickSettingsDragProgress > 0,
      ),
    );
    final shadeMedia = media.copyWith(
      padding: media.padding.copyWith(
        top: media.padding.top + _gamepadDockHeight,
      ),
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        ShellInputRegion(
          debugLabel: 'Gamepad shade',
          active: shadeActive,
          pointerPolicy: ShellPointerPolicy.fullScene,
          keyboardPolicy: ShellKeyboardPolicy.capture,
          compositorPolicy: ShellCompositorPolicy.exclusive,
          child: Stack(
            fit: StackFit.expand,
            children: [
              const _GamepadShadeGestureRegion(),
              MediaQuery(
                data: shadeMedia,
                child: SystemShadeLayer(
                  ignoring: launchActive,
                  showStatusBar: false,
                ),
              ),
            ],
          ),
        ),
        // Above the shade: a corner swipe must reach its sheet even while the
        // shade is open, and the sheets own input exclusively when visible.
        const GamepadSidePanels(),
      ],
    );
  }
}

class _GamepadShadeGestureRegion extends ConsumerWidget {
  const _GamepadShadeGestureRegion();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(referenceShellProvider.notifier);
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: _gamepadDockHeight,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onVerticalDragStart: (_) {
          ref.read(desktopWorkspaceProvider.notifier).closeOverview();
          controller.startQuickSettingsDrag(
            progress: ref
                .read(referenceShellProvider)
                .quickSettingsDragProgress,
          );
        },
        onVerticalDragUpdate: (details) {
          controller.updateQuickSettingsDrag(
            Offset(
              0.0,
              details.delta.dy *
                  ReferenceShellMetrics.quickSettingsDragScale(
                    MediaQuery.sizeOf(context),
                  ),
            ),
          );
        },
        onVerticalDragEnd: (details) {
          controller.endQuickSettingsDrag(details.primaryVelocity ?? 0.0);
        },
        onVerticalDragCancel: () => controller.endQuickSettingsDrag(0.0),
      ),
    );
  }
}
