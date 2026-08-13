import 'package:flutter/material.dart';

/// Client-side icon for a bubble / preset label (no DB `icon_key` in v1).
///
/// See `docs/erd/bubble-ux-hybrid-plan-2026-07-24.md` §II.5.
/// Verb defaults: `docs/erd/verb-presets-job-goers-2026-07-25.md`.
IconData iconForIntentLabel(String? label) {
  final key = (label ?? '').trim().toLowerCase();
  return switch (key) {
    // Current defaults (verb seed v4)
    'check mail' => Icons.mail_outline,
    'message someone' => Icons.chat,
    'call someone' => Icons.call,
    'book a cab' => Icons.local_taxi,
    'order food' => Icons.restaurant,
    'pay someone' => Icons.account_balance_wallet,
    // Prior verb seed (v2) + legacy category defaults for history bubbles
    'watch reels' => Icons.play_circle_outline,
    'payments' => Icons.account_balance_wallet,
    'calls' => Icons.call,
    'messages' => Icons.chat,
    'food order' => Icons.restaurant,
    'commute' => Icons.directions_car,
    _ => Icons.flag,
  };
}

/// Labels that use a Material icon rather than a letter avatar.
const Set<String> _knownPresetLabelsLower = {
  'check mail',
  'message someone',
  'call someone',
  'book a cab',
  'order food',
  'pay someone',
  'watch reels',
  'payments',
  'calls',
  'messages',
  'food order',
  'commute',
};

/// Single-letter avatar when [iconForIntentLabel] would be the generic flag
/// and the text is custom (non-preset). Returns null to use the Material icon.
String? letterAvatarForCustomIntent(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return null;
  final lower = trimmed.toLowerCase();
  if (_knownPresetLabelsLower.contains(lower)) return null;
  return String.fromCharCode(trimmed.runes.first).toUpperCase();
}
