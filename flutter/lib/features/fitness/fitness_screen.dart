import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/shell.dart';
import '../../app/theme.dart';
import 'fitness_api.dart';
import 'fitness_detail.dart';
import 'metric_tiles.dart';
import 'providers.dart';
import '../chat/command_dispatch.dart'
    show fitnessFilterCommandProvider, FilterFitness;
import '../chat/screen_context.dart' show screenContextProvider;

const _cacheKey = 'fitness_summary';

class FitnessScreen extends ConsumerStatefulWidget {
  const FitnessScreen({super.key});
  @override
  ConsumerState<FitnessScreen> createState() => _FitnessScreenState();
}

class _FitnessScreenState extends ConsumerState<FitnessScreen>
    with WidgetsBindingObserver {
  FitnessSummary? _summary;
  String? _error;
  bool _syncing = false;
  String? _syncNote;
  DateTime? _lastFetchedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Show stale cache immediately — user pulls to refresh.
    final stale = ref.read(cacheStoreProvider).readStale(_cacheKey);
    if (stale != null) _summary = FitnessSummary.fromJson(stale);
    // Auto-load once if no cache yet (first visit).
    if (_summary == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }

    // Publish current route for AI context (deferred past build — Riverpod
    // disallows provider mutation during widget tree construction).
    Future(() => ref.read(screenContextProvider.notifier).setRoute('/fitness'));

    // React to AI fitness filter commands (stub — no filter UI yet)
    ref.listenManual<FilterFitness?>(fitnessFilterCommandProvider, (_, cmd) {
      if (cmd == null || !mounted) return;
      debugPrint('[AI] FilterFitness: type=${cmd.type} days=${cmd.days}');
      ref.read(fitnessFilterCommandProvider.notifier).set(null); // consume
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;
    final age = _lastFetchedAt == null
        ? const Duration(days: 1)
        : DateTime.now().difference(_lastFetchedAt!);
    if (age.inMinutes >= 10) _load(background: true);
  }

  Future<void> _load({bool background = false}) async {
    try {
      final summary = await ref.read(fitnessApiProvider).fetchSummary();
      ref.read(cacheStoreProvider).write(_cacheKey, _toJson(summary));
      _lastFetchedAt = DateTime.now();
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
        if (!didPop) {
          context
              .findAncestorWidgetOfExactType<StatefulNavigationShell>()
              ?.goBranch(0);
        }
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
                      strokeWidth: 2,
                      color: t.accent,
                    ),
                  )
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
                            child: Text(
                              'Pull to load fitness data',
                              style: TextStyle(color: t.textMuted),
                            ),
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
                    if (_syncNote != null) ...[
                      Text(
                        _syncNote!,
                        style: TextStyle(fontSize: 12, color: t.textMuted),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (!summary.hasData)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          'No fitness data synced yet. Press “Sync now”.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: t.textMuted),
                        ),
                      ),
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 1.5,
                      children: [
                        for (final def in fitnessTiles) _tile(t, def, summary),
                      ],
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _errorView(HdTokens t) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.warning_amber_rounded, color: t.warning, size: 36),
        const SizedBox(height: 8),
        Text(_error!, style: TextStyle(color: t.textPrimary)),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: () => _load(), child: const Text('Retry')),
      ],
    ),
  );

  Widget _tile(HdTokens t, MetricTileDef def, FitnessSummary summary) {
    final h = tileHeadline(summary, def);
    return InkWell(
      onTap: () => Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => detailFor(def))),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: t.panel,
          border: Border.all(color: t.border),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(def.icon, size: 16, color: t.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    def.label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: t.textSecondary),
                  ),
                ),
                Icon(Icons.chevron_right, size: 16, color: t.textMuted),
              ],
            ),
            Text.rich(
              overflow: TextOverflow.ellipsis,
              TextSpan(
                text: h.value,
                style: TextStyle(
                    fontSize: 24, fontWeight: FontWeight.w700, color: t.textPrimary),
                children: [
                  if (h.unit.isNotEmpty)
                    TextSpan(
                      text: ' ${h.unit}',
                      style: TextStyle(fontSize: 13, color: t.textSecondary),
                    ),
                ],
              ),
            ),
            Text(
              h.sub,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: t.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

/// Re-serialize a summary back to the API JSON shape for caching.
Map<String, dynamic> _toJson(FitnessSummary s) => {
  'generated_at': s.generatedAt,
  'types': s.types
      .map(
        (x) => {
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
        },
      )
      .toList(),
  'totals': {
    'types': s.totals.types,
    'healthy': s.totals.healthy,
    'stale': s.totals.stale,
    'bytes': s.totals.bytes,
  },
};
