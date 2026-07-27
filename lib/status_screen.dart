import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:permission_handler/permission_handler.dart';

import 'device_manufacturer.dart';
import 'main.dart' show triggerCapturePromptManually;
import 'oem_autostart_copy.dart';

/// Signature matching [triggerCapturePromptManually] — injected so widget
/// tests can assert the button was invoked with the right pixel size
/// without going through `IsolateNameServer`, which has no real platform
/// implementation in a widget test. See `docs/ARCHITECTURE.md` §3 for the
/// full "why route through the background isolate" story.
typedef ManualPromptTrigger = void Function({required int screenWidth, required int screenHeight});

/// Default battery-exemption check/request, factored to top-level functions
/// (not inline closures) specifically so `StatusScreen`'s constructor can
/// stay `const` — an inline lambda default isn't a valid compile-time
/// constant even when it captures nothing, only a bare tear-off is.
Future<bool> _defaultCheckBatteryExemption() => Permission.ignoreBatteryOptimizations.isGranted;

Future<void> _defaultRequestBatteryExemption() async {
  await Permission.ignoreBatteryOptimizations.request();
}

/// "Is it working?" screen: overlay permission state (with a re-request
/// action), OEM autostart/battery guidance, an honest note on notification
/// visibility, and the "show me the prompt now" button so a tester can
/// verify the capture screen without waiting for a real unlock.
///
/// All three plugin-touching dependencies — permission check, permission
/// request, and the manual-prompt trigger — are injectable constructor
/// params defaulting to the real calls, the same shape `HistoryScreen` uses
/// for `IntentStore`. That's what lets this screen have a widget test at
/// all: none of `FlutterOverlayWindow`'s methods have a real platform
/// implementation under `flutter_test`.
class StatusScreen extends StatefulWidget {
  final Future<bool> Function() checkPermission;
  final Future<bool?> Function() requestPermission;
  final ManualPromptTrigger onShowPromptNow;

  /// Battery-optimization-exemption check/request — the STANDARD Android
  /// dialog (`Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` under
  /// `permission_handler`), not the OEM-specific Autostart Manager screens
  /// below (those have no public API and stay instructions-only). Injectable
  /// for the same testability reason as [checkPermission]/[requestPermission]
  /// — no real platform implementation under `flutter_test`.
  final Future<bool> Function() checkBatteryExemption;
  final Future<void> Function() requestBatteryExemption;

  /// Manufacturer / brand string for OEM tile highlight. Defaults to
  /// [readDeviceManufacturer]; inject in tests (e.g. `() async => 'vivo'`).
  final Future<String?> Function() readManufacturer;

  const StatusScreen({
    super.key,
    Future<bool> Function()? checkPermission,
    Future<bool?> Function()? requestPermission,
    ManualPromptTrigger? onShowPromptNow,
    Future<bool> Function()? checkBatteryExemption,
    Future<void> Function()? requestBatteryExemption,
    Future<String?> Function()? readManufacturer,
  })  : checkPermission = checkPermission ?? FlutterOverlayWindow.isPermissionGranted,
        requestPermission = requestPermission ?? FlutterOverlayWindow.requestPermission,
        onShowPromptNow = onShowPromptNow ?? triggerCapturePromptManually,
        checkBatteryExemption = checkBatteryExemption ?? _defaultCheckBatteryExemption,
        requestBatteryExemption = requestBatteryExemption ?? _defaultRequestBatteryExemption,
        readManufacturer = readManufacturer ?? readDeviceManufacturer;

  @override
  State<StatusScreen> createState() => _StatusScreenState();
}

class _StatusScreenState extends State<StatusScreen> {
  /// Null while the first check is in flight. Kept distinct from
  /// true/false so the UI can show a neutral "checking…" state instead of
  /// flashing a wrong answer before the real one arrives.
  bool? _permissionGranted;

  /// Same null-while-checking convention as [_permissionGranted].
  bool? _batteryExempt;

  OemGuidance? _matchedOem;

  @override
  void initState() {
    super.initState();
    _refreshPermission();
    _refreshBatteryExemption();
    _loadManufacturer();
  }

  Future<void> _loadManufacturer() async {
    final raw = await widget.readManufacturer();
    if (!mounted) return;
    setState(() => _matchedOem = matchOemGuidance(raw));
  }

  Future<void> _refreshPermission() async {
    final granted = await widget.checkPermission();
    if (mounted) setState(() => _permissionGranted = granted);
  }

  Future<void> _requestPermission() async {
    await widget.requestPermission();
    // requestPermission() opens the system "Display over other apps"
    // settings page and returns immediately — often before the user has
    // actually flipped the switch and come back. Re-checking here mostly
    // catches the case where it was already granted (a no-op grant), while
    // the explicit "Refresh status" action below covers the real
    // grant-then-return flow.
    await _refreshPermission();
  }

  Future<void> _refreshBatteryExemption() async {
    final exempt = await widget.checkBatteryExemption();
    if (mounted) setState(() => _batteryExempt = exempt);
  }

  Future<void> _requestBatteryExemption() async {
    await widget.requestBatteryExemption();
    // Same reasoning as _requestPermission: the system dialog returns before
    // the user has necessarily answered it, so this mostly catches the
    // already-granted no-op case; the real answer needs a re-check anyway.
    await _refreshBatteryExemption();
  }

