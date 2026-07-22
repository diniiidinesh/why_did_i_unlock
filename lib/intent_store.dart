import 'dart:io';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

/// Defensive backstop on stored intent text, independent of the UI layer's
/// own (stricter) `intentMaxInputLength` in main.dart — this is defense in
/// depth against a malformed/oversized message reaching the store, not a
/// UX-facing limit, so it's deliberately generous and store-local (importing
/// main.dart here would create a circular import: main.dart imports this file).
const int _maxStoredTextLength = 500;

/// The two outcome kinds an unlock can resolve to. `intent` = a real declared
/// intent that became a bubble; `noIntent` = the honest "Just Like That"
/// admission (see [noIntentLabel] in main.dart). Kept as its own dimension,
/// separate from [IntentSource], so "purposeless-unlock rate" is a clean
/// `WHERE kind = ...` query rather than mixed into the input-method buckets.
enum IntentKind { intent, noIntent }

/// How a real intent's text was entered. Only meaningful when [IntentKind.intent]
/// — null for [IntentKind.noIntent] rows.
enum IntentSource { preset, custom }

String _kindToDb(IntentKind kind) => kind == IntentKind.intent ? 'intent' : 'no_intent';

IntentKind _kindFromDb(String value) => value == 'intent' ? IntentKind.intent : IntentKind.noIntent;

String? _sourceToDb(IntentSource? source) {
  if (source == null) return null;
  return source == IntentSource.preset ? 'preset' : 'custom';
}

IntentSource? _sourceFromDb(String? value) {
  if (value == null) return null;
  return value == 'preset' ? IntentSource.preset : IntentSource.custom;
}

/// One logged unlock event — either a completed (dismissed) intent or a
/// no-intent ("Just Like That") admission. Immutable; constructed by the
/// overlay isolate at declare/no-intent time and relayed via
/// `FlutterOverlayWindow.shareData()` to the background isolate for storage
/// (the overlay engine has no plugins registered — see CLAUDE.md §3 — so it
/// cannot call sqflite directly).
class IntentEvent {
  /// Client-generated at declare/no-intent time. Makes the write idempotent
  /// (`INSERT OR IGNORE`) — safe against a retried or duplicated relay.
  final String clientId;
  final IntentKind kind;
  final IntentSource? source;
  final String text;
  final DateTime declaredAt;
  final DateTime completedAt;

  const IntentEvent({
    required this.clientId,
    required this.kind,
    required this.source,
    required this.text,
    required this.declaredAt,
    required this.completedAt,
  });

  /// Builds from the JSON-primitive Map that crosses the overlay→background
  /// `shareData`/`overlayListener` bridge (JSONMessageCodec — only
  /// String/num/bool/List/Map survive the trip, no DateTime/enum objects).
  /// Throws [FormatException] on any structurally invalid message; callers
  /// (the `overlayListener` handler) should catch and drop malformed messages
  /// rather than let a bad message crash the persistent background isolate.
  factory IntentEvent.fromMessage(Map<dynamic, dynamic> message) {
    final clientId = message['clientId'];
    final kindStr = message['kind'];
    final sourceStr = message['source'];
    final text = message['text'];
    final declaredAtMs = message['declaredAt'];
    final completedAtMs = message['completedAt'];

    if (clientId is! String || clientId.isEmpty) {
      throw const FormatException('clientId missing or not a non-empty String');
    }
    if (kindStr != 'intent' && kindStr != 'no_intent') {
      throw const FormatException('kind must be "intent" or "no_intent"');
    }
    final kind = _kindFromDb(kindStr as String);
    if (kind == IntentKind.intent && sourceStr != 'preset' && sourceStr != 'custom') {
      throw const FormatException('source must be "preset" or "custom" when kind=intent');
    }
    if (kind == IntentKind.noIntent && sourceStr != null) {
      throw const FormatException('source must be null when kind=no_intent');
    }
    if (text is! String || text.isEmpty) {
      throw const FormatException('text missing or not a non-empty String');
    }
    if (text.length > _maxStoredTextLength) {
      throw const FormatException('text exceeds max stored length');
    }
    if (declaredAtMs is! int || completedAtMs is! int) {
      throw const FormatException('declaredAt/completedAt must be int (ms epoch)');
    }
    if (declaredAtMs > completedAtMs) {
      throw const FormatException('declaredAt must be <= completedAt');
    }

    return IntentEvent(
      clientId: clientId,
      kind: kind,
      source: _sourceFromDb(sourceStr as String?),
      text: text,
      declaredAt: DateTime.fromMillisecondsSinceEpoch(declaredAtMs, isUtc: true),
      completedAt: DateTime.fromMillisecondsSinceEpoch(completedAtMs, isUtc: true),
    );
  }

