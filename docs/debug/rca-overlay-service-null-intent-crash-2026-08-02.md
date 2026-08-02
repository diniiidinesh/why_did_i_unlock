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

**Status as of 2026-08-02: prepared, not yet applied.** GitHub write access in this
Claude Code session is scoped only to `diniiidinesh/why_did_i_unlock`, so the actual
fork/push/issue-filing against `X-SLAYER/flutter_overlay_window` has to happen from a
session (or by hand) that has access to that repo. Everything needed to do it in a few
minutes is below.

### Step-by-step, once you're back

1. **Fork** `https://github.com/X-SLAYER/flutter_overlay_window` to your own GitHub
   account (`diniiidinesh`) — via the GitHub website "Fork" button, or a Claude Code
   session started with that repo as a source.
2. **Edit** `android/src/main/java/flutter/overlay/window/flutter_overlay_window/OverlayService.java`
   in your fork. Find `onStartCommand` (starts around line 101) and add a null guard as
   the very first lines of the method body:

   ```java
   @Override
   public int onStartCommand(Intent intent, int flags, int startId) {
       if (intent == null) {
           // Android restarts a killed START_STICKY service with a null Intent —
           // documented behavior, not an error. Nothing to do until the app
           // calls showOverlay() again with real arguments.
           return START_STICKY;
       }
       int startX = intent.getIntExtra("startX", OverlayConstants.DEFAULT_XY);
       // ...rest of the existing method body, unchanged...
   ```

   (Keep everything else in the method exactly as-is — this only adds the guard clause
   before the first line that dereferences `intent`.)
3. **Commit and push** that change to your fork (any branch name is fine, e.g. `main`).
4. **File the upstream issue** on `X-SLAYER/flutter_overlay_window` (use the crash
   details in this doc — stack trace, devices, root cause, and mention the one-line
   fix). Worth linking your fork/commit so the maintainer can cherry-pick it directly.
5. **Point `pubspec.yaml` at your fork.** Replace:

   ```yaml
   flutter_overlay_window: ^0.5.0
   ```

   with:

   ```yaml
   flutter_overlay_window:
     git:
       url: https://github.com/diniiidinesh/flutter_overlay_window.git
       ref: main   # or whatever branch/commit you pushed the fix to
   ```

6. **On your laptop:** `flutter clean`, `flutter pub get`, `flutter run --release`, then
   deliberately reproduce the restart path (open the app, force-stop it or let it idle
   under memory pressure so Android kills the service, then trigger a restart — e.g.
   `adb shell am kill <package>` or use "Force stop" from App info, then unlock the
   phone again) and confirm no crash and the bubble still works normally.
7. Once confirmed, this becomes a normal merge like any other fix. Keep the fork around
   until the upstream fix (if any) ships and you've verified you can drop back to the
   official version cleanly.

## Why not just patch the plugin's files inside `android/` directly, unforked?

Editing the plugin's source in your local `.pub-cache` or a vendored copy would work
until the next `flutter pub get`/`flutter clean` silently reverts it — this class of fix
needs to live somewhere `pub get` will keep re-fetching it from, which is exactly what a
git dependency override gives you. It's also the only way to have a real diff to submit
upstream.