  void _showPromptNow() {
    final mq = MediaQuery.of(context);
    final truePixels = mq.size * mq.devicePixelRatio;
    widget.onShowPromptNow(
      screenWidth: truePixels.width.round(),
      screenHeight: truePixels.height.round(),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Requested — watch for the capture screen.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final oemList = oemGuidanceListPreferring(_matchedOem);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Status & troubleshooting'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _PermissionCard(
            granted: _permissionGranted,
            onGrant: _requestPermission,
            onRefresh: _refreshPermission,
          ),
          const SizedBox(height: 24),
          const _SectionHeader('Battery & autostart'),
          const SizedBox(height: 8),
          Text(
            oemGuidanceIntro,
            style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.35),
          ),
          const SizedBox(height: 12),
          _BatteryExemptionCard(
            exempt: _batteryExempt,
            onRequest: _requestBatteryExemption,
            onRefresh: _refreshBatteryExemption,
          ),
          const SizedBox(height: 8),
          const Text(
            'Then follow your phone maker\'s steps below — especially "Don\'t optimize" / '
            '"No restrictions" / "Not optimized".',
            style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.35),
          ),
          const SizedBox(height: 12),
          ...oemList.map(
            (g) => _OemTile(
              guidance: g,
              highlighted: _matchedOem != null && g.vendor == _matchedOem!.vendor,
            ),
          ),
          const _GenericOemFallbackTile(),
          const SizedBox(height: 24),
          const _SectionHeader('Notifications'),
          const SizedBox(height: 8),
          const Text(
            // Honest, not a fabricated "granted" check — the manifest does
            // not request POST_NOTIFICATIONS yet (CLAUDE.md §2), so there is
            // nothing real to report here beyond this note.
            'This app doesn\'t use notifications yet — the small ongoing '
            'notification you may see is required by Android to keep the '
            'background monitoring service alive, not a feature notification.',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 24),
          const _SectionHeader('Test it now'),
          const SizedBox(height: 8),
          const Text(
            'Shows the capture screen immediately, bypassing the usual '
            'cooldown/probability/quiet-hours checks — useful for verifying '
            'the prompt works without waiting for a real unlock. It still '
            'needs overlay permission and won\'t double-fire over a real '
            'prompt.',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _showPromptNow,
            child: const Text('Show me the prompt now'),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) =>
      Text(text, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600));
}

class _PermissionCard extends StatelessWidget {
  final bool? granted;
  final VoidCallback onGrant;
  final VoidCallback onRefresh;

  const _PermissionCard({required this.granted, required this.onGrant, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final String statusText;
    final Color statusColor;
    if (granted == null) {
      statusText = 'Checking…';
      statusColor = Colors.white54;
    } else if (granted == true) {
      statusText = 'Granted';
      statusColor = Colors.greenAccent;
    } else {
      statusText = 'Not granted';
      statusColor = Colors.redAccent;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Overlay permission', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(statusText, style: TextStyle(color: statusColor, fontSize: 14)),
          const SizedBox(height: 8),
          Text(overlayPermissionFindHint, style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.35)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              if (granted != true)
                ElevatedButton(onPressed: onGrant, child: const Text('Grant permission')),
              OutlinedButton(onPressed: onRefresh, child: const Text('Refresh status')),
            ],
          ),
        ],
      ),
    );
  }
}

/// The STANDARD Android battery-optimization-exemption dialog — a single
/// system-provided prompt that works identically on every OEM, unlike the
/// manufacturer-specific Autostart Manager screens below (no public API,
/// stay instructions-only). Mirrors [_PermissionCard]'s shape/states.
class _BatteryExemptionCard extends StatelessWidget {
  final bool? exempt;
  final VoidCallback onRequest;
  final VoidCallback onRefresh;

  const _BatteryExemptionCard({required this.exempt, required this.onRequest, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final String statusText;
    final Color statusColor;
    if (exempt == null) {
      statusText = 'Checking…';
      statusColor = Colors.white54;
    } else if (exempt == true) {
      statusText = 'Exempt — background restrictions won\'t apply';
      statusColor = Colors.greenAccent;
    } else {
      statusText = 'Not exempt';
      statusColor = Colors.redAccent;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Battery optimization', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(statusText, style: TextStyle(color: statusColor, fontSize: 14)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              if (exempt != true)
                ElevatedButton(onPressed: onRequest, child: const Text('Disable battery optimization')),
              OutlinedButton(onPressed: onRefresh, child: const Text('Refresh status')),
            ],
          ),
        ],
      ),
    );
  }
}

class _OemTile extends StatelessWidget {
  final OemGuidance guidance;
  final bool highlighted;

  const _OemTile({required this.guidance, this.highlighted = false});

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      key: ValueKey('oem-${guidance.vendor}-$highlighted'),
      initiallyExpanded: highlighted,
      iconColor: Colors.white70,
      collapsedIconColor: Colors.white70,
      title: Text(guidance.vendor, style: const TextStyle(color: Colors.white, fontSize: 14)),
      subtitle: highlighted
          ? const Text('Looks like your phone', style: TextStyle(color: Colors.white54, fontSize: 12))
          : null,
      children: guidance.steps
          .map((step) => Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text('• $step', style: const TextStyle(color: Colors.white70, fontSize: 13)),
              ))
          .toList(),
    );
  }
}

class _GenericOemFallbackTile extends StatelessWidget {
  const _GenericOemFallbackTile();

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      iconColor: Colors.white70,
      collapsedIconColor: Colors.white70,
      title: const Text('My phone isn\'t listed', style: TextStyle(color: Colors.white, fontSize: 14)),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Text(genericOemFallback, style: const TextStyle(color: Colors.white70, fontSize: 13)),
        ),
      ],
    );
  }
}
