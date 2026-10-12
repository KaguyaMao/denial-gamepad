import 'package:denial_desktop/src/desktop/desktop_overview_target.dart';
import 'package:denial_desktop/src/desktop/desktop_workspace.dart';
import 'package:denial_desktop/src/desktop/desktop_workspace_overview_layout.dart';
import 'package:denial_flutter_sdk/models.dart';
import 'package:denial_flutter_sdk/settings.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _size = Size(1200, 800);
const _bounds = Rect.fromLTWH(0, 51, 1200, 749);

void main() {
  test('the touch strip keeps one row and overflows instead of shrinking', () {
    final items = <DesktopWorkspaceOverviewItem>[
      for (var id = 1; id <= 5; id += 1)
        DesktopWorkspaceOverviewItem(
          objectId: id,
          frame: const Rect.fromLTWH(0, 51, 1200, 749),
          z: id,
          workspaceId: id,
          minimized: false,
        ),
    ];
    final arrangement = DesktopWorkspaceOverviewLayout.arrange(
      items: items,
      bounds: _bounds,
      viewport: _bounds,
      workspaceCount: 5,
      orientation: WorkspaceSwitchingOrientation.horizontal,
      strip: true,
    );
    expect(arrangement.cards, hasLength(5));
    // Every card shares one horizontal band.
    final tops = arrangement.cards.map((card) => card.rect.top).toSet();
    expect(tops, hasLength(1));
    // Five full-width cards cannot fit; the row overflows the bounds.
    final right = arrangement.cards
        .map((card) => card.rect.right)
        .reduce((a, b) => a > b ? a : b);
    expect(right, greaterThan(_bounds.right));
  });

  test('every strip card preserves the source layout proportions', () {
    final items = <DesktopWorkspaceOverviewItem>[
      DesktopWorkspaceOverviewItem(
        objectId: 1,
        frame: const Rect.fromLTWH(0, 51, 1200, 749),
        z: 1,
        workspaceId: 1,
        minimized: false,
      ),
      // A split pane is a narrow sliver on the desktop.
      DesktopWorkspaceOverviewItem(
        objectId: 2,
        frame: const Rect.fromLTWH(600, 51, 300, 749),
        z: 2,
        workspaceId: 1,
        minimized: false,
      ),
    ];
    final arrangement = DesktopWorkspaceOverviewLayout.arrange(
      items: items,
      bounds: _bounds,
      viewport: _bounds,
      workspaceCount: 1,
      orientation: WorkspaceSwitchingOrientation.horizontal,
      strip: true,
    );
    expect(arrangement.cards, hasLength(1));
    final card = arrangement.cards.single;
    final first = arrangement.frames[1]!;
    final second = arrangement.frames[2]!;
    // The two windows remain distinct tiles in the same workspace card.
    expect(first.width / second.width, closeTo(1200 / 300, 0.01));
    expect(card.sourceRect, _bounds);
  });

  test('strip scrolling pans freely and survives a live snapshot', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final workspace = container.read(desktopWorkspaceProvider.notifier);
    workspace.syncWorkspaceConfiguration(
      enabled: true,
      count: 4,
      monitorIds: const <int>[0],
      authoritativeActiveWorkspaces: const <int, int>{0: 1},
    );
    final windows = <DenialWindow>[
      for (var id = 1; id <= 4; id += 1) _window(id, workspaceId: id),
    ];
    workspace.syncWindows(
      windows,
      _size,
      1,
      snapshotSequence: 1,
      windowLayout: DesktopWindowLayout.dwindle,
      stripOverview: true,
    );
    workspace.openWorkspaceOverview(
      monitorId: 0,
      bounds: _bounds,
      backgroundBounds: const Rect.fromLTWH(0, 0, 1200, 800),
      viewport: _bounds,
      orientation: WorkspaceSwitchingOrientation.horizontal,
      stripOverview: true,
      selectedObjectId: 1,
    );
    expect(container.read(desktopWorkspaceProvider).overview, isNotNull);

    workspace.moveOverviewBy(-1, const Offset(-400, 0));
    final scrolled = container
        .read(desktopWorkspaceProvider)
        .overview!
        .scrollOffset;
    expect(scrolled, lessThan(0.0));
    final frames = container.read(desktopWorkspaceProvider).overview!.frames;

    // A live snapshot re-arranges the strip; the user's pan must survive it.
    workspace.syncWindows(
      <DenialWindow>[
        _window(1, workspaceId: 1, x: 950, width: 80),
        _window(2, workspaceId: 2, minimized: true, x: 0, width: 250),
        _window(3, workspaceId: 3),
        _window(4, workspaceId: 4),
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
    expect(
      container.read(desktopWorkspaceProvider).overview!.frames,
      isNotEmpty,
    );
    expect(
      container.read(desktopWorkspaceProvider).overview!.workspaces!.strip,
      isTrue,
    );
  });

  test('backgrounded strip windows retain their split preview geometry', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final workspace = container.read(desktopWorkspaceProvider.notifier);
    workspace.syncWindows(
      <DenialWindow>[
        _window(1, x: 0, width: 600),
        _window(2, x: 600, width: 600),
      ],
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

    workspace.syncWindows(
      <DenialWindow>[
        _window(1, x: 0, width: 600),
        _window(2, minimized: true, x: 600, width: 600),
      ],
      _size,
      1,
      snapshotSequence: 2,
      windowLayout: DesktopWindowLayout.dwindle,
      stripOverview: true,
    );

    expect(
      container.read(desktopWorkspaceProvider).placements[2]!.frame,
      const Rect.fromLTWH(600, 51, 600, 749),
      reason: 'backgrounding must not replace the split frame with fullscreen',
    );
  });

  test('gamepad overview preserves a background split tile aspect ratio', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final workspace = container.read(desktopWorkspaceProvider.notifier);
    final windows = <DenialWindow>[
      _window(1, x: 0, width: 600),
      _window(2, minimized: true, x: 600, width: 600),
    ];
    workspace.syncWindows(
      windows,
      _size,
      1,
      snapshotSequence: 1,
      windowLayout: DesktopWindowLayout.dwindle,
      stripOverview: true,
    );
    final sourceFrame = container
        .read(desktopWorkspaceProvider)
        .placements[2]!
        .frame;
    final target = DesktopOverviewTarget.resolve(
      viewSize: _size,
      displayLayout: _displayLayout,
      windows: windows,
      workspace: container.read(desktopWorkspaceProvider),
      foregroundObjectId: 1,
      preferredMonitorId: 0,
    )!;

    workspace.toggleOverview(
      monitorId: target.monitorId,
      bounds: target.bounds,
      backgroundBounds: target.backgroundBounds,
      objectIds: target.objectIds,
      selectedObjectId: 1,
    );

    final preview = container
        .read(desktopWorkspaceProvider)
        .overview!
        .frames[2]!;
    expect(
      preview.width / preview.height,
      closeTo(sourceFrame.width / sourceFrame.height, 0.01),
    );
  });

  test('a split tile preview keeps its source aspect ratio', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final workspace = container.read(desktopWorkspaceProvider.notifier);
    final windows = <DenialWindow>[
      _window(1, x: 0, width: 600),
      _window(2, minimized: true, x: 600, width: 600),
    ];
    workspace.syncWindows(
      windows,
      _size,
      1,
      snapshotSequence: 1,
      windowLayout: DesktopWindowLayout.dwindle,
      stripOverview: true,
    );
    final splitFrame = container
        .read(desktopWorkspaceProvider)
        .placements[2]!
        .frame;
    final target = DesktopOverviewTarget.resolve(
      viewSize: _size,
      displayLayout: _displayLayout,
      windows: windows,
      workspace: container.read(desktopWorkspaceProvider),
      foregroundObjectId: 1,
      preferredMonitorId: 0,
    )!;

    workspace.toggleOverview(
      monitorId: target.monitorId,
      bounds: target.bounds,
      backgroundBounds: target.backgroundBounds,
      objectIds: target.objectIds,
      selectedObjectId: 1,
    );

    final card = container.read(desktopWorkspaceProvider).overview!.frames[2]!;
    expect(
      card.width / card.height,
      closeTo(splitFrame.width / splitFrame.height, 0.01),
    );
  });

  test('gamepad overview keeps narrow active split tiles in the strip', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final workspace = container.read(desktopWorkspaceProvider.notifier);
    final windows = <DenialWindow>[
      _window(1, x: 0, width: 1136),
      _window(2, x: 1136, width: 64),
    ];
    workspace.syncWindows(
      windows,
      _size,
      1,
      snapshotSequence: 1,
      windowLayout: DesktopWindowLayout.dwindle,
      stripOverview: true,
    );

    final target = DesktopOverviewTarget.resolve(
      viewSize: _size,
      displayLayout: _displayLayout,
      windows: windows,
      workspace: container.read(desktopWorkspaceProvider),
      foregroundObjectId: 1,
      preferredMonitorId: 0,
      includeSmallPreviews: true,
    );
    expect(target?.objectIds, contains(2));
  });

  test(
    'a minimized squeezed tile remains visible and restorable in overview',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final workspace = container.read(desktopWorkspaceProvider.notifier);
      final windows = <DenialWindow>[
        _window(1, width: 600),
        _window(2, minimized: true, x: 600, width: 64),
      ];
      workspace.syncWindows(
        windows,
        _size,
        1,
        snapshotSequence: 1,
        windowLayout: DesktopWindowLayout.dwindle,
        stripOverview: true,
      );

      final target = DesktopOverviewTarget.resolve(
        viewSize: _size,
        displayLayout: _displayLayout,
        windows: windows,
        workspace: container.read(desktopWorkspaceProvider),
        foregroundObjectId: 1,
        preferredMonitorId: 0,
      );
      expect(target?.objectIds, contains(2));

      workspace.toggleOverview(
        monitorId: target!.monitorId,
        bounds: target.bounds,
        backgroundBounds: target.backgroundBounds,
        objectIds: target.objectIds,
        selectedObjectId: 1,
      );
      expect(
        container.read(desktopWorkspaceProvider).overview!.frames.keys,
        contains(2),
      );

      workspace.activate(2);
      expect(
        container.read(desktopWorkspaceProvider).placements[2]!.minimized,
        isFalse,
      );
    },
  );
}

