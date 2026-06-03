import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

String _boxLabel(ItemDef i, int n) => n == 1 ? i.boxLabel : '${i.boxLabel}s';

Widget _grab(HdTokens t) => Center(
      child: Container(
        width: 40,
        height: 4,
        margin: const EdgeInsets.only(bottom: 12),
        decoration:
            BoxDecoration(color: t.textMuted, borderRadius: BorderRadius.circular(2)),
      ),
    );

Widget _roundBtn(HdTokens t, IconData icon, VoidCallback? onTap) => InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
                color: onTap == null ? t.border.withValues(alpha: 0.4) : t.border)),
        child: Icon(icon,
            size: 14,
            color: onTap == null
                ? t.textMuted.withValues(alpha: 0.4)
                : t.textSecondary),
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
  final _adjust = <String, int>{};
  final _count = <String, int>{};
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
            tabs: const [Tab(text: 'Adjust'), Tab(text: 'Count'), Tab(text: 'PAK')],
          ),
          SizedBox(
            height: 360,
            child: TabBarView(children: [_adjustTab(t), _countTab(t), _pakTab(t)]),
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
                  _roundBtn(t, Icons.remove, () => setState(() => _adjust[i.code] = d - 1)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text(d > 0 ? '+$d' : '$d',
                        style: hdMono.copyWith(color: t.textPrimary)),
                  ),
                  _roundBtn(t, Icons.add, () => setState(() => _adjust[i.code] = d + 1)),
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
          _confirmBtn('Set PAK install',
              () => _run(() => ref.read(inventoryApiProvider).setPakInstall(_pakDate))),
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

// ============================ Order (multi-step) ============================

enum _OrderStep { count, list }

class OrderSheet extends ConsumerStatefulWidget {
  const OrderSheet({super.key, required this.data, required this.onDone});
  final InventoryResponse data;
  final VoidCallback onDone;
  @override
  ConsumerState<OrderSheet> createState() => _OrderSheetState();
}

class _OrderSheetState extends ConsumerState<OrderSheet> {
  _OrderStep _step = _OrderStep.count;
  late final Map<String, int> _counts; // physical stock count per nxstage item
  final Map<String, int> _boxes = {}; // boxes to order per item
  bool _saving = false;
  bool _copied = false;

  List<ItemDef> get _nxstage =>
      items.where((i) => i.section == 'nxstage').toList();

  @override
  void initState() {
    super.initState();
    _counts = {for (final i in _nxstage) i.code: widget.data.stock[i.code] ?? 0};
  }

  Future<void> _submitCount() async {
    setState(() => _saving = true);
    try {
      await ref
          .read(inventoryApiProvider)
          .logEvent('stock_count', _counts, note: 'order stock count');
      _boxes.clear();
      for (final i in _nxstage) {
        final b = orderBoxes(i.code, _counts[i.code] ?? 0);
        if (b > 0) _boxes[i.code] = b;
      }
      setState(() {
        _step = _OrderStep.list;
        _saving = false;
      });
    } catch (_) {
      if (mounted) setState(() => _saving = false);
    }
  }

  List<ItemDef> get _orderItems =>
      _nxstage.where((i) => (_boxes[i.code] ?? 0) > 0).toList();

  void _copyList() {
    final lines = _orderItems
        .map((i) => '${i.label}: ${_boxes[i.code]} ${_boxLabel(i, _boxes[i.code]!)}')
        .join('\n');
    Clipboard.setData(ClipboardData(text: lines));
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2),
        () => mounted ? setState(() => _copied = false) : null);
  }

  Future<void> _confirm() async {
    setState(() => _saving = true);
    final order = {
      for (final i in _orderItems) i.code: _boxes[i.code]! * i.boxSize,
    };
    final callDate = widget.data.cycle?.callDate ?? _iso(DateTime.now());
    try {
      await ref.read(inventoryApiProvider).confirmOrder(callDate, order);
      if (mounted) Navigator.pop(context);
      widget.onDone();
    } catch (_) {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.hd;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _grab(t),
        Text(_step == _OrderStep.count ? 'Step 1: Stock count' : 'Step 2: Order list',
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w700, color: t.textPrimary)),
        const SizedBox(height: 8),
        if (_step == _OrderStep.count) _countStep(t) else _listStep(t),
      ],
    );
  }

  Widget _countStep(HdTokens t) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Count what you physically have — this resets the estimate before calculating the order.',
              style: TextStyle(fontSize: 12, color: t.textMuted)),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: ListView(
              shrinkWrap: true,
              children: _nxstage.map((i) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    Expanded(
                        child: Text(i.label,
                            style: TextStyle(color: t.textPrimary, fontSize: 14))),
                    Text('${i.unit}s ',
                        style: TextStyle(color: t.textMuted, fontSize: 11)),
                    SizedBox(
                      width: 64,
                      child: TextFormField(
                        initialValue: '${_counts[i.code] ?? 0}',
                        textAlign: TextAlign.right,
                        keyboardType: TextInputType.number,
                        onChanged: (raw) {
                          final n = int.tryParse(raw);
                          if (n != null && n >= 0) _counts[i.code] = n;
                        },
                      ),
                    ),
                  ]),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
              onPressed: _saving ? null : _submitCount,
              child: Text(_saving ? 'Saving…' : 'Next: calculate order →')),
        ],
      );

  Widget _listStep(HdTokens t) {
    final orderItems = _orderItems;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (orderItems.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text('Stock is sufficient — nothing to order.',
                textAlign: TextAlign.center, style: TextStyle(color: t.textMuted)),
          )
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 300),
            child: ListView(
              shrinkWrap: true,
              children: orderItems.map((i) {
                final b = _boxes[i.code] ?? 0;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(i.label,
                              style: TextStyle(color: t.textPrimary, fontSize: 14)),
                          Text('have ${_counts[i.code] ?? 0}',
                              style: TextStyle(color: t.textMuted, fontSize: 11)),
                        ],
                      ),
                    ),
                    _roundBtn(t, Icons.remove,
                        b <= 0 ? null : () => setState(() => _boxes[i.code] = b - 1)),
                    SizedBox(
                      width: 64,
                      child: Text('$b ${_boxLabel(i, b)}',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: t.accent, fontWeight: FontWeight.w600, fontSize: 13)),
                    ),
                    _roundBtn(t, Icons.add, () => setState(() => _boxes[i.code] = b + 1)),
                  ]),
                );
              }).toList(),
            ),
          ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: orderItems.isEmpty ? null : _copyList,
              icon: Icon(_copied ? Icons.check : Icons.copy, size: 16),
              label: Text(_copied ? 'Copied' : 'Copy list'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ElevatedButton(
              onPressed: (_saving || orderItems.isEmpty) ? null : _confirm,
              child: Text(_saving ? 'Saving…' : 'Confirm order'),
            ),
          ),
        ]),
      ],
    );
  }
}

