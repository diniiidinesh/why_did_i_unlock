import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:permission_handler/permission_handler.dart';

import 'app_settings.dart';
import 'brand.dart';
import 'device_manufacturer.dart';
import 'oem_autostart_copy.dart';

/// Five-step first-run flow: value prop → how it works → overlay permission
/// (explained before the system dialog, not a cold ask) → OEM reliability →
/// data disclosure. See the sprint 4 plan's screen map — this replaces
/// today's cold permission request in `HomeScreen.initState` (`CLAUDE.md` §9
/// flags exactly this as the top onboarding drop-off risk) with an explained
/// one.
///
/// Plugin/store-touching calls are injectable constructor params defaulting
/// to the real calls, same shape as `HistoryScreen` / `StatusScreen`, so
/// widget tests don't need platform implementations.
class OnboardingScreen extends StatefulWidget {
  final Future<bool> Function() checkPermission;
  final Future<bool?> Function() requestPermission;
  final Future<void> Function() completeOnboarding;

  /// Battery-optimization-exemption check/request — the standard Android
  /// dialog, same as the Status screen's card (see that screen's doc for why
  /// this is distinct from the OEM Autostart Manager screens shown on this
  /// same onboarding step, which have no public API).
  final Future<bool> Function() checkBatteryExemption;
  final Future<void> Function() requestBatteryExemption;

  /// Manufacturer / brand for OEM step matching. Defaults to
  /// [readDeviceManufacturer]; inject in tests.
  final Future<String?> Function() readManufacturer;

  /// Called after [completeOnboarding] resolves on the final step.
  final VoidCallback? onFinished;

  const OnboardingScreen({
    super.key,
    Future<bool> Function()? checkPermission,
    Future<bool?> Function()? requestPermission,
    Future<bool> Function()? checkBatteryExemption,
    Future<void> Function()? requestBatteryExemption,
    Future<String?> Function()? readManufacturer,
    Future<void> Function()? completeOnboarding,
    this.onFinished,
  })  : checkPermission = checkPermission ?? FlutterOverlayWindow.isPermissionGranted,
        requestPermission = requestPermission ?? FlutterOverlayWindow.requestPermission,
        checkBatteryExemption = checkBatteryExemption ?? _defaultCheckBatteryExemption,
        requestBatteryExemption = requestBatteryExemption ?? _defaultRequestBatteryExemption,
        readManufacturer = readManufacturer ?? readDeviceManufacturer,
        completeOnboarding = completeOnboarding ?? _defaultCompleteOnboarding;

  static Future<void> _defaultCompleteOnboarding() => const AppSettings().setOnboardingCompleted(true);

  // Top-level-function tear-offs, not inline closures, so this constructor
  // can stay `const` — see status_screen.dart's identical pattern/doc.
  static Future<bool> _defaultCheckBatteryExemption() => Permission.ignoreBatteryOptimizations.isGranted;

  static Future<void> _defaultRequestBatteryExemption() async {
    await Permission.ignoreBatteryOptimizations.request();
  }

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

const int _stepCount = 5;

class _OnboardingScreenState extends State<OnboardingScreen> with WidgetsBindingObserver {
  final PageController _controller = PageController();
  int _step = 0;
  bool? _permissionGranted;

  /// Same null-while-checking convention as [_permissionGranted]. Lives on
  /// the same step as the OEM autostart guidance (step 3, index 3) since
  /// both are "keep the background service alive" asks.
  bool? _batteryExempt;

