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
| **Main UI** | `MainActivity` (`FlutterActivity`) | `main()` → `MyApp` → `HomeScreen` | Ephemeral — dies when the Activity/task is destroyed (incl. swipe-away) | Yes (auto) | Show the settings/permission screen. Request the overlay permission (needs an Activity). Nothing else. |
| **Background** | `UnlockListenerService` (foreground service) | `backgroundMain()` | **Persistent** — lives as long as the foreground service (survives task removal) | Yes (auto) | The "brain": receive unlock/lock events, run prompt triage, call `showOverlay()`. Also the sole writer of the Sprint 3 `intent_log` DB — opens it once, subscribes `overlayListener`, inserts on every relayed event. |
| **Overlay** | `OverlayService` (from `flutter_overlay_window`) | `overlayMain()` → `OverlayRoot` | Cached; created lazily on first `showOverlay`, persists for the process | **No** (only the overlay plugin's own channel) | Render the capture screen and the bubble. Runs the capture→bubble state machine. |

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
  - The overlay engine **cannot call `sqflite`** (or any plugin) directly. Sprint 3's
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
- **`UnlockReceiver`** — runtime-registered (NOT in the manifest — `ACTION_USER_PRESENT`
  can only be registered at runtime). Listens for `ACTION_USER_PRESENT` (unlock) and
  `ACTION_SCREEN_OFF` (lock). On unlock it computes the **true display size natively**
  (`getRealMetrics`) and passes it to Dart, because the headless background engine can't
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
  `onUnlock` with `{width, height}` args (native-provided display size), and `onLock`
  (no args). Handler installed by `backgroundMain`.
- **`flutter_overlay_window` internal channels** (`x-slayer/*`): `showOverlay`,
  `closeOverlay`, `resizeOverlay`, `updateFlag`, `isActive`, plus `shareData` /
  `overlayListener` for overlay↔main-app messaging — this is the Sprint 3 intent-log
  write path (`OverlayRoot._dismissBubble` / `_submitNoIntent` call `shareData()` with
  an `IntentEvent.toMessage()` Map; `backgroundMain` subscribes `overlayListener` and
  calls `IntentStore.insertEvent`). **Critical: `shareData()` calls from the overlay
  isolate must be fire-and-forget (`unawaited(...)`), never `await`ed — see §5.**
  Routing is native-side static-field-based (`WindowSetup.messenger`, set by whichever
  engine last called the plugin's `onAttachedToEngine` — background attaches after
  MainActivity in the normal launch path, so background wins); confirmed via a
  real-device spike (native source read + swipe-from-Recents test) that this reaches
  the background engine reliably, including after the main UI engine is destroyed.

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
→ `closeOverlay()` then `showOverlay()` at bubble (pill) size with `defaultFlag`. The
close+reopen is required because flipping the window flag in place doesn't release input
focus (would block touches in other apps). Screen/pill sizing is in **raw device pixels**
(the plugin quirk); the pill dp is × `devicePixelRatio`.

**Dismiss bubble:** `OverlayRoot._dismissBubble` → builds an `IntentEvent` (kind=intent)
→ `unawaited(shareData(...))` (Sprint 3 write relay — fire-and-forget, see §5) →
`closeOverlay()` then resets its own state back to capture mode (the overlay engine is
cached and its widget state survives `closeOverlay`, so an explicit reset is required
or a stale bubble reappears). `_submitNoIntent` (the "Just Like That" path) does the
same `shareData()` relay with kind=no_intent before its own `closeOverlay()`.

**Overlay message → stored row (Sprint 3):** `shareData(event.toMessage())` (overlay
isolate) → native `OverlayService`'s `overlayMessageChannel` forwards via the static
`WindowSetup.messenger` → background engine's `overlayListener` stream →
`IntentEvent.fromMessage()` (validates: non-empty/length-capped text, valid kind/source
combination, `declaredAt <= completedAt`; malformed messages are logged and dropped,
never crash the isolate) → `IntentStore.insertEvent()` (`INSERT OR IGNORE` on
`client_id`, idempotent against any retry/duplicate).

**Lock:** `ACTION_SCREEN_OFF` → `UnlockReceiver` → `onPhoneLocked()` → `onLock` → logged
(no UI action today).

**Boot:** `BOOT_COMPLETED` / `QUICKBOOT_POWERON` → `BootReceiver` →
`startForegroundService(UnlockListenerService)` → service `onCreate` rebuilds the
background engine.

## 5. Key plugin gotchas (also in CLAUDE.md §5 / memory)

- `showOverlay()` sizes the window in **raw device pixels, not dp** (`resizeOverlay` DOES
  use dp — inconsistent). We pass native `getRealMetrics` px for the capture screen and
  `dp × devicePixelRatio` for the bubble.
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
- **Memory:** up to 3 engines while the app is open (UI + background + overlay), dropping
  to ~2 (background + overlay) when closed. Battery soak vs. the <2%/day target is untested.

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