// ============================ Apply delivery ============================

class DeliverySheet extends ConsumerStatefulWidget {
  const DeliverySheet({super.key, required this.cycle, required this.onDone});
  final Cycle cycle;
  final VoidCallback onDone;
  @override
  ConsumerState<DeliverySheet> createState() => _DeliverySheetState();
}

class _DeliverySheetState extends ConsumerState<DeliverySheet> {
  late final Map<String, int> _counts; // units received per item
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _counts = {
      for (final e in (widget.cycle.order ?? {}).entries)
        if (e.value > 0) e.key: e.value,
    };
  }

  Future<void> _apply() async {
    setState(() => _saving = true);
    try {
      await ref.read(inventoryApiProvider).applyDelivery(
          adjustments: _counts.isEmpty ? null : _counts);
      if (mounted) Navigator.pop(context);
      widget.onDone();
    } catch (_) {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.hd;
    final codes = _counts.keys.toList();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _grab(t),
        Text('Apply delivery',
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w700, color: t.textPrimary)),
        const SizedBox(height: 4),
        Text('Adjust quantities if anything arrived differently from what was ordered.',
            style: TextStyle(fontSize: 12, color: t.textMuted)),
        const SizedBox(height: 8),
        if (codes.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text('No order on record — use Log event → Adjust instead.',
                textAlign: TextAlign.center, style: TextStyle(color: t.textMuted)),
          )
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: ListView(
              shrinkWrap: true,
              children: codes.map((code) {
                final item = getItem(code);
                final qty = _counts[code] ?? 0;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    Expanded(
                        child: Text(item?.label ?? code,
                            style: TextStyle(color: t.textPrimary, fontSize: 14))),
                    _roundBtn(t, Icons.remove,
                        qty <= 0 ? null : () => setState(() => _counts[code] = qty - 1)),
                    SizedBox(
                      width: 64,
                      child: Text('$qty ${item?.unit ?? ''}',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: t.accent, fontWeight: FontWeight.w600, fontSize: 13)),
                    ),
                    _roundBtn(t, Icons.add, () => setState(() => _counts[code] = qty + 1)),
                  ]),
                );
              }).toList(),
            ),
          ),
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: (_saving || codes.isEmpty) ? null : _apply,
          child: Text(_saving ? 'Applying…' : 'Apply delivery'),
        ),
      ],
    );
  }
}

// ============================ Edit placed order ============================

class EditOrderSheet extends ConsumerStatefulWidget {
  const EditOrderSheet({super.key, required this.cycle, required this.onDone});
  final Cycle cycle;
  final VoidCallback onDone;
  @override
  ConsumerState<EditOrderSheet> createState() => _EditOrderSheetState();
}

class _EditOrderSheetState extends ConsumerState<EditOrderSheet> {
  late final Map<String, int> _boxes; // boxes per item
  String? _addCode;
  bool _saving = false;

  List<ItemDef> get _nxstage =>
      items.where((i) => i.section == 'nxstage').toList();

