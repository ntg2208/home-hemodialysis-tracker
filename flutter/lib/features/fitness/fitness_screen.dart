import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/shell.dart';
import '../../app/theme.dart';
import 'fitness_api.dart';
import 'providers.dart';
import '../chat/command_dispatch.dart'
    show fitnessFilterCommandProvider, FilterFitness;
import '../chat/screen_context.dart' show screenContextProvider;

const _cacheKey = 'fitness_summary';
const _cacheTtl = Duration(hours: 12);

const _typeMeta = <String, ({String label, IconData icon})>{
  'steps': (label: 'Steps', icon: Icons.directions_walk),
  'daily-resting-heart-rate': (label: 'Resting HR', icon: Icons.favorite),
  'sleep': (label: 'Sleep', icon: Icons.bedtime_outlined),
  'oxygen-saturation': (label: 'SpO₂', icon: Icons.water_drop_outlined),
  'daily-heart-rate-variability':
      (label: 'HRV (daily)', icon: Icons.monitor_heart_outlined),
  'heart-rate-variability':
      (label: 'HRV (raw)', icon: Icons.monitor_heart_outlined),
  'respiratory-rate-sleep-summary': (label: 'Respiratory rate', icon: Icons.air),
  'daily-sleep-temperature-derivations':
      (label: 'Skin temp', icon: Icons.thermostat_outlined),
  'heart-rate': (label: 'Heart rate', icon: Icons.speed),
};

({String label, IconData icon}) _meta(String type) =>
    _typeMeta[type] ?? (label: type, icon: Icons.show_chart);

String _fmtMb(int bytes) => bytes >= 1000000
    ? '${(bytes / 1000000).toStringAsFixed(1)} MB'
    : '${(bytes / 1000).round()} KB';

String _daysAgo(String? date) {
  if (date == null || date.isEmpty) return 'never';
  final then = DateTime.tryParse('${date}T00:00:00Z');
  if (then == null) return date;
  final days = DateTime.now().toUtc().difference(then).inDays;
  if (days <= 0) return 'today';
  if (days == 1) return 'yesterday';
  return '$days days ago';
}

class FitnessScreen extends ConsumerStatefulWidget {
  const FitnessScreen({super.key});
  @override
  ConsumerState<FitnessScreen> createState() => _FitnessScreenState();
}

class _FitnessScreenState extends ConsumerState<FitnessScreen> {
  FitnessSummary? _summary;
  String? _error;
  bool _syncing = false;
  String? _syncNote;

  @override
  void initState() {
    super.initState();
    // Show stale cache immediately — user pulls to refresh.
    final stale = ref.read(cacheStoreProvider).readStale(_cacheKey);
    if (stale != null) _summary = FitnessSummary.fromJson(stale);
    // Auto-load once if no cache yet (first visit).
    if (_summary == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }

    // Publish current route for AI context
    ref.read(screenContextProvider.notifier).setRoute('/fitness');

    // React to AI fitness filter commands (stub — no filter UI yet)
    ref.listenManual<FilterFitness?>(fitnessFilterCommandProvider, (_, cmd) {
      if (cmd == null || !mounted) return;
      debugPrint('[AI] FilterFitness: type=${cmd.type} days=${cmd.days}');
      ref.read(fitnessFilterCommandProvider.notifier).set(null); // consume
    });
  }

  Future<void> _load({bool background = false}) async {
    try {
      final summary = await ref.read(fitnessApiProvider).fetchSummary();
      ref.read(cacheStoreProvider).write(_cacheKey, _toJson(summary));
      if (mounted) {
        setState(() {
          _summary = summary;
          _error = null;
        });
      }
    } catch (e) {
      if (!background && mounted) {
        // On network failure, try stale cache before showing an error.
        final stale = ref.read(cacheStoreProvider).readStale(_cacheKey);
        if (stale != null) {
          setState(() {
            _summary = FitnessSummary.fromJson(stale);
            _error = null;
          });
        } else {
          setState(() => _error = 'Could not load fitness data.');
        }
      }
      // Background-refresh failures silently keep whatever is already shown.
    }
  }

