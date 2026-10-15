import 'package:flutter/material.dart' show CircularProgressIndicator, Icons;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:denial_flutter_sdk/controls.dart';
import 'package:denial_flutter_sdk/motion.dart';
import 'package:denial_flutter_sdk/shell_theme.dart';
import 'package:denial_flutter_sdk/tokens.dart';

import 'hhd_client.dart';
import 'hhd_controller.dart';
import 'hhd_schema.dart';

/// Handheld Daemon's device controls, as a full-height edge sheet.
///
/// The panel renders Handheld Daemon's own schema, so it adapts to the device
/// and matches the daemon's configurator. It never touches `shortcuts.*`: the
/// daemon's touchscreen gestures stay its own.
class HandheldControlsPanel extends ConsumerStatefulWidget {
  const HandheldControlsPanel({required this.onClose, super.key});

  final VoidCallback onClose;

  @override
  ConsumerState<HandheldControlsPanel> createState() =>
      _HandheldControlsPanelState();
}

class _HandheldControlsPanelState extends ConsumerState<HandheldControlsPanel> {
  var _verbosity = HhdVerbosity.advanced;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(hhdControlProvider);
    final controller = ref.read(hhdControlProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(
          status: state.status,
          busy: state.busy,
          verbosity: _verbosity,
          onToggleVerbosity: () =>
              setState(() => _verbosity = _verbosity.toggled),
          onClose: widget.onClose,
          onRefresh: controller.refresh,
        ),
        if (state.error case final message?) _ErrorBanner(message: message),
        Expanded(
          child: switch (state.status) {
            HhdConnectionStatus.connecting => const Center(
              child: CircularProgressIndicator(),
            ),
            HhdConnectionStatus.unavailable => _Unavailable(
              onRetry: controller.refresh,
            ),
            HhdConnectionStatus.ready => _Body(
              state: state,
              controller: controller,
              verbosity: _verbosity,
            ),
          },
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.status,
    required this.busy,
    required this.verbosity,
    required this.onToggleVerbosity,
    required this.onClose,
    required this.onRefresh,
  });

  final HhdConnectionStatus status;
  final bool busy;
  final HhdVerbosity verbosity;
  final VoidCallback onToggleVerbosity;
  final VoidCallback onClose;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final colors = context.shellColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '掌机调节',
                  style: context.shellTheme.text.cardTitle.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
                Text(
                  switch (status) {
                    HhdConnectionStatus.connecting => '正在连接 Handheld Daemon',
                    HhdConnectionStatus.ready => 'Handheld Daemon 已连接',
                    HhdConnectionStatus.unavailable => 'Handheld Daemon 不可用',
                  },
                  style: context.shellTheme.text.systemBarCaption.copyWith(
                    color: colors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          if (busy)
            const Padding(
              padding: EdgeInsets.only(right: 6),
              child: SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          _IconButton(
            icon: Icons.refresh_rounded,
            label: '重新读取',
            onTap: onRefresh,
          ),
          _IconButton(icon: Icons.close_rounded, label: '关闭', onTap: onClose),
        ],
      ),
    );
  }
}

class _IconButton extends StatelessWidget {
  const _IconButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox.square(
        dimension: 40,
        child: Center(
          child: Icon(icon, size: 20, color: context.shellColors.textSecondary),
        ),
      ),
    ),
  );
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.shellColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.performanceWarning.withValues(alpha: 0.18),
          borderRadius: context.shellTheme.borderRadius(ShellRadii.chip),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Text(
            message,
            style: context.shellTheme.text.systemBarCaption.copyWith(
              color: colors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.settings_input_hdmi_rounded,
            size: 36,
            color: context.shellColors.textTertiary,
          ),
          const SizedBox(height: 10),
          Text(
            '无法连接到 Handheld Daemon',
            textAlign: TextAlign.center,
            style: context.shellTheme.text.base.copyWith(
              color: context.shellColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '请确认 hhd 服务正在运行。',
            textAlign: TextAlign.center,
            style: context.shellTheme.text.systemBarCaption.copyWith(
              color: context.shellColors.textTertiary,
            ),
          ),
          const SizedBox(height: 14),
          _PillButton(label: '重试', onTap: onRetry),
        ],
      ),
    ),
  );
}

