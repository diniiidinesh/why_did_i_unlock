# SETUP.md — Dev environment

How to go from a blank machine to a running build of this Flutter Android app.
Android-first project; no emulator, no iOS build, no desktop tooling required.

**Part A is macOS** (the current dev machine, since 2026-08-31). **Part C is the
Windows procedure**, kept because it's where this project was built through
`0.6.4+17` and is still accurate if that machine gets used again. Part B is shared
by both.

**One rule throughout:** after any change to your PATH, open a **new terminal**.
PATH changes do not apply to already-open shells.

---

## What you're installing

Command Line Tools → Homebrew → the repo → Flutter SDK → Android Studio (for the
SDK only) → a JDK → Claude Code → a physical Android device.

No emulator. This app's unlock detection and overlay only behave correctly on real
hardware (`CLAUDE.md` §8) — an emulator will happily run the app and tell you
nothing useful about the thing the app actually does.

---

# Part A — macOS (Apple Silicon)

Written for an Apple-silicon MacBook (M-series). The default shell is **zsh**, so
PATH edits go in `~/.zshrc` — not `~/.bash_profile`, which zsh never reads. That
mismatch is the single most common "I installed it but the command isn't found"
cause on a fresh Mac.

**Paste commands without trailing `#` comments.** This machine's zsh does not have
`interactive_comments` enabled, so a line like `brew install --cask android-studio
# SDK only` is not a command plus a comment — zsh passes `#` and the comment words
to `brew` as real arguments. Homebrew then goes looking for a cask literally named
`#`, dumps its entire "did you mean?" list of every cask it knows, and the shell
reports `command not found: add`. Nothing is installed and nothing says so clearly.
Either strip the comments when pasting, or turn the option on once:

```bash
echo 'setopt interactive_comments' >> ~/.zshrc
```

## A1. Xcode Command Line Tools

```bash
xcode-select --install
```

This gives you `git`, `make`, and the compilers Homebrew needs. It is **not** full
Xcode — you don't need Xcode for this project (see A9 on what `flutter doctor` will
say about that).

Verify:

```bash
git --version
```

## A2. Rosetta 2

```bash
sudo softwareupdate --install-rosetta --agree-to-license
```

Why, even on a native-arm64 toolchain: parts of the Android SDK command-line tooling
are still x86_64-only, and Flutter's own macOS install docs list Rosetta as a
requirement on Apple silicon. It's a one-time, few-hundred-MB install that costs
nothing if unused, and skipping it produces confusing "bad CPU type in executable"
failures deep inside a Gradle build rather than at install time.

## A3. Homebrew

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

On Apple silicon Homebrew installs to `/opt/homebrew` (not `/usr/local`) and the
installer does **not** put it on your PATH for you. Run the two lines it prints at
the end, which are:

```bash
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zshrc
eval "$(/opt/homebrew/bin/brew shellenv)"
```

Verify with `brew --version`.

## A4. Get the repo onto the machine

```bash
mkdir -p ~/src
git clone <your-repo-url> ~/src/why_did_i_unlock
```

**Do not clone into `~/Desktop`, `~/Documents`, or anywhere else inside iCloud
Drive.** With "Desktop & Documents Folders" sync enabled — on by default for many
Apple-ID setups — iCloud will try to sync `build/`, `.dart_tool/`, and Gradle
caches, which are large, churn constantly, and can be evicted mid-build. That
produces intermittent, nonsensical build failures. `~/src` is outside sync and has
none of these problems. (macOS has no path-length limit to worry about, unlike
Windows.)

## A5. Flutter SDK

This project's `pubspec.yaml` requires Dart SDK `^3.11.5`, so you need a **current
stable** Flutter.

1. Download the **stable** bundle for **Apple silicon (arm64)** from
   <https://docs.flutter.dev/install> — the file is named like
   `flutter_macos_arm64_<version>-stable.zip`. Taking the Intel build by mistake
   works, but every Dart/Gradle invocation then runs under Rosetta and builds are
   noticeably slower.
