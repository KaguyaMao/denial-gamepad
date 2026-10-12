import 'package:denial_desktop/src/desktop/desktop_workspace.dart';
import 'package:denial_flutter_sdk/models.dart';
import 'package:denial_flutter_sdk/settings.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _viewSize = Size(1200, 800);
const _workArea = Rect.fromLTWH(0, 51, 1200, 749);
const _outputBounds = Rect.fromLTWH(0, 0, 1200, 800);

void main() {
  test('Gamepad overview projects every split tile onto workspace cards', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final workspace = container.read(desktopWorkspaceProvider.notifier);
    workspace.syncWorkspaceConfiguration(
      enabled: true,
      count: 3,
      monitorIds: const <int>[0],
      authoritativeActiveWorkspaces: const <int, int>{0: 1},
    );
    workspace.syncWindows(
      <DenialWindow>[
        _window(1, const Rect.fromLTWH(0, 51, 1136, 749), workspaceId: 1),
        // This narrow live pane is smaller than the old overview preview
        // threshold, but must remain part of the real split miniature.
        _window(2, const Rect.fromLTWH(1136, 51, 64, 749), workspaceId: 1),
        _window(3, const Rect.fromLTWH(100, 100, 700, 500), workspaceId: 2),
      ],
      _viewSize,
      1,
      snapshotSequence: 1,
      windowLayout: DesktopWindowLayout.dwindle,
      stripOverview: true,
    );

    workspace.openWorkspaceOverview(
      monitorId: 0,
      bounds: _workArea,
      backgroundBounds: _outputBounds,
      viewport: _workArea,
      orientation: WorkspaceSwitchingOrientation.horizontal,
      selectedObjectId: 1,
    );

    final overview = container.read(desktopWorkspaceProvider).overview!;
    expect(overview.workspaces!.cards, hasLength(3));
    expect(overview.frames.keys, containsAll(<int>[1, 2, 3]));
    final source = container
        .read(desktopWorkspaceProvider)
        .placements[2]!
        .frame;
    final miniature = overview.frames[2]!;
    expect(
      miniature.width / miniature.height,
      closeTo(source.width / source.height, 0.01),
    );

    // A Gamepad swipe outside the cards scrolls the workspace strip without
    // mutating the canonical, unscrolled projections.
    workspace.moveOverviewBy(-1, const Offset(-400, 0));
    final afterPan = container.read(desktopWorkspaceProvider).overview!;
    expect(afterPan.scrollOffset, lessThan(0.0));
    expect(afterPan.frames, overview.frames);

    // Selecting a card updates the camera target while keeping the deck open.
    workspace.applyWorkspaceChanged(0, 2);
    final afterSwitch = container.read(desktopWorkspaceProvider);
    expect(afterSwitch.activeWorkspaceFor(0), 2);
    expect(afterSwitch.overview?.workspaces?.cards, hasLength(3));
  });

  test('a minimized Gamepad window stays on the restore shelf', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final workspace = container.read(desktopWorkspaceProvider.notifier);
    workspace.syncWorkspaceConfiguration(
      enabled: true,
      count: 2,
      monitorIds: const <int>[0],
    );
    workspace.syncWindows(
      <DenialWindow>[
        _window(1, const Rect.fromLTWH(0, 51, 600, 749), workspaceId: 1),
        _window(
          2,
          const Rect.fromLTWH(600, 51, 64, 749),
          workspaceId: 1,
          minimized: true,
        ),
      ],
      _viewSize,
      1,
      snapshotSequence: 1,
      windowLayout: DesktopWindowLayout.dwindle,
      stripOverview: true,
    );

    workspace.openWorkspaceOverview(
      monitorId: 0,
      bounds: _workArea,
      backgroundBounds: _outputBounds,
      viewport: _workArea,
      orientation: WorkspaceSwitchingOrientation.horizontal,
      selectedObjectId: 1,
    );

    final overview = container.read(desktopWorkspaceProvider).overview!;
    expect(overview.workspaces!.shelf.isEmpty, isFalse);
    expect(overview.frames, contains(2));

    // Activating the shelf tile restores it instead of selecting a workspace.
    workspace.activate(2);
    final restored = container.read(desktopWorkspaceProvider);
    expect(restored.overview, isNull);
    expect(restored.placements[2]!.minimized, isFalse);
  });

  test('overlap hit testing activates the same window painted on top', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final workspace = container.read(desktopWorkspaceProvider.notifier);
    final windows = <DenialWindow>[
      _window(1, const Rect.fromLTWH(100, 100, 700, 500), workspaceId: 1),
      _window(2, const Rect.fromLTWH(100, 100, 700, 500), workspaceId: 1),
    ];
    workspace.syncWindows(
      windows,
      _viewSize,
      1,
      snapshotSequence: 1,
      windowLayout: DesktopWindowLayout.stacking,
    );

    expect(
      desktopWindowAtPosition(
        position: const Offset(400, 300),
        workspace: container.read(desktopWorkspaceProvider),
        windowsById: <int, DenialWindow>{
          for (final window in windows) window.objectId: window,
        },
      )?.objectId,
      2,
    );

    // Raising the lower window must update the canonical order used by both
    // scene painting and the shell's pointer hit test.
    workspace.activate(1);
    expect(
      desktopWindowAtPosition(
        position: const Offset(400, 300),
        workspace: container.read(desktopWorkspaceProvider),
        windowsById: <int, DenialWindow>{
          for (final window in windows) window.objectId: window,
        },
      )?.objectId,
      1,
    );
  });
}

DenialWindow _window(
  int id,
  Rect geometry, {
  required int workspaceId,
  bool minimized = false,
}) => DenialWindow(
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
  workspaceId: workspaceId,
  minimized: minimized,
  serverSideDecorated: false,
  transform: 0,
  scale120: 120,
);
