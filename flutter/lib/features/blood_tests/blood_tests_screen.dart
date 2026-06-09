import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:go_router/go_router.dart';

import '../../app/providers.dart' show testModeProvider;
import '../../app/shell.dart';
import '../../app/theme.dart';
import '../../flavor.dart';
import 'csv_import_sheet.dart';
import 'entry_sheet.dart';
import 'logic.dart';
import 'markers.dart';
import 'models.dart';
import 'providers.dart';
import '../chat/command_dispatch.dart'
    show btFilterCommandProvider, FilterBloodTests;
import '../chat/screen_context.dart' show screenContextProvider;
import 'widgets/filter_bar.dart' show FilterBar, FilterPill, FilterState;
import 'widgets/results_table.dart';
import 'widgets/scorecard.dart';
import 'widgets/trend_chart.dart';

enum _Status { loading, error, ready }

class BloodTestsScreen extends ConsumerStatefulWidget {
  const BloodTestsScreen({super.key});
  @override
  ConsumerState<BloodTestsScreen> createState() => _BloodTestsScreenState();
}

class _BloodTestsScreenState extends ConsumerState<BloodTestsScreen> {
  _Status _status = _Status.loading;
  String? _errorMsg;
  List<BloodTestRow> _rows = [];
  String _coveredFrom = '';
  int? _lastSynced;
  bool _refreshing = false;
  bool _refreshError = false;

  late Set<String> _favorites;
  FilterState _filter = const FilterState();

  final ScrollController _markerScrollCtrl = ScrollController();
  bool _markerHovered = false;

  @override
  void initState() {
    super.initState();
    _favorites = ref.read(btStoreProvider).readFavorites();
    _bootstrap();
    // Re-bootstrap when test mode is toggled so synthetic data loads immediately.
    ref.listenManual(testModeProvider, (_, __) {
      setState(() => _status = _Status.loading);
      _bootstrap();
    });

    // Publish current route for AI context (deferred past build — Riverpod
    // disallows provider mutation during widget tree construction).
    Future(() => ref.read(screenContextProvider.notifier).setRoute('/blood-tests'));

    // React to AI blood test filter commands
    ref.listenManual(btFilterCommandProvider, (_, cmd) {
      if (cmd == null || !mounted) return;
      _applyAiFilter(cmd);
      ref.read(btFilterCommandProvider.notifier).set(null); // consume
    });
  }

