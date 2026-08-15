import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:why_did_i_unlock/about_screen.dart';

/// Guards the one fact `appVersion` cannot guarantee about itself: that a
/// hand-maintained constant still matches `pubspec.yaml`.
///
/// Added after it silently didn't. `appVersion` sat at `0.6.3+11` through the
/// `+12` release, so problem-report emails from that build declared the wrong
/// version — which, during the 2026-08-15 overlay investigation, made a
/// correctly-updated build look like a stale one and cost two rounds of
/// diagnosis before `adb shell dumpsys package` settled it.
///
/// The real fix would be reading the version at runtime (`package_info_plus`),
/// but that's a new dependency for a display string, and `CLAUDE.md` §7 says
/// keep the count low. A test costs nothing at runtime and fails the moment
/// the two diverge, which is the property that was actually missing.
void main() {
  test('appVersion matches pubspec.yaml version', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(r'^version:\s*(\S+)\s*$', multiLine: true).firstMatch(pubspec);

    expect(
      match,
      isNotNull,
      reason: 'Could not find a `version:` line in pubspec.yaml',
    );

    expect(
      appVersion,
      match!.group(1),
      reason: 'lib/about_screen.dart\'s appVersion has drifted from '
          'pubspec.yaml. Bump appVersion to match — otherwise every '
          '"Report a problem" email from this build states the wrong version.',
    );
  });
}
