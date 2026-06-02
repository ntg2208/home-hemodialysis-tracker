import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../treatment/providers.dart' show inventoryApiProvider;
import 'constants.dart';
import 'inventory_models.dart';
import 'stock_calc.dart';

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
];
String _fmt(String? dateStr) {
  if (dateStr == null) return '';
  final d = DateTime.tryParse(dateStr);
  return d == null ? dateStr : '${d.day} ${_months[d.month - 1]}';
}

String _iso(DateTime d) => d.toIso8601String().substring(0, 10);

Widget _grab(HdTokens t) => Center(
      child: Container(
        width: 40,
        height: 4,
        margin: const EdgeInsets.only(bottom: 12),
        decoration:
            BoxDecoration(color: t.textMuted, borderRadius: BorderRadius.circular(2)),
      ),
    );

// ============================ Log event ============================

class LogEventSheet extends ConsumerStatefulWidget {
  const LogEventSheet({super.key, required this.data, required this.onDone});
  final InventoryResponse data;
  final VoidCallback onDone;
  @override
  ConsumerState<LogEventSheet> createState() => _LogEventSheetState();
}

class _LogEventSheetState extends ConsumerState<LogEventSheet> {
  final _adjust = <String, int>{}; // manual deltas
  final _count = <String, int>{}; // absolute counts
  String _pakDate = _iso(DateTime.now());
  bool _saving = false;

