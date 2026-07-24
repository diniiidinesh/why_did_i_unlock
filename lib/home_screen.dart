import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

import 'about_screen.dart';
import 'app_settings.dart';
import 'beacon_theme.dart';
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
///
/// Insight / settings / permission data is loaded in [initState] and again
/// whenever the app resumes (`WidgetsBindingObserver`) or the user
/// pull-to-refreshes / returns from a pushed route — otherwise a long-lived
/// Home `State` would keep the first snapshot forever (same "fetched once,
/// never re-fetched" shape as `docs/ARCHITECTURE.md` §8.1, on the main UI
/// engine rather than the overlay).
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

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
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
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Unlock writes land in the background engine while this UI State stays
    // mounted. Resume is the signal that fresh insight rows may exist —
    // same reason OnboardingScreen re-checks permission on resume.
    if (state == AppLifecycleState.resumed) {
      _refreshVisible();
    }
  }

  /// Re-reads permission, settings snapshot, and insight queries without
  /// reopening the store. Used by pull-to-refresh, app resume, and return
  /// from a pushed route.
  Future<void> _refreshVisible() async {
    if (!mounted || _store == null) return;
    try {
      final results = await (
        widget.checkPermission(),
        widget.settings.loadSnapshot(),
      ).wait;
      if (!mounted) return;
      setState(() {
        _permissionGranted = results.$1;
        _settingsSnapshot = results.$2;
      });
      await _loadInsights();
    } catch (_) {
      if (mounted) setState(() => _loadFailed = true);
    }
  }

  Future<void> _openRoute(WidgetBuilder builder) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: builder));
    // Settings / Status / History / Manage can change prefs, permission, or
    // (via delete-all) the underlying logs — refresh when we become visible
    // again even if the process never left `resumed`.
    if (mounted) await _refreshVisible();
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
      // Defensive timeouts on prefs + overlay-permission plugin calls — same
      // class of "native/plugin Future never completes" failure already
      // guarded on the unlock path (`_withTimeout` in main.dart). Without
      // these, Home stays on CircularProgressIndicator forever until
      // force-stop (observed after reboot with a wedged process).
      final granted = await _awaitWithTimeout(
        'Home.checkPermission()',
        widget.checkPermission(),
      );
      final snapshot = await _awaitWithTimeout(
        'AppSettings.loadSnapshot()',
        widget.settings.loadSnapshot(),
      );
      if (granted == null || snapshot == null) {
        if (_ownsStore) await store.close();
        if (mounted) setState(() => _loadFailed = true);
        return;
      }

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

  /// Mirrors `main.dart`'s `_withTimeout` for the main-UI engine (that helper
  /// is library-private to `main.dart` and cannot be imported here).
  Future<T?> _awaitWithTimeout<T>(String label, Future<T> future) async {
    try {
      return await future.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      debugPrint('⏱️ $label timed out after 5s — failing Home load rather than risk a permanent stall');
      return null;
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
    WidgetsBinding.instance.removeObserver(this);
    if (_ownsStore) _store?.close();
    super.dispose();
  }

  List<DonutSlice> _donutSlices(List<OutcomeCount> outcomes) {
    const colors = {
      OutcomeCategory.intentDone: BeaconColors.amber,
      OutcomeCategory.intentAbandoned: Color(0xFFEF6C00),
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
    if (!snap.promptsEnabled) return 'Prompts are off';
    final cooldown = snap.cooldown.inMinutes;
    final pct = (snap.probability * 100).round();
    final quiet = snap.quietHoursEnabled ? 'Quiet hours on' : null;
    final parts = <String>[
      '$pct% of unlocks',
      if (cooldown > 0) '${cooldown}m cooldown' else 'No cooldown',
      ?quiet,
    ];
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final insightsReady = _unlockCount != null && _promptShownCount != null && _outcomes != null && _durationLoaded;
    final isEmpty = (_allTimeUnlockCount ?? 0) == 0 && !_loadFailed;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refreshVisible,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
            children: [
              const Text(
                appDisplayName,
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
                  onOpenStatus: () => _openRoute((_) => const StatusScreen()),
                ),
                const SizedBox(height: 12),
                if (isEmpty)
                  const _HomeCard(
                    child: Text(
                      'No unlocks yet. Lock and unlock your phone to start.',
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
                              return states.contains(WidgetState.selected)
                                  ? BeaconColors.onAmber
                                  : Colors.white70;
                            }),
                            backgroundColor: WidgetStateProperty.resolveWith((states) {
                              return states.contains(WidgetState.selected)
                                  ? BeaconColors.amber
                                  : Colors.white10;
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
                            '$_unlockCount unlocks · $_promptShownCount prompts',
                            style: const TextStyle(color: Colors.white70, fontSize: 15),
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
                          'Time to mark done',
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
                            '${_durationStats!.sampleCount} completed',
                            style: const TextStyle(color: Colors.white70, fontSize: 13),
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
                          onPressed: () => _openRoute((_) => const SettingsScreen()),
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
              _HomeLink(label: 'View history', onPressed: () => _openRoute((_) => const HistoryScreen())),
              _HomeLink(label: 'Manage options', onPressed: () => _openRoute((_) => const ManagePresetsScreen())),
              _HomeLink(label: 'About', onPressed: () => _openRoute((_) => const AboutScreen())),
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
      statusText = 'Checking…';
      statusColor = Colors.white54;
    } else if (granted) {
      statusText = 'Ready — overlay permission granted';
      statusColor = const Color(0xFF81C784);
    } else {
      statusText = 'Needs overlay permission';
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
  final VoidCallback onPressed;

  const _HomeLink({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 16)),
    );
  }
}
