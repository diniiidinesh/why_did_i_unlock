import 'dart:io';

import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

/// Defensive backstop on stored intent text, independent of the UI layer's
/// own (stricter) `intentMaxInputLength` in main.dart — this is defense in
/// depth against a malformed/oversized message reaching the store, not a
/// UX-facing limit, so it's deliberately generous and store-local (importing
/// main.dart here would create a circular import: main.dart imports this file).
const int _maxStoredTextLength = 500;

/// Preset limits — see docs/DATA_MODEL.md §7 for the full rationale. The
/// binding constraint is decision cost at the capture screen (must be
/// answerable in ~2s, one-handed), not storage or layout space.
const int maxEnabledPresets = 8;
const int maxStoredPresets = 30;
const int presetLabelMaxLength = 40;

/// Stricter UI-facing cap, applied by the manage-presets text field (T16) —
/// the store's own [presetLabelMaxLength] is the defence-in-depth backstop
/// behind it, mirroring how [_maxStoredTextLength] backstops
/// `intentMaxInputLength` in main.dart.
const int presetLabelUiMaxLength = 24;

/// Reserved bound for `intent_preset.allowed_packages`. **Not enforced
/// anywhere yet** — there is deliberately no setter for that column until
/// app-restricted sessions are built (docs/DATA_MODEL.md §10), so there is no
/// write path to validate. Declared now so the limit is decided once, with
/// the schema, rather than invented later under feature pressure.
const int allowedPackagesMaxLength = 2000;

/// The two outcome kinds an unlock can resolve to. `intent` = a real declared
/// intent that became a bubble; `noIntent` = the honest "Just Like That"
/// admission (see [noIntentLabel] in main.dart). Kept as its own dimension,
/// separate from [IntentSource], so "purposeless-unlock rate" is a clean
/// `WHERE kind = ...` query rather than mixed into the input-method buckets.
enum IntentKind { intent, noIntent }

/// How a real intent's text was entered. Only meaningful when [IntentKind.intent]
/// — null for [IntentKind.noIntent] rows.
enum IntentSource { preset, custom }

/// Lifecycle of a declared intent row, added in schema v2 (see
/// docs/DATA_MODEL.md §4). `open` = declared but not yet dismissed; `done` =
/// dismissed normally; `abandoned` = swept from a lingering `open` row on
/// background-engine start (the bubble is gone — the process that would have
/// dismissed it died). `noIntent` rows go straight to `done` — there is no
/// intermediate state for an atomic admission.
enum IntentStatus { open, done, abandoned }

/// Why a given unlock did NOT show a prompt (or the special-cased "shown but
/// unusual" values). See docs/DATA_MODEL.md §5 for expected volumes — the
/// last two are defensive guards that should fire ~never; a nonzero count is
/// itself a diagnostic signal, not noise.
enum SkipReason {
  promptsDisabled,
  cooldown,
  probability,
  overlayActive,
  noPermission,
  invalidScreenSize,
  pluginTimeout,
  quietHours,

  /// Unlock while a bubble was snoozed — restored the bubble instead of a
  /// capture prompt (`docs/erd/bubble-ux-hybrid-plan-2026-07-24.md` R5b).
  snoozeEnded,
}

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

String _statusToDb(IntentStatus status) => switch (status) {
      IntentStatus.open => 'open',
      IntentStatus.done => 'done',
      IntentStatus.abandoned => 'abandoned',
    };

IntentStatus _statusFromDb(String value) => switch (value) {
      'open' => IntentStatus.open,
      'abandoned' => IntentStatus.abandoned,
      _ => IntentStatus.done,
    };

String _skipReasonToDb(SkipReason reason) => switch (reason) {
      SkipReason.promptsDisabled => 'prompts_disabled',
      SkipReason.cooldown => 'cooldown',
      SkipReason.probability => 'probability',
      SkipReason.overlayActive => 'overlay_active',
      SkipReason.noPermission => 'no_permission',
      SkipReason.invalidScreenSize => 'invalid_screen_size',
      SkipReason.pluginTimeout => 'plugin_timeout',
      SkipReason.quietHours => 'quiet_hours',
      SkipReason.snoozeEnded => 'snooze_ended',
    };

SkipReason? _skipReasonFromDb(String? value) => switch (value) {
      'prompts_disabled' => SkipReason.promptsDisabled,
      'cooldown' => SkipReason.cooldown,
      'probability' => SkipReason.probability,
      'overlay_active' => SkipReason.overlayActive,
      'no_permission' => SkipReason.noPermission,
      'invalid_screen_size' => SkipReason.invalidScreenSize,
      'plugin_timeout' => SkipReason.pluginTimeout,
      'quiet_hours' => SkipReason.quietHours,
      'snooze_ended' => SkipReason.snoozeEnded,
      _ => null,
    };

/// One logged unlock event — either a completed (dismissed) intent, an
/// abandoned one, or a no-intent ("Just Like That") admission. Constructed by
/// the overlay isolate at declare/no-intent time and relayed via
/// `IsolateNameServer` ports to the background isolate for storage (the
/// overlay engine has no plugins registered — see docs/ARCHITECTURE.md §1 —
/// so it cannot call sqflite directly).
///
/// [unlockId] and [presetId] are DIMENSION/EVENT links resolved by the
/// BACKGROUND isolate at write time (see [IntentStore.insertOpenIntent]),
/// never supplied across the relay for [unlockId] — the overlay isolate has
/// no way to know which `unlock_log` row it belongs to. [presetId] MAY be
/// supplied by the overlay (once presets are relayed to it — see the config
/// relay work) when the source is a known preset.
class IntentEvent {
  /// Client-generated at declare/no-intent time. Makes the write idempotent
  /// (`INSERT OR IGNORE` / update-by-key) — safe against a retried or
  /// duplicated relay.
  final String clientId;
  final IntentKind kind;
  final IntentSource? source;
  final String text;
  final DateTime declaredAt;
  final DateTime completedAt;
  final IntentStatus status;
  final int? presetId;

  /// Resolved by the store, not carried across the relay — see class doc.
  /// Only populated on rows read back FROM the store (e.g. `recentEvents`);
  /// always null on a freshly-constructed event about to be inserted.
  final int? unlockId;

  const IntentEvent({
    required this.clientId,
    required this.kind,
    required this.source,
    required this.text,
    required this.declaredAt,
    required this.completedAt,
    this.status = IntentStatus.done,
    this.presetId,
    this.unlockId,
  });

