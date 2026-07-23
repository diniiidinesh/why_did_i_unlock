import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

import 'about_screen.dart';
import 'app_settings.dart';
import 'history_screen.dart';
import 'insights/outcome_donut.dart';
import 'intent_store.dart';
import 'manage_presets_screen.dart';
import 'settings_screen.dart';
import 'status_screen.dart';

/// Home: "is it working?" first, then today's story (counts / donut / timing),
/// then links into Settings / History / Manage / Status / About.
///
/// Extracted from `main.dart` so insight loading stays testable without
/// dragging the three-engine entrypoints into every widget test. Every
/// plugin-touching dependency is injectable — same pattern as
/// [HistoryScreen] / [StatusScreen] / [SettingsScreen].
class HomeScreen extends StatefulWidget {
  final Future<IntentStore> Function()? openStore;
  final AppSettings settings;
  final Future<bool> Function() checkPermission;

  const HomeScreen({
    super.key,
    this.openStore,
    this.settings = const AppSettings(),
    Future<bool> Function()? checkPermission,
  }) : checkPermission = checkPermission ?? FlutterOverlayWindow.isPermissionGranted;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  IntentStore? _store;
  /// True only when this State opened the default on-device store — injected
  /// [HomeScreen.openStore] remains owned by the caller (widget tests).
  bool _ownsStore = false;
  bool? _permissionGranted;
  InsightWindow _window = InsightWindow.today;
  int? _unlockCount;
  int? _promptShownCount;
  int? _allTimeUnlockCount;
  List<OutcomeCount>? _outcomes;
  DurationStats? _durationStats;
  bool _durationLoaded = false;
  AppSettingsSnapshot? _settingsSnapshot;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final IntentStore store;
      if (widget.openStore != null) {
        store = await widget.openStore!();
        _ownsStore = false;
      } else {
        store = await IntentStore.open(ownConnection: true);
        _ownsStore = true;
      }
      final results = await (
        widget.checkPermission(),
        widget.settings.loadSnapshot(),
      ).wait;
      final granted = results.$1;
      final snapshot = results.$2;

      if (!mounted) {
        if (_ownsStore) await store.close();
        return;
      }

