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
}) {
  final declared = declaredAt ?? DateTime.utc(2026, 1, 1, 10, 0, 0);
  return IntentEvent(
    clientId: clientId,
    kind: kind,
    source: source,
    text: text,
    declaredAt: declared,
    completedAt: completedAt ?? declared,
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
}
