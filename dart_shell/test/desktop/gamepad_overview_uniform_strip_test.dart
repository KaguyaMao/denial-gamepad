import 'package:denial_desktop/src/desktop/desktop_overview_layout.dart';
import 'package:denial_desktop/src/desktop/desktop_workspace.dart';
import 'package:denial_flutter_sdk/models.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _workArea = Rect.fromLTWH(0, 51, 1200, 749);
const _bounds = Rect.fromLTWH(0, 51, 1200, 749);

void main() {
  test('every application occupies an equal slot and keeps its real size', () {
    final arrangement = DesktopOverviewLayout.arrangeUniformStrip(
      items: const <DesktopOverviewItem>[
        DesktopOverviewItem(
          objectId: 1,
          frame: _workArea,
          z: 1,
          workspaceId: 1,
        ),
        DesktopOverviewItem(
          objectId: 2,
          frame: Rect.fromLTWH(0, 51, 600, 749),
          z: 2,
          workspaceId: 1,
        ),
        DesktopOverviewItem(
          objectId: 3,
          frame: Rect.fromLTWH(600, 51, 600, 749),
          z: 3,
          workspaceId: 1,
        ),
        // Narrower than the old preview threshold, but still a real pane.
        DesktopOverviewItem(
          objectId: 4,
          frame: Rect.fromLTWH(1136, 51, 64, 749),
          z: 4,
          workspaceId: 2,
        ),
      ],
      bounds: _bounds,
      sourceViewport: _workArea,
    );
    expect(arrangement, isNotNull);
    final slots = arrangement!.slots;
    final frames = arrangement.frames;
    expect(slots[1]!.width, closeTo(slots[2]!.width, 0.01));
    expect(slots[1]!.height, closeTo(slots[2]!.height, 0.01));
    expect(slots[1]!.height, closeTo((_bounds.height - 60) * 0.60, 0.5));
    expect(slots[2]!.width, closeTo(slots[3]!.width, 0.01));
    expect(slots[3]!.width, closeTo(slots[4]!.width, 0.01));
    expect(frames[1]!.width, closeTo(slots[1]!.width, 0.5));
    expect(frames[1]!.height, closeTo(slots[1]!.height, 0.5));
    expect(frames[2]!.width / slots[2]!.width, closeTo(0.5, 0.01));
    expect(frames[3]!.width / slots[3]!.width, closeTo(0.5, 0.01));
    expect(frames[2]!.left, closeTo(slots[2]!.left, 0.5));
    expect(frames[3]!.left, greaterThan(slots[3]!.left));
    expect(slots[2]!.right, lessThan(slots[3]!.left));
    expect(slots[3]!.right, lessThanOrEqualTo(slots[4]!.left));
    expect(frames[4]!.width / slots[4]!.width, closeTo(64 / 1200, 0.02));
    expect(frames.containsKey(4), isTrue);
  });

  test('the uniform strip overflows instead of shrinking cards', () {
    final arrangement = DesktopOverviewLayout.arrangeUniformStrip(
      items: <DesktopOverviewItem>[
        for (var id = 1; id <= 5; id += 1)
          DesktopOverviewItem(
            objectId: id,
            frame: _workArea,
            z: id,
            workspaceId: id,
          ),
      ],
      bounds: _bounds,
      sourceViewport: _workArea,
    );
    final slots = arrangement!.slots;
    expect(slots, hasLength(5));
    final widths = slots.values.map((slot) => slot.width).toList();
    for (final width in widths) {
      expect(width, closeTo(widths.first, 0.01));
    }
    expect(
      slots.values.map((slot) => slot.right).reduce((a, b) => a > b ? a : b),
      greaterThan(_bounds.right),
    );
  });

  test('edge-drag backgrounding keeps the pre-drag size in overview', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final workspace = container.read(desktopWorkspaceProvider.notifier);
    const original = Rect.fromLTWH(0, 51, 600, 749);
    const sliver = Rect.fromLTWH(0, 51, 40, 749);
    workspace.syncWindows(
      <DenialWindow>[_window(1, original)],
      const Size(1200, 800),
      1,
      snapshotSequence: 1,
      stripOverview: true,
    );
    workspace.applyNativePlacement(
      1,
      _resize(
        sequence: 2,
        rect: original,
        phase: DenialWindowPlacementPhase.begin,
      ),
    );
    workspace.applyNativePlacement(
      1,
      _resize(
        sequence: 3,
        rect: sliver,
        phase: DenialWindowPlacementPhase.update,
      ),
    );
    expect(
      container.read(desktopWorkspaceProvider).placements[1]!.frame.width,
      40,
    );

    workspace.syncWindows(
      <DenialWindow>[_window(1, original, minimized: true)],
      const Size(1200, 800),
      1,
      snapshotSequence: 4,
      stripOverview: true,
    );
    expect(
      container.read(desktopWorkspaceProvider).placements[1]!.frame,
      original,
    );

    workspace.openApplicationStripOverview(
      monitorId: 0,
      bounds: _bounds,
      backgroundBounds: const Rect.fromLTWH(0, 0, 1200, 800),
      sourceViewport: _workArea,
      objectIds: const <int>{1},
      selectedObjectId: 1,
    );
    final overview = container.read(desktopWorkspaceProvider).overview!;
    final slot = overview.slots![1]!;
    final content = overview.frames[1]!;
    expect(content.width / slot.width, closeTo(600 / 1200, 0.01));
    expect(content.width, lessThan(slot.width));
  });
}

DenialWindowPlacementEvent _resize({
  required int sequence,
  required Rect rect,
  required DenialWindowPlacementPhase phase,
}) {
  return DenialWindowPlacementEvent(
    sequence: sequence,
    windowId: 1,
    contentRect: rect,
    monitorId: 0,
    workspaceId: 1,
    phase: phase,
    change: DenialWindowPlacementChange.resize,
  );
}

DenialWindow _window(int id, Rect geometry, {bool minimized = false}) {
  return DenialWindow(
    objectId: id,
    objectKind: 'xdg',
    surfaceId: id,
    windowId: id,
    textureId: id,
    title: 'App $id',
    appId: 'app.$id',
    width: geometry.width.round(),
    height: geometry.height.round(),
    surfaceX: geometry.left,
    surfaceY: geometry.top,
    surfaceWidth: geometry.width,
    surfaceHeight: geometry.height,
    textureSourceX: 0,
    textureSourceY: 0,
    textureSourceWidth: geometry.width,
    textureSourceHeight: geometry.height,
    geometryX: geometry.left,
    geometryY: geometry.top,
    geometryWidth: geometry.width,
    geometryHeight: geometry.height,
    monitorId: 0,
    workspaceId: 1,
    minimized: minimized,
    serverSideDecorated: false,
    transform: 0,
    scale120: 120,
  );
}
