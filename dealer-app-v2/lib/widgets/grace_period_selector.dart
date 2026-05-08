import 'package:flutter/material.dart';
import 'package:dealer_app/app/emi_locker_app.dart';

class GracePeriodSelector extends StatelessWidget {
  const GracePeriodSelector({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final int selected;
  final ValueChanged<int> onChanged;

  static const _options = [2, 4, 8, 24];

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Grace period', style: tt.labelMedium?.copyWith(color: AppTone.muted)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: _options.map((hours) {
            final isSelected = selected == hours;
            return ChoiceChip(
              label: Text(hours == 24 ? '24 h' : '$hours h'),
              selected: isSelected,
              selectedColor: AppTone.brand,
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : AppTone.ink,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
              onSelected: (_) => onChanged(hours),
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
        Text(
          'Device unlocks for ${selected}h then auto-relocks.',
          style: tt.bodySmall?.copyWith(color: AppTone.muted),
        ),
      ],
    );
  }
}
