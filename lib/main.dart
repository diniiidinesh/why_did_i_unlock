import 'dart:async';
import 'dart:isolate';
import 'dart:math';
import 'dart:ui' show IsolateNameServer;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

import 'app_settings.dart';
import 'history_screen.dart';
import 'intent_store.dart';
import 'prompt_policy.dart';

/// A preset as rendered on the capture screen — just the fields
/// [IntentCaptureScreen] needs (id + label), not the full `IntentPreset`
/// from `intent_store.dart` (which also carries sort_order/enabled/
/// deletedAt/tier/allowedPackages — all background-only concerns already
/// applied before this is ever constructed: only active presets, already in
/// display order, ever become a `CapturePreset`). This is the replacement
/// for the old hardcoded `intentPresets` constant — presets are now
/// DB-backed and relayed to the overlay isolate on demand (see
/// docs/DATA_MODEL.md §4, "config relay").
///
/// Public (not `_`-prefixed) specifically so widget tests can construct
/// sample presets to inject via [IntentCaptureScreen]'s constructor — a
/// private type here couldn't be named from a test file, which is a
/// different library.
class CapturePreset {
  final int id;
  final String label;
  const CapturePreset({required this.id, required this.label});
}

/// Label for the honest "no real reason" option. Deliberately NOT a plain
/// "Skip" — it still logs (see [_OverlayRootState._submitNoIntent]), just
/// without forcing a fake intent or showing a bubble. A too-easy bypass would
/// undercut the whole friction mechanic; this keeps the friction while being
/// honest about habitual/purposeless unlocks (itself useful signal).
const String noIntentLabel = 'Just Like That';

/// Max characters accepted by the custom-intent text field. Kept as a named
/// constant so raising or lowering the limit later is a one-line change.
const int intentMaxInputLength = 100;

/// Collapsed bubble (pill) size in logical pixels (dp). NOTE: the plugin's
/// showOverlay() treats width/height as raw *device pixels*, not dp, so these
/// are multiplied by devicePixelRatio at call time (see _submitIntent).
const double _bubbleWidthDp = 200;
const double _bubbleHeightDp = 56;

/// Platform channel shared by native → Dart unlock/lock notifications.
/// The handler is installed by [backgroundMain] (the persistent background
/// engine), NOT by the main UI — see the architecture note on backgroundMain.
const MethodChannel _unlockChannel = MethodChannel('com.whydidiunlock/unlock');

/// Single, isolate-safe access point for every stored setting (prompts
/// on/off, cooldown, probability, quiet hours — see `lib/app_settings.dart`).
/// Stateless and cheap to construct (every method opens a fresh
/// `SharedPreferencesAsync` internally, never a cached instance — see that
/// file's class doc for why a cached copy is a real, previously-hit bug when
/// a setting is written from the main UI engine and read from this
/// persistent background engine's separate isolate). One shared `const`
/// instance rather than `AppSettings()` at every call site purely for
/// readability; it carries no state to share.
const AppSettings _appSettings = AppSettings();

final Random _clientIdRandom = Random();

/// Generates a client-side event id at declare/no-intent time (in the
/// overlay isolate, which has no plugins registered and therefore no access
/// to any platform-backed id source). Only needs to be practically
/// collision-free for one device's local idempotency dedup, not globally
/// unique — declared_at ms + a random suffix is enough for that.
String _generateClientId(DateTime declaredAt) {
  return '${declaredAt.millisecondsSinceEpoch}-${_clientIdRandom.nextInt(1 << 32)}';
}

IntentSource _intentSourceFromString(String source) {
  return source == 'preset' ? IntentSource.preset : IntentSource.custom;
}

void main() {
  runApp(const MyApp());
}

/// Headless entry point for the PERSISTENT BACKGROUND ENGINE.
///
/// This runs in its own Flutter engine hosted by `UnlockListenerService`
/// (native), which the foreground service keeps alive independently of any
/// Activity. That's the whole point: `MainActivity`'s engine is destroyed when
/// the user swipes the app out of Recents, so the unlock-reaction logic must
/// NOT live there — it lives here, where it survives task removal. This engine
/// has `flutter_overlay_window` registered (auto-registered natively), so it
/// can call showOverlay(); the overlay engine itself cannot (no plugins on it).
/// See docs/ARCHITECTURE.md for the full engine topology.
/// The Sprint 3 write path's DB handle. Opened once, lazily, by
/// [backgroundMain] (this engine is the sole writer — see CLAUDE.md §3 /
/// ARCHITECTURE.md). Nullable because opening is async and must not block
/// (or be raced by) the unlock method-channel handler registration below;
/// [_showCaptureScreen]'s cooldown check (wired in a later step) treats a
/// still-null store as "no prior event" and allows the prompt.
IntentStore? _intentStore;

/// Name for a same-process `IsolateNameServer` port used to relay
/// completed-intent events from the overlay isolate to THIS persistent
/// background isolate — see [backgroundMain] / the overlay's `_dismissBubble`
/// and `_submitNoIntent`.
///
/// This REPLACES flutter_overlay_window's `shareData()`/`overlayListener`
/// bridge, which was found (on-device, 2026-07-22 — see
/// docs/debug/sprint3-session-log-2026-07-22.txt) to silently drop every
/// write after the first one in a process's lifetime. Root cause, confirmed
/// against the plugin's native source: that bridge routes through a single
/// static native field (`WindowSetup.messenger`) set by whichever *engine*
/// last called the plugin's `onAttachedToEngine` — including the ephemeral
/// main UI engine. Opening the app (e.g. to view the History screen) makes
/// the main UI engine attach the plugin and steal that static field; once
/// its `FlutterJNI` later detaches, every subsequent `shareData()` call
/// targets a dead engine and is dropped with a native-only log warning
/// (`FlutterJNI was detached from native C++`) — invisible to Dart, no
/// exception, no rejected Future.
///
/// `IsolateNameServer` ports are pure Dart, same-process, and registered
/// ONLY by this isolate — the main UI engine's lifecycle can't hijack or
/// kill the target, because there IS no "which engine owns this" ambiguity
/// like the plugin's single static field has. `SendPort.send()` is also
/// inherently synchronous/fire-and-forget, so the earlier "never await
/// shareData()" gotcha (CLAUDE.md §3) doesn't exist for this transport —
/// there's no reply to await in the first place.
const String _intentWritePortName = 'com.whydidiunlock.intent_write_port';

