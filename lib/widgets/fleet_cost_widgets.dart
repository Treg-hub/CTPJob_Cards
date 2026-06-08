import 'package:flutter/material.dart';

import '../models/fleet_cost_line.dart';
import '../theme/app_theme.dart';

String costCategoryHint(FleetCostCategory category) {
  switch (category) {
    case FleetCostCategory.parts:
      return 'Parts or materials bought for this forklift.';
    case FleetCostCategory.labour:
      return 'External labour, contractor, or workshop invoice.';
    case FleetCostCategory.invoice:
      return 'Full supplier invoice (may cover several line items).';
    case FleetCostCategory.other:
      return 'Other spend — delivery, consumables, etc.';
  }
}

/// Shown at the top of the Costs tab — job queue for entering spend.
class FleetCostJobsGuideBanner extends StatelessWidget {
  const FleetCostJobsGuideBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kBrandOrange.withValues(alpha: 0.08),
        border: Border.all(color: kBrandOrange.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.receipt_long_outlined, color: kBrandOrange, size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Last 50 mechanic jobs below. Orange = needs costing — tap to enter '
              'spend. Green = already has costs (tap to view or add more). '
              'Use General cost for spend not tied to a job.',
              style: TextStyle(fontSize: 13, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

class FleetCostStatusBadge extends StatelessWidget {
  const FleetCostStatusBadge({super.key, required this.hasCostLines});

  final bool hasCostLines;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: hasCostLines ? Colors.green : kBrandOrange,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        hasCostLines ? 'Costed' : 'Needs costing',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class FleetReportsGuideBanner extends StatelessWidget {
  const FleetReportsGuideBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kBrandOrange.withValues(alpha: 0.08),
        border: Border.all(color: kBrandOrange.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.bar_chart_outlined, color: kBrandOrange, size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Review spend by month or year-to-date. Export CSV to share with '
              'accounts or for your own records.',
              style: TextStyle(fontSize: 13, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

class FleetCostGuideBanner extends StatelessWidget {
  const FleetCostGuideBanner({
    super.key,
    this.linkedToJob = false,
  });

  final bool linkedToJob;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kBrandOrange.withValues(alpha: 0.08),
        border: Border.all(color: kBrandOrange.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.attach_money, color: kBrandOrange, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              linkedToJob
                  ? 'Enter what was spent on this mechanic job. '
                      'Amounts are only visible to cost managers — not mechanics.'
                  : 'Record spend against a forklift. Link to a mechanic job when '
                      'the cost relates to work they logged.',
              style: const TextStyle(fontSize: 13, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

class FleetCostCategoryHint extends StatelessWidget {
  const FleetCostCategoryHint({super.key, required this.category});

  final FleetCostCategory category;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kBrandOrange.withValues(alpha: 0.06),
        border: Border.all(color: kBrandOrange.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: kBrandOrange, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              costCategoryHint(category),
              style: const TextStyle(fontSize: 12, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}