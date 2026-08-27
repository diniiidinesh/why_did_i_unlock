# ARCHITECTURE — Why Did I Unlock

> System design reference. **Keep this updated whenever the engine topology, native
> components, event flows, or their rationale change.**
> For product context/decisions see `CLAUDE.md` (repo root); for the current PRD see `docs/PRD.md`.

This app is unusual for a Flutter app: it runs **three separate Flutter engines**
with different lifetimes and capabilities, plus native Android services/receivers.
Getting the topology wrong reintroduces bugs we've already fixed, so this document
exists to make the "why" durable.

## 1. The three Flutter engines

| Engine | Host (native) | Dart entry point | Lifetime | Plugins registered? | Job |
|---|---|---|---|---|---|
| **Main UI** | `MainActivity` (`FlutterActivity`) | `main()` → `MyApp` → `HomeScreen` | Ephemeral — dies when the Activity/task is destroyed (incl. swipe-away) | Yes (auto) | Show the settings/permission screen. Request the overlay permission (needs an Activity). Day-1 recap **tap** is handled here (`onDidReceiveNotificationResponse`) so a shade tap opens the recap if it is still due. |
| **Background** | `UnlockListenerService` (foreground service) | `backgroundMain()` | **Persistent** — lives as long as the foreground service (survives task removal) | Yes (auto) | The "brain": receive unlock/lock events, run prompt triage, call `showOverlay()`. Also the sole writer of the Sprint 3 `intent_log` DB — opens it once, subscribes `overlayListener`, inserts on every relayed event. **Day-1 recap reminder** (`flutter_local_notifications.show`) also runs here, piggybacking the existing unlock handler — never from overlay. |
| **Overlay** | `OverlayService` (from `flutter_overlay_window`) | `overlayMain()` → `OverlayRoot` | Cached; created lazily on first `showOverlay`, persists for the process | **No** (only the overlay plugin's own channel) | Render the capture screen and the hybrid bubble (Beacon frosted glass). Runs the capture→expanded→collapsed state machine. Theme: `beaconDarkTheme()` (same tokens as main UI). |

### Why three, and why this split

- **The background engine must survive task removal.** When the user swipes the app
  out of Recents, `MainActivity` (and its engine) is destroyed, but the foreground
  service survives. The unlock-reaction logic therefore CANNOT live in the UI engine
  — it lives in the background engine, tied to the service's lifecycle. (This was the
  P0 "app stops working after swipe-away" bug.)
- **The background engine must have plugins registered** so it can call
  `flutter_overlay_window`'s `showOverlay()`. A plain `FlutterEngine(context)`
  auto-registers plugins, which is why it can.
- **The overlay engine has NO plugins registered** (verified in the plugin's native
  source — it never calls `GeneratedPluginRegistrant.registerWith` for its engine).
  Consequences:
  - The overlay engine **cannot call `showOverlay()` on itself** — that's why the
    background engine (not the overlay engine) drives showing the capture screen.
  - The overlay engine **cannot call `sqflite`** (or any plugin) directly — including
    the day-1 `flutter_local_notifications` path, which is background-engine only. Sprint 3's
    intent-log writes are relayed from the overlay isolate to the **background**
    engine (confirmed the correct target, not "main" — see below) via
    `FlutterOverlayWindow.shareData()` / `overlayListener`.
- **Keeping the UI engine ephemeral is deliberate**, not a bug: the settings screen's
  isolate has no reason to persist while the app is closed. The app's dominant lifecycle
  state is "closed but monitoring," so the persistent footprint is a *minimal* headless
  background engine, not a full UI tree. (Rejected alternative: a single cached engine
  reused for UI + background — simpler, but keeps the whole UI tree resident 24/7, wrong
  for the low-end-device memory target.)

## 2. Native components

- **`MainActivity`** — launcher activity. Hosts the main UI engine. `onCreate` starts
  `UnlockListenerService`. Intentionally owns NO unlock method channel anymore.
- **`UnlockListenerService`** — foreground service (`specialUse`). On `onCreate`: posts
  its ongoing notification, creates/caches the **background engine** running
  `backgroundMain` and wires the `com.whydidiunlock/unlock` method channel to it, then
  runtime-registers `UnlockReceiver`. `START_STICKY` (OS restarts it if killed).
  Also overrides `onConfigurationChanged` (2026-07-24): reads real display size via
  `ScreenMetrics` and invokes `onOrientationChanged {width,height}` on the same
  channel so the background engine can reopen the overlay at the correct size after
  rotate (overlay Dart metrics are the *window*, not the phone — see §5).
- **`ScreenMetrics`** (added 2026-07-24) — shared Kotlin helper for true display size
  (`getRealMetrics`). Used by `UnlockReceiver` (unlock) and `UnlockListenerService`
  (orientation) so both paths share one definition of “screen”.
- **`UnlockReceiver`** — runtime-registered (NOT in the manifest — `ACTION_USER_PRESENT`
  can only be registered at runtime). Listens for `ACTION_USER_PRESENT` (unlock) and
  `ACTION_SCREEN_OFF` (lock). On unlock it computes the **true display size natively**
  via `ScreenMetrics` and passes it to Dart, because the headless background engine can't
  read display metrics itself.
