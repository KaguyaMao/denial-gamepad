import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Which edge sheet the gamepad profile shows.
enum SidePanelSide { left, right }

/// Which edge sheet is open, or null when both are closed.
///
/// The gamepad profile owns the two edge sheets. The compositor reports a
/// bottom-corner outward swipe as a shell action, and the chrome that hosts the
/// sheets opens them through this provider.
final sidePanelProvider = NotifierProvider<SidePanelController, SidePanelSide?>(
  SidePanelController.new,
);

class SidePanelController extends Notifier<SidePanelSide?> {
  @override
  SidePanelSide? build() => null;

  void open(SidePanelSide side) {
    if (state != side) state = side;
  }

  void close() {
    if (state != null) state = null;
  }

  void toggle(SidePanelSide side) {
    state = state == side ? null : side;
  }
}

/// Opens the shell's Settings application.
///
/// The desktop scene owns the launcher, and the dashboard sheet lives in the
/// profile chrome, a sibling of the scene. The scene publishes its opener into
/// this shared holder so the sheet can invoke it without reaching into the
/// scene's private state.
class SettingsOpenerHolder {
  void Function()? open;
}

final settingsOpenerProvider = Provider<SettingsOpenerHolder>(
  (ref) => SettingsOpenerHolder(),
);