class _PillButton extends StatelessWidget {
  const _PillButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ShellTheme.of(context);
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.accentPalette.primary,
            borderRadius: theme.borderRadius(ShellRadii.roundButton),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            child: Text(
              label,
              style: theme.text.base.copyWith(
                color: theme.accentPalette.onPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.state,
    required this.controller,
    required this.verbosity,
  });

  /// Sections the panel never shows.
  ///
  /// `shortcuts` configures Handheld Daemon's own input handling, including its
  /// touchscreen gestures. Those stay the daemon's: Denial opens its own side
  /// panels from the screen corners and must not become a second place to edit
  /// the daemon's gesture bindings.
  static const _hiddenSections = <String>{'shortcuts'};

  final HhdControlState state;
  final HhdControlController controller;
  final HhdVerbosity verbosity;

  @override
  Widget build(BuildContext context) {
    final settings = state.settings;
    final tdpWritable = state.availability.canWrite;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        _AvailabilityNote(availability: state.availability),
        if (settings != null)
          for (final entry in settings.roots.entries)
            if (!_hiddenSections.contains(entry.key))
              _Section(
                node: entry.value,
                live: state.live,
                controller: controller,
                verbosity: verbosity,
                tdpWritable: tdpWritable,
              ),
      ],
    );
  }
}

/// Reports TDP ownership so a read-only panel is not mistaken for a bug.
class _AvailabilityNote extends StatelessWidget {
  const _AvailabilityNote({required this.availability});

  final HhdTdpAvailability availability;

  @override
  Widget build(BuildContext context) {
    final (text, tone) = switch (availability) {
      HhdTdpAvailability.enabled => ('TDP 由 Handheld Daemon 管理', null),
      HhdTdpAvailability.disabled => ('TDP 管理已关闭', null),
      HhdTdpAvailability.conflict => ('TDP 被其他程序占用，相关项只读', true),
      HhdTdpAvailability.unavailable => ('此设备没有 TDP 接口', null),
    };
    if (tone == null && availability == HhdTdpAvailability.enabled) {
      return const SizedBox.shrink();
    }
    final colors = context.shellColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: (tone == true ? colors.performanceWarning : colors.tileOff)
              .withValues(alpha: 0.18),
          borderRadius: context.shellTheme.borderRadius(ShellRadii.chip),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Text(
            text,
            style: context.shellTheme.text.systemBarCaption.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Generic schema rendering
// ---------------------------------------------------------------------------

class _Section extends StatelessWidget {
  const _Section({
    required this.node,
    required this.live,
    required this.controller,
    required this.verbosity,
    required this.tdpWritable,
  });

  final HhdSettingNode node;
  final Map<String, Object?> live;
  final HhdControlController controller;
  final HhdVerbosity verbosity;
  final bool tdpWritable;

  @override
  Widget build(BuildContext context) {
    if (!verbosity.shows(node)) return const SizedBox.shrink();
    final rows = <Widget>[
      for (final child in node.children.values)
        ..._rowsFor(child, live, controller, verbosity, tdpWritable),
    ];
    if (rows.isEmpty) return const SizedBox.shrink();
    final title = node.hasTag('hide-title') || node.title.isEmpty
        ? null
        : node.title;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.only(left: 2, bottom: 6),
              child: Text(
                title,
                style: context.shellTheme.text.cardTitle.copyWith(
                  color: context.shellColors.textPrimary,
                ),
              ),
            ),
          ...rows,
        ],
      ),
    );
  }
}