- **`BootReceiver`** — manifest-registered, `exported="true"` (safe: `BOOT_COMPLETED` is
  a protected broadcast that can't be spoofed). Restarts the service after reboot. Also
  catches OEM quick-boot variants (`QUICKBOOT_POWERON`).
- **`UpdateReceiver`** (added 2026-07-23) — manifest-registered, listens for
  `ACTION_MY_PACKAGE_REPLACED` and restarts `UnlockListenerService`. Installing an app
  update always kills its running process (the OS can't hot-swap running code), and
  unlike a reboot this does NOT put the app into Android's "stopped" broadcast-
  withholding state — so without this receiver, nothing would ever restart the service
  after a real-world update (a Play push, or a manually installed newer APK), and
  monitoring would silently stay dead until the user happened to reopen the app. Found
  via an on-device build push during Sprint 4; `flutter run` masked it by auto-launching
  the app after every install. See `UpdateReceiver.kt`'s doc comment for the full
  distinction from `BootReceiver`'s mechanism.
- **`OverlayService`** — from the `flutter_overlay_window` plugin. Hosts the overlay
  engine, adds/removes the overlay window.

## 3. Channels

- **`com.whydidiunlock/unlock`** (native → background engine):
  `onUnlock` with `{width, height}` args (native-provided display size), `onLock`
  (no args), and `onOrientationChanged` with `{width, height}` (same size source as
  unlock — `ScreenMetrics`). Handler installed by `backgroundMain`.
- **`flutter_overlay_window` internal channels** (`x-slayer/*`): `showOverlay`,
  `closeOverlay`, `resizeOverlay`, `updateFlag` — window lifecycle only. The plugin's own
  `shareData`/`overlayListener` bridge is **not used** — see below.
- **`IsolateNameServer` ports** (pure Dart, same-process, not a platform channel at all) —
  overlay↔background messaging, replacing the plugin's `shareData()`/`overlayListener`
  bridge used through early Sprint 3. That bridge routed through a single native static
  field (`WindowSetup.messenger`) set by whichever engine last attached the plugin,
  which the ephemeral main UI engine could silently hijack (confirmed via native source
  read — see §5's fire-and-forget note, which is now historical: there is no reply to
  await over this transport in the first place, since `SendPort.send()` is
  synchronous/fire-and-forget by construction). Three named ports, all registered by
  `backgroundMain`:
  - `com.whydidiunlock.intent_write_port` — overlay → background. Carries three tagged
    message shapes (a `type` field selects which `IntentStore` call the listener makes):
    `declare` (an `IntentEvent.toMessage()`, from `_submitIntent` → `insertOpenIntent`),
    `dismiss` (an `IntentDismissal.toMessage()`, from `_dismissBubble` →
    `markIntentDone`), and `noIntent` (an `IntentEvent.toMessage()`, from
    `_submitNoIntent` → `insertEvent`, atomic — see docs/DATA_MODEL.md §4 for why
    declare/dismiss are two writes but no-intent is one).
  - `com.whydidiunlock.overlay_closed_port` — overlay → background. Signals a REAL
    `closeOverlay()` (dismiss or no-intent), replacing `FlutterOverlayWindow.isActive()`
    — see §5.
  - `com.whydidiunlock.manual_prompt_port` (added 2026-07-23, T6) — **main UI engine →
    background**, the only port that flows this direction. Backs the Status screen's
    "show me the prompt now" button — `triggerCapturePromptManually()` is the public
    entry point Status calls directly (imports `main.dart`, doesn't need to touch its
    internals). Can't be a direct `showOverlay()` call from the main engine instead,
    because `_overlayIsActive` is a plain background-isolate variable: a direct call
    would leave it `false` while a manually-triggered overlay is actually showing, so a
    real unlock arriving moments later would try to show a second one on top of it.
    Routing through the background isolate means the manual trigger goes through the
    same `_overlayIsActive` guard a real unlock does — see `_showCaptureScreenManually`,
    which deliberately bypasses prompts-enabled/quiet-hours/cooldown/probability (the
    whole point is showing it on demand, not re-running triage) but keeps the permission
    check and the active-overlay guard. It also does NOT write an `unlock_log` row — this
    isn't a real unlock, and logging it would inflate "unlocks today." Returns `bool`
    (added 2026-07-23, after an on-device T6 investigation) — `true` iff the port lookup
    succeeded and the message was handed off, `false` if the background engine hasn't
    registered it yet. Fire-and-forget, not a round trip: `true` is not a guarantee the
    capture screen actually appears (permission/overlay-active are still checked
    asynchronously on the other side) — see the function's own doc comment.
  - `com.whydidiunlock.overlay_config_port` (T11) — **background → overlay**, the
    reverse of every port above it and the first one registered by the OVERLAY isolate
    rather than by `backgroundMain` (in `_OverlayRootState.initState`, not
    `overlayMain`, since the overlay engine's widget State — not its bare entry-point
    function — is what needs to react to the reply via `setState`). Carries the reply
    to a `requestPresets` message (sent over the existing `intent_write_port`, no
    dedicated overlay→background request port needed): `{id, label}` per active
    preset, already filtered and ordered by `activePresets()`. Requested on engine
    cold start AND again after every `_dismissBubble` reset to capture mode, so a
    preset edited via the separate main-engine Settings/manage-presets screens doesn't
    stay stale for this cached engine's whole remaining lifetime. Pull, not push — see
    docs/DATA_MODEL.md §4 ("Getting presets to the capture screen") for why a push
    would race the overlay engine's cold start on the very first show.
  - Also see `_ensureIntentStore`'s early call, replaced in the sweep — `backgroundMain`
    calls `_sweepAbandonedIntents()` once per engine start, which both warms the store
    open and reclassifies any `open` intent_log row left by a process that died before
    dismissing it (docs/DATA_MODEL.md §3, cases 7/8).
  - `com.whydidiunlock.lock_signal_port` (T12) — **background → overlay**, same
    direction as `overlay_config_port` and registered by the overlay isolate for the
    same reason. Sent from `backgroundMain`'s `onLock` handler, only when
    `_overlayIsActive`. The overlay isolate decides what to do with it based on its own
    `_mode` — capture screen (unanswered question) closes; a live bubble (outstanding
    intent) stays up. See §4's Lock flow below.

## 4. Event flows

**Unlock (the core loop):**
```
System ACTION_USER_PRESENT
  → UnlockReceiver.onReceive (computes real screen px via getRealMetrics)
  → UnlockListenerService.onPhoneUnlocked(width, height)   [static, via background engine's channel]
  → [com.whydidiunlock/unlock: onUnlock]
  → backgroundMain handler → _showCaptureScreen(width, height)
      · isPermissionGranted? isActive() guard?
      · FlutterOverlayWindow.showOverlay(full screen, focusPointer, startPosition (0,0))
  → OverlayService starts → overlay engine renders OverlayRoot in capture mode
```

**Declare intent → bubble** (all inside the overlay engine): `OverlayRoot._submitIntent`
generates `clientId` ONCE (reused for both widget state and the relay below — calling
the id generator twice would mint two different ids for the same intent) → **relays a
`declare` message immediately**, before the window resize (this is what makes the
declaration durable even if the process dies before the bubble is ever dismissed — see
docs/DATA_MODEL.md §4) → `closeOverlay()` then `showOverlay()` at **expanded** bubble
size (icon + text + Done + Snooze; `PositionGravity.none`), then auto-collapses ~2s to a
52dp chat-head via `resizeOverlay` (dp) or close+reopen fallback. Capture→bubble still
needs close+reopen because flipping the window flag in place doesn't release input focus.
Spec: `docs/erd/bubble-ux-hybrid-plan-2026-07-24.md`. Screen sizing for `showOverlay` is
**raw device pixels**; `resizeOverlay` uses **dp**.

**Done (tick):** `OverlayRoot._dismissBubble` → relays a minimal `dismiss` message
(just `clientId` + `completedAt` — the declared fields were already persisted by the
`declare` relay above, see `IntentDismissal`'s doc) → `closeOverlay()` then resets its
own state back to capture mode (the overlay engine is cached and its widget state
survives `closeOverlay`, so an explicit reset is required or a stale bubble reappears).

**Snooze:** overlay sends `snoozeStart` (no `intent_log` write), closes the window;
background arms a 10-min timer. Unlock or timer → collapsed `showOverlay` (unlock logs
`skip_reason=snooze_ended`). Process death while snoozed → abandoned sweep.

`_submitNoIntent` (the "Just Like That" path) relays a single `noIntent` message (kind,
source=null, text, matching declared/completed timestamps) before its own
`closeOverlay()` — atomic, no separate declare/dismiss step, since there's no bubble to
later dismiss.

**Overlay message → stored row:** `_sendToBackground(message)` (overlay isolate, via the
`com.whydidiunlock.intent_write_port` `IsolateNameServer` port) → background engine's
`intentWritePort` listener branches on the message's `type` tag:
- `declare` → `IntentEvent.fromMessage()` (validates: non-empty/length-capped text, valid
  kind/source combination, `declaredAt <= completedAt`, `presetId` int-or-absent) →
  `IntentStore.insertOpenIntent()` — writes `status='open'`, resolves `unlock_id` via a
  stateless lookup (docs/DATA_MODEL.md §4), idempotent on `client_id`.
- `dismiss` → `IntentDismissal.fromMessage()` (validates `clientId` + `completedAt`) →
  `IntentStore.markIntentDone()` — updates the matching `open` row to `done`; a no-op
  (never a crash) if that row is missing or already `done`/`abandoned`.
- `noIntent` → `IntentEvent.fromMessage()` → `IntentStore.insertEvent()` — same
  single-shot idempotent insert as Sprint 3, `status='done'` from the start.
- Any other/missing `type`, or a message that fails validation, is logged and dropped —
  never crashes the background isolate.

**Recovering from a lost dismissal:** if the process dies between `declare` and
`dismiss` (reboot, OEM kill, a dropped relay), the row survives as `open` rather than
never having existed at all — the entire reason declaration writes moved earlier than
dismissal. `backgroundMain` calls `_sweepAbandonedIntents()` once per engine start,
which reclassifies any lingering `open` row to `abandoned`: it's no longer live (the
overlay isolate that would have dismissed it is gone), but it is NOT lost — the
declared text, source, and timestamp all remain queryable. See docs/DATA_MODEL.md §3,
cases 7/8.

**Lock (T12):** `ACTION_SCREEN_OFF` → `UnlockReceiver` → `onPhoneLocked()` → `onLock` →
logged, then, if `_overlayIsActive`, `_signalLockToOverlay()` sends over
`lock_signal_port`. The overlay isolate's listener checks its own `_mode`: a live
**capture screen** is a stale, unanswered question, so it closes (`closeOverlay()` +
`_signalOverlayClosed()`, same as a real dismiss) — otherwise the next unlock would
wrongly log `overlay_active` for a screen nobody is even looking at. A live **bubble**
(an outstanding intent) is left running, unchanged from pre-T12 behaviour — the next
unlock still skips as `overlay_active` this iteration (multi-intent stacking is
deferred, docs/DATA_MODEL.md §10 / the Sprint 4 plan §7.1). The decision has to be made
in the overlay isolate, not `backgroundMain`, because only the overlay isolate's widget
state knows which mode it's actually in.

**Partially-typed text survives the close, deliberately.** The capture-screen close path
does NOT reset `_mode`/`_intentText`/the `TextEditingController` the way `_dismissBubble`
resets the bubble path. Since the overlay engine's widget tree survives `closeOverlay()`
regardless (§5's caching note — the reason `_dismissBubble` needs an explicit reset at
all), leaving this path bare means any text the user had started typing is still sitting
in the `TextField` on the next capture screen, rather than being silently discarded.
Only the window closes; the in-progress draft does not.

**Boot:** `BOOT_COMPLETED` / `QUICKBOOT_POWERON` → `BootReceiver` →
`startForegroundService(UnlockListenerService)` → service `onCreate` rebuilds the
background engine.

## 5. Key plugin gotchas (also in CLAUDE.md §5 / memory)

- `showOverlay()` sizes the window in **raw device pixels, not dp** (`resizeOverlay` DOES
  use dp — inconsistent). We pass native `getRealMetrics` px for the capture screen and
  `dp × devicePixelRatio` for the bubble.
- **Overlay-engine `View.physicalSize` is the overlay window, not the phone display.**
  When the bubble is 52dp, metrics report ~136×136 px. Do **not** use that (or overlay
  `didChangeMetrics`) for rotation. Unlock **and orientation** sizes come from native
  `ScreenMetrics` → `UnlockListenerService` → `onUnlock` / `onOrientationChanged`
  `{width,height}` on `com.whydidiunlock/unlock`. Background does **one**
  `closeOverlay`+`showOverlay` (capture full-screen or bubble right-center).
- **`PositionGravity.auto` is unsafe after rotation** (plugin caches `szWindow` once).
  Bubble shows use `PositionGravity.none`. Drag-end edge snap is background
  `moveOverlay` only; expand/collapse is close+reopen (not `resizeOverlay` alone —
  under `centerRight`, resize keeps `x` fixed and left-docked expand went off-screen).
- A **full-cover overlay window consumes ALL touches** regardless of flag; only a *small*
  window passes outside touches through. So the bubble must be a small window; only the
  capture screen is full-screen.
- The overlay engine is **cached and survives `closeOverlay()`** — its widget state
  persists between shows; reset it explicitly on dismiss.
- `startPosition (0,0)` is required for a true full-screen capture window (the plugin's
  default position shifts up by the status-bar height).
- **`alignment` MUST be `topLeft`, not `center`, for the full-screen capture window.**
  Confirmed via `adb shell dumpsys window windows`: `OverlayAlignment.center` sets
  `gr=CENTER`, and combined with the window's `fitTypes=NAVIGATION_BARS`, Android computes
  a "fit" parent frame that *excludes* the nav bar (e.g. height 2337 on a 2400px-tall
  display — the 63px difference is the nav bar), then **centers** our full-height window
  inside that shrunk region. Net effect: the window shifts up by half the nav-bar inset
  (~31px here), landing that many px short of the true display bottom — the screen size/
  position values were already correct; this is a gravity/fit artifact, not a size bug.
  `topLeft` anchors to the true origin and avoids the centering. Verified numerically: the
  live window `frame` went from `[0,-31][1080,2369]` to exactly `[0,0][1080,2400]`.
- **`shareData()` from the overlay isolate MUST be fire-and-forget — never `await` it.**
  Verified in the plugin's native source (`OverlayService.java`): the overlay-side
  `overlayMessageChannel.setMessageHandler` forwards the message via
  `WindowSetup.messenger.send(message)` and **never calls `reply.reply(...)`**.
  `BasicMessageChannel.send()`'s Dart `Future` only resolves on a native reply, so
  awaiting it hangs forever. This is not theoretical — awaiting it in
  `_dismissBubble()` during Sprint 3 development silently broke the bubble's × button
  outright (the function never reached `closeOverlay()`, and the bubble became
  permanently unclosable). Wrap every `shareData()` call from overlay-isolate code in
  `unawaited(...)`.
- **On Android specifically, `PRAGMA journal_mode=WAL` must run via `db.rawQuery()`,
  not `db.execute()`.** Android's sqflite backend rejects `execute()` for any statement
  that returns a result row (the PRAGMA returns the resulting mode) with
  `DatabaseException(unknown error (code 0 SQLITE_OK): Queries can be performed using
  SQLiteDatabase query or rawQuery methods only.)`. Desktop unit tests using
  `sqflite_common_ffi` do NOT catch this — that backend tolerates `execute()` for it —
  so this only ever surfaces as a real on-device crash, never in a desktop `flutter
  test` run. **A clean `flutter test` pass does not prove a new sqflite code path
  works on-device; always do at least one real-device write/read cycle.**
- **`FlutterOverlayWindow.isActive()` can hang in native code in a way even a Dart
  `.timeout()` can't catch**, once the app has been opened at least once during the
  process's lifetime. Observed on-device 2026-07-22: `_showCaptureScreen` silently
  stalled after logging `Has overlay permission: true`, with no further output —
  `.timeout()` wraps the `Future`, but the native call never returned control to Dart
  at all, so the timeout's own completion was starved too. **Fixed by not calling it**:
  replaced with a self-tracked `bool _overlayIsActive` in the background isolate, set
  `true` right before `showOverlay()` and cleared by an explicit "overlay closed"
  signal sent from the overlay isolate (`_overlayClosedPortName`, an `IsolateNameServer`
  port, same mechanism as the write relay) right after a real `closeOverlay()`. No
  plugin native call in the hot path at all.
- **`FlutterOverlayWindow.showOverlay()` must also be under `_withTimeout`, and a
  timeout must reset `_overlayIsActive`.** Unlike `isActive()` (abandoned entirely),
  we still have to call `showOverlay()` — but it is the same plugin / shared-messenger
  defect class. If the await never returns after `_overlayIsActive = true` is set,
  every later unlock silently skips as `overlay_active` with no error, until
  force-stop resets the process. Guard: `_presentCaptureOverlay` wraps
  `showOverlay()` in `_withTimeout`; on timeout it sets `_overlayIsActive = false`
  and logs `⏱️ showOverlay() timed out — resetting _overlayIsActive` so the next
  unlock can try again. The unlock is logged as `SkipReason.pluginTimeout`.
  Full investigation (plus the related “empty presets after first post-reboot unlock”
  poison path): `docs/debug/rca-post-reboot-overlay-stall-presets-2026-07-24.md`.
- **`FlutterOverlayWindow.closeOverlay()` must go through `_closeOverlayWindow()` —
  never call it directly.** Same defect class again, and the one that actually caused
  the long-running "unlock stopped prompting" bug (confirmed on-device 2026-08-15,
  after two earlier fixes aimed at other failure modes that never fired). `closeOverlay()`
  is called from the OVERLAY isolate, and in the stuck state logcat showed
  `🔒 Overlay: closing capture screen on lock` on two consecutive locks with
  `🔵 Overlay closed signal received` never arriving on the background side — the two
  log lines sit either side of exactly one statement, so the close never returned.
  Because `_signalOverlayClosed()` (pure Dart, cannot fail) sat *after* that await, it
  never ran, and `_overlayIsActive` stayed true forever. Note a hung `await` does NOT
  block the isolate's event loop, so every later lock re-entered and hung identically —
  which is why it looked permanent rather than intermittent, and why the overlay isolate
  still responded to other messages (ruling out the "overlay engine died" theory).
- **THE RULE behind all four bullets above: a pure-Dart state signal must never sit
  downstream of a plugin call that can hang.** `IsolateNameServer` port sends are
  in-process and cannot fail; plugin calls from the overlay isolate demonstrably can
  hang forever, because the plugin routes them through a single static native field
  (`WindowSetup.messenger`) owned by whichever engine attached the plugin last — so
  merely opening the app can leave the overlay isolate talking to a detached messenger.
  When ordering the two, put the signal where a hang cannot starve it (before the call,
  or after a `_withTimeout`-guarded one), and never let plugin success gate state
  correctness. Every future overlay-isolate plugin call should assume it can hang.
- **Never send a timed-out `activePresets()` as `[]` to the overlay.** `_withTimeout`
  returns `null` on hang; coercing that to an empty list and `port.send`-ing it
  permanently poisons the overlay's cached `_presets` (first unlock after CE
  storage unlocks is the hot path — store just opened, `insertUnlock` and
  `activePresets` can both time out). `_replyActivePresetsToOverlay` must abort
  the send on `null` and retry; the overlay must wait for a real config *reply*,
  not only a successful request *send*. See the same RCA doc.
- **sqflite's `singleInstance: true` (the default) shares ONE native connection across
  every `open()` call for the same file path, even across different Dart isolates.**
  Sprint 3's History screen (main UI engine) and the background writer both open
  `intents.db`; with the default, they got the SAME connection, so the History screen's
  `dispose()` → `close()` closed the writer's connection too — every subsequent
  background write then threw `DatabaseException(database_closed)`, permanently, until
  the process restarted. Fixed via `IntentStore.open({ownConnection: false})`: the
  background writer keeps the default shared/`singleInstance` connection; the History
  screen passes `ownConnection: true` (→ `singleInstance: false`) for its own
  independent connection it can freely open/close. Two connections to one file is
  exactly what WAL mode (already in place, see above) is for.
- **The background engine can start before Android's credential-encrypted storage is
  unlocked, causing the first `IntentStore.open()` to fail — and if that failure isn't
  retried, storage (and anything that reads it) breaks permanently for the rest of the
  process.** `backgroundMain()` is the direct-boot service entry point (§6): it can run
  at `LOCKED_BOOT_COMPLETED`, before the user's first post-reboot unlock, while the
  default app-data storage location `getDatabasesPath()` resolves to is still locked.
  Observed on-device 2026-07-22: `FileSystemException: ... (OS Error: Required key not
  available, errno = 126)` — `ENOKEY`, i.e. the CE-storage key isn't available yet. The
  original code called `IntentStore.open()` exactly once, unawaited and uncaught, at
  engine start — that single failed attempt left `_intentStore` null forever, which
  silently broke BOTH the cooldown check (`lastCompletedAt` read as "no prior event",
  always) AND all future writes (the insert listener was only registered after a
  successful open, so it never ran). Fixed via an idempotent `_ensureIntentStore()`
  retried at three points — best-effort at boot, before every write, and at the top of
  every triage check — so the user's next real unlock (the exact moment storage is
  guaranteed available again) gets a fresh attempt instead of trusting a stale failure
  from before boot finished. A concurrent-open guard (a shared in-flight `Future`)
  prevents two simultaneous callers from both calling `open()` when the store is still
  null.
