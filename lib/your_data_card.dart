import 'package:flutter/material.dart';

import 'app_settings.dart';
import 'intent_store.dart';

/// Settings "Your data" section (T18 / docs/DATA_MODEL.md §8): event counts,
/// oldest record, retention chips, export, delete-all, and one-shot prune.
///
/// Presets are kept on wipe/prune — they are configuration, not event history.
class YourDataCard extends StatefulWidget {
  final AppSettings settings;
  final Future<IntentStore> Function()? openStore;
  final Future<void> Function() exportAndShare;
  final void Function(String message) showSnackBar;

  const YourDataCard({
    super.key,
    required this.settings,
    this.openStore,
    required this.exportAndShare,
    required this.showSnackBar,
  });

  @override
  State<YourDataCard> createState() => _YourDataCardState();
}

class _YourDataCardState extends State<YourDataCard> {
  IntentStore? _store;
  /// True when this card opened the default on-device store. Injected
  /// [YourDataCard.openStore] stays owned by the caller (tests).
  bool _ownsStore = false;
  UserDataCounts? _counts;
  DateTime? _oldest;
  RetentionPeriod? _retention;
  bool _busy = false;

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
        store.userDataCounts(),
        store.oldestRecordAt(),
        widget.settings.retentionPeriod(),
      ).wait;
      if (!mounted) {
        if (_ownsStore) await store.close();
        return;
      }
      setState(() {
        _store = store;
        _counts = results.$1;
        _oldest = results.$2;
        _retention = results.$3;
      });
    } catch (_) {
      if (mounted) widget.showSnackBar('Couldn\'t load Your data.');
    }
  }

  Future<void> _refreshCounts() async {
    final store = _store;
    if (store == null) return;
    final counts = await store.userDataCounts();
    final oldest = await store.oldestRecordAt();
    if (!mounted) return;
    setState(() {
      _counts = counts;
      _oldest = oldest;
    });
  }

  @override
  void dispose() {
    if (_ownsStore) _store?.close();
    super.dispose();
  }

  Future<void> _setRetention(RetentionPeriod period) async {
    setState(() => _retention = period);
    await widget.settings.setRetentionPeriod(period);
  }

  Future<void> _export() async {
    try {
      await widget.exportAndShare();
    } catch (_) {
      widget.showSnackBar('Export failed. Please try again.');
    }
  }

  Future<void> _confirmDeleteAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Delete all event history?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'This removes every unlock and intent log. Your Manage options (presets) stay. This can\'t be undone.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete all', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed != true || _store == null) return;
    setState(() => _busy = true);
    try {
      await _store!.deleteAllUserData();
      await _refreshCounts();
      widget.showSnackBar('All unlock and intent history deleted.');
    } catch (_) {
      widget.showSnackBar('Delete failed. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmPrune() async {
    final choice = await showDialog<_PruneChoice>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Delete older than…', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Remove unlock and intent rows older than the period you pick. Presets are kept.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, _PruneChoice.ninetyDays),
            child: const Text('90 days'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, _PruneChoice.oneYear),
            child: const Text('365 days'),
          ),
        ],
      ),
    );
    if (choice == null || _store == null || !mounted) return;

    final cutoff = DateTime.now().toUtc().subtract(
      choice == _PruneChoice.ninetyDays ? const Duration(days: 90) : const Duration(days: 365),
    );

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Confirm delete', style: TextStyle(color: Colors.white)),
        content: Text(
          'Delete events older than ${choice == _PruneChoice.ninetyDays ? '90' : '365'} days?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      final deleted = await _store!.pruneOlderThan(cutoff);
      await _refreshCounts();
      widget.showSnackBar(deleted == 0 ? 'Nothing older than that.' : 'Deleted $deleted events.');
    } catch (_) {
      widget.showSnackBar('Delete failed. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _oldestLabel() {
    final oldest = _oldest;
    if (oldest == null) return 'No events stored yet';
    final local = oldest.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    return 'Oldest record: $y-$m-$d';
  }

  String _countsLabel() {
    final counts = _counts;
    if (counts == null) return 'Loading…';
    return '${counts.unlockCount} unlocks · ${counts.intentCount} intents';
  }

  @override
  Widget build(BuildContext context) {
    final retention = _retention;
    final loaded = retention != null && _counts != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _YourDataSectionHeader('Your data'),
        if (!loaded)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          )
        else ...[
          ListTile(
            textColor: Colors.white,
            title: const Text('Events stored'),
            subtitle: Text(_countsLabel(), style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ),
          ListTile(
            textColor: Colors.white,
            title: Text(_oldestLabel()),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text('Keep history for', style: TextStyle(color: Colors.white70, fontSize: 13)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(
              spacing: 8,
              children: [
                for (final period in RetentionPeriod.values)
                  ChoiceChip(
                    label: Text(_retentionLabel(period)),
                    selected: retention == period,
                    onSelected: _busy
                        ? null
                        : (selected) {
                            if (selected) _setRetention(period);
                          },
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          ListTile(
            enabled: !_busy,
            iconColor: Colors.white70,
            textColor: Colors.white,
            leading: const Icon(Icons.ios_share),
            title: const Text('Export data'),
            subtitle: const Text(
              'One CSV of every unlock, then any orphan intents. Shared via your phone\'s share sheet.',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
            onTap: _busy ? null : _export,
          ),
          ListTile(
            enabled: !_busy,
            iconColor: Colors.white70,
            textColor: Colors.white,
            leading: const Icon(Icons.delete_outline),
            title: const Text('Delete all event history'),
            subtitle: const Text(
              'Unlocks and intents only — presets stay.',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
            onTap: _busy ? null : _confirmDeleteAll,
          ),
          ListTile(
            enabled: !_busy,
            iconColor: Colors.white70,
            textColor: Colors.white,
            leading: const Icon(Icons.history),
            title: const Text('Delete older than…'),
            subtitle: const Text(
              'One-shot prune; doesn\'t wait for automatic retention.',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
            onTap: _busy ? null : _confirmPrune,
          ),
        ],
      ],
    );
  }

  static String _retentionLabel(RetentionPeriod period) {
    switch (period) {
      case RetentionPeriod.ninetyDays:
        return '90 days';
      case RetentionPeriod.oneYear:
        return '365 days';
      case RetentionPeriod.forever:
        return 'Forever';
    }
  }
}

enum _PruneChoice { ninetyDays, oneYear }

class _YourDataSectionHeader extends StatelessWidget {
  final String text;
  const _YourDataSectionHeader(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
      );
}