const _displayLayout = DisplayLayout(
  epoch: 1,
  globalOrigin: Offset.zero,
  logicalSize: _size,
  pixelSize: _size,
  engineScale: 1,
  tickerMonitorId: 0,
  systemBarMonitorId: 0,
  systemBarMonitorIds: <int>[0],
  systemBarSide: SystemBarSide.top,
  systemBarThickness: 51,
  maximizePadding: 0,
  outputs: <DisplayOutput>[
    DisplayOutput(
      monitorId: 0,
      name: 'eDP-1',
      logicalRect: Rect.fromLTWH(0, 0, 1200, 800),
      pixelSize: _size,
      scale: 1,
      refreshRate: 60,
    ),
  ],
);

DenialWindow _window(
  int id, {
  bool minimized = false,
  int workspaceId = 1,
  double x = 0,
  double width = 1200,
}) => DenialWindow(
  objectId: id,
  objectKind: 'xdg',
  surfaceId: id,
  windowId: id,
  textureId: id,
  title: 'App $id',
  appId: 'app.$id',
  width: 1200,
  height: 749,
  surfaceX: x,
  surfaceY: 51,
  surfaceWidth: width,
  surfaceHeight: 749,
  textureSourceX: 0,
  textureSourceY: 0,
  textureSourceWidth: 1200,
  textureSourceHeight: 749,
  geometryX: x,
  geometryY: 51,
  geometryWidth: width,
  geometryHeight: 749,
  monitorId: 0,
  workspaceId: workspaceId,
  minimized: minimized,
  serverSideDecorated: false,
  transform: 0,
  scale120: 120,
);
