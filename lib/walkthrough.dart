import 'dart:async';

import 'package:flutter/material.dart';

import 'beacon_theme.dart';
import 'brand.dart';
import 'bubble_widget.dart';
import 'intent_store.dart';
import 'preset_pill.dart';

/// Feel-tune these on device; they are the only walkthrough timings.
///
/// - [walkthroughBeatDuration] — how long each beat holds before auto-advance
/// - [walkthroughMorphDuration] — pill→bubble / sheet / dock interpolation
/// - [walkthroughHighlightDuration] — Done halo
/// - [walkthroughSnoozeHoldDuration] — Snooze pulse before the bubble fades
///   (longer than a normal highlight so that last teaching beat can land)
const Duration walkthroughBeatDuration = Duration(milliseconds: 2800);
const Duration walkthroughMorphDuration = Duration(milliseconds: 500);
const Duration walkthroughHighlightDuration = Duration(milliseconds: 900);
const Duration walkthroughSnoozeHoldDuration = Duration(milliseconds: 1800);

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
/// One persistent phone frame: beat changes morph the same prompt / bubble
/// via implicit animations. A hidden [PageView] is only the swipe-to-scrub
/// gesture surface — it must not slide a new frame onto the screen.
/// Reuses [BubbleWidget] and [PresetPill] directly; autoplay is a [Timer],
/// cancelled on last beat, pause, inactive, and dispose.
class WalkthroughView extends StatefulWidget {
  /// When false, autoplay is stopped (the onboarding [PageView] builds every
  /// step eagerly; only the visible step should tick).
  final bool active;

  /// Pushed from Home / About rather than embedded in onboarding.
  final bool standalone;

  /// When false, the caller owns close (e.g. [WalkthroughScreen]'s AppBar).
  final bool showCloseButton;

  /// Called while [active] when playback reaches or leaves the last beat.
  /// `true` means still playing (not last beat); `false` means holding on
  /// the last beat (or reduced-motion, which has no sequence).
  final ValueChanged<bool>? onPlaybackActive;

  /// Called when a standalone walkthrough should close (Skip on the last
  /// beat, or Done).
  final VoidCallback? onStandaloneFinished;

  const WalkthroughView({
    super.key,
    this.active = true,
    this.standalone = false,
    this.showCloseButton = true,
    this.onPlaybackActive,
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
  bool? _lastNotifiedPlaying;

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
      _lastNotifiedPlaying = null;
      _goTo(WalkthroughBeat.unlock);
    } else if (!widget.active && oldWidget.active) {
      _autoplay?.cancel();
      _autoplay = null;
      _lastNotifiedPlaying = null;
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

  void _goTo(WalkthroughBeat beat) {
    _beat = beat;
    // Always jump: the PageView is an invisible scrubber. Animating it would
    // slide empty pages underneath a frame that is supposed to morph in place.
    if (_pages.hasClients && _pages.page?.round() != beat.index) {
      _pages.jumpToPage(beat.index);
    }
    setState(() {});
    _scheduleAdvance();
    _notifyPlayback();
  }

  void _onPageChanged(int index) {
    final beat = WalkthroughBeat.values[index];
    if (beat == _beat) return;
    setState(() => _beat = beat);
    _scheduleAdvance();
    _notifyPlayback();
  }

  bool _isPlaying(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return false;
    return _beat != WalkthroughBeat.values.last;
  }

  void _notifyPlayback() {
    if (!widget.active || widget.onPlaybackActive == null) return;
    final playing = _isPlaying(context);
    if (_lastNotifiedPlaying == playing) return;
    _lastNotifiedPlaying = playing;
    final cb = widget.onPlaybackActive!;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.active) return;
      cb(playing);
    });
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
    if (_beat == WalkthroughBeat.values.last) return;
    _paused = false;
    _goTo(WalkthroughBeat.values.last);
  }

  @override
  Widget build(BuildContext context) {
    _notifyPlayback();
    if (MediaQuery.disableAnimationsOf(context)) {
      return _ReducedMotionWalkthrough(
        standalone: widget.standalone,
        showCloseButton: widget.showCloseButton,
        onSkip: widget.standalone ? widget.onStandaloneFinished : _onSkip,
      );
    }

    return Column(
      children: [
        if (widget.showCloseButton &&
            !(widget.standalone && _beat == WalkthroughBeat.values.last))
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _onSkip,
              child: const Text('Skip'),
            ),
          ),
        Expanded(
          child: GestureDetector(
            key: const ValueKey('walkthrough-stage'),
            behavior: HitTestBehavior.opaque,
            onTap: _togglePause,
            child: Stack(
              fit: StackFit.expand,
              children: [
                PageView.builder(
                  controller: _pages,
                  itemCount: WalkthroughBeat.values.length,
                  onPageChanged: _onPageChanged,
                  itemBuilder: (context, index) => const SizedBox.expand(),
                ),
                IgnorePointer(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 36),
                      child: _PhoneFrame(
                        key: const ValueKey('walkthrough-phone'),
                        child: _BeatScene(beat: _beat),
                      ),
                    ),
                  ),
                ),
              ],
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
        if (widget.standalone && _beat == WalkthroughBeat.values.last)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: widget.onStandaloneFinished,
                child: const Text('Done'),
              ),
            ),
          ),
      ],
    );
  }
}

