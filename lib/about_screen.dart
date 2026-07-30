import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'brand.dart';
import 'problem_report.dart';

export 'brand.dart'
    show
        appDisplayName,
        brandMarkAsset,
        feedbackEmail,
        privacyPolicyUrl,
        playListingUrl;

/// Kept as its own constant rather than read from `pubspec.yaml` at build
/// time (no `package_info_plus` dependency yet — this repo keeps the
/// dependency count low, `CLAUDE.md` §7) — must be bumped by hand alongside
/// `pubspec.yaml`'s `version:` when that changes. [AboutScreen.version]
/// exists specifically so tests don't depend on this staying in sync.
const String appVersion = '0.6.2+10';

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

  /// Optional override for tests — defaults to [ProblemReportLog.snapshotForEmail].
  final Future<String> Function()? problemLogSnapshot;

  const AboutScreen({
    super.key,
    UrlLauncher? launch,
    String? version,
    this.problemLogSnapshot,
  })  : launch = launch ?? _defaultLaunch,
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

  Future<void> _openProblemReport(BuildContext context) async {
    final snapshot = await (problemLogSnapshot ?? ProblemReportLog.snapshotForEmail)();
    if (!context.mounted) return;
    final body = 'App version: $version\n'
        'OS: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}\n\n'
        'What happened?\n'
        '(Describe what you were doing when it failed.)\n\n\n'
        'Recent in-app errors (auto-filled; may be empty):\n'
        '$snapshot\n';
    final uri = Uri(
      scheme: 'mailto',
      path: feedbackEmail,
      queryParameters: {
        'subject': '$appDisplayName problem report ($version)',
        'body': body,
      },
    );
    await _open(context, uri, failureMessage: 'No email app found to send a report.');
  }

  void _openPrivacyPolicy(BuildContext context) {
    _open(context, Uri.parse(privacyPolicyUrl), failureMessage: 'Couldn\'t open the privacy policy.');
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
          Center(
            child: Image.asset(
              brandMarkAsset,
              width: 72,
              height: 72,
              filterQuality: FilterQuality.high,
            ),
          ),
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
            leading: const Icon(Icons.bug_report_outlined),
            title: const Text('Report a problem'),
            subtitle: const Text(
              'Email a crash/bug report (includes recent in-app errors if any)',
              style: TextStyle(color: Colors.white38),
            ),
            onTap: () => _openProblemReport(context),
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