  /// Builds from the JSON-primitive Map that crosses the overlay→background
  /// IsolateNameServer relay (only String/num/bool/List/Map survive the
  /// trip, no DateTime/enum objects — see `_relayIntentEvent` in main.dart).
  /// Throws [FormatException] on any structurally invalid message; callers
  /// should catch and drop malformed messages rather than let a bad message
  /// crash the persistent background isolate.
  factory IntentEvent.fromMessage(Map<dynamic, dynamic> message) {
    final clientId = message['clientId'];
    final kindStr = message['kind'];
    final sourceStr = message['source'];
    final text = message['text'];
    final declaredAtMs = message['declaredAt'];
    final completedAtMs = message['completedAt'];
    final presetId = message['presetId'];

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
    if (presetId != null && presetId is! int) {
      throw const FormatException('presetId must be int or absent');
    }

    return IntentEvent(
      clientId: clientId,
      kind: kind,
      source: _sourceFromDb(sourceStr as String?),
      text: text,
      declaredAt: DateTime.fromMillisecondsSinceEpoch(declaredAtMs, isUtc: true),
      completedAt: DateTime.fromMillisecondsSinceEpoch(completedAtMs, isUtc: true),
      presetId: presetId as int?,
    );
  }

  /// The Map shape sent across the relay — mirror of [IntentEvent.fromMessage].
  /// Deliberately does NOT include [unlockId] (never known by the overlay
  /// isolate) or [status] (the background isolate decides that from context —
  /// a message on the "declare" relay is always `open`/pending, a message on
  /// the "no intent" relay is always immediately `done`).
  Map<String, dynamic> toMessage() => {
        'clientId': clientId,
        'kind': _kindToDb(kind),
        'source': _sourceToDb(source),
        'text': text,
        'declaredAt': declaredAt.millisecondsSinceEpoch,
        'completedAt': completedAt.millisecondsSinceEpoch,
        if (presetId != null) 'presetId': presetId,
      };
}

/// One row in `unlock_log` — written by the background isolate for EVERY
/// unlock, whether or not a prompt was shown. See docs/DATA_MODEL.md §3 for
/// why this table exists (intent_log alone undercounts unlocks by over 50%
/// at the shipped triage defaults) and §6 for the full scenario table.
///
/// Strictly append-only: written once, never updated (docs/DATA_MODEL.md §2).
class UnlockEvent {
  final int? id;
  final DateTime unlockedAt;
  final bool promptShown;
  final SkipReason? skipReason;

  const UnlockEvent({
    this.id,
    required this.unlockedAt,
    required this.promptShown,
    this.skipReason,
  }) : assert(
          promptShown != (skipReason != null),
          'skipReason must be set iff promptShown is false',
        );
}

/// One row in `intent_preset` — a user-editable capture-screen pill. Seeded
/// on first install with [defaultPresetLabels] (verb phrases; see
/// `docs/erd/verb-presets-job-goers-2026-07-25.md`). Untouched installs that
/// still have [legacyDefaultPresetLabels] are migrated once via
/// [defaultPresetsSeedVersionKey].
///
/// [tier] and [allowedPackages] are forward-compat columns, unused this
/// iteration — see docs/DATA_MODEL.md §10 (delay-to-reveal prompts and
/// app-restricted sessions respectively). Deliberately not modelled as enums
/// yet since only one value ('standard'/null) is ever produced today.
class IntentPreset {
  final int id;
  final String label;
  final int sortOrder;
  final bool enabled;
  final DateTime? deletedAt;
  final String tier;
  final String? allowedPackages;
  final DateTime createdAt;

  const IntentPreset({
    required this.id,
    required this.label,
    required this.sortOrder,
    required this.enabled,
    this.deletedAt,
    this.tier = 'standard',
    this.allowedPackages,
    required this.createdAt,
  });

  bool get isDeleted => deletedAt != null;
}

/// Thrown when a preset mutation would violate a limit in
/// docs/DATA_MODEL.md §7 (too many enabled, too many stored, label too long).
/// A distinct exception type so UI code can catch it and show a specific
/// message rather than a generic failure.
class PresetLimitExceeded implements Exception {
  final String message;
  const PresetLimitExceeded(this.message);
  @override
  String toString() => 'PresetLimitExceeded: $message';
}

/// The minimal message relayed from the overlay isolate at DISMISSAL time —
/// deliberately NOT a full [IntentEvent]. The declared fields (kind, source,
/// text, declaredAt) were already persisted by the earlier "declare" relay
/// (see [IntentStore.insertOpenIntent]); dismissal only needs to locate that
/// row by its client-generated key and mark it complete. See
/// docs/DATA_MODEL.md §4.
class IntentDismissal {
  final String clientId;
  final DateTime completedAt;

  const IntentDismissal({required this.clientId, required this.completedAt});

  /// Mirrors [IntentEvent.fromMessage]'s validation style — throws
  /// [FormatException] on any structurally invalid message; callers should
  /// catch and drop rather than let a bad message crash the background
  /// isolate.
  factory IntentDismissal.fromMessage(Map<dynamic, dynamic> message) {
    final clientId = message['clientId'];
    final completedAtMs = message['completedAt'];
    if (clientId is! String || clientId.isEmpty) {
      throw const FormatException('clientId missing or not a non-empty String');
    }
    if (completedAtMs is! int) {
      throw const FormatException('completedAt must be int (ms epoch)');
    }
    return IntentDismissal(
      clientId: clientId,
      completedAt: DateTime.fromMillisecondsSinceEpoch(completedAtMs, isUtc: true),
    );
  }

  Map<String, dynamic> toMessage() => {
        'clientId': clientId,
        'completedAt': completedAt.millisecondsSinceEpoch,
      };
}

const String _dbFileName = 'intents.db';
const int _schemaVersion = 2;

/// The five presets shipped on fresh install / Restore defaults.
/// Verb phrases tuned for job-goer unlocks — see
/// `docs/erd/verb-presets-job-goers-2026-07-25.md`.
const List<String> defaultPresetLabels = [
  'Check mail',
  'Message someone',
  'Book a cab',
  'Order food',
  'Pay someone',
];

/// Pre-verb seed (schema v2 era). Used only to detect "untouched defaults"
/// installs that should auto-migrate to [defaultPresetLabels].
const List<String> legacyDefaultPresetLabels = [
  'Payments',
  'Calls',
  'Messages',
  'Food Order',
  'Commute',
];