- **`SharedPreferences.getInstance()` caches a per-isolate singleton — never use it from
  code that runs in more than one of this app's isolates.** `AppSettings` was built
  against `SharedPreferencesAsync` from the start specifically to avoid this (its own doc
  comment explains why: settings are written from the UI engine's Settings screen and read
  from the background engine). `lib/problem_report.dart`'s `ProblemReportLog` did NOT
  follow that pattern originally — it used `getInstance()` even though `installHooks()`
  runs in all three isolates (ui/background/overlay). Found 2026-08-01 investigating a
  "Report a problem never shows any logs" report: two real bugs from the one root cause.
  (1) A UI-isolate `getInstance()` call could return a cached copy that never saw entries
  the background isolate wrote later in the same process lifetime, so About → Report a
  problem could show stale/empty logs even though errors WERE being recorded elsewhere.
  (2) Worse, because `record()` is read-modify-write, an isolate holding a stale cached
  read could overwrite every entry another isolate had appended since — silent data loss,
  not just staleness. Fixed by switching to `SharedPreferencesAsync` (reads the platform
  fresh on every call, same as `AppSettings`). **Still unresolved: the overlay isolate has
  no plugins registered at all** (the same reason `shareData()` was replaced by
  `IsolateNameServer` ports, above), so no `shared_preferences` call — sync or async —
  works there; `ProblemReportLog.record()` silently no-ops via its catch block whenever
  called from the overlay isolate, which is exactly where the bubble and capture screen
  run. Capturing overlay-isolate errors needs a relay through the background isolate's
  ports, the same pattern as `_intentWritePortName` — tracked in `docs/BACKLOG.md`, not
  yet built (needs on-device iteration, not a blind port-wiring change).
