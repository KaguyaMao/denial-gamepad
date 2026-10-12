import 'package:denial_desktop/src/desktop/desktop_overview_preview_interaction.dart';
import 'package:denial_desktop/src/desktop/desktop_scene_layers.dart';
import 'package:denial_desktop/src/desktop/retained_animated_positioned.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  testWidgets('scrolled foreground card owns up-swipe above real barrier', (
    tester,
  ) async {
    var closed = 0;
    var barrierPans = 0;
    await tester.pumpWidget(
      ProviderScope(
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Stack(
            fit: StackFit.expand,
            children: [
              DesktopOverviewInputLayer(
                active: true,
                touchMode: true,
                onBarrierTap: (_) {},
                onBarrierPan: (_) => barrierPans++,
                onBarrierPanStart: () => barrierPans++,
                foregroundControls: const [],
              ),
              RetainedAnimatedPositioned(
                rect: const Rect.fromLTWH(500, 150, 300, 300),
                layoutRect: const Rect.fromLTWH(0, 0, 600, 600),
                paintOffset: const Offset(-350, 0),
                duration: Duration.zero,
                child: DesktopOverviewPreviewInteraction(
                  overviewActive: true,
                  overview: true,
                  desktopWidget: false,
                  dragging: false,
                  swipeUpTerminates: true,
                  label: 'scrolled card',
                  onTap: () {},
                  onClose: () => closed++,
                  onDragStart: () {},
                  onDragUpdate: (_) {},
                  onDragEnd: () {},
                  onDragCancel: () {},
                  child: const ColoredBox(color: Color(0xFF112233)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(const Offset(300, 400));
    await gesture.moveBy(const Offset(0, -40));
    await tester.pump();
    await gesture.moveBy(const Offset(0, -80));
    await tester.pump();
    await gesture.moveBy(const Offset(0, -80));
    await gesture.up();
    await tester.pump();
    expect(closed, 1);
    expect(barrierPans, 0);
  });

  testWidgets('view offset does not restart or rewind card position tween', (
    tester,
  ) async {
    const childKey = ValueKey('retained-card');
    var offset = 0.0;
    late StateSetter rebuild;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return Stack(
              children: [
                RetainedAnimatedPositioned(
                  rect: const Rect.fromLTWH(300, 100, 250, 250),
                  paintOffset: Offset(offset, 0),
                  duration: const Duration(milliseconds: 300),
                  child: const ColoredBox(
                    key: childKey,
                    color: Color(0xFF112233),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
    final initial = tester.getRect(find.byKey(childKey));
    for (final sample in [-80.0, -160.0, -120.0, -200.0]) {
      rebuild(() => offset = sample);
      await tester.pump();
      expect(
        tester.getRect(find.byKey(childKey)),
        initial.shift(Offset(sample, 0)),
      );
      // Unrelated scene/snapshot rebuild: never return to a stale tween origin.
      rebuild(() {});
      await tester.pump(const Duration(milliseconds: 16));
      expect(
        tester.getRect(find.byKey(childKey)),
        initial.shift(Offset(sample, 0)),
      );
    }
  });

  testWidgets('an upward swipe on a gamepad overview card closes its app', (
    tester,
  ) async {
    var closed = 0;
    var scrolled = 0.0;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 300,
            height: 300,
            child: DesktopOverviewPreviewInteraction(
              overviewActive: true,
              overview: true,
              desktopWidget: false,
              dragging: false,
              swipeUpTerminates: true,
              label: 'card',
              onTap: () {},
              onClose: () => closed += 1,
              onDragStart: () {},
              onDragUpdate: (delta) => scrolled += delta.dx,
              onDragEnd: () {},
              onDragCancel: () {},
              child: const ColoredBox(color: Color(0xFF112233)),
            ),
          ),
        ),
      ),
    );

    final gesture = await tester.startGesture(const Offset(400, 350));
    await gesture.moveBy(const Offset(0, -40));
    await tester.pump();
    await gesture.moveBy(const Offset(0, -80));
    await tester.pump();
    await gesture.moveBy(const Offset(0, -80));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(closed, 1, reason: 'upward travel exceeded the termination distance');
    expect(scrolled, 0.0, reason: 'a purely vertical swipe does not scroll');
  });

  testWidgets('horizontal swipe on a card scrolls instead of closing', (
    tester,
  ) async {
    var closed = 0;
    var scrolled = 0.0;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 300,
            height: 300,
            child: DesktopOverviewPreviewInteraction(
              overviewActive: true,
              overview: true,
              desktopWidget: false,
              dragging: false,
              swipeUpTerminates: true,
              label: 'card',
              onTap: () {},
              onClose: () => closed += 1,
              onDragStart: () {},
              onDragUpdate: (delta) => scrolled += delta.dx,
              onDragEnd: () {},
              onDragCancel: () {},
              child: const ColoredBox(color: Color(0xFF112233)),
            ),
          ),
        ),
      ),
    );

    final gesture = await tester.startGesture(const Offset(400, 300));
    await gesture.moveBy(const Offset(-60, -10));
    await tester.pump();
    await gesture.moveBy(const Offset(-60, -10));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(closed, 0);
    expect(scrolled, lessThan(0.0));
  });
}
