import 'package:denial_desktop/src/desktop/desktop_overview_layout.dart';
import 'package:denial_desktop/src/desktop/desktop_workspace.dart';
import 'package:denial_flutter_sdk/models.dart';
import 'package:denial_flutter_sdk/settings.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _size = Size(1200, 800);
const _bounds = Rect.fromLTWH(0, 51, 1200, 749);

void main() {
  test('the touch strip keeps one row and overflows instead of shrinking', () {
    final items = <DesktopOverviewItem>[
      for (var id = 1; id <= 5; id += 1)
        DesktopOverviewItem(
          objectId: id,
          frame: const Rect.fromLTWH(0, 51, 1200, 749),
          z: id,
        ),
    ];
    final frames = DesktopOverviewLayout.arrange(
      items: items,
      bounds: _bounds,
      strip: true,
    );
    expect(frames, hasLength(5));
    // Every card shares one horizontal band.
    final tops = frames.values.map((frame) => frame.top).toSet();
    expect(tops, hasLength(1));
    // Five full-width cards cannot fit; the row overflows the bounds.
    final right = frames.values
        .map((frame) => frame.right)
        .reduce((a, b) => a > b ? a : b);
    expect(right, greaterThan(_bounds.right));
  });

  test('every strip card uses the exclusive-application shape', () {
    final items = <DesktopOverviewItem>[
      DesktopOverviewItem(
        objectId: 1,
        frame: const Rect.fromLTWH(0, 51, 1200, 749),
        z: 1,
      ),
      // A split pane is a narrow sliver on the desktop.
      DesktopOverviewItem(
        objectId: 2,
        frame: const Rect.fromLTWH(600, 51, 300, 749),
        z: 2,
      ),
    ];
    final uniform = DesktopOverviewLayout.arrange(
      items: items,
      bounds: _bounds,
      strip: true,
      stripAspectRatio: _bounds.width / _bounds.height,
    );
    expect(uniform, hasLength(2));
    // Both cards share one aspect ratio, so the split pane is not a sliver.
    final first = uniform[1]!;
    final second = uniform[2]!;
    expect(
      (first.width / first.height - second.width / second.height).abs(),
      lessThan(0.001),
    );
    expect(second.width / second.height, closeTo(1200 / 749, 0.01));
  });

  test('backgrounding a card removes it from the overview', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final workspace = container.read(desktopWorkspaceProvider.notifier);
    workspace.syncWindows(
      <DenialWindow>[_window(1), _window(2)],
      _size,
      1,
      snapshotSequence: 1,
      windowLayout: DesktopWindowLayout.dwindle,
      stripOverview: true,
    );
    workspace.toggleOverview(
      monitorId: 0,
      bounds: _bounds,
      backgroundBounds: const Rect.fromLTWH(0, 0, 1200, 800),
      objectIds: {1, 2},
    );
    expect(
      container.read(desktopWorkspaceProvider).overview!.frames,
      hasLength(2),
    );

    workspace.backgroundOverviewWindow(1);
    final overview = container.read(desktopWorkspaceProvider).overview;
    expect(
      overview?.frames.containsKey(1),
      false,
      reason: 'a backgrounded card must leave the strip',
    );
    expect(overview?.frames.containsKey(2), true);
  });

  test('strip scrolling pans freely and survives a live snapshot', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final workspace = container.read(desktopWorkspaceProvider.notifier);
    final windows = <DenialWindow>[
      for (var id = 1; id <= 4; id += 1) _window(id),
    ];
    workspace.syncWindows(
      windows,
      _size,
      1,
      snapshotSequence: 1,
      windowLayout: DesktopWindowLayout.dwindle,
      stripOverview: true,
    );
    workspace.toggleOverview(
      monitorId: 0,
      bounds: _bounds,
      backgroundBounds: const Rect.fromLTWH(0, 0, 1200, 800),
      objectIds: {1, 2, 3, 4},
    );
    expect(container.read(desktopWorkspaceProvider).overview, isNotNull);

    workspace.moveOverviewBy(-1, const Offset(-400, 0));
    final scrolled = container
        .read(desktopWorkspaceProvider)
        .overview!
        .scrollOffset;
    expect(scrolled, lessThan(0.0));

    // A live snapshot re-arranges the strip; the user's pan must survive it.
    workspace.syncWindows(
      <DenialWindow>[
        _window(1),
        _window(2, minimized: true),
        _window(3),
        _window(4),
      ],
      _size,
      1,
      snapshotSequence: 2,
      windowLayout: DesktopWindowLayout.dwindle,
      stripOverview: true,
    );
    expect(
      container.read(desktopWorkspaceProvider).overview!.scrollOffset,
      scrolled,
    );
  });
}

DenialWindow _window(int id, {bool minimized = false}) => DenialWindow(
  objectId: id,
  objectKind: 'xdg',
  surfaceId: id,
  windowId: id,
  textureId: id,
  title: 'App $id',
  appId: 'app.$id',
  width: 1200,
  height: 749,
  surfaceX: 0,
  surfaceY: 51,
  surfaceWidth: 1200,
  surfaceHeight: 749,
  textureSourceX: 0,
  textureSourceY: 0,
  textureSourceWidth: 1200,
  textureSourceHeight: 749,
  geometryX: 0,
  geometryY: 51,
  geometryWidth: 1200,
  geometryHeight: 749,
  monitorId: 0,
  minimized: minimized,
  transform: 0,
  scale120: 120,
);
