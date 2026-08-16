import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:why_did_i_unlock/discovery_tooltip.dart';
import 'package:why_did_i_unlock/nudge_tuning.dart';

void main() {
  const policy = DiscoveryPolicy();

  setUp(() {
    DiscoverySession.skipThisLaunch = false;
  });

  tearDown(() {
    DiscoverySession.skipThisLaunch = false;
  });

  test('queue is Settings first, then Manage — never both eligible as next', () {
    expect(
      policy.nextTooltip(
        hasUnlocks: true,
        settingsOpened: false,
        manageOpened: false,
        settingsShows: 0,
        manageShows: 0,
      ),
      DiscoveryTarget.settings,
    );
    expect(
      policy.nextTooltip(
        hasUnlocks: true,
        settingsOpened: true,
        manageOpened: false,
        settingsShows: 1,
        manageShows: 0,
      ),
      DiscoveryTarget.manage,
    );
    expect(
      policy.nextTooltip(
        hasUnlocks: true,
        settingsOpened: false,
        manageOpened: false,
        settingsShows: 1,
        manageShows: 0,
        dismissedThisSession: {DiscoveryTarget.settings},
      ),
      DiscoveryTarget.manage,
    );
  });

  test('opening a screen retires that tooltip permanently', () {
    expect(
      policy.nextTooltip(
        hasUnlocks: true,
        settingsOpened: true,
        manageOpened: true,
        settingsShows: 0,
        manageShows: 0,
      ),
      isNull,
    );
  });

  test('show cap retires a tooltip even if the screen was never opened', () {
    expect(
      policy.nextTooltip(
        hasUnlocks: true,
        settingsOpened: false,
        manageOpened: true,
        settingsShows: NudgeTuning.maxTooltipShows,
        manageShows: 0,
      ),
      isNull,
    );
  });

  test('the session after finishing onboarding does not show a tooltip', () {
    DiscoverySession.skipThisLaunch = true;
    expect(
      policy.nextTooltip(
        hasUnlocks: true,
        settingsOpened: false,
        manageOpened: false,
        settingsShows: 0,
        manageShows: 0,
      ),
      isNull,
    );
  });

  test('no unlocks yet — wait for the first real unlock', () {
    expect(
      policy.nextTooltip(
        hasUnlocks: false,
        settingsOpened: false,
        manageOpened: false,
        settingsShows: 0,
        manageShows: 0,
      ),
      isNull,
    );
  });

  test('fallback banner waits for the launch threshold and any unopened screen', () {
    expect(
      policy.showFallbackBanner(
        launchCount: NudgeTuning.nudgeBannerLaunchThreshold - 1,
        settingsOpened: false,
        manageOpened: false,
      ),
      isFalse,
    );
    expect(
      policy.showFallbackBanner(
        launchCount: NudgeTuning.nudgeBannerLaunchThreshold,
        settingsOpened: false,
        manageOpened: true,
      ),
      isTrue,
    );
    expect(
      policy.showFallbackBanner(
        launchCount: NudgeTuning.nudgeBannerLaunchThreshold,
        settingsOpened: true,
        manageOpened: true,
      ),
      isFalse,
    );
  });

  testWidgets('one tooltip at a time, and Open Settings stays tappable', (tester) async {
    final settingsKey = GlobalKey();
    final manageKey = GlobalKey();
    final key = GlobalKey<_TooltipHarnessState>();
    await tester.pumpWidget(MaterialApp(
      home: _TooltipHarness(
        key: key,
        settingsKey: settingsKey,
        manageKey: manageKey,
      ),
    ));
    await tester.pump();

    key.currentState!.show(DiscoveryTarget.settings);
    await tester.pump();
    expect(find.byKey(const ValueKey('discovery-tooltip-settings')), findsOneWidget);
    expect(find.byKey(const ValueKey('discovery-tooltip-manage')), findsNothing);

    await tester.tap(find.text('Open Settings'));
    await tester.pump();
    expect(key.currentState!.settingsTaps, 1);

    key.currentState!.show(DiscoveryTarget.manage);
    await tester.pump();
    expect(find.byKey(const ValueKey('discovery-tooltip-settings')), findsNothing);
    expect(find.byKey(const ValueKey('discovery-tooltip-manage')), findsOneWidget);
    expect(find.text('Got it'), findsOneWidget);
  });
}

class _TooltipHarness extends StatefulWidget {
  final GlobalKey settingsKey;
  final GlobalKey manageKey;

  const _TooltipHarness({
    super.key,
    required this.settingsKey,
    required this.manageKey,
  });

  @override
  State<_TooltipHarness> createState() => _TooltipHarnessState();
}

class _TooltipHarnessState extends State<_TooltipHarness> {
  OverlayEntry? _entry;
  int settingsTaps = 0;

  @override
  void dispose() {
    _entry?.remove();
    super.dispose();
  }

  void show(DiscoveryTarget target) {
    _entry?.remove();
    final targetKey = target == DiscoveryTarget.settings ? widget.settingsKey : widget.manageKey;
    _entry = buildDiscoveryTooltipEntry(
      targetKey: targetKey,
      target: target,
      onGotIt: () {
        _entry?.remove();
        _entry = null;
        setState(() {});
      },
    );
    Overlay.of(context).insert(_entry!);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.only(top: 200),
        child: Column(
          children: [
            TextButton(
              key: widget.settingsKey,
              onPressed: () => settingsTaps++,
              child: const Text('Open Settings'),
            ),
            TextButton(
              key: widget.manageKey,
              onPressed: () {},
              child: const Text('Manage options'),
            ),
          ],
        ),
      ),
    );
  }
}