  @override
  void initState() {
    super.initState();
    _boxes = {};
    for (final e in (widget.cycle.order ?? {}).entries) {
      final item = getItem(e.key);
      if (item != null && e.value > 0) {
        _boxes[e.key] = (e.value / item.boxSize).round();
      }
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final order = {
      for (final e in _boxes.entries)
        if (e.value > 0) e.key: e.value * (getItem(e.key)?.boxSize ?? 1),
    };
    try {
      await ref.read(inventoryApiProvider).updateOrder(order);
      if (mounted) Navigator.pop(context);
      widget.onDone();
    } catch (_) {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.hd;
    final orderItems = _nxstage.where((i) => (_boxes[i.code] ?? 0) > 0).toList();
    final addable = _nxstage.where((i) => (_boxes[i.code] ?? 0) <= 0).toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _grab(t),
        Text('Edit order',
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w700, color: t.textPrimary)),
        const SizedBox(height: 8),
        if (orderItems.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('No items — add one below.',
                textAlign: TextAlign.center, style: TextStyle(color: t.textMuted)),
          )
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 260),
            child: ListView(
              shrinkWrap: true,
              children: orderItems.map((i) {
                final qty = _boxes[i.code] ?? 0;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    Expanded(
                        child: Text(i.label,
                            style: TextStyle(color: t.textPrimary, fontSize: 14))),
                    _roundBtn(t, Icons.delete_outline,
                        () => setState(() => _boxes.remove(i.code))),
                    const SizedBox(width: 6),
                    _roundBtn(t, Icons.remove,
                        qty <= 1 ? null : () => setState(() => _boxes[i.code] = qty - 1)),
                    SizedBox(
                      width: 60,
                      child: Text('$qty ${_boxLabel(i, qty)}',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: t.accent, fontWeight: FontWeight.w600, fontSize: 13)),
                    ),
                    _roundBtn(t, Icons.add, () => setState(() => _boxes[i.code] = qty + 1)),
                  ]),
                );
              }).toList(),
            ),
          ),
        if (addable.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: DropdownButton<String>(
                value: _addCode,
                isExpanded: true,
                hint: const Text('Add item…'),
                dropdownColor: t.panel,
                underline: const SizedBox.shrink(),
                items: addable
                    .map((i) =>
                        DropdownMenuItem(value: i.code, child: Text(i.label)))
                    .toList(),
                onChanged: (v) => setState(() => _addCode = v),
              ),
            ),
            const SizedBox(width: 8),
            _roundBtn(t, Icons.add, _addCode == null
                ? null
                : () => setState(() {
                      _boxes[_addCode!] = 1;
                      _addCode = null;
                    })),
          ]),
        ],
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: (_saving || orderItems.isEmpty) ? null : _save,
          child: Text(_saving ? 'Saving…' : 'Save order'),
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
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _saving ? null : () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: const StadiumBorder(),
              ),
              child: const Text('Cancel'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton(
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
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: const StadiumBorder(),
              ),
              child: Text(_saving ? 'Saving…' : 'Save'),
            ),
          ),
        ]),
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
  const ViewOrderSheet({
    super.key,
    required this.cycle,
    required this.onEdit,
    required this.onEarlyDelivery,
  });
  final Cycle cycle;
  final VoidCallback onEdit;
  final VoidCallback onEarlyDelivery;

  @override
  Widget build(BuildContext context) {
    final t = context.hd;
    final order = cycle.order ?? {};
    final canDeliver = cycle.orderPlaced && cycle.deliveryAppliedAt == null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _grab(t),
        Row(children: [
          Text('Placed order',
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700, color: t.textPrimary)),
          if (cycle.orderPlacedAt != null) ...[
            const SizedBox(width: 8),
            Text(_fmt(cycle.orderPlacedAt!.substring(0, 10)),
                style: TextStyle(fontSize: 12, color: t.textMuted)),
          ],
          const Spacer(),
          TextButton(
              onPressed: () {
                Navigator.pop(context);
                onEdit();
              },
              child: const Text('Edit')),
        ]),
        const SizedBox(height: 4),
        ...order.entries.where((e) => e.value > 0).map((e) {
          final item = getItem(e.key);
          final boxes = item != null ? (e.value / item.boxSize).round() : e.value;
          final boxLabel = item != null ? _boxLabel(item, boxes) : 'units';
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              Expanded(
                  child: Text(item?.label ?? e.key,
                      style: TextStyle(color: t.textSecondary))),
              Text('$boxes $boxLabel',
                  style:
                      TextStyle(color: t.accent, fontWeight: FontWeight.w600)),
            ]),
          );
        }),
        const SizedBox(height: 8),
        Text('Delivery expected ${_fmt(cycle.deliveryDate)}',
            style: TextStyle(fontSize: 12, color: t.textMuted)),
        if (canDeliver) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              onEarlyDelivery();
            },
            icon: const Icon(Icons.local_shipping_outlined, size: 16),
            label: const Text('Early delivery'),
          ),
        ],
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
                final evItems =
                    e.deltas.entries.where((x) => x.value > 0).toList();
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_fmt(e.timestamp.substring(0, 10)),
                          style: TextStyle(fontSize: 12, color: t.textMuted)),
                      ...evItems.map((x) {
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
