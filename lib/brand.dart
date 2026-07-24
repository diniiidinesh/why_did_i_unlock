/// User-visible Beacon brand strings and public URLs.
///
/// Package / applicationId stay `why_did_i_unlock` /
/// `com.whydidiunlock.why_did_i_unlock` forever — see
/// `docs/erd/beacon-store-rename-2026-07-24.md`.
library;

/// Short on-device name (launcher, Home, About, notification, overlays).
const String appDisplayName = 'Beacon';

/// Play Console title (≤30 chars). Not used as the Android launcher label.
const String playStoreTitle = 'Beacon: Mindful Phone Use';

/// Support / feedback inbox (also Play Console + privacy policy contact).
const String feedbackEmail = 'hi@dineshkaliki.com';

/// Public privacy policy (GitHub Pages + custom domain).
const String privacyPolicyUrl = 'https://dineshkaliki.com/beacon/privacy/';

/// Play Store listing — fill after the Console app exists.
const String playListingUrl =
    'https://TODO_PLAY_LISTING_URL_UNRESOLVED.placeholder.invalid';

/// On-device brand mark — solid navy square (not the checkerboard export).
const String brandMarkAsset = 'assets/icon/icon.png';