/// First verb seed (Watch reels instead of Pay someone). Untouched v2 installs
/// migrate to [defaultPresetLabels] when [defaultPresetsSeedVersion] bumps.
const List<String> verbPresetLabelsV2 = [
  'Check mail',
  'Message someone',
  'Book a cab',
  'Order food',
  'Watch reels',
];

/// Prefs key for [defaultPresetLabels] seed generation. Bumped when the
/// shipped default set changes so untouched installs can migrate once.
const String defaultPresetsSeedVersionKey = 'default_presets_seed_version';
const int defaultPresetsSeedVersion = 3;

/// A dashboard time window (T14) — every insight query is windowed and
/// index-backed (docs/DATA_MODEL.md §8), never a full-table scan, since
/// retention can legitimately keep years of rows around. [today] is the
/// user's LOCAL calendar day (what "today" means to a person looking at a
/// dashboard); [last7Days]/[last30Days] are rolling windows from now, not
/// calendar-aligned — see [IntentStore._windowStart].
enum InsightWindow { today, last7Days, last30Days }

/// Which bucket a declared/no-intent event falls into for the Home donut
/// (T18 assigns labels/colors — see `lib/insights/outcome_donut.dart`'s doc
/// on why the painter itself takes plain `DonutSlice` data, not this type).
enum OutcomeCategory { intentDone, intentAbandoned, noIntent }

/// One bucket's count from [IntentStore.outcomeBreakdown].
class OutcomeCount {
  final OutcomeCategory category;
  final int count;
  const OutcomeCount({required this.category, required this.count});
}

/// Completion-duration stats from [IntentStore.completionDurationStats] —
/// see that method's doc for the median/mean computation and its known
/// simplification (screen-off spans aren't excluded, docs/DATA_MODEL.md §6).
class DurationStats {
  final double medianSeconds;
  final double meanSeconds;
  final int sampleCount;
  const DurationStats({required this.medianSeconds, required this.meanSeconds, required this.sampleCount});
}

/// Repository over the on-device SQLite schema (`unlock_log`, `intent_log`,
/// `intent_preset` — see docs/DATA_MODEL.md for the full ERD and rationale).
/// Reused by BOTH the background engine (the sole writer — see CLAUDE.md §3)
/// and the main UI engine (read-only, for the history/insights screens).
/// Opened in WAL mode so those two isolates' separate connections to the same
/// file can safely read-while-write.
///
/// Every query is parameterized (`?` + whereArgs) — never string-interpolated
/// — so arbitrary user-typed intent text can never be interpreted as SQL.
class IntentStore {
  final Database _db;

  IntentStore._(this._db);