      setState(() {
        _store = store;
        _permissionGranted = granted;
        _settingsSnapshot = snapshot;
        _loadFailed = false;
      });
      await _loadInsights();
    } catch (_) {
      if (mounted) setState(() => _loadFailed = true);
    }
  }

  Future<void> _loadInsights() async {
    final store = _store;
    if (store == null) return;
    final now = DateTime.now();
    try {
      final results = await (
        store.unlockCount(window: _window, now: now),
        store.promptShownCount(window: _window, now: now),
        store.outcomeBreakdown(window: _window, now: now),
        store.completionDurationStats(window: _window, now: now),
        store.userDataCounts(),
      ).wait;
      if (!mounted) return;
      setState(() {
        _unlockCount = results.$1;
        _promptShownCount = results.$2;
        _outcomes = results.$3;
        _durationStats = results.$4;
        _durationLoaded = true;
        _allTimeUnlockCount = results.$5.unlockCount;
        _loadFailed = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadFailed = true);
    }
  }

  Future<void> _setWindow(InsightWindow window) async {
    if (window == _window) return;
    setState(() {
      _window = window;
      _unlockCount = null;
      _promptShownCount = null;
      _outcomes = null;
      _durationStats = null;
      _durationLoaded = false;
    });
    await _loadInsights();
  }

  @override
  void dispose() {
    if (_ownsStore) _store?.close();
    super.dispose();
  }

  List<DonutSlice> _donutSlices(List<OutcomeCount> outcomes) {
    const colors = {
      OutcomeCategory.intentDone: Color(0xFF4CAF50),
      OutcomeCategory.intentAbandoned: Color(0xFFFF9800),
      OutcomeCategory.noIntent: Color(0xFF9E9E9E),
    };
    const labels = {
      OutcomeCategory.intentDone: 'Done',
      OutcomeCategory.intentAbandoned: 'Abandoned',
      OutcomeCategory.noIntent: 'No intent',
    };
    // Stable order so the ring + legend don't reshuffle when a bucket is zero.
    return OutcomeCategory.values.map((category) {
      final match = outcomes.where((o) => o.category == category);
      final count = match.isEmpty ? 0 : match.fold<int>(0, (sum, o) => sum + o.count);
      return DonutSlice(
        label: labels[category]!,
        value: count.toDouble(),
        color: colors[category]!,
      );
    }).toList();
  }

  String _windowLabel(InsightWindow window) {
    switch (window) {
      case InsightWindow.today:
        return 'Today';
      case InsightWindow.last7Days:
        return '7 days';
      case InsightWindow.last30Days:
        return '30 days';
    }
  }

  String _formatDuration(double seconds) {
    if (seconds < 60) return '${seconds.round()}s';
    final minutes = seconds / 60;
    if (minutes < 60) return '${minutes.toStringAsFixed(minutes < 10 ? 1 : 0)}m';
    final hours = minutes / 60;
    return '${hours.toStringAsFixed(1)}h';
  }

  String _settingsSummary(AppSettingsSnapshot snap) {
    final cooldown = snap.cooldown.inMinutes;
    final pct = (snap.probability * 100).round();
    final quiet = snap.quietHoursEnabled ? 'quiet hours on' : 'quiet hours off';
    final prompts = snap.promptsEnabled ? 'prompts on' : 'prompts off';
    return '$prompts · ${cooldown}m cooldown · $pct% · $quiet';
  }

  @override
  Widget build(BuildContext context) {
    final insightsReady = _unlockCount != null && _promptShownCount != null && _outcomes != null && _durationLoaded;
    final isEmpty = (_allTimeUnlockCount ?? 0) == 0 && !_loadFailed;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            await _loadInsights();
            final granted = await widget.checkPermission();
            final snapshot = await widget.settings.loadSnapshot();
            if (mounted) {
              setState(() {
                _permissionGranted = granted;
                _settingsSnapshot = snapshot;
              });
            }
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
            children: [
              const Text(
                'Why Did I Unlock?',
                style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 20),
              if (_loadFailed)
                const _HomeCard(
                  child: Text(
                    'Couldn\'t load local data. Pull to retry.',
                    style: TextStyle(color: Colors.white70),
                  ),
                )
              else if (!insightsReady && _store == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else ...[
                _StatusCard(
                  permissionGranted: _permissionGranted,
                  onOpenStatus: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const StatusScreen()),
                    );
                  },
                ),
                const SizedBox(height: 12),
                if (isEmpty)
                  const _HomeCard(
                    child: Text(
                      'No unlocks logged yet. Once the overlay is watching, '
                      'today\'s counts and breakdown will show up here.',
                      style: TextStyle(color: Colors.white70, height: 1.35),
                    ),
                  )
                else ...[
                  _HomeCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _windowLabel(_window),
                          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        SegmentedButton<InsightWindow>(
                          segments: const [
                            ButtonSegment(value: InsightWindow.today, label: Text('Today')),
                            ButtonSegment(value: InsightWindow.last7Days, label: Text('7d')),
                            ButtonSegment(value: InsightWindow.last30Days, label: Text('30d')),
                          ],
                          selected: {_window},
                          onSelectionChanged: (next) {
                            if (next.isNotEmpty) _setWindow(next.first);
                          },
                          style: ButtonStyle(
                            foregroundColor: WidgetStateProperty.resolveWith((states) {
                              return states.contains(WidgetState.selected) ? Colors.black : Colors.white70;
                            }),
                            backgroundColor: WidgetStateProperty.resolveWith((states) {
                              return states.contains(WidgetState.selected) ? Colors.white : Colors.white10;
                            }),
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (!insightsReady)
                          const Center(child: Padding(
                            padding: EdgeInsets.all(12),
                            child: CircularProgressIndicator(),
                          ))
                        else ...[
                          Text(
                            '$_unlockCount unlocks · $_promptShownCount prompts shown',
                            style: const TextStyle(color: Colors.white70, fontSize: 15),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Unlock count is what this app observed — a floor if the service was offline.',
                            style: TextStyle(color: Colors.white38, fontSize: 12),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _HomeCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Outcomes',
                          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 12),
                        if (_outcomes == null)
                          const Center(child: CircularProgressIndicator())
                        else
                          Center(
                            child: OutcomeDonut(
                              slices: _donutSlices(_outcomes!),
                              size: 140,
                              centerLabel: _outcomes!.fold<int>(0, (s, o) => s + o.count).toString(),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _HomeCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Time to complete',
                          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        if (!_durationLoaded)
                          const Center(child: CircularProgressIndicator())
                        else if (_durationStats == null)
                          const Text(
                            'Not enough data yet',
                            style: TextStyle(color: Colors.white54),
                          )
                        else ...[
                          Text(
                            'Median ${_formatDuration(_durationStats!.medianSeconds)}',
                            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Mean ${_formatDuration(_durationStats!.meanSeconds)} · ${_durationStats!.sampleCount} sessions',
                            style: const TextStyle(color: Colors.white70, fontSize: 13),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Includes time while the screen was off — lock gaps aren\'t excluded yet.',
                            style: TextStyle(color: Colors.white38, fontSize: 12),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                _HomeCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Settings',
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _settingsSnapshot == null
                            ? 'Loading…'
                            : _settingsSummary(_settingsSnapshot!),
                        style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.35),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const SettingsScreen()),
                            );
                          },
                          child: const Text('Open Settings'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
              const Text(
                'More',
                style: TextStyle(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.w600),
              ),
              _HomeLink(label: 'Settings', screenBuilder: (_) => const SettingsScreen()),
              _HomeLink(label: 'View history', screenBuilder: (_) => const HistoryScreen()),
              _HomeLink(label: 'Manage options', screenBuilder: (_) => const ManagePresetsScreen()),
              _HomeLink(label: 'Status & troubleshooting', screenBuilder: (_) => const StatusScreen()),
              _HomeLink(label: 'About', screenBuilder: (_) => const AboutScreen()),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final bool? permissionGranted;
  final VoidCallback onOpenStatus;

  const _StatusCard({required this.permissionGranted, required this.onOpenStatus});

  @override
  Widget build(BuildContext context) {
    final granted = permissionGranted;
    final String statusText;
    final Color statusColor;
    if (granted == null) {
      statusText = 'Checking overlay permission…';
      statusColor = Colors.white54;
    } else if (granted) {
      statusText = 'Overlay permission granted — monitoring can run.';
      statusColor = const Color(0xFF81C784);
    } else {
      statusText = 'Overlay permission needed before unlock prompts can appear.';
      statusColor = const Color(0xFFFFB74D);
    }

    return _HomeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Status',
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(statusText, style: TextStyle(color: statusColor, height: 1.35)),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: onOpenStatus,
              child: const Text('Status & troubleshooting'),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeCard extends StatelessWidget {
  final Widget child;
  const _HomeCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }
}

/// One Home navigation entry — same TextButton style as the pre-T18 Home list.
class _HomeLink extends StatelessWidget {
  final String label;
  final WidgetBuilder screenBuilder;

  const _HomeLink({required this.label, required this.screenBuilder});

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () {
        Navigator.of(context).push(MaterialPageRoute(builder: screenBuilder));
      },
      child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 16)),
    );
  }
}
