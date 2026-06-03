import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart' show cacheStoreProvider;
import '../../app/shell.dart';
import '../../app/theme.dart';
import '../treatment/providers.dart' show inventoryApiProvider;
import 'constants.dart';
import 'inventory_models.dart';
import 'inventory_sheets.dart';
import 'stock_calc.dart';

String _today() => DateTime.now().toIso8601String().substring(0, 10);

int _daysUntil(String dateStr) {
  final d = DateTime.tryParse(dateStr);
  if (d == null) return 0;
  final today = DateTime.now();
  final t0 = DateTime(today.year, today.month, today.day);
  final d0 = DateTime(d.year, d.month, d.day);
  return d0.difference(t0).inDays;
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
];
String _fmt(String dateStr) {
  final d = DateTime.tryParse(dateStr);
  return d == null ? dateStr : '${d.day} ${_months[d.month - 1]}';
}

class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key});
  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  InventoryResponse? _data;
  String? _error;

  static const _cacheKey = 'inventory';

  @override
  void initState() {
    super.initState();
    // Show cached data immediately — user pulls to refresh.
    try {
      final cached = ref.read(cacheStoreProvider).readStale(_cacheKey);
      if (cached != null) _data = InventoryResponse.fromJson(cached);
    } catch (_) {/* cache unavailable (e.g. first launch) */}
    // Auto-load once if there's no cached data yet (first visit).
    if (_data == null) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _load(autoApply: true));
    }
  }

  Future<void> _load({bool autoApply = false}) async {
    try {
      final data = await ref.read(inventoryApiProvider).fetchInventory();
      if (!mounted) return;
      // Persist to cache for offline reads.
      try {
        ref.read(cacheStoreProvider).write(_cacheKey, data.toJson());
      } catch (_) {}
      setState(() {
        _data = data;
        _error = null;
      });
      // Auto-apply a delivery whose date has passed.
      final c = data.cycle;
      if (autoApply &&
          c != null &&
          c.orderPlaced &&
          c.deliveryAppliedAt == null &&
          c.deliveryDate.compareTo(_today()) <= 0) {
        await ref.read(inventoryApiProvider).applyDelivery();
        _load();
      }
    } catch (e) {
      if (mounted && _data == null) {
        setState(() => _error = 'Could not load inventory.');
      }
    }
  }

  Future<void> _adjust(String code, int delta) async {
    final data = _data;
    if (data == null) return;
    setState(() {
      _data = _withStock(data, {code: (data.stock[code] ?? 0) + delta});
    });
    try {
      await ref.read(inventoryApiProvider).logEvent('manual', {code: delta});
    } catch (_) {
      // revert
      if (mounted) {
        setState(() => _data = _withStock(_data!, {code: (_data!.stock[code] ?? 0) - delta}));
      }
    }
  }

  /// Long-press the current stock count to set an exact quantity directly.
  /// Uses stock_count event type which does an absolute set, not a relative delta.
  Future<void> _setExact(String code, int current) async {
    final controller = TextEditingController(text: '$current');
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Set exact count', style: TextStyle(color: context.hd.textPrimary)),
        backgroundColor: context.hd.panel,
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Quantity'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final v = int.tryParse(controller.text);
              if (v != null && v >= 0) Navigator.pop(ctx, v);
            },
            child: const Text('Set'),
          ),
        ],
      ),
    );
    if (result == null || !mounted) return;
    final prev = _data!.stock[code] ?? 0;
    setState(() => _data = _withStock(_data!, {code: result}));
    try {
      await ref.read(inventoryApiProvider).logEvent('stock_count', {code: result});
    } catch (_) {
      if (mounted) setState(() => _data = _withStock(_data!, {code: prev}));
    }
  }

  InventoryResponse _withStock(InventoryResponse base, Map<String, int> patch) {
    return InventoryResponse(
      stock: {...base.stock, ...patch},
      cycle: base.cycle,
      pakInstalledAt: base.pakInstalledAt,
      pakSessions: base.pakSessions,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.hd;
    final data = _data;

    Widget body;
    if (data == null) {
      body = _error != null
          ? Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(_error!, style: TextStyle(color: t.danger)),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: _load, child: const Text('Retry')),
            ]))
          : const Center(child: CircularProgressIndicator());
    } else {
      final entries = items.map((i) => StockEntry(i.code, data.stock[i.code] ?? 0)).toList();
      final sorted = sortStock(entries);
      final nxstage =
          sorted.where((e) => getItem(e.code)?.section == 'nxstage').toList();
      final hospital =
          sorted.where((e) => getItem(e.code)?.section == 'hospital').toList();

      body = RefreshIndicator(
        onRefresh: () => _load(autoApply: true),
        child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          _Banner(cycle: data.cycle, onAction: _onBannerAction),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _openLogEvent(data),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Log event'),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
                onPressed: _openHistory, child: const Text('Deliveries')),
          ]),
          const SizedBox(height: 16),
          _section(t, 'NxStage Supplies', nxstage, data),
          const SizedBox(height: 16),
          _section(t, 'Hospital Prescriptions', hospital, data),
        ],
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.findAncestorWidgetOfExactType<StatefulNavigationShell>()?.goBranch(0);
      },
      child: HdScaffold(title: 'Inventory', body: body),
    );
  }

  Widget _section(
      HdTokens t, String title, List<StockEntry> entries, InventoryResponse data) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title.toUpperCase(),
            style: TextStyle(fontSize: 12, letterSpacing: 1, color: t.textMuted)),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: t.panel,
            border: Border.all(color: t.border),
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(
            children: [
              for (final e in entries)
                _StockRow(
                  item: getItem(e.code)!,
                  qty: e.qty,
                  onAdjust: (d) => _adjust(e.code, d),
                  onSetExact: () => _setExact(e.code, e.qty),
                  pakInstalledAt: e.code == 'PAK-001' ? data.pakInstalledAt : null,
                  pakSessions: e.code == 'PAK-001' ? data.pakSessions : null,
                ),
            ],
          ),
        ),
      ],
    );
  }

  // --- banner actions ---
  void _onBannerAction(_BannerAction a) {
    final data = _data;
    if (data == null) return;
    switch (a) {
      case _BannerAction.setup:
        _openCycleDates(initial: null);
      case _BannerAction.editDates:
        _openCycleDates(initial: data.cycle);
      case _BannerAction.placeOrder:
        _openPlaceOrder(data);
      case _BannerAction.viewOrder:
        _openViewOrder(data.cycle!);
      case _BannerAction.adjustDelivery:
        _openDelivery(data.cycle!);
      case _BannerAction.deliver:
        _quickDeliver();
    }
  }

  Future<void> _quickDeliver() async {
    await ref.read(inventoryApiProvider).applyDelivery();
    _load();
  }

  // --- sheets ---
  void _sheet(Widget child) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SheetShell(child: child),
    );
  }

  void _openLogEvent(InventoryResponse data) =>
      _sheet(LogEventSheet(data: data, onDone: _load));

  void _openHistory() => _sheet(const HistorySheet());

  void _openViewOrder(Cycle cycle) => _sheet(ViewOrderSheet(
        cycle: cycle,
        onEdit: () => _sheet(EditOrderSheet(cycle: cycle, onDone: _load)),
        onEarlyDelivery: _quickDeliver,
      ));

  Future<void> _openCycleDates({required Cycle? initial}) async {
    _sheet(CycleDatesSheet(initial: initial, onDone: _load));
  }

  void _openPlaceOrder(InventoryResponse data) =>
      _sheet(OrderSheet(data: data, onDone: _load));

  void _openDelivery(Cycle cycle) =>
      _sheet(DeliverySheet(cycle: cycle, onDone: _load));
}