  Future<void> _run(Future<void> Function() op) async {
    setState(() => _saving = true);
    try {
      await op();
      if (mounted) Navigator.pop(context);
      widget.onDone();
    } catch (_) {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.hd;
    return DefaultTabController(
      length: 3,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _grab(t),
          TabBar(
            labelColor: t.accent,
            unselectedLabelColor: t.textMuted,
            indicatorColor: t.accent,
            tabs: const [
              Tab(text: 'Adjust'),
              Tab(text: 'Count'),
              Tab(text: 'PAK'),
            ],
          ),
          SizedBox(
            height: 360,
            child: TabBarView(children: [
              _adjustTab(t),
              _countTab(t),
              _pakTab(t),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _adjustTab(HdTokens t) => Column(children: [
        Expanded(
          child: ListView(
            children: items.map((i) {
              final d = _adjust[i.code] ?? 0;
              return ListTile(
                dense: true,
                title: Text(i.label, style: TextStyle(color: t.textPrimary)),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                      onPressed: () => setState(() => _adjust[i.code] = d - 1),
                      icon: const Icon(Icons.remove, size: 16)),
                  Text(d > 0 ? '+$d' : '$d',
                      style: hdMono.copyWith(color: t.textPrimary)),
                  IconButton(
                      onPressed: () => setState(() => _adjust[i.code] = d + 1),
                      icon: const Icon(Icons.add, size: 16)),
                ]),
              );
            }).toList(),
          ),
        ),
        _confirmBtn('Apply adjustments', () {
          final deltas = {
            for (final e in _adjust.entries)
              if (e.value != 0) e.key: e.value
          };
          if (deltas.isEmpty) return;
          _run(() => ref.read(inventoryApiProvider).logEvent('manual', deltas));
        }),
      ]);

  Widget _countTab(HdTokens t) => Column(children: [
        Expanded(
          child: ListView(
            children: items.map((i) {
              final v = _count[i.code] ?? (widget.data.stock[i.code] ?? 0);
              return ListTile(
                dense: true,
                title: Text(i.label, style: TextStyle(color: t.textPrimary)),
                trailing: SizedBox(
                  width: 64,
                  child: TextFormField(
                    initialValue: '$v',
                    textAlign: TextAlign.right,
                    keyboardType: TextInputType.number,
                    onChanged: (raw) {
                      final n = int.tryParse(raw);
                      if (n != null) _count[i.code] = n;
                    },
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        _confirmBtn('Save stock count', () {
          if (_count.isEmpty) return;
          _run(() => ref
              .read(inventoryApiProvider)
              .logEvent('stock_count', _count, note: 'monthly stock count'));
        }),
      ]);

  Widget _pakTab(HdTokens t) => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('PAK installed date', style: TextStyle(color: t.textSecondary)),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: DateTime.parse(_pakDate),
                firstDate: DateTime(2023),
                lastDate: DateTime.now(),
              );
              if (picked != null) setState(() => _pakDate = _iso(picked));
            },
            icon: const Icon(Icons.calendar_today_outlined, size: 16),
            label: Text(_fmt(_pakDate)),
          ),
          const SizedBox(height: 16),
          _confirmBtn('Set PAK install', () {
            _run(() => ref.read(inventoryApiProvider).setPakInstall(_pakDate));
          }),
        ],
      );

  Widget _confirmBtn(String label, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
              onPressed: _saving ? null : onTap,
              child: Text(_saving ? 'Saving…' : label)),
        ),
      );
}

// ============================ Place order ============================

class PlaceOrderSheet extends ConsumerStatefulWidget {
  const PlaceOrderSheet({super.key, required this.data, required this.onDone});
  final InventoryResponse data;
  final VoidCallback onDone;
  @override
  ConsumerState<PlaceOrderSheet> createState() => _PlaceOrderSheetState();
}

class _PlaceOrderSheetState extends ConsumerState<PlaceOrderSheet> {
  late final Map<String, int> _boxes; // per-item boxes to order
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _boxes = {
      for (final i in items)
        if (i.section == 'nxstage')
          i.code: orderBoxes(i.code, widget.data.stock[i.code] ?? 0),
    };
  }

  @override
  Widget build(BuildContext context) {
    final t = context.hd;
    final ordering =
        items.where((i) => i.section == 'nxstage' && (_boxes[i.code] ?? 0) > 0).toList();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _grab(t),
        Text('Place order',
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w700, color: t.textPrimary)),
        const SizedBox(height: 4),
        Text('Suggested to reach target stock. Adjust boxes as needed.',
            style: TextStyle(fontSize: 12, color: t.textMuted)),
        const SizedBox(height: 12),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320),
          child: ListView(
            shrinkWrap: true,
            children: items.where((i) => i.section == 'nxstage').map((i) {
              final b = _boxes[i.code] ?? 0;
              return ListTile(
                dense: true,
                title: Text(i.label, style: TextStyle(color: t.textPrimary)),
                subtitle: Text('${i.boxSize} ${i.unit}/${i.boxLabel}',
                    style: TextStyle(color: t.textMuted, fontSize: 11)),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                      onPressed: b <= 0
                          ? null
                          : () => setState(() => _boxes[i.code] = b - 1),
                      icon: const Icon(Icons.remove, size: 16)),
                  Text('$b ${i.boxLabel}${b != 1 ? 's' : ''}',
                      style: hdMono.copyWith(color: t.textPrimary, fontSize: 12)),
                  IconButton(
                      onPressed: () => setState(() => _boxes[i.code] = b + 1),
                      icon: const Icon(Icons.add, size: 16)),
                ]),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 8),
        ElevatedButton(
          onPressed: (_saving || ordering.isEmpty)
              ? null
              : () async {
                  setState(() => _saving = true);
                  // Convert boxes → units for the API.
                  final order = <String, int>{
                    for (final e in _boxes.entries)
                      if (e.value > 0)
                        e.key: e.value * (getItem(e.key)?.boxSize ?? 1),
                  };
                  final callDate =
                      widget.data.cycle?.callDate ?? _iso(DateTime.now());
                  try {
                    await ref
                        .read(inventoryApiProvider)
                        .confirmOrder(callDate, order);
                    if (context.mounted) Navigator.pop(context);
                    widget.onDone();
                  } catch (_) {
                    if (mounted) setState(() => _saving = false);
                  }
                },
          child: Text(_saving ? 'Placing…' : 'Confirm order'),
        ),
      ],
    );
  }
}

// ============================ Cycle dates ============================

class CycleDatesSheet extends ConsumerStatefulWidget {
  const CycleDatesSheet({super.key, required this.initial, required this.onDone});
  final Cycle? initial;
  final VoidCallback onDone;
  @override
  ConsumerState<CycleDatesSheet> createState() => _CycleDatesSheetState();
}

