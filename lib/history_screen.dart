import 'package:flutter/material.dart';

import 'intent_store.dart';

/// Read-only view of recent intent-log events, opened from [HomeScreen].
/// Runs in the MAIN UI ENGINE (unlike the background engine, which is the
/// sole writer — see CLAUDE.md §3): it opens its OWN connection to the same
/// on-disk DB file, safe because that file is in WAL mode (concurrent reads
/// never block or corrupt the writer). No mutation/delete — that's
/// deliberately out of scope for this first, minimal history view.
class HistoryScreen extends StatefulWidget {
  /// Injectable store-opener, so widget tests can seed an in-memory
  /// `sqflite_common_ffi` store instead of hitting the real on-device path
  /// (which needs a platform channel unavailable in a pure widget test).
  /// Defaults to null, meaning "open the real on-device store."
  final Future<IntentStore> Function()? openStore;

  const HistoryScreen({super.key, this.openStore});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  IntentStore? _store;
  List<IntentEvent>? _events;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // ownConnection: true — this runs in the main UI engine, a DIFFERENT
    // isolate from the background writer. It MUST NOT share the writer's
    // sqflite connection, or this screen's close()-on-dispose would close the
    // writer's DB too (see IntentStore.open's doc / the 2026-07-22 debug log).
    final store = await (widget.openStore?.call() ?? IntentStore.open(ownConnection: true));
    final events = await store.recentEvents();
    if (mounted) {
      setState(() {
        _store = store;
        _events = events;
      });
    } else {
      await store.close();
    }
  }

  @override
  void dispose() {
    _store?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('History'),
      ),
      body: SafeArea(
        top: false,
        child: _events == null
            ? const Center(child: CircularProgressIndicator())
            : _events!.isEmpty
                ? const Center(
                    child: Text(
                      'No unlocks logged yet',
                      style: TextStyle(color: Colors.white54),
                    ),
                  )
                : ListView.builder(
                    itemCount: _events!.length,
                    itemBuilder: (context, index) => _HistoryTile(event: _events![index]),
                  ),
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  final IntentEvent event;

  const _HistoryTile({required this.event});

  @override
  Widget build(BuildContext context) {
    final isNoIntent = event.kind == IntentKind.noIntent;
    return ListTile(
      title: Text(
        event.text,
        style: TextStyle(
          color: isNoIntent ? Colors.white54 : Colors.white,
          fontStyle: isNoIntent ? FontStyle.italic : FontStyle.normal,
        ),
      ),
      subtitle: Text(
        _subtitle(event),
        style: const TextStyle(color: Colors.white38, fontSize: 12),
      ),
    );
  }

  String _subtitle(IntentEvent event) {
    final sourceLabel = switch (event.source) {
      IntentSource.preset => 'preset',
      IntentSource.custom => 'custom',
      null => 'no intent',
    };
    return '$sourceLabel · ${_relativeTime(event.completedAt)}';
  }

  String _relativeTime(DateTime dt) {
    final diff = DateTime.now().toUtc().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
