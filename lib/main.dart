import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:shared_preferences/shared_preferences.dart';

const List<String> intentPresets = [
  'Payments',
  'Calls',
  'Messages',
  'Food Order',
  'Commute',
];

/// Label for the honest "no real reason" option. Deliberately NOT a plain
/// "Skip" — it still logs (see [_OverlayRootState._submitNoIntent]), just
/// without forcing a fake intent or showing a bubble. A too-easy bypass would
/// undercut the whole friction mechanic; this keeps the friction while being
/// honest about habitual/purposeless unlocks (itself useful signal).
const String noIntentLabel = 'Just Like That';

/// Max characters accepted by the custom-intent text field. Kept as a named
/// constant so raising or lowering the limit later is a one-line change.
const int intentMaxInputLength = 100;

/// Collapsed bubble (pill) size in logical pixels (dp). NOTE: the plugin's
/// showOverlay() treats width/height as raw *device pixels*, not dp, so these
/// are multiplied by devicePixelRatio at call time (see _submitIntent).
const double _bubbleWidthDp = 200;
const double _bubbleHeightDp = 56;

/// Platform channel shared by native → Dart unlock/lock notifications.
/// The handler is installed by [backgroundMain] (the persistent background
/// engine), NOT by the main UI — see the architecture note on backgroundMain.
const MethodChannel _unlockChannel = MethodChannel('com.whydidiunlock/unlock');

/// SharedPreferences key for the master on/off toggle. Kept as its own
/// standalone stored value — not folded into a hypothetical "settings blob"
/// — so future schedule-based rules (e.g. quiet hours) can be added as
/// separate stored state later without changing what this switch means.
/// shared_preferences (not sqflite) because this is a single flag, not the
/// intent-history log; it works fine from the headless background engine,
/// since — unlike the overlay engine — it has full plugin registration.
const String promptsEnabledKey = 'prompts_enabled';

/// Whether the capture screen should be shown right now. Today this only
/// checks the master toggle above; this is the seam where future
/// schedule-based rules would ALSO be checked, as additional conditions —
/// not merged into the master toggle's own meaning.
///
/// Uses SharedPreferencesAsync (not SharedPreferences.getInstance()), which
/// caches a static per-isolate singleton on first use — a real bug here,
/// since the toggle is written from HomeScreen's engine but read from the
/// separate persistent background engine's isolate. The cached copy in the
/// background isolate never saw writes from the other engine. Async reads
/// the platform directly on every call, no isolate-local caching.
Future<bool> _shouldPrompt() async {
  final prefs = SharedPreferencesAsync();
  return await prefs.getBool(promptsEnabledKey) ?? true;
}

void main() {
  runApp(const MyApp());
}

/// Headless entry point for the PERSISTENT BACKGROUND ENGINE.
///
/// This runs in its own Flutter engine hosted by `UnlockListenerService`
/// (native), which the foreground service keeps alive independently of any
/// Activity. That's the whole point: `MainActivity`'s engine is destroyed when
/// the user swipes the app out of Recents, so the unlock-reaction logic must
/// NOT live there — it lives here, where it survives task removal. This engine
/// has `flutter_overlay_window` registered (auto-registered natively), so it
/// can call showOverlay(); the overlay engine itself cannot (no plugins on it).
/// See docs/ARCHITECTURE.md for the full engine topology.
@pragma("vm:entry-point")
void backgroundMain() {
  WidgetsFlutterBinding.ensureInitialized();
  _unlockChannel.setMethodCallHandler((call) async {
    if (call.method == 'onUnlock') {
      debugPrint('🔓 UNLOCK EVENT RECEIVED at ${DateTime.now()}');
      // Gate only the prompt — monitoring/logging above still runs either
      // way, so turning this off doesn't stop the service, just the popup.
      if (!await _shouldPrompt()) {
        debugPrint('🔕 Prompts disabled, skipping');
        return;
      }
      final args = (call.arguments as Map?) ?? const {};
      final width = (args['width'] as num?)?.toInt() ?? 0;
      final height = (args['height'] as num?)?.toInt() ?? 0;
      await _showCaptureScreen(width, height);
    } else if (call.method == 'onLock') {
      debugPrint('🔒 LOCK EVENT RECEIVED at ${DateTime.now()}');
    }
  });
  debugPrint('🧠 backgroundMain ready (persistent background engine)');
}