class _CycleDatesSheetState extends ConsumerState<CycleDatesSheet> {
  String? _call;
  String? _delivery;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _call = widget.initial?.callDate;
    _delivery = widget.initial?.deliveryDate;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.hd;
    final isEdit = widget.initial != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _grab(t),
        Text(isEdit ? 'Edit cycle dates' : 'Set cycle dates',
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w700, color: t.textPrimary)),
        const SizedBox(height: 12),
        _dateField(t, 'Call date', _call, (d) {
          setState(() {
            _call = d;
            if (!isEdit && _delivery == null) {
              _delivery = _iso(DateTime.parse(d).add(const Duration(days: 7)));
            }
          });
        }),
        const SizedBox(height: 8),
        _dateField(t, 'Delivery date', _delivery, (d) => setState(() => _delivery = d)),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: (_saving || _call == null || _delivery == null)
              ? null
              : () async {
                  setState(() => _saving = true);
                  try {
                    final api = ref.read(inventoryApiProvider);
                    if (isEdit) {
                      await api.updateCycleDates(_call!, _delivery!);
                    } else {
                      await api.initCycle(_call!, deliveryDate: _delivery);
                    }
                    if (context.mounted) Navigator.pop(context);
                    widget.onDone();
                  } catch (_) {
                    if (mounted) setState(() => _saving = false);
                  }
                },
          child: Text(_saving ? 'Saving…' : 'Save'),
        ),
      ],
    );
  }

  Widget _dateField(
      HdTokens t, String label, String? value, ValueChanged<String> onPick) {
    return Row(children: [
      SizedBox(
          width: 100,
          child: Text(label, style: TextStyle(color: t.textSecondary))),
      const Spacer(),
      OutlinedButton.icon(
        onPressed: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: value != null ? DateTime.parse(value) : DateTime.now(),
            firstDate: DateTime(2024),
            lastDate: DateTime(2030),
          );
          if (picked != null) onPick(_iso(picked));
        },
        icon: const Icon(Icons.calendar_today_outlined, size: 16),
        label: Text(value == null ? 'Pick' : _fmt(value)),
      ),
    ]);
  }
}

// ============================ View order ============================

class ViewOrderSheet extends StatelessWidget {
  const ViewOrderSheet({super.key, required this.cycle});
  final Cycle cycle;
  @override
  Widget build(BuildContext context) {
    final t = context.hd;
    final order = cycle.order ?? {};
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _grab(t),
        Text('Placed order',
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w700, color: t.textPrimary)),
        const SizedBox(height: 8),
        ...order.entries.where((e) => e.value > 0).map((e) {
          final item = getItem(e.key);
          final boxes = item != null ? (e.value / item.boxSize).round() : e.value;
          final label = item?.label ?? e.key;
          final boxLabel = item != null
              ? (boxes == 1 ? item.boxLabel : '${item.boxLabel}s')
              : 'units';
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              Expanded(
                  child: Text(label, style: TextStyle(color: t.textSecondary))),
              Text('$boxes $boxLabel',
                  style: TextStyle(
                      color: t.accent, fontWeight: FontWeight.w600)),
            ]),
          );
        }),
        const SizedBox(height: 8),
        Text('Delivery expected ${_fmt(cycle.deliveryDate)}',
            style: TextStyle(fontSize: 12, color: t.textMuted)),
      ],
    );
  }
}

// ============================ History ============================

class HistorySheet extends ConsumerStatefulWidget {
  const HistorySheet({super.key});
  @override
  ConsumerState<HistorySheet> createState() => _HistorySheetState();
}

class _HistorySheetState extends ConsumerState<HistorySheet> {
  List<DeliveryEvent>? _deliveries;

  @override
  void initState() {
    super.initState();
    ref.read(inventoryApiProvider).fetchDeliveries().then((d) {
      if (mounted) setState(() => _deliveries = d);
    }).catchError((_) {
      if (mounted) setState(() => _deliveries = <DeliveryEvent>[]);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.hd;
    final d = _deliveries;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _grab(t),
        Text('Delivery history',
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w700, color: t.textPrimary)),
        const SizedBox(height: 8),
        if (d == null)
          const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()))
        else if (d.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('No deliveries applied yet.',
                style: TextStyle(color: t.textMuted)),
          )
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 360),
            child: ListView(
              shrinkWrap: true,
              children: d.map((e) {
                final items = e.deltas.entries.where((x) => x.value > 0).toList();
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_fmt(e.timestamp.substring(0, 10)),
                          style: TextStyle(fontSize: 12, color: t.textMuted)),
                      ...items.map((x) {
                        final item = getItem(x.key);
                        final boxes = item != null
                            ? (x.value / item.boxSize).round()
                            : x.value;
                        return Row(children: [
                          Expanded(
                              child: Text(item?.label ?? x.key,
                                  style: TextStyle(color: t.textSecondary))),
                          Text('+$boxes',
                              style: TextStyle(
                                  color: t.accent, fontWeight: FontWeight.w600)),
                        ]);
                      }),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }
}
