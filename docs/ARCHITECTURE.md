# ARCHITECTURE — Why Did I Unlock

> System design reference. **Keep this updated whenever the engine topology, native
> components, event flows, or their rationale change.** Last updated: 2026-07-20.
> For product context/decisions see `CLAUDE.md` (repo root); for the current PRD see `docs/PRD.md`.

This app is unusual for a Flutter app: it runs **three separate Flutter engines**
with different lifetimes and capabilities, plus native Android services/receivers.
Getting the topology wrong reintroduces bugs we've already fixed, so this document
exists to make the "why" durable.

## 1. The three Flutter engines

| Engine | Host (native) | Dart entry point | Lifetime | Plugins registered? | Job |
|---|---|---|---|---|---|
| **Main UI** | `MainActivity` (`FlutterActivity`) | `main()` → `MyApp` → `HomeScreen` | Ephemeral — dies when the Activity/task is destroyed (incl. swipe-away) | Yes (auto) | Show the settings/permission screen. Request the overlay permission (needs an Activity). Nothing else. |
| **Background** | `UnlockListenerService` (foreground service) | `backgroundMain()` | **Persistent** — lives as long as the foreground service (survives task removal) | Yes (auto) | The "brain": receive unlock/lock events, decide whether to show the capture screen, call `showOverlay()`. Future home of Sprint 3 storage writes. |
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
    completed-intent DB write must be relayed from the overlay isolate to a
    plugin-registered engine (background or main) via `FlutterOverlayWindow.shareData()`
    / `overlayListener`.
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
- **`OverlayService`** — from the `flutter_overlay_window` plugin. Hosts the overlay
  engine, adds/removes the overlay window.

## 3. Channels

- **`com.whydidiunlock/unlock`** (native → background engine):
  `onUnlock` with `{width, height}` args (native-provided display size), and `onLock`
  (no args). Handler installed by `backgroundMain`.
- **`flutter_overlay_window` internal channels** (`x-slayer/*`): `showOverlay`,
  `closeOverlay`, `resizeOverlay`, `updateFlag`, `isActive`, plus `shareData` /
  `overlayListener` for overlay↔main-app messaging (the path Sprint 3 storage will use).

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

**Dismiss bubble:** `OverlayRoot._dismissBubble` → `closeOverlay()` then resets its own
state back to capture mode (the overlay engine is cached and its widget state survives
`closeOverlay`, so an explicit reset is required or a stale bubble reappears).

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

## 6. Known limitations / reliability gaps (not defects introduced here)

- **First unlock right after a reboot may be missed.** Plain `BOOT_COMPLETED` is delivered
  by the OS only *after* the first post-reboot unlock, and can be delayed further under
  heavy boot load. Self-heals from the 2nd unlock. Closing this fully needs
  `LOCKED_BOOT_COMPLETED` / direct-boot (backlogged — interacts with storage encryption
  context; expensive to test).
- **Aggressive OEMs (Xiaomi/Oppo/Vivo)** may block boot auto-start and kill the foreground
  service during normal use unless the user grants "Autostart" / disables battery
  optimization. Not fixable in code — needs a guided onboarding screen (P1 backlog).
- **Full process kill:** `START_STICKY` restarts the service, but unlocks during the gap
  are missed; `am force-stop` disables restart entirely until manual relaunch.
- **Memory:** up to 3 engines while the app is open (UI + background + overlay), dropping
  to ~2 (background + overlay) when closed. Battery soak vs. the <2%/day target is untested.