/// Low-level send over the intent-write port (see [_intentWritePortName]).
/// Looked up fresh on every call (not cached) since the background engine's
/// port is only guaranteed to exist once `backgroundMain` has actually run —
/// cheap process-local lookup, not a platform channel call, so there's no
/// cost to avoid caching. `SendPort.send()` is synchronous and
/// fire-and-forget by construction — no reply to await, so no `unawaited()`
/// needed here (unlike the `shareData()` call this transport replaced).
///
/// Three typed wrappers below (`_relayDeclaredIntent` /
/// `_relayDismissal` / `_relayNoIntent`) are the only callers — each tags its
/// message with a `type` field so `backgroundMain`'s listener knows which
/// [IntentStore] method to call, since the three shapes need different
/// handling (see docs/DATA_MODEL.md §4 on why declaration and dismissal are
/// separate writes now, not one).
void _sendToBackground(Map<String, dynamic> message) {
  final port = IsolateNameServer.lookupPortByName(_intentWritePortName);
  if (port == null) {
    debugPrint('⚠️ Could not find intent-write port — background engine not ready? Message dropped: $message');
    return;
  }
  port.send(message);
}

/// Relayed from `_submitIntent` at DECLARATION time — creates the `open` row
/// (via `IntentStore.insertOpenIntent` in the listener). This is what makes
/// an intent survive a process death before it's dismissed: the row already
/// exists the moment the user declares it, not only once they dismiss the
/// bubble. See docs/DATA_MODEL.md §4.
void _relayDeclaredIntent(IntentEvent event) {
  _sendToBackground({...event.toMessage(), 'type': 'declare'});
}

/// Relayed from `_dismissBubble` at DISMISSAL time — marks the existing
/// `open` row `done` (via `IntentStore.markIntentDone`). Deliberately a
/// minimal [IntentDismissal], not a full event — see that class's doc.
void _relayDismissal(IntentDismissal dismissal) {
  _sendToBackground({...dismissal.toMessage(), 'type': 'dismiss'});
}

/// Relayed from `_submitNoIntent` — an atomic admission with no separate
/// declare/dismiss step (via `IntentStore.insertEvent`, unchanged from
/// Sprint 3). See that method's doc for why "Just Like That" doesn't go
/// through the open/done lifecycle the other two message types do.
void _relayNoIntent(IntentEvent event) {
  _sendToBackground({...event.toMessage(), 'type': 'noIntent'});
}

/// Handles the `requestPresets` message (see the `intentWritePort.listen`
/// switch): fetches the currently-active presets and sends them to the
/// overlay isolate's reply port (see [_overlayConfigPortName]). Called from
/// the background isolate, which — unlike the overlay isolate — has full
/// plugin access and can call [IntentStore] directly; the whole reason this
/// relay exists is that the overlay isolate cannot.
///
/// Sends the minimal [CapturePreset] shape (id + label only), not the full
/// `IntentPreset` row — sort_order/enabled/deletedAt/tier/allowedPackages
/// are all resolved here, server-side, by calling `activePresets()` (already
/// filtered to enabled+non-deleted, already ordered): the overlay never
/// needs to know about disabled or soft-deleted presets at all.
///
/// If the overlay's reply port isn't found (e.g. a request arrived before
/// `_OverlayRootState.initState` finished registering it — shouldn't happen
/// given the ordering in that method, but not fatal if it somehow did), this
/// just logs and returns: the overlay's own request is what matters for
/// retry, not this side re-attempting delivery.
Future<void> _replyActivePresetsToOverlay(IntentStore store) async {
  final presets = await _withTimeout('IntentStore.activePresets()', store.activePresets());
  final payload = (presets ?? const [])
      .map((p) => {'id': p.id, 'label': p.label})
      .toList();
  final port = IsolateNameServer.lookupPortByName(_overlayConfigPortName);
  if (port == null) {
    debugPrint('⚠️ Could not find overlay-config reply port — overlay not ready yet? Presets dropped');
    return;
  }
  port.send({'presets': payload});
  debugPrint('📤 Sent ${payload.length} preset(s) to overlay');
}

/// Name for a second same-process port: the overlay isolate signals THIS
/// isolate whenever it fully closes (dismiss / "Just Like That" — NOT the
/// close+reopen resize inside `_submitIntent`, which is still "active").
///
/// Replaces `FlutterOverlayWindow.isActive()`, which was found (on-device,
/// 2026-07-22 — see docs/debug/sprint3-session-log-2026-07-22.txt) to hang
/// in native code after the app had been opened once, in a way a Dart-level
/// `.timeout()` could not catch (the hang is below the Dart await, inside
/// the plugin's native platform-channel handling) — same root class as the
/// shareData() bug above: the ephemeral main UI engine attaching the plugin
/// disrupts state the background engine depends on. We now track "is the
/// overlay showing" ourselves instead of asking the plugin.
const String _overlayClosedPortName = 'com.whydidiunlock.overlay_closed_port';

/// True from the moment `_showCaptureScreen` calls `showOverlay()` until the
/// overlay isolate signals it fully closed. Lives in the background isolate
/// (the only place that reads it, in `_showCaptureScreen`); set true
/// synchronously BEFORE the `showOverlay()` await (not after) to close the
/// race where a second `onUnlock` could arrive while the first is still
/// awaiting that call.
bool _overlayIsActive = false;

/// Called from the overlay isolate right after a REAL `closeOverlay()` (i.e.
/// dismiss or "Just Like That" — not the close+reopen resize in
/// `_submitIntent`, which must NOT report closed). Mirrors [_relayIntentEvent]:
/// looked up fresh, not cached; `send()` is synchronous/fire-and-forget.
void _signalOverlayClosed() {
  final port = IsolateNameServer.lookupPortByName(_overlayClosedPortName);
  if (port == null) {
    debugPrint('⚠️ Could not find overlay-closed port — background engine not ready?');
    return;
  }
  port.send(true);
}

/// Name for a THIRD same-process port, direction reversed from the other
/// two: main UI engine → background engine. Backs the Status screen's
/// "show me the prompt now" button (T6) — a tester's way to verify the app
/// actually works without waiting for a real unlock.
///
/// This has to be relayed to the background isolate rather than the Status
/// screen calling `FlutterOverlayWindow.showOverlay()` directly, because
/// `_overlayIsActive` is a plain background-isolate variable, not shared
/// state — a direct call from the main engine would leave it `false` while
/// a real overlay is actually showing, so the very next real unlock would
/// try to show a second one on top of it. Routing through the background
/// isolate means the manual trigger goes through the exact same
/// `_overlayIsActive` guard a real unlock does.
const String _manualPromptPortName = 'com.whydidiunlock.manual_prompt_port';

