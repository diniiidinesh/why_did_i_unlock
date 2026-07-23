import 'package:flutter/material.dart';
import 'package:why_did_i_unlock/about_screen.dart';
import 'package:why_did_i_unlock/insights/outcome_donut.dart';
import 'package:why_did_i_unlock/manage_presets_screen.dart';
import 'package:why_did_i_unlock/onboarding_screen.dart';
import 'package:why_did_i_unlock/status_screen.dart';

/// DEV-ONLY manual-QA harness for the Sprint 4 Cursor UI screens
/// (T4/T5/T6/T15/T16) — NOT part of the shipped app and NOT wired into
/// `lib/main.dart` (that file is Claude Code's; wiring these into real
/// navigation is T18, still pending). This lets a human open each screen
/// on a real device/emulator today, before T18 lands, without touching
/// `main.dart` at all.
///
/// Run it with a separate entrypoint flag, e.g.:
///
///   flutter run -t tool/preview_screens.dart -d DEVICE_ID
///
/// Every screen below is pushed with its REAL default dependencies (real
/// `FlutterOverlayWindow` permission calls, a real on-device `IntentStore`
/// connection, real `url_launcher`) — this is genuine manual verification
/// against the same code path the real app will eventually use, not a
/// mocked walkthrough. That's also exactly why `flutter test` can't
/// substitute for this: none of those real plugin calls have a platform
/// implementation under the test framework.
void main() {
  runApp(const _PreviewApp());
}

class _PreviewApp extends StatelessWidget {
  const _PreviewApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sprint 4 screen preview (dev only)',
      theme: ThemeData.dark(),
      home: const _PreviewMenu(),
    );
  }
}

class _PreviewMenu extends StatelessWidget {
  const _PreviewMenu();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Preview a Sprint 4 screen'),
      ),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Dev-only harness — not part of the shipped app. Tap a screen to open it '
              'with its real dependencies (permission checks, on-device storage, etc).',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ),
          _tile(context, 'T4 — Onboarding', (_) => const OnboardingScreen()),
          _tile(context, 'T5 — About', (_) => const AboutScreen()),
          _tile(context, 'T6 — Status & troubleshooting', (_) => const StatusScreen()),
          _tile(context, 'T15 — Outcome donut (sample data)', (_) => const _DonutPreview()),
          _tile(context, 'T16 — Manage presets (real on-device store)', (_) => const ManagePresetsScreen()),
        ],
      ),
    );
  }

  Widget _tile(BuildContext context, String title, WidgetBuilder builder) {
    return ListTile(
      textColor: Colors.white,
      title: Text(title),
      trailing: const Icon(Icons.chevron_right, color: Colors.white38),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: builder)),
    );
  }
}

/// T15 has no store dependency by design (see its own doc comment) — this
/// wraps it with representative sample slices so it's visible standalone,
/// the same shape T18 will eventually feed it with real aggregated counts.
class _DonutPreview extends StatelessWidget {
  const _DonutPreview();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, title: const Text('Outcome donut (sample)')),
      body: const Center(
        child: OutcomeDonut(
          slices: [
            DonutSlice(label: 'Done', value: 12, color: Colors.greenAccent),
            DonutSlice(label: 'Abandoned', value: 3, color: Colors.orangeAccent),
            DonutSlice(label: 'No intent', value: 5, color: Colors.white38),
          ],
          centerLabel: '20',
        ),
      ),
    );
  }
}