// ============================ Stock row ============================

Color _statusColor(HdTokens t, StockStatus s) => switch (s) {
      StockStatus.red => t.danger,
      StockStatus.amber => t.warning,
      StockStatus.green => t.good,
    };

class _StockRow extends StatelessWidget {
  const _StockRow({
    required this.item,
    required this.qty,
    required this.onAdjust,
    required this.onSetExact,
    this.pakInstalledAt,
    this.pakSessions,
  });
  final ItemDef item;
  final int qty;
  final ValueChanged<int> onAdjust;
  final VoidCallback onSetExact;
  final String? pakInstalledAt;
  final int? pakSessions;

  @override
  Widget build(BuildContext context) {
    final t = context.hd;
    final sr = sessionsRemaining(item.code, qty);
    final status = stockStatus(item.code, qty);
    final color = _statusColor(t, status);
    final showPak = item.code == 'PAK-001' && pakInstalledAt != null;
    final pakColor = (pakSessions ?? 0) >= 10
        ? t.danger
        : (pakSessions ?? 0) >= 8
            ? t.warning
            : t.good;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Flexible(
                      child: Text(item.label,
                          style: TextStyle(color: t.textPrimary, fontSize: 14))),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onLongPress: onSetExact,
                    child: Text('$qty ${item.unit}${qty != 1 ? 's' : ''}',
                        style: TextStyle(color: color, fontSize: 12)),
                  ),
                  if (sr != null)
                    Text(' ~$sr sess',
                        style: TextStyle(color: t.textMuted, fontSize: 12)),
                ]),
                if (showPak)
                  Text(
                    'Installed ${_fmt(pakInstalledAt!)} · ${pakSessions ?? 0}/10 sess',
                    style: TextStyle(color: pakColor, fontSize: 11),
                  ),
              ],
            ),
          ),
          _round(t, Icons.remove, qty <= 0 ? null : () => onAdjust(-1)),
          const SizedBox(width: 6),
          _round(t, Icons.add, () => onAdjust(1)),
        ],
      ),
    );
  }

  Widget _round(HdTokens t, IconData icon, VoidCallback? onTap) => InkWell(
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
              color: onTap == null ? t.textMuted.withValues(alpha: 0.4) : t.textSecondary),
        ),
      );
}

