import 'package:flutter/material.dart';

import '../../../app/theme.dart';

const _phases = ['admission', 'in-center-hd', 'home-hd'];
const _months = [
  ('01', 'Jan'), ('02', 'Feb'), ('03', 'Mar'), ('04', 'Apr'),
  ('05', 'May'), ('06', 'Jun'), ('07', 'Jul'), ('08', 'Aug'),
  ('09', 'Sep'), ('10', 'Oct'), ('11', 'Nov'), ('12', 'Dec'),
];

class FilterState {
  const FilterState({
    this.phases = const ['home-hd'],
    this.from = '',
    this.to = '',
    this.marker = '',
  });
  final List<String> phases;
  final String from; // 'YYYY-MM' or ''
  final String to;
  final String marker;

  FilterState copyWith(
          {List<String>? phases, String? from, String? to, String? marker}) =>
      FilterState(
        phases: phases ?? this.phases,
        from: from ?? this.from,
        to: to ?? this.to,
        marker: marker ?? this.marker,
      );
}

class FilterBar extends StatelessWidget {
  const FilterBar({
    super.key,
    required this.filter,
    required this.markers,
    required this.years,
    required this.onChange,
  });

  final FilterState filter;
  final List<String> markers;
  final List<int> years;
  final ValueChanged<FilterState> onChange;

  String _bound(String year, String month) =>
      year.isEmpty || month.isEmpty ? '' : '$year-$month';

  @override
  Widget build(BuildContext context) {
    final t = context.hd;
    final fromYear = filter.from.length >= 4 ? filter.from.substring(0, 4) : '';
    final fromMonth = filter.from.length >= 7 ? filter.from.substring(5, 7) : '';
    final toYear = filter.to.length >= 4 ? filter.to.substring(0, 4) : '';
    final toMonth = filter.to.length >= 7 ? filter.to.substring(5, 7) : '';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: t.panel,
        border: Border(bottom: BorderSide(color: t.border)),
      ),
      child: Column(
        children: [
          _row(t, 'Phase', _field(t, _dropdown<String>(
            t,
            value: filter.phases.isEmpty ? 'all' : filter.phases.first,
            items: [
              const DropdownMenuItem(value: 'all', child: Text('All phases')),
              ..._phases.map((p) => DropdownMenuItem(value: p, child: Text(p))),
            ],
            onChanged: (v) => onChange(filter.copyWith(
                phases: (v == null || v == 'all') ? const [] : [v])),
          ))),
          const SizedBox(height: 8),
          _row(t, 'From', _monthYear(t, fromMonth, fromYear,
              (m) => onChange(filter.copyWith(from: _bound(fromYear, m))),
              (y) => onChange(filter.copyWith(from: _bound(y, fromMonth))))),
          const SizedBox(height: 8),
          _row(t, 'To', _monthYear(t, toMonth, toYear,
              (m) => onChange(filter.copyWith(to: _bound(toYear, m))),
              (y) => onChange(filter.copyWith(to: _bound(y, toMonth))))),
          const SizedBox(height: 8),
          _row(t, 'Marker', _field(t, _dropdown<String>(
            t,
            value: markers.contains(filter.marker) ? filter.marker : null,
            items: markers
                .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                .toList(),
            onChanged: (v) => v == null ? null : onChange(filter.copyWith(marker: v)),
          ))),
        ],
      ),
    );
  }

  /// A label fixed on the left, the control filling the rest — keeps every row's
  /// controls left-aligned to the same column.
  Widget _row(HdTokens t, String label, Widget control) => Row(
        children: [
          SizedBox(
            width: 52,
            child: Text(label,
                style: TextStyle(fontSize: 12, color: t.textMuted)),
          ),
          Expanded(child: control),
        ],
      );

  Widget _monthYear(HdTokens t, String month, String year,
          ValueChanged<String> onMonth, ValueChanged<String> onYear) =>
      Row(children: [
        Expanded(
          child: _field(t, _dropdown<String>(
            t,
            value: month.isEmpty ? '' : month,
            items: [
              const DropdownMenuItem(value: '', child: Text('Month')),
              ..._months.map((m) =>
                  DropdownMenuItem(value: m.$1, child: Text(m.$2))),
            ],
            onChanged: (v) => onMonth(v ?? ''),
          )),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _field(t, _dropdown<String>(
            t,
            value: year.isEmpty ? '' : year,
            items: [
              const DropdownMenuItem(value: '', child: Text('Year')),
              ...years.map((y) => DropdownMenuItem(value: '$y', child: Text('$y'))),
            ],
            onChanged: (v) => onYear(v ?? ''),
          )),
        ),
      ]);

  /// Boxed container so each dropdown has a consistent height/outline.
  Widget _field(HdTokens t, Widget child) => Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: t.bg,
          border: Border.all(color: t.border),
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.centerLeft,
        child: child,
      );

  Widget _dropdown<T>(HdTokens t,
          {required T? value,
          required List<DropdownMenuItem<T>> items,
          required ValueChanged<T?> onChanged}) =>
      DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          items: items,
          onChanged: onChanged,
          isDense: true,
          isExpanded: true,
          dropdownColor: t.panel,
          iconEnabledColor: t.textMuted,
          style: TextStyle(fontSize: 14, color: t.textPrimary),
        ),
      );
}
