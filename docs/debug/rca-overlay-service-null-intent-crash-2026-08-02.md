# RCA — overlay service crash on restart (Android vitals, 2026-08-02)

## What happened, in plain words

Three of your closed testers' phones (yours — Nothing Phone, a Google Pixel, and a
Samsung) crashed the app in the background. This wasn't something the app did wrong —
it's a bug in a piece of borrowed code (the `flutter_overlay_window` plugin, the library
that draws the floating bubble) that we don't own.

Here's the chain of events:

1. Android occasionally kills background apps to free up memory — completely normal,
   happens to every app, especially on phones that are aggressive about battery/memory
   (which is most phones today).
2. Because our bubble-drawing service is registered as "please restart me if you kill
   me" (`START_STICKY` — same mechanism our own unlock-listening service uses, and
   that part is fine), Android brings it back a moment later.
3. When Android restarts a killed service like this, it's documented, expected Android
   behavior that it calls the service back with **no information about why it's being
   started** — literally a "null" instead of the usual instructions.
4. The plugin's code doesn't check for that "no information" case — it assumes there's
   always something there and immediately tries to read a value out of it. Reading a
   value out of nothing crashes the app.

So: phone gets memory-pressured → Android does something completely normal → the
plugin's restart-handling code doesn't expect it → crash. It's a missing safety check
in someone else's code, triggered by ordinary Android housekeeping.

## Why "Report a problem" never caught this

This crash happens in Java, inside Android's own service-restart machinery, before any
of our Flutter/Dart code even runs. Our error logging (`ProblemReportLog`, the thing we
just fixed) can only see mistakes inside our own Dart code — it has no way to see into
Android's internals. This is exactly the "native crashes leave no Flutter log" caveat
the Report-a-problem email already warns testers about. Play Console's Android
vitals — not our own logging — is what surfaced this, which is exactly why checking it
was worth doing.

## The technical detail (for the record)

- **Crash:** `NullPointerException` at `OverlayService.onStartCommand` (line ~101),
  calling `intent.getIntExtra(...)` when `intent` is `null`.
