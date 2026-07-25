/// Static copy for OEM autostart / battery-optimization guidance, shared
/// between the onboarding flow (T4, step 4) and the Status screen (T6).
///
/// Extracted to its own file rather than duplicated in both screens because
/// the underlying facts (which OEMs are aggressive, and what setting fixes
/// it) are the same regardless of when the user is reading them — onboarding
/// shows this once, proactively; Status lets a user re-check it any time
/// (e.g. after an OEM software update resets the setting, a real recurring
/// complaint on aggressive-OEM Android). See `docs/BACKLOG.md` OEM autostart
/// and `CLAUDE.md` §8/§9 for why this matters: these OEMs are known to block
/// boot auto-restart AND kill the foreground service during normal use,
/// which is the single biggest source of "why did the app just stop working"
/// reports this product is exposed to.
///
/// Field notes (2026-07-25):
/// - OnePlus OxygenOS: App info → Battery usage → "Allow background activity"
///   ON **and** "Optimize battery use" → **Don't optimize** (not "Always ask").
/// - Vivo (screenshots): App info → Battery usage → Background power control →
///   **Allow background power usage** (not Background power smart control).
/// Menu labels drift by firmware — steps stress allow-background + leave smart
/// optimize / smart control.
library;

import 'brand.dart';

/// One OEM's autostart/battery-exemption setting. [steps] is deliberately
/// short, outcome-oriented phrasing rather than a screenshot-by-version
/// walkthrough — OEM menus change between firmware versions, whereas
/// "turn ON allow-background" + "leave Don't optimize / No restrictions"
/// stays useful longer.
class OemGuidance {
  final String vendor;
  final List<String> steps;

  const OemGuidance({required this.vendor, required this.steps});
}

/// Shared framing above the per-OEM list (Status + onboarding). Explains why
/// the standard Android battery-exemption dialog alone is not enough on
/// aggressive skins.
final String oemGuidanceIntro =
    'Two separate things matter on many phones: (1) allow $appDisplayName to '
    'run in the background, and (2) turn off that maker\'s "smart" / auto '
    'battery optimization for this app. Allowing background alone is often '
    'not enough — smart optimize can still silently stop prompts.';

/// Ordered so the OEMs named explicitly in `CLAUDE.md` §8 as most aggressive
/// (Xiaomi/Oppo/Vivo — also the most relevant for the India market, this
/// app's most likely early audience) come first. OnePlus shares ColorOS/
/// OxygenOS battery screens with Oppo/Realme.
///
/// Not `const` — steps interpolate [appDisplayName] from `brand.dart`.
final List<OemGuidance> oemAutostartGuidance = [
  OemGuidance(
    vendor: 'Xiaomi / Redmi / POCO (MIUI, HyperOS)',
    steps: [
      'Long-press $appDisplayName → App info → Autostart → turn ON '
          '(or Settings → Apps → Manage apps → $appDisplayName → Autostart).',
      'Same App info → Battery saver (or Battery) → choose No restrictions '
          '(not Battery saver / Restricted). This turns off smart background limits.',
      'Optional: Settings → Battery & performance → App battery saver → '
          '$appDisplayName → No restrictions.',
    ],
  ),
  OemGuidance(
    vendor: 'OnePlus / Oppo / Realme (OxygenOS, ColorOS)',
    steps: [
      'App info for $appDisplayName → Battery usage → Power consumption controls '
          '(names vary slightly).',
      'Turn ON Allow background activity.',
      'Tap Optimize battery use → choose Don\'t optimize '
          '(not Always ask / Auto-optimize / Smart). Smart optimize can still kill monitoring.',
      'If you see Autostart management (Settings → Apps): turn ON for $appDisplayName.',
    ],
  ),
  OemGuidance(
    vendor: 'Vivo / iQOO (FuntouchOS / OriginOS)',
    steps: [
      // Exact path from 2026-07-25 friend screenshots (OriginOS/Funtouch).
      'App info for $appDisplayName → Battery usage → Background power control.',
      'Choose Allow background power usage — not Background power smart control '
          '(smart control is the default and can silently stop prompts even when '
          '"allow background" looks fine elsewhere).',
      'Also turn ON Autostart if present: Settings → Apps → Autostart '
          '(or i Manager → App manager → Autostart) → $appDisplayName.',
      'Optional: turn OFF Pause app activity if unused on the App info screen '
          '(Unused app settings), so the OS doesn\'t freeze the app after idle days.',
    ],
  ),
  OemGuidance(
    vendor: 'Samsung (One UI)',
    steps: [
      'Settings → Apps → $appDisplayName → Battery → Unrestricted '
          '(not Optimized / Restricted).',
      'Settings → Battery (and device care) → Background usage limits → '
          'confirm $appDisplayName is NOT in Sleeping or Deep sleeping apps; '
          'add it under Never sleeping apps if that list exists.',
    ],
  ),
];

/// Shown when a user's device doesn't match any vendor above, or the vendor
/// list above ever goes stale — a fallback that still points at the right
/// outcomes rather than leaving the user stuck.
final String genericOemFallback =
    'Open App info for $appDisplayName → Battery / Battery usage. '
    'Turn ON anything like "Allow background activity", then open '
    '"Optimize battery use" / "Battery optimization" / "Battery saver" and choose '
    'Don\'t optimize, Not optimized, Unrestricted, or No restrictions — '
    'not Smart, Always ask, or Auto-optimize. '
    'Also look for Autostart and turn it ON if present.';

/// In-app hint before Android's "Display over other apps" list. On Android 11+
/// the system ignores package deep-links and shows every app — we can't
/// highlight our row, so naming [appDisplayName] here is the friction lever.
final String overlayPermissionFindHint =
    'You\'ll see a list of apps — tap $appDisplayName, then turn the switch on.';

/// Matches [android.os.Build.MANUFACTURER] / brand strings (case-insensitive
/// substrings) to a known [OemGuidance] entry. Returns null for Pixel /
/// Nothing / unknown makers — callers show [genericOemFallback].
///
/// Pure / injectable: pass fake strings in unit tests; production callers
/// feed [readDeviceManufacturer].
OemGuidance? matchOemGuidance(String? manufacturerOrBrand) {
  if (manufacturerOrBrand == null) return null;
  final s = manufacturerOrBrand.trim().toLowerCase();
  if (s.isEmpty) return null;

  bool has(String needle) => s.contains(needle);

  // Order matters for overlapping brands (none currently overlap).
  if (has('xiaomi') || has('redmi') || has('poco')) {
    return oemAutostartGuidance[0];
  }
  if (has('oppo') || has('realme') || has('oneplus')) {
    return oemAutostartGuidance[1];
  }
  if (has('vivo') || has('iqoo')) {
    return oemAutostartGuidance[2];
  }
  if (has('samsung')) {
    return oemAutostartGuidance[3];
  }
  return null;
}

/// Puts [matched] first when non-null; otherwise returns the default order.
List<OemGuidance> oemGuidanceListPreferring(OemGuidance? matched) {
  if (matched == null) return List<OemGuidance>.from(oemAutostartGuidance);
  return [
    matched,
    ...oemAutostartGuidance.where((g) => g.vendor != matched.vendor),
  ];
}
