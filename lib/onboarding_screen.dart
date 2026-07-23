import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

import 'app_settings.dart';
import 'oem_autostart_copy.dart';

/// Five-step first-run flow: value prop → how it works → overlay permission
/// (explained before the system dialog, not a cold ask) → OEM reliability →
/// data disclosure. See the sprint 4 plan's screen map — this replaces
/// today's cold permission request in `HomeScreen.initState` (`CLAUDE.md` §9
/// flags exactly this as the top onboarding drop-off risk) with an explained
/// one, though wiring `MyApp` to actually show this before `HomeScreen` is
/// out of scope here (Claude Code/T18 owns `main.dart`).
///
/// All three plugin/store-touching calls — permission check, permission
/// request, and marking onboarding complete — are injectable constructor
/// params defaulting to the real calls, same shape as `HistoryScreen`
/// (`IntentStore`) and `StatusScreen` (`FlutterOverlayWindow`), and for the
/// same reason: none of them have a real platform implementation under
/// `flutter_test`.
class OnboardingScreen extends StatefulWidget {
  final Future<bool> Function() checkPermission;
  final Future<bool?> Function() requestPermission;
  final Future<void> Function() completeOnboarding;

  /// Called after [completeOnboarding] resolves on the final step. Optional
  /// because this screen doesn't own navigation (nothing wires it into
  /// `MyApp` yet — that's T18's job); it exists purely so a future caller,
  /// or a test, can observe "onboarding just finished" without this screen
  /// needing to know what happens next.
  final VoidCallback? onFinished;

  const OnboardingScreen({
    super.key,
    Future<bool> Function()? checkPermission,
    Future<bool?> Function()? requestPermission,
    Future<void> Function()? completeOnboarding,
    this.onFinished,
  })  : checkPermission = checkPermission ?? FlutterOverlayWindow.isPermissionGranted,
        requestPermission = requestPermission ?? FlutterOverlayWindow.requestPermission,
        completeOnboarding = completeOnboarding ?? _defaultCompleteOnboarding;

  static Future<void> _defaultCompleteOnboarding() => const AppSettings().setOnboardingCompleted(true);

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

const int _stepCount = 5;

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _controller = PageController();
  int _step = 0;
  bool? _permissionGranted;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _refreshPermission() async {
    final granted = await widget.checkPermission();
    if (mounted) setState(() => _permissionGranted = granted);
  }

  Future<void> _requestPermission() async {
    await widget.requestPermission();
    await _refreshPermission();
  }

  void _next() {
    if (_step == _stepCount - 1) {
      _finish();
      return;
    }
    _controller.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  void _back() {
    _controller.previousPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  Future<void> _finish() async {
    await widget.completeOnboarding();
    widget.onFinished?.call();
  }

  void _onPageChanged(int index) {
    setState(() => _step = index);
    // Permission state can only change while this screen is open by the
    // user granting/denying it in the system dialog triggered from step 3,
    // but re-checking whenever step 3 comes into view (including navigating
    // back to it) keeps the displayed status honest either way.
    if (index == 2) _refreshPermission();
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _step == _stepCount - 1;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _controller,
                onPageChanged: _onPageChanged,
                children: [
                  const _ValuePropStep(),
                  const _HowItWorksStep(),
                  _PermissionStep(
                    granted: _permissionGranted,
                    onGrant: _requestPermission,
                  ),
                  const _OemReliabilityStep(),
                  const _YourDataStep(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Column(
                children: [
                  _StepDots(step: _step, count: _stepCount),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      if (_step > 0)
                        TextButton(onPressed: _back, child: const Text('Back'))
                      else
                        const SizedBox.shrink(),
                      const Spacer(),
                      ElevatedButton(
                        onPressed: _next,
                        child: Text(isLast ? 'Get started' : 'Continue'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepDots extends StatelessWidget {
  final int step;
  final int count;
  const _StepDots({required this.step, required this.count});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final active = i == step;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: active ? 10 : 6,
          height: 6,
          decoration: BoxDecoration(
            color: active ? Colors.white : Colors.white24,
            borderRadius: BorderRadius.circular(3),
          ),
        );
      }),
    );
  }
}

/// Shared scaffolding for a step's content: icon, headline, body — every
/// step follows this shape so the flow reads consistently while each step's
/// widget below only supplies its own copy/extra content.
class _StepBody extends StatelessWidget {
  final IconData icon;
  final String headline;
  final String body;
  final Widget? extra;

  const _StepBody({required this.icon, required this.headline, required this.body, this.extra});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.white70, size: 40),
          const SizedBox(height: 24),
          Text(headline, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Text(body, style: const TextStyle(color: Colors.white70, fontSize: 15, height: 1.4)),
          if (extra != null) ...[const SizedBox(height: 20), extra!],
        ],
      ),
    );
  }
}

class _ValuePropStep extends StatelessWidget {
  const _ValuePropStep();

