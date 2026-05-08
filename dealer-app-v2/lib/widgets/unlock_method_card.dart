import 'package:flutter/material.dart';
import 'package:dealer_app/app/emi_locker_app.dart';

enum UnlockMethod { online, offline }

class UnlockMethodCard extends StatelessWidget {
  const UnlockMethodCard({
    super.key,
    required this.method,
    required this.selected,
    required this.onTap,
  });

  final UnlockMethod method;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isOnline = method == UnlockMethod.online;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected ? AppTone.brand.withValues(alpha: 0.07) : Colors.transparent,
          border: Border.all(
            color: selected ? AppTone.brand : AppTone.muted.withValues(alpha: 0.3),
            width: selected ? 1.6 : 1.0,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: (selected ? AppTone.brand : AppTone.muted).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                isOnline ? Icons.wifi_rounded : Icons.sms_outlined,
                color: selected ? AppTone.brand : AppTone.muted,
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isOnline ? 'Online unlock' : 'Offline unlock (OTP)',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: selected ? AppTone.brand : AppTone.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isOnline
                        ? 'Device unlocks within 60 seconds over the internet.'
                        : 'You SMS a one-time code to the customer\'s phone.',
                    style: const TextStyle(fontSize: 12, color: AppTone.muted),
                  ),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle_rounded, color: AppTone.brand, size: 20),
          ],
        ),
      ),
    );
  }
}