class _ReducedMotionWalkthrough extends StatelessWidget {
  final bool standalone;
  final bool showCloseButton;
  final VoidCallback? onSkip;

  const _ReducedMotionWalkthrough({
    required this.standalone,
    this.showCloseButton = true,
    this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (showCloseButton)
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
        if (standalone)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onSkip,
                child: const Text('Done'),
              ),
            ),
          ),
      ],
    );
  }
}

class _PhoneFrame extends StatelessWidget {
  final Widget child;
  const _PhoneFrame({super.key, required this.child});

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

class _BeatScene extends StatefulWidget {
  final WalkthroughBeat beat;
  const _BeatScene({required this.beat});

  @override
  State<_BeatScene> createState() => _BeatSceneState();
}

class _BeatSceneState extends State<_BeatScene> {
  Timer? _snoozeFade;
  bool _snoozeDismissed = false;

  @override
  void initState() {
    super.initState();
    _armSnoozeFade();
  }

  @override
  void didUpdateWidget(_BeatScene oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.beat != widget.beat) _armSnoozeFade();
  }

  @override
  void dispose() {
    _snoozeFade?.cancel();
    super.dispose();
  }

  void _armSnoozeFade() {
    _snoozeFade?.cancel();
    _snoozeDismissed = false;
    if (widget.beat != WalkthroughBeat.snooze) return;
    _snoozeFade = Timer(walkthroughSnoozeHoldDuration, () {
      if (mounted) setState(() => _snoozeDismissed = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final beat = widget.beat;
    final showPrompt =
        beat == WalkthroughBeat.promptShown || beat == WalkthroughBeat.promptSelected;
    final promptSelected = beat == WalkthroughBeat.promptSelected;
    final showApps = beat == WalkthroughBeat.followsYou ||
        beat == WalkthroughBeat.markDone ||
        beat == WalkthroughBeat.snooze;
    final showCollapsed =
        beat == WalkthroughBeat.becomesBubble || beat == WalkthroughBeat.followsYou;
    final showExpanded =
        beat == WalkthroughBeat.markDone || beat == WalkthroughBeat.snooze;
    final docked = showCollapsed || showExpanded;

    return ColoredBox(
      color: const Color(0xFF1C1C1E),
      child: Stack(
        children: [
          AnimatedOpacity(
            duration: walkthroughMorphDuration,
            opacity: showApps ? 1 : 0,
            child: const _MockApps(),
          ),
          AnimatedOpacity(
            duration: walkthroughMorphDuration,
            opacity: beat == WalkthroughBeat.unlock ? 1 : 0,
            child: const ColoredBox(color: Color(0xFF0A0A0A)),
          ),
          AnimatedPositioned(
            duration: walkthroughMorphDuration,
            curve: Curves.easeOutCubic,
            left: 8,
            right: 8,
            bottom: showPrompt ? 12 : -220,
            child: IgnorePointer(
              child: _PromptSheet(selected: promptSelected),
            ),
          ),
          AnimatedPositioned(
            duration: walkthroughMorphDuration,
            curve: Curves.easeOutCubic,
            right: 8,
            top: docked ? 72 : 200,
            child: AnimatedOpacity(
              duration: walkthroughMorphDuration,
              opacity: docked && !_snoozeDismissed ? 1 : 0,
              child: _DockedBubble(
                expanded: showExpanded,
                highlightDone: beat == WalkthroughBeat.markDone,
                highlightSnooze: beat == WalkthroughBeat.snooze && !_snoozeDismissed,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Matches [_BubbleAction] layout in `bubble_widget.dart` (32dp, 8dp trailing
/// padding, 6dp gap). Rings sit *around* the icons — stroke only, no label.
const double _kActionDp = 32;
const double _kActionGap = 6;
const double _kBubblePadRight = 8;
const double _kRingDp = 40;

class _DockedBubble extends StatelessWidget {
  final bool expanded;
  final bool highlightDone;
  final bool highlightSnooze;

  const _DockedBubble({
    required this.expanded,
    required this.highlightDone,
    required this.highlightSnooze,
  });

  @override
  Widget build(BuildContext context) {
    if (!expanded) {
      return SizedBox(
        width: bubbleCollapsedDp,
        child: BubbleWidget(
          intentText: _demoIntent,
          expanded: false,
          onDone: () {},
          onSnooze: () {},
          onToggleExpand: () {},
        ),
      );
    }
    return SizedBox(
      width: expandedBubbleWidthDp(_demoIntent),
      height: bubbleExpandedHeightDp,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          BubbleWidget(
            intentText: _demoIntent,
            expanded: true,
            onDone: () {},
            onSnooze: () {},
            onToggleExpand: () {},
          ),
          if (highlightDone)
            Positioned(
              key: const ValueKey('walkthrough-highlight-done'),
              right: _ringRight(_kBubblePadRight + _kActionDp / 2),
              top: (bubbleExpandedHeightDp - _kRingDp) / 2,
              child: const _PulseRing(),
            ),
          if (highlightSnooze)
            Positioned(
              key: const ValueKey('walkthrough-highlight-snooze'),
              right: _ringRight(
                _kBubblePadRight + _kActionDp + _kActionGap + _kActionDp / 2,
              ),
              top: (bubbleExpandedHeightDp - _kRingDp) / 2,
              child: const _PulseRing(),
            ),
        ],
      ),
    );
  }

  static double _ringRight(double centerFromRight) => centerFromRight - _kRingDp / 2;
}

/// Stroke-only circle that pulses. Square [SizedBox] so BoxShape.circle stays
/// round even inside a tight row. Ticker is disposed with the State.
class _PulseRing extends StatefulWidget {
  const _PulseRing();

  @override
  State<_PulseRing> createState() => _PulseRingState();
}

class _PulseRingState extends State<_PulseRing> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: Tween<double>(begin: 0.92, end: 1.12).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
      ),
      child: SizedBox(
        width: _kRingDp,
        height: _kRingDp,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: BeaconColors.amber, width: 2),
          ),
        ),
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
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: const CloseButton(),
        title: const Text('How Beacon works'),
      ),
      body: SafeArea(
        child: WalkthroughView(
          standalone: true,
          onStandaloneFinished: () => Navigator.of(context).maybePop(),
        ),
      ),
    );
  }
}