  OemGuidance? _matchedOem;
  bool _manufacturerLoaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadManufacturer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadManufacturer() async {
    final raw = await widget.readManufacturer();
    if (!mounted) return;
    setState(() {
      _matchedOem = matchOemGuidance(raw);
      _manufacturerLoaded = true;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // requestPermission() launches Android's "Display over other apps"
    // settings screen and its Future resolves immediately — well before the
    // user has actually flipped the toggle and come back. The real signal
    // that a grant may have happened is this app resuming from the
    // background, not that call returning. Scoped to the permission step so
    // it's a no-op (and doesn't fire a stray plugin call) on every other
    // step of the flow.
    if (state == AppLifecycleState.resumed && _step == 2) {
      _refreshPermission();
    }
    // Same reasoning, one step later: the battery-exemption system dialog
    // (step 3, alongside OEM autostart guidance) also returns immediately,
    // before the user has actually answered it.
    if (state == AppLifecycleState.resumed && _step == 3) {
      _refreshBatteryExemption();
    }
  }

  Future<void> _refreshPermission() async {
    final granted = await widget.checkPermission();
    if (mounted) setState(() => _permissionGranted = granted);
  }

  Future<void> _requestPermission() async {
    await widget.requestPermission();
    await _refreshPermission();
  }

  Future<void> _refreshBatteryExemption() async {
    final exempt = await widget.checkBatteryExemption();
    if (mounted) setState(() => _batteryExempt = exempt);
  }

  Future<void> _requestBatteryExemption() async {
    await widget.requestBatteryExemption();
    await _refreshBatteryExemption();
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
    // Re-checking whenever these steps come into view keeps status honest
    // when navigating back — without auto-advancing again.
    if (index == 2) _refreshPermission();
    if (index == 3) _refreshBatteryExemption();
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
                  _OemReliabilityStep(
                    batteryExempt: _batteryExempt,
                    onRequestBatteryExemption: _requestBatteryExemption,
                    matchedOem: _matchedOem,
                    manufacturerLoaded: _manufacturerLoaded,
                  ),
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
  final IconData? icon;
  final Widget? leading;
  final String headline;
  final String body;
  final Widget? extra;

  const _StepBody({
    this.icon,
    this.leading,
    required this.headline,
    required this.body,
    this.extra,
  }) : assert(icon != null || leading != null);

  @override
  Widget build(BuildContext context) {
    final lead = leading ?? Icon(icon!, color: Colors.white70, size: 40);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          lead,
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
    return _StepBody(
      leading: Image.asset(
        brandMarkAsset,
        width: 48,
        height: 48,
        filterQuality: FilterQuality.high,
      ),
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
          'Unlock your phone and you\'ll be asked what you\'re doing. Tap a '
          'preset or type your own reason — it follows you as a small bubble '
          'across apps until you dismiss it.\n\n'
          'By default you\'re asked on every unlock, except within 1 minute of '
          'the last prompt (so rapid lock/unlock doesn\'t nag). Change that '
          'gap — or how often you\'re asked — anytime in Settings.',
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
          'continue either way and grant it later from Status & troubleshooting.\n\n'
          '$overlayPermissionFindHint',
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
  final bool? batteryExempt;
  final Future<void> Function() onRequestBatteryExemption;
  final OemGuidance? matchedOem;
  final bool manufacturerLoaded;

  const _OemReliabilityStep({
    required this.batteryExempt,
    required this.onRequestBatteryExemption,
    required this.matchedOem,
    required this.manufacturerLoaded,
  });

  @override
  Widget build(BuildContext context) {
    final String statusText;
    final Color statusColor;
    if (batteryExempt == null) {
      statusText = 'Checking…';
      statusColor = Colors.white54;
    } else if (batteryExempt == true) {
      statusText = 'Exempt — background restrictions won\'t apply';
      statusColor = Colors.greenAccent;
    } else {
      statusText = 'Not exempt yet';
      statusColor = Colors.orangeAccent;
    }

    final Widget oemBlock;
    if (!manufacturerLoaded) {
      oemBlock = const Text('Checking your phone…', style: TextStyle(color: Colors.white54, fontSize: 13));
    } else if (matchedOem != null) {
      oemBlock = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Looks like your phone: ${matchedOem!.vendor}',
            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          for (final step in matchedOem!.steps)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('• $step', style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.35)),
            ),
          const SizedBox(height: 8),
          const Text(
            'You can revisit every maker\'s steps anytime in Status & troubleshooting.',
            style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.35),
          ),
        ],
      );
    } else {
      oemBlock = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(genericOemFallback, style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.35)),
          const SizedBox(height: 8),
          const Text(
            'Full maker-specific steps are in Status & troubleshooting if you need them later.',
            style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.35),
          ),
        ],
      );
    }

    return _StepBody(
      icon: Icons.battery_alert_outlined,
      headline: 'Some phones need one more step',
      body:
          'Certain phone makers aggressively stop background apps to save '
          'battery, which can silently stop the prompts.\n\n'
          '$oemGuidanceIntro\n\n'
          'First tap the standard Android exemption below, then follow your '
          'maker\'s steps (especially leaving smart / auto optimize).',
      extra: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(statusText, style: TextStyle(color: statusColor, fontSize: 14)),
          const SizedBox(height: 8),
          if (batteryExempt != true)
            ElevatedButton(onPressed: onRequestBatteryExemption, child: const Text('Disable battery optimization')),
          const SizedBox(height: 20),
          oemBlock,
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
