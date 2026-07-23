import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// The user-visible app name shown on this screen.
///
/// TODO: update when the store brand (`CLAUDE.md` §12) is decided — naming is
/// still `UNRESOLVED`. This is one of several places the current working name
/// lives in code; see the "Cursor note" appended under `CLAUDE.md` §12 for the
/// full list (added alongside this screen, Sprint 4 T5) so nobody has to
/// re-grep the repo the day this is finally settled.
const String appDisplayName = 'Why Did I Unlock';

/// Kept as its own constant rather than read from `pubspec.yaml` at build
/// time (no `package_info_plus` dependency yet — this repo keeps the
/// dependency count low, `CLAUDE.md` §7) — must be bumped by hand alongside
/// `pubspec.yaml`'s `version:` when that changes. [AboutScreen.version]
/// exists specifically so tests don't depend on this staying in sync.
const String appVersion = '0.5.0+7';

/// Real contact address is still an open `[P1]` in `docs/BACKLOG.md`
/// ("dedicated contact email, not plus-addressing"). Deliberately an
/// obviously-fake, grep-able placeholder — `TODO_CONTACT_EMAIL_UNRESOLVED`
/// — rather than a real-looking address, so it can never be mistaken for a
/// working inbox and is trivial to find (`grep -r TODO_CONTACT_EMAIL`) the
/// day a real one is chosen.
const String feedbackEmail = 'TODO_CONTACT_EMAIL_UNRESOLVED@placeholder.invalid';

/// No privacy-policy website exists yet — `docs/PRIVACY_POLICY.md` itself is
/// `[APP NAME]` / `[DATE OF PUBLICATION]` placeholders pending a public repo
/// to host it on (`docs/BACKLOG.md` `[P1]`). Same grep-able-placeholder
/// convention as [feedbackEmail].
const String privacyPolicyUrl = 'https://TODO_PRIVACY_POLICY_URL_UNRESOLVED.placeholder.invalid';

/// No Play listing exists yet (`CLAUDE.md` §5 — sideload-only distribution
/// for now; store brand itself is unresolved, §12). Same convention.
const String playListingUrl = 'https://TODO_PLAY_LISTING_URL_UNRESOLVED.placeholder.invalid';

/// Injected in place of a real `url_launcher` call so widget tests never
/// touch a platform channel — same pattern `HistoryScreen.openStore` uses
/// for `IntentStore`. Defaults to the real plugin call outside of tests.
typedef UrlLauncher = Future<bool> Function(Uri uri);

Future<bool> _defaultLaunch(Uri uri) => launchUrl(uri, mode: LaunchMode.externalApplication);

/// App info, feedback, and (currently placeholder) policy/store links.
/// Read-only, no `IntentStore`/`AppSettings` dependency — this screen is
/// pure static content plus outbound links, so it has nothing to inject
/// beyond [launch] and [version] for testability.
class AboutScreen extends StatelessWidget {
  final UrlLauncher launch;
  final String version;

  const AboutScreen({super.key, UrlLauncher? launch, String? version})
      : launch = launch ?? _defaultLaunch,
        version = version ?? appVersion;

  Future<void> _open(BuildContext context, Uri uri, {required String failureMessage}) async {
    bool ok;
    try {
      ok = await launch(uri);
    } catch (_) {
      // A placeholder host/address, or no app installed that can handle the
      // scheme, both surface here on a real device today — that's expected
      // until the [P1] naming/policy/listing decisions land, not a crash.
      ok = false;
    }
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failureMessage)));
    }
  }

  void _openFeedback(BuildContext context) {
    // Pre-filled with app + OS info so a tester doesn't have to type it —
    // this is the closed-test-scale "just ask them" feedback channel the
    // sprint plan chose over building analytics (docs/BACKLOG.md).
    final uri = Uri(
      scheme: 'mailto',
      path: feedbackEmail,
      queryParameters: {
        'subject': '$appDisplayName feedback ($version)',
        'body': 'App version: $version\nOS: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}\n\n',
      },
    );
    _open(context, uri, failureMessage: 'No email app found to send feedback.');
  }

  void _openPrivacyPolicy(BuildContext context) {
    _open(context, Uri.parse(privacyPolicyUrl), failureMessage: 'Privacy policy isn\'t published yet.');
  }

  void _openPlayListing(BuildContext context, {required String failureMessage}) {
    _open(context, Uri.parse(playListingUrl), failureMessage: failureMessage);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('About'),
      ),
      body: ListView(
        children: [
          const SizedBox(height: 16),
          const Icon(Icons.lock_clock_outlined, color: Colors.white70, size: 48),
          const SizedBox(height: 8),
          const Center(
            child: Text(appDisplayName, style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600)),
          ),
          Center(
            child: Text('Version $version', style: const TextStyle(color: Colors.white54, fontSize: 13)),
          ),
          const SizedBox(height: 24),
          const _SectionDivider(),
          ListTile(
            iconColor: Colors.white70,
            textColor: Colors.white,
            leading: const Icon(Icons.mail_outline),
            title: const Text('Send feedback'),
            subtitle: const Text('Email the developer', style: TextStyle(color: Colors.white38)),
            onTap: () => _openFeedback(context),
          ),
          ListTile(
            iconColor: Colors.white70,
            textColor: Colors.white,
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Privacy policy'),
            onTap: () => _openPrivacyPolicy(context),
          ),
          ListTile(
            iconColor: Colors.white70,
            textColor: Colors.white,
            leading: const Icon(Icons.star_border),
            title: const Text('Rate on Play'),
            onTap: () => _openPlayListing(context, failureMessage: 'Not on Google Play yet.'),
          ),
          ListTile(
            iconColor: Colors.white70,
            textColor: Colors.white,
            leading: const Icon(Icons.share_outlined),
            title: const Text('Share'),
            subtitle: const Text('Share the Play listing with a friend', style: TextStyle(color: Colors.white38)),
            onTap: () => _openPlayListing(context, failureMessage: 'Nothing to share yet — no Play listing.'),
          ),
          const _SectionDivider(),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('Support', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Text(
              // Deliberately copy-only, no payment links — payment links are
              // explicitly deferred past first Play approval (sprint plan
              // "Already decided" list) and monetization itself is still
              // UNDECIDED (CLAUDE.md SS11).
              'This app is free to use while in closed testing. If you\'d like to support '
              'development, that option isn\'t available yet — check back after launch.',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _SectionDivider extends StatelessWidget {
  const _SectionDivider();

  @override
  Widget build(BuildContext context) => const Divider(color: Colors.white12, height: 1);
}
