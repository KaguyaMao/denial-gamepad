import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import 'package:denial_flutter_sdk/motion.dart';
import 'package:denial_flutter_sdk/shell_theme.dart';
import 'package:denial_flutter_sdk/rendering.dart';

import '../widgets/desktop_visibility_transition.dart';

/// Publishes whether a window has finished moving into overview.
///
/// The position animation owns this signal so preview emphasis follows its
/// actual completion rather than a parallel timer that can drift or ignore an
/// interrupted transition.
class DesktopOverviewTransitionStatus
    extends InheritedNotifier<ValueNotifier<bool>> {
  const DesktopOverviewTransitionStatus({
    super.key,
    required ValueNotifier<bool> completed,
    required super.child,
  }) : super(notifier: completed);

  static bool completedOf(BuildContext context) {
    final status = context
        .dependOnInheritedWidgetOfExactType<DesktopOverviewTransitionStatus>();
    return status?.notifier?.value ?? true;
  }
}

/// Pointer interaction for a window preview in the desktop overview.
///
/// Overview previews retain the window's real layout size and use a paint
/// transform to fit it into the arranged overview frame. Pan deltas therefore
/// have to be measured in global coordinates: Flutter's local [DragUpdateDetails.delta]
/// is transformed back through the preview scale and would make a scaled-down
/// window move farther than the pointer.
class DesktopOverviewPreviewInteraction extends StatefulWidget {
  const DesktopOverviewPreviewInteraction({
    super.key,
    required this.overviewActive,
    required this.overview,
    required this.desktopWidget,
    required this.dragging,
    this.selected = false,
    this.swipeUpCloses = false,
    required this.label,
    required this.onTap,
    required this.onClose,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onDragCancel,
    this.onFling,
    required this.child,
  });

  final bool overviewActive;
  final bool overview;
  final bool desktopWidget;
  final bool dragging;
  final bool selected;

  /// Touch-first overview: an upward swipe on a card closes its application
  /// instead of repositioning it. Pointer desktops keep drag-to-arrange.
  final bool swipeUpCloses;
  final String label;
  final VoidCallback onTap;
  final VoidCallback onClose;
  final VoidCallback onDragStart;
  final ValueChanged<Offset> onDragUpdate;
  final VoidCallback onDragEnd;
  final VoidCallback onDragCancel;

  /// Horizontal release velocity (logical pixels/second) for strip inertia.
  final ValueChanged<double>? onFling;
  final Widget child;

  @override
  State<DesktopOverviewPreviewInteraction> createState() =>
      _DesktopOverviewPreviewInteractionState();
}

class _DesktopOverviewPreviewInteractionState
    extends State<DesktopOverviewPreviewInteraction> {
  static const double _emphasizedScale = 1.018;
  static const double _swipeCloseDistance = 96.0;

  bool _hovered = false;
  Offset? _lastGlobalDragPosition;
  Offset _swipeTravel = Offset.zero;

  @override
  void didUpdateWidget(covariant DesktopOverviewPreviewInteraction oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((!widget.overview && !widget.desktopWidget) || widget.dragging) {
      _hovered = false;
    }
    if (!widget.overview) {
      _lastGlobalDragPosition = null;
      _swipeTravel = Offset.zero;
    }
  }

  void _setHovered(bool hovered) {
    if ((!widget.overview && !widget.desktopWidget) || _hovered == hovered) {
      return;
    }
    setState(() => _hovered = hovered);
  }

  void _startDrag(DragStartDetails details) {
    _lastGlobalDragPosition = details.globalPosition;
    _swipeTravel = Offset.zero;
    if (widget.swipeUpCloses) {
      return;
    }
    widget.onDragStart();
  }

  void _updateDrag(DragUpdateDetails details) {
    final previousPosition = _lastGlobalDragPosition;
    final globalPosition = details.globalPosition;
    _lastGlobalDragPosition = globalPosition;
    final delta = previousPosition == null
        ? Offset.zero
        : globalPosition - previousPosition;
    if (widget.swipeUpCloses) {
      _swipeTravel += delta;
      // Horizontal motion scrolls the strip even when it starts on a card, so
      // the whole overview pans freely. Only a deliberate upward swipe closes.
      if (delta.dx != 0.0) {
        widget.onDragUpdate(Offset(delta.dx, 0.0));
      }
      return;
    }
    if (previousPosition != null) {
      widget.onDragUpdate(delta);
    }
  }

  void _endDrag(DragEndDetails details) {
    _lastGlobalDragPosition = null;
    if (widget.swipeUpCloses) {
      final upSwipe =
          _swipeTravel.dy <= -_swipeCloseDistance &&
          _swipeTravel.dy.abs() > _swipeTravel.dx.abs();
      _swipeTravel = Offset.zero;
      if (upSwipe) {
        widget.onClose();
      } else {
        widget.onFling?.call(details.velocity.pixelsPerSecond.dx);
      }
      return;
    }
    widget.onDragEnd();
  }

  void _cancelDrag() {
    _lastGlobalDragPosition = null;
    _swipeTravel = Offset.zero;
    if (!widget.swipeUpCloses) {
      widget.onDragCancel();
    }
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (widget.overviewActive &&
        widget.overview &&
        event.buttons == kMiddleMouseButton) {
      widget.onClose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final overviewTransitionCompleted =
        DesktopOverviewTransitionStatus.completedOf(context);
    final hovered =
        (widget.overview || widget.desktopWidget) &&
        !widget.dragging &&
        _hovered;
    final emphasized = widget.overview
        ? overviewTransitionCompleted && (widget.selected || hovered)
        : hovered;
    final interactive =
        (widget.overviewActive && widget.overview) ||
        (!widget.overviewActive && widget.desktopWidget);
    return Semantics(
      button: interactive,
      selected: widget.overview ? widget.selected : null,
      label: interactive ? widget.label : null,
      child: MouseRegion(
        cursor: interactive ? ShellMouseCursors.link : ShellMouseCursors.normal,
        onEnter: interactive ? (_) => _setHovered(true) : null,
        onExit: interactive ? (_) => _setHovered(false) : null,
        child: Listener(
          onPointerDown: _handlePointerDown,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: interactive ? widget.onTap : null,
            onPanStart: widget.overview ? _startDrag : null,
            onPanUpdate: widget.overview ? _updateDrag : null,
            onPanEnd: widget.overview ? _endDrag : null,
            onPanCancel: widget.overview ? _cancelDrag : null,
            child: AnimatedScale(
              duration: Motion.tile,
              curve: emphasized
                  ? Motion.md3EmphasizedDecelerate
                  : Motion.md3EmphasizedAccelerate,
              scale: emphasized ? _emphasizedScale : 1.0,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  widget.child,
                  IgnorePointer(
                    child: DesktopVisibilityFade(
                      child: AnimatedContainer(
                        duration: Motion.tile,
                        curve: Motion.standard,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: context.shellTheme.accent.withValues(
                              alpha: widget.selected ? 1.0 : 0.0,
                            ),
                            width: widget.selected ? 2.0 : 0.0,
                          ),
                          borderRadius: BorderRadius.circular(
                            context.shellTheme.windowRadius,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
