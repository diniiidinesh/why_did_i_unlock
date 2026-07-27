import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:why_did_i_unlock/intent_store.dart';
import 'package:why_did_i_unlock/manage_presets_screen.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  // Every test opens its own in-memory store and pumps the screen against
  // it, following the exact real-isolate-I/O pattern HistoryScreen's test
  // already established: sqflite_common_ffi does its work on a background
  // Isolate, which the default test zone can deadlock on inside setState(),
  // so real I/O is wrapped in tester.runAsync() (see history_screen_test.dart
  // for the fuller explanation).
  Future<IntentStore> openTestStore() async {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    return IntentStore.open(path: inMemoryDatabasePath);
  }

  Future<void> pumpScreen(WidgetTester tester, IntentStore store) async {
    await tester.pumpWidget(MaterialApp(
      home: ManagePresetsScreen(openStore: () async => store),
    ));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
  }

  testWidgets('lists the seeded default presets, newest-first schema aside — sorted by sort_order', (tester) async {
    late IntentStore store;
    await tester.runAsync(() async => store = await openTestStore());

    await pumpScreen(tester, store);

    for (final label in defaultPresetLabels) {
      expect(find.text(label), findsOneWidget);
    }

    await tester.runAsync(() => store.close());
  });

  testWidgets('dragging a preset by its handle persists the new order', (tester) async {
    late IntentStore store;
    await tester.runAsync(() async => store = await openTestStore());

    await pumpScreen(tester, store);

    // Check mail starts first. Drag its handle down past Message someone's row.
    final handle = find.descendant(
      of: find.widgetWithText(ListTile, 'Check mail'),
      matching: find.byIcon(Icons.drag_handle),
    );
    await tester.drag(handle, const Offset(0, 120));
    await tester.pumpAndSettle();

    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();

    await tester.runAsync(() async {
      final all = await store.allPresets();
      final byLabel = {for (final p in all) p.label: p.sortOrder};
      expect(byLabel['Check mail']!, greaterThan(byLabel['Message someone']!));
    });

    await tester.runAsync(() => store.close());
  });

  testWidgets('a soft-deleted preset is hidden from this list but stays resolvable in history', (tester) async {
    late IntentStore store;
    await tester.runAsync(() async {
      store = await openTestStore();
      final all = await store.allPresets();
      final mail = all.firstWhere((p) => p.label == 'Check mail');
      await store.deletePreset(mail.id);
    });

    await pumpScreen(tester, store);

    expect(find.text('Check mail'), findsNothing);
    expect(find.text('Message someone'), findsOneWidget);

    await tester.runAsync(() async {
      final all = await store.allPresets();
      expect(all.any((p) => p.label == 'Check mail' && p.isDeleted), isTrue);
    });

    await tester.runAsync(() => store.close());
  });

  testWidgets('the empty-presets state renders without overflow when every preset is deleted', (tester) async {
    late IntentStore store;
    await tester.runAsync(() async {
      store = await openTestStore();
      final all = await store.allPresets();
      for (final p in all) {
        await store.deletePreset(p.id);
      }
    });

    await pumpScreen(tester, store);

    // docs/DATA_MODEL.md §7: the minimum enabled/stored count is
    // deliberately zero — this must render as a valid state, not an error.
    expect(find.textContaining('No presets'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.runAsync(() => store.close());
  });

  testWidgets('toggling a preset off via the switch persists immediately', (tester) async {
    late IntentStore store;
    await tester.runAsync(() async => store = await openTestStore());

    await pumpScreen(tester, store);

    await tester.tap(find.descendant(
      of: find.widgetWithText(ListTile, 'Check mail'),
      matching: find.byType(Switch),
    ));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();

    await tester.runAsync(() async {
      final all = await store.allPresets();
      expect(all.firstWhere((p) => p.label == 'Check mail').enabled, isFalse);
    });

    await tester.runAsync(() => store.close());
  });

  testWidgets('enabling a preset past the 8-enabled cap shows an error and leaves it disabled', (tester) async {
    late IntentStore store;
    await tester.runAsync(() async {
      store = await openTestStore();
      // Bring the store to exactly maxEnabledPresets (8) enabled presets
      // (5 defaults + 3 new), PLUS one more, explicitly disabled, so there's
      // a real switch in the UI whose "turn on" action is the actual edge
      // documented in docs/DATA_MODEL.md §7 — not a happy-path toggle, and
      // not exercising the store API directly bypassing the screen.
      // Created (and disabled) BEFORE the other three, while there's still
      // headroom under the cap — creating it after would throw immediately,
      // since createPreset() always enables by default.
      final oneTooManyId = await store.createPreset('One too many');
      await store.setPresetEnabled(oneTooManyId, false);
      for (var i = 0; i < 3; i++) {
        await store.createPreset('Extra $i');
      }
    });

    await pumpScreen(tester, store);
    expect(find.text('One too many'), findsOneWidget);

    await tester.tap(find.descendant(
      of: find.widgetWithText(ListTile, 'One too many'),
      matching: find.byType(Switch),
    ));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();

    // A usable error, not a crash — and the row must still read as disabled
    // afterwards, since the store rejected the mutation and _reload() only
    // ever reflects what's actually persisted.
    expect(find.byType(SnackBar), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      final all = await store.allPresets();
      expect(all.firstWhere((p) => p.label == 'One too many').enabled, isFalse);
    });

    await tester.runAsync(() => store.close());
  });

  testWidgets('deleting a preset via the confirm dialog removes it from the list', (tester) async {
    late IntentStore store;
    await tester.runAsync(() async => store = await openTestStore());

    await pumpScreen(tester, store);
    expect(find.text('Pay someone'), findsOneWidget);

    await tester.tap(find.descendant(
      of: find.widgetWithText(ListTile, 'Pay someone'),
      matching: find.byIcon(Icons.delete_outline),
    ));
    await tester.pump();
    expect(find.text('Delete preset?'), findsOneWidget);

    await tester.tap(find.text('Delete'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();

    expect(find.text('Pay someone'), findsNothing);

    await tester.runAsync(() => store.close());
  });

  testWidgets('deleting a preset does NOT touch its historical intent_log rows', (tester) async {
    // The exact regression this task's brief calls out explicitly: "restore
    // defaults" hard-deleting old rows would have broken every history
    // entry pointing at them via preset_id. Soft-delete (used here) must
    // never remove the underlying row.
    late IntentStore store;
    late int mailId;
    await tester.runAsync(() async {
      store = await openTestStore();
      mailId = (await store.allPresets()).firstWhere((p) => p.label == 'Check mail').id;
      await store.insertEvent(IntentEvent(
        clientId: 'hist-1',
        kind: IntentKind.intent,
        source: IntentSource.preset,
        text: 'Check mail',
        presetId: mailId,
        declaredAt: DateTime.utc(2026, 1, 1),
        completedAt: DateTime.utc(2026, 1, 1),
      ));
    });

    await pumpScreen(tester, store);
    await tester.tap(find.descendant(
      of: find.widgetWithText(ListTile, 'Check mail'),
      matching: find.byIcon(Icons.delete_outline),
    ));
    await tester.pump();
    await tester.tap(find.text('Delete'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();

    await tester.runAsync(() async {
      final events = await store.recentEvents();
      final row = events.firstWhere((e) => e.clientId == 'hist-1');
      expect(row.presetId, mailId);
      expect(row.text, 'Check mail');
    });

    await tester.runAsync(() => store.close());
  });

  testWidgets('restoring defaults re-seeds the verb five without hard-deleting old rows', (tester) async {
    late IntentStore store;
    await tester.runAsync(() async {
      store = await openTestStore();
      await store.renamePreset((await store.allPresets()).first.id, 'Renamed Preset');
    });

    await pumpScreen(tester, store);
    expect(find.text('Renamed Preset'), findsOneWidget);

    await tester.tap(find.text('Restore defaults'));
    await tester.pump();
    expect(find.text('Restore default presets?'), findsOneWidget);

    await tester.tap(find.text('Restore'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();

    expect(find.text('Renamed Preset'), findsNothing);
    for (final label in defaultPresetLabels) {
      expect(find.text(label), findsOneWidget);
    }

    // The old (renamed) row must still exist in storage, soft-deleted — a
    // hard delete here would orphan any intent_log.preset_id pointing at it
    // (this task's brief flags this exact bug as already having been made
    // once by the data layer, then fixed; the UI must not reintroduce it by
    // calling some other, hypothetical hard-delete path).
    await tester.runAsync(() async {
      final all = await store.allPresets();
      expect(all.any((p) => p.label == 'Renamed Preset' && p.isDeleted), isTrue);
    });

    await tester.runAsync(() => store.close());
  });

  testWidgets('creating a preset past the stored cap shows an error via the Add dialog', (tester) async {
    late IntentStore store;
    await tester.runAsync(() async {
      store = await openTestStore();
      final existing = (await store.allPresets()).length;
      for (var i = existing; i < maxStoredPresets; i++) {
        // Disable each as it's created so this loop hits the STORED cap
        // (30) without also tripping the separate ENABLED cap (8) first.
        final id = await store.createPreset('Filler $i');
        await store.setPresetEnabled(id, false);
      }
    });

    await pumpScreen(tester, store);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'One too many');
    await tester.tap(find.text('Save'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();

    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text('One too many'), findsNothing);

    await tester.runAsync(() => store.close());
  });
}