/// Name for a FOURTH same-process port, registered by the OVERLAY isolate
/// itself (not by `backgroundMain`, unlike the other three) — background →
/// overlay, carrying the reply to a `requestPresets` message (see the
/// `intentWritePort.listen` switch's `'requestPresets'` case). This is the
/// first port this file registers from the overlay side rather than just
/// looking one up; symmetric with the existing lookup-only usage and backed
/// by the same pure-Dart, same-process mechanism, so no new risk class —
/// still worth an explicit on-device check (docs/TEST_PLAN.md) precisely
/// because it's a first, not because there's a specific reason to distrust it.
///
/// **Pull, not push** — the overlay isolate requests config (over the
/// existing `_intentWritePortName`, reusing that channel rather than adding
/// a second overlay→background port) and background replies here.
/// Deliberately not the other way around: a push right after `showOverlay()`
/// would race the overlay engine's cold start on the very first show, since
/// the overlay's reply port can't exist to receive anything before its own
/// isolate has run far enough to register it. Making the late party (the
/// overlay) the requester eliminates the race outright instead of papering
/// over it with an artificial delay. See docs/DATA_MODEL.md §4.
const String _overlayConfigPortName = 'com.whydidiunlock.overlay_config_port';

/// Called from the MAIN UI ENGINE (the Status screen, T6) — the only
/// function in this file callable directly from outside it, since Status
/// lives in a different file/screen and needs a real entry point rather
/// than plumbing through `main.dart`'s internals.
///
/// [screenWidth]/[screenHeight] must be the TRUE display size in raw device
/// pixels (e.g. `MediaQuery.of(context).size * MediaQuery.of(context).devicePixelRatio`,
/// rounded). Unlike the real unlock path, the main UI engine CAN read its
/// own display metrics directly (it has an actual UI), so there's no need
/// to fall back on a native-provided value the way the headless background
/// engine does.
void triggerCapturePromptManually({required int screenWidth, required int screenHeight}) {
  final port = IsolateNameServer.lookupPortByName(_manualPromptPortName);
  if (port == null) {
    debugPrint('⚠️ Could not find manual-prompt port — background engine not ready?');
    return;
  }
  port.send({'screenWidth': screenWidth, 'screenHeight': screenHeight});
}

@pragma("vm:entry-point")
void backgroundMain() {
  WidgetsFlutterBinding.ensureInitialized();

  // Registered synchronously, before any async work, so the overlay isolate
  // can always find this port once backgroundMain has started running.
  // Cleared first because a START_STICKY service restart re-runs this entry
  // point, and a name can only map to one port at a time — without this, a
  // restart would throw registering a name that's still mapped to the
  // now-dead previous engine's port.
  IsolateNameServer.removePortNameMapping(_intentWritePortName);
  final intentWritePort = ReceivePort();
  IsolateNameServer.registerPortWithName(intentWritePort.sendPort, _intentWritePortName);

  // Same reasoning as intentWritePort above, for the overlay-closed signal
  // that replaces FlutterOverlayWindow.isActive(). This listener can attach
  // immediately (no DB dependency), unlike intentWritePort's.
  IsolateNameServer.removePortNameMapping(_overlayClosedPortName);
  final overlayClosedPort = ReceivePort();
  IsolateNameServer.registerPortWithName(overlayClosedPort.sendPort, _overlayClosedPortName);
  overlayClosedPort.listen((_) {
    _overlayIsActive = false;
    debugPrint('🔵 Overlay closed signal received');
  });

  // Same cleared-then-registered reasoning as the two ports above — see
  // that comment. This one flows the OPPOSITE direction (main → background):
  // see _manualPromptPortName's doc for why the Status screen can't just
  // call showOverlay() directly.
  IsolateNameServer.removePortNameMapping(_manualPromptPortName);
  final manualPromptPort = ReceivePort();
  IsolateNameServer.registerPortWithName(manualPromptPort.sendPort, _manualPromptPortName);
  manualPromptPort.listen((message) async {
    final map = message as Map;
    final width = (map['screenWidth'] as num?)?.toInt() ?? 0;
    final height = (map['screenHeight'] as num?)?.toInt() ?? 0;
    await _showCaptureScreenManually(width, height);
  });

  _unlockChannel.setMethodCallHandler((call) async {
    if (call.method == 'onUnlock') {
      debugPrint('🔓 UNLOCK EVENT RECEIVED at ${DateTime.now()}');
      // The prompts-disabled/quiet-hours/permission/etc. triage all now
      // happens INSIDE _showCaptureScreen, which is called unconditionally
      // on every unlock — not gated here — because every unlock needs an
      // unlock_log row regardless of outcome (docs/DATA_MODEL.md §3), and
      // _showCaptureScreen is the one place already positioned to log
      // exactly which gate fired.
      final args = (call.arguments as Map?) ?? const {};
      final width = (args['width'] as num?)?.toInt() ?? 0;
      final height = (args['height'] as num?)?.toInt() ?? 0;
      await _showCaptureScreen(width, height);
    } else if (call.method == 'onLock') {
      debugPrint('🔒 LOCK EVENT RECEIVED at ${DateTime.now()}');
    }
  });

  // The listener attaches to intentWritePort IMMEDIATELY and unconditionally
  // — NOT gated behind a successful IntentStore.open() — for two reasons:
  // (1) a single-subscription ReceivePort buffers messages sent before
  // .listen() runs, so attaching early never loses a write; (2) if
  // backgroundMain's entry point re-runs in an already-live engine (see the
  // removePortNameMapping comment above), this guarantees the listener is on
  // the CURRENT port even if _intentStore (a top-level static) is already
  // non-null from before. Each message's handler calls _ensureIntentStore()
  // itself, so a store that failed to open at boot gets retried per write
  // too, not just on the next unlock.
  //
  // Branches on the `type` tag added by _relayDeclaredIntent /
  // _relayDismissal / _relayNoIntent — see those functions' docs for why the
  // three shapes need different IntentStore calls (docs/DATA_MODEL.md §4).
  intentWritePort.listen((message) async {
    try {
      final map = message as Map;
      final store = await _ensureIntentStore();
      if (store == null) {
        debugPrint('⚠️ Dropping relayed message — IntentStore unavailable: $map');
        return;
      }
      switch (map['type']) {
        case 'declare':
          final event = IntentEvent.fromMessage(map);
          await store.insertOpenIntent(event);
          debugPrint('📂 Intent opened: text="${event.text}"');
        case 'dismiss':
          final dismissal = IntentDismissal.fromMessage(map);
          await store.markIntentDone(clientId: dismissal.clientId, completedAt: dismissal.completedAt);
          debugPrint('✅ Intent marked done: clientId=${dismissal.clientId}');
        case 'noIntent':
          final event = IntentEvent.fromMessage(map);
          await store.insertEvent(event);
          debugPrint('💾 Stored no-intent event: text="${event.text}"');
        case 'requestPresets':
          await _replyActivePresetsToOverlay(store);
        default:
          debugPrint('⚠️ Unknown relay message type (${map['type']}) — dropped: $map');
      }
    } catch (e) {
      debugPrint('⚠️ Ignoring malformed overlay message ($e): $message');
    }
  });

  // Best-effort early open + abandoned-intent sweep — NOT awaited, so
  // backgroundMain stays synchronous up to the handler registrations above.
  // Subsumes the plain early-open this replaced: _sweepAbandonedIntents
  // calls _ensureIntentStore as its own first step, so warming the store and
  // sweeping stale `open` rows happen together rather than as two separate
  // concerns. If this attempt fails (see _ensureIntentStore's doc comment
  // for why it reliably can on a real device), _showCaptureScreen and the
  // write listener above each retry the open lazily when they next need it —
  // the sweep itself is simply skipped for this engine start if so, since a
  // failed store open means there's nothing to sweep yet anyway.
  unawaited(_sweepAbandonedIntents());

  debugPrint('🧠 backgroundMain ready (persistent background engine)');
}

