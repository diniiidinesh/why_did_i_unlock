import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

void main() {
  runApp(const MyApp());
}

@pragma("vm:entry-point")
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      color: Colors.transparent,
      home: BubbleWidget(),
    ),
  );
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

  static const platform = MethodChannel('com.whydidiunlock/unlock');

  @override
  void initState() {
    super.initState();
    _requestOverlayPermission();
    _listenForUnlock();
  }

  Future<void> _requestOverlayPermission() async {
    final hasPermission = await FlutterOverlayWindow.isPermissionGranted();
    if (!hasPermission) {
      await FlutterOverlayWindow.requestPermission();
    }
  }

  void _listenForUnlock() {
    platform.setMethodCallHandler((call) async {
      if (call.method == 'onUnlock') {
        debugPrint('🔓 UNLOCK EVENT RECEIVED');
        _showBubble();
      }
    });
  }

  Future<void> _showBubble() async {
    final hasPermission = await FlutterOverlayWindow.isPermissionGranted();
    debugPrint('📋 Has overlay permission: $hasPermission');
    if (hasPermission) {
      await FlutterOverlayWindow.showOverlay(
        enableDrag: true,
        height: 200,
        width: 200,
        alignment: OverlayAlignment.center,
        flag: OverlayFlag.defaultFlag,
        overlayTitle: 'Why Did I Unlock?',
        overlayContent: 'Tap to log your reason',
      );
      debugPrint('🟣 showOverlay called');
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

class BubbleWidget extends StatelessWidget {
  const BubbleWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Center(
        child: Container(
          width: 100,
          height: 100,
          decoration: const BoxDecoration(
            color: Colors.deepPurple,
            shape: BoxShape.circle,
          ),
          child: const Center(
            child: Text(
              '🔒',
              style: TextStyle(fontSize: 32),
            ),
          ),
        ),
      ),
    );
  }
}