/// Static copy for OEM autostart / battery-optimization guidance, shared
/// between the onboarding flow (T4, step 4) and the Status screen (T6).
///
/// Extracted to its own file rather than duplicated in both screens because
/// the underlying facts (which OEMs are aggressive, and what setting fixes
/// it) are the same regardless of when the user is reading them — onboarding
/// shows this once, proactively; Status lets a user re-check it any time
/// (e.g. after an OEM software update resets the setting, a real recurring
/// complaint on aggressive-OEM Android). See `docs/BACKLOG.md` `[P1] OEM
/// autostart onboarding` and `CLAUDE.md` §8/§9 for why this matters: these
/// OEMs are known to block boot auto-restart AND kill the foreground service
/// during normal use, which is the single biggest source of "why did the app
/// just stop working" reports this product is exposed to.
library;

/// One OEM's autostart/battery-exemption setting. [steps] is deliberately
/// short, generic phrasing ("Settings app name → menu path") rather than a
/// screenshot-by-version walkthrough — OEM settings menus change between
/// firmware versions often enough that a precise recipe would go stale
/// faster than this file gets revisited, whereas "look for a setting named
/// roughly this, in roughly this place" stays useful longer.
class OemGuidance {
  final String vendor;
  final List<String> steps;

  const OemGuidance({required this.vendor, required this.steps});
}

/// Ordered so the OEMs named explicitly in `CLAUDE.md` §8 as most aggressive
/// (Xiaomi/Oppo/Vivo — also the most relevant for the India market, this
/// app's most likely early audience) come first.
const List<OemGuidance> oemAutostartGuidance = [
  OemGuidance(
    vendor: 'Xiaomi / Redmi / POCO (MIUI, HyperOS)',
    steps: [
      'Settings → Apps → Manage apps → Why Did I Unlock → Autostart → turn ON',
      'Settings → Battery & performance → App battery saver → Why Did I Unlock → No restrictions',
    ],
  ),
  OemGuidance(
    vendor: 'Oppo / Realme / OnePlus (ColorOS)',
    steps: [
      'Settings → Battery → App battery management → Why Did I Unlock → Allow background activity',
      'Settings → Apps → Autostart management → turn ON for Why Did I Unlock',
    ],
  ),
  OemGuidance(
    vendor: 'Vivo (FuntouchOS / OriginOS)',
    steps: [
      'Settings → Battery → Background power consumption management → Why Did I Unlock → Allow',
      'i Manager → App manager → Autostart manager → turn ON for Why Did I Unlock',
    ],
  ),
  OemGuidance(
    vendor: 'Samsung',
    steps: [
      'Settings → Apps → Why Did I Unlock → Battery → Unrestricted',
      'Device care → Battery → Background usage limits → make sure the app is NOT in "Put unused apps to sleep"',
    ],
  ),
];

/// Shown when a user's device doesn't match any vendor above, or the vendor
/// list above ever goes stale — a fallback that still points at the right
/// underlying Android setting name rather than leaving the user stuck.
const String genericOemFallback =
    'Look in your phone\'s Settings app for "Battery optimization", "Background '
    'app management", or "Autostart", and make sure Why Did I Unlock is allowed to '
    'run in the background / is excluded from battery optimization. The exact menu '
    'wording varies by phone maker.';
