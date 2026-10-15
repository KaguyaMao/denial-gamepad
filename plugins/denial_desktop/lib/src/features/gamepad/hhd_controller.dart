/// Handheld Daemon state for the controls sidebar.
///
/// Reads the daemon's schema and live state, long-polls it for changes, and
/// writes single dotted keys back. Handheld Daemon's own touchscreen shortcuts
/// are never read or written here: the gesture layer belongs to the daemon.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'hhd_client.dart';
import 'hhd_schema.dart';

/// How the sidebar is currently talking to Handheld Daemon.
enum HhdConnectionStatus { connecting, ready, unavailable }

class HhdControlState {
  const HhdControlState({
    this.status = HhdConnectionStatus.connecting,
    this.settings,
    this.live = const <String, Object?>{},
    this.availability = HhdTdpAvailability.unavailable,
    this.error,
    this.busy = false,
  });

  final HhdConnectionStatus status;
  final HhdSettings? settings;
  final Map<String, Object?> live;
  final HhdTdpAvailability availability;
  final String? error;
  final bool busy;

  bool get ready => status == HhdConnectionStatus.ready;

  HhdControlState copyWith({
    HhdConnectionStatus? status,
    HhdSettings? settings,
    Map<String, Object?>? live,
    HhdTdpAvailability? availability,
    String? error,
    bool clearError = false,
    bool? busy,
  }) => HhdControlState(
    status: status ?? this.status,
    settings: settings ?? this.settings,
    live: live ?? this.live,
    availability: availability ?? this.availability,
    error: clearError ? null : (error ?? this.error),
    busy: busy ?? this.busy,
  );
}

final hhdClientProvider = Provider<HhdClient>((ref) => HhdClient());

/// Sidebar state. Auto-disposed, so the daemon is only polled while the sidebar
/// is on screen.
final hhdControlProvider =
    NotifierProvider.autoDispose<HhdControlController, HhdControlState>(
      HhdControlController.new,
    );

class HhdControlController extends Notifier<HhdControlState> {
  late final HhdClient _client;
  var _disposed = false;
  var _consecutiveFailures = 0;

  @override
  HhdControlState build() {
    _client = ref.watch(hhdClientProvider);
    ref.onDispose(() => _disposed = true);
    unawaited(_start());
    return const HhdControlState();
  }

  Future<void> _start() async {
    await _load();
    if (_disposed) return;
    await _poll();
  }

  Future<void> _load() async {
    try {
      final settingsJson = await _client.settings();
      final live = await _client.state();
      if (_disposed) return;
      state = state.copyWith(
        status: HhdConnectionStatus.ready,
        settings: HhdSettings.fromJson(settingsJson),
        live: live,
        availability: resolveHhdTdpAvailability(live),
        clearError: true,
      );
      _consecutiveFailures = 0;
    } on HhdApiException catch (error) {
      if (_disposed) return;
      state = state.copyWith(
        status: HhdConnectionStatus.unavailable,
        error: error.message,
      );
    }
  }

  /// Long-polls the daemon's event loop, backing off while it is down.
  Future<void> _poll() async {
    while (!_disposed) {
      try {
        final live = await _client.pollState();
        if (_disposed) return;
        _consecutiveFailures = 0;
        _apply(live);
      } on HhdApiException catch (error) {
        if (_disposed) return;
        _consecutiveFailures++;
        // A single missed long poll is a hiccup, not a disconnection.
        if (_consecutiveFailures >= 2 ||
            state.status != HhdConnectionStatus.ready) {
          state = state.copyWith(
            status: HhdConnectionStatus.unavailable,
            error: error.message,
          );
        }
        // The daemon may have restarted with a different schema.
        if (_consecutiveFailures == 3) await _load();
        await Future<void>.delayed(_backoff(_consecutiveFailures));
      }
    }
  }

  Duration _backoff(int failures) => Duration(seconds: failures.clamp(1, 6));

  void _apply(Map<String, Object?> live) {
    state = state.copyWith(
      status: HhdConnectionStatus.ready,
      live: live,
      availability: resolveHhdTdpAvailability(live),
      clearError: true,
    );
  }

  /// Writes one dotted key and adopts Handheld Daemon's authoritative reply.
  ///
  /// `shortcuts.*` is refused outright: those keys configure Handheld Daemon's
  /// own input handling, including its touchscreen gestures, which stay the
  /// daemon's. This is a guard, not a policy the UI is trusted to enforce.
  Future<void> setValue(String key, Object? value) async {
    if (_disposed) return;
    if (key == 'shortcuts' || key.startsWith('shortcuts.')) return;
    state = state.copyWith(busy: true, clearError: true);
    try {
      final reply = await _client.setValue(key, value);
      if (_disposed) return;
      _apply(reply);
      state = state.copyWith(busy: false);
    } on HhdApiException catch (error) {
      if (_disposed) return;
      state = state.copyWith(busy: false, error: error.message);
    }
  }

  Future<void> refresh() => _load();
}