List<Widget> _rowsFor(
  HhdSettingNode node,
  Map<String, Object?> live,
  HhdControlController controller,
  HhdVerbosity verbosity,
  bool tdpWritable,
) {
  if (!verbosity.shows(node)) return const <Widget>[];
  // TDP is the one subtree another program can take ownership of.
  final enabled = tdpWritable || !node.key.startsWith('tdp.');
  final value = readHhdValue(live, node.key);
  switch (node.kind) {
    case HhdSettingKind.boolean:
      return <Widget>[
        _SwitchTile(
          title: node.title,
          subtitle: node.hint.isEmpty ? null : node.hint,
          value: value == true,
          enabled: enabled,
          onChanged: (next) => controller.setValue(node.key, next),
        ),
      ];
    case HhdSettingKind.integer:
    case HhdSettingKind.number:
      if (!node.hasRange) {
        return <Widget>[
          _InfoTile(title: node.title, value: _formatValue(value, node.unit)),
        ];
      }
      final fallback = node.defaultValue;
      final current = value is num
          ? value
          : fallback is num
          ? fallback
          : node.minimum!;
      return <Widget>[
        _SliderTile(
          title: node.title,
          unit: node.unit,
          value: current.toDouble(),
          minimum: node.minimum!.toDouble(),
          maximum: node.maximum!.toDouble(),
          step: (node.step ?? 1).toDouble(),
          enabled: enabled,
          onChanged: (next) => controller.setValue(
            node.key,
            node.kind == HhdSettingKind.integer ? next.round() : next,
          ),
        ),
      ];
    case HhdSettingKind.multiple:
      return <Widget>[
        _ChoiceTile(
          title: node.title,
          options: node.options,
          value: value is String ? value : null,
          enabled: enabled,
          onChanged: (next) => controller.setValue(node.key, next),
        ),
      ];
    case HhdSettingKind.mode:
      // Only recurse into the selected mode's children; falling back to the
      // node itself would re-render the same selector forever.
      final subtree = value is String ? node.modes[value] : null;
      return <Widget>[
        _ChoiceTile(
          title: node.title,
          options: <String, String>{
            for (final mode in node.modes.entries)
              mode.key: mode.value.title.isEmpty ? mode.key : mode.value.title,
          },
          value: value is String ? value : null,
          enabled: enabled,
          onChanged: (next) => controller.setValue(node.key, next),
        ),
        if (subtree != null)
          ..._rowsFor(subtree, live, controller, verbosity, tdpWritable),
      ];
    case HhdSettingKind.action:
      return <Widget>[
        _ActionTile(
          title: node.title,
          destructive: node.hasTag('verify'),
          onInvoke: () => controller.setValue(node.key, true),
        ),
      ];
    case HhdSettingKind.display:
    case HhdSettingKind.version:
      return <Widget>[
        _InfoTile(title: node.title, value: _formatValue(value, node.unit)),
      ];
    case HhdSettingKind.custom:
      return const <Widget>[];
    case HhdSettingKind.container:
      return <Widget>[
        for (final child in node.children.values)
          ..._rowsFor(child, live, controller, verbosity, tdpWritable),
      ];
  }
}

String _formatValue(Object? value, String unit) {
  if (value == null) return '—';
  if (value is bool) return value ? '开' : '关';
  if (value is num) {
    final text = value == value.roundToDouble() ? '${value.round()}' : '$value';
    return unit.isEmpty ? text : '$text$unit';
  }
  return '$value';
}

// ---------------------------------------------------------------------------
// Rows
// ---------------------------------------------------------------------------

class _SwitchTile extends StatelessWidget {
  const _SwitchTile({
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.enabled = true,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.shellColors;
    final theme = ShellTheme.of(context);
    return Semantics(
      toggled: value,
      enabled: enabled,
      label: title,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? () => onChanged(!value) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.text.base.copyWith(
                        color: enabled
                            ? colors.textPrimary
                            : colors.textTertiary,
                      ),
                    ),
                    if (subtitle case final subtitle?)
                      Text(
                        subtitle,
                        style: theme.text.systemBarCaption.copyWith(
                          color: colors.textTertiary,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _Switch(value: value, enabled: enabled),
            ],
          ),
        ),
      ),
    );
  }
}

class _Switch extends StatelessWidget {
  const _Switch({required this.value, required this.enabled});

  final bool value;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = ShellTheme.of(context);
    final accent = theme.accentPalette;
    final track = value ? accent.primary : context.shellColors.tileOff;
    return AnimatedContainer(
      duration: Motion.pill,
      curve: Motion.standard,
      width: 42,
      height: 26,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: enabled ? track : track.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(999),
      ),
      child: AnimatedAlign(
        duration: Motion.pill,
        curve: Motion.standard,
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        child: SizedBox.square(
          dimension: 20,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: value
                  ? accent.onPrimary
                  : context.shellColors.textTertiary,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.title,
    required this.options,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final String title;
  final Map<String, String> options;
  final String? value;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty) return const SizedBox.shrink();
    final theme = ShellTheme.of(context);
    final colors = context.shellColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title.isNotEmpty)
            Text(
              title,
              style: theme.text.base.copyWith(color: colors.textSecondary),
            ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final option in options.entries)
                _ChoiceChip(
                  label: option.value,
                  selected: option.key == value,
                  enabled: enabled,
                  onTap: () => onChanged(option.key),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChoiceChip extends StatelessWidget {
  const _ChoiceChip({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ShellTheme.of(context);
    final accent = theme.accentPalette;
    final background = selected ? accent.primary : context.shellColors.tileOff;
    final foreground = selected
        ? accent.onPrimary
        : context.shellColors.panelText;
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
        child: AnimatedContainer(
          duration: Motion.pill,
          curve: Motion.standard,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: enabled ? background : background.withValues(alpha: 0.4),
            borderRadius: theme.borderRadius(ShellRadii.chip),
          ),
          child: Text(
            label,
            style: theme.text.base.copyWith(color: foreground),
          ),
        ),
      ),
    );
  }
}

