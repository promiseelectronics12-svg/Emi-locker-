import 'package:flutter/material.dart';
import 'package:dealer_app/app/emi_locker_app.dart';

Color tierColor(String tier) {
  switch (tier.toUpperCase()) {
    case 'GOLD':        return const Color(0xFFD97706);
    case 'SILVER':      return AppTone.muted;
    case 'BRONZE':      return const Color(0xFF92400E);
    case 'RED':         return AppTone.danger;
    case 'BLACKLISTED': return AppTone.ink;
    default:            return AppTone.muted;
  }
}

class TierBadge extends StatelessWidget {
  const TierBadge({super.key, required this.tier});

  final String tier;

  @override
  Widget build(BuildContext context) {
    final isBlacklisted = tier.toUpperCase() == 'BLACKLISTED';
    final bg = tierColor(tier);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg.withValues(alpha: isBlacklisted ? 1.0 : 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: bg.withValues(alpha: 0.4)),
      ),
      child: Text(
        tier.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: isBlacklisted ? Colors.white : bg,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}
