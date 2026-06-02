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
      year.isEmpty ? '' : (month.isEmpty ? '' : '$year-$month');

  @override
  Widget build(BuildContext context) {
    final t = context.hd;
    final fromYear = filter.from.length >= 4 ? filter.from.substring(0, 4) : '';
    final fromMonth = filter.from.length >= 7 ? filter.from.substring(5, 7) : '';
    final toYear = filter.to.length >= 4 ? filter.to.substring(0, 4) : '';
    final toMonth = filter.to.length >= 7 ? filter.to.substring(5, 7) : '';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.panel,
        border: Border(bottom: BorderSide(color: t.border)),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.end,
        children: [
          _labeled(t, 'Phase', _dropdown<String>(
            t,
            value: filter.phases.isEmpty ? 'all' : filter.phases.first,
            items: [
              const DropdownMenuItem(value: 'all', child: Text('All phases')),
              ..._phases.map((p) => DropdownMenuItem(value: p, child: Text(p))),
            ],
            onChanged: (v) => onChange(filter.copyWith(
                phases: (v == null || v == 'all') ? const [] : [v])),
          )),
          _labeled(t, 'From', Row(mainAxisSize: MainAxisSize.min, children: [
            _monthDropdown(t, fromMonth,
                (m) => onChange(filter.copyWith(from: _bound(fromYear, m)))),
            const SizedBox(width: 4),
            _yearDropdown(t, fromYear,
                (y) => onChange(filter.copyWith(from: _bound(y, fromMonth)))),
          ])),
          _labeled(t, 'To', Row(mainAxisSize: MainAxisSize.min, children: [
            _monthDropdown(t, toMonth,
                (m) => onChange(filter.copyWith(to: _bound(toYear, m)))),
            const SizedBox(width: 4),
            _yearDropdown(t, toYear,
                (y) => onChange(filter.copyWith(to: _bound(y, toMonth)))),
          ])),
          _labeled(t, 'Marker', _dropdown<String>(
            t,
            value: markers.contains(filter.marker) ? filter.marker : null,
            items: markers
                .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                .toList(),
            onChanged: (v) => v == null ? null : onChange(filter.copyWith(marker: v)),
          )),
        ],
      ),
    );
  }

  Widget _labeled(HdTokens t, String label, Widget child) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: t.textMuted)),
          const SizedBox(height: 2),
          child,
        ],
      );

  Widget _dropdown<T>(HdTokens t,
          {required T? value,
          required List<DropdownMenuItem<T>> items,
          required ValueChanged<T?> onChanged}) =>
      DropdownButton<T>(
        value: value,
        items: items,
        onChanged: onChanged,
        isDense: true,
        dropdownColor: t.panel,
        style: TextStyle(fontSize: 13, color: t.textPrimary),
        underline: const SizedBox.shrink(),
      );

  Widget _monthDropdown(HdTokens t, String month, ValueChanged<String> onChanged) =>
      _dropdown<String>(
        t,
        value: month.isEmpty ? '' : month,
        items: [
          const DropdownMenuItem(value: '', child: Text('Month')),
          ..._months.map((m) =>
              DropdownMenuItem(value: m.$1, child: Text(m.$2))),
        ],
        onChanged: (v) => onChanged(v ?? ''),
      );

  Widget _yearDropdown(HdTokens t, String year, ValueChanged<String> onChanged) =>
      _dropdown<String>(
        t,
        value: year.isEmpty ? '' : year,
        items: [
          const DropdownMenuItem(value: '', child: Text('Year')),
          ...years.map((y) =>
              DropdownMenuItem(value: '$y', child: Text('$y'))),
        ],
        onChanged: (v) => onChanged(v ?? ''),
      );
}
