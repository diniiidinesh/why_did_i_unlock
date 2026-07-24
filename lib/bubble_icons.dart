import 'package:flutter/material.dart';

/// Client-side icon for a bubble / preset label (no DB `icon_key` in v1).
///
/// See `docs/erd/bubble-ux-hybrid-plan-2026-07-24.md` §II.5.
IconData iconForIntentLabel(String? label) {
  final key = (label ?? '').trim().toLowerCase();
  return switch (key) {
    'payments' => Icons.account_balance_wallet,
    'calls' => Icons.call,
    'messages' => Icons.chat,
    'food order' => Icons.restaurant,
    'commute' => Icons.directions_car,
    _ => Icons.flag,
  };
}

/// Single-letter avatar when [iconForIntentLabel] would be the generic flag
/// and the text is custom (non-preset). Returns null to use the Material icon.
String? letterAvatarForCustomIntent(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return null;
  final lower = trimmed.toLowerCase();
  const presets = {'payments', 'calls', 'messages', 'food order', 'commute'};
  if (presets.contains(lower)) return null;
  return String.fromCharCode(trimmed.runes.first).toUpperCase();
}
