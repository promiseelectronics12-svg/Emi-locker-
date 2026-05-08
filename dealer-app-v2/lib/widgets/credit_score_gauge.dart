import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:dealer_app/app/emi_locker_app.dart';
import 'tier_badge.dart';

class CreditScoreGauge extends StatelessWidget {
  const CreditScoreGauge({super.key, required this.score, required this.tier});

  final int score;
  final String tier;

  @override
  Widget build(BuildContext context) {
    final color = tierColor(tier);
    final fraction = (score / 1000).clamp(0.0, 1.0);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 180,
          height: 100,
          child: Stack(
            alignment: Alignment.bottomCenter,
            children: [
              PieChart(
                PieChartData(
                  startDegreeOffset: 180,
                  sectionsSpace: 0,
                  centerSpaceRadius: 48,
                  sections: [
                    PieChartSectionData(
                      value: fraction * 180,
                      color: color,
                      radius: 18,
                      showTitle: false,
                    ),
                    PieChartSectionData(
                      value: (1 - fraction) * 180,
                      color: AppTone.muted.withValues(alpha: 0.15),
                      radius: 18,
                      showTitle: false,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$score',
                      style: const TextStyle(
                        fontFamily: 'JetBrainsMono',
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        color: AppTone.ink,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    TierBadge(tier: tier),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