- **Day-1 recap notification is two engines, not one.** `flutter_local_notifications.show`
  runs in the **background** isolate (unlock handler, `maybePostDayOneNotification`).
  Tap handling (`onDidReceiveNotificationResponse` / `bindUiTapHandler`) lives on the
  **main UI** isolate (`AppLauncher`) so a shade tap while Home is already up can
  still open the recap. Never call the plugin from overlay-isolate code.
  **Android AAR requires core-library desugaring** (`isCoreLibraryDesugaringEnabled` +
  `desugar_jdk_libs` in `android/app/build.gradle.kts`) even though we never call
  `zonedSchedule`. **One destination:** icon open and shade tap both show
  `DayOneStatsScreen`; Continue is the only path to Home. Payload `day_one_recap`
  so we ignore the overlay plugin's own FGS notification.

## 6. Known limitations / reliability gaps (not defects introduced here)

- **First-unlock-after-reboot gap: CLOSED (v0.4.0).** `BootReceiver` +
  `UnlockListenerService` are `directBootAware` and handle `LOCKED_BOOT_COMPLETED`
  (fires before the device's first post-reboot unlock), so monitoring starts before
  that unlock rather than after it. Verified across 2 real reboots. (Historical note:
  this section used to say this gap was open/backlogged — it isn't anymore.)
- **Aggressive OEMs (Xiaomi/Oppo/Vivo)** may block boot auto-start and kill the foreground
  service during normal use unless the user grants "Autostart" / disables battery
  optimization. Not fixable in code — needs a guided onboarding screen (P1 backlog).
- **Full process kill:** `START_STICKY` restarts the service, but unlocks during the gap
  are missed; `am force-stop` disables restart entirely until manual relaunch. This is
  also the known edge case Sprint 3's storage doesn't solve: if the app process is
  killed between a bubble dismiss and the background engine's DB write completing,
  that event is lost — same class of gap, not a new one. (Not the same mechanism as an
  **app update** killing the process — that's handled by `UpdateReceiver`, above.)
- **The overlay plugin's FGS notification is expected, not a second recap.** Android
  requires a visible foreground-service notification. Once `POST_NOTIFICATIONS` is
  granted, testers see **two** shade items: the one-shot day-1 recap
  ("Your first day with Beacon") and the overlay `OverlayService` item (channel
  `IMPORTANCE_DEFAULT`; body is `overlayContent`, the declared intent). Dinesh
  accepted this 2026-08-16: silent, clears when the session is marked Done. Do
  **not** patch the overlay fork to hide it unless a Play review demands it.

- **Memory:** up to 3 engines while the app is open (UI + background + overlay), dropping
  to ~2 (background + overlay) when closed. Battery soak vs. the <2%/day target is untested.
- **`flutter_overlay_window`'s own background service (`OverlayService`) crashes with a
  `NullPointerException` when Android restarts it after a low-memory kill.** Found via
  Play Console Android vitals 2026-08-02, affecting 3 closed testers (Nothing Phone,
  Pixel, Samsung). `Service.onStartCommand()` is documented to receive a `null` `Intent`
  on a `START_STICKY` restart (same restart mechanism our own `UnlockListenerService`
  uses without issue); the plugin's `onStartCommand` dereferences `intent` immediately
  with no null check. Purely native/Java, outside our code — not something
  `ProblemReportLog` can ever see. `0.5.0` (our pinned version) is also the latest
  published version, so there's no upgrade path. **Applied 2026-08-02:** forked to
  `diniiidinesh/flutter_overlay_window`, patched (early-return `START_STICKY` when
  `intent == null`), pushed to `fix/overlay-service-null-intent`; `why_did_i_unlock`'s
  `pubspec.yaml` now depends on that branch via a git dependency instead of the
  published `0.5.0`. Still needs: an upstream issue filed by hand (cross-owner GitHub
  access can't be added mid-session) and an on-device restart-path check (`flutter pub
  get`, force-stop the app, unlock again) before this is considered verified. Full RCA:
  `docs/debug/rca-overlay-service-null-intent-crash-2026-08-02.md`.
- **The overlay plugin's own FGS notification (above) was showing no visible icon.**
  Found 2026-08-27, alongside auditing every notification source for correct Beacon
  branding (two others — `UnlockListenerService`'s own FGS notification and the day-1
  recap — already used a dedicated flat icon and were fine). `OverlayService`'s
  `setSmallIcon()` was fed `getDrawableResourceId("mipmap", "launcher")`, which
  resolves the host app's `ic_launcher` — an adaptive icon (background+foreground
  layers) on API 26+, which Android cannot render as a notification small icon; it
  silently falls back to a blank/default icon per-OEM instead of erroring, the same
  failure class fixed for the day-1 recap notification (§PLAY_SUBMISSION/CLAUDE.md
  PR #28). **Applied 2026-08-27:** second patch to the same fork
  (`diniiidinesh/flutter_overlay_window`, `fix/overlay-service-null-intent` branch,
  commit `2cca325`) — looks up a dedicated flat `ic_stat_beacon` drawable first,
  falling back to the original launcher-mipmap lookup only if that resource is
  absent (keeps default behavior for any other app using this plugin). Confirmed via
  `flutter build appbundle --release` + `flutter build apk --release --split-per-abi`
  after `flutter pub upgrade flutter_overlay_window` (bumps `pubspec.lock`'s
  `resolved-ref`); on-device confirmation that the bubble's shade item now shows the
  Beacon icon is still open.

## 7. Testing gotchas (Sprint 3 — sqflite + widget tests)

- **`sqflite_common_ffi` does its real work on a background Isolate — genuine async I/O,
  not a fake-Timer-based Future.** `testWidgets`' default automated test zone can
  deadlock a `setState()` triggered by that kind of real callback: a widget that opens
  a store and loads data in `initState()` will hang **forever** at `pumpWidget()` (not
  throw, not time out quickly) if the real isolate round-trip isn't given real-zone
  treatment. Confirmed by direct reproduction during Sprint 3 (`history_screen_test.dart`
  hung indefinitely; bisected line-by-line with debug prints to confirm the store's
  `recentEvents()` call itself completed fine — the hang was specifically in the
  framework not processing the resulting `setState`).
  - **Fix:** wrap any real async I/O (store opens, inserts, the post-`pumpWidget` wait
    for a widget's async load to finish) in `tester.runAsync(() async { ... })` —
    Flutter's documented escape hatch for genuine async work (isolates, real Timers,
    file I/O) inside a widget test. Then `await tester.pump()` to let the framework
    process the now-completed state change.
  - Separately: don't use `pumpAndSettle()` on a screen showing a `CircularProgressIndicator`
    — its indeterminate animation schedules frames forever, so "wait until no more
    frames are scheduled" never resolves (its own internal timeout is 10 *minutes*, not
    seconds, so this reads as a hang, not a quick failure). Use explicit `pump()` calls
    instead.
- **A stale/orphaned Gradle daemon can make a build look permanently stuck** at
  `Running Gradle task 'assembleRelease'` with zero progress for many minutes, even
  though a fresh daemon would finish the same build in well under a minute. Check the
  daemon's own log (`~/.gradle/daemon/<ver>/daemon-<pid>.out.log`) for "finished
  executing the build" before concluding it's a real hang; `cd android && ./gradlew
  --stop` then retry if it's stale. Also in CLAUDE.md §7.

## 8. Debugging playbook — recognizing recurring bug classes

This codebase has now hit the same handful of root causes repeatedly, in different
disguises. Written 2026-07-24 after two more instances were found in one testing
session (both in `docs/BACKLOG.md`: the stale overlay-preset-cache bug, and the
manual-trigger-pollutes-cooldown bug) — so the pattern, not just the individual bugs,
is documented here for whoever debugs the next one.

### 8.1 "It works, but only after I do X (reopen the app / reboot / wait)"

This exact shape of symptom has a name in this codebase: **a long-lived cached engine
is holding stale state, and nothing re-fetches it.** Three real bugs have had this
shape:

- The `shareData()` transport hijack (Sprint 3) — worked once, then silently died
  until reboot.
- The config-relay race (T11) — worked until one lost message, then permanently
  empty until reboot.
- The stale-preset-cache bug (Sprint 4, `docs/BACKLOG.md`) — worked until an edit
  in Manage Options, then permanently stale until reboot.

**Why reboot is always the "fix":** the overlay engine (`docs/ARCHITECTURE.md` §1) is
cached and only destroyed by a full process kill — not by `closeOverlay()`, not by
reopening the main UI app (a different engine entirely), not by repeated real unlocks.
A reboot is simply the most reliable way a tester stumbles into killing that cached
process. **If a symptom "only happens once per install" or "only clears on reboot,"
suspect a value that's fetched once (at `initState`, or once at engine start) and
never refreshed — find where that fetch happens, and check every code path that
SHOULD invalidate it but doesn't call it again.** In `lib/main.dart`, search for
`_requestPresets()`, `_ensureIntentStore()`, and any `IsolateNameServer`
`ReceivePort`/`registerPortWithName` pair as the places this class of bug tends to
live.

### 8.2 "A test-only action affected real behavior"

The manual-trigger-pollutes-cooldown bug is the general shape: **a code path
explicitly built to be test-only (`_showCaptureScreenManually`, T6's "show me the
prompt now") protected itself against ONE side effect (`_logUnlock`, so it wouldn't
inflate `unlock_log` stats) but not against ANOTHER (the relayed answer still writing
to `intent_log`, which cooldown reads from).** The lesson: when adding a "just for
testing" entry point, grep for **every** downstream write/read it can reach, not just
the first one that comes to mind — `docs/DATA_MODEL.md`'s tables (`unlock_log`,
`intent_log`, `intent_preset`) are the exhaustive list of state that can leak between
a test action and real behavior. If a new manual/debug trigger is ever added, ask
"what does answering this prompt eventually write to, and does anything downstream
(cooldown, insight queries, export) read that without caring where it came from?"

### 8.3 Reading the logs — the emoji convention

`debugPrint` calls throughout `lib/main.dart` are prefixed with an emoji by rough
category, consistently enough to `grep`/scan for a specific class of event:
🔓/🔒 unlock/lock events · 🟣 overlay window shown · 🎲 triage decision (cooldown/
probability) · 📮/📤/📥 config-relay (presets) traffic · 💽 store opened · 🧹 abandoned-
intent sweep · 📝/✅/🤷 intent declared/dismissed/no-intent · 🧪 manual test trigger ·
⚠️ a recoverable/logged failure · ⏱️ a `_withTimeout` guard firing (should be
**~never** — see §5's `plugin_timeout` note). A capture-screen-not-appearing report
should always start by grepping for 🔓 (did the unlock even reach `backgroundMain`?),
then 🎲 (was it skipped, and why?), then 🟣 (did `showOverlay()` actually get called?)
— that ordering isolates which of the three layers (native → background → overlay)
the problem is in before touching any code.

Also useful after 2026-07-24: **📐** = orientation event / one bubble reopen (native
`onOrientationChanged` path). If rotation “loses” the bubble, look for 📐 first; a
flood of 📌 snap lines without a single reopen usually means an old overlay-metrics
path or mid-landscape snap using stale portrait width.

## 9. Beacon visual system (UI tokens)

Accent is **Beacon amber `#FFB300`**, not Material purple. Tokens + `beaconDarkTheme()`
live in `lib/beacon_theme.dart`; both the main UI and overlay engines apply that theme.
Bubble chrome (frosted glass, amber border/glow) is in `lib/bubble_widget.dart`.

Durable token/spec (redundant with code on purpose): `docs/erd/beacon-visual-identity-2026-07-24.md`.
Hybrid bubble UX (states/actions): `docs/erd/bubble-ux-hybrid-plan-2026-07-24.md`.

Do **not** call `sqflite` from the overlay isolate — Beacon is theme-only and does not
change the three-engine plugin constraints in §1.