/// Sweeps any intent left `open` by a process that died before dismissing it
/// (reboot, OEM kill — docs/DATA_MODEL.md §3 cases 7/8) to `abandoned`.
/// Called once per background-engine start, never per-unlock or per-write: a
/// fresh engine start is exactly the moment any `open` row from a PREVIOUS
/// process can no longer be dismissed by whatever declared it (that
/// process's overlay-isolate widget state is gone), so it's the right and
/// only point to reclassify it. Wrapped in try/catch — a sweep failure must
/// never crash engine startup, and there's always a later opportunity: the
/// next engine start sweeps whatever's still lingering.
Future<void> _sweepAbandonedIntents() async {
  try {
    final store = await _ensureIntentStore();
    if (store == null) {
      debugPrint('⚠️ Skipping abandoned-intent sweep — IntentStore unavailable');
      return;
    }
    final swept = await _withTimeout('IntentStore.sweepOpenToAbandoned()', store.sweepOpenToAbandoned());
    if (swept != null && swept > 0) {
      debugPrint('🧹 Swept $swept abandoned intent(s)');
    }
  } catch (e) {
    debugPrint('⚠️ Failed to sweep abandoned intents (non-fatal): $e');
  }
}

/// Opens `_intentStore` if it isn't already open, retrying on every call
/// rather than giving up after one failure. Real, observed failure mode
/// (on-device, 2026-07-22): `backgroundMain` runs at `LOCKED_BOOT_COMPLETED`
/// — i.e. it can start BEFORE the user's first post-reboot unlock, while
/// Android's credential-encrypted storage (where `getDatabasesPath()`
/// resolves by default) is still locked. The original code called
/// `IntentStore.open()` exactly once, unawaited and uncaught, at engine
/// start: that first attempt raced storage being locked, threw
/// `DatabaseException(open_failed ...)`, and — because nothing ever tried
/// again — left `_intentStore` null for the rest of the process's life. Every
/// later cooldown check then read `_intentStore == null` as "no prior event"
/// (a deliberate design choice for the brief window right after a NORMAL
/// engine start — see the comment in `_showCaptureScreen` — but never meant
/// to be permanent), so the cooldown floor silently stopped working, AND
/// every subsequent write was dropped since the insert listener could never
/// stand up a store either. Calling this from both the write-listener and
/// `_showCaptureScreen` means the very next real event (the user's first
/// post-reboot unlock, by which point storage is guaranteed unlocked) gets a
/// fresh attempt instead of trusting a stale failure from before boot
/// finished.
Future<IntentStore?> _ensureIntentStore() async {
  if (_intentStore != null) return _intentStore;
  // Coalesce concurrent opens. Two events arriving close together (e.g. the
  // write-listener and an unlock's triage check) both pass the null check
  // above before the first open() resolves, so without this guard both call
  // IntentStore.open() — observed on-device as "💽 IntentStore opened" logged
  // twice on the first post-boot unlock. Sharing one in-flight future means
  // exactly one open() runs; late callers await the same result. Cleared in
  // catch so a FAILED open (the direct-boot storage-locked case) is retried
  // with a fresh future next time rather than re-awaiting the dead one.
  try {
    final opening = _intentStoreOpening ??= IntentStore.open();
    final store = await opening;
    if (_intentStore == null) {
      _intentStore = store;
      debugPrint('💽 IntentStore opened');
    }
    _intentStoreOpening = null;
  } catch (e) {
    _intentStoreOpening = null;
    debugPrint('⚠️ IntentStore.open() failed, will retry when next needed: $e');
  }
  return _intentStore;
}

/// In-flight `IntentStore.open()` future, shared by concurrent
/// [_ensureIntentStore] callers so only one open runs at a time. Null when no
/// open is in progress. See [_ensureIntentStore].
Future<IntentStore>? _intentStoreOpening;

@pragma("vm:entry-point")
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      color: Colors.transparent,
      home: OverlayRoot(),
    ),
  );
}

/// Wraps a plugin/DB call that has a real, observed failure mode: a native
/// reply or DB operation that silently never completes (the same class of
/// bug as the `shareData()` fire-and-forget issue — see CLAUDE.md §3 /
/// ARCHITECTURE.md §5 — but on a different call). Without this, a single
/// stuck `await` here wedges this specific `_showCaptureScreen` invocation
/// forever; because a fresh one is spawned on every unlock (Dart doesn't
/// serialize re-entrant async handler calls), the failure accumulates
/// silently across unlocks rather than crashing loudly — exactly the
/// "no prompt, no error, no log" symptom found in testing. On timeout, log
/// which call was responsible and return null so the caller can degrade
/// gracefully (skip just this one unlock) instead of leaving it stuck.
Future<T?> _withTimeout<T>(String label, Future<T> future) async {
  try {
    return await future.timeout(const Duration(seconds: 5));
  } on TimeoutException {
    debugPrint('⏱️ $label timed out after 5s — skipping this unlock rather than risk a permanent stall');
    return null;
  }
}

/// Records one `unlock_log` row — see docs/DATA_MODEL.md §2/§3 for why this
/// must run for EVERY unlock regardless of outcome, and why it happens AFTER
/// the decision (and after `showOverlay()` on the shown path) rather than
/// before: it must never sit on the ~500ms unlock-to-prompt path
/// (`CLAUDE.md` §8), and it must never be able to suppress the prompt on
/// failure. Wrapped in try/catch AND `_withTimeout` — belt and braces,
/// matching the two independently-observed failure classes already hit in
/// this codebase (a DB call that throws, and a plugin/DB call that never
/// returns at all — `docs/ARCHITECTURE.md` §5).
Future<void> _logUnlock({
  required DateTime unlockedAt,
  required bool promptShown,
  SkipReason? skipReason,
}) async {
  try {
    final store = await _ensureIntentStore();
    if (store == null) {
      debugPrint('⚠️ Dropping unlock_log row — IntentStore unavailable');
      return;
    }
    await _withTimeout(
      'IntentStore.insertUnlock()',
      store.insertUnlock(unlockedAt: unlockedAt, promptShown: promptShown, skipReason: skipReason),
    );
  } catch (e) {
    debugPrint('⚠️ Failed to log unlock (non-fatal): $e');
  }
}

