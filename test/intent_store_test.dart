import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:why_did_i_unlock/intent_store.dart';

IntentEvent _event({
  String clientId = 'c1',
  IntentKind kind = IntentKind.intent,
  IntentSource? source = IntentSource.preset,
  String text = 'Payments',
  DateTime? declaredAt,
  DateTime? completedAt,
  int? presetId,
}) {
  final declared = declaredAt ?? DateTime.utc(2026, 1, 1, 10, 0, 0);
  return IntentEvent(
    clientId: clientId,
    kind: kind,
    source: source,
    text: text,
    declaredAt: declared,
    completedAt: completedAt ?? declared,
    presetId: presetId,
  );
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late IntentStore store;

  setUp(() async {
    // ":memory:" — fresh in-memory DB per test, no shared state, no disk I/O.
    store = await IntentStore.open(path: inMemoryDatabasePath);
  });

  tearDown(() async {
    await store.close();
  });

  test('1. insertEvent then recentEvents returns it', () async {
    await store.insertEvent(_event());
    final events = await store.recentEvents();
    expect(events, hasLength(1));
    expect(events.first.text, 'Payments');
  });

  test('2. empty DB returns empty list', () async {
    final events = await store.recentEvents();
    expect(events, isEmpty);
  });

  test('3. SQL-injection literal is stored verbatim, table survives', () async {
    const malicious = "'); DROP TABLE intent_log;--";
    await store.insertEvent(_event(text: malicious));
    final events = await store.recentEvents();
    expect(events, hasLength(1));
    expect(events.first.text, malicious);
  });

  test('4. idempotent insert: same clientId twice yields one row', () async {
    await store.insertEvent(_event(clientId: 'dup'));
    await store.insertEvent(_event(clientId: 'dup', text: 'different text'));
    final events = await store.recentEvents();
    expect(events, hasLength(1));
    expect(events.first.text, 'Payments'); // first write wins, second ignored
  });

  test('5a. fromMessage rejects empty text', () {
    final msg = _event().toMessage()..['text'] = '';
    expect(() => IntentEvent.fromMessage(msg), throwsFormatException);
  });

  test('5b. fromMessage rejects oversized text', () {
    final msg = _event().toMessage()..['text'] = 'x' * 501;
    expect(() => IntentEvent.fromMessage(msg), throwsFormatException);
  });

  test('5c. fromMessage rejects bad kind', () {
    final msg = _event().toMessage()..['kind'] = 'bogus';
    expect(() => IntentEvent.fromMessage(msg), throwsFormatException);
  });

  test('5d. fromMessage rejects non-null source when kind=no_intent', () {
    final msg = _event().toMessage()
      ..['kind'] = 'no_intent'
      ..['source'] = 'preset';
    expect(() => IntentEvent.fromMessage(msg), throwsFormatException);
  });

  test('5e. fromMessage rejects declaredAt > completedAt', () {
    final msg = _event().toMessage();
    msg['declaredAt'] = (msg['completedAt'] as int) + 1000;
    expect(() => IntentEvent.fromMessage(msg), throwsFormatException);
  });

  test('5f. fromMessage rejects a non-int presetId', () {
    final msg = _event().toMessage();
    msg['presetId'] = 'not-an-int';
    expect(() => IntentEvent.fromMessage(msg), throwsFormatException);
  });

  test('5g. toMessage omits presetId when null and round-trips it when set', () {
    expect(_event().toMessage().containsKey('presetId'), isFalse);
    final withPreset = _event(presetId: 7).toMessage();
    expect(withPreset['presetId'], 7);
    expect(IntentEvent.fromMessage(withPreset).presetId, 7);
  });

  test('6. no-intent row stores source=null, completedAt=declaredAt', () async {
    final declared = DateTime.utc(2026, 1, 1, 12, 0, 0);
    await store.insertEvent(_event(
      kind: IntentKind.noIntent,
      source: null,
      text: 'Just Like That',
      declaredAt: declared,
      completedAt: declared,
    ));
    final events = await store.recentEvents();
    expect(events, hasLength(1));
    expect(events.first.kind, IntentKind.noIntent);
    expect(events.first.source, isNull);
    expect(events.first.completedAt, events.first.declaredAt);
  });

  test('7. recentEvents(limit) returns newest-first, capped, mixed kinds', () async {
    await store.insertEvent(_event(
      clientId: 'a',
      completedAt: DateTime.utc(2026, 1, 1, 9, 0, 0),
    ));
    await store.insertEvent(_event(
      clientId: 'b',
      kind: IntentKind.noIntent,
      source: null,
      text: 'Just Like That',
      completedAt: DateTime.utc(2026, 1, 1, 11, 0, 0),
    ));
    await store.insertEvent(_event(
      clientId: 'c',
      completedAt: DateTime.utc(2026, 1, 1, 10, 0, 0),
    ));

    final limited = await store.recentEvents(limit: 2);
    expect(limited, hasLength(2));
    expect(limited[0].clientId, 'b'); // 11:00 — newest
    expect(limited[1].clientId, 'c'); // 10:00 — next
  });

  test('8. lastCompletedAt returns latest across kinds; null when empty', () async {
    expect(await store.lastCompletedAt(), isNull);

    await store.insertEvent(_event(
      clientId: 'a',
      completedAt: DateTime.utc(2026, 1, 1, 9, 0, 0),
    ));
    await store.insertEvent(_event(
      clientId: 'b',
      kind: IntentKind.noIntent,
      source: null,
      text: 'Just Like That',
      completedAt: DateTime.utc(2026, 1, 1, 15, 0, 0),
    ));

    final last = await store.lastCompletedAt();
    expect(last, DateTime.utc(2026, 1, 1, 15, 0, 0));
  });

  test('9. schema migration smoke: reopening the same file preserves data', () async {
    // Uses a real temp-file path (not :memory:) so a second open() call
    // reconnects to the same on-disk DB rather than a fresh empty one.
    final tempPath = '${Directory.systemTemp.path}/intent_store_migration_test.db';
    final file = File(tempPath);
    if (await file.exists()) await file.delete();

    var s = await IntentStore.open(path: tempPath);
    await s.insertEvent(_event(clientId: 'persisted'));
    await s.close();

    s = await IntentStore.open(path: tempPath); // same version — simulates reopen
    final events = await s.recentEvents();
    expect(events, hasLength(1));
    expect(events.first.clientId, 'persisted');
    await s.close();

    await file.delete();
  });

  // -------------------------------------------------------------------
  // Schema v2 — migration, unlock_log, open/done/abandoned lifecycle,
  // unlock_id resolution, presets. See docs/DATA_MODEL.md.
  // -------------------------------------------------------------------

  group('20. v1 -> v2 migration', () {
    test('a real v1-schema file upgrades cleanly and keeps existing rows', () async {
      final tempPath = '${Directory.systemTemp.path}/intent_store_v1_to_v2_test.db';
      final file = File(tempPath);
      if (await file.exists()) await file.delete();

      // Build a genuine v1 database by hand (version 1, old schema only) so
      // this exercises onUpgrade, not onCreate.
      final v1Db = await databaseFactoryFfi.openDatabase(
        tempPath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, version) async {
            await db.execute('''
              CREATE TABLE intent_log (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                client_id TEXT NOT NULL UNIQUE,
                kind TEXT NOT NULL,
                source TEXT,
                text TEXT NOT NULL,
                declared_at INTEGER NOT NULL,
                completed_at INTEGER NOT NULL
              )
            ''');
            await db.execute('CREATE INDEX idx_completed_at ON intent_log(completed_at)');
          },
        ),
      );
      await v1Db.insert('intent_log', {
        'client_id': 'pre-existing',
        'kind': 'intent',
        'source': 'preset',
        'text': 'Payments',
        'declared_at': 1000,
        'completed_at': 2000,
      });
      await v1Db.close();

      final store = await IntentStore.open(path: tempPath);

      // Existing row survived, and defaults to status='done'.
      final events = await store.recentEvents();
      expect(events, hasLength(1));
      expect(events.first.clientId, 'pre-existing');
      expect(events.first.status, IntentStatus.done);
      expect(events.first.unlockId, isNull);
      expect(events.first.presetId, isNull);

      // New tables exist and are usable.
      expect(await store.recentUnlocks(), isEmpty);
      final presets = await store.allPresets();
      expect(presets, hasLength(5));
      expect(presets.map((p) => p.label), containsAll(['Payments', 'Calls', 'Messages', 'Food Order', 'Commute']));

      await store.close();
      await file.delete();
    });
  });

  group('21. unlock_log', () {
    test('insertUnlock + recentUnlocks round-trips prompt_shown=true', () async {
      final id = await store.insertUnlock(
        unlockedAt: DateTime.utc(2026, 1, 1, 9, 0, 0),
        promptShown: true,
      );
      expect(id, greaterThan(0));
      final unlocks = await store.recentUnlocks();
      expect(unlocks, hasLength(1));
      expect(unlocks.first.promptShown, isTrue);
      expect(unlocks.first.skipReason, isNull);
    });

    test('insertUnlock + recentUnlocks round-trips a skip reason', () async {
      await store.insertUnlock(
        unlockedAt: DateTime.utc(2026, 1, 1, 9, 0, 0),
        promptShown: false,
        skipReason: SkipReason.cooldown,
      );
      final unlocks = await store.recentUnlocks();
      expect(unlocks.first.promptShown, isFalse);
      expect(unlocks.first.skipReason, SkipReason.cooldown);
    });

    test('insertUnlock + recentUnlocks round-trips SkipReason.quietHours', () async {
      await store.insertUnlock(
        unlockedAt: DateTime.utc(2026, 1, 1, 2, 0, 0),
        promptShown: false,
        skipReason: SkipReason.quietHours,
      );
      final unlocks = await store.recentUnlocks();
      expect(unlocks.first.skipReason, SkipReason.quietHours);
    });

    test('recentUnlocks respects the limit argument', () async {
      for (var i = 0; i < 5; i++) {
        await store.insertUnlock(unlockedAt: DateTime.utc(2026, 1, 1, 9 + i), promptShown: true);
      }
      expect((await store.recentUnlocks(limit: 3)), hasLength(3));
    });

    test('recentUnlocks returns newest first', () async {
      await store.insertUnlock(unlockedAt: DateTime.utc(2026, 1, 1, 9, 0, 0), promptShown: true);
      await store.insertUnlock(unlockedAt: DateTime.utc(2026, 1, 1, 11, 0, 0), promptShown: true);
      await store.insertUnlock(unlockedAt: DateTime.utc(2026, 1, 1, 10, 0, 0), promptShown: true);
      final unlocks = await store.recentUnlocks();
      expect(unlocks.map((u) => u.unlockedAt.hour), [11, 10, 9]);
    });
  });

  group('22. declare/dismiss lifecycle', () {
    test('insertOpenIntent writes status=open with completedAt=declaredAt placeholder', () async {
      final declared = DateTime.utc(2026, 1, 1, 10, 0, 0);
      await store.insertOpenIntent(_event(clientId: 'open1', declaredAt: declared, completedAt: declared));
      final events = await store.recentEvents();
      expect(events, hasLength(1));
      expect(events.first.status, IntentStatus.open);
      expect(events.first.completedAt, declared);
    });

    test('markIntentDone transitions open -> done and sets real completedAt', () async {
      final declared = DateTime.utc(2026, 1, 1, 10, 0, 0);
      final dismissed = DateTime.utc(2026, 1, 1, 10, 5, 0);
      await store.insertOpenIntent(_event(clientId: 'open2', declaredAt: declared, completedAt: declared));
      await store.markIntentDone(clientId: 'open2', completedAt: dismissed);
      final events = await store.recentEvents();
      expect(events.first.status, IntentStatus.done);
      expect(events.first.completedAt, dismissed);
    });

    test('markIntentDone is idempotent — a second call is a harmless no-op', () async {
      final declared = DateTime.utc(2026, 1, 1, 10, 0, 0);
      await store.insertOpenIntent(_event(clientId: 'open3', declaredAt: declared, completedAt: declared));
      await store.markIntentDone(clientId: 'open3', completedAt: DateTime.utc(2026, 1, 1, 10, 5, 0));
      // Second call with a later time must not resurrect/re-complete the row.
      await store.markIntentDone(clientId: 'open3', completedAt: DateTime.utc(2026, 1, 1, 10, 10, 0));
      final events = await store.recentEvents();
      expect(events, hasLength(1));
      expect(events.first.completedAt, DateTime.utc(2026, 1, 1, 10, 5, 0));
    });

    test('sweepOpenToAbandoned moves only open rows, leaves done rows alone', () async {
      final declared = DateTime.utc(2026, 1, 1, 10, 0, 0);
      await store.insertOpenIntent(_event(clientId: 'stays-open', declaredAt: declared, completedAt: declared));
      await store.insertOpenIntent(_event(clientId: 'gets-done', declaredAt: declared, completedAt: declared));
      await store.markIntentDone(clientId: 'gets-done', completedAt: DateTime.utc(2026, 1, 1, 10, 5, 0));

      final swept = await store.sweepOpenToAbandoned();
      expect(swept, 1);

      final events = await store.recentEvents();
      final byId = {for (final e in events) e.clientId: e.status};
      expect(byId['stays-open'], IntentStatus.abandoned);
      expect(byId['gets-done'], IntentStatus.done);
    });

    test('insertOpenIntent is idempotent — a duplicated relay yields one row', () async {
      final declared = DateTime.utc(2026, 1, 1, 10, 0, 0);
      final event = _event(clientId: 'dupe', declaredAt: declared, completedAt: declared);
      await store.insertOpenIntent(event);
      await store.insertOpenIntent(event);
      expect(await store.recentEvents(), hasLength(1));
    });

    test('markIntentDone on an unknown clientId is a silent no-op, not a throw', () async {
      await store.markIntentDone(clientId: 'never-existed', completedAt: DateTime.utc(2026, 1, 1, 11));
      expect(await store.recentEvents(), isEmpty);
    });

    test('markIntentDone does NOT resurrect an already-abandoned row', () async {
      // The real scenario: an intent is declared, the process dies, the next
      // engine start sweeps it to `abandoned` — and only THEN a late/retried
      // relay of the original dismissal arrives. That must not silently flip
      // a correctly-abandoned row back to `done` and fabricate a completion
      // time, which would corrupt the timing stats the status column exists
      // to protect.
      final declared = DateTime.utc(2026, 1, 1, 10, 0, 0);
      await store.insertOpenIntent(_event(clientId: 'late', declaredAt: declared, completedAt: declared));
      await store.sweepOpenToAbandoned();
      await store.markIntentDone(clientId: 'late', completedAt: DateTime.utc(2026, 1, 1, 10, 5, 0));

      final events = await store.recentEvents();
      expect(events.first.status, IntentStatus.abandoned);
      expect(events.first.completedAt, declared); // untouched placeholder
    });

    test('sweepOpenToAbandoned returns 0 and changes nothing when no rows are open', () async {
      await store.insertEvent(_event(clientId: 'already-done'));
      expect(await store.sweepOpenToAbandoned(), 0);
      expect((await store.recentEvents()).first.status, IntentStatus.done);
    });

    test('insertEvent (no-intent path) writes status=done directly', () async {
      await store.insertEvent(_event(
        clientId: 'ni1',
        kind: IntentKind.noIntent,
        source: null,
        text: 'Just Like That',
      ));
      final events = await store.recentEvents();
      expect(events.first.status, IntentStatus.done);
    });
  });

  group('23. unlock_id resolution', () {
    test('a declared intent links to the most recent prompted unlock', () async {
      await store.insertUnlock(unlockedAt: DateTime.utc(2026, 1, 1, 8, 0, 0), promptShown: false, skipReason: SkipReason.cooldown);
      final promptedId = await store.insertUnlock(unlockedAt: DateTime.utc(2026, 1, 1, 9, 0, 0), promptShown: true);

      await store.insertOpenIntent(_event(clientId: 'linked'));

      final events = await store.recentEvents();
      expect(events.first.unlockId, promptedId);
    });

    test('a LATER skipped unlock does not steal the link from the prompted one', () async {
      // The realistic sequence this protects: prompt shown at T1, user leaves
      // it open, unlocks again at T2 (skipped as overlay_active), THEN
      // answers at T3. The link must still resolve to T1's prompted row —
      // this is precisely the "two prompted unlocks are never adjacent"
      // argument that makes the stateless lookup safe (docs/DATA_MODEL.md §4).
      final promptedId = await store.insertUnlock(
        unlockedAt: DateTime.utc(2026, 1, 1, 9, 0, 0),
        promptShown: true,
      );
      await store.insertUnlock(
        unlockedAt: DateTime.utc(2026, 1, 1, 9, 5, 0),
        promptShown: false,
        skipReason: SkipReason.overlayActive,
      );

      await store.insertOpenIntent(_event(clientId: 'after-skip'));

      expect((await store.recentEvents()).first.unlockId, promptedId);
    });

    test('with no prompted unlock in the table, unlockId is null (never throws)', () async {
      await store.insertOpenIntent(_event(clientId: 'orphan'));
      final events = await store.recentEvents();
      expect(events.first.unlockId, isNull);
    });

    test('no-intent (insertEvent) rows also resolve unlockId', () async {
      final promptedId = await store.insertUnlock(unlockedAt: DateTime.utc(2026, 1, 1, 9, 0, 0), promptShown: true);
      await store.insertEvent(_event(clientId: 'ni-link', kind: IntentKind.noIntent, source: null, text: 'Just Like That'));
      final events = await store.recentEvents();
      expect(events.first.unlockId, promptedId);
    });
  });

  group('24. lastCompletedAt includes open-row placeholders', () {
    test('an open intent counts as "just engaged" for cooldown purposes', () async {
      final declared = DateTime.utc(2026, 1, 1, 12, 0, 0);
      await store.insertOpenIntent(_event(clientId: 'open-for-cooldown', declaredAt: declared, completedAt: declared));
      expect(await store.lastCompletedAt(), declared);
    });
  });

  group('25. presets', () {
    test('migration seeds exactly the historical five, in order, enabled', () async {
      final presets = await store.activePresets();
      expect(presets.map((p) => p.label), ['Payments', 'Calls', 'Messages', 'Food Order', 'Commute']);
      expect(presets.every((p) => p.enabled), isTrue);
    });

    test('createPreset appends at the end of sort order', () async {
      final id = await store.createPreset('Groceries');
      final presets = await store.activePresets();
      expect(presets.last.id, id);
      expect(presets.last.label, 'Groceries');
      expect(presets.last.sortOrder, 5);
    });

    test('createPreset rejects an empty label', () async {
      expect(() => store.createPreset('   '), throwsA(isA<PresetLimitExceeded>()));
    });

    test('createPreset rejects a label over the stored max', () async {
      expect(() => store.createPreset('x' * 41), throwsA(isA<PresetLimitExceeded>()));
    });

    test('renaming a preset does not change past history text', () async {
      final presets = await store.activePresets();
      final paymentsId = presets.firstWhere((p) => p.label == 'Payments').id;
      await store.insertOpenIntent(_event(clientId: 'hist1', text: 'Payments', presetId: paymentsId));
      await store.markIntentDone(clientId: 'hist1', completedAt: DateTime.utc(2026, 1, 1, 10, 5, 0));

      await store.renamePreset(paymentsId, 'Bill Pay');

      final events = await store.recentEvents();
      expect(events.first.text, 'Payments'); // snapshot, unchanged
      expect(events.first.presetId, paymentsId); // series preserved

      final renamed = await store.allPresets();
      expect(renamed.firstWhere((p) => p.id == paymentsId).label, 'Bill Pay');
    });

    test('soft-deleting a preset hides it from activePresets but keeps allPresets and history resolvable', () async {
      final presets = await store.activePresets();
      final callsId = presets.firstWhere((p) => p.label == 'Calls').id;
      await store.insertOpenIntent(_event(clientId: 'hist2', text: 'Calls', presetId: callsId));

      await store.deletePreset(callsId);

      final active = await store.activePresets();
      expect(active.map((p) => p.label), isNot(contains('Calls')));

      final all = await store.allPresets();
      final deleted = all.firstWhere((p) => p.id == callsId);
      expect(deleted.isDeleted, isTrue);
      expect(deleted.enabled, isFalse);

      final events = await store.recentEvents();
      expect(events.first.presetId, callsId); // still resolvable
    });

    test('setPresetEnabled(false) then (true) round-trips', () async {
      final presets = await store.activePresets();
      final id = presets.first.id;
      await store.setPresetEnabled(id, false);
      expect((await store.activePresets()).map((p) => p.id), isNot(contains(id)));
      await store.setPresetEnabled(id, true);
      expect((await store.activePresets()).map((p) => p.id), contains(id));
    });

    test('enabling cannot exceed maxEnabledPresets', () async {
      // 5 seeded + 3 more = 8 (the max), all enabled by createPreset's own check.
      await store.createPreset('P6');
      await store.createPreset('P7');
      await store.createPreset('P8');
      expect((await store.activePresets()).length, maxEnabledPresets);

      // A 9th can be created disabled-by-necessity... but createPreset itself
      // refuses once at the enabled cap, since it enables by default.
      expect(() => store.createPreset('P9'), throwsA(isA<PresetLimitExceeded>()));
    });

    test('reorderPresets rewrites sort_order contiguously', () async {
      final presets = await store.activePresets();
      final ids = presets.map((p) => p.id).toList().reversed.toList();
      await store.reorderPresets(ids);
      final reordered = await store.activePresets();
      expect(reordered.map((p) => p.id).toList(), ids);
      expect(reordered.map((p) => p.sortOrder).toList(), List.generate(ids.length, (i) => i));
    });

    test('restoreDefaultPresets re-seeds after everything was deleted', () async {
      final presets = await store.allPresets();
      for (final p in presets) {
        await store.deletePreset(p.id);
      }
      expect(await store.activePresets(), isEmpty);

      await store.restoreDefaultPresets();
      final restored = await store.activePresets();
      expect(restored.map((p) => p.label), ['Payments', 'Calls', 'Messages', 'Food Order', 'Commute']);
    });

    test('restoreDefaultPresets soft-deletes, keeping old preset_id references resolvable', () async {
      // Regression: an earlier implementation hard-deleted every row here,
      // which orphaned every intent_log.preset_id pointing at them — silently
      // breaking the historical series that column exists to preserve.
      final paymentsId = (await store.activePresets()).firstWhere((p) => p.label == 'Payments').id;
      await store.insertOpenIntent(_event(clientId: 'pre-restore', text: 'Payments', presetId: paymentsId));

      await store.restoreDefaultPresets();

      // The old row still exists (soft-deleted), so the history link resolves.
      final all = await store.allPresets();
      final oldRow = all.firstWhere((p) => p.id == paymentsId);
      expect(oldRow.isDeleted, isTrue);
      expect((await store.recentEvents()).first.presetId, paymentsId);
    });

    test('the stored-preset cap ignores soft-deleted rows', () async {
      // Regression: counting soft-deleted rows toward maxStoredPresets meant a
      // user who repeatedly created and deleted presets would permanently
      // exhaust the cap, since soft-delete never removes the row.
      for (var i = 0; i < 10; i++) {
        final id = await store.createPreset('Temp $i');
        await store.deletePreset(id);
      }
      // 5 seeded + 10 created-then-deleted = 15 rows, but only 5 active.
      expect((await store.allPresets()).length, 15);
      // Must still be able to create — this threw before the fix.
      await store.createPreset('Still allowed');
      expect((await store.activePresets()).map((p) => p.label), contains('Still allowed'));
    });

    test('zero enabled presets is a valid, non-throwing state', () async {
      final presets = await store.allPresets();
      for (final p in presets) {
        await store.setPresetEnabled(p.id, false);
      }
      expect(await store.activePresets(), isEmpty);
      // Capture-screen-side layout validity is covered in widget tests, not here.
    });
  });

  group('26. IntentDismissal message validation', () {
    test('round-trips through toMessage/fromMessage', () {
      final dismissal = IntentDismissal(clientId: 'c1', completedAt: DateTime.utc(2026, 1, 1, 10, 5));
      final rebuilt = IntentDismissal.fromMessage(dismissal.toMessage());
      expect(rebuilt.clientId, dismissal.clientId);
      expect(rebuilt.completedAt, dismissal.completedAt);
    });

    test('rejects missing clientId', () {
      final msg = IntentDismissal(clientId: 'c1', completedAt: DateTime.utc(2026, 1, 1)).toMessage();
      msg.remove('clientId');
      expect(() => IntentDismissal.fromMessage(msg), throwsFormatException);
    });

    test('rejects empty clientId', () {
      final msg = IntentDismissal(clientId: '', completedAt: DateTime.utc(2026, 1, 1)).toMessage();
      expect(() => IntentDismissal.fromMessage(msg), throwsFormatException);
    });

    test('rejects a non-int completedAt', () {
      final msg = IntentDismissal(clientId: 'c1', completedAt: DateTime.utc(2026, 1, 1)).toMessage();
      msg['completedAt'] = 'not-a-timestamp';
      expect(() => IntentDismissal.fromMessage(msg), throwsFormatException);
    });

    test('rejects a missing completedAt', () {
      final msg = IntentDismissal(clientId: 'c1', completedAt: DateTime.utc(2026, 1, 1)).toMessage();
      msg.remove('completedAt');
      expect(() => IntentDismissal.fromMessage(msg), throwsFormatException);
    });
  });

  group('27. declare-then-dismiss via the two-message shape (end-to-end at the store level)', () {
    test('a declare message followed by a dismiss message produces one done row', () async {
      final declared = DateTime.utc(2026, 1, 1, 10, 0, 0);
      final dismissed = DateTime.utc(2026, 1, 1, 10, 3, 0);

      // Mirrors what backgroundMain's listener does for 'declare' then
      // 'dismiss' messages — not testing main.dart directly (it's
      // unreachable from tests, see docs/TEST_PLAN.md), but confirming the
      // store-level contract those two calls rely on.
      await store.insertOpenIntent(_event(clientId: 'e2e', declaredAt: declared, completedAt: declared));
      final dismissal = IntentDismissal(clientId: 'e2e', completedAt: dismissed);
      await store.markIntentDone(clientId: dismissal.clientId, completedAt: dismissal.completedAt);

      final events = await store.recentEvents();
      expect(events, hasLength(1));
      expect(events.first.status, IntentStatus.done);
      expect(events.first.completedAt, dismissed);
      expect(events.first.declaredAt, declared);
    });

    test('a declare message with no matching dismiss survives a sweep as abandoned', () async {
      final declared = DateTime.utc(2026, 1, 1, 10, 0, 0);
      await store.insertOpenIntent(_event(clientId: 'e2e-crash', declaredAt: declared, completedAt: declared));

      // Simulates the process dying before dismissal (reboot, OEM kill) and
      // a fresh engine starting — backgroundMain calls this once at startup.
      final swept = await store.sweepOpenToAbandoned();

      expect(swept, 1);
      final events = await store.recentEvents();
      expect(events.first.status, IntentStatus.abandoned);
      // The intent is NOT lost — this is the whole point of writing at
      // declaration time instead of only at dismissal (docs/DATA_MODEL.md §4).
      expect(events.first.text, 'Payments');
    });
  });
}
