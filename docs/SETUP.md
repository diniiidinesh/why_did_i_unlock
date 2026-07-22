# SETUP.md — Dev environment (Windows)

How to go from a blank Windows machine to a running build of this Flutter Android app. Android-first project; no emulator, no iOS, no Windows-desktop tooling required.

**One rule throughout:** after any change to your PATH, open a **new terminal**. PATH changes do not apply to already-open terminals.

---

## What you're installing

Git → the repo → Flutter SDK → Android Studio (for the SDK only) → Claude Code → a physical Android device. Four installs and one phone. No emulator — this app's unlock detection and overlay only behave correctly on real hardware.

---

## 1. Git for Windows

Download from https://git-scm.com and install with defaults (keep "Add Git to PATH" checked).

Why: both Flutter and Claude Code use Git internally. Verify:

```powershell
git --version
```

## 2. Get the repo onto the machine

Clone into a **short path** (Windows has path-length limits that break Gradle/Flutter builds in deep folders):

```powershell
git clone <your-repo-url> C:\src\why_did_i_unlock
```

If the code isn't on a remote yet, push it to a private repo first — never leave the only copy on one machine.

## 3. Flutter SDK

1. Confirm the target folder is clean: create `C:\src` if it doesn't exist. Do **not** install under `C:\Program Files` or any admin-only path — Flutter needs to write to its own cache and will throw "installed in a protected folder" errors otherwise.
2. Download the latest **stable** bundle from https://docs.flutter.dev/install (Windows → Android), named like `flutter_windows_<version>-stable.zip`.
3. Extract to `C:\src` via PowerShell (avoids the double-nested-folder mistake File Explorer sometimes makes):

   ```powershell
   Expand-Archive -Path "$env:USERPROFILE\Downloads\flutter_windows_<version>-stable.zip" -DestinationPath "C:\src"
   ```

   Verify the result is `C:\src\flutter\bin\flutter.bat` (not `C:\src\flutter\flutter\bin\...`).
4. Add to PATH: Start → "Edit environment variables for your account" → **User variables** → **Path** → **Edit** → **New** → add `C:\src\flutter\bin` → OK out.
5. In a **new** PowerShell:

   ```powershell
   flutter --version
   ```

   Confirm the bundled Dart is **≥ 3.11.5** (this project's pubspec requires it). If `flutter` isn't recognized, you either didn't open a new terminal or the PATH is wrong. If `flutter.bat` exists but the command still fails, add `C:\src\flutter` as an antivirus exclusion.

## 4. Android Studio (SDK only — not your editor)

You install this purely to fetch the Android SDK, Platform-Tools, Build-Tools, and command-line tools, and to accept licenses. Then you close it and work in Claude Code.

1. Install from https://developer.android.com/studio (defaults).
2. First launch → **Standard** setup → let it download the SDK and accept the license.
3. **Add command-line tools (the commonly-missed step):** Welcome screen → **More Actions → SDK Manager** → **SDK Tools** tab → tick **Android SDK Command-line Tools (latest)** → **Apply**. Skipping this causes the `cmdline-tools component is missing` error.
4. Accept Android licenses:

   ```powershell
   flutter doctor --android-licenses
   ```

   Press `y` at each prompt.

Default SDK location: `C:\Users\<you>\AppData\Local\Android\Sdk`. If Flutter can't find it later:
`flutter config --android-sdk "C:\Users\<you>\AppData\Local\Android\Sdk"`

## 5. Claude Code

Open **PowerShell** (not CMD, not Git Bash) and run:

```powershell
irm https://claude.ai/install.ps1 | iex
```

Native Windows install — no Node.js, npm, or WSL. Auto-updates in the background. Close and reopen the terminal, then verify:

```powershell
claude --version
```

Requires a paid Claude account (Pro, Max, Team, Enterprise, or Console API). If `claude` isn't recognized after reopening, confirm `%USERPROFILE%\.local\bin` is on your PATH. Run `claude doctor` to diagnose.

## 6. Connect a physical Android device

1. On the phone: enable **Developer Options** (tap Build Number 7×) → turn on **USB debugging**.
2. Plug in via USB; authorize the computer when prompted on the phone.
3. Confirm:

   ```powershell
   flutter devices
   ```

Troubleshooting: if `adb devices` shows nothing, it's a USB driver issue (install your phone brand's OEM driver). If adb sees it but `flutter devices` doesn't, it's a Flutter SDK config issue.

## 7. Validate and run

```powershell
flutter doctor        # Flutter + Android toolchain should be green
cd C:\src\why_did_i_unlock
flutter pub get       # install dependencies
flutter run           # build & launch on the connected phone
```

If `flutter pub get` fails on an SDK-constraint error, your Flutter is too old for this project's Dart `^3.11.5` requirement → `flutter upgrade`.

---

## Troubleshooting: a build looks stuck

If `flutter run --release` sits at `Running Gradle task 'assembleRelease'...` with
**zero progress for several minutes**, don't assume it's just a slow build (a real one
finishes in well under a minute on this project once Gradle's daemon is warm) — it's
more likely a **stale/orphaned Gradle daemon** left behind by a previously
killed/interrupted `flutter run`. Check the daemon's own log before waiting it out or
killing anything:

```powershell
Get-ChildItem "$env:USERPROFILE\.gradle\daemon\*\daemon-*.out.log" | Sort-Object LastWriteTime -Descending | Select-Object -First 1 | Get-Content -Tail 20
```

If that log already shows `finished executing the build` while your terminal still
shows no progress, Gradle itself is done — the stall is elsewhere (install/launch to
the device). If the log shows no recent activity at all, the daemon is genuinely stuck:

```powershell
cd android
./gradlew --stop
cd ..
flutter run --release -d <device-id>
```

This cost real debugging time during Sprint 3 before being root-caused — check this
first next time a build "hangs."

---

## Expected `flutter doctor` results

Green required: **Flutter**, **Android toolchain**, **Connected device** (after step 6).

**Safe to ignore:**
- **[✗] Visual Studio — develop Windows apps.** Only needed to build Windows *desktop* apps. This is an Android project; you'll never use it. Do not install Visual Studio.
- **Android Studio listed without Flutter/Dart plugins.** Those plugins are only for editing inside Android Studio. You use Claude Code, so this doesn't block builds.
- **[✗] Chrome — develop for the web.** Not targeting web.

---

## Done when

`flutter doctor` is green on Flutter + Android toolchain, your phone shows in `flutter devices`, and `flutter run` launches the app on it. Test in `--release` on a low-end device when judging real-world performance.
