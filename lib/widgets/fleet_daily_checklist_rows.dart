import 'package:flutter/material.dart';

import '../models/fleet_daily_check.dart';
import '../theme/app_theme.dart';

/// Checkbox rows for the daily pre-use safety checklist.
/// Checked = verified safe; unchecked items are flagged at submit.
class FleetDailyChecklistRows extends StatelessWidget {
  const FleetDailyChecklistRows({
    super.key,
    required this.items,
    required this.onToggle,
    this.readOnly = false,
  });

  final List<FleetDailyCheckItem> items;
  final void Function(int index, bool checked) onToggle;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).appColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: List.generate(items.length, (index) {
        final item = items[index];
        final checked = item.isOk && item.reviewed;
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Material(
            color: colors.cardSurface,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: readOnly ? null : () => onToggle(index, !checked),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Checkbox(
                      value: checked,
                      onChanged: readOnly
                          ? null
                          : (v) => onToggle(index, v ?? false),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        '${item.id}. ${item.label}',
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 13,
                          color: readOnly && !checked
                              ? colors.textMuted
                              : null,
                          decoration: readOnly && !checked
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}