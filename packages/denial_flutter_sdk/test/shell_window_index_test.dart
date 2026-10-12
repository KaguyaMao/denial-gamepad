import 'package:denial_flutter_sdk/models.dart';
import 'package:denial_flutter_sdk/state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('hidden transient children remain raw-indexable but not app-facing', () {
    final parent = _window(10);
    final child = _window(
      11,
      transientParentObjectId: parent.objectId,
      hiddenByTransientParent: true,
    );
    final state = ShellState(
      windows: <DenialWindow>[parent, child],
      windowSnapshotSequence: 1,
      locked: false,
      foregroundObjectId: parent.objectId,
    );

    expect(state.windows, contains(child));
    expect(state.windowByObjectId(child.objectId), same(child));
    expect(state.openAppWindows, contains(parent));
    expect(state.openAppWindows, isNot(contains(child)));
    expect(state.openAppWindowsByObjectId[child.objectId], isNull);
    expect(state.windowByWindowId(child.windowId), same(child));
    expect(state.foregroundWindow, same(parent));
    expect(state.openAppWindowCount, 1);
  });
}

DenialWindow _window(
  int objectId, {
  int? transientParentObjectId,
  bool hiddenByTransientParent = false,
}) {
  return DenialWindow(
    objectId: objectId,
    objectKind: 'wayland',
    surfaceId: objectId,
    windowId: objectId,
    textureId: objectId,
    title: 'Window $objectId',
    appId: 'org.example.window$objectId',
    width: 100,
    height: 100,
    surfaceX: 0,
    surfaceY: 0,
    surfaceWidth: 100,
    surfaceHeight: 100,
    textureSourceX: 0,
    textureSourceY: 0,
    textureSourceWidth: 100,
    textureSourceHeight: 100,
    geometryX: 0,
    geometryY: 0,
    geometryWidth: 100,
    geometryHeight: 100,
    monitorId: 0,
    transientParentObjectId: transientParentObjectId,
    hiddenByTransientParent: hiddenByTransientParent,
    transform: 0,
    scale120: 120,
  );
}