  @override
  void dispose() {
    _markerScrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final store = ref.read(btStoreProvider);
    final cache = store.readCache();
    final defaultFrom = sixMonthsAgo(DateTime.now());

    if (cache.rows.isNotEmpty) {
      // Show cached data immediately — user pulls to refresh.
      setState(() {
        _rows = cache.rows;
        _coveredFrom = cache.coveredFrom ?? defaultFrom;
        _lastSynced = cache.lastSynced;
        _status = _Status.ready;
      });
      return;
    }

    try {
      final rows = await ref.read(bloodTestsApiProvider).fetchRange(from: defaultFrom);
      final now = DateTime.now().millisecondsSinceEpoch;
      await store.writeCache(rows, defaultFrom, now);
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _coveredFrom = defaultFrom;
        _lastSynced = now;
        _status = _Status.ready;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          // If there's still no data at all, show empty state instead of error.
          if (_rows.isEmpty) {
            _status = _Status.ready;
          } else {
            _refreshing = false;
          }
        });
      }
    }
  }

  void _selectMarker(String marker) {
    setState(() => _filter = _filter.copyWith(marker: marker));
  }

  void _applyAiFilter(FilterBloodTests cmd) {
    setState(() {
      var f = _filter;
      if (cmd.marker != null) f = f.copyWith(marker: cmd.marker);
      if (cmd.phase != null) f = f.copyWith(phases: [cmd.phase!]);
      if (cmd.months != null) {
        f = f.copyWith(rangePreset: switch (cmd.months!) {
          3 => '3m',
          6 => '6m',
          12 => '1y',
          _ => 'all',
        });
      }
      _filter = f;
    });
  }

  Future<void> _revalidate(String fromFloor) async {
    setState(() {
      _refreshing = true;
      _refreshError = false;
    });
    try {
      final fresh =
          await ref.read(bloodTestsApiProvider).fetchRange(from: fromFloor);
      final now = DateTime.now().millisecondsSinceEpoch;
      final merged = mergeRows(_rows, fresh);
      final coveredFrom =
          earlierMonth(fromFloor, _coveredFrom) ? fromFloor : _coveredFrom;
      await ref.read(btStoreProvider).writeCache(merged, coveredFrom, now);
      if (!mounted) return;
      setState(() {
        _rows = merged;
        _coveredFrom = coveredFrom;
        _lastSynced = now;
        _refreshing = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _refreshing = false;
          _refreshError = true;
        });
      }
    }
  }

  /// Backfill the uncovered older slice when a `from` older than coverage is picked.
  Future<void> _ensureRange(String requestedFrom) async {
    final need = computeFetchRange(_coveredFrom, requestedFrom);
    if (need == null) return;
    setState(() {
      _refreshing = true;
      _refreshError = false;
    });
    try {
      final older = await ref
          .read(bloodTestsApiProvider)
          .fetchRange(from: need.from, to: need.to);
      final now = DateTime.now().millisecondsSinceEpoch;
      final merged = mergeRows(_rows, older);
      await ref.read(btStoreProvider).writeCache(merged, requestedFrom, now);
      if (!mounted) return;
      setState(() {
        _rows = merged;
        _coveredFrom = requestedFrom;
        _lastSynced = now;
        _refreshing = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _refreshing = false;
          _refreshError = true;
        });
      }
    }
  }

  List<String> _markers() {
    final set = <String>{for (final r in _rows) r.marker};
    final list = set.toList()..sort();
    return list;
  }

  /// Compute the effective lower-bound month for refresh/backfill from the
  /// current range preset. Returns '2020-01' (earliest plausible data) when
  /// the preset is 'all', and [sixMonthsAgo] as a fallback for empty presets.
  String _effectiveFrom() {
    if (_filter.rangePreset == 'all') return '2020-01';
    if (_filter.rangePreset.isEmpty) return sixMonthsAgo(DateTime.now());
    return rangeFrom(_filter.rangePreset);
  }

  void _onFilterChange(FilterState next) {
    final oldPreset = _filter.rangePreset;
    setState(() => _filter = next);
    if (next.rangePreset == 'all') {
      // Switching to all-time — backfill any uncovered history.
      _ensureRange('2020-01');
    } else if (next.rangePreset != oldPreset &&
        next.rangePreset.isNotEmpty) {
      _ensureRange(rangeFrom(next.rangePreset));
    }
  }

  void _toggleFavorite(String marker) {
    setState(() {
      _favorites = {..._favorites};
      if (!_favorites.add(marker)) _favorites.remove(marker);
    });
    ref.read(btStoreProvider).writeFavorites(_favorites);
  }

  Future<void> _exportCsv() async {
    final rows = _rows;
    if (rows.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No data to export')));
      }
      return;
    }
    final buf = StringBuffer();
    buf.writeln('date,marker,value,unit,ref_low,ref_high,timing,note');
    for (final r in rows) {
      buf.writeln(
          '${r.datetime.substring(0, 10)},${r.marker},${r.value},${r.unit},'
          '${r.refLow ?? ''},${r.refHigh ?? ''},${r.timing},${r.note}');
    }
    await Clipboard.setData(ClipboardData(text: buf.toString()));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('CSV copied to clipboard')));
    }
  }

  String _syncLabel() {
    if (_refreshing) return 'Syncing…';
    if (_refreshError) return 'Offline — showing cached';
    if (_lastSynced == null) return 'Not synced yet';
    final mins = ((DateTime.now().millisecondsSinceEpoch - _lastSynced!) / 60000).round();
    if (mins < 1) return 'Synced just now';
    if (mins < 60) return 'Synced ${mins}m ago';
    final hrs = (mins / 60).round();
    if (hrs < 24) return 'Synced ${hrs}h ago';
    return 'Synced ${(hrs / 24).round()}d ago';
  }

  /// "Jun 2023" from the cache floor "2023-06".
  String _coveredFromLabel() {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final parts = _coveredFrom.split('-');
    if (parts.length != 2) return _coveredFrom;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (y == null || m == null || m < 1 || m > 12) return _coveredFrom;
    return '${months[m - 1]} $y';
  }

  /// Empty-state shown when [scoped] has no rows.
  /// While downloading: spinner. Otherwise: coverage + one-tap full-history download.
  Widget _emptyState(HdTokens t) {
    if (_refreshing) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 80),
          Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text('Downloading…',
                  style: TextStyle(fontSize: 14, color: t.textMuted)),
            ]),
          ),
        ],
      );
    }

    final coverageText = _coveredFrom.isNotEmpty
        ? 'Cache covers ${_coveredFromLabel()} – present'
        : 'Cache is empty';

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 80),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.cloud_download_outlined, size: 44, color: t.textMuted),
              const SizedBox(height: 16),
              Text('No results for these filters',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: t.textPrimary)),
              const SizedBox(height: 8),
              Text(coverageText,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: t.textMuted)),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: () {
                  // Fetch full history and switch to "all" so the data is visible.
                  setState(() => _filter = _filter.copyWith(rangePreset: 'all'));
                  _ensureRange('2020-01');
                },
                icon: const Icon(Icons.download, size: 18),
                label: const Text('Download full history'),
              ),
            ]),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.hd;

    Widget body;
    if (_status == _Status.loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_status == _Status.error) {
      body = Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_errorMsg ?? 'Error', style: TextStyle(color: t.danger)),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: _bootstrap, child: const Text('Retry')),
        ]),
      );
    } else {
      final inTrend = _filter.marker.isNotEmpty;
      final markers = _markers();
      final scoped = filterRows(_rows,
          phase: _filter.phases,
          rangePreset: _filter.rangePreset,
          to: _filter.to.isEmpty ? null : _filter.to);

      body = Column(
        children: [
          FilterBar(
            filter: _filter,
            onChange: _onFilterChange,
          ),
          _syncRow(t),
          if (inTrend) _markerPillsRow(t, markers),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _revalidate(_effectiveFrom()),
              child: inTrend
                  ? _trendView(scoped)
                  : scoped.isEmpty
                      ? _emptyState(t)
                      : Scorecard(
                          rows: scoped,
                          favorites: _favorites,
                          onSelectMarker: _selectMarker,
                          onToggleFavorite: _toggleFavorite,
                        ),
            ),
          ),
        ],
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_filter.marker.isNotEmpty) {
          // Trend view → back to scorecard
          setState(() => _filter = _filter.copyWith(marker: ''));
        } else {
          // Scorecard view → go to Treatment
          context.findAncestorWidgetOfExactType<StatefulNavigationShell>()?.goBranch(0);
        }
      },
      child: HdScaffold(
        title: 'Blood Tests',
        actions: kCommunity
            ? [
                IconButton(
                  icon: const Icon(Icons.download_outlined),
                  tooltip: 'Export CSV',
                  onPressed: _exportCsv,
                ),
                IconButton(
                  icon: const Icon(Icons.upload_file_outlined),
                  tooltip: 'Import CSV',
                  onPressed: () => showCsvImportSheet(context).then((_) => _bootstrap()),
                ),
                IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: 'Add result',
                  onPressed: () => showEntrySheet(context).then((_) => _bootstrap()),
                ),
              ]
            : null,
        body: body,
      ),
    );
  }

  /// Scrollable row of marker pills — shown above the trend chart so the user
  /// can switch markers without going back to the scorecard.
  Widget _markerPillsRow(HdTokens t, List<String> markers) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: t.panel,
          border: Border(bottom: BorderSide(color: t.border)),
        ),
        child: MouseRegion(
          onEnter: (_) => setState(() => _markerHovered = true),
          onExit: (_) => setState(() => _markerHovered = false),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final pageWidth = constraints.maxWidth * 0.7;
              return Stack(
                children: [
                  SizedBox(
                    height: 32,
                    child: ListView.builder(
                      controller: _markerScrollCtrl,
                      scrollDirection: Axis.horizontal,
                      physics: const ClampingScrollPhysics(),
                      itemCount: markers.length,
                      itemBuilder: (_, i) {
                        final m = markers[i];
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterPill(
                            label: displayName(m),
                            active: _filter.marker == m,
                            onTap: () => setState(
                                () => _filter = _filter.copyWith(marker: m)),
                          ),
                        );
                      },
                    ),
                  ),
                  if (_markerHovered) ...[
                    _scrollArrow(t, Icons.chevron_left, true,
                        () => _scrollMarkersBy(-pageWidth)),
                    _scrollArrow(t, Icons.chevron_right, false,
                        () => _scrollMarkersBy(pageWidth)),
                  ],
                ],
              );
            },
          ),
        ),
      );

  void _scrollMarkersBy(double delta) {
    if (!_markerScrollCtrl.hasClients) return;
    final target = (_markerScrollCtrl.offset + delta)
        .clamp(0.0, _markerScrollCtrl.position.maxScrollExtent);
    _markerScrollCtrl.animateTo(
      target,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  Widget _scrollArrow(
          HdTokens t, IconData icon, bool left, VoidCallback onTap) =>
      Positioned(
        left: left ? 0 : null,
        right: left ? null : 0,
        top: 0,
        bottom: 0,
        child: Center(
          child: Material(
            color: t.panel.withValues(alpha: 0.85),
            borderRadius: BorderRadius.only(
              topLeft: left ? Radius.zero : const Radius.circular(20),
              bottomLeft: left ? Radius.zero : const Radius.circular(20),
              topRight: left ? const Radius.circular(20) : Radius.zero,
              bottomRight: left ? const Radius.circular(20) : Radius.zero,
            ),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.only(
                topLeft: left ? Radius.zero : const Radius.circular(20),
                bottomLeft: left ? Radius.zero : const Radius.circular(20),
                topRight: left ? const Radius.circular(20) : Radius.zero,
                bottomRight: left ? const Radius.circular(20) : Radius.zero,
              ),
              child: SizedBox(
                width: 28,
                height: 32,
                child: Icon(icon, size: 16, color: t.textSecondary),
              ),
            ),
          ),
        ),
      );

  /// Trend chart + results table for the currently selected marker.
  Widget _trendView(List<BloodTestRow> scoped) {
    final trendRows =
        scoped.where((r) => r.marker == _filter.marker).toList();
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        TrendChart(marker: _filter.marker, rows: trendRows),
        ResultsTable(rows: trendRows),
      ],
    );
  }

  Widget _syncRow(HdTokens t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: t.panel,
          border: Border(bottom: BorderSide(color: t.border)),
        ),
        child: Row(children: [
          // Green dot when synced successfully.
          if (!_refreshError && _lastSynced != null)
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(right: 8),
              decoration:
                  BoxDecoration(color: t.good, shape: BoxShape.circle),
            ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_syncLabel(),
                  style: TextStyle(
                      fontSize: 12,
                      color: _refreshError ? t.warning : t.textMuted)),
              if (_coveredFrom.isNotEmpty)
                Text('from ${_coveredFromLabel()}',
                    style: TextStyle(fontSize: 11, color: t.textMuted)),
            ],
          ),
          const Spacer(),
          SizedBox(
            height: 30,
            child: OutlinedButton(
              onPressed: _refreshing
                  ? null
                  : () => _revalidate(_effectiveFrom()),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 30),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                side: BorderSide(color: t.border),
                foregroundColor: t.textSecondary,
                textStyle: const TextStyle(fontSize: 12),
              ),
              child: Text(_refreshing ? 'Syncing…' : 'Sync'),
            ),
          ),
        ]),
      );

}