/// Shows the intent-capture overlay on unlock — or decides not to, logging
/// exactly why either way. Lives at top level (not in a widget) because it
/// runs in the headless background engine — see [backgroundMain].
/// [screenWidth]/[screenHeight] are the true display size in raw device
/// pixels, provided by native (the headless engine can't read display
/// metrics itself).
///
/// Called UNCONDITIONALLY on every unlock (the caller no longer gates on
/// prompts-enabled before calling this) because every unlock needs an
/// `unlock_log` row regardless of outcome — this function is the one place
/// already positioned to log exactly which gate fired, so the gating logic
/// lives here rather than being split across the channel handler and here.
///
/// Checks run cheapest/no-I/O first: prompts-enabled and quiet hours are a
/// single batched settings read with no plugin or DB call, so a user who has
/// turned prompts off (or is in a configured quiet window) never pays for the
/// permission check or a DB round-trip. Permission, screen size, and
/// overlay-active preserve their original relative order from before this
/// task; cooldown/probability come last since they're the only checks that
/// need the store.
Future<void> _showCaptureScreen(int screenWidth, int screenHeight) async {
  final unlockedAt = DateTime.now();
  final settings = await _appSettings.loadSnapshot();

  // Gate only the prompt — monitoring/logging below still runs either way
  // (the unlock_log row is still written), so turning this off doesn't stop
  // the service, just the popup.
  if (!settings.promptsEnabled) {
    debugPrint('🔕 Prompts disabled, skipping');
    await _logUnlock(unlockedAt: unlockedAt, promptShown: false, skipReason: SkipReason.promptsDisabled);
    return;
  }

  if (settings.quietHoursEnabled &&
      !QuietHoursPolicy(settings.quietHoursWindow).shouldPrompt(PromptContext(now: unlockedAt))) {
    debugPrint('🌙 Quiet hours active (${settings.quietHoursWindow}), skipping');
    await _logUnlock(unlockedAt: unlockedAt, promptShown: false, skipReason: SkipReason.quietHours);
    return;
  }

  final hasPermission = await _withTimeout('isPermissionGranted()', FlutterOverlayWindow.isPermissionGranted());
  debugPrint('📋 Has overlay permission: $hasPermission');
  if (hasPermission != true) {
    await _logUnlock(unlockedAt: unlockedAt, promptShown: false, skipReason: SkipReason.noPermission);
    return;
  }

  if (screenWidth <= 0 || screenHeight <= 0) {
    debugPrint('⚠️ Invalid screen size ($screenWidth x $screenHeight), skipping');
    await _logUnlock(unlockedAt: unlockedAt, promptShown: false, skipReason: SkipReason.invalidScreenSize);
    return;
  }

  // Self-tracked instead of FlutterOverlayWindow.isActive() — that plugin
  // call was found (on-device, 2026-07-22) to hang in native code in a way
  // even a Dart-level .timeout() couldn't catch, once the app had been
  // opened. See _overlayIsActive / _overlayClosedPortName for the full story
  // and docs/debug/sprint3-session-log-2026-07-22.txt for the evidence.
  if (_overlayIsActive) {
    debugPrint('🟡 Overlay already active, skipping re-trigger');
    await _logUnlock(unlockedAt: unlockedAt, promptShown: false, skipReason: SkipReason.overlayActive);
    return;
  }

  // Prompt triage: a deterministic cooldown floor (never re-prompt within
  // the configured cooldown of the last event), then a probability gate
  // above it (unpredictable timing resists the habituation a fixed cadence
  // causes — see docs/DATA_MODEL.md / CLAUDE.md §9). Both policies are built
  // FRESH from the just-loaded settings snapshot rather than held as
  // module-level finals, so a change made in the Settings screen (T13) takes
  // effect on the very next unlock with no engine restart — the whole reason
  // AppSettings never caches a SharedPreferencesAsync instance (see that
  // class's doc comment). _ensureIntentStore retries the open if a prior
  // attempt failed (e.g. it raced credential-encrypted storage being locked
  // pre-first-unlock, see that function's doc comment) instead of trusting a
  // stale null forever; a still-null result here (a genuinely unavailable
  // store, not just "hasn't opened yet") is treated as "no prior event," so
  // the cooldown floor doesn't block this unlock rather than silently
  // wedging the prompt entirely. Checked (and logged) as two separate steps
  // — not a single CompositePromptPolicy — so a long streak of skips is
  // diagnosable as "cooldown is stuck" (a real bug) vs. "unlucky probability
  // draws" (working as intended), which a clubbed-together log line can't
  // distinguish (this is what made an early Sprint 3 test run look broken).
  final store = await _ensureIntentStore();
  final lastCompletedAt = store == null
      ? null
      : await _withTimeout('IntentStore.lastCompletedAt()', store.lastCompletedAt());
  final ctx = PromptContext(now: unlockedAt, lastCompletedAt: lastCompletedAt);

  final cooldownPolicy = TimeCooldownPolicy(settings.cooldown);
  if (!cooldownPolicy.shouldPrompt(ctx)) {
    final elapsed = lastCompletedAt == null ? null : ctx.now.difference(lastCompletedAt);
    debugPrint('🎲 Triage: skipping — COOLDOWN active (elapsed $elapsed < ${settings.cooldown})');
    await _logUnlock(unlockedAt: unlockedAt, promptShown: false, skipReason: SkipReason.cooldown);
    return;
  }
  final probabilityPolicy = ProbabilityPromptPolicy(settings.probability);
  if (!probabilityPolicy.shouldPrompt(ctx)) {
    debugPrint('🎲 Triage: skipping — PROBABILITY miss (p=${settings.probability})');
    await _logUnlock(unlockedAt: unlockedAt, promptShown: false, skipReason: SkipReason.probability);
    return;
  }
  debugPrint('🎲 Triage: prompting (cooldown clear, probability hit p=${settings.probability})');

  // Size the window from the native-provided true display size (raw device
  // pixels — exactly what showOverlay() expects; see CLAUDE.md §5). We do NOT
  // use PlatformDispatcher here because this runs in the headless background
  // engine, which has no display surface and reports 0x0. We also avoid the
  // plugin's WindowSize.fullCover, whose native screenHeight() under-covers
  // the bottom on this device.
  //
  // alignment MUST be topLeft, not center. Confirmed via `dumpsys window
  // windows`: with center gravity, Android fits the window's "parent" frame
  // to exclude the nav bar (height 2337 = 2400 - 63px nav bar), then CENTERS
  // our (taller) requested window inside that shrunk region — shifting it up
  // ~31px (half the nav-bar inset) so the bottom lands 31px short of the true
  // display bottom. That's the exposed-bottom bug; it's a gravity/fit
  // artifact, not a size or position value problem (both were already
  // correct). topLeft anchors to the true origin instead of centering within
  // an inset-shrunk region.
  //
  // startPosition (0,0): pins the window to the true top-left; without it the
  // plugin's default position shifts the window up by the status-bar height.
  //
  // Set BEFORE the await, not after: closes the race where a second
  // onUnlock could arrive (a fresh async call — Dart doesn't serialize
  // re-entrant handler invocations) while this call is still awaiting
  // showOverlay(), and both would otherwise see _overlayIsActive == false.
  await _presentCaptureOverlay(screenWidth, screenHeight);
  // Logged AFTER showOverlay(), not before: the prompt reaching the screen is
  // the time-critical part (CLAUDE.md §8's ~500ms target); this write is not
  // (docs/DATA_MODEL.md §3c).
  await _logUnlock(unlockedAt: unlockedAt, promptShown: true);
}

