/// A navigable model of Handheld Daemon's `/api/v1/settings` tree.
///
/// The panel renders from this schema instead of hard-coding Legion Go fields,
/// so the same UI adapts to every device Handheld Daemon supports. The tag sets
/// below are Handheld Daemon's own, so the same settings appear at the same
/// level as in its configurator.
library;

import 'hhd_client.dart';

/// Every setting kind Handheld Daemon publishes.
enum HhdSettingKind {
  container,
  mode,
  multiple,
  boolean,
  integer,
  number,
  display,
  action,
  version,
  custom;

  static HhdSettingKind parse(Object? raw) => switch (raw) {
    'container' => HhdSettingKind.container,
    'mode' => HhdSettingKind.mode,
    'multiple' => HhdSettingKind.multiple,
    'bool' => HhdSettingKind.boolean,
    'int' => HhdSettingKind.integer,
    'float' => HhdSettingKind.number,
    'display' => HhdSettingKind.display,
    'action' => HhdSettingKind.action,
    'version' => HhdSettingKind.version,
    _ => HhdSettingKind.custom,
  };
}

/// How much of the tree the panel shows.
///
/// Handheld Daemon's own configurator offers two levels and hides a node when it
/// carries one of the level's tags.
enum HhdVerbosity {
  advanced(<String>[
    'non-essential',
    'advanced',
    'expert',
    'hidden',
    'hhd-update-decky',
    'hhd-version-display-decky',
  ]),
  expert(<String>[
    'expert',
    'hidden',
    'hhd-update-decky',
    'hhd-version-display-decky',
  ]);

  const HhdVerbosity(this.hiddenTags);

  final List<String> hiddenTags;

  bool shows(HhdSettingNode node) => !node.tags.any(hiddenTags.contains);

  HhdVerbosity get toggled => this == HhdVerbosity.advanced
      ? HhdVerbosity.expert
      : HhdVerbosity.advanced;

  String get label => switch (this) {
    HhdVerbosity.advanced => '基础',
    HhdVerbosity.expert => '专家',
  };
}

/// One node of the settings tree, with its dotted key and resolved children.
class HhdSettingNode {
  HhdSettingNode({
    required this.key,
    required this.kind,
    required this.title,
    this.hint = '',
    this.unit = '',
    this.defaultValue,
    this.minimum,
    this.maximum,
    this.step,
    Map<String, String> options = const <String, String>{},
    Map<String, HhdSettingNode> modes = const <String, HhdSettingNode>{},
    List<String> tags = const <String>[],
    Map<String, HhdSettingNode> children = const <String, HhdSettingNode>{},
  }) : options = Map.unmodifiable(options),
       modes = Map.unmodifiable(modes),
       tags = List.unmodifiable(tags),
       children = Map.unmodifiable(children);

  /// Dotted path from the tree root, e.g. `tdp.lenovo.tdp.custom.tdp`.
  final String key;
  final HhdSettingKind kind;
  final String title;
  final String hint;
  final String unit;
  final Object? defaultValue;
  final num? minimum;
  final num? maximum;
  final num? step;
  final Map<String, String> options;
  final Map<String, HhdSettingNode> modes;
  final List<String> tags;
  final Map<String, HhdSettingNode> children;

  bool hasTag(String tag) => tags.contains(tag);

  /// A numeric leaf is bounded only when both ends are known and ordered.
  bool get hasRange =>
      minimum != null && maximum != null && minimum! <= maximum!;

  static HhdSettingNode? fromJson(String key, Object? raw) {
    if (raw is! Map) return null;
    final map = raw.cast<String, Object?>();
    return HhdSettingNode(
      key: key,
      kind: HhdSettingKind.parse(map['type']),
      title: _asString(map['title']) ?? '',
      hint: _asString(map['hint']) ?? '',
      unit: _asString(map['unit']) ?? '',
      defaultValue: map['default'],
      minimum: _asNum(map['min']),
      maximum: _asNum(map['max']),
      step: _asNum(map['step']),
      options: _stringMap(map['options']),
      modes: _childNodes(key, map['modes']),
      tags: _stringList(map['tags']),
      children: _childNodes(key, map['children']),
    );
  }

  static Map<String, HhdSettingNode> _childNodes(String key, Object? raw) {
    if (raw is! Map) return const <String, HhdSettingNode>{};
    final nodes = <String, HhdSettingNode>{};
    raw.forEach((Object? childKey, Object? child) {
      final node = fromJson('$key.$childKey', child);
      if (node != null) nodes['$childKey'] = node;
    });
    return nodes;
  }

  static Map<String, String> _stringMap(Object? raw) {
    if (raw is! Map) return const <String, String>{};
    final out = <String, String>{};
    raw.forEach((Object? key, Object? value) {
      out['$key'] = _asString(value) ?? '$value';
    });
    return out;
  }

  static List<String> _stringList(Object? raw) {
    if (raw is! List) return const <String>[];
    return <String>[
      for (final value in raw)
        if (value is String) value,
    ];
  }

  /// Handheld Daemon is a separate program: a future version may publish a
  /// value of an unexpected type. Reading is tolerant so one odd field cannot
  /// take the panel, and the shell, down.
  static num? _asNum(Object? value) => value is num ? value : null;

  static String? _asString(Object? value) => value is String ? value : null;
}

/// The whole settings tree.
class HhdSettings {
  HhdSettings(this.roots);

  final Map<String, HhdSettingNode> roots;

  factory HhdSettings.fromJson(Map<String, Object?> json) {
    final roots = <String, HhdSettingNode>{};
    json.forEach((String key, Object? value) {
      final node = HhdSettingNode.fromJson(key, value);
      if (node != null) roots[key] = node;
    });
    return HhdSettings(roots);
  }

  /// Depth-first lookup by dotted key, including mode subtrees.
  HhdSettingNode? find(String dottedKey) {
    final segments = dottedKey.split('.');
    var node = roots[segments.first];
    for (final segment in segments.skip(1)) {
      node = node?.children[segment] ?? node?.modes[segment];
    }
    return node;
  }
}

/// Whether Handheld Daemon currently accepts TDP changes.
enum HhdTdpAvailability {
  enabled,
  disabled,
  conflict,
  unavailable;

  bool get canWrite => this == HhdTdpAvailability.enabled;
}

/// Derives the availability flag from live state, preferring Handheld Daemon's
/// neutral Steam interface over the generic readiness flag.
HhdTdpAvailability resolveHhdTdpAvailability(Map<String, Object?> state) {
  final status = readHhdValue(state, 'hhd.steamos.tdp_status');
  if (status is String) {
    switch (status) {
      case 'conflict':
        return HhdTdpAvailability.conflict;
      case 'enabled':
        return HhdTdpAvailability.enabled;
      case 'disabled':
        return HhdTdpAvailability.disabled;
    }
  }
  final ready = readHhdValue(state, 'hhd.settings.tdp_ready');
  if (ready == true) return HhdTdpAvailability.enabled;
  if (ready == false) return HhdTdpAvailability.disabled;
  return HhdTdpAvailability.unavailable;
}