class _SliderTile extends StatefulWidget {
  const _SliderTile({
    required this.title,
    required this.value,
    required this.minimum,
    required this.maximum,
    required this.step,
    required this.onChanged,
    this.unit = '',
    this.enabled = true,
  });

  final String title;
  final String unit;
  final double value;
  final double minimum;
  final double maximum;
  final double step;
  final bool enabled;
  final ValueChanged<double> onChanged;

  @override
  State<_SliderTile> createState() => _SliderTileState();
}

class _SliderTileState extends State<_SliderTile> {
  double? _dragValue;

  double get _span {
    final span = widget.maximum - widget.minimum;
    return span <= 0 ? 1 : span;
  }

  double get _displayValue =>
      (_dragValue ?? widget.value).clamp(widget.minimum, widget.maximum);

  @override
  void didUpdateWidget(covariant _SliderTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The authoritative value arrived; stop showing the local drag preview.
    if (widget.value != oldWidget.value) _dragValue = null;
  }

  void _commit(double normalized) {
    final raw = widget.minimum + normalized * _span;
    final stepped = widget.step <= 0
        ? raw
        : (raw / widget.step).round() * widget.step;
    widget.onChanged(stepped.clamp(widget.minimum, widget.maximum));
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShellTheme.of(context);
    final colors = context.shellColors;
    final normalized = ((_displayValue - widget.minimum) / _span).clamp(
      0.0,
      1.0,
    );
    final shown = _displayValue;
    final label = shown == shown.roundToDouble()
        ? '${shown.round()}'
        : shown.toStringAsFixed(1);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.title,
                  style: theme.text.base.copyWith(color: colors.textSecondary),
                ),
              ),
              Text(
                widget.unit.isEmpty ? label : '$label${widget.unit}',
                style: theme.text.systemBarValue.copyWith(
                  color: widget.enabled
                      ? colors.textPrimary
                      : colors.textTertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Opacity(
            opacity: widget.enabled ? 1 : 0.4,
            child: IgnorePointer(
              ignoring: !widget.enabled,
              child: RangeBar(
                value: normalized,
                activeColor: theme.accent,
                inactiveColor: colors.tileOff,
                height: 30,
                onChanged: (next) =>
                    setState(() => _dragValue = widget.minimum + next * _span),
                onChangeEnd: _commit,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = ShellTheme.of(context);
    final colors = context.shellColors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title.isNotEmpty)
            Expanded(
              child: Text(
                title,
                style: theme.text.base.copyWith(color: colors.textSecondary),
              ),
            )
          else
            const Spacer(),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: theme.text.base.copyWith(color: colors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatefulWidget {
  const _ActionTile({
    required this.title,
    required this.onInvoke,
    this.destructive = false,
  });

  final String title;
  final bool destructive;
  final VoidCallback onInvoke;

  @override
  State<_ActionTile> createState() => _ActionTileState();
}

class _ActionTileState extends State<_ActionTile> {
  /// Destructive actions confirm inline; the shell has no Material navigator.
  bool _confirming = false;

  void _activate() {
    if (!widget.destructive) {
      widget.onInvoke();
      return;
    }
    setState(() => _confirming = true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShellTheme.of(context);
    if (!_confirming) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Align(
          alignment: Alignment.centerLeft,
          child: _PillButton(label: widget.title, onTap: _activate),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${widget.title}：确定继续吗？',
            style: theme.text.base.copyWith(
              color: context.shellColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _PillButton(
                label: '取消',
                onTap: () => setState(() => _confirming = false),
              ),
              const SizedBox(width: 8),
              _PillButton(
                label: '继续',
                onTap: () {
                  setState(() => _confirming = false);
                  widget.onInvoke();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
