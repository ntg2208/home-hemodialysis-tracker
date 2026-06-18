import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../inventory/constants.dart';
import '../inventory/consumption_rates_provider.dart';
import '../inventory/rate_overrides.dart';

class SupplyRatesSection extends ConsumerStatefulWidget {
  const SupplyRatesSection({super.key});
  @override
  ConsumerState<SupplyRatesSection> createState() => _SupplyRatesSectionState();
}

class _SupplyRatesSectionState extends ConsumerState<SupplyRatesSection> {
  static final _nxstage = items.where((i) => i.section == 'nxstage').toList();

  final Map<String, TextEditingController> _rateCtrl = {};
  final Map<String, TextEditingController> _targetCtrl = {};
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    final overrides = ref.read(consumptionRatesProvider);
    for (final item in _nxstage) {
      final o = overrides[item.code];
      final effectiveRate = _effectiveDefaultRate(item);
      _rateCtrl[item.code] = TextEditingController(
        text: o?.perSession != null
            ? '${o!.perSession}'
            : (effectiveRate != null ? '$effectiveRate' : ''),
      );
      final effectiveTarget = o?.targetQty ?? item.targetQty;
      _targetCtrl[item.code] =
          TextEditingController(text: '$effectiveTarget');
    }
  }

  // Returns the display default per-session rate.
  // PAK returns null (shown as read-only "0.1"). Needles returns 2.
  // Items with no session rate return null (no rate field shown).
  int? _effectiveDefaultRate(ItemDef item) {
    if (item.code == 'PAK-001') return null;
    if (item.code == 'P00012326') return 2;
    return item.perSession;
  }

  @override
  void dispose() {
    for (final c in _rateCtrl.values) {
      c.dispose();
    }
    for (final c in _targetCtrl.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final overrides = <String, RateOverride>{};
    for (final item in _nxstage) {
      final rateText = _rateCtrl[item.code]?.text.trim() ?? '';
      final targetText = _targetCtrl[item.code]?.text.trim() ?? '';
      final rate = int.tryParse(rateText);
      final target = int.tryParse(targetText);
      final validRate = (rate != null && rate > 0) ? rate : null;
      final validTarget = (target != null && target > 0) ? target : null;
      if (validRate != null || validTarget != null) {
        overrides[item.code] = RateOverride(
          perSession: item.code != 'PAK-001' ? validRate : null,
          targetQty: validTarget,
        );
      }
    }
    await ref.read(consumptionRatesProvider.notifier).save(overrides);
    setState(() => _saved = true);
  }

  Future<void> _reset() async {
    await ref.read(consumptionRatesProvider.notifier).reset();
    for (final item in _nxstage) {
      final effectiveRate = _effectiveDefaultRate(item);
      _rateCtrl[item.code]?.text =
          effectiveRate != null ? '$effectiveRate' : '';
      _targetCtrl[item.code]?.text = '${item.targetQty}';
    }
    setState(() => _saved = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Rates reset to defaults')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in _nxstage) _itemRow(item),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _save,
                child: Text(_saved ? 'Saved ✓' : 'Save rates'),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: _reset,
              child: const Text('Reset to defaults'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _itemRow(ItemDef item) {
    final isPak = item.code == 'PAK-001';
    final hasRate = isPak || _effectiveDefaultRate(item) != null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item.label,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Row(
            children: [
              if (hasRate) ...[
                Expanded(
                  child: isPak
                      ? InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Per session',
                            isDense: true,
                          ),
                          child: const Text('0.1 (fixed)',
                              style: TextStyle(fontSize: 14)),
                        )
                      : TextField(
                          controller: _rateCtrl[item.code],
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'Per session',
                            hintText: '${_effectiveDefaultRate(item)}',
                            isDense: true,
                            suffixText: item.unit,
                          ),
                          onChanged: (_) => setState(() => _saved = false),
                        ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: TextField(
                  controller: _targetCtrl[item.code],
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Target qty',
                    hintText: '${item.targetQty}',
                    isDense: true,
                    suffixText: item.unit,
                  ),
                  onChanged: (_) => setState(() => _saved = false),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