  /// The Map shape sent across `shareData()` — mirror of [IntentEvent.fromMessage].
  Map<String, dynamic> toMessage() => {
        'clientId': clientId,
        'kind': _kindToDb(kind),
        'source': _sourceToDb(source),
        'text': text,
        'declaredAt': declaredAt.millisecondsSinceEpoch,
        'completedAt': completedAt.millisecondsSinceEpoch,
      };
}

const String _dbFileName = 'intents.db';
const int _schemaVersion = 1;

/// Repository over the `intent_log` SQLite table. Reused by BOTH the
/// background engine (the sole writer — see CLAUDE.md §3 / ARCHITECTURE.md)
/// and the main UI engine (read-only, for the history screen). Opened in WAL
/// mode so those two isolates' separate connections to the same file can
/// safely read-while-write (see ERD notes in the Sprint 3 plan).
///
/// Every query is parameterized (`?` + whereArgs) — never string-interpolated
/// — so arbitrary user-typed intent text can never be interpreted as SQL.
class IntentStore {
  final Database _db;

  IntentStore._(this._db);

  /// Opens (creating on first run) the on-device DB. [path] is injectable so
  /// tests can point at an in-memory `sqflite_common_ffi` database instead of
  /// the real on-device file.
  ///
  /// [ownConnection] (→ sqflite `singleInstance: false`) gives this store its
  /// OWN native connection instead of sharing sqflite's default per-path
  /// singleton. The persistent background writer (backgroundMain) uses the
  /// default shared connection; the history screen — a DIFFERENT isolate
  /// (main UI engine) opening the SAME file — MUST pass `ownConnection: true`.
  /// Without it, both isolates share ONE connection, and the history screen's
  /// `close()` on dispose closes the writer's connection too, so every
  /// subsequent background write throws `DatabaseException(database_closed)`
  /// permanently until the process restarts (confirmed on-device 2026-07-22 —
  /// see docs/debug/sprint3-session-log-2026-07-22.txt). Two independent
  /// connections to one file is exactly what WAL mode (below) is for: one
  /// writer + concurrent readers, no cross-close.
  static Future<IntentStore> open({String? path, bool ownConnection = false}) async {
    final dbPath = path ?? join(await getDatabasesPath(), _dbFileName);
    // Defensive: on a completely fresh install/reinstall, the background
    // engine can be the very first thing to ever touch app storage (no
    // MainActivity launch has happened yet to implicitly create it) — belt
    // on top of the real fix (retrying open() at the call site in main.dart)
    // for the `DatabaseException(open_failed ...)` seen on-device 2026-07-22.
    // Harmless no-op for the in-memory test path (dirname of ':memory:' is
    // '.', which always exists).
    await Directory(dirname(dbPath)).create(recursive: true);
    final db = await openDatabase(
      dbPath,
      version: _schemaVersion,
      singleInstance: !ownConnection,
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
    );
    // rawQuery, NOT execute: `PRAGMA journal_mode=WAL` returns a result row
    // (the resulting mode). Android's sqflite backend rejects that via
    // execute() ("Queries can be performed using ... query or rawQuery
    // methods only") — only caught on a real device, since sqflite_common_ffi
    // (used by desktop unit tests) tolerates execute() for this PRAGMA.
    await db.rawQuery('PRAGMA journal_mode=WAL');
    return IntentStore._(db);
  }

  Future<void> close() => _db.close();

  /// Idempotent insert — a retried/duplicated relay of the same [event]
  /// (same `clientId`) is a silent no-op rather than a duplicate row.
  Future<void> insertEvent(IntentEvent event) async {
    await _db.insert(
      'intent_log',
      {
        'client_id': event.clientId,
        'kind': _kindToDb(event.kind),
        'source': _sourceToDb(event.source),
        'text': event.text,
        'declared_at': event.declaredAt.millisecondsSinceEpoch,
        'completed_at': event.completedAt.millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// Most recent `completed_at` across ALL events (intent or no-intent) —
  /// the input the cooldown policy needs. Null on an empty log (never
  /// prompted before → no floor to apply).
  Future<DateTime?> lastCompletedAt() async {
    final rows = await _db.rawQuery('SELECT MAX(completed_at) AS m FROM intent_log');
    final ms = rows.first['m'] as int?;
    if (ms == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  }

  /// Most recent [limit] events, newest first — feeds the history screen.
  Future<List<IntentEvent>> recentEvents({int limit = 50}) async {
    final rows = await _db.query(
      'intent_log',
      orderBy: 'completed_at DESC',
      limit: limit,
    );
    return rows
        .map((row) => IntentEvent(
              clientId: row['client_id'] as String,
              kind: _kindFromDb(row['kind'] as String),
              source: _sourceFromDb(row['source'] as String?),
              text: row['text'] as String,
              declaredAt: DateTime.fromMillisecondsSinceEpoch(row['declared_at'] as int, isUtc: true),
              completedAt: DateTime.fromMillisecondsSinceEpoch(row['completed_at'] as int, isUtc: true),
            ))
        .toList();
  }
}
