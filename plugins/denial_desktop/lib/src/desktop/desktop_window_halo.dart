import 'package:denial_flutter_sdk/effects.dart';
import 'package:denial_flutter_sdk/models.dart';
import 'package:flutter/widgets.dart';

import 'desktop_workspace.dart';

/// How far the halo extends beyond a window, in logical pixels.
///
/// Matches the gamepad tile margin, so the halo reads as the window's own
/// shadow rather than a second frame.
const double desktopWindowHaloExtent = 16.0;

/// How much the covered desktop is darkened, from 0 to 1.
const double desktopWindowHaloDim = 0.16;

/// Blur and dim the desktop a window covers, one ring wider than the window.
///
/// Drawn behind the windows and above the wallpaper, so the region a window
/// hides recedes instead of competing with it. Only visible, non-fullscreen
/// placements on the presented workspace contribute; the ring is clipped to the
/// scene, so edge windows dim to the screen edge rather than past it.
class DesktopWindowHalo extends StatelessWidget {
  const DesktopWindowHalo({
    super.key,
    required this.placements,
    required this.windowsById,
    required this.desktop,
  });

  final List<DesktopWindowPlacement> placements;
  final Map<int, DenialWindow> windowsById;
  final DesktopWorkspaceState desktop;

  @override
  Widget build(BuildContext context) {
    final rects = <Rect>[];
    for (final placement in placements) {
      // Fullscreen already owns the whole output; a halo would only dim it.
      if (placement.fullscreen || placement.minimized) continue;
      if (!desktop.isPlacementPresented(placement)) continue;
      final rect = placement.contentRect.inflate(desktopWindowHaloExtent);
      if (!rect.isFinite || rect.isEmpty) continue;
      rects.add(rect);
    }
    if (rects.isEmpty) return const SizedBox.shrink();
    return Stack(
      fit: StackFit.expand,
      children: [
        for (final rect in rects)
          Positioned.fromRect(
            rect: rect,
            child: const ShellBackdropBlur(
              borderRadius: BorderRadius.zero,
              child: DecoratedBox(
                decoration: BoxDecoration(color: Color(0x29000000)),
              ),
            ),
          ),
      ],
    );
  }
}
