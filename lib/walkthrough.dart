import 'dart:async';

import 'package:flutter/material.dart';

import 'beacon_theme.dart';
import 'brand.dart';
import 'bubble_widget.dart';
import 'intent_store.dart';
import 'preset_pill.dart';

/// Auto-advance interval per beat. Named so it can be retuned on-device
/// without hunting literals (`docs/erd/onboarding-revamp-2026-08-15.md` §8.4).
const Duration walkthroughBeatDuration = Duration(milliseconds: 2800);

const Duration _kBeatAnim = Duration(milliseconds: 400);

/// The 7 teaching beats, in order. Captions are the Dinesh-approved copy
/// from the onboarding-revamp ERD §4B — do not reword to fit the layout.
enum WalkthroughBeat {
  unlock,
  promptShown,
  promptSelected,
  becomesBubble,
  followsYou,
  markDone,
  snooze,
}

extension WalkthroughBeatCaption on WalkthroughBeat {
  String get caption {
    switch (this) {
      case WalkthroughBeat.unlock:
        return 'You unlock.';
      case WalkthroughBeat.promptShown:
        return '$appDisplayName asks why.';
      case WalkthroughBeat.promptSelected:
        return 'You pick a reason.';
      case WalkthroughBeat.becomesBubble:
        return 'It becomes a bubble.';
      case WalkthroughBeat.followsYou:
        return 'It follows you across apps.';
      case WalkthroughBeat.markDone:
        return 'Tap Done when you\'re finished.';
      case WalkthroughBeat.snooze:
        return 'Or snooze it for later.';
    }
  }
}

String get _demoIntent => defaultPresetLabels.first;

/// Scripted 7-beat walkthrough of unlock → prompt → bubble.
///
/// Main-UI-engine only — never mount this from overlay-isolate code.
/// Reuses [BubbleWidget] and [PresetPill] directly; does not wrap a Ticker
/// that outlives the sequence (autoplay is a [Timer], cancelled on last
/// beat, pause, inactive, and dispose).
class WalkthroughView extends StatefulWidget {
  /// When false, autoplay is stopped (the onboarding [PageView] builds every
  /// step eagerly; only the visible step should tick).
  final bool active;

  /// Pushed from Home / About rather than embedded in onboarding.
  final bool standalone;

  /// Called when a standalone walkthrough should close (Skip on the last
  /// beat, or Done).
  final VoidCallback? onStandaloneFinished;

  const WalkthroughView({
    super.key,
    this.active = true,
    this.standalone = false,
    this.onStandaloneFinished,
  });

  @override
  State<WalkthroughView> createState() => _WalkthroughViewState();
}

class _WalkthroughViewState extends State<WalkthroughView> {
  final PageController _pages = PageController();
  WalkthroughBeat _beat = WalkthroughBeat.unlock;
  bool _paused = false;
  Timer? _autoplay;

  @override
  void initState() {
    super.initState();
    if (widget.active) _scheduleAdvance();
  }

