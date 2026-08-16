/// All feature-discovery nudge tuning. Kept together deliberately so the
/// cadence can be retuned in one edit after closed-test feedback
/// (`docs/erd/onboarding-revamp-2026-08-15.md` §4C.4).
///
/// Compile-time constants, not user-facing settings — a threshold for "how
/// often we nudge you about Settings" is not a control a user would set.
class NudgeTuning {
  static const int maxTooltipShows = 3;
  static const int nudgeBannerLaunchThreshold = 5;
  static const bool fallbackBannerEnabled = true;
}

/// One-session gate so a just-finished onboarding does not immediately
/// point at Home chrome (`§4C.2` "let the user land on Home once").
class DiscoverySession {
  static bool skipThisLaunch = false;
}
