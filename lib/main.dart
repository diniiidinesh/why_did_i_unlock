import 'dart:async';
import 'dart:isolate';
import 'dart:math';
import 'dart:ui' show IsolateNameServer, PlatformDispatcher;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

import 'app_settings.dart';
import 'beacon_theme.dart';
import 'brand.dart';
import 'bubble_overlay_geometry.dart';
import 'bubble_widget.dart';
import 'day_one.dart';
import 'day_one_notifications.dart';
import 'day_one_stats_screen.dart';
import 'home_screen.dart';
import 'intent_store.dart';
import 'onboarding_screen.dart';
import 'preset_pill.dart';
import 'problem_report.dart';
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

/// A previously-declared intent still `open` (undismissed) at the moment a
/// new capture screen is shown. Reserved for multi-intent prompting
/// (docs/erd/sprint4-app-shell-plan-2026-07-23.md §7.1: "prompt again with
/// the previous bubble's text differentiated, so the user can mark it done
/// or add a second intent") — **T12 only plumbs the parameter through; it is
/// always passed an empty list this iteration.** Nothing queries
/// `WHERE status='open'` yet. Minimal shape (not the full DB row) mirrors
/// [CapturePreset]'s reasoning: the future rendering code needs just enough
/// to show a "you already said X" reminder, not preset/unlock linkage.
class OutstandingIntent {
  final String clientId;
  final String text;
  final DateTime declaredAt;
  const OutstandingIntent({required this.clientId, required this.text, required this.declaredAt});
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

/// Bubble window sizes (dp). `showOverlay` wants device px (`dp * dpr`);
/// `resizeOverlay` wants dp — see docs/ARCHITECTURE.md §5.
/// Spec: docs/erd/bubble-ux-hybrid-plan-2026-07-24.md §I.5.
const Duration _bubbleAutoCollapseDelay = Duration(seconds: 2);
const Duration _bubbleSnoozeDuration = Duration(minutes: 10);

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
  WidgetsFlutterBinding.ensureInitialized();
  ProblemReportLog.installHooks('ui');
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
/// Returns `true` if the port was found and the message handed off, `false`
/// if it wasn't (background engine not ready yet — see [_requestPresets]'s
/// retry loop, added after this exact race was caught on-device 2026-07-23:
/// the overlay's `initState` fired before `backgroundMain` had (re-)registered
/// its ports, and because the config-relay request only ever fired once with
/// no retry, that single failure left the capture screen permanently without
/// presets for the rest of that cached overlay engine's lifetime).
bool _sendToBackground(Map<String, dynamic> message) {
  final port = IsolateNameServer.lookupPortByName(_intentWritePortName);
  if (port == null) {
    // Gated: `message` can carry declared intent text (declare/noIntent
    // payloads) — debugPrint is NOT stripped from release builds
    // (docs/PLAY_SUBMISSION.md §3b.1), so an unguarded log here would put the
    // user's own words in Android's system log / bug reports / OEM diagnostic
    // uploads, directly contradicting the privacy policy's "nothing leaves
    // your device."
    if (kDebugMode) {
      debugPrint('⚠️ Could not find intent-write port — background engine not ready? Message dropped: $message');
    }
    return false;
  }
  port.send(message);
  return true;
}

/// Relayed from `_submitIntent` at DECLARATION time — creates the `open` row
/// (via `IntentStore.insertOpenIntent` in the listener). This is what makes
/// an intent survive a process death before it's dismissed: the row already
/// exists the moment the user declares it, not only once they dismiss the
/// bubble. See docs/DATA_MODEL.md §4.
void _relayDeclaredIntent(IntentEvent event) {
  _sendToBackground({...event.toMessage(), 'type': 'declare'});
}

/// Tells background the overlay is now a bubble (before close+reopen), so
/// [onOrientationChanged] does not reopen a full-screen capture mid-declare.
/// Sent even for manual sessions (which skip the declare DB write).
void _relayBubbleShowing({required String text, required double dpr}) {
  _sendToBackground({'type': 'bubbleShowing', 'text': text, 'dpr': dpr});
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
  // Post-reboot first unlock often opens the store mid-unlock while CE
  // storage is still warming; concurrent insertUnlock + activePresets can
  // both hit `_withTimeout`. Retry briefly before giving up.
  List<IntentPreset>? presets;
  const maxAttempts = 3;
  const retryDelay = Duration(milliseconds: 500);
  for (var attempt = 1; attempt <= maxAttempts; attempt++) {
    presets = await _withTimeout('IntentStore.activePresets()', store.activePresets());
    if (presets != null) break;
    if (attempt < maxAttempts) await Future.delayed(retryDelay);
  }
  // `_withTimeout` returns null on hang/timeout. Treating that as `[]` and
  // still sending would permanently poison the overlay's `_presets` cache
  // with an empty list (observed post-reboot first unlock 2026-07-24: store
  // had just recovered from ENOKEY, `insertUnlock` and `activePresets` both
  // timed out, overlay logged "Sent 0" / "_presets now has 0 entries").
  // A real "user disabled every preset" still returns an empty *list*, not
  // null — only abort the send on failure so a later retry can land real data.
  if (presets == null) {
    debugPrint('⚠️ activePresets unavailable after $maxAttempts attempts — not overwriting overlay presets with []');
    return;
  }
  final payload = presets
      .map((p) => {'id': p.id, 'label': p.label})
      .toList();
  final port = IsolateNameServer.lookupPortByName(_overlayConfigPortName);
  if (port == null) {
    debugPrint('⚠️ Could not find overlay-config reply port — overlay not ready yet? Presets dropped');
    return;
  }
  // `manual` rides along on this same message rather than a separate one —
  // see [_currentPresentIsManual]'s doc for why a second message on this
  // port would be actively dangerous (it would be misread as an empty
  // preset list). Reflects whichever capture presentation is CURRENTLY
  // showing (or was most recently shown), which is exactly what the overlay
  // needs to decide whether to relay this session's answer — see
  // docs/BACKLOG.md's [P1] "manual trigger arms real cooldown" entry.
  port.send({'presets': payload, 'manual': _currentPresentIsManual});
  debugPrint('📤 Sent ${payload.length} preset(s) to overlay (manual=$_currentPresentIsManual)');
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
/// awaiting that call. Also cleared by `_presentCaptureOverlay` if
/// `showOverlay()` itself times out — without that reset the flag stays
/// stuck `true` forever and every later unlock silently skips as
/// `overlay_active` (force-stop was the only recovery before this guard).
bool _overlayIsActive = false;

/// What the live overlay window is showing. Needed so
/// [onOrientationChanged] can reopen capture vs bubble correctly — the
/// background isolate cannot read [OverlayRoot]'s `_mode`.
enum _ActiveOverlayKind { none, capture, bubble }

_ActiveOverlayKind _activeOverlayKind = _ActiveOverlayKind.none;

/// Last bubble text / dpr for orientation reopen (and snooze-adjacent paths).
String _bubbleOverlayText = '';
double _bubbleOverlayDpr = 1.0;

/// Guards against overlapping orientation reopens (and vs mid-declare show).
bool _orientationRepositioning = false;

/// Last true display size from native unlock / [onOrientationChanged].
/// Used for drag-end snap — overlay [PlatformDispatcher.displays] often stays
/// on the *portrait* width after rotate, so left dock computed as ~359dp and
/// the bubble sits mid-landscape (TEST_PLAN 60 / on-device logs 2026-07-24).
int _lastNativeWidthPx = 0;
int _lastNativeHeightPx = 0;

/// In-memory snooze session (background isolate). Intent row stays `open`;
/// no schema write. See docs/erd/bubble-ux-hybrid-plan-2026-07-24.md §II.
bool _snoozeActive = false;
_SnoozeSession? _snoozeSession;
Timer? _snoozeTimer;

class _SnoozeSession {
  final String clientId;
  final String text;
  final String source;
  final DateTime declaredAt;
  final int? presetId;
  final bool isManual;
  final double dpr;

  const _SnoozeSession({
    required this.clientId,
    required this.text,
    required this.source,
    required this.declaredAt,
    required this.presetId,
    required this.isManual,
    required this.dpr,
  });
}

void _clearSnoozeState() {
  _snoozeTimer?.cancel();
  _snoozeTimer = null;
  _snoozeActive = false;
  _snoozeSession = null;
}

void _armSnoozeTimer() {
  _snoozeTimer?.cancel();
  _snoozeTimer = Timer(_bubbleSnoozeDuration, () {
    debugPrint('😴 Snooze timer elapsed — restoring collapsed bubble');
    unawaited(_restoreSnoozedBubble());
  });
}

/// Re-shows the bubble at collapsed size after snooze ends (timer or unlock).
Future<void> _restoreSnoozedBubble() async {
  final session = _snoozeSession;
  if (!_snoozeActive || session == null) return;
  _snoozeTimer?.cancel();
  _snoozeTimer = null;
  _snoozeActive = false;
  _snoozeSession = null;

  if (_overlayIsActive) {
    debugPrint('😴 Snooze restore skipped — overlay already active');
    return;
  }

  final dpr = session.dpr <= 0 ? 1.0 : session.dpr;
  final side = (bubbleCollapsedDp * dpr).round();
  _overlayIsActive = true;
  final shown = await _withTimeout(
    'showOverlay(snooze restore)',
    FlutterOverlayWindow.showOverlay(
      height: side,
      width: side,
      alignment: OverlayAlignment.centerRight,
      flag: OverlayFlag.defaultFlag,
      overlayTitle: appDisplayName,
      overlayContent: session.text,
      enableDrag: true,
      // Plugin PositionGravity.auto uses a screen size captured once at
      // show — stale after rotate, so it "snaps" to mid-landscape. We snap
      // ourselves via [_snapBubbleToEdge] when the overlay asks.
      positionGravity: PositionGravity.none,
    ).then((_) => true),
  );
  if (shown == null) {
    _overlayIsActive = false;
    _activeOverlayKind = _ActiveOverlayKind.none;
    debugPrint('⏱️ Snooze restore showOverlay timed out');
    return;
  }
  _activeOverlayKind = _ActiveOverlayKind.bubble;
  _bubbleOverlayText = session.text;
  _bubbleOverlayDpr = dpr;
  debugPrint('😴 Snooze restore: collapsed bubble shown (${side}x$side)');
}

/// Native [onOrientationChanged] → one close+reopen. Never query display size
/// from Dart isolates (overlay view ≠ phone; background is headless).
Future<void> _onOrientationChanged(int widthPx, int heightPx) async {
  _lastNativeWidthPx = widthPx;
  _lastNativeHeightPx = heightPx;
  if (!_overlayIsActive) {
    debugPrint('📐 Orientation ${widthPx}x$heightPx — no overlay, ignore');
    return;
  }
  if (_orientationRepositioning) {
    debugPrint('📐 Orientation — already repositioning, ignore');
    return;
  }
  _orientationRepositioning = true;
  try {
    switch (_activeOverlayKind) {
      case _ActiveOverlayKind.capture:
        await _repositionCaptureForOrientation(widthPx, heightPx);
      case _ActiveOverlayKind.bubble:
        await _repositionBubbleForOrientation();
      case _ActiveOverlayKind.none:
        debugPrint('📐 Orientation — active flag set but kind=none, ignore');
    }
  } finally {
    _orientationRepositioning = false;
  }
}

Future<void> _repositionCaptureForOrientation(int widthPx, int heightPx) async {
  debugPrint('📐 Orientation: one capture reopen ${widthPx}x$heightPx');
  await _closeOverlayWindow('orientation capture');
  final shown = await _withTimeout(
    'showOverlay(orientation capture)',
    FlutterOverlayWindow.showOverlay(
      height: heightPx,
      width: widthPx,
      alignment: OverlayAlignment.topLeft,
      flag: OverlayFlag.focusPointer,
      startPosition: const OverlayPosition(0, 0),
      overlayTitle: appDisplayName,
      overlayContent: 'Declare your intent',
    ).then((_) => true),
  );
  if (shown == null) {
    _overlayIsActive = false;
    _activeOverlayKind = _ActiveOverlayKind.none;
    debugPrint('⏱️ Orientation capture showOverlay timed out');
  }
}

Future<void> _repositionBubbleForOrientation() async {
  final dpr = _bubbleOverlayDpr <= 0 ? 1.0 : _bubbleOverlayDpr;
  final side = (bubbleCollapsedDp * dpr).round();
  debugPrint(
    '📐 Orientation: one bubble reopen at right-center '
    '(${side}x$side, text len=${_bubbleOverlayText.length})',
  );
  await _closeOverlayWindow('orientation bubble');
  final shown = await _withTimeout(
    'showOverlay(orientation bubble)',
    FlutterOverlayWindow.showOverlay(
      height: side,
      width: side,
      alignment: OverlayAlignment.centerRight,
      flag: OverlayFlag.defaultFlag,
      overlayTitle: appDisplayName,
      overlayContent: _bubbleOverlayText,
      enableDrag: true,
      positionGravity: PositionGravity.none,
    ).then((_) => true),
  );
  if (shown == null) {
    _overlayIsActive = false;
    _activeOverlayKind = _ActiveOverlayKind.none;
    debugPrint('⏱️ Orientation bubble showOverlay timed out');
    return;
  }
  _notifyOverlayBubbleRepositioned();
}

void _notifyOverlayBubbleRepositioned() {
  final port = IsolateNameServer.lookupPortByName(_overlayConfigPortName);
  if (port == null) return;
  port.send({'type': 'bubbleRepositioned'});
}

void _notifyOverlayDockSide({required bool dockLeft}) {
  final port = IsolateNameServer.lookupPortByName(_overlayConfigPortName);
  if (port == null) return;
  port.send({'type': 'bubbleDocked', 'dockLeft': dockLeft});
}

/// Drag-end edge snap only (not rotation — see [_onOrientationChanged]).
///
/// Coordinates assume [OverlayAlignment.centerRight] gravity: `x == 0` is the
/// right edge; larger `x` shifts left. Left dock = `screenWidthDp - widthDp`.
///
/// Prefer [nativeWidthPx]/[nativeHeightPx] (from unlock/orientation) over any
/// overlay-reported logical size — the overlay engine's display metrics lag
/// after rotate and produced mid-screen "left" docks at x≈359 on landscape.
Future<void> _snapBubbleToEdge({
  required double widthDp,
  required double heightDp,
  required double screenWidthDp,
  required double screenHeightDp,
  required double dpr,
  bool? dockLeft,
  double? detectWidthDp,
  bool resetY = false,
}) async {
  if (widthDp <= 0) return;
  if (_orientationRepositioning) return;

  var screenW = screenWidthDp;
  var screenH = screenHeightDp;
  if (_lastNativeWidthPx > 0 && _lastNativeHeightPx > 0 && dpr > 0) {
    screenW = _lastNativeWidthPx / dpr;
    screenH = _lastNativeHeightPx / dpr;
  }
  if (screenW <= 0) return;

  try {
    final pos = await _withTimeout(
      'getOverlayPosition()',
      FlutterOverlayWindow.getOverlayPosition(),
    );
    if (pos == null) return;
    final probe = detectWidthDp ?? widthDp;
    final left = dockLeft ??
        bubbleDockedLeft(x: pos.x, widthDp: probe, screenWidthDp: screenW);
    final x = bubbleSnapX(
      dockLeft: left,
      widthDp: widthDp,
      screenWidthDp: screenW,
    );
    final y = bubbleClampY(
      y: pos.y,
      heightDp: heightDp,
      screenHeightDp: screenH,
      resetY: resetY,
    );
    final moved = await _withTimeout(
      'moveOverlay()',
      FlutterOverlayWindow.moveOverlay(OverlayPosition(x, y)),
    );
    if (moved == true) {
      debugPrint(
        '📌 Bubble snapped to ${left ? 'left' : 'right'} '
        '(x=$x y=$y, screen=${screenW.toStringAsFixed(1)}x${screenH.toStringAsFixed(1)})',
      );
      _notifyOverlayDockSide(dockLeft: left);
    }
  } catch (e) {
    debugPrint('⚠️ Bubble snap failed: $e');
  }
}

/// True while (or most recently while) the CURRENTLY showing capture screen
/// was reached via the manual Status-screen trigger ([_showCaptureScreenManually])
/// rather than a real unlock ([_showCaptureScreen]). Set synchronously inside
/// [_presentCaptureOverlay] — mirrors [_overlayIsActive]'s "before the await,
/// not after" rule for the same reason: a fresh presentation must see the
/// correct value the instant its own preset-push message goes out, not
/// whatever the previous session left behind.
///
/// This is how the overlay isolate — which cannot tell a real unlock from a
/// manual trigger on its own; both take the exact same `showOverlay()` code
/// path — learns which kind of session it's currently running, so it can
/// skip persisting an answer that came from a tester tapping "Show me the
/// prompt now" rather than an actual unlock. See docs/BACKLOG.md's [P1]
/// "manual trigger arms real cooldown" entry for the bug this fixes, and
/// [_replyActivePresetsToOverlay] for how this value reaches the overlay
/// (piggybacked on the same preset-push/reply message, not a second one).
bool _currentPresentIsManual = false;

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

/// Name for a FIFTH same-process port, background → overlay (same direction
/// as [_overlayConfigPortName], so also registered by the OVERLAY isolate
/// itself, not by `backgroundMain`). Carries the "screen locked" signal used
/// by T12 (docs/erd/sprint4-app-shell-plan-2026-07-23.md §3a): a live
/// CAPTURE SCREEN on lock is a stale, unanswered question and should close
/// (otherwise the next unlock wrongly logs `overlay_active` — a skip that
/// isn't really one); a live BUBBLE (an outstanding intent) stays up,
/// unchanged from today's behaviour. Only the overlay isolate knows its own
/// `_mode`, so the close-or-not decision has to be made there, not here.
const String _lockSignalPortName = 'com.whydidiunlock.lock_signal_port';

/// Sent from `backgroundMain`'s `onLock` handler, only when
/// [_overlayIsActive] (no point signalling when nothing is showing). Mirrors
/// [_signalOverlayClosed]'s fire-and-forget lookup-by-name style; a not-found
/// port just means the overlay isolate hasn't registered it (e.g. never shown
/// this process), not an error.
void _signalLockToOverlay() {
  final port = IsolateNameServer.lookupPortByName(_lockSignalPortName);
  if (port == null) {
    debugPrint('⚠️ Could not find lock-signal port — overlay not active/registered?');
    return;
  }
  port.send(true);
}

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
///
/// Returns `true` if the message was actually sent to the background isolate,
/// `false` if its port couldn't be found (the background engine hasn't
/// registered it yet, or isn't running at all). This return value was added
/// after an on-device investigation (2026-07-23, T6 manual testing) found the
/// button silently doing nothing when the background engine never started —
/// `void` let that failure look identical to success from the caller's side,
/// which directly contradicts this button's own purpose: "show me the prompt
/// now" exists to surface real problems (see the permission-check note on
/// `_showCaptureScreenManually` below), and a background engine that never
/// came up is exactly such a problem, not something to hide.
///
/// This is a **fire-and-forget send**, not a round trip — `true` means "the
/// port existed and the message was handed off," not "the capture screen is
/// now guaranteed to appear" (permission/overlay-active checks still happen
/// asynchronously on the other side, in `_showCaptureScreenManually`, and are
/// not reported back here). Good enough to distinguish "nothing will ever
/// happen" from "something is in flight" — richer round-trip status would
/// need a reply port, deferred as a future improvement if it's ever needed.
bool triggerCapturePromptManually({required int screenWidth, required int screenHeight}) {
  final port = IsolateNameServer.lookupPortByName(_manualPromptPortName);
  if (port == null) {
    debugPrint('⚠️ Could not find manual-prompt port — background engine not ready?');
    return false;
  }
  port.send({'screenWidth': screenWidth, 'screenHeight': screenHeight});
  return true;
}

@pragma("vm:entry-point")
void backgroundMain() {
  WidgetsFlutterBinding.ensureInitialized();
  ProblemReportLog.installHooks('background');

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
    _activeOverlayKind = _ActiveOverlayKind.none;
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
      _lastNativeWidthPx = width;
      _lastNativeHeightPx = height;
      await _showCaptureScreen(width, height);
      // After the prompt path, not before: a day-1 prefs/plugin call must
      // never sit on the unlock→capture hot path (`CLAUDE.md` §8). Failures
      // inside are swallowed; the in-app recap still runs on next launch.
      unawaited(maybePostDayOneNotification());
    } else if (call.method == 'onLock') {
      debugPrint('🔒 LOCK EVENT RECEIVED at ${DateTime.now()}');
      unawaited(ProblemReportLog.recordBreadcrumb(
        'background',
        _overlayIsActive ? 'lock → signaled to overlay' : 'lock (no overlay up)',
      ));
      // Only the CAPTURE screen should close on lock; a live bubble (an
      // outstanding intent) stays up — see _lockSignalPortName's doc and
      // docs/erd/sprint4-app-shell-plan-2026-07-23.md §3a. Skip the signal
      // entirely when no overlay is up at all.
      if (_overlayIsActive) {
        _signalLockToOverlay();
      }
    } else if (call.method == 'onOrientationChanged') {
      final args = (call.arguments as Map?) ?? const {};
      final width = (args['width'] as num?)?.toInt() ?? 0;
      final height = (args['height'] as num?)?.toInt() ?? 0;
      debugPrint('📐 ORIENTATION EVENT ${width}x$height at ${DateTime.now()}');
      await _onOrientationChanged(width, height);
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
      // Snooze is UI-only — must not depend on IntentStore being open
      // (direct-boot CE storage races would otherwise drop the snooze arm).
      if (map['type'] == 'snoozeStart') {
        final dpr = (map['dpr'] as num?)?.toDouble() ?? 1.0;
        _snoozeSession = _SnoozeSession(
          clientId: map['clientId'] as String? ?? '',
          text: map['text'] as String? ?? '',
          source: map['source'] as String? ?? 'custom',
          declaredAt: DateTime.fromMillisecondsSinceEpoch(
            (map['declaredAt'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
          ),
          presetId: (map['presetId'] as num?)?.toInt(),
          isManual: map['manual'] as bool? ?? false,
          dpr: dpr,
        );
        _snoozeActive = true;
        _overlayIsActive = false;
        _activeOverlayKind = _ActiveOverlayKind.none;
        _armSnoozeTimer();
        debugPrint('😴 Snooze armed for ${_bubbleSnoozeDuration.inMinutes}m');
        unawaited(ProblemReportLog.recordBreadcrumb('background', 'bubble snoozed'));
        return;
      }
      // Bubble visible (declare UI path) — set kind before DB so orientation
      // mid-declare cannot reopen a capture screen.
      if (map['type'] == 'bubbleShowing') {
        _activeOverlayKind = _ActiveOverlayKind.bubble;
        _bubbleOverlayText = map['text'] as String? ?? _bubbleOverlayText;
        _bubbleOverlayDpr = (map['dpr'] as num?)?.toDouble() ?? _bubbleOverlayDpr;
        debugPrint('🫧 Overlay kind=bubble (showing)');
        unawaited(ProblemReportLog.recordBreadcrumb('background', 'bubble showing'));
        return;
      }
      // Ad-hoc one-line notes from the OVERLAY isolate, which has no plugins
      // of its own (see ProblemReportLog's class doc) — this relay is how an
      // overlay-side event still reaches the on-device log. Deliberately
      // free-text but NEVER passed user-declared intent text — see call
      // sites in [_abandonLostBubble] etc.
      if (map['type'] == 'breadcrumb') {
        final msg = map['message'] as String?;
        if (msg != null) {
          unawaited(ProblemReportLog.recordBreadcrumb('overlay', msg));
        }
        return;
      }
      // Edge snap — no DB. See [_snapBubbleToEdge].
      if (map['type'] == 'bubbleSnap') {
        final widthDp = (map['widthDp'] as num?)?.toDouble() ?? bubbleCollapsedDp;
        final heightDp =
            (map['heightDp'] as num?)?.toDouble() ?? bubbleExpandedHeightDp;
        final screenWidthDp = (map['screenWidthDp'] as num?)?.toDouble() ?? 0;
        final screenHeightDp = (map['screenHeightDp'] as num?)?.toDouble() ?? 0;
        final dpr = (map['dpr'] as num?)?.toDouble() ?? 1.0;
        final detectWidthDp = (map['detectWidthDp'] as num?)?.toDouble();
        final dockLeft = map['dockLeft'] as bool?;
        final resetY = map['resetY'] as bool? ?? false;
        unawaited(_snapBubbleToEdge(
          widthDp: widthDp,
          heightDp: heightDp,
          screenWidthDp: screenWidthDp,
          screenHeightDp: screenHeightDp,
          dpr: dpr,
          dockLeft: dockLeft,
          detectWidthDp: detectWidthDp,
          resetY: resetY,
        ));
        return;
      }
      final store = await _ensureIntentStore();
      if (store == null) {
        // Gated per docs/PLAY_SUBMISSION.md §3b.1 — see _sendToBackground's
        // doc for why: `map` can carry the user's declared intent text.
        if (kDebugMode) debugPrint('⚠️ Dropping relayed message — IntentStore unavailable: $map');
        return;
      }
      switch (map['type']) {
        case 'declare':
          _clearSnoozeState();
          final event = IntentEvent.fromMessage(map);
          await store.insertOpenIntent(event);
          if (kDebugMode) debugPrint('📂 Intent opened: text="${event.text}"');
          // Breadcrumb intentionally omits event.text (user-declared content)
          // — see recordBreadcrumb's doc.
          unawaited(ProblemReportLog.recordBreadcrumb('background', 'intent declared'));
        case 'dismiss':
          _clearSnoozeState();
          final dismissal = IntentDismissal.fromMessage(map);
          await store.markIntentDone(clientId: dismissal.clientId, completedAt: dismissal.completedAt);
          debugPrint('✅ Intent marked done: clientId=${dismissal.clientId}');
          unawaited(ProblemReportLog.recordBreadcrumb('background', 'intent dismissed'));
        case 'noIntent':
          _clearSnoozeState();
          final event = IntentEvent.fromMessage(map);
          await store.insertEvent(event);
          if (kDebugMode) debugPrint('💾 Stored no-intent event: text="${event.text}"');
          unawaited(ProblemReportLog.recordBreadcrumb('background', 'no-intent unlock ("Just Like That")'));
        case 'requestPresets':
          await _replyActivePresetsToOverlay(store);
        default:
          if (kDebugMode) debugPrint('⚠️ Unknown relay message type (${map['type']}) — dropped: $map');
      }
    } catch (e) {
      // Gated: `message` (the raw, possibly-malformed payload) is included
      // for debugging and can still carry user text even when malformed.
      if (kDebugMode) debugPrint('⚠️ Ignoring malformed overlay message ($e): $message');
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
  ProblemReportLog.installHooks('overlay');
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      color: Colors.transparent,
      theme: beaconDarkTheme(),
      home: const OverlayRoot(),
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

/// Closes the overlay window without ever letting the plugin call become
/// load-bearing for state. **Always use this — never call
/// `FlutterOverlayWindow.closeOverlay()` directly.**
///
/// `closeOverlay()` is a plugin call, and plugin calls made from the OVERLAY
/// isolate are this codebase's documented hang hazard (`docs/ARCHITECTURE.md`
/// §5: `shareData()`'s native handler never replies so an awaited call hangs
/// forever; `isActive()` hangs below the Dart await where even `.timeout()`
/// can't see it). The plugin routes them through a single static native field
/// (`WindowSetup.messenger`) owned by whichever engine attached the plugin
/// last, so merely opening the app can leave the overlay isolate talking to a
/// detached messenger.
///
/// **Confirmed on-device 2026-08-15**, and it was the real root cause of
/// "unlock stopped prompting" (the two earlier fixes addressed different
/// failure modes and never fired): `_handleLockSignal` logged "closing
/// capture screen on lock" and then never reached its very next statement,
/// `_signalOverlayClosed()` — twice in a row, with `🔵 Overlay closed signal
/// received` never appearing on the background side. `_overlayIsActive`
/// therefore stayed true forever and no unlock prompted again until a
/// force-stop. A hung `await` doesn't block the isolate's event loop, which
/// is why each later lock printed the same line and hung again identically.
///
/// **The rule this encodes: a pure-Dart state signal must never sit
/// downstream of a plugin call that can hang.** Every caller has to be able
/// to reach its `_signalOverlayClosed()` / reopen / state reset no matter
/// what the plugin does, so this swallows both a hang and a throw and always
/// returns. Worst case the window outlives its close by the timeout — vastly
/// cheaper than the app silently never prompting again.
Future<void> _closeOverlayWindow(String label) async {
  try {
    final closed = await _withTimeout(
      'closeOverlay($label)',
      FlutterOverlayWindow.closeOverlay().then((_) => true),
    );
    if (closed == null) {
      // Breadcrumbed, not just debugPrinted: this is the fingerprint of the
      // 2026-08-15 root cause, and release builds are exactly where nobody is
      // watching logcat. Relayed from whichever isolate hit it — the overlay
      // isolate has no plugins of its own (see ProblemReportLog's class doc).
      _sendToBackground({'type': 'breadcrumb', 'message': 'closeOverlay($label) hung — continued anyway'});
    }
  } catch (e) {
    debugPrint('⚠️ closeOverlay($label) threw (continuing anyway): $e');
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
  // Fire-and-forget, unconditional (not inside the try/store-gated block
  // below) — same "must never sit on the unlock path, must never suppress
  // the prompt" reasoning as this function's own doc comment, and it must
  // survive an unavailable IntentStore too, since "store keeps failing to
  // open" is itself exactly the kind of thing a breadcrumb trail should show.
  unawaited(ProblemReportLog.recordBreadcrumb(
    'background',
    promptShown ? 'unlock → prompt shown' : 'unlock → skipped (${skipReason?.name ?? "unknown"})',
  ));
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

  // Unlock ends snooze early — before triage / capture (R5b).
  if (_snoozeActive) {
    debugPrint('😴 Unlock ends snooze — restoring bubble');
    await _restoreSnoozedBubble();
    await _logUnlock(unlockedAt: unlockedAt, promptShown: false, skipReason: SkipReason.snoozeEnded);
    return;
  }

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

  final shown = await _presentCaptureOverlay(screenWidth, screenHeight, manual: false);
  // Logged AFTER showOverlay(), not before: the prompt reaching the screen is
  // the time-critical part (CLAUDE.md §8's ~500ms target); this write is not
  // (docs/DATA_MODEL.md §3c). A timed-out showOverlay must NOT count as shown.
  if (!shown) {
    await _logUnlock(unlockedAt: unlockedAt, promptShown: false, skipReason: SkipReason.pluginTimeout);
    return;
  }
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
///
/// [manual] distinguishes the two callers for [_currentPresentIsManual] (see
/// that variable's doc) — `false` from the real-unlock path, `true` from the
/// manual Status-screen trigger. Required, not defaulted, so a future third
/// caller can't accidentally inherit the wrong value by omission.
///
/// Returns `true` if `showOverlay()` completed; `false` if it timed out (in
/// which case [_overlayIsActive] is reset so the next unlock can try again —
/// without that reset, a hung `showOverlay()` would leave the flag stuck
/// `true` forever and every later unlock would silently skip as
/// `overlay_active`).
Future<bool> _presentCaptureOverlay(int screenWidth, int screenHeight, {required bool manual}) async {
  // Set BEFORE showOverlay(), same reasoning as _overlayIsActive just below:
  // the preset/manual push that follows showOverlay() must see the value for
  // THIS presentation, not a stale one from whatever was shown previously.
  _currentPresentIsManual = manual;
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
  _activeOverlayKind = _ActiveOverlayKind.capture;
  // showOverlay() was the one plugin call on this path NOT under
  // `_withTimeout`. Same defect class as isActive()/shareData()
  // (ARCHITECTURE.md §5 — shared native messenger hijack): if the await
  // never returns, `_overlayIsActive` stays true and every later unlock
  // silently skips. Force-stop "fixed" that by resetting process state.
  // `.then((_) => true)` makes the void Future observable as null-on-timeout.
  final shown = await _withTimeout(
    'showOverlay()',
    FlutterOverlayWindow.showOverlay(
      height: screenHeight,
      width: screenWidth,
      alignment: OverlayAlignment.topLeft,
      flag: OverlayFlag.focusPointer,
      startPosition: const OverlayPosition(0, 0),
      overlayTitle: appDisplayName,
      overlayContent: 'Declare your intent',
    ).then((_) => true),
  );
  if (shown == null) {
    _overlayIsActive = false;
    _activeOverlayKind = _ActiveOverlayKind.none;
    debugPrint('⏱️ showOverlay() timed out — resetting _overlayIsActive');
    return false;
  }
  debugPrint('🟣 showOverlay called (${screenWidth}x$screenHeight capture screen)');

  // Push a fresh preset list on EVERY capture present — real unlock or
  // manual trigger, cold overlay-engine start or a long-cached engine being
  // reused. Fixes docs/BACKLOG.md's [P0] "overlay presets go stale for an
  // entire session" bug: the overlay isolate only ever refreshed its
  // `_presets` in `initState` and after a bubble dismiss, so a session that
  // went through "Just Like That" answers (no dismiss) or simply never
  // showed a bubble again after a Manage Options edit kept serving a stale
  // list — sometimes for the engine's entire remaining lifetime, until a
  // reboot. See docs/ARCHITECTURE.md §8.1 for the general "cached engine
  // holding stale state" pattern this fits.
  //
  // Fire-and-forget and best-effort, not awaited before returning: this must
  // not sit on the unlock hot path (CLAUDE.md §8's ~500ms target — the same
  // reason `_logUnlock` above is also un-awaited-relative-to-the-caller by
  // running after `showOverlay()`, not before it). On a truly cold overlay
  // engine start, `_overlayConfigPortName` may not be registered yet (the
  // overlay's own `initState` hasn't run far enough) — that's fine, because
  // the overlay's own `_requestPresets()` pull (with its bounded retry,
  // called from `initState`) is what reliably lands presets in that case.
  // This push exists specifically for every OTHER present, where the port
  // is already live from a previous show and there is no reason to wait for
  // the overlay to notice anything changed.
  unawaited(_ensureIntentStore().then((store) {
    if (store != null) _replyActivePresetsToOverlay(store);
  }));
  return true;
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
  final shown = await _presentCaptureOverlay(screenWidth, screenHeight, manual: true);
  if (!shown) {
    debugPrint('🧪 Manual prompt trigger: showOverlay timed out');
    return;
  }
  debugPrint('🧪 Manual prompt shown (Status screen trigger)');
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: beaconDarkTheme(),
      home: const AppLauncher(),
    );
  }
}

/// Decides between the 5-step onboarding flow (T4) and `HomeScreen`, based on
/// `AppSettings.onboardingCompleted()` — the same flag `OnboardingScreen`
/// itself sets on its last step. Previously `MyApp` went straight to
/// `HomeScreen` unconditionally, which is why onboarding existed as a file
/// but nobody ever saw it: nothing decided to show it.
///
/// A user upgrading from a pre-onboarding install (the flag was never
/// written) sees the flow once — deliberate, not a bug: `onboardingCompleted`
/// is intentionally its own flag rather than inferred from e.g. "has the
/// overlay permission" (see that method's doc comment), so there is no other
/// signal to check.
class AppLauncher extends StatefulWidget {
  const AppLauncher({super.key});

  @override
  State<AppLauncher> createState() => _AppLauncherState();
}

class _AppLauncherState extends State<AppLauncher> {
  /// Null while the check is in flight — deliberately a blank black screen
  /// for that brief window rather than a spinner, matching this app's other
  /// "no flash of stale/loading UI" choices (docs/DATA_MODEL.md §4).
  bool? _onboardingCompleted;
  bool _showDayOneRecap = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Same defensive timeout posture as the unlock path's plugin/DB calls:
    // SharedPreferencesAsync has no timeout of its own, and a hung read here
    // leaves AppLauncher on the blank black Scaffold forever (null
    // `_onboardingCompleted`) until force-stop. On timeout, degrade to
    // "already onboarded" so a returning user reaches Home instead of
    // re-seeing onboarding or staying stuck — wrong less often than a
    // permanent blank screen after reboot.
    final completed = await _withTimeout(
      'AppSettings.onboardingCompleted()',
      _appSettings.onboardingCompleted(),
    );
    await _appSettings.ensureFirstLaunchAt(DateTime.now());
    var showRecap = false;
    if (completed != false) {
      showRecap = await _withTimeout(
            'dayOneRecapShouldShow()',
            dayOneRecapShouldShow(_appSettings, DateTime.now()),
          ) ??
          false;
    }
    if (mounted) {
      setState(() {
        _onboardingCompleted = completed ?? true;
        _showDayOneRecap = showRecap;
      });
    }
    // Shade tap while Home is already up should open the recap if it is
    // still due. Widget tests may hit a missing plugin — bind swallows it.
    if (completed != false) {
      DayOneNotifications.bindUiTapHandler(_showRecapFromNotificationTap);
    }
  }

  void _showRecapFromNotificationTap() {
    unawaited(_openRecapIfStillDue());
  }

  Future<void> _openRecapIfStillDue() async {
    final due = await dayOneRecapShouldShow(_appSettings, DateTime.now());
    if (!mounted || !due) return;
    setState(() => _showDayOneRecap = true);
  }

  Future<void> _dismissDayOneRecap() async {
    await _appSettings.setDayOneNudgeShown(true);
    if (mounted) setState(() => _showDayOneRecap = false);
  }

  @override
  Widget build(BuildContext context) {
    final completed = _onboardingCompleted;
    if (completed == null) {
      return const Scaffold(backgroundColor: Colors.black);
    }
    if (!completed) {
      return OnboardingScreen(
        onShowPromptNow: triggerCapturePromptManually,
        onFinished: () {
          if (mounted) setState(() => _onboardingCompleted = true);
        },
      );
    }
    if (_showDayOneRecap) {
      return DayOneStatsScreen(onFinished: _dismissDayOneRecap);
    }
    return const HomeScreen();
  }
}

enum _OverlayMode { capture, bubble }

enum _BubbleUiMode { expanded, collapsed }

class OverlayRoot extends StatefulWidget {
  const OverlayRoot({super.key});

  @override
  State<OverlayRoot> createState() => _OverlayRootState();
}

class _OverlayRootState extends State<OverlayRoot> {
  _OverlayMode _mode = _OverlayMode.capture;
  _BubbleUiMode _bubbleUiMode = _BubbleUiMode.expanded;
  String _intentText = '';
  String _intentSource = '';
  DateTime? _declaredAt;
  String? _intentClientId;
  int? _intentPresetId;
  Timer? _autoCollapseTimer;
  Timer? _snapDebounce;

  /// Which horizontal edge the bubble last occupied (from background dock
  /// notify after drag snap, or left/right show). Expand uses matching
  /// [OverlayAlignment] so we never `resizeOverlay` under stale `x`.
  bool _dockedLeft = false;

  /// Presets to render on the capture screen — empty until the first reply
  /// arrives. An empty list is a deliberately valid, already-tested state
  /// (docs/DATA_MODEL.md §7: "zero enabled presets is a valid, non-throwing
  /// state"), so the brief window between this engine's cold start and the
  /// first reply landing degrades to exactly that same state rather than
  /// needing a separate loading UI — no spinner, no flash of stale data.
  List<CapturePreset> _presets = [];

  /// Whether at least one config reply has arrived from the background
  /// isolate this engine lifetime. Distinguishes "still waiting" from
  /// "received an intentionally empty active-preset list" so
  /// [_requestPresets] can keep retrying when background aborts a reply
  /// (e.g. `activePresets` timed out and correctly refused to send `[]`).
  bool _presetsConfigReceived = false;

  /// Completer for the in-flight [_requestPresets] wait — completed by the
  /// config-port listener when any reply lands so we don't stack concurrent
  /// `activePresets` queries on a still-warming post-reboot store.
  Completer<void>? _presetsReplyCompleter;

  /// Whether the capture screen CURRENTLY showing (or most recently shown)
  /// was reached via the manual Status-screen trigger rather than a real
  /// unlock — see [_currentPresentIsManual]'s doc in the background isolate
  /// for the full story. Read at answer time ([_submitIntent]/
  /// [_submitNoIntent]/[_dismissBubble]) to skip persisting a test tap as if
  /// it were a real declared/no-intent event (docs/BACKLOG.md's [P1] "manual
  /// trigger arms real cooldown"). Defaults `false` (real) so a session
  /// answered before the very first config reply lands — the same
  /// brief-race window already accepted for [_presets] — errs toward NOT
  /// silently dropping a real write, rather than toward under-persisting.
  bool _sessionIsManual = false;

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
    debugPrint('🔧 Overlay: config reply port registered');
    configPort.listen((message) {
      debugPrint('📥 Overlay: received config reply: $message');
      final map = message as Map;
      final msgType = map['type'] as String?;
      if (msgType == 'bubbleRepositioned') {
        // Background did one orientation close+reopen at right-center.
        if (mounted) {
          setState(() {
            _bubbleUiMode = _BubbleUiMode.collapsed;
            _dockedLeft = false;
          });
          _cancelAutoCollapse();
        }
        return;
      }
      if (msgType == 'bubbleDocked') {
        _dockedLeft = map['dockLeft'] as bool? ?? false;
        return;
      }
      final rawPresets = (map['presets'] as List?) ?? const [];
      // `manual` rides the same message as presets — see
      // _replyActivePresetsToOverlay's doc for why this is one message, not
      // two (a second, presets-less message on this port would otherwise be
      // misread as "zero active presets").
      final rawManual = map['manual'] as bool? ?? false;
      if (mounted) {
        setState(() {
          _presetsConfigReceived = true;
          _presets = rawPresets
              .map((p) => CapturePreset(id: (p as Map)['id'] as int, label: p['label'] as String))
              .toList();
          _sessionIsManual = rawManual;
        });
        final pending = _presetsReplyCompleter;
        if (pending != null && !pending.isCompleted) pending.complete();
        debugPrint(
          '📥 Overlay: _presets now has ${_presets.length} entr${_presets.length == 1 ? 'y' : 'ies'}, '
          'manual=$_sessionIsManual',
        );
      } else {
        debugPrint('⚠️ Overlay: config reply arrived but widget was unmounted, dropped');
      }
    });
    // Port registration above MUST complete before this request is sent —
    // it does, since both are synchronous statements with no await between
    // them, so there's no window where background could look up a port that
    // doesn't exist yet.
    _requestPresets();

    // T12: registered the same way as configPort above (by this isolate,
    // not backgroundMain) — see _lockSignalPortName's doc.
    IsolateNameServer.removePortNameMapping(_lockSignalPortName);
    final lockSignalPort = ReceivePort();
    IsolateNameServer.registerPortWithName(lockSignalPort.sendPort, _lockSignalPortName);
    lockSignalPort.listen((_) => _handleLockSignal());
  }

  @override
  void dispose() {
    _autoCollapseTimer?.cancel();
    _snapDebounce?.cancel();
    super.dispose();
  }

  Size? _screenSizeDp() {
    final displays = PlatformDispatcher.instance.displays;
    if (displays.isNotEmpty) {
      final d = displays.first;
      if (d.size.width > 0 && d.devicePixelRatio > 0) {
        return Size(
          d.size.width / d.devicePixelRatio,
          d.size.height / d.devicePixelRatio,
        );
      }
    }
    final views = PlatformDispatcher.instance.views;
    if (views.isEmpty) return null;
    final view = views.first;
    final size = view.display.size;
    if (size.width <= 0 || size.height <= 0 || view.devicePixelRatio <= 0) {
      return null;
    }
    return Size(
      size.width / view.devicePixelRatio,
      size.height / view.devicePixelRatio,
    );
  }

  double _currentBubbleWidthDp() {
    return _bubbleUiMode == _BubbleUiMode.expanded
        ? expandedBubbleWidthDp(_intentText)
        : bubbleCollapsedDp;
  }

  /// Drag-end edge snap via background [moveOverlay]. Rotation is native →
  /// background close+reopen — do not snap from overlay metrics.
  void _requestBubbleSnap({
    required double widthDp,
    bool? dockLeft,
    bool resetY = false,
  }) {
    final screen = _screenSizeDp();
    final dpr = MediaQuery.of(context).devicePixelRatio;
    if (dockLeft != null) _dockedLeft = dockLeft;
    _sendToBackground({
      'type': 'bubbleSnap',
      'widthDp': widthDp,
      'heightDp': bubbleExpandedHeightDp,
      'screenWidthDp': screen?.width ?? 0,
      'screenHeightDp': screen?.height ?? 0,
      'dpr': dpr,
      'dockLeft': ?dockLeft,
      'resetY': resetY,
    });
  }

  void _scheduleSnapAfterInteraction() {
    _snapDebounce?.cancel();
    _snapDebounce = Timer(const Duration(milliseconds: 120), () {
      if (!mounted || _mode != _OverlayMode.bubble) return;
      _requestBubbleSnap(widthDp: _currentBubbleWidthDp());
    });
  }

  Future<void> _showBubbleWindow({
    required bool expanded,
    bool? dockLeft,
  }) async {
    final left = dockLeft ?? _dockedLeft;
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final widthDp = expanded ? expandedBubbleWidthDp(_intentText) : bubbleCollapsedDp;
    final heightDp = bubbleExpandedHeightDp;
    // Guarded too: a hang HERE would skip both the reopen below and the
    // _abandonLostBubble() recovery, stranding the bubble with no window and
    // no reset — the earlier fix's blind spot.
    await _closeOverlayWindow('bubble resize');
    // GUARDED, and it must stay that way — this close+reopen is the overlay
    // isolate's twin of the background-path bug fixed in _presentCaptureOverlay
    // (docs/BACKLOG.md "hung showOverlay() left _overlayIsActive stuck true"),
    // and it was left unguarded when that one was fixed. Confirmed on-device
    // 2026-08-13: the window vanished with the process still alive (no LMK
    // kill, no crash in logcat), background still logging "🟡 Overlay already
    // active" on every unlock and the overlay isolate still answering the lock
    // signal with "bubble is live" — i.e. BOTH sides believed a bubble was up
    // while the screen had none, and force-stop was the only recovery.
    //
    // This path is far more exposed than the capture path: it runs on EVERY
    // expand/collapse, including the unattended auto-collapse timer, which
    // reaches it through `unawaited(...)` — so a raw throw here becomes an
    // unhandled async error that release builds swallow without a trace,
    // which is exactly why the original failure left no fingerprint. Hence
    // both a timeout AND a catch-all: once closeOverlay() has succeeded, ANY
    // failure to reopen means the window is gone for good.
    var reopened = false;
    try {
      reopened = await _withTimeout(
            'showOverlay(bubble resize)',
            FlutterOverlayWindow.showOverlay(
              height: (heightDp * dpr).round(),
              width: (widthDp * dpr).round(),
              // Always centerRight so drag-snap [moveOverlay] coords stay
              // consistent (x=0 = right). Left dock is a single post-show
              // move with resetY.
              alignment: OverlayAlignment.centerRight,
              flag: OverlayFlag.defaultFlag,
              overlayTitle: appDisplayName,
              overlayContent: _intentText,
              enableDrag: true,
              positionGravity: PositionGravity.none,
            ).then((_) => true),
          ) ??
          false;
    } catch (e) {
      debugPrint('⚠️ Overlay: bubble reopen threw ($e)');
    }
    if (!reopened) {
      await _abandonLostBubble();
      return;
    }
    if (left) {
      _requestBubbleSnap(widthDp: widthDp, dockLeft: true, resetY: true);
    } else {
      _dockedLeft = false;
    }
  }

  /// Last resort when [_showBubbleWindow]'s reopen fails: the bubble's window
  /// is already closed and is not coming back, so the only question left is
  /// whether the app notices.
  ///
  /// Fails OPEN, deliberately. Losing one bubble costs the user a single
  /// outstanding intent; leaving the two "is an overlay showing" flags stuck
  /// true costs them the app's entire core loop — every subsequent unlock
  /// skips as `overlay_active` with no prompt, no bubble and no error, until
  /// a force-stop they have no reason to think of. The declared intent's row
  /// was already persisted at declare time (see [_submitIntent]) and is
  /// deliberately NOT marked done here: it was abandoned, not completed, and
  /// writing a false completion would also arm [TimeCooldownPolicy] against
  /// the next real unlock.
  Future<void> _abandonLostBubble() async {
    debugPrint('🩹 Overlay: bubble window lost — resetting to capture so unlocks keep prompting');
    // Relayed to background (this isolate has no plugins of its own — see
    // ProblemReportLog's class doc) — the single most useful breadcrumb this
    // change adds, since this is precisely the recovery path for the 2026-08-13
    // stuck-overlay bug; if it ever fires in the field, a report should show it.
    _sendToBackground({'type': 'breadcrumb', 'message': 'bubble window lost — recovered to capture'});
    _cancelAutoCollapse();
    _snapDebounce?.cancel();
    // Clears the background isolate's _overlayIsActive. Safe to call for a
    // window that is already gone — this is exactly the "real close" it
    // means, just reached by failure rather than by the user.
    _signalOverlayClosed();
    // Same reset as _dismissBubble, and for the same reason: the plugin
    // caches this engine, so without it the next unlock reattaches a cached
    // view still in bubble mode inside a full-screen capture window, which
    // swallows every touch and blocks the phone.
    if (mounted) {
      setState(() {
        _mode = _OverlayMode.capture;
        _intentText = '';
        _intentSource = '';
        _declaredAt = null;
        _intentClientId = null;
        _intentPresetId = null;
        _bubbleUiMode = _BubbleUiMode.expanded;
        _dockedLeft = false;
        _sessionIsManual = false;
      });
    }
    _requestPresets();
  }

  void _cancelAutoCollapse() {
    _autoCollapseTimer?.cancel();
    _autoCollapseTimer = null;
  }

  void _scheduleAutoCollapse() {
    _cancelAutoCollapse();
    _autoCollapseTimer = Timer(_bubbleAutoCollapseDelay, () {
      if (!mounted || _mode != _OverlayMode.bubble) return;
      if (_bubbleUiMode == _BubbleUiMode.collapsed) return;
      unawaited(_setBubbleExpanded(false));
    });
  }

  /// Reacts to a lock signal relayed from the background isolate (see
  /// _lockSignalPortName). Only closes the CAPTURE screen — a stale,
  /// unanswered question on lock is noise, and leaving it open makes the
  /// next unlock wrongly log `overlay_active` (a skip that isn't really one).
  /// A live BUBBLE (an outstanding intent) is left running unchanged; this
  /// iteration's behaviour there stays exactly what it is today (see
  /// docs/erd/sprint4-app-shell-plan-2026-07-23.md §3a/§7.1).
  ///
  /// Deliberately does NOT reset `_mode`/`_intentText`/any capture-screen
  /// widget state the way `_dismissBubble` does for the bubble path — the
  /// overlay engine is cached and its widget tree survives `closeOverlay()`
  /// (that's exactly why `_dismissBubble` NEEDS an explicit reset, or a stale
  /// bubble reappears). Leaving this path bare means `IntentCaptureScreen`'s
  /// `TextEditingController` — and any partially-typed text in it — survives
  /// the close+reopen untouched: the next unlock's capture screen (if triage
  /// lets one through) resumes the same draft rather than starting blank.
  /// Only the WINDOW closes; the conversation the user was mid-typing does
  /// not reset.
  Future<void> _handleLockSignal() async {
    if (_mode != _OverlayMode.capture) {
      debugPrint('🔒 Overlay: lock signal ignored — bubble is live, staying up');
      return;
    }
    debugPrint('🔒 Overlay: closing capture screen on lock');
    await _closeOverlayWindow('lock');
    // Tells the background isolate this is a REAL close (not the
    // close+reopen resize in _submitIntent) — see _overlayIsActive.
    _signalOverlayClosed();
  }

  /// Sends a `requestPresets` message over the existing intent-write port
  /// (reusing that channel rather than adding a second overlay→background
  /// port — see docs/DATA_MODEL.md §4). Called once at engine cold start
  /// (`initState`) and again every time the overlay returns to capture mode
  /// after a dismissal, so a preset edited via the Settings/manage-presets
  /// screens (a different engine entirely) is picked up on the NEXT capture
  /// screen rather than staying stale for this cached engine's entire
  /// lifetime.
  /// Retries a bounded number of times if the background isolate's port
  /// isn't found yet — confirmed on-device 2026-07-23 as a real, if brief,
  /// startup race (background can legitimately not have registered its ports
  /// yet at the exact moment this overlay engine's `initState` fires, e.g.
  /// if `backgroundMain` is mid-restart). Without a retry, that single
  /// failure was permanent: this only ever fires once per cached overlay
  /// engine's lifetime from `initState`, so a lost first attempt meant no
  /// presets for every unlock reusing that same engine afterward — not a
  /// one-off flake, a standing failure until the process itself restarted.
  ///
  /// Also keeps requesting until a config *reply* arrives (or attempts are
  /// exhausted): a successful *send* alone is not enough — background may
  /// receive `requestPresets` and then abort without replying when
  /// `activePresets()` times out (see [_replyActivePresetsToOverlay]). The
  /// older "return on first successful send" left the overlay stuck with
  /// `_presets = []` for the rest of that engine's life.
  ///
  /// Waits on a Completer between attempts (not a fixed short delay) so we
  /// don't stack five concurrent `activePresets` queries against a
  /// still-warming post-reboot DB. ~6s per attempt × 5 covers the
  /// background-side timeout+retry window without looking like a hang.
  Future<void> _requestPresets() async {
    const maxAttempts = 5;
    const replyWait = Duration(seconds: 6);
    const portRetryDelay = Duration(milliseconds: 400);
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      if (_presetsConfigReceived) return;
      debugPrint('📮 Overlay: sending requestPresets (attempt $attempt/$maxAttempts)');
      if (!_sendToBackground({'type': 'requestPresets'})) {
        if (attempt < maxAttempts) await Future.delayed(portRetryDelay);
        continue;
      }
      final completer = Completer<void>();
      _presetsReplyCompleter = completer;
      try {
        await completer.future.timeout(replyWait);
        return;
      } on TimeoutException {
        debugPrint('📮 Overlay: no config reply within ${replyWait.inSeconds}s (attempt $attempt/$maxAttempts)');
      }
    }
    if (!_presetsConfigReceived) {
      debugPrint('⚠️ Overlay: giving up on requestPresets after $maxAttempts attempts — no config reply');
    }
  }

  Future<void> _setBubbleExpanded(bool expanded) async {
    if (_mode != _OverlayMode.bubble) return;
    final next = expanded ? _BubbleUiMode.expanded : _BubbleUiMode.collapsed;
    if (_bubbleUiMode == next) return;
    _snapDebounce?.cancel();
    final dockLeft = _dockedLeft;
    if (mounted) setState(() => _bubbleUiMode = next);
    if (expanded) {
      _scheduleAutoCollapse();
    } else {
      _cancelAutoCollapse();
    }
    // Always close+reopen with left/right alignment — never resizeOverlay
    // alone (keeps WindowManager x fixed under centerRight → off-screen pill).
    await _showBubbleWindow(expanded: expanded, dockLeft: dockLeft);
  }

  Future<void> _toggleBubbleExpand() async {
    await _setBubbleExpanded(_bubbleUiMode != _BubbleUiMode.expanded);
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
    // Gated per docs/PLAY_SUBMISSION.md §3b.1 — `trimmed` is the user's own
    // declared-intent text; debugPrint is not stripped from release builds.
    if (kDebugMode) {
      debugPrint('📝 Intent declared: "$trimmed" (source: $source) at $declaredAt');
    }

    setState(() {
      _intentText = trimmed;
      _intentSource = source;
      _declaredAt = declaredAt;
      _intentClientId = clientId;
      _intentPresetId = presetId;
      _mode = _OverlayMode.bubble;
      _bubbleUiMode = _BubbleUiMode.expanded;
      _dockedLeft = false;
    });

    // Tell background kind=bubble BEFORE close+reopen so orientation cannot
    // reopen a capture screen mid-declare (manual sessions skip DB declare).
    final dpr = MediaQuery.of(context).devicePixelRatio;
    _relayBubbleShowing(text: trimmed, dpr: dpr);

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
    //
    // Skipped entirely for a manual (Status-screen "show me the prompt now")
    // session — see docs/BACKLOG.md's [P1] "manual trigger arms real
    // cooldown": persisting a test tap's answer poisoned TimeCooldownPolicy's
    // MAX(completed_at) read for the very next REAL unlock. The bubble/UI
    // transition below still happens unconditionally — only the DB write is
    // gated, so a manual session still looks and behaves like a real one to
    // whoever is testing it.
    if (!_sessionIsManual) {
      _relayDeclaredIntent(IntentEvent(
        clientId: clientId,
        kind: IntentKind.intent,
        source: _intentSourceFromString(source),
        text: trimmed,
        declaredAt: declaredAt,
        completedAt: declaredAt,
        presetId: presetId,
      ));
    } else {
      debugPrint('🧪 Manual session — skipping intent_log declare write');
    }

    // The capture screen's window is created focusable (needed for the text
    // field's keyboard). Flipping to a non-focusable flag in place via
    // updateFlag()/resizeOverlay() doesn't reliably make Android release
    // focus it already granted, which is what was blocking touches/keyboard/
    // back-gesture in every other app. Closing and reopening a fresh window
    // at bubble size with defaultFlag (non-focusable from birth) avoids that
    // — the Flutter engine and this widget's state survive the recreation.
    await _showBubbleWindow(expanded: true, dockLeft: false);
    _scheduleAutoCollapse();
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
    //
    // Skipped for a manual session — see the matching comment in
    // _submitIntent and docs/BACKLOG.md's [P1] entry. This was in fact the
    // exact repro that surfaced the bug: a manual trigger answered with
    // "Just Like That" wrote a real completed_at that armed cooldown for the
    // next real unlock.
    if (!_sessionIsManual) {
      final event = IntentEvent(
        clientId: _generateClientId(now),
        kind: IntentKind.noIntent,
        source: null,
        text: noIntentLabel,
        declaredAt: now,
        completedAt: now,
      );
      _relayNoIntent(event);
    } else {
      debugPrint('🧪 Manual session — skipping intent_log no-intent write');
    }

    await _closeOverlayWindow('no-intent');
    // Tells the background isolate this is a REAL close (not the
    // close+reopen resize in _submitIntent) — see _overlayIsActive.
    _signalOverlayClosed();
    // Defensive reset for whatever session comes next, in case its own
    // config reply is somehow delayed past the moment it's answered — see
    // _sessionIsManual's doc for why `false` (real) is the safer default to
    // fall back to than leaving this session's `true` lingering.
    _sessionIsManual = false;
  }

  Future<void> _snoozeBubble() async {
    if (_mode != _OverlayMode.bubble) return;
    _cancelAutoCollapse();
    final dpr = MediaQuery.of(context).devicePixelRatio;
    // Leave widget state in bubble+collapsed so a restore showOverlay paints
    // the chat-head, not a stale expanded pill or capture screen.
    if (mounted) {
      setState(() => _bubbleUiMode = _BubbleUiMode.collapsed);
    }
    _sendToBackground({
      'type': 'snoozeStart',
      'clientId': _intentClientId,
      'text': _intentText,
      'source': _intentSource,
      'declaredAt': _declaredAt?.millisecondsSinceEpoch,
      'presetId': _intentPresetId,
      'manual': _sessionIsManual,
      'dpr': dpr,
    });
    await _closeOverlayWindow('snooze');
    _signalOverlayClosed();
    // Gated per docs/PLAY_SUBMISSION.md §3b.1 — _intentText is the user's own
    // declared-intent text; debugPrint is not stripped from release builds.
    if (kDebugMode) {
      debugPrint('😴 Overlay: snoozed "$_intentText"');
    }
  }

  Future<void> _dismissBubble() async {
    final dismissedAt = DateTime.now();
    final activeFor = _declaredAt == null ? null : dismissedAt.difference(_declaredAt!);
    _cancelAutoCollapse();
    // Gated per docs/PLAY_SUBMISSION.md §3b.1 — see _submitIntent's doc.
    if (kDebugMode) {
      debugPrint(
        '✅ Intent dismissed: "$_intentText" (source: $_intentSource) '
        'declared at $_declaredAt, dismissed at $dismissedAt, active for $activeFor',
      );
    }

    // Only clientId + completedAt relayed here — kind/source/text/declaredAt
    // were already persisted by _submitIntent's declare-time relay above;
    // this just marks that same row (matched by clientId) done. See
    // IntentDismissal's doc and docs/DATA_MODEL.md §4. _intentClientId is
    // always non-null here: this is only reachable from bubble mode, which
    // _submitIntent only enters after setting it.
    //
    // Skipped for a manual session — see the matching comment in
    // _submitIntent and docs/BACKLOG.md's [P1] entry. _submitIntent already
    // skipped the declare write for this same session, so there is no open
    // row for this clientId to mark done anyway; relaying the dismissal here
    // would just be a wasted round-trip (or, on `markIntentDone`'s
    // no-matching-row path, silently do nothing) — either way, skip it.
    if (!_sessionIsManual) {
      _relayDismissal(IntentDismissal(clientId: _intentClientId!, completedAt: dismissedAt));
    } else {
      debugPrint('🧪 Manual session — skipping intent_log dismiss write');
    }

    await _closeOverlayWindow('dismiss');
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
        _intentPresetId = null;
        _bubbleUiMode = _BubbleUiMode.expanded;
        _dockedLeft = false;
        // Defensive reset, same reasoning as _submitNoIntent's — see
        // _sessionIsManual's doc.
        _sessionIsManual = false;
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
          // Always empty this iteration — see OutstandingIntent's doc (T12
          // plumbs the parameter only; nothing populates it yet).
          outstandingIntents: const [],
        );
      case _OverlayMode.bubble:
        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerUp: (_) => _scheduleSnapAfterInteraction(),
          onPointerCancel: (_) => _scheduleSnapAfterInteraction(),
          child: BubbleWidget(
            intentText: _intentText,
            expanded: _bubbleUiMode == _BubbleUiMode.expanded,
            onDone: () => unawaited(_dismissBubble()),
            onSnooze: () => unawaited(_snoozeBubble()),
            onToggleExpand: () => unawaited(_toggleBubbleExpand()),
          ),
        );
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

  /// Forward-compat only this iteration — see [OutstandingIntent]'s doc.
  /// Defaults to empty so existing call sites/tests are unaffected; not yet
  /// rendered anywhere.
  final List<OutstandingIntent> outstandingIntents;

  const IntentCaptureScreen({
    super.key,
    required this.presets,
    required this.onSubmit,
    required this.onNoIntent,
    this.outstandingIntents = const [],
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
                                    PresetPill(
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

/// "Just Like That" — a real pill so it reads as tappable (Dinesh's feedback
/// on the previous bare italic-underlined TextButton), but styled MUTED
/// relative to [PresetPill] (dimmer border/text, no fill) so it still
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



