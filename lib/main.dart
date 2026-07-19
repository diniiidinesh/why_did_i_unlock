import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

const List<String> intentPresets = [
  'Check messages',
  'Quick search',
  'Just browsing',
];

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
  // startPosition (0,0): the plugin's default position shifts the window up by
  // the status-bar height; combined with our explicit full height that would
  // leave the bottom short by exactly that amount. Pinning to the origin makes
  // the height reach the true bottom of the display.
  await FlutterOverlayWindow.showOverlay(
    height: screenHeight,
    width: screenWidth,
    alignment: OverlayAlignment.center,
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
  // overlay permission on first launch, which needs a real Activity context.

  @override
  void initState() {
    super.initState();
    _requestOverlayPermission();
  }

  Future<void> _requestOverlayPermission() async {
    final hasPermission = await FlutterOverlayWindow.isPermissionGranted();
    if (!hasPermission) {
      await FlutterOverlayWindow.requestPermission();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: const Center(
        child: Text(
          'Why Did I Unlock?',
          style: TextStyle(color: Colors.white, fontSize: 24),
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
        return IntentCaptureScreen(onSubmit: _submitIntent);
      case _OverlayMode.bubble:
        return BubbleWidget(intentText: _intentText, onClose: _dismissBubble);
    }
  }
}

class IntentCaptureScreen extends StatefulWidget {
  /// Called with (text, source) where source is 'preset' or 'custom'.
  final void Function(String text, String source) onSubmit;

  const IntentCaptureScreen({super.key, required this.onSubmit});

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

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.85),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
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
              const SizedBox(height: 32),
              TextField(
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
                onSubmitted: (value) => widget.onSubmit(value, 'custom'),
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