  @override
  Widget build(BuildContext context) {
    return const _StepBody(
      icon: Icons.lock_clock_outlined,
      headline: 'Notice why you picked up your phone',
      body:
          'Most unlocks happen on autopilot. This app asks what you\'re unlocking '
          'for, then keeps that intent on screen as a bubble until you\'re done — '
          'so a quick check becomes a deliberate one.',
    );
  }
}

class _HowItWorksStep extends StatelessWidget {
  const _HowItWorksStep();

  @override
  Widget build(BuildContext context) {
    return const _StepBody(
      icon: Icons.timeline_outlined,
      headline: 'How it works',
      body:
          'Unlock your phone, and sometimes you\'ll be asked what you\'re doing. '
          'Tap a preset or type your own reason, and it follows you as a small '
          'bubble across apps — a gentle reminder of what you came to do, until '
          'you dismiss it.',
    );
  }
}

class _PermissionStep extends StatelessWidget {
  final bool? granted;
  final Future<void> Function() onGrant;

  const _PermissionStep({required this.granted, required this.onGrant});

  @override
  Widget build(BuildContext context) {
    final String statusText;
    final Color statusColor;
    if (granted == null) {
      statusText = 'Checking…';
      statusColor = Colors.white54;
    } else if (granted == true) {
      statusText = 'Granted — you\'re all set';
      statusColor = Colors.greenAccent;
    } else {
      statusText = 'Not granted yet';
      statusColor = Colors.orangeAccent;
    }

    return _StepBody(
      icon: Icons.layers_outlined,
      headline: 'One permission is needed',
      body:
          'The bubble that follows you across apps needs the "Display over other '
          'apps" permission. Android requires this for any floating overlay — we '
          'only use it to show your declared intent, nothing else. You can '
          'continue either way and grant it later from Settings.',
      extra: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(statusText, style: TextStyle(color: statusColor, fontSize: 14)),
          const SizedBox(height: 12),
          if (granted != true)
            ElevatedButton(onPressed: onGrant, child: const Text('Grant permission')),
        ],
      ),
    );
  }
}

class _OemReliabilityStep extends StatelessWidget {
  const _OemReliabilityStep();

  @override
  Widget build(BuildContext context) {
    return _StepBody(
      icon: Icons.battery_alert_outlined,
      headline: 'Some phones need one more step',
      body:
          'Certain phone makers aggressively stop background apps to save '
          'battery, which can silently stop the prompts. If your phone is one '
          'of these, allow autostart / unrestricted battery use so monitoring '
          'keeps running. If you\'re not sure, you can always check this again '
          'later from Status & troubleshooting.',
      extra: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final g in oemAutostartGuidance) Text('• ${g.vendor}', style: const TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 8),
          const Text('My phone isn\'t listed?', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(genericOemFallback, style: const TextStyle(color: Colors.white70, fontSize: 13)),
        ],
      ),
    );
  }
}

class _YourDataStep extends StatelessWidget {
  const _YourDataStep();

  @override
  Widget build(BuildContext context) {
    return const _StepBody(
      icon: Icons.shield_outlined,
      headline: 'Your data stays on your phone',
      body:
          'Everything you declare is stored only in this app\'s private storage — '
          'no accounts, no analytics, no network calls of any kind. You\'ll be '
          'able to review your history, adjust how long it\'s kept, export it, '
          'or delete it at any time from Settings.',
    );
  }
}
