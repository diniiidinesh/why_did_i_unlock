import 'package:flutter/material.dart';

import 'beacon_theme.dart';

/// Amber stadium pill used on the unlock capture screen.
///
/// Extracted so the onboarding walkthrough can render the same widget rather
/// than a look-alike (`docs/erd/onboarding-revamp-2026-08-15.md` §2.1 / §4B).
class PresetPill extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool selected;

  const PresetPill({
    super.key,
    required this.label,
    required this.onTap,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: selected ? BeaconColors.onAmber : Colors.white,
        backgroundColor: selected ? BeaconColors.amber : Colors.transparent,
        side: const BorderSide(color: BeaconColors.amber, width: 1.25),
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
      child: Text(label),
    );
  }
}
