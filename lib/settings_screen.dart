import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'about_screen.dart' show privacyPolicyUrl;
import 'app_settings.dart';
import 'export_csv.dart';
import 'intent_store.dart';
import 'manage_presets_screen.dart';
import 'your_data_card.dart';

/// Same typedef shape as `about_screen.dart`'s `UrlLauncher` — kept as its
/// own local declaration (rather than importing the other file's private
/// `_defaultLaunch`) so this screen has no compile-time dependency on
/// `AboutScreen` beyond the one string constant it deliberately reuses
/// (`privacyPolicyUrl`) so Settings and About share one constant.
typedef UrlLauncher = Future<bool> Function(Uri uri);

Future<bool> _defaultLaunch(Uri uri) => launchUrl(uri, mode: LaunchMode.externalApplication);

/// Fixed cooldown choices (minutes) offered as chips, plus a Custom slot for
/// anything else. Deliberately a short, curated list rather than a
/// continuous slider — see the doc comment on [_CooldownRow] for why.
const List<int> cooldownPresetMinutes = [0, 1, 5, 10, 15, 30];

/// Fixed probability choices (as whole percent) offered as chips, plus a
/// Custom slot. See [_ProbabilityRow].
const List<int> probabilityPresetPercent = [25, 50, 75, 100];

/// Settings screen: prompt on/off, cooldown, probability, quiet hours, and
/// links to Manage options / CSV export / the privacy policy.
///
/// Reachable from `HomeScreen`'s nav list since Sprint 4's Stage A merge —
/// this screen itself stays fully self-contained (no dependency on
/// `HomeScreen`), which is what let it be built and widget-tested before
/// that wiring existed. Every plugin-touching dependency is an injectable
/// constructor param defaulting to the real
/// implementation, the same pattern `StatusScreen`/`AboutScreen`/
/// `ManagePresetsScreen` already use, which is what lets this screen have a
/// widget test at all: `AppSettings` needs a fake `SharedPreferencesAsync`
/// platform instance under `flutter_test`, `url_launcher` has no real
/// platform implementation there either, and pushing the real
/// `ManagePresetsScreen` would drag `sqflite` into this suite for no reason.
///
/// Cooldown and probability are exposed as a short list of preset
/// `ChoiceChip`s plus a "Custom" slot rather than continuous sliders — see
/// the doc comments on [_CooldownRow] and [_ProbabilityRow] for why. Both
/// still go through `AppSettings`'s own clamping (defence in depth); this
/// screen additionally validates and gives feedback (a `SnackBar`) on an
/// out-of-range Custom entry, rather than letting a user type 999 and see
/// it silently succeed with no indication anything was adjusted.
///
/// CSV export / Your data live here; prefs and event counts are re-read on
/// app resume via [WidgetsBindingObserver] so a long-lived Settings route
/// does not keep a stale `initState` snapshot (`docs/ARCHITECTURE.md` §8.1).
class SettingsScreen extends StatefulWidget {
  final AppSettings settings;
  final UrlLauncher launch;
  final WidgetBuilder? managePresetsBuilder;
  final Future<void> Function()? exportAndShare;
  final Future<IntentStore> Function()? openStore;

  const SettingsScreen({
    super.key,
    this.settings = const AppSettings(),
    UrlLauncher? launch,
    this.managePresetsBuilder,
    this.exportAndShare,
    this.openStore,
  }) : launch = launch ?? _defaultLaunch;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with WidgetsBindingObserver {
  /// Null while the first load is in flight, mirroring the other Sprint 4
  /// screens' null-vs-loaded pattern.
  bool? _promptsEnabled;
  int? _cooldownMinutes;
  double? _probability;
  bool? _quietHoursEnabled;
  QuietHoursWindow? _quietHoursWindow;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Prefs can change from another isolate / future surface; resume is the
    // cheap invalidation signal (docs/ARCHITECTURE.md §8.1). In-screen edits
    // already update local state via setState — this covers returning from
    // background after an update or an external write.
    if (state == AppLifecycleState.resumed) {
      _load();
    }
  }