- **Trigger:** Android restarting a `START_STICKY` service after a low-memory kill, per
  documented `Service.onStartCommand()` behavior (a restart delivers `intent = null`
  unless the service opts into `START_REDELIVER_INTENT`, which this plugin doesn't).
- **Package:** `flutter_overlay_window`, pinned at `^0.5.0` in `pubspec.yaml` — which is
  also the *newest* version published (last release ~15 months ago as of this writing).
  Its own changelog claims "Fix NullPointerException in OverlayService," but that fix
  addressed a different case (a missing extra), not a fully-null `Intent`; confirmed
  against the plugin's current `main` branch on GitHub — the null check still isn't
  there.
- **Devices affected (per Android vitals):** Nothing Phone (Dinesh's device), a Google
  Pixel, a Samsung device. Consistent with "whichever OEM reclaimed memory during that
  tester's session," not a device-specific bug.
- **Fix:** a one-line null guard at the top of `onStartCommand` — if `intent == null`,
  return `START_STICKY` immediately instead of touching it. This is the standard,
  widely-documented pattern for this exact Android lifecycle case.

## The fix path (why a fork, not a plugin upgrade)

There is no newer plugin version to upgrade to — `0.5.0` is the latest. So the only way
to get this into the app before the maintainer (if ever) ships a fix is to patch our own
copy of the plugin ("fork" it) and point `pubspec.yaml` at that copy instead of the
official one, while also filing the bug against the original so it can ideally be fixed
upstream and the fork retired later.

**Status as of 2026-08-02: steps 1–4 done (from a Claude Code session with GitHub write
access to the fork, once Dinesh forked it manually — cross-owner GitHub access can't be
added to an existing session, so this needed the fork to exist under `diniiidinesh`
first). Remaining: file the upstream issue by hand, then verify on-device.**

1. ✅ **Forked** to `https://github.com/diniiidinesh/flutter_overlay_window`.
2. ✅ **Patched** `android/src/main/java/flutter/overlay/window/flutter_overlay_window/OverlayService.java`
   — added the null guard as the first lines of `onStartCommand`:

   ```java
   public int onStartCommand(Intent intent, int flags, int startId) {
       if (intent == null) {
           // Android redelivers a null Intent when it restarts a killed
           // START_STICKY service (documented Service.onStartCommand behavior) —
           // there is nothing to act on until the app calls showOverlay() again
           // with real arguments, so just stay alive.
           return START_STICKY;
       }
       mResources = getApplicationContext().getResources();
       int startX = intent.getIntExtra("startX", OverlayConstants.DEFAULT_XY);
       // ...rest of the existing method body, unchanged...
   ```

3. ✅ **Committed and pushed** to branch `fix/overlay-service-null-intent` on the fork
   (commit `614e5cb`).
4. ✅ **`pubspec.yaml` in `why_did_i_unlock` now points at the fork's fix branch:**

   ```yaml
   flutter_overlay_window:
     git:
       url: https://github.com/diniiidinesh/flutter_overlay_window.git
       ref: fix/overlay-service-null-intent
   ```

### What's still manual — do these when you're back

5. **File the upstream issue** on `https://github.com/X-SLAYER/flutter_overlay_window/issues/new`
   (this needs your own GitHub login — it's a different repo owner, which Claude Code
   sessions can't cross into once a session already has repos from another owner).
   Suggested title/body, ready to paste:

   > **Title:** `OverlayService.onStartCommand crashes with NullPointerException on
   > service restart (null Intent)`
   >
   > **Body:**
   > `OverlayService.onStartCommand` calls `intent.getIntExtra(...)` without checking
   > whether `intent` is null. Android delivers a null `Intent` when it restarts a
   > killed `START_STICKY` service (documented `Service.onStartCommand()` behavior) —
   > this happens on ordinary low-memory kills, not just edge cases. Confirmed via
   > Android vitals across 3 real devices (Nothing Phone, a Pixel, a Samsung device).
   >
   > Stack trace:
   > ```
   > Caused by java.lang.NullPointerException: Attempt to invoke virtual method
   > 'int android.content.Intent.getIntExtra(java.lang.String, int)' on a null
   > object reference
   >   at flutter.overlay.window.flutter_overlay_window.OverlayService.onStartCommand
   > ```
   >
   > I've pushed a one-line fix (early-return `START_STICKY` when `intent == null`)
   > here: https://github.com/diniiidinesh/flutter_overlay_window/tree/fix/overlay-service-null-intent
   > — happy to open a PR against `main` if useful.

   Optionally, open the PR itself (`Compare & pull request` from that branch) so the
   maintainer can merge with one click.
6. **On your laptop:** `flutter clean`, `flutter pub get` (this will rewrite
   `pubspec.lock`'s `flutter_overlay_window` entry to the git dependency — expected,
   commit it), `flutter run --release`, then deliberately reproduce the restart path.

   **`adb shell am force-stop <package>` does NOT reproduce this crash** — force-stop
   puts the app into Android's "stopped" state, where the OS deliberately will not
   auto-restart any of its services or deliver most broadcasts, specifically to honor a
   user-initiated stop. The crash only happens when the low-memory killer reclaims the
   process, which (unlike force-stop) *does* honor `START_STICKY` and restarts the
   service with `intent = null` — a different code path entirely. (Confirmed on-device
   2026-08-11: force-stop + unlock produced no overlay and no crash, which is expected
   force-stop behavior, not evidence the fix works.)

   **`adb shell kill -9 <pid>` also failed on-device (2026-08-11):** `Operation not
   permitted` — the `shell` user doesn't have raw signal-kill permission over another
   app's process on this device/Android version (this varies by device; don't assume it
   works elsewhere either). Use the ActivityManager-mediated equivalent instead, which
   goes through Android's own crash-reporting path rather than a raw signal and is
   exposed to `shell` specifically for this kind of test, regardless of the target app's
   debuggable flag:

   ```
   adb shell am crash com.whydidiunlock.why_did_i_unlock
   ```

   **Critical precondition, easy to get wrong: `OverlayService` only exists while a
   bubble or capture screen is actively showing** (`showOverlay()`/`closeOverlay()` in
   `lib/main.dart` start/stop it — it is not an always-on service like
   `UnlockListenerService`). `am crash` kills the whole app process, but Android only
   attempts a `START_STICKY` restart for services that were *actually running* at the
   moment of the kill. If no bubble is showing when you run `am crash`, there is nothing
   to restart and the null-guard code is never touched — the test will silently pass for
   the wrong reason.

   Also note **`UnlockListenerService` (our own, always-on) restarts independently and
   responds to the next lock/unlock with a fresh, real (non-null) `Intent`** — so "I
   locked, unlocked, and saw the overlay" is consistent with success whether or not
   `OverlayService`'s null-guard was ever exercised. It is not, by itself, proof.

   The procedure that actually isolates the bug:
   1. Declare an intent so a bubble is actively showing (so `OverlayService` is alive).
   2. In a second terminal, start `adb logcat` and leave it tailing.
   3. Run `adb shell am crash com.whydidiunlock.why_did_i_unlock`.
   4. Watch logcat for a few seconds **without touching the phone**. Pre-fix, this
      restart would throw a `FATAL EXCEPTION` / `NullPointerException` at
      `OverlayService.onStartCommand` right in that window. No crash there is the real
      confirmation — not what happens after a subsequent lock/unlock.
   5. Lock/unlock afterward only as a secondary sanity check that things still behave
      normally.
7. Once confirmed, this is a normal merge like any other fix. Keep the fork around
   until the upstream fix (if any) ships and you've verified you can drop back to the
   official version cleanly.

## Confirmed on-device (2026-08-11)

`adb logcat -c` → `adb shell am crash com.whydidiunlock.why_did_i_unlock` (bubble
actively showing) → `adb logcat -d` dump, repeated twice. Both dumps show
`ActivityManager: Scheduling restart of crashed service
com.whydidiunlock.why_did_i_unlock/flutter.overlay.window.flutter_overlay_window.OverlayService
in ~11000ms for start-requested` — proof `OverlayService` was genuinely alive and
Android genuinely scheduled the null-`Intent` restart, not a false pass. In both cases
the restarted process ran on for minutes afterward with no further `FATAL EXCEPTION`,
and the full ~5.4MB combined log contains zero `NullPointerException` occurrences. Null
guard confirmed working. `docs/TEST_PLAN.md` case 82 now ✅.

## Why not just patch the plugin's files inside `android/` directly, unforked?

Editing the plugin's source in your local `.pub-cache` or a vendored copy would work
until the next `flutter pub get`/`flutter clean` silently reverts it — this class of fix
needs to live somewhere `pub get` will keep re-fetching it from, which is exactly what a
git dependency override gives you. It's also the only way to have a real diff to submit
upstream.
