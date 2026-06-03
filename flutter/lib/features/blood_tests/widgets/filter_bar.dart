import 'package:flutter/material.dart';

import '../../../app/theme.dart';

const _phaseOptions = [
  ('', 'All phases'),
  ('home-hd', 'Home'),
  ('in-center-hd', 'In-centre'),
  ('admission', 'Admission'),
];

const _rangeOptions = [
  ('3m', '3M'),
  ('6m', '6M'),
  ('1y', '1Y'),
  ('all', 'All'),
];

/// Immutable filter state for the Blood Tests screen.
///
/// [rangePreset] drives the time-window pills (3M / 6M / 1Y / All); when it is
/// anything other than `'all'` or `''`, the effective lower bound is computed via
/// [rangeFrom] in `logic.dart`. The raw [from] / [to] fields are kept so custom
/// backfill ranges still work, but the pill UI only touches [rangePreset].
class FilterState {
  const FilterState({
    this.phases = const ['home-hd'],
    this.rangePreset = '6m',
    this.from = '',
    this.to = '',
    this.marker = '',
  });
  final List<String> phases;
  final String rangePreset; // '3m' | '6m' | '1y' | 'all' | ''
  final String from;
  final String to;
  final String marker;

  FilterState copyWith({
    List<String>? phases,
    String? rangePreset,
    String? from,
    String? to,
    String? marker,
  }) =>
      FilterState(
        phases: phases ?? this.phases,
        rangePreset: rangePreset ?? this.rangePreset,
        from: from ?? this.from,
        to: to ?? this.to,
        marker: marker ?? this.marker,
      );
}

/// Phase + timeframe pills.
///
/// The pills are the primary filter mechanism — every tap calls [onChange] with a
/// new [FilterState].
class FilterBar extends StatelessWidget {
  const FilterBar({
    super.key,
    required this.filter,
    required this.onChange,
  });

  final FilterState filter;
  final ValueChanged<FilterState> onChange;

  @override
  Widget build(BuildContext context) {
    final t = context.hd;
    final activePhase = filter.phases.isEmpty ? '' : filter.phases.first;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: t.panel,
        border: Border(bottom: BorderSide(color: t.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // --- Phase pills ---
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (value, label) in _phaseOptions)
                FilterPill(
                  label: label,
                  active: value == activePhase,
                  onTap: () => onChange(filter.copyWith(
                      phases: value.isEmpty ? const [] : [value])),
                ),
            ],
          ),
          const SizedBox(height: 12),
          // --- Timeframe pills with calendar icon ---
          Row(
            children: [
              Icon(Icons.calendar_today_outlined, size: 16, color: t.textMuted),
              const SizedBox(width: 8),
              ..._rangeOptions.map((opt) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterPill(
                      label: opt.$2,
                      active: filter.rangePreset == opt.$1,
                      onTap: () =>
                          onChange(filter.copyWith(rangePreset: opt.$1)),
                    ),
                  )),
            ],
          ),
        ],
      ),
    );
  }
}

/// A single selectable pill chip.
///
/// Active: cyan border + cyan text + subtle cyan fill.
/// Inactive: muted border + muted text, dark fill.
class FilterPill extends StatelessWidget {
  const FilterPill({super.key, required this.label, required this.active, required this.onTap});
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.hd;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: active ? t.accent.withValues(alpha: 0.12) : t.bg,
          border: Border.all(
            color: active ? t.accent : t.border,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
            color: active ? t.accent : t.textSecondary,
          ),
        ),
      ),
    );
  }
}