  Future<void> _load() async {
    final results = await (
      widget.settings.promptsEnabled(),
      widget.settings.cooldownMinutes(),
      widget.settings.promptProbability(),
      widget.settings.quietHoursEnabled(),
      widget.settings.quietHoursWindow(),
    ).wait;
    if (!mounted) return;
    setState(() {
      _promptsEnabled = results.$1;
      _cooldownMinutes = results.$2;
      _probability = results.$3;
      _quietHoursEnabled = results.$4;
      _quietHoursWindow = results.$5;
    });
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _setPromptsEnabled(bool value) async {
    setState(() => _promptsEnabled = value);
    await widget.settings.setPromptsEnabled(value);
  }

  /// Writes a cooldown value that's already known to be in range (a preset
  /// chip tap), so no clamp-and-warn feedback is needed here — only the
  /// Custom entry path can produce an out-of-range value.
  Future<void> _setCooldownMinutes(int minutes) async {
    setState(() => _cooldownMinutes = minutes);
    await widget.settings.setCooldownMinutes(minutes);
  }

  /// Validates a typed Custom cooldown value: clamps to
  /// `[cooldownMinMinutes, cooldownMaxMinutes]`, tells the user when that
  /// happened, and always persists the clamped value — never the raw
  /// out-of-range input, and never a silent no-op on invalid text.
  Future<void> _submitCustomCooldown(String text) async {
    final parsed = int.tryParse(text.trim());
    if (parsed == null) {
      _showSnackBar('Enter a whole number of minutes.');
      return;
    }
    final clamped = parsed.clamp(AppSettings.cooldownMinMinutes, AppSettings.cooldownMaxMinutes);
    if (clamped != parsed) {
      _showSnackBar(
        'Cooldown must be ${AppSettings.cooldownMinMinutes}–${AppSettings.cooldownMaxMinutes} minutes.',
      );
    }
    await _setCooldownMinutes(clamped);
  }

  /// See [_setCooldownMinutes] — same "already validated" contract for
  /// preset percentage chips.
  Future<void> _setProbabilityPercent(int percent) async {
    final probability = percent / 100.0;
    setState(() => _probability = probability);
    await widget.settings.setPromptProbability(probability);
  }

  /// See [_submitCustomCooldown] — same clamp-and-warn contract, in percent
  /// terms (`AppSettings.probabilityMin/Max` are 0.0–1.0 fractions, so this
  /// converts to the 25–100 UI scale before comparing).
  Future<void> _submitCustomProbability(String text) async {
    final parsed = int.tryParse(text.trim());
    if (parsed == null) {
      _showSnackBar('Enter a whole percentage.');
      return;
    }
    final minPercent = (AppSettings.probabilityMin * 100).round();
    final maxPercent = (AppSettings.probabilityMax * 100).round();
    final clamped = parsed.clamp(minPercent, maxPercent);
    if (clamped != parsed) {
      _showSnackBar('Probability must be $minPercent–$maxPercent%.');
    }
    await _setProbabilityPercent(clamped);
  }

  Future<void> _setQuietHoursEnabled(bool value) async {
    setState(() => _quietHoursEnabled = value);
    await widget.settings.setQuietHoursEnabled(value);
  }

  Future<void> _pickQuietHoursTime({required bool isStart}) async {
    final window = _quietHoursWindow;
    if (window == null) return;
    final initial = _minutesToTimeOfDay(isStart ? window.startMinutes : window.endMinutes);
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null) return;
    final minutes = _timeOfDayToMinutes(picked);
    final updated = QuietHoursWindow(
      startMinutes: isStart ? minutes : window.startMinutes,
      endMinutes: isStart ? window.endMinutes : minutes,
    );
    setState(() => _quietHoursWindow = updated);
    await widget.settings.setQuietHoursWindow(updated);
  }

  static TimeOfDay _minutesToTimeOfDay(int minutes) => TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);

  static int _timeOfDayToMinutes(TimeOfDay time) => time.hour * 60 + time.minute;

  static String _formatMinutes(int minutes) {
    final time = _minutesToTimeOfDay(minutes);
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  Future<void> _openManagePresets() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: widget.managePresetsBuilder ?? (_) => const ManagePresetsScreen(),
      ),
    );
  }

  Future<void> _openPrivacyPolicy() async {
    bool ok;
    try {
      ok = await widget.launch(Uri.parse(privacyPolicyUrl));
    } catch (_) {
      // Placeholder host today — expected until the naming/policy [P1]
      // decision lands (CLAUDE.md §12), not a crash. Same non-fatal
      // treatment as AboutScreen's outbound links.
      ok = false;
    }
    if (!ok) _showSnackBar('Privacy policy isn\'t published yet.');
  }

  @override
  Widget build(BuildContext context) {
    final promptsEnabled = _promptsEnabled;
    final cooldownMinutes = _cooldownMinutes;
    final probability = _probability;
    final quietHoursEnabled = _quietHoursEnabled;
    final quietHoursWindow = _quietHoursWindow;

    final loaded = promptsEnabled != null &&
        cooldownMinutes != null &&
        probability != null &&
        quietHoursEnabled != null &&
        quietHoursWindow != null;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Settings'),
      ),
      body: SafeArea(
        top: false,
        child: !loaded
            ? const Center(child: CircularProgressIndicator())
            : ListView(
              children: [
                const _SectionHeader('Prompts'),
                SwitchListTile(
                  title: const Text('Prompt on unlock', style: TextStyle(color: Colors.white)),
                  subtitle: const Text(
                    'Turn off to stop the "What are you unlocking for?" prompt entirely.',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  value: promptsEnabled,
                  onChanged: _setPromptsEnabled,
                ),
                const _SectionDivider(),
                const _SectionHeader(
                  'Cooldown',
                  subtitle:
                      'Minimum gap after a prompt before the next one. Default '
                      '1 min stops rapid lock/unlock from asking twice. Set to '
                      '0 for no gap.',
                ),
                _CooldownRow(
                  minutes: cooldownMinutes,
                  onPresetSelected: _setCooldownMinutes,
                  onCustomSubmitted: _submitCustomCooldown,
                ),
                const _SectionDivider(),
                const _SectionHeader(
                  'Prompt probability',
                  subtitle:
                      'Chance of being asked once cooldown has cleared. '
                      'Default 100% = every unlock. Lower it if prompts feel '
                      'too frequent.',
                ),
                _ProbabilityRow(
                  probability: probability,
                  onPresetSelected: _setProbabilityPercent,
                  onCustomSubmitted: _submitCustomProbability,
                ),
                const _SectionDivider(),
                const _SectionHeader('Quiet hours'),
                SwitchListTile(
                  title: const Text('Suppress prompts', style: TextStyle(color: Colors.white)),
                  value: quietHoursEnabled,
                  onChanged: _setQuietHoursEnabled,
                ),
                ListTile(
                  textColor: Colors.white,
                  title: const Text('Start'),
                  trailing: Text(
                    _formatMinutes(quietHoursWindow.startMinutes),
                    style: const TextStyle(color: Colors.white70),
                  ),
                  onTap: () => _pickQuietHoursTime(isStart: true),
                ),
                ListTile(
                  textColor: Colors.white,
                  title: const Text('End'),
                  trailing: Text(
                    _formatMinutes(quietHoursWindow.endMinutes),
                    style: const TextStyle(color: Colors.white70),
                  ),
                  onTap: () => _pickQuietHoursTime(isStart: false),
                ),
                const _SectionDivider(),
                ListTile(
                  iconColor: Colors.white70,
                  textColor: Colors.white,
                  leading: const Icon(Icons.tune),
                  title: const Text('Manage options'),
                  trailing: const Icon(Icons.chevron_right, color: Colors.white38),
                  onTap: _openManagePresets,
                ),
                const _SectionDivider(),
                YourDataCard(
                  settings: widget.settings,
                  openStore: widget.openStore,
                  exportAndShare: widget.exportAndShare ?? exportAndShareCsv,
                  showSnackBar: _showSnackBar,
                ),
                const _SectionDivider(),
                ListTile(
                  iconColor: Colors.white70,
                  textColor: Colors.white,
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: const Text('Privacy policy'),
                  onTap: _openPrivacyPolicy,
                ),
                const SizedBox(height: 24),
              ],
            ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  final String? subtitle;
  const _SectionHeader(this.text, {this.subtitle});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(text, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(subtitle!, style: const TextStyle(color: Colors.white54, fontSize: 12, height: 1.35)),
            ],
          ],
        ),
      );
}

class _SectionDivider extends StatelessWidget {
  const _SectionDivider();

  @override
  Widget build(BuildContext context) => const Divider(color: Colors.white12, height: 1);
}

/// Cooldown is offered as a short list of preset `ChoiceChip`s
/// ([cooldownPresetMinutes]) plus a "Custom" slot, not a slider. Cooldown
/// only has a handful of genuinely useful values, and continuous dragging
/// doesn't add anything a curated list doesn't already cover; sensible
/// defaults behind a simple picker matches the product stance that triage
/// customization is not this app's differentiator (`CLAUDE.md` §3). Typing
/// a value outside `AppSettings.cooldownMinMinutes..cooldownMaxMinutes`
/// into Custom is still fully supported, but is validated (see
/// `_submitCustomCooldown`) rather than silently clamped with no feedback.
class _CooldownRow extends StatefulWidget {
  final int minutes;
  final ValueChanged<int> onPresetSelected;
  final ValueChanged<String> onCustomSubmitted;

  const _CooldownRow({
    required this.minutes,
    required this.onPresetSelected,
    required this.onCustomSubmitted,
  });

  @override
  State<_CooldownRow> createState() => _CooldownRowState();
}

class _CooldownRowState extends State<_CooldownRow> {
  late final TextEditingController _controller;
  late bool _isCustom;

  @override
  void initState() {
    super.initState();
    _isCustom = !cooldownPresetMinutes.contains(widget.minutes);
    _controller = TextEditingController(text: widget.minutes.toString());
  }

  @override
  void didUpdateWidget(covariant _CooldownRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.minutes != widget.minutes) {
      _isCustom = !cooldownPresetMinutes.contains(widget.minutes);
      _controller.text = widget.minutes.toString();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final preset in cooldownPresetMinutes)
                ChoiceChip(
                  label: Text('$preset min'),
                  selected: !_isCustom && widget.minutes == preset,
                  onSelected: (_) {
                    setState(() {
                      _isCustom = false;
                      _controller.text = preset.toString();
                    });
                    widget.onPresetSelected(preset);
                  },
                ),
              ChoiceChip(
                label: const Text('Custom'),
                selected: _isCustom,
                onSelected: (_) => setState(() => _isCustom = true),
              ),
            ],
          ),
          if (_isCustom) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(suffixText: 'min'),
              onSubmitted: widget.onCustomSubmitted,
              onEditingComplete: () => widget.onCustomSubmitted(_controller.text),
            ),
          ],
        ],
      ),
    );
  }
}

/// Same rationale as [_CooldownRow], for [probabilityPresetPercent].
class _ProbabilityRow extends StatefulWidget {
  final double probability;
  final ValueChanged<int> onPresetSelected;
  final ValueChanged<String> onCustomSubmitted;

  const _ProbabilityRow({
    required this.probability,
    required this.onPresetSelected,
    required this.onCustomSubmitted,
  });

  @override
  State<_ProbabilityRow> createState() => _ProbabilityRowState();
}

class _ProbabilityRowState extends State<_ProbabilityRow> {
  late final TextEditingController _controller;
  late bool _isCustom;

  int get _percent => (widget.probability * 100).round();

  @override
  void initState() {
    super.initState();
    _isCustom = !probabilityPresetPercent.contains(_percent);
    _controller = TextEditingController(text: _percent.toString());
  }

  @override
  void didUpdateWidget(covariant _ProbabilityRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.probability != widget.probability) {
      _isCustom = !probabilityPresetPercent.contains(_percent);
      _controller.text = _percent.toString();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final percent = _percent;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final preset in probabilityPresetPercent)
                ChoiceChip(
                  label: Text('$preset%'),
                  selected: !_isCustom && percent == preset,
                  onSelected: (_) {
                    setState(() {
                      _isCustom = false;
                      _controller.text = preset.toString();
                    });
                    widget.onPresetSelected(preset);
                  },
                ),
              ChoiceChip(
                label: const Text('Custom'),
                selected: _isCustom,
                onSelected: (_) => setState(() => _isCustom = true),
              ),
            ],
          ),
          if (_isCustom) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(suffixText: '%'),
              onSubmitted: widget.onCustomSubmitted,
              onEditingComplete: () => widget.onCustomSubmitted(_controller.text),
            ),
          ],
        ],
      ),
    );
  }
}