@pragma("vm:entry-point")
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      color: Colors.transparent,
      home: OverlayRoot(),
    ),
  );
}

/// Shows the intent-capture overlay on unlock. Lives at top level (not in a
/// widget) because it runs in the headless background engine — see
/// [backgroundMain]. [screenWidth]/[screenHeight] are the true display size in
/// raw device pixels, provided by native (the headless engine can't read
/// display metrics itself).
Future<void> _showCaptureScreen(int screenWidth, int screenHeight) async {
  final hasPermission = await FlutterOverlayWindow.isPermissionGranted();
  debugPrint('📋 Has overlay permission: $hasPermission');
  if (!hasPermission) return;

  if (screenWidth <= 0 || screenHeight <= 0) {
    debugPrint('⚠️ Invalid screen size ($screenWidth x $screenHeight), skipping');
    return;
  }

  final alreadyActive = await FlutterOverlayWindow.isActive();
  if (alreadyActive) {
    debugPrint('🟡 Overlay already active, skipping re-trigger');
    return;
  }

  // Size the window from the native-provided true display size (raw device
  // pixels — exactly what showOverlay() expects; see CLAUDE.md §5). We do NOT
  // use PlatformDispatcher here because this runs in the headless background
  // engine, which has no display surface and reports 0x0. We also avoid the
  // plugin's WindowSize.fullCover, whose native screenHeight() under-covers
  // the bottom on this device.
  //
  // alignment MUST be topLeft, not center. Confirmed via `dumpsys window
  // windows`: with center gravity, Android fits the window's "parent" frame
  // to exclude the nav bar (height 2337 = 2400 - 63px nav bar), then CENTERS
  // our (taller) requested window inside that shrunk region — shifting it up
  // ~31px (half the nav-bar inset) so the bottom lands 31px short of the true
  // display bottom. That's the exposed-bottom bug; it's a gravity/fit
  // artifact, not a size or position value problem (both were already
  // correct). topLeft anchors to the true origin instead of centering within
  // an inset-shrunk region.
  //
  // startPosition (0,0): pins the window to the true top-left; without it the
  // plugin's default position shifts the window up by the status-bar height.
  await FlutterOverlayWindow.showOverlay(
    height: screenHeight,
    width: screenWidth,
    alignment: OverlayAlignment.topLeft,
    flag: OverlayFlag.focusPointer,
    startPosition: const OverlayPosition(0, 0),
    overlayTitle: 'Why Did I Unlock?',
    overlayContent: 'Declare your intent',
  );
  debugPrint('🟣 showOverlay called (${screenWidth}x$screenHeight capture screen)');
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {

  // NOTE: unlock/lock handling deliberately does NOT live here anymore. It runs
  // in the persistent background engine (see backgroundMain) so it survives the
  // app being swiped out of Recents. This screen's only job is to request the
  // overlay permission on first launch (needs a real Activity context) and
  // host the prompts on/off toggle — there's no dedicated Settings screen yet,
  // so it lives here rather than building one just for a single switch.

  bool _promptsEnabled = true;

  @override
  void initState() {
    super.initState();
    _requestOverlayPermission();
    _loadPromptsEnabled();
  }

  Future<void> _requestOverlayPermission() async {
    final hasPermission = await FlutterOverlayWindow.isPermissionGranted();
    if (!hasPermission) {
      await FlutterOverlayWindow.requestPermission();
    }
  }

  Future<void> _loadPromptsEnabled() async {
    final enabled = await _shouldPrompt();
    if (mounted) setState(() => _promptsEnabled = enabled);
  }

  Future<void> _togglePrompts(bool value) async {
    setState(() => _promptsEnabled = value);
    await SharedPreferencesAsync().setBool(promptsEnabledKey, value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Why Did I Unlock?',
              style: TextStyle(color: Colors.white, fontSize: 24),
            ),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Unlock prompts',
                  style: TextStyle(color: Colors.white70, fontSize: 16),
                ),
                Switch(
                  value: _promptsEnabled,
                  onChanged: _togglePrompts,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

enum _OverlayMode { capture, bubble }

class OverlayRoot extends StatefulWidget {
  const OverlayRoot({super.key});

  @override
  State<OverlayRoot> createState() => _OverlayRootState();
}

class _OverlayRootState extends State<OverlayRoot> {
  _OverlayMode _mode = _OverlayMode.capture;
  String _intentText = '';
  String _intentSource = '';
  DateTime? _declaredAt;

  Future<void> _submitIntent(String text, String source) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final declaredAt = DateTime.now();
    debugPrint(
      '📝 Intent declared: "$trimmed" (source: $source) at $declaredAt',
    );

    setState(() {
      _intentText = trimmed;
      _intentSource = source;
      _declaredAt = declaredAt;
      _mode = _OverlayMode.bubble;
    });

    // Read density BEFORE the awaits (avoids using context across an async gap).
    // showOverlay() sizes the window in raw device pixels, so convert dp -> px.
    final dpr = MediaQuery.of(context).devicePixelRatio;

    // The capture screen's window is created focusable (needed for the text
    // field's keyboard). Flipping to a non-focusable flag in place via
    // updateFlag()/resizeOverlay() doesn't reliably make Android release
    // focus it already granted, which is what was blocking touches/keyboard/
    // back-gesture in every other app. Closing and reopening a fresh window
    // at bubble size with defaultFlag (non-focusable from birth) avoids that
    // — the Flutter engine and this widget's state survive the recreation.
    await FlutterOverlayWindow.closeOverlay();
    await FlutterOverlayWindow.showOverlay(
      height: (_bubbleHeightDp * dpr).round(),
      width: (_bubbleWidthDp * dpr).round(),
      alignment: OverlayAlignment.center,
      flag: OverlayFlag.defaultFlag,
      overlayTitle: 'Why Did I Unlock?',
      overlayContent: trimmed,
      enableDrag: true,
    );
  }

  /// Honest "no real reason" path — logs the habitual/purposeless unlock
  /// (real signal, see docs/BACKLOG.md) but does NOT transition to bubble
  /// mode: there's no declared task, so a persistent reminder would just be
  /// nagging. State stays in capture mode with nothing set, so the engine is
  /// already clean for the next unlock (no reset needed, unlike _dismissBubble).
  Future<void> _submitNoIntent() async {
    debugPrint('🤷 No intent declared ("$noIntentLabel") at ${DateTime.now()}');
    await FlutterOverlayWindow.closeOverlay();
  }

  Future<void> _dismissBubble() async {
    final dismissedAt = DateTime.now();
    final activeFor = _declaredAt == null ? null : dismissedAt.difference(_declaredAt!);
    debugPrint(
      '✅ Intent dismissed: "$_intentText" (source: $_intentSource) '
      'declared at $_declaredAt, dismissed at $dismissedAt, active for $activeFor',
    );

    await FlutterOverlayWindow.closeOverlay();
    // The plugin caches the overlay's Flutter engine and only detaches the
    // view on closeOverlay() — the engine (and therefore this State's _mode +
    // _intentText) survives. Without this reset, the next unlock reattaches
    // the cached view still in bubble mode showing the old intent; and because
    // that next window opens full-screen for the capture prompt, a stale bubble
    // in a full-screen window swallows every touch and blocks the phone. Reset
    // to a clean capture state so the next unlock shows a fresh prompt.
    if (mounted) {
      setState(() {
        _mode = _OverlayMode.capture;
        _intentText = '';
        _intentSource = '';
        _declaredAt = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (_mode) {
      case _OverlayMode.capture:
        return IntentCaptureScreen(
          onSubmit: _submitIntent,
          onNoIntent: _submitNoIntent,
        );
      case _OverlayMode.bubble:
        return BubbleWidget(intentText: _intentText, onClose: _dismissBubble);
    }
  }
}

class IntentCaptureScreen extends StatefulWidget {
  /// Called with (text, source) where source is 'preset' or 'custom'.
  final void Function(String text, String source) onSubmit;

  /// Called when the user picks the honest "no real reason" option instead.
  final VoidCallback onNoIntent;

  const IntentCaptureScreen({
    super.key,
    required this.onSubmit,
    required this.onNoIntent,
  });

  @override
  State<IntentCaptureScreen> createState() => _IntentCaptureScreenState();
}

class _IntentCaptureScreenState extends State<IntentCaptureScreen> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submitCustomText() => widget.onSubmit(_controller.text, 'custom');

  @override
  Widget build(BuildContext context) {
    // Scaffold (not a bare Material) so resizeToAvoidBottomInset shrinks the
    // available body height when the keyboard opens.
    //
    // Layout is thumb-zone-driven (per one-handed mobile UX research: the
    // bottom/center of the screen is the reachable "easy zone", the top is
    // the "hard zone" for one-handed thumb use — critical, tappable elements
    // belong in the lower two-thirds). The title is read-only, so it stays
    // fixed up top where it's easy to READ. Every TAPPABLE element (presets,
    // "Just Like That", the text field/OK) is pushed down into the reachable
    // zone, ending with the text field glued just above the keyboard.
    //
    // The presets/no-intent group uses the LayoutBuilder + ConstrainedBox
    // (minHeight: full available space) + IntrinsicHeight + mainAxisAlignment
    // .end combo: this is what lets a Column inside a SingleChildScrollView
    // still bottom-align its content when there's slack space (a bare
    // Column inside a scroll view always top-aligns, since the scroll view
    // gives it unbounded height), while still scrolling gracefully — instead
    // of overflowing — if the keyboard squeezes the available space below
    // the content's natural height.
    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: 0.85),
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: constraints.maxHeight),
                        child: IntrinsicHeight(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              const Text(
                                'What are you unlocking for?',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.white, fontSize: 24),
                              ),
                              const SizedBox(height: 32),
                              Wrap(
                                spacing: 12,
                                runSpacing: 12,
                                alignment: WrapAlignment.center,
                                children: [
                                  for (final preset in intentPresets)
                                    _PresetButton(
                                      label: preset,
                                      onTap: () => widget.onSubmit(preset, 'preset'),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 24),
                              // Deliberately styled DIFFERENTLY from the
                              // topic pills above — muted border/italic
                              // text, preceding caption — so it visually
                              // reads as a different kind of answer, "no
                              // real reason", not just another category.
                              // Still logs (see _submitNoIntent); not a
                              // plain Skip.
                              const Text(
                                'or, if there isn\'t one —',
                                style: TextStyle(color: Colors.white38, fontSize: 13),
                              ),
                              const SizedBox(height: 8),
                              _NoIntentButton(onTap: widget.onNoIntent),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      maxLength: intentMaxInputLength,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        hintText: 'Type your intent...',
                        hintStyle: TextStyle(color: Colors.white54),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.white54),
                        ),
                      ),
                      onSubmitted: (_) => _submitCustomText(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _submitCustomText,
                    child: const Text(
                      'OK',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PresetButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _PresetButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: const BorderSide(color: Colors.white54),
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
      child: Text(label),
    );
  }
}

/// "Just Like That" — a real pill so it reads as tappable (Dinesh's feedback
/// on the previous bare italic-underlined TextButton), but styled MUTED
/// relative to [_PresetButton] (dimmer border/text, no fill) so it still
/// visually reads as the "no real reason" option rather than another topic.
class _NoIntentButton extends StatelessWidget {
  final VoidCallback onTap;

  const _NoIntentButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white70,
        side: const BorderSide(color: Colors.white24),
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
      child: const Text(
        noIntentLabel,
        style: TextStyle(fontSize: 14, fontStyle: FontStyle.italic),
      ),
    );
  }
}

class BubbleWidget extends StatelessWidget {
  final String intentText;
  final VoidCallback onClose;

  const BubbleWidget({
    super.key,
    required this.intentText,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    // The bubble fills its (pill-sized) window; a fixed border radius of half
    // the pill height gives a stadium shape without hardcoding a width that
    // could sub-pixel-overflow after the dp->px rounding in _submitIntent.
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.deepPurple,
          borderRadius: BorderRadius.circular(_bubbleHeightDp / 2),
        ),
        padding: const EdgeInsets.only(left: 16, right: 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                intentText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
            GestureDetector(
              onTap: onClose,
              child: Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(
                  color: Colors.black26,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, size: 16, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