  /// Opens (creating/migrating on first run) the on-device DB. [path] is
  /// injectable so tests can point at an in-memory `sqflite_common_ffi`
  /// database instead of the real on-device file.
  ///
  /// [ownConnection] (→ sqflite `singleInstance: false`) gives this store its
  /// OWN native connection instead of sharing sqflite's default per-path
  /// singleton. The persistent background writer (backgroundMain) uses the
  /// default shared connection; any OTHER isolate opening the SAME file (the
  /// history/insights/settings screens, all in the main UI engine) MUST pass
  /// `ownConnection: true`. Without it, both isolates share ONE connection,
  /// and the second isolate's `close()` on dispose closes the writer's
  /// connection too, so every subsequent background write throws
  /// `DatabaseException(database_closed)` permanently until the process
  /// restarts (confirmed on-device 2026-07-22 — see
  /// docs/debug/sprint3-session-log-2026-07-22.txt). Two independent
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
        await _createV1Schema(db);
        await _migrateV1ToV2(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // A fresh DB (created above) already has the current schema and
        // never reaches here — onUpgrade only runs on a real upgrade from an
        // older on-disk file, i.e. exactly the v0.5.0+7 installs already in
        // the field. Written as a straight-line if-chain (not a switch) so
        // each future bump is one more `if (oldVersion < N)` block, matching
        // the additive-only migration policy in docs/DATA_MODEL.md §11.
        if (oldVersion < 2) {
          await _migrateV1ToV2(db);
        }
      },
    );
    // rawQuery, NOT execute: `PRAGMA journal_mode=WAL` returns a result row
    // (the resulting mode). Android's sqflite backend rejects that via
    // execute() ("Queries can be performed using ... query or rawQuery
    // methods only") — only caught on a real device, since sqflite_common_ffi
    // (used by desktop unit tests) tolerates execute() for this PRAGMA.
    await db.rawQuery('PRAGMA journal_mode=WAL');
    final store = IntentStore._(db);
    await store._ensureDefaultPresetSeed();
    return store;
  }

  /// Once per install: if prefs say we're behind [defaultPresetsSeedVersion]
  /// and the enabled list is exactly a known prior default set (legacy five or
  /// [verbPresetLabelsV2]), soft-delete those rows and re-seed
  /// [defaultPresetLabels]. Customized lists are left alone; only the version
  /// flag advances. See `docs/erd/verb-presets-job-goers-2026-07-25.md`.
  Future<void> _ensureDefaultPresetSeed() async {
    final prefs = SharedPreferencesAsync();
    final version = await prefs.getInt(defaultPresetsSeedVersionKey) ?? 1;
    if (version >= defaultPresetsSeedVersion) return;

    final active = await activePresets();
    final labels = active.map((p) => p.label).toSet();
    // Require unique labels equal to a prior default set (no customs mixed in).
    final matchesPriorDefaults = active.length == labels.length &&
        (_sameLabelSet(labels, legacyDefaultPresetLabels) ||
            _sameLabelSet(labels, verbPresetLabelsV2));
    if (matchesPriorDefaults) {
      final now = DateTime.now().toUtc().millisecondsSinceEpoch;
      for (final preset in active) {
        await _db.update(
          'intent_preset',
          {'deleted_at': now, 'enabled': 0},
          where: 'id = ?',
          whereArgs: [preset.id],
        );
      }
      final seededAt = DateTime.now().toUtc().millisecondsSinceEpoch;
      final batch = _db.batch();
      for (var i = 0; i < defaultPresetLabels.length; i++) {
        batch.insert('intent_preset', {
          'label': defaultPresetLabels[i],
          'sort_order': i,
          'enabled': 1,
          'tier': 'standard',
          'created_at': seededAt,
        });
      }
      await batch.commit(noResult: true);
    }

    await prefs.setInt(defaultPresetsSeedVersionKey, defaultPresetsSeedVersion);
  }

  static bool _sameLabelSet(Set<String> actual, List<String> expected) {
    final want = expected.toSet();
    return actual.length == want.length && actual.containsAll(want);
  }

  static Future<void> _createV1Schema(Database db) async {
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
  }

  /// Schema v1 → v2 (docs/DATA_MODEL.md §11). Entirely additive: no column is
  /// dropped or narrowed, no existing row is rewritten in a way that changes
  /// its meaning. Safe to run on a freshly-created v1 schema (from
  /// [_createV1Schema], same call) or on a real upgrade over a v0.5.0+7
  /// on-disk file.
  static Future<void> _migrateV1ToV2(Database db) async {
    await db.execute('''
      CREATE TABLE unlock_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        unlocked_at INTEGER NOT NULL,
        prompt_shown INTEGER NOT NULL,
        skip_reason TEXT
      )
    ''');
    await db.execute('CREATE INDEX idx_unlocked_at ON unlock_log(unlocked_at)');

    // status: existing rows are all fully-completed dismissals or no_intent
    // admissions written under the old single-insert-at-dismissal model, so
    // 'done' is the correct default for every pre-existing row — no backfill
    // logic needed beyond the column default itself.
    await db.execute("ALTER TABLE intent_log ADD COLUMN status TEXT NOT NULL DEFAULT 'done'");
    await db.execute('ALTER TABLE intent_log ADD COLUMN unlock_id INTEGER');
    await db.execute('ALTER TABLE intent_log ADD COLUMN preset_id INTEGER');
    await db.execute('CREATE INDEX idx_declared_at ON intent_log(declared_at)');

    await db.execute('''
      CREATE TABLE intent_preset (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        label TEXT NOT NULL,
        sort_order INTEGER NOT NULL,
        enabled INTEGER NOT NULL DEFAULT 1,
        deleted_at INTEGER,
        tier TEXT NOT NULL DEFAULT 'standard',
        allowed_packages TEXT,
        created_at INTEGER NOT NULL
      )
    ''');
    final seededAt = DateTime.now().toUtc().millisecondsSinceEpoch;
    final batch = db.batch();
    for (var i = 0; i < defaultPresetLabels.length; i++) {
      batch.insert('intent_preset', {
        'label': defaultPresetLabels[i],
        'sort_order': i,
        'enabled': 1,
        'tier': 'standard',
        'created_at': seededAt,
      });
    }
    await batch.commit(noResult: true);
  }

  Future<void> close() => _db.close();

  // ---------------------------------------------------------------------
  // unlock_log — append-only. See docs/DATA_MODEL.md §2, invariant 1.
  // ---------------------------------------------------------------------

  /// Records one unlock. Called from `_showCaptureScreen` in main.dart
  /// AFTER the prompt-or-skip decision and after `showOverlay()` (if shown)
  /// — never on the hot path before that, and never allowed to block or
  /// suppress the prompt on failure (docs/DATA_MODEL.md §2, invariant 3).
  /// Returns the new row's id, used by [insertOpenIntent] to resolve
  /// `unlock_id` — but callers on the unlock path do NOT need to keep it:
  /// resolution happens by lookup, not by threading this id through
  /// cross-isolate state (docs/DATA_MODEL.md §4).
  Future<int> insertUnlock({
    required DateTime unlockedAt,
    required bool promptShown,
    SkipReason? skipReason,
  }) {
    assert(promptShown != (skipReason != null), 'skipReason must be set iff promptShown is false');
    return _db.insert('unlock_log', {
      'unlocked_at': unlockedAt.toUtc().millisecondsSinceEpoch,
      'prompt_shown': promptShown ? 1 : 0,
      'skip_reason': skipReason == null ? null : _skipReasonToDb(skipReason),
    });
  }

  /// Most recent [limit] unlock rows, newest first. Not used by any screen
  /// yet (that's T14/T18) — exists now so [insertUnlock] is round-trip
  /// testable and so `_skipReasonFromDb` has a real caller.
  Future<List<UnlockEvent>> recentUnlocks({int limit = 50}) async {
    final rows = await _db.query('unlock_log', orderBy: 'unlocked_at DESC', limit: limit);
    return rows
        .map((row) => UnlockEvent(
              id: row['id'] as int,
              unlockedAt: DateTime.fromMillisecondsSinceEpoch(row['unlocked_at'] as int, isUtc: true),
              promptShown: (row['prompt_shown'] as int) == 1,
              skipReason: _skipReasonFromDb(row['skip_reason'] as String?),
            ))
        .toList();
  }

  // ---------------------------------------------------------------------
  // intent_log — declare-time write, dismiss-time update. See
  // docs/DATA_MODEL.md §4 ("status — declaration-time writes").
  // ---------------------------------------------------------------------

  /// Legacy single-shot insert, kept for the "Just Like That" path (an
  /// atomic admission — there is no separate declare/dismiss step to split,
  /// see `_submitNoIntent` in main.dart) and for backward-compatible tests.
  /// Writes directly as `status=done` and resolves `unlock_id` via the same
  /// stateless lookup [insertOpenIntent] uses, so no-intent rows get the
  /// link too. Idempotent on `client_id` (`INSERT OR IGNORE`).
  Future<void> insertEvent(IntentEvent event) async {
    final unlockId = await _resolveUnlockId();
    await _db.insert(
      'intent_log',
      {
        'client_id': event.clientId,
        'kind': _kindToDb(event.kind),
        'source': _sourceToDb(event.source),
        'text': event.text,
        'declared_at': event.declaredAt.millisecondsSinceEpoch,
        'completed_at': event.completedAt.millisecondsSinceEpoch,
        'status': _statusToDb(IntentStatus.done),
        'unlock_id': unlockId,
        'preset_id': event.presetId,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// Writes a declared-intent row at DECLARATION time with `status='open'`
  /// — not at dismissal. This is what stops an intent from being lost
  /// entirely if the process dies before the bubble is dismissed (reboot,
  /// OEM kill — docs/DATA_MODEL.md §6, cases 7/8): the row already exists
  /// and survives as `open`, later swept to `abandoned` by
  /// [sweepOpenToAbandoned] on the next background-engine start.
  ///
  /// `unlock_id` is resolved here via [_resolveUnlockId] — a stateless
  /// lookup, not in-memory correlation (docs/DATA_MODEL.md §4). Idempotent
  /// on `client_id`.
  Future<void> insertOpenIntent(IntentEvent event) async {
    assert(event.kind == IntentKind.intent, 'insertOpenIntent is for declared intents only — use insertEvent for no_intent');
    final unlockId = await _resolveUnlockId();
    await _db.insert(
      'intent_log',
      {
        'client_id': event.clientId,
        'kind': _kindToDb(event.kind),
        'source': _sourceToDb(event.source),
        'text': event.text,
        'declared_at': event.declaredAt.millisecondsSinceEpoch,
        // Placeholder, NOT a real completion time — kept equal to
        // declared_at so the column stays NOT NULL without a table rebuild,
        // and so a cooldown check against a still-open row uses "just
        // engaged" as the reference point (see docs/DATA_MODEL.md §4).
        // Overwritten by markIntentDone on real completion.
        'completed_at': event.declaredAt.millisecondsSinceEpoch,
        'status': _statusToDb(IntentStatus.open),
        'unlock_id': unlockId,
        'preset_id': event.presetId,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// Marks a previously-[insertOpenIntent]'d row as dismissed. Keyed on
  /// `client_id` — a stable, client-generated key, not in-memory state — so
  /// this is safe to call more than once (idempotent: a repeat call with the
  /// same or later [completedAt] is a harmless no-op once already done,
  /// since the WHERE clause only matches rows still `open`).
  Future<void> markIntentDone({
    required String clientId,
    required DateTime completedAt,
  }) async {
    await _db.update(
      'intent_log',
      {
        'completed_at': completedAt.millisecondsSinceEpoch,
        'status': _statusToDb(IntentStatus.done),
      },
      where: 'client_id = ? AND status = ?',
      whereArgs: [clientId, _statusToDb(IntentStatus.open)],
    );
  }

  /// Sweeps any lingering `open` rows to `abandoned`. Call once at
  /// background-engine start (`backgroundMain` in main.dart) — a fresh
  /// engine start means the overlay's cached widget state is gone too, so
  /// any `open` row at that point can no longer be dismissed by the process
  /// that declared it (docs/DATA_MODEL.md §6, cases 7/8).
  Future<int> sweepOpenToAbandoned() {
    return _db.update(
      'intent_log',
      {'status': _statusToDb(IntentStatus.abandoned)},
      where: 'status = ?',
      whereArgs: [_statusToDb(IntentStatus.open)],
    );
  }

  /// Resolves the `unlock_log` row a newly-written intent belongs to: the
  /// most recent row with `prompt_shown=1`. Unambiguous by construction —
  /// while a prompt is showing, subsequent unlocks are skipped as
  /// `overlay_active`, so two prompted unlocks are never adjacent
  /// (docs/DATA_MODEL.md §4). Returns null (never throws) if unresolvable,
  /// e.g. on a fresh DB or if `unlock_log` writes have been failing —  a
  /// null link is a normal, expected outcome, not an error.
  Future<int?> _resolveUnlockId() async {
    final rows = await _db.query(
      'unlock_log',
      columns: ['id'],
      where: 'prompt_shown = 1',
      orderBy: 'unlocked_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['id'] as int;
  }

  /// Most recent `completed_at` across ALL events (intent or no-intent) —
  /// the input the cooldown policy needs. Deliberately includes `open` and
  /// `abandoned` rows too: an open row's `completed_at` placeholder equals
  /// `declared_at`, i.e. "the user just engaged," which is exactly what the
  /// cooldown should measure from (docs/DATA_MODEL.md §4). Null on an empty
  /// log (never prompted before → no floor to apply).
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
    return rows.map(_intentEventFromRow).toList();
  }

  IntentEvent _intentEventFromRow(Map<String, Object?> row) => IntentEvent(
        clientId: row['client_id'] as String,
        kind: _kindFromDb(row['kind'] as String),
        source: _sourceFromDb(row['source'] as String?),
        text: row['text'] as String,
        declaredAt: DateTime.fromMillisecondsSinceEpoch(row['declared_at'] as int, isUtc: true),
        completedAt: DateTime.fromMillisecondsSinceEpoch(row['completed_at'] as int, isUtc: true),
        status: _statusFromDb((row['status'] as String?) ?? 'done'),
        presetId: row['preset_id'] as int?,
        unlockId: row['unlock_id'] as int?,
      );

  // ---------------------------------------------------------------------
  // Insight queries (T14) — windowed counts, outcome breakdown, and
  // SQL-computed completion-duration stats feeding the Home screen's cards
  // (T18) and donut (T15). See docs/DATA_MODEL.md §6/§8 for the metric
  // honesty and windowing/indexing rules these follow.
  // ---------------------------------------------------------------------

  /// Inclusive lower boundary for [window], as a UTC instant — every stored
  /// timestamp is UTC epoch ms, so the conversion happens here, once, rather
  /// than at every call site. [InsightWindow.today] is LOCAL midnight
  /// (what a user means by "today"), converted to UTC; the rolling windows
  /// are relative to [now], not calendar-aligned. [now] is injectable for
  /// tests; defaults to the real current time.
  DateTime _windowStart(InsightWindow window, DateTime now) {
    switch (window) {
      case InsightWindow.today:
        return DateTime(now.year, now.month, now.day).toUtc();
      case InsightWindow.last7Days:
        return now.toUtc().subtract(const Duration(days: 7));
      case InsightWindow.last30Days:
        return now.toUtc().subtract(const Duration(days: 30));
    }
  }

  /// Total unlocks in [window] — every `unlock_log` row regardless of
  /// outcome. Per docs/DATA_MODEL.md §6, this is a FLOOR not a truth when
  /// the service has been dead, but it's still the correct count of what
  /// WAS observed; the Home card should label it accordingly, not this query.
  Future<int> unlockCount({required InsightWindow window, DateTime? now}) async {
    final since = _windowStart(window, now ?? DateTime.now());
    final rows = await _db.rawQuery(
      'SELECT COUNT(*) AS n FROM unlock_log WHERE unlocked_at >= ?',
      [since.millisecondsSinceEpoch],
    );
    return Sqflite.firstIntValue(rows) ?? 0;
  }

  /// Prompts actually shown in [window] — the numerator for a "prompt rate"
  /// against [unlockCount]'s denominator.
  Future<int> promptShownCount({required InsightWindow window, DateTime? now}) async {
    final since = _windowStart(window, now ?? DateTime.now());
    final rows = await _db.rawQuery(
      'SELECT COUNT(*) AS n FROM unlock_log WHERE unlocked_at >= ? AND prompt_shown = 1',
      [since.millisecondsSinceEpoch],
    );
    return Sqflite.firstIntValue(rows) ?? 0;
  }

  /// Outcome breakdown for the Home donut — returns plain counts per
  /// [OutcomeCategory]; T18 assigns labels/colors when building
  /// `DonutSlice`s (see that class's doc for why the painter itself has no
  /// `IntentStore` dependency). Windowed on `declared_at` (when the user
  /// engaged), not `completed_at`, so an intent declared inside the window
  /// but only dismissed/abandoned later still counts toward the window it
  /// was DECLARED in — the natural reading of "what happened today."
  Future<List<OutcomeCount>> outcomeBreakdown({required InsightWindow window, DateTime? now}) async {
    final since = _windowStart(window, now ?? DateTime.now());
    final rows = await _db.rawQuery(
      '''
      SELECT kind, status, COUNT(*) AS n
      FROM intent_log
      WHERE declared_at >= ?
      GROUP BY kind, status
      ''',
      [since.millisecondsSinceEpoch],
    );
    return rows.map((row) {
      final kind = _kindFromDb(row['kind'] as String);
      final status = _statusFromDb((row['status'] as String?) ?? 'done');
      final category = kind == IntentKind.noIntent
          ? OutcomeCategory.noIntent
          : (status == IntentStatus.abandoned ? OutcomeCategory.intentAbandoned : OutcomeCategory.intentDone);
      return OutcomeCount(category: category, count: row['n'] as int);
    }).toList();
  }

  /// Completion-duration stats (median headline, mean secondary — see
  /// docs/DATA_MODEL.md §6 and plan §6: Home labels this "Time to mark done"
  /// because it is time-until-dismissed, not task completion) over
  /// `kind='intent' AND status='done'`
  /// rows DECLARED within [window]. `no_intent` ("Just Like That") rows are
  /// always written with `completed_at == declared_at` (zero duration) and
  /// must not drag median/mean down. Null on zero matching rows — a real
  /// "not enough data yet" state, never a fabricated zero duration.
  ///
  /// Median is computed exactly per docs/DATA_MODEL.md §8's decision: COUNT
  /// first, then a single `ORDER BY ... LIMIT 1 OFFSET n ~/ 2` query — one
  /// middle row, not an averaged pair on an even count. Deliberately simple:
  /// this is a directional headline metric, not a statistic anyone audits
  /// to the second.
  ///
  /// **Known simplification, not solved here:** does not exclude intents
  /// whose open period spanned a screen-off, which docs/DATA_MODEL.md §6
  /// treats as an ideal — the schema has no persisted lock-event table to
  /// detect that from (`onLock` in main.dart is logged via `debugPrint`
  /// only, never written to a table), so there's nothing to join against.
  Future<DurationStats?> completionDurationStats({required InsightWindow window, DateTime? now}) async {
    final since = _windowStart(window, now ?? DateTime.now());
    final countRows = await _db.rawQuery(
      '''
      SELECT COUNT(*) AS n, AVG(completed_at - declared_at) AS mean_ms
      FROM intent_log
      WHERE kind = ? AND status = ? AND declared_at >= ?
      ''',
      [_kindToDb(IntentKind.intent), _statusToDb(IntentStatus.done), since.millisecondsSinceEpoch],
    );
    final n = Sqflite.firstIntValue(countRows) ?? 0;
    if (n == 0) return null;
    final meanMs = (countRows.first['mean_ms'] as num).toDouble();

    final medianRows = await _db.rawQuery(
      '''
      SELECT (completed_at - declared_at) AS duration_ms
      FROM intent_log
      WHERE kind = ? AND status = ? AND declared_at >= ?
      ORDER BY duration_ms
      LIMIT 1 OFFSET ?
      ''',
      [_kindToDb(IntentKind.intent), _statusToDb(IntentStatus.done), since.millisecondsSinceEpoch, n ~/ 2],
    );
    final medianMs = (medianRows.first['duration_ms'] as num).toDouble();

    return DurationStats(
      medianSeconds: medianMs / 1000,
      meanSeconds: meanMs / 1000,
      sampleCount: n,
    );
  }

  // ---------------------------------------------------------------------
  // intent_preset — user-editable capture-screen pills. See
  // docs/DATA_MODEL.md §4 ("preset_id alongside text") and §7 (limits).
  // ---------------------------------------------------------------------

  /// Presets available to show on the capture screen: enabled, not deleted,
  /// ordered for display. This is the exact set relayed to the overlay
  /// isolate (docs/DATA_MODEL.md §7 — only enabled/non-deleted presets are
  /// sent; the overlay never needs the full library).
  Future<List<IntentPreset>> activePresets() async {
    final rows = await _db.query(
      'intent_preset',
      where: 'enabled = 1 AND deleted_at IS NULL',
      orderBy: 'sort_order ASC',
    );
    return rows.map(_presetFromRow).toList();
  }

  /// All stored presets (including disabled/soft-deleted) for the manage
  /// screen.
  Future<List<IntentPreset>> allPresets() async {
    final rows = await _db.query('intent_preset', orderBy: 'sort_order ASC');
    return rows.map(_presetFromRow).toList();
  }

  IntentPreset _presetFromRow(Map<String, Object?> row) => IntentPreset(
        id: row['id'] as int,
        label: row['label'] as String,
        sortOrder: row['sort_order'] as int,
        enabled: (row['enabled'] as int) == 1,
        deletedAt: row['deleted_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(row['deleted_at'] as int, isUtc: true),
        tier: (row['tier'] as String?) ?? 'standard',
        allowedPackages: row['allowed_packages'] as String?,
        createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int, isUtc: true),
      );

  /// Creates a new preset at the end of the sort order. Throws
  /// [PresetLimitExceeded] past [maxStoredPresets] total or
  /// [presetLabelMaxLength] chars — enforced here rather than as a DB
  /// constraint (a row-count cap isn't expressible in SQLite without a
  /// trigger, and an app-level check can return a usable message;
  /// docs/DATA_MODEL.md §7). A new preset is enabled by default; if that
  /// would exceed [maxEnabledPresets] the caller should catch and either
  /// disable another preset first or create it disabled — this method does
  /// not silently choose.
  Future<int> createPreset(String label) async {
    final trimmed = label.trim();
    if (trimmed.isEmpty) {
      throw const PresetLimitExceeded('Label cannot be empty');
    }
    if (trimmed.length > presetLabelMaxLength) {
      throw PresetLimitExceeded('Label exceeds $presetLabelMaxLength characters');
    }
    // Counts NON-DELETED rows only. Soft-deleted presets are invisible to
    // both the manage screen and the relay payload, which is what this cap
    // exists to bound (docs/DATA_MODEL.md §7) — counting them would mean a
    // user who repeatedly creates and deletes presets permanently exhausts
    // the cap and can never create another, since soft-delete never removes
    // the row.
    final totalRow = Sqflite.firstIntValue(
      await _db.rawQuery('SELECT COUNT(*) FROM intent_preset WHERE deleted_at IS NULL'),
    );
    if ((totalRow ?? 0) >= maxStoredPresets) {
      throw PresetLimitExceeded('Cannot store more than $maxStoredPresets presets');
    }
    final enabledCount = Sqflite.firstIntValue(
      await _db.rawQuery('SELECT COUNT(*) FROM intent_preset WHERE enabled = 1 AND deleted_at IS NULL'),
    );
    if ((enabledCount ?? 0) >= maxEnabledPresets) {
      throw PresetLimitExceeded('Cannot enable more than $maxEnabledPresets presets at once');
    }
    final maxOrderRow = Sqflite.firstIntValue(await _db.rawQuery('SELECT MAX(sort_order) FROM intent_preset'));
    final nextOrder = (maxOrderRow ?? -1) + 1;
    return _db.insert('intent_preset', {
      'label': trimmed,
      'sort_order': nextOrder,
      'enabled': 1,
      'tier': 'standard',
      'created_at': DateTime.now().toUtc().millisecondsSinceEpoch,
    });
  }

  /// Renames a preset. Unrestricted — see docs/DATA_MODEL.md §4: blocking
  /// edits to protect analytics is backwards, and history keeps the old
  /// label regardless (via the `text` snapshot on `intent_log`), so a rename
  /// here cannot falsify past records.
  Future<void> renamePreset(int id, String newLabel) async {
    final trimmed = newLabel.trim();
    if (trimmed.isEmpty) {
      throw const PresetLimitExceeded('Label cannot be empty');
    }
    if (trimmed.length > presetLabelMaxLength) {
      throw PresetLimitExceeded('Label exceeds $presetLabelMaxLength characters');
    }
    await _db.update('intent_preset', {'label': trimmed}, where: 'id = ?', whereArgs: [id]);
  }

  /// Enables or disables a preset. Enabling past [maxEnabledPresets] throws
  /// [PresetLimitExceeded] rather than silently refusing — the caller (the
  /// manage-presets UI) is expected to show this as a clear error, per
  /// docs/DATA_MODEL.md §7.
  Future<void> setPresetEnabled(int id, bool enabled) async {
    if (enabled) {
      final enabledCount = Sqflite.firstIntValue(
        await _db.rawQuery('SELECT COUNT(*) FROM intent_preset WHERE enabled = 1 AND deleted_at IS NULL AND id != ?', [id]),
      );
      if ((enabledCount ?? 0) >= maxEnabledPresets) {
        throw PresetLimitExceeded('Cannot enable more than $maxEnabledPresets presets at once');
      }
    }
    await _db.update('intent_preset', {'enabled': enabled ? 1 : 0}, where: 'id = ?', whereArgs: [id]);
  }

  /// Soft-deletes a preset (sets `deleted_at`), hiding it from the capture
  /// screen while keeping it resolvable via `preset_id` for historical rows.
  /// A hard delete would orphan those references — see docs/DATA_MODEL.md §4.
  Future<void> deletePreset(int id) async {
    await _db.update(
      'intent_preset',
      {'deleted_at': DateTime.now().toUtc().millisecondsSinceEpoch, 'enabled': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Rewrites `sort_order` to be contiguous (0…n−1) in the given id order.
  /// Simpler to reason about than gap-based ordering at this row count
  /// (≤[maxStoredPresets]) — see docs/DATA_MODEL.md §7.
  Future<void> reorderPresets(List<int> idsInOrder) async {
    final batch = _db.batch();
    for (var i = 0; i < idsInOrder.length; i++) {
      batch.update('intent_preset', {'sort_order': i}, where: 'id = ?', whereArgs: [idsInOrder[i]]);
    }
    await batch.commit(noResult: true);
  }

  /// Soft-deletes every existing preset and re-seeds [defaultPresetLabels] —
  /// the "restore defaults" safety net for a user who has disabled or deleted
  /// every preset (docs/DATA_MODEL.md §7: the minimum enabled count is
  /// deliberately zero, so this is the recovery path, not a forced floor).
  ///
  /// Soft-deletes rather than hard-deletes for the same reason
  /// [deletePreset] does: a hard delete would orphan every `intent_log.
  /// preset_id` pointing at the old rows, silently breaking the historical
  /// series that column exists to preserve across edits. The old rows stay
  /// resolvable; they're just invisible to the capture screen and manage
  /// list.
  Future<void> restoreDefaultPresets() async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await _db.update(
      'intent_preset',
      {'deleted_at': now, 'enabled': 0},
      where: 'deleted_at IS NULL',
    );
    final seededAt = DateTime.now().toUtc().millisecondsSinceEpoch;
    final batch = _db.batch();
    for (var i = 0; i < defaultPresetLabels.length; i++) {
      batch.insert('intent_preset', {
        'label': defaultPresetLabels[i],
        'sort_order': i,
        'enabled': 1,
        'tier': 'standard',
        'created_at': seededAt,
      });
    }
    await batch.commit(noResult: true);
  }

  // ---------------------------------------------------------------------
  // Export (T17) — lossless CSV source rows. See docs/DATA_MODEL.md §9.
  // ---------------------------------------------------------------------

  /// Every unlock (LEFT JOIN intent + preset for outcome columns), then any
  /// orphan intents (`unlock_id IS NULL`) with unlock columns blank — nothing
  /// is silently dropped. Order: unlocks by `unlocked_at` ascending, then
  /// orphans by `declared_at` ascending. Soft-deleted presets still resolve
  /// by `preset_id` for `preset_label` (docs/DATA_MODEL.md §4).
  Future<List<ExportRow>> exportRows() async {
    final unlockRows = await _db.rawQuery('''
      SELECT
        u.unlocked_at AS unlocked_at,
        u.prompt_shown AS prompt_shown,
        u.skip_reason AS skip_reason,
        i.text AS intent_text,
        i.kind AS intent_kind,
        i.source AS intent_source,
        p.label AS preset_label,
        i.preset_id AS preset_id,
        i.declared_at AS declared_at,
        i.completed_at AS completed_at,
        i.status AS status
      FROM unlock_log u
      LEFT JOIN intent_log i ON i.unlock_id = u.id
      LEFT JOIN intent_preset p ON p.id = i.preset_id
      ORDER BY u.unlocked_at ASC, u.id ASC
    ''');

    final orphanRows = await _db.rawQuery('''
      SELECT
        NULL AS unlocked_at,
        NULL AS prompt_shown,
        NULL AS skip_reason,
        i.text AS intent_text,
        i.kind AS intent_kind,
        i.source AS intent_source,
        p.label AS preset_label,
        i.preset_id AS preset_id,
        i.declared_at AS declared_at,
        i.completed_at AS completed_at,
        i.status AS status
      FROM intent_log i
      LEFT JOIN intent_preset p ON p.id = i.preset_id
      WHERE i.unlock_id IS NULL
      ORDER BY i.declared_at ASC, i.id ASC
    ''');

    return [...unlockRows, ...orphanRows].map(_exportRowFromQuery).toList();
  }

  static ExportRow _exportRowFromQuery(Map<String, Object?> row) {
    final unlockedMs = row['unlocked_at'] as int?;
    final declaredMs = row['declared_at'] as int?;
    final completedMs = row['completed_at'] as int?;
    final promptShownRaw = row['prompt_shown'] as int?;

    int? durationSeconds;
    if (declaredMs != null && completedMs != null) {
      durationSeconds = ((completedMs - declaredMs) / 1000).round();
    }

    return ExportRow(
      unlockedAt: unlockedMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(unlockedMs, isUtc: true),
      promptShown: promptShownRaw == null ? null : promptShownRaw == 1,
      skipReason: row['skip_reason'] as String?,
      intentText: row['intent_text'] as String?,
      intentKind: row['intent_kind'] as String?,
      intentSource: row['intent_source'] as String?,
      presetLabel: row['preset_label'] as String?,
      presetId: row['preset_id'] as int?,
      declaredAt: declaredMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(declaredMs, isUtc: true),
      completedAt: completedMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(completedMs, isUtc: true),
      durationSeconds: durationSeconds,
      status: row['status'] as String?,
    );
  }

  // ---------------------------------------------------------------------
  // Your data (T18) — counts, oldest record, delete/prune. Presets are
  // configuration, not event history: wipe/prune never touch intent_preset
  // (docs/DATA_MODEL.md §8).
  // ---------------------------------------------------------------------

  /// All-time unlock + intent row counts for the Settings "Your data" card.
  /// Deliberately unwindowed — retention disclosure needs the full store
  /// size, not today's slice.
  Future<UserDataCounts> userDataCounts() async {
    final unlockRows = await _db.rawQuery('SELECT COUNT(*) AS n FROM unlock_log');
    final intentRows = await _db.rawQuery('SELECT COUNT(*) AS n FROM intent_log');
    return UserDataCounts(
      unlockCount: Sqflite.firstIntValue(unlockRows) ?? 0,
      intentCount: Sqflite.firstIntValue(intentRows) ?? 0,
    );
  }

  /// Earliest timestamp across unlocks (`unlocked_at`) and intents
  /// (`declared_at`), or null when both tables are empty.
  Future<DateTime?> oldestRecordAt() async {
    final rows = await _db.rawQuery('''
      SELECT MIN(ts) AS oldest FROM (
        SELECT unlocked_at AS ts FROM unlock_log
        UNION ALL
        SELECT declared_at AS ts FROM intent_log
      )
    ''');
    final ms = Sqflite.firstIntValue(rows);
    if (ms == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  }

  /// Deletes every unlock and intent row. Keeps `intent_preset` (labels the
  /// user curated). No `VACUUM` — free pages are reused (docs/DATA_MODEL.md §8).
  Future<void> deleteAllUserData() async {
    final batch = _db.batch();
    batch.delete('intent_log');
    batch.delete('unlock_log');
    await batch.commit(noResult: true);
  }

  /// One-shot prune: removes unlocks with `unlocked_at` before [cutoff] and
  /// intents with `declared_at` before [cutoff]. Returns how many rows were
  /// deleted across both tables. Does not touch presets; no `VACUUM`.
  Future<int> pruneOlderThan(DateTime cutoff) async {
    final ms = cutoff.toUtc().millisecondsSinceEpoch;
    final intentDeleted = await _db.delete(
      'intent_log',
      where: 'declared_at < ?',
      whereArgs: [ms],
    );
    final unlockDeleted = await _db.delete(
      'unlock_log',
      where: 'unlocked_at < ?',
      whereArgs: [ms],
    );
    return intentDeleted + unlockDeleted;
  }
}

/// All-time event counts for the Settings "Your data" card (T18).
class UserDataCounts {
  final int unlockCount;
  final int intentCount;

  const UserDataCounts({required this.unlockCount, required this.intentCount});

  int get totalEvents => unlockCount + intentCount;
}

/// One lossless CSV export row (docs/DATA_MODEL.md §9). Timestamps are UTC
/// instants; [formatExportCsv] converts them to ISO-8601 local for the file.
class ExportRow {
  final DateTime? unlockedAt;
  final bool? promptShown;
  final String? skipReason;
  final String? intentText;
  final String? intentKind;
  final String? intentSource;
  final String? presetLabel;
  final int? presetId;
  final DateTime? declaredAt;
  final DateTime? completedAt;
  final int? durationSeconds;
  final String? status;

  const ExportRow({
    this.unlockedAt,
    this.promptShown,
    this.skipReason,
    this.intentText,
    this.intentKind,
    this.intentSource,
    this.presetLabel,
    this.presetId,
    this.declaredAt,
    this.completedAt,
    this.durationSeconds,
    this.status,
  });
}
