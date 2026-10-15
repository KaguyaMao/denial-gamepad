import 'package:denial_flutter_sdk/input.dart';
import 'package:denial_flutter_sdk/motion.dart';
import 'package:denial_flutter_sdk/shell_theme.dart';

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../desktop/desktop_dashboard.dart';
import 'handheld_controls_panel.dart';
import 'side_panel_controller.dart';

/// Width of each edge sheet, as a fraction of the output.
const double sidePanelWidthFraction = 0.25;

/// Full-height edge sheets for the gamepad profile.
///
/// The left sheet is Denial's own dashboard; the right sheet is the Handheld
/// Daemon controls panel. Both span the output's full height and a quarter of
/// its width, and both are opened by a bottom-corner outward swipe that the
/// compositor reports as a shell action.
///
/// The sheets are exclusive: while one is open the desktop scene behind it does
/// not receive contacts, so a window's edge-resize band cannot fight them.
class GamepadSidePanels extends ConsumerWidget {
  const GamepadSidePanels({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final side = ref.watch(sidePanelProvider);
    final controller = ref.read(sidePanelProvider.notifier);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final duration = reduceMotion ? Duration.zero : Motion.cardSettle;
    final width = MediaQuery.sizeOf(context).width * sidePanelWidthFraction;

    return Stack(
      fit: StackFit.expand,
      children: [
        for (final candidate in SidePanelSide.values)
          _SidePanelSheet(
            side: candidate,
            open: side == candidate,
            width: width,
            duration: duration,
            onDismiss: controller.close,
          ),
      ],
    );
  }
}

class _SidePanelSheet extends ConsumerStatefulWidget {
  const _SidePanelSheet({
    required this.side,
    required this.open,
    required this.width,
    required this.duration,
    required this.onDismiss,
  });

  final SidePanelSide side;
  final bool open;
  final double width;
  final Duration duration;
  final VoidCallback onDismiss;

  @override
  ConsumerState<_SidePanelSheet> createState() => _SidePanelSheetState();
}

class _SidePanelSheetState extends ConsumerState<_SidePanelSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: widget.duration,
    value: widget.open ? 1 : 0,
  );
  bool _mounted = false;

  @override
  void initState() {
    super.initState();
    _mounted = widget.open;
    if (widget.open) unawaited(_reveal.forward());
  }

  @override
  void didUpdateWidget(covariant _SidePanelSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.duration != widget.duration) {
      _reveal.duration = widget.duration;
    }
    if (widget.open == oldWidget.open) return;
    if (widget.open) {
      setState(() => _mounted = true);
      unawaited(_reveal.forward());
    } else {
      _reveal.reverse().whenCompleteOrCancel(() {
        if (mounted && !widget.open) setState(() => _mounted = false);
      });
    }
  }

  @override
  void dispose() {
    _reveal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_mounted) return const SizedBox.shrink();
    final onLeft = widget.side == SidePanelSide.left;
    return ShellInputRegion(
      debugLabel: 'Gamepad ${widget.side.name} side panel',
      active: widget.open,
      pointerPolicy: ShellPointerPolicy.fullScene,
      keyboardPolicy: ShellKeyboardPolicy.capture,
      compositorPolicy: ShellCompositorPolicy.exclusive,
      child: AnimatedBuilder(
        animation: _reveal,
        builder: (context, child) => _SidePanelTransition(
          progress: _reveal.value,
          fromLeft: onLeft,
          child: child!,
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onDismiss,
              child: const SizedBox.expand(),
            ),
            Align(
              alignment: onLeft ? Alignment.centerLeft : Alignment.centerRight,
              child: SizedBox(
                width: widget.width,
                height: double.infinity,
                child: _SidePanelSurface(
                  side: widget.side,
                  onDismiss: widget.onDismiss,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Slides the sheet in from its edge and fades it with the reveal progress.
class _SidePanelTransition extends StatelessWidget {
  const _SidePanelTransition({
    required this.progress,
    required this.fromLeft,
    required this.child,
  });

  final double progress;
  final bool fromLeft;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final offset = (1 - progress) * (fromLeft ? -1.0 : 1.0);
    return FractionalTranslation(
      translation: Offset(offset * sidePanelWidthFraction, 0),
      child: Opacity(opacity: progress, child: child),
    );
  }
}

class _SidePanelSurface extends ConsumerWidget {
  const _SidePanelSurface({required this.side, required this.onDismiss});

  final SidePanelSide side;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ShellTheme.of(context);
    return ClipRect(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: theme.panelGradient(
            context.shellColors.panelBackground,
            context.shellColors.panelBackgroundBottom,
          ),
        ),
        child: switch (side) {
          // Denial's own dashboard, reflowed for a tall narrow sheet.
          SidePanelSide.left => DesktopDashboard(
            onEnter: () {},
            onExit: () {},
            onOpenSettings: () {
              onDismiss();
              ref.read(settingsOpenerProvider).open?.call();
            },
          ),
          // Handheld Daemon's device controls.
          SidePanelSide.right => HandheldControlsPanel(onClose: onDismiss),
        },
      ),
    );
  }
}