/// The actual `showOverlay()` call, shared by the real unlock path
/// ([_showCaptureScreen]) and the manual trigger ([_showCaptureScreenManually],
/// T6's "show me the prompt now"). Setting `_overlayIsActive` and the window
/// params themselves must stay IDENTICAL between the two paths — a manual
/// trigger is still a real overlay window with the same sizing/gravity
/// constraints, just reached by a different route into this isolate. Split
/// out specifically so there is exactly one place that can get the window
/// flags/alignment wrong, not two copies that could drift.
Future<void> _presentCaptureOverlay(int screenWidth, int screenHeight) async {
  // Size the window from the true display size in raw device pixels — exactly
  // what showOverlay() expects; see CLAUDE.md §5. We do NOT use
  // PlatformDispatcher here because this runs in the headless background
  // engine, which has no display surface and reports 0x0 on the real-unlock
  // path — see the two callers for how each supplies a real value instead. We
  // also avoid the plugin's WindowSize.fullCover, whose native screenHeight()
  // under-covers the bottom on this device.
  //
  // alignment MUST be topLeft, not center. Confirmed via `dumpsys window
  // windows`: with center gravity, Android fits the window's "parent" frame
  // to exclude the nav bar (height 2337 = 2400 - 63px nav bar), then CENTERS
  // our (taller) requested window inside that shrunk region — shifting it up
  // ~31px (half the nav-bar inset) so the bottom lands 31px short of the true
  // display bottom. That's the exposed-bottom bug; it's a gravity/fit
  // artifact, not a size or position value problem (both were already
  // correct). topLeft anchors to the true origin instead of centering within
  // an inset-shrunk region.
  //
  // startPosition (0,0): pins the window to the true top-left; without it the
  // plugin's default position shifts the window up by the status-bar height.
  //
  // Set BEFORE the await, not after: closes the race where a second trigger
  // (a real unlock OR another manual trigger) could arrive (a fresh async
  // call — Dart doesn't serialize re-entrant handler invocations) while this
  // call is still awaiting showOverlay(), and both would otherwise see
  // _overlayIsActive == false.
  _overlayIsActive = true;
  await FlutterOverlayWindow.showOverlay(
    height: screenHeight,
    width: screenWidth,
    alignment: OverlayAlignment.topLeft,
    flag: OverlayFlag.focusPointer,
    startPosition: const OverlayPosition(0, 0),
    overlayTitle: 'Why Did I Unlock?',
    overlayContent: 'Declare your intent',
  );
  debugPrint('🟣 showOverlay called (${screenWidth}x$screenHeight capture screen)');
}

