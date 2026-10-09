import 'package:denial_desktop/src/desktop/desktop_overview_preview_interaction.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('an upward swipe on a gamepad overview card closes it', (
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
              swipeUpCloses: true,
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

    expect(closed, 1, reason: 'upward travel exceeded the close distance');
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
              swipeUpCloses: true,
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