2. Extract to a user-writable path — **not** `/usr/local`, `/opt`, or anywhere
   needing `sudo`. Flutter writes to its own cache directory and fails with
   permission errors from a root-owned install:

   ```bash
   mkdir -p ~/development
   cd ~/development
   unzip ~/Downloads/flutter_macos_arm64_<version>-stable.zip
   ```

   Confirm the result is `~/development/flutter/bin/flutter` (not a double-nested
   `~/development/flutter/flutter/bin/...`).
3. If macOS Gatekeeper quarantined the download (symptom: "cannot be opened because
   the developer cannot be verified" when Flutter runs a bundled binary):

   ```bash
   xattr -dr com.apple.quarantine ~/development/flutter
   ```
4. Add to PATH:

   ```bash
   echo 'export PATH="$HOME/development/flutter/bin:$PATH"' >> ~/.zshrc
   ```
5. In a **new** terminal:

   ```bash
   flutter --version
   ```

   Confirm the bundled Dart is **≥ 3.11.5**. If `flutter pub get` later fails with
   an SDK-constraint error, your Flutter is too old → `flutter upgrade`.

> **What's actually installed on this machine:** the Homebrew cask, at
> `/opt/homebrew/share/flutter`. That predates this document and there is no reason
> to redo it — `flutter upgrade` was run against it on 2026-08-31 and moved cleanly
> from 3.41.9 to **3.47.2 (Dart 3.13.2)**, comfortably past this project's
> `^3.11.5` floor. The caveat to know rather than act on: the SDK now sits under
> Homebrew's control, so `flutter upgrade` and `brew upgrade` both think they own
> its version, and a `brew upgrade --cask flutter` can move the SDK out from under
> a channel you set by hand. The archive install above is what Flutter's own
> tooling assumes and is the cleaner starting point on a genuinely fresh machine;
> switching an already-working cask install to it buys nothing.

## A6. Android Studio (SDK only — not your editor)

You install this purely to fetch the Android SDK, Platform-Tools, Build-Tools, and
command-line tools, and to accept the licenses. Then you close it and work in Claude
Code.

```bash
brew install --cask android-studio
```

1. Launch it → **Standard** setup → let it download the SDK and accept the license.
2. **Add command-line tools (the commonly-missed step):** Welcome screen →
   **More Actions → SDK Manager** → **SDK Tools** tab → tick **Android SDK
   Command-line Tools (latest)** → **Apply**. Skipping this causes the
   `cmdline-tools component is missing` error from `flutter doctor`.
3. Accept the licenses:

   ```bash
   flutter doctor --android-licenses
   ```

   Press `y` at each prompt.

Default SDK location on macOS: `~/Library/Android/sdk`. If Flutter can't find it:

```bash
flutter config --android-sdk "$HOME/Library/Android/sdk"
```

It's also worth putting `adb` on your PATH — you'll want it directly for
`adb logcat` when debugging the overlay:

```bash
echo 'export PATH="$HOME/Library/Android/sdk/platform-tools:$PATH"' >> ~/.zshrc
```

## A7. JDK — use Android Studio's bundled one

**Do this step after A6, not before.** `flutter config --jdk-dir` stores whatever
string you hand it without checking that the path exists, so running it before
Android Studio is installed silently records a broken path and the resulting
build failure points at the JDK rather than at the missing install. Confirm the
directory is really there first:

```bash
ls "/Applications/Android Studio.app/Contents/jbr/Contents/Home"
```

**Then point Flutter at the JetBrains Runtime that ships inside Android Studio:**

```bash
flutter config --jdk-dir "/Applications/Android Studio.app/Contents/jbr/Contents/Home"
```

Why this matters more than it looks: this project pins **AGP 8.13.0** with the
**Gradle 8.14** wrapper and compiles at **Java 17** (`android/settings.gradle.kts`,
`android/gradle/wrapper/gradle-wrapper.properties`, `android/app/build.gradle.kts`).
Each Gradle version supports Java only up to a known maximum, and `brew install
openjdk` installs whatever the newest JDK is — which is routinely *newer* than the
pinned Gradle supports. The failure mode is an opaque
`Unsupported class file major version` at configuration time, which reads like a
project bug rather than a JDK mismatch. Android Studio's bundled JBR is version-
matched to the Android toolchain by construction, so it sidesteps the whole
question. Don't `brew install` a JDK unless you have a specific reason.

Verify what Flutter resolved:

```bash
flutter doctor -v | grep -i java
```

## A8. Claude Code

```bash
curl -fsSL https://claude.ai/install.sh | bash
```

Close and reopen the terminal, then:

```bash
claude --version
```

Requires a paid Claude account (Pro, Max, Team, Enterprise, or Console API). If
`claude` isn't found after reopening, confirm `~/.local/bin` is on your PATH. Run
`claude doctor` to diagnose.

Also re-authenticate the GitHub CLI if you use it — its token lives in the OS
keychain, not in the repo:

```bash
brew install gh && gh auth login
```

## A9. Connect a physical Android device

Good news versus Windows: **macOS needs no OEM USB drivers.** `adb` talks to the
phone directly.

1. On the phone: enable **Developer Options** (tap Build Number 7×) → turn on
   **USB debugging**.
2. Plug in via USB-C and authorize the computer when the phone prompts.
3. Confirm:

   ```bash
   flutter devices
   ```

If nothing shows up, the overwhelmingly likely cause is the **cable**: many USB-C
cables (especially the ones bundled with chargers) are power-only and carry no data.
Try a different cable before debugging anything else. After that, `adb kill-server
&& adb devices` to force a fresh daemon.

## A10. Machine-local Gradle memory (check this if the Air is 8 GB)

`android/gradle.properties` — which **is** committed — sets:

```
org.gradle.jvmargs=-Xmx8G -XX:MaxMetaspaceSize=4G ...
```

That's an 8 GB heap for the Gradle daemon alone. On a 16 GB or 24 GB MacBook Air
it's fine. On a **base 8 GB Air it is larger than the entire machine**, and you'll
get heavy swapping, multi-minute builds, and occasional OOM kills that look like
random build failures.

Fix it **without editing the repo file** — Gradle reads
`~/.gradle/gradle.properties` at higher precedence than the project's own, so a
user-level override wins and stays out of git:

```bash
mkdir -p ~/.gradle
echo 'org.gradle.jvmargs=-Xmx4G -XX:MaxMetaspaceSize=1G' >> ~/.gradle/gradle.properties
```

Leave the committed value alone: it's tuned for the machine that produces release
bundles, and changing it in git would silently re-tune everyone else's builds.

Unrelated but worth knowing on this hardware: the Air is fanless, so a long
`flutter build appbundle --release` will thermally throttle. A release build taking
longer than it did on the old machine is expected, not a broken setup.

## A11. Validate and run

```bash
flutter doctor
cd ~/src/why_did_i_unlock
flutter pub get
flutter run --release        # physical device only
```

Note that `flutter pub get` will fetch `flutter_overlay_window` from a **git**
source, not pub.dev — the forked, patched build at
`diniiidinesh/flutter_overlay_window` (branch `fix/overlay-service-null-intent`).
That means pub needs working git access to GitHub at dependency-resolution time; a
first `pub get` on a machine where GitHub auth isn't set up yet is the one place
that fork shows up as a setup problem rather than an invisible detail.

### Expected `flutter doctor` results on macOS

Green required: **Flutter**, **Android toolchain**, **Connected device** (after A9).

**Safe to ignore:**

- **[✗] Xcode — develop for iOS and macOS**, and the CocoaPods warning that comes
  with it. This is an Android project. The `ios/` and `macos/` directories exist
  only because they're part of the Flutter project template; iOS is an explicitly
  open/undecided question (`CLAUDE.md` §12) and would be a separate product built
  on Shortcuts + Focus Filters, not this codebase. **Do not install Xcode to make
  this line go green** — it's a ~10 GB install that buys you nothing here.
- **[✗] Chrome — develop for the web.** Not targeting web.
- **Android Studio listed without the Flutter/Dart plugins.** Those plugins only
  matter for editing inside Android Studio. You use Claude Code.

---

# Part B — Shared (any machine)

## B1. Restore the release signing key (only if you'll build for Play)

**A fresh clone builds fine without this** — `android/app/build.gradle.kts` falls
back to debug signing when `android/key.properties` is absent, so `flutter run` and
debug builds work immediately. You only need this step to produce a **release**
build that Play will accept as an update to the existing app.

Two files, both **gitignored by design** and therefore *not* in the clone
(`CLAUDE.md` §5):

| File | What it is |
|---|---|
| `android/app/keystore/upload-keystore.jks` | The upload key (alias `upload`) |
| `android/key.properties` | Points at the keystore + holds its passwords |

Restore both from your own backup. `key.properties`'s `storeFile` is resolved
relative to `android/app/`, so it reads `storeFile=keystore/upload-keystore.jks`.
Then verify:

```bash
flutter build appbundle --release
```

A successful *debug-fallback* build looks identical in the terminal, so confirm the
signing actually took: the build log names the release signing config, and the
resulting AAB must be signed with the upload key for Play to accept it.

> ### ⚠️ If the keystore or its password is lost, it cannot be regenerated
>
> Play matches every update against the original upload key. Losing it means no
> future build can be published as an update — existing users would need a full
> uninstall/reinstall of a differently-signed app to ever get another version.
>
> Keep the `.jks` in durable backup (password manager attachment, encrypted cloud
> storage — somewhere that survives losing this machine) and the password in a
> password manager. **Never commit either**; both are in `.gitignore` precisely so
> an accidental `git add -A` can't publish the signing key.
>
> **On a machine switch this is the one irreplaceable item.** Everything else in
> this document can be reinstalled from the internet; the keystore cannot. Confirm
> you can actually open your backup copy *before* you wipe or hand on the old
> machine.

`android/local.properties` is also machine-local, but the Flutter tooling
regenerates it automatically — nothing to restore.

## B2. Troubleshooting: a build looks stuck

If `flutter run --release` sits at `Running Gradle task 'assembleRelease'...` with
**zero progress for several minutes**, don't assume it's just a slow build (a real
one finishes in well under a minute on this project once Gradle's daemon is warm) —
it's more likely a **stale/orphaned Gradle daemon** left behind by a previously
killed/interrupted `flutter run`. Check the daemon's own log before waiting it out
or killing anything:

```bash
tail -20 "$(ls -t ~/.gradle/daemon/*/daemon-*.out.log | head -1)"
```

If that log already shows `finished executing the build` while your terminal still
shows no progress, Gradle itself is done — the stall is elsewhere (install/launch to
the device). If the log shows no recent activity at all, the daemon is genuinely
stuck:

```bash
cd android && ./gradlew --stop && cd ..
flutter run --release -d <device-id>
```

This cost real debugging time during Sprint 3 before being root-caused — check it
first next time a build "hangs."

## B3. What does *not* travel between machines

- **Claude Code's local memory.** It lives under `~/.claude/projects/…/memory/` per
  machine and has no cross-device sync. Everything durable is deliberately kept in
  git instead — `CLAUDE.md` for operational state, `docs/` for the rest. Nothing
  needs exporting; a fresh session on the new machine reads `CLAUDE.md` and is
  caught up.
- **`.claude/settings.local.json`** — per-machine tool permissions with absolute
  paths (e.g. the Android SDK's `adb`). Expect to re-add these; a Windows
  `...\AppData\Local\Android\Sdk\platform-tools\adb.exe` entry means nothing to a
  Mac, where the same binary is at
  `~/Library/Android/sdk/platform-tools/adb`.
- **The release keystore and `key.properties`** — see B1. Gitignored on purpose.
- **GitHub CLI auth** — stored in the OS keychain/credential store.
- **Gradle and pub caches** — `~/.gradle`, `~/.pub-cache`. Nothing to migrate; they
  rebuild on first build (so budget extra time for that first `flutter run`).

## B4. Done when

`flutter doctor` is green on Flutter + Android toolchain, your phone shows in
`flutter devices`, and `flutter run` launches the app on it. Judge real-world
performance in `--release`, on a low-end device (`CLAUDE.md` §8 — the low-end pass is
still an outstanding gap).

If you also intend to publish, B1's `flutter build appbundle --release` should
succeed with the real keystore in place — not the debug fallback.

---

# Part C — Windows (previous machine; kept for reference)

The procedure this project was developed under through `0.6.4+17`. Still accurate;
just not the current machine.

## C1. Git for Windows

Download from <https://git-scm.com> and install with defaults (keep "Add Git to
PATH" checked). Verify with `git --version`.

## C2. Get the repo onto the machine

Clone into a **short path** — Windows path-length limits break Gradle/Flutter builds
in deep folders:

```powershell
git clone <your-repo-url> C:\src\why_did_i_unlock
```

## C3. Flutter SDK

1. Create `C:\src` if needed. Do **not** install under `C:\Program Files` or any
   admin-only path — Flutter needs to write to its own cache and throws "installed
   in a protected folder" errors otherwise.
2. Download the latest **stable** bundle from <https://docs.flutter.dev/install>
   (Windows → Android), named like `flutter_windows_<version>-stable.zip`.
3. Extract via PowerShell (avoids the double-nested-folder mistake File Explorer
   sometimes makes):

   ```powershell
   Expand-Archive -Path "$env:USERPROFILE\Downloads\flutter_windows_<version>-stable.zip" -DestinationPath "C:\src"
   ```

   Verify the result is `C:\src\flutter\bin\flutter.bat`.
4. Add `C:\src\flutter\bin` to PATH: Start → "Edit environment variables for your
   account" → **User variables** → **Path** → **Edit** → **New**.
5. In a **new** PowerShell, `flutter --version`; confirm bundled Dart ≥ 3.11.5. If
   `flutter.bat` exists but the command still fails, add `C:\src\flutter` as an
   antivirus exclusion.

## C4. Android Studio (SDK only)

Install from <https://developer.android.com/studio> (defaults) → **Standard** setup →
then **More Actions → SDK Manager → SDK Tools → Android SDK Command-line Tools
(latest) → Apply**. Then `flutter doctor --android-licenses`.

Default SDK location: `C:\Users\<you>\AppData\Local\Android\Sdk`. If Flutter can't
find it: `flutter config --android-sdk "C:\Users\<you>\AppData\Local\Android\Sdk"`.

## C5. Claude Code

In **PowerShell** (not CMD, not Git Bash):

```powershell
irm https://claude.ai/install.ps1 | iex
```

Native Windows install — no Node.js, npm, or WSL. Reopen the terminal, then
`claude --version`. If not recognized, confirm `%USERPROFILE%\.local\bin` is on PATH.

## C6. Physical device

Enable Developer Options + USB debugging on the phone, plug in, authorize, then
`flutter devices`. If `adb devices` shows nothing it's a **USB driver** issue —
install the phone brand's OEM driver. If adb sees it but `flutter devices` doesn't,
it's a Flutter SDK config issue.

## C7. Windows-only gotchas

- **Windows Developer Mode must be on.** The federated plugins (`sqflite`,
  `shared_preferences`, `flutter_local_notifications`) need symlink support and fail
  to build without it (`CLAUDE.md` §2). *This does not apply on macOS* — symlinks
  work natively there, which is why Part A never mentions it.
- **[✗] Visual Studio — develop Windows apps** in `flutter doctor` is safe to
  ignore; that's for Windows *desktop* builds. Do not install Visual Studio.
- Stale Gradle daemon check, PowerShell form:

  ```powershell
  Get-ChildItem "$env:USERPROFILE\.gradle\daemon\*\daemon-*.out.log" | Sort-Object LastWriteTime -Descending | Select-Object -First 1 | Get-Content -Tail 20
  ```