  Future<void> _sync() async {
    if (_syncing) return;
    setState(() {
      _syncing = true;
      _syncNote = null;
    });
    try {
      final synced = await ref.read(fitnessApiProvider).sync();
      final errored = synced.entries
          .where((e) => (e.value as Map?)?['status'] == 'error')
          .map((e) => e.key)
          .toList();
      _syncNote = errored.isEmpty
          ? 'Sync complete.'
          : 'Synced with ${errored.length} type(s) failing: ${errored.join(', ')}';
      await _load();
    } catch (_) {
      _syncNote = 'Sync failed.';
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.hd;
    final summary = _summary;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.findAncestorWidgetOfExactType<StatefulNavigationShell>()?.goBranch(0);
      },
      child: HdScaffold(
        title: 'Fitness',
      actions: [
        IconButton(
          onPressed: _syncing ? null : _sync,
          tooltip: 'Sync now',
          icon: _syncing
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: t.accent))
              : const Icon(Icons.refresh),
        ),
      ],
      body: summary == null
          ? (_error != null
              ? _errorView(t)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      const SizedBox(height: 120),
                      Center(
                        child: Text('Pull to load fitness data',
                            style: TextStyle(color: t.textMuted)),
                      ),
                    ],
                  ),
                ))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                _healthLine(t, summary),
                if (_syncNote != null) ...[
                  const SizedBox(height: 6),
                  Text(_syncNote!,
                      style: TextStyle(fontSize: 12, color: t.textMuted)),
                ],
                const SizedBox(height: 16),
                if (!summary.hasData)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text('No fitness data synced yet. Press “Sync now”.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: t.textMuted)),
                  ),
                if (summary.types.any((x) => x.latest != null))
                  _latestCard(t, summary),
                const SizedBox(height: 12),
                _pipelineCard(t, summary),
                const SizedBox(height: 12),
                Center(
                    child: Text('${_fmtMb(summary.totals.bytes)} stored in GCS',
                        style: TextStyle(fontSize: 12, color: t.textMuted))),
              ],
              ),
            ),
      ),
    );
  }

  Widget _errorView(HdTokens t) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.warning_amber_rounded, color: t.warning, size: 36),
          const SizedBox(height: 8),
          Text(_error!, style: TextStyle(color: t.textPrimary)),
          const SizedBox(height: 12),
          OutlinedButton(
              onPressed: () => _load(), child: const Text('Retry')),
        ]),
      );

  Widget _healthLine(HdTokens t, FitnessSummary s) => Row(children: [
        Icon(s.allHealthy ? Icons.check_circle_outline : Icons.warning_amber_rounded,
            size: 16, color: s.allHealthy ? t.good : t.warning),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Last sync ${_daysAgo(s.lastSynced)} · ${s.totals.healthy}/${s.totals.types} types healthy',
            style: TextStyle(fontSize: 13, color: t.textSecondary),
          ),
        ),
      ]);

  Widget _latestCard(HdTokens t, FitnessSummary s) {
    final cards = s.types.where((x) => x.latest != null).toList();
    return _card(t,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('LATEST READINGS',
                style: TextStyle(
                    fontSize: 11, letterSpacing: 1, color: t.textMuted)),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 4,
              mainAxisSpacing: 8,
              children: cards.map((x) {
                final l = x.latest!;
                final m = _meta(x.type);
                return Row(children: [
                  Icon(m.icon, size: 16, color: t.accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text.rich(
                          overflow: TextOverflow.ellipsis,
                          TextSpan(
                            text: l.value,
                            style: TextStyle(
                                color: t.textPrimary,
                                fontWeight: FontWeight.w600),
                            children: [
                              if (l.unit.isNotEmpty)
                                TextSpan(
                                    text: ' ${l.unit}',
                                    style: TextStyle(
                                        color: t.textSecondary, fontSize: 13)),
                            ],
                          ),
                        ),
                        Text(
                          l.label +
                              (x.type == 'oxygen-saturation'
                                  ? ' (latest sample)'
                                  : ''),
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: t.textMuted),
                        ),
                      ],
                    ),
                  ),
                ]);
              }).toList(),
            ),
          ],
        ));
  }

  Widget _pipelineCard(HdTokens t, FitnessSummary s) => _card(t,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('PIPELINE STATUS',
              style:
                  TextStyle(fontSize: 11, letterSpacing: 1, color: t.textMuted)),
          const SizedBox(height: 8),
          ...s.types.map((x) {
            final m = _meta(x.type);
            final ok = x.error == null && !x.stale;
            final statusIcon = x.error != null
                ? Icon(Icons.warning_amber_rounded, size: 16, color: t.danger)
                : ok
                    ? Icon(Icons.check_circle_outline, size: 16, color: t.good)
                    : Icon(Icons.warning_amber_rounded,
                        size: 16, color: t.warning);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                Icon(m.icon, size: 14, color: t.textMuted),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(m.label,
                        style: TextStyle(fontSize: 13, color: t.textSecondary))),
                Text(x.error != null ? '—' : '${x.count ?? 0}',
                    style: hdMono.copyWith(fontSize: 12, color: t.textMuted)),
                const SizedBox(width: 12),
                SizedBox(
                    width: 78,
                    child: Text(x.error != null ? '' : (x.lastDate ?? ''),
                        textAlign: TextAlign.right,
                        style: TextStyle(fontSize: 11, color: t.textMuted))),
                const SizedBox(width: 8),
                statusIcon,
              ]),
            );
          }),
        ],
      ));

  Widget _card(HdTokens t, {required Widget child}) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: t.panel,
          border: Border.all(color: t.border),
          borderRadius: BorderRadius.circular(14),
        ),
        child: child,
      );
}

/// Re-serialize a summary back to the API JSON shape for caching.
Map<String, dynamic> _toJson(FitnessSummary s) => {
      'generated_at': s.generatedAt,
      'types': s.types
          .map((x) => {
                'type': x.type,
                'last_synced': x.lastSynced,
                'count': x.count,
                'last_date': x.lastDate,
                'stale': x.stale,
                'bytes': x.bytes,
                'error': x.error,
                if (x.latest != null)
                  'latest': {
                    'label': x.latest!.label,
                    'value': x.latest!.value,
                    'unit': x.latest!.unit,
                    'at': x.latest!.at,
                  },
              })
          .toList(),
      'totals': {
        'types': s.totals.types,
        'healthy': s.totals.healthy,
        'stale': s.totals.stale,
        'bytes': s.totals.bytes,
      },
    };
