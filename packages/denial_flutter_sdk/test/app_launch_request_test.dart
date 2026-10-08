import 'package:denial_flutter_sdk/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final request = AppLaunchRequest(
    requestId: 1,
    appName: 'QQ',
    iconPath: null,
    expectedAppIds: <String>['com.qq.QQ', 'QQ'],
    existingObjectIds: <int>[10],
  );

  test('matches the Flatpak and Xwayland QQ identities', () {
    expect(request.matchesWindow(_window(11, appId: 'com.qq.QQ')), isTrue);
    expect(request.matchesWindow(_window(12, appId: 'QQ')), isTrue);
  });

  test('uses a new window title only after excluding existing windows', () {
    expect(
      request.matchesWindow(_window(13, appId: 'unknown', title: 'QQ')),
      isTrue,
    );
    expect(
      request.matchesWindow(_window(10, appId: 'unknown', title: 'QQ')),
      isFalse,
    );
  });
}

DenialWindow _window(int objectId, {required String appId, String title = ''}) {
  return DenialWindow(
    objectId: objectId,
    objectKind: 'wayland',
    surfaceId: objectId,
    windowId: objectId,
    textureId: objectId,
    title: title,
    appId: appId,
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
    transform: 0,
    scale120: 120,
  );
}