/// The manual-trigger counterpart to [_showCaptureScreen] — reached via
/// [_manualPromptPortName] from the Status screen's "show me the prompt now"
/// button (T6), not from a real unlock. Deliberately bypasses
/// prompts-enabled, quiet hours, cooldown, and probability: the whole point
/// of the button is to show the prompt regardless of triage state, so a
/// tester isn't told "no, cooldown" when they explicitly asked to see it.
///
/// What it does NOT skip: the permission check (surfacing a real permission
/// problem is exactly what this button exists to catch — silently
/// succeeding would defeat its purpose) and the `_overlayIsActive` guard
/// (can't show two overlay windows at once, manually triggered or not).
///
/// Deliberately does NOT call [_logUnlock] — this isn't a real unlock, and
/// counting it would inflate "unlocks today" and the prompt-rate stats with
/// test-only noise the metrics were never meant to include.
Future<void> _showCaptureScreenManually(int screenWidth, int screenHeight) async {
  final hasPermission = await _withTimeout('isPermissionGranted()', FlutterOverlayWindow.isPermissionGranted());
  if (hasPermission != true) {
    debugPrint('🧪 Manual prompt trigger: permission not granted, cannot show');
    return;
  }
  if (screenWidth <= 0 || screenHeight <= 0) {
    debugPrint('🧪 Manual prompt trigger: invalid screen size ($screenWidth x $screenHeight), cannot show');
    return;
  }
  if (_overlayIsActive) {
    debugPrint('🧪 Manual prompt trigger: overlay already active, skipping');
    return;
  }
  await _presentCaptureOverlay(screenWidth, screenHeight);
  debugPrint('🧪 Manual prompt shown (Status screen trigger)');
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {

  // NOTE: unlock/lock handling deliberately does NOT live here anymore. It runs
  // in the persistent background engine (see backgroundMain) so it survives the
  // app being swiped out of Recents. This screen's only job is to request the
  // overlay permission on first launch (needs a real Activity context) and
  // host the prompts on/off toggle — there's no dedicated Settings screen yet,
  // so it lives here rather than building one just for a single switch.

  bool _promptsEnabled = true;

  @override
  void initState() {
    super.initState();
    _requestOverlayPermission();
    _loadPromptsEnabled();
  }

  Future<void> _requestOverlayPermission() async {
    final hasPermission = await FlutterOverlayWindow.isPermissionGranted();
    if (!hasPermission) {
      await FlutterOverlayWindow.requestPermission();
    }
  }

  Future<void> _loadPromptsEnabled() async {
    final enabled = await _appSettings.promptsEnabled();
    if (mounted) setState(() => _promptsEnabled = enabled);
  }

  Future<void> _togglePrompts(bool value) async {
    setState(() => _promptsEnabled = value);
    await _appSettings.setPromptsEnabled(value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Why Did I Unlock?',
              style: TextStyle(color: Colors.white, fontSize: 24),
            ),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Unlock prompts',
                  style: TextStyle(color: Colors.white70, fontSize: 16),
                ),
                Switch(
                  value: _promptsEnabled,
                  onChanged: _togglePrompts,
                ),
              ],
            ),
            const SizedBox(height: 24),
            TextButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const HistoryScreen()),
                );
              },
              child: const Text(
                'View history',
                style: TextStyle(color: Colors.white70, fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _OverlayMode { capture, bubble }

class OverlayRoot extends StatefulWidget {
  const OverlayRoot({super.key});

  @override
  State<OverlayRoot> createState() => _OverlayRootState();
}

class _OverlayRootState extends State<OverlayRoot> {
  _OverlayMode _mode = _OverlayMode.capture;
  String _intentText = '';
  String _intentSource = '';
  DateTime? _declaredAt;
  String? _intentClientId;

  /// Presets to render on the capture screen — empty until the first reply
  /// arrives. An empty list is a deliberately valid, already-tested state
  /// (docs/DATA_MODEL.md §7: "zero enabled presets is a valid, non-throwing
  /// state"), so the brief window between this engine's cold start and the
  /// first reply landing degrades to exactly that same state rather than
  /// needing a separate loading UI — no spinner, no flash of stale data.
  List<CapturePreset> _presets = [];

  @override
  void initState() {
    super.initState();
    // Cleared first for the same reason backgroundMain clears its three
    // ports before registering — if this engine's Dart isolate somehow
    // re-runs initState within one process lifetime, a name can only map to
    // one port at a time.
    IsolateNameServer.removePortNameMapping(_overlayConfigPortName);
    final configPort = ReceivePort();
    IsolateNameServer.registerPortWithName(configPort.sendPort, _overlayConfigPortName);
    configPort.listen((message) {
      final map = message as Map;
      final rawPresets = (map['presets'] as List?) ?? const [];
      if (mounted) {
        setState(() {
          _presets = rawPresets
              .map((p) => CapturePreset(id: (p as Map)['id'] as int, label: p['label'] as String))
              .toList();
        });
      }
    });
    // Port registration above MUST complete before this request is sent —
    // it does, since both are synchronous statements with no await between
    // them, so there's no window where background could look up a port that
    // doesn't exist yet.
    _requestPresets();
  }

  /// Sends a `requestPresets` message over the existing intent-write port
  /// (reusing that channel rather than adding a second overlay→background
  /// port — see docs/DATA_MODEL.md §4). Called once at engine cold start
  /// (`initState`) and again every time the overlay returns to capture mode
  /// after a dismissal, so a preset edited via the Settings/manage-presets
  /// screens (a different engine entirely) is picked up on the NEXT capture
  /// screen rather than staying stale for this cached engine's entire
  /// lifetime.
  void _requestPresets() {
    _sendToBackground({'type': 'requestPresets'});
  }

  Future<void> _submitIntent(String text, String source, {int? presetId}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final declaredAt = DateTime.now();
    // Computed ONCE and reused for both the widget state and the relay
    // below — calling _generateClientId twice (once here, once inside the
    // old setState callback) would mint two DIFFERENT ids for the same
    // intent, since it includes a random suffix. That would break the
    // dismiss-time relay's ability to find this row at all (markIntentDone
    // is keyed on clientId).
    final clientId = _generateClientId(declaredAt);
    debugPrint(
      '📝 Intent declared: "$trimmed" (source: $source) at $declaredAt',
    );

    setState(() {
      _intentText = trimmed;
      _intentSource = source;
      _declaredAt = declaredAt;
      _intentClientId = clientId;
      _mode = _OverlayMode.bubble;
    });

    // Relayed at DECLARATION time, not dismissal — this is what lets the
    // intent survive a process death before the bubble is ever dismissed
    // (reboot, OEM kill): the row already exists the moment the user
    // declares it. See docs/DATA_MODEL.md §4 and _relayDeclaredIntent's doc.
    // completedAt is a required IntentEvent field but is IGNORED by
    // insertOpenIntent (which uses declaredAt as its own placeholder), so
    // declaredAt is passed for both — there is no real completion yet.
    // presetId is null for custom text (there's no preset to point at) and
    // for any preset tap that arrived before this engine's first
    // requestPresets reply landed — a null presetId degrades to grouping by
    // the text snapshot alone, exactly the pre-T11 behaviour, never an error
    // (docs/DATA_MODEL.md §4).
    _relayDeclaredIntent(IntentEvent(
      clientId: clientId,
      kind: IntentKind.intent,
      source: _intentSourceFromString(source),
      text: trimmed,
      declaredAt: declaredAt,
      completedAt: declaredAt,
      presetId: presetId,
    ));

    // Read density BEFORE the awaits (avoids using context across an async gap).
    // showOverlay() sizes the window in raw device pixels, so convert dp -> px.
    final dpr = MediaQuery.of(context).devicePixelRatio;

    // The capture screen's window is created focusable (needed for the text
    // field's keyboard). Flipping to a non-focusable flag in place via
    // updateFlag()/resizeOverlay() doesn't reliably make Android release
    // focus it already granted, which is what was blocking touches/keyboard/
    // back-gesture in every other app. Closing and reopening a fresh window
    // at bubble size with defaultFlag (non-focusable from birth) avoids that
    // — the Flutter engine and this widget's state survive the recreation.
    await FlutterOverlayWindow.closeOverlay();
    await FlutterOverlayWindow.showOverlay(
      height: (_bubbleHeightDp * dpr).round(),
      width: (_bubbleWidthDp * dpr).round(),
      alignment: OverlayAlignment.center,
      flag: OverlayFlag.defaultFlag,
      overlayTitle: 'Why Did I Unlock?',
      overlayContent: trimmed,
      enableDrag: true,
    );
  }

  /// Honest "no real reason" path — logs the habitual/purposeless unlock
  /// (real signal, see docs/BACKLOG.md) but does NOT transition to bubble
  /// mode: there's no declared task, so a persistent reminder would just be
  /// nagging. State stays in capture mode with nothing set, so the engine is
  /// already clean for the next unlock (no reset needed, unlike _dismissBubble).
  Future<void> _submitNoIntent() async {
    final now = DateTime.now();
    debugPrint('🤷 No intent declared ("$noIntentLabel") at $now');

    // Relayed to the background engine (the sole DB writer — see CLAUDE.md
    // §3) via the same-process IsolateNameServer port — see
    // _intentWritePortName for why this replaced shareData(). Atomic — no
    // separate declare/dismiss step, since there's no bubble to later
    // dismiss (see _relayNoIntent's doc).
    final event = IntentEvent(
      clientId: _generateClientId(now),
      kind: IntentKind.noIntent,
      source: null,
      text: noIntentLabel,
      declaredAt: now,
      completedAt: now,
    );
    _relayNoIntent(event);

    await FlutterOverlayWindow.closeOverlay();
    // Tells the background isolate this is a REAL close (not the
    // close+reopen resize in _submitIntent) — see _overlayIsActive.
    _signalOverlayClosed();
  }

  Future<void> _dismissBubble() async {
    final dismissedAt = DateTime.now();
    final activeFor = _declaredAt == null ? null : dismissedAt.difference(_declaredAt!);
    debugPrint(
      '✅ Intent dismissed: "$_intentText" (source: $_intentSource) '
      'declared at $_declaredAt, dismissed at $dismissedAt, active for $activeFor',
    );

    // Only clientId + completedAt relayed here — kind/source/text/declaredAt
    // were already persisted by _submitIntent's declare-time relay above;
    // this just marks that same row (matched by clientId) done. See
    // IntentDismissal's doc and docs/DATA_MODEL.md §4. _intentClientId is
    // always non-null here: this is only reachable from bubble mode, which
    // _submitIntent only enters after setting it.
    _relayDismissal(IntentDismissal(clientId: _intentClientId!, completedAt: dismissedAt));

    await FlutterOverlayWindow.closeOverlay();
    // Tells the background isolate this is a REAL close (not the
    // close+reopen resize in _submitIntent) — see _overlayIsActive.
    _signalOverlayClosed();
    // The plugin caches the overlay's Flutter engine and only detaches the
    // view on closeOverlay() — the engine (and therefore this State's _mode +
    // _intentText) survives. Without this reset, the next unlock reattaches
    // the cached view still in bubble mode showing the old intent; and because
    // that next window opens full-screen for the capture prompt, a stale bubble
    // in a full-screen window swallows every touch and blocks the phone. Reset
    // to a clean capture state so the next unlock shows a fresh prompt.
    if (mounted) {
      setState(() {
        _mode = _OverlayMode.capture;
        _intentText = '';
        _intentSource = '';
        _declaredAt = null;
        _intentClientId = null;
      });
    }
    // Refresh presets for the NEXT capture screen — see _requestPresets's
    // doc for why this happens here rather than only once at cold start.
    _requestPresets();
  }

  @override
  Widget build(BuildContext context) {
    switch (_mode) {
      case _OverlayMode.capture:
        return IntentCaptureScreen(
          presets: _presets,
          onSubmit: _submitIntent,
          onNoIntent: _submitNoIntent,
        );
      case _OverlayMode.bubble:
        return BubbleWidget(intentText: _intentText, onClose: _dismissBubble);
    }
  }
}

class IntentCaptureScreen extends StatefulWidget {
  /// Presets to render as pills. DB-backed and relayed from the background
  /// isolate (see [CapturePreset]'s doc) — may be empty, which is a
  /// deliberately valid state (docs/DATA_MODEL.md §7), not an error to guard
  /// against.
  final List<CapturePreset> presets;

  /// Called with (text, source, presetId) where source is 'preset' or
  /// 'custom' and presetId is the tapped preset's id (null for custom text).
  final void Function(String text, String source, {int? presetId}) onSubmit;

  /// Called when the user picks the honest "no real reason" option instead.
  final VoidCallback onNoIntent;

  const IntentCaptureScreen({
    super.key,
    required this.presets,
    required this.onSubmit,
    required this.onNoIntent,
  });

  @override
  State<IntentCaptureScreen> createState() => _IntentCaptureScreenState();
}

class _IntentCaptureScreenState extends State<IntentCaptureScreen> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submitCustomText() => widget.onSubmit(_controller.text, 'custom');

  @override
  Widget build(BuildContext context) {
    // Scaffold (not a bare Material) so resizeToAvoidBottomInset shrinks the
    // available body height when the keyboard opens.
    //
    // Layout is thumb-zone-driven (per one-handed mobile UX research: the
    // bottom/center of the screen is the reachable "easy zone", the top is
    // the "hard zone" for one-handed thumb use — critical, tappable elements
    // belong in the lower two-thirds). The title is read-only, so it stays
    // fixed up top where it's easy to READ. Every TAPPABLE element (presets,
    // "Just Like That", the text field/OK) is pushed down into the reachable
    // zone, ending with the text field glued just above the keyboard.
    //
    // The presets/no-intent group uses the LayoutBuilder + ConstrainedBox
    // (minHeight: full available space) + IntrinsicHeight + mainAxisAlignment
    // .end combo: this is what lets a Column inside a SingleChildScrollView
    // still bottom-align its content when there's slack space (a bare
    // Column inside a scroll view always top-aligns, since the scroll view
    // gives it unbounded height), while still scrolling gracefully — instead
    // of overflowing — if the keyboard squeezes the available space below
    // the content's natural height.
    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: 0.85),
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: constraints.maxHeight),
                        child: IntrinsicHeight(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              const Text(
                                'What are you unlocking for?',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.white, fontSize: 24),
                              ),
                              const SizedBox(height: 32),
                              Wrap(
                                spacing: 12,
                                runSpacing: 12,
                                alignment: WrapAlignment.center,
                                children: [
                                  for (final preset in widget.presets)
                                    _PresetButton(
                                      label: preset.label,
                                      onTap: () => widget.onSubmit(preset.label, 'preset', presetId: preset.id),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 24),
                              // Deliberately styled DIFFERENTLY from the
                              // topic pills above — muted border/italic
                              // text, preceding caption — so it visually
                              // reads as a different kind of answer, "no
                              // real reason", not just another category.
                              // Still logs (see _submitNoIntent); not a
                              // plain Skip.
                              const Text(
                                'or, if there isn\'t one —',
                                style: TextStyle(color: Colors.white38, fontSize: 13),
                              ),
                              const SizedBox(height: 8),
                              _NoIntentButton(onTap: widget.onNoIntent),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      maxLength: intentMaxInputLength,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        hintText: 'Type your intent...',
                        hintStyle: TextStyle(color: Colors.white54),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.white54),
                        ),
                      ),
                      onSubmitted: (_) => _submitCustomText(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _submitCustomText,
                    child: const Text(
                      'OK',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PresetButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _PresetButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: const BorderSide(color: Colors.white54),
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
      child: Text(label),
    );
  }
}

