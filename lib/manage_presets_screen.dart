import 'package:flutter/material.dart';

import 'intent_store.dart';

/// Reorder / rename / enable / soft-delete / restore-defaults UI for
/// `intent_preset` rows. Pattern after `HistoryScreen`: an injectable
/// [openStore] (defaults to opening the real on-device store) and its OWN
/// sqflite connection (`ownConnection: true`) since this runs in the main UI
/// engine, a different isolate from the persistent background writer — see
/// `IntentStore.open`'s doc comment and `docs/DATA_MODEL.md` §2 for why
/// sharing the writer's connection would break it.
///
/// Every mutation here goes through `IntentStore`'s own limit checks
/// (`docs/DATA_MODEL.md` §7) rather than re-implementing them — this screen
/// only has to catch [PresetLimitExceeded] and show it, never decide what
/// the limits are. That split is deliberate: two places independently
/// deciding "is this too many presets" is exactly the kind of drift that
/// produced the soft-delete-counting-toward-the-cap bug this sprint already
/// found once.
class ManagePresetsScreen extends StatefulWidget {
  final Future<IntentStore> Function()? openStore;

  const ManagePresetsScreen({super.key, this.openStore});

  @override
  State<ManagePresetsScreen> createState() => _ManagePresetsScreenState();
}

class _ManagePresetsScreenState extends State<ManagePresetsScreen> {
  IntentStore? _store;

  /// Null while the first load is in flight — distinct from an empty list,
  /// which is a real, valid state (docs/DATA_MODEL.md §7: the minimum
  /// enabled/stored preset count is deliberately zero).
  List<IntentPreset>? _presets;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final store = await (widget.openStore?.call() ?? IntentStore.open(ownConnection: true));
    if (!mounted) {
      await store.close();
      return;
    }
    _store = store;
    await _reload();
  }

  @override
  void dispose() {
    _store?.close();
    super.dispose();
  }

  /// Re-fetches from the store rather than mutating the local list in place.
  /// At ≤[maxStoredPresets] rows this query is cheap, and always reloading
  /// means the displayed list can never silently drift from what's actually
  /// stored (sort order after a reorder, ids after a restore-defaults
  /// re-seed, etc.) — correctness over a micro-optimisation here.
  Future<void> _reload() async {
    final store = _store;
    if (store == null) return;
    // allPresets() includes soft-deleted rows; this screen — like the
    // capture screen — must never show them (docs/DATA_MODEL.md §4: they
    // stay resolvable in history via preset_id, but are hidden everywhere
    // else), so filter here rather than adding a second store method that
    // duplicates activePresets()'s enabled-only filter for a slightly
    // different audience.
    final all = await store.allPresets();
    final visible = all.where((p) => !p.isDeleted).toList()..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    if (mounted) setState(() => _presets = visible);
  }

  void _showError(Object error) {
    final message = error is PresetLimitExceeded ? error.message : 'Something went wrong. Please try again.';
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _toggleEnabled(IntentPreset preset, bool enabled) async {
    try {
      await _store!.setPresetEnabled(preset.id, enabled);
      await _reload();
    } catch (e) {
      _showError(e);
      // No local state to revert — the switch's displayed value comes from
      // [_presets] via _reload(), and a failed mutation intentionally
      // leaves that untouched, so the UI just reflects reality again.
    }
  }

  Future<void> _reorder(int oldIndex, int newIndex) async {
    final presets = _presets;
    if (presets == null) return;
    final reordered = List<IntentPreset>.from(presets);
    // Using onReorderItem (not the deprecated onReorder) — its newIndex is
    // already adjusted for the removed item at oldIndex, so no manual
    // off-by-one correction is needed here.
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, moved);

    setState(() => _presets = reordered); // Optimistic — snappy drag feedback.
    try {
      await _store!.reorderPresets(reordered.map((p) => p.id).toList());
    } catch (e) {
      _showError(e);
      await _reload(); // Fall back to the store's real order on failure.
    }
  }

  Future<void> _delete(IntentPreset preset) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete preset?'),
        content: Text(
          '"${preset.label}" will be removed from the capture screen. Past history entries '
          'that used it are unaffected and keep showing what you chose at the time.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _store!.deletePreset(preset.id);
      await _reload();
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _rename(IntentPreset preset) async {
    final newLabel = await _promptForLabel(context, title: 'Rename preset', initialValue: preset.label);
    if (newLabel == null) return;
    try {
      await _store!.renamePreset(preset.id, newLabel);
      await _reload();
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _create() async {
    final label = await _promptForLabel(context, title: 'New preset', initialValue: '');
    if (label == null) return;
    try {
      await _store!.createPreset(label);
      await _reload();
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _restoreDefaults() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore default presets?'),
        content: const Text(
          'This replaces your current preset list with the original five. Your existing '
          'presets stay resolvable in history — they\'re just hidden from the capture screen '
          'and this list from now on.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Restore')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _store!.restoreDefaultPresets();
      await _reload();
    } catch (e) {
      _showError(e);
    }
  }

  Future<String?> _promptForLabel(BuildContext context, {required String title, required String initialValue}) {
    final controller = TextEditingController(text: initialValue);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          // UI-facing cap, backstopped by the store's own (looser)
          // presetLabelMaxLength check — docs/DATA_MODEL.md §7.
          maxLength: presetLabelUiMaxLength,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final presets = _presets;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Manage options'),
        actions: [
          TextButton(
            onPressed: presets == null ? null : _restoreDefaults,
            child: const Text('Restore defaults'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: presets == null ? null : _create,
        child: const Icon(Icons.add),
      ),
      body: presets == null
          ? const Center(child: CircularProgressIndicator())
          : presets.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      // A valid, intentional state (docs/DATA_MODEL.md §7) —
                      // not an error and not something to steer the user
                      // away from.
                      'No presets. The capture screen still works fine with just '
                      'the text field and "Just Like That" — add one below if you want quick-tap options back.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white54),
                    ),
                  ),
                )
              : ReorderableListView.builder(
                  itemCount: presets.length,
                  onReorderItem: _reorder,
                  // Explicit handle instead of the platform-dependent default
                  // (long-press on touch platforms, an auto-inserted handle
                  // icon on desktop) — one deterministic drag affordance
                  // everywhere, and one that a widget test can target
                  // reliably regardless of the host platform running it.
                  buildDefaultDragHandles: false,
                  itemBuilder: (context, index) {
                    final preset = presets[index];
                    return _PresetTile(
                      key: ValueKey(preset.id),
                      index: index,
                      preset: preset,
                      onToggle: (enabled) => _toggleEnabled(preset, enabled),
                      onRename: () => _rename(preset),
                      onDelete: () => _delete(preset),
                    );
                  },
                ),
    );
  }
}

class _PresetTile extends StatelessWidget {
  final int index;
  final IntentPreset preset;
  final ValueChanged<bool> onToggle;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const _PresetTile({
    super.key,
    required this.index,
    required this.preset,
    required this.onToggle,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      tileColor: Colors.white10,
      textColor: Colors.white,
      title: Text(preset.label),
      leading: Switch(value: preset.enabled, onChanged: onToggle),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(icon: const Icon(Icons.edit_outlined, color: Colors.white70), onPressed: onRename),
          IconButton(icon: const Icon(Icons.delete_outline, color: Colors.white70), onPressed: onDelete),
          ReorderableDragStartListener(
            index: index,
            child: const Icon(Icons.drag_handle, color: Colors.white38),
          ),
        ],
      ),
    );
  }
}