  @override
  void didUpdateWidget(WalkthroughView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      _paused = false;
      _goTo(WalkthroughBeat.unlock, animate: false);
      _scheduleAdvance();
    } else if (!widget.active && oldWidget.active) {
      _autoplay?.cancel();
      _autoplay = null;
    }
  }

  @override
  void dispose() {
    _autoplay?.cancel();
    _pages.dispose();
    super.dispose();
  }

  void _scheduleAdvance() {
    _autoplay?.cancel();
    _autoplay = null;
    if (!widget.active || _paused || _beat == WalkthroughBeat.values.last) {
      return;
    }
    _autoplay = Timer(walkthroughBeatDuration, () {
      if (!mounted || _paused || !widget.active) return;
      final next = _beat.index + 1;
      if (next >= WalkthroughBeat.values.length) return;
      _goTo(WalkthroughBeat.values[next]);
    });
  }

  void _goTo(WalkthroughBeat beat, {bool animate = true}) {
    _beat = beat;
    if (_pages.hasClients) {
      if (animate) {
        _pages.animateToPage(
          beat.index,
          duration: _kBeatAnim,
          curve: Curves.easeOut,
        );
      } else {
        _pages.jumpToPage(beat.index);
      }
    }
    setState(() {});
    _scheduleAdvance();
  }

  void _onPageChanged(int index) {
    final beat = WalkthroughBeat.values[index];
    if (beat == _beat) return;
    setState(() => _beat = beat);
    _scheduleAdvance();
  }

  void _togglePause() {
    if (!widget.active) return;
    setState(() => _paused = !_paused);
    if (_paused) {
      _autoplay?.cancel();
      _autoplay = null;
    } else {
      _scheduleAdvance();
    }
  }

  void _onSkip() {
    if (widget.standalone) {
      widget.onStandaloneFinished?.call();
      return;
    }
    if (_beat == WalkthroughBeat.values.last) return;
    _paused = false;
    _goTo(WalkthroughBeat.values.last, animate: false);
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return _ReducedMotionWalkthrough(
        standalone: widget.standalone,
        onSkip: widget.standalone ? widget.onStandaloneFinished : _onSkip,
      );
    }

    return Column(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _onSkip,
            child: const Text('Skip'),
          ),
        ),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _togglePause,
            child: PageView.builder(
              controller: _pages,
              itemCount: WalkthroughBeat.values.length,
              onPageChanged: _onPageChanged,
              itemBuilder: (context, index) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 36),
                    child: _PhoneFrame(
                      child: _BeatScene(beat: WalkthroughBeat.values[index]),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
          child: Text(
            _beat.caption,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}

class _ReducedMotionWalkthrough extends StatelessWidget {
  final bool standalone;
  final VoidCallback? onSkip;

  const _ReducedMotionWalkthrough({required this.standalone, this.onSkip});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: onSkip,
            child: Text(standalone ? 'Close' : 'Skip'),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
            children: [
              for (final beat in WalkthroughBeat.values)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    beat.caption,
                    style: const TextStyle(color: Colors.white, fontSize: 18, height: 1.35),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PhoneFrame extends StatelessWidget {
  final Widget child;
  const _PhoneFrame({required this.child});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 9 / 17,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white24, width: 3),
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _BeatScene extends StatelessWidget {
  final WalkthroughBeat beat;
  const _BeatScene({required this.beat});

  @override
  Widget build(BuildContext context) {
    final showPrompt = beat == WalkthroughBeat.promptShown || beat == WalkthroughBeat.promptSelected;
    final promptSelected = beat == WalkthroughBeat.promptSelected;
    final showApps = beat == WalkthroughBeat.followsYou ||
        beat == WalkthroughBeat.markDone ||
        beat == WalkthroughBeat.snooze;
    final showCollapsed = beat == WalkthroughBeat.becomesBubble || beat == WalkthroughBeat.followsYou;
    final showExpanded = beat == WalkthroughBeat.markDone || beat == WalkthroughBeat.snooze;
    final bubbleVisible = showCollapsed || showExpanded;
    final bubbleOpacity = beat == WalkthroughBeat.snooze ? 0.0 : 1.0;

    return ColoredBox(
      color: beat == WalkthroughBeat.unlock ? const Color(0xFF0A0A0A) : const Color(0xFF1C1C1E),
      child: Stack(
        children: [
          AnimatedOpacity(
            duration: _kBeatAnim,
            opacity: showApps ? 1 : 0,
            child: const _MockApps(),
          ),
          AnimatedOpacity(
            duration: _kBeatAnim,
            opacity: beat == WalkthroughBeat.unlock ? 1 : 0,
            child: const ColoredBox(color: Color(0xFF0A0A0A)),
          ),
          AnimatedPositioned(
            duration: _kBeatAnim,
            curve: Curves.easeOut,
            left: 8,
            right: 8,
            bottom: showPrompt ? 12 : -220,
            child: IgnorePointer(
              child: _PromptSheet(selected: promptSelected),
            ),
          ),
          if (promptSelected)
            const Positioned(
              left: 0,
              right: 0,
              bottom: 168,
              child: Center(
                child: Text(
                  'Saved',
                  style: TextStyle(
                    color: BeaconColors.amber,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          AnimatedPositioned(
            duration: _kBeatAnim,
            curve: Curves.easeOut,
            right: 8,
            top: showCollapsed || showExpanded ? 72 : 200,
            child: IgnorePointer(
              child: AnimatedOpacity(
                duration: _kBeatAnim,
                opacity: bubbleVisible ? bubbleOpacity : 0,
                child: showExpanded
                    ? SizedBox(
                        width: expandedBubbleWidthDp(_demoIntent),
                        child: BubbleWidget(
                          intentText: _demoIntent,
                          expanded: true,
                          onDone: () {},
                          onSnooze: () {},
                          onToggleExpand: () {},
                        ),
                      )
                    : BubbleWidget(
                        intentText: _demoIntent,
                        expanded: false,
                        onDone: () {},
                        onSnooze: () {},
                        onToggleExpand: () {},
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PromptSheet extends StatelessWidget {
  final bool selected;
  const _PromptSheet({required this.selected});

  @override
  Widget build(BuildContext context) {
    final shown = defaultPresetLabels.take(3).toList();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xF01C1C1E),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'What are you unlocking for?',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              alignment: WrapAlignment.center,
              children: [
                for (final label in shown)
                  Transform.scale(
                    scale: 0.78,
                    child: PresetPill(
                      label: label,
                      selected: selected && label == _demoIntent,
                      onTap: () {},
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MockApps extends StatelessWidget {
  const _MockApps();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFF2C2C2E),
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 36, 56, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Inbox', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
            SizedBox(height: 10),
            _MockRow(),
            SizedBox(height: 8),
            _MockRow(),
            SizedBox(height: 8),
            _MockRow(),
          ],
        ),
      ),
    );
  }
}

class _MockRow extends StatelessWidget {
  const _MockRow();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }
}

/// Full-screen wrapper used by Home / About. Pops itself when the user is done.
class WalkthroughScreen extends StatelessWidget {
  const WalkthroughScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: WalkthroughView(
          standalone: true,
          onStandaloneFinished: () => Navigator.of(context).maybePop(),
        ),
      ),
    );
  }
}