// ============================ Banner ============================

enum _BannerAction { setup, editDates, placeOrder, viewOrder, deliver, adjustDelivery }

class _Banner extends StatelessWidget {
  const _Banner({required this.cycle, required this.onAction});
  final Cycle? cycle;
  final void Function(_BannerAction) onAction;

  @override
  Widget build(BuildContext context) {
    final t = context.hd;

    Widget card(Widget child) => Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: t.panel,
            border: Border.all(color: t.border),
            borderRadius: BorderRadius.circular(14),
          ),
          child: child,
        );

    // ── No cycle ──────────────────────────────────────────────
    if (cycle == null) {
      return card(Column(children: [
        _headerRow(t, 'DELIVERY CYCLE'),
        const SizedBox(height: 12),
        Text('No delivery cycle set up yet.',
            style: TextStyle(color: t.textSecondary, fontSize: 13)),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => onAction(_BannerAction.setup),
            icon: const Icon(Icons.calendar_today, size: 18),
            label: const Text('Set dates'),
          ),
        ),
      ]));
    }

    final c = cycle!;
    final callDays = _daysUntil(c.callDate);
    final deliveryDays = _daysUntil(c.deliveryDate);
    final deliveryDue = c.orderPlaced && deliveryDays <= 0;

    final callLabel = callDays == 0
        ? 'today'
        : callDays < 0
            ? '${callDays.abs()}d ago'
            : 'in ${callDays}d';
    final deliveryLabel = deliveryDays == 0
        ? 'today'
        : deliveryDays < 0
            ? '${deliveryDays.abs()}d overdue'
            : 'in ${deliveryDays}d';

    // ── Main action button (context-dependent) ─────────────────
    Widget action;
    if (deliveryDue) {
      action = SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: () => onAction(_BannerAction.deliver),
          icon: const Icon(Icons.check_circle_outline, size: 18),
          label: const Text('Mark delivered'),
          style: ElevatedButton.styleFrom(
            backgroundColor: t.good,
            foregroundColor: t.accentOn,
          ),
        ),
      );
    } else if (c.orderPlaced) {
      action = SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: () => onAction(_BannerAction.viewOrder),
          icon: const Icon(Icons.local_shipping_outlined, size: 18),
          label: const Text('View order'),
        ),
      );
    } else {
      action = SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: () => onAction(_BannerAction.placeOrder),
          icon: const Icon(Icons.local_shipping_outlined, size: 18),
          label: const Text('Place order'),
        ),
      );
    }

    return card(Column(children: [
      _headerRow(t, 'DELIVERY CYCLE',
          onEdit: () => onAction(_BannerAction.editDates)),
      const SizedBox(height: 16),
      // CALL BY ──▶ DELIVERY timeline
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _dateBlock(t, 'CALL BY', _fmt(c.callDate), callLabel,
              overdue: callDays < 0)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Icon(Icons.arrow_forward, size: 18, color: t.textMuted),
          ),
          Expanded(
              child: _dateBlock(t, 'DELIVERY', _fmt(c.deliveryDate),
                  deliveryLabel,
                  overdue: deliveryDue)),
        ],
      ),
      const SizedBox(height: 16),
      action,
    ]));
  }

  /// Section header: muted uppercase label + optional edit pencil.
  Widget _headerRow(HdTokens t, String title, {VoidCallback? onEdit}) =>
      Row(children: [
        Text(title,
            style:
                TextStyle(fontSize: 11, letterSpacing: 1, color: t.textMuted)),
        const Spacer(),
        if (onEdit != null)
          GestureDetector(
            onTap: onEdit,
            child: Icon(Icons.edit_outlined, size: 16, color: t.textMuted),
          ),
      ]);

  /// One side of the CALL BY → DELIVERY timeline.
  Widget _dateBlock(
      HdTokens t, String label, String date, String relative,
      {bool overdue = false}) {
    final labelColor = overdue ? t.warning : t.textMuted;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 10, letterSpacing: 1, color: t.textMuted)),
        const SizedBox(height: 4),
        Text(date,
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: overdue ? t.warning : t.textPrimary)),
        Text(relative, style: TextStyle(fontSize: 12, color: labelColor)),
      ],
    );
  }
}

// ============================ Sheet shell ============================

class _SheetShell extends StatelessWidget {
  const _SheetShell({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final t = context.hd;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: t.bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: child,
      ),
    );
  }
}