/// "Just Like That" — a real pill so it reads as tappable (Dinesh's feedback
/// on the previous bare italic-underlined TextButton), but styled MUTED
/// relative to [_PresetButton] (dimmer border/text, no fill) so it still
/// visually reads as the "no real reason" option rather than another topic.
class _NoIntentButton extends StatelessWidget {
  final VoidCallback onTap;

  const _NoIntentButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white70,
        side: const BorderSide(color: Colors.white24),
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
      child: const Text(
        noIntentLabel,
        style: TextStyle(fontSize: 14, fontStyle: FontStyle.italic),
      ),
    );
  }
}

class BubbleWidget extends StatelessWidget {
  final String intentText;
  final VoidCallback onClose;

  const BubbleWidget({
    super.key,
    required this.intentText,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    // The bubble fills its (pill-sized) window; a fixed border radius of half
    // the pill height gives a stadium shape without hardcoding a width that
    // could sub-pixel-overflow after the dp->px rounding in _submitIntent.
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.deepPurple,
          borderRadius: BorderRadius.circular(_bubbleHeightDp / 2),
        ),
        padding: const EdgeInsets.only(left: 16, right: 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                intentText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
            GestureDetector(
              onTap: onClose,
              child: Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(
                  color: Colors.black26,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, size: 16, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
