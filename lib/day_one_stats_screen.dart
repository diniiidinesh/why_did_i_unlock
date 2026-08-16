import 'package:flutter/material.dart';

import 'beacon_theme.dart';
import 'day_one.dart';
import 'intent_store.dart';

/// Destination for the day-1 recap (`§4C.5` / `§4D`). Comfort-copy, then
/// real counts from existing [IntentStore] queries. Opens from
/// [AppLauncher] after 24h (icon open **or** shade-reminder tap),
/// or from About's hidden long-press debug.
class DayOneStatsScreen extends StatefulWidget {
  final Future<IntentStore> Function()? openStore;
  final VoidCallback? onFinished;

  const DayOneStatsScreen({super.key, this.openStore, this.onFinished});

  @override
  State<DayOneStatsScreen> createState() => _DayOneStatsScreenState();
}

class _DayOneStatsScreenState extends State<DayOneStatsScreen> {
  IntentStore? _store;
  DayOneStats? _stats;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    IntentStore? store;
    try {
      store = await (widget.openStore?.call() ?? IntentStore.open(ownConnection: true));
      final stats = await DayOneStats.load(store);
      if (!mounted) {
        await store.close();
        return;
      }
      setState(() {
        _store = store;
        _stats = stats;
      });
    } catch (_) {
      if (store != null && _store == null) await store.close();
      if (mounted) setState(() => _stats = DayOneStats.empty);
    }
  }

  @override
  void dispose() {
    _store?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stats = _stats;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Your first day'),
      ),
      body: SafeArea(
        top: false,
        child: stats == null
            ? const Center(child: CircularProgressIndicator())
            : Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'A look at how you used your phone.',
                      style: TextStyle(color: Colors.white70, fontSize: 16, height: 1.35),
                    ),
                    const SizedBox(height: 28),
                    _StatRow(label: 'Unlocks', value: '${stats.unlockCount}'),
                    _StatRow(label: 'Intents declared', value: '${stats.intentsDeclared}'),
                    _StatRow(label: 'Just Like That', value: '${stats.purposelessCount}'),
                    _StatRow(
                      label: 'Most common reason',
                      value: stats.mostCommonReason ?? 'None yet',
                    ),
                    const Spacer(),
                    ElevatedButton(
                      onPressed: widget.onFinished ?? () => Navigator.of(context).maybePop(),
                      child: const Text('Continue'),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final String value;

  const _StatRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 15)),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(
                color: BeaconColors.amber,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
