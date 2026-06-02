import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/shell.dart';
import '../../app/theme.dart';
import 'logic.dart';
import 'models.dart';
import 'providers.dart';
import 'widgets/filter_bar.dart';
import 'widgets/results_table.dart';
import 'widgets/scorecard.dart';
import 'widgets/trend_chart.dart';

enum _Status { loading, error, ready }

enum _Tab { scorecard, trend }

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

  _Tab _tab = _Tab.scorecard;
  late Set<String> _favorites;
  FilterState _filter = const FilterState();

  @override
  void initState() {
    super.initState();
    _favorites = ref.read(btStoreProvider).readFavorites();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final store = ref.read(btStoreProvider);
    final cache = store.readCache();
    final defaultFrom = sixMonthsAgo(DateTime.now());

    if (cache.rows.isNotEmpty) {
      setState(() {
        _rows = cache.rows;
        _coveredFrom = cache.coveredFrom ?? defaultFrom;
        _lastSynced = cache.lastSynced;
        _status = _Status.ready;
        _refreshing = true;
        _initFilterDefaults();
      });
      _revalidate(defaultFrom);
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
        _initFilterDefaults();
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = _Status.error;
          _errorMsg = 'Could not load blood tests.';
        });
      }
    }
  }

  /// On first data load, default the marker to the first one and the From/To
  /// range to the actual span of the loaded rows (the default 6-month window).
  void _initFilterDefaults() {
    if (_filter.marker.isEmpty) {
      final markers = _markers();
      if (markers.isNotEmpty) _filter = _filter.copyWith(marker: markers.first);
    }
    if (_filter.from.isEmpty && _filter.to.isEmpty && _rows.isNotEmpty) {
      final months = _rows.map((r) => r.datetime.substring(0, 7)).toList()..sort();
      _filter = _filter.copyWith(from: months.first, to: months.last);
    }
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
        _initFilterDefaults();
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

  List<int> _years() {
    final nowYear = DateTime.now().year;
    final ys = <int>{for (final r in _rows) int.parse(r.datetime.substring(0, 4))};
    for (var y = 2023; y <= nowYear; y++) {
      ys.add(y);
    }
    final list = ys.toList()..sort();
    return list;
  }

  void _onFilterChange(FilterState next) {
    final oldFrom = _filter.from;
    setState(() => _filter = next);
    if (next.from.isNotEmpty && next.from != oldFrom) _ensureRange(next.from);
  }

  void _selectMarker(String marker) {
    setState(() {
      _filter = _filter.copyWith(marker: marker);
      _tab = _Tab.trend;
    });
  }

  void _toggleFavorite(String marker) {
    setState(() {
      _favorites = {..._favorites};
      if (!_favorites.add(marker)) _favorites.remove(marker);
    });
    ref.read(btStoreProvider).writeFavorites(_favorites);
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
      final scoped = filterRows(_rows,
          phase: _filter.phases,
          from: _filter.from.isEmpty ? null : _filter.from,
          to: _filter.to.isEmpty ? null : _filter.to);
      final trendRows =
          scoped.where((r) => r.marker == _filter.marker).toList();

      body = Column(
        children: [
          FilterBar(
            filter: _filter,
            markers: _markers(),
            years: _years(),
            onChange: _onFilterChange,
          ),
          _syncRow(t),
          _tabBar(t),
          Expanded(
            child: _tab == _Tab.scorecard
                ? Scorecard(
                    rows: scoped,
                    favorites: _favorites,
                    onSelectMarker: _selectMarker,
                    onToggleFavorite: _toggleFavorite,
                  )
                : ListView(children: [
                    TrendChart(marker: _filter.marker, rows: trendRows),
                    ResultsTable(rows: trendRows),
                  ]),
          ),
        ],
      );
    }

    return PopScope(
      canPop: _tab != _Tab.trend,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _tab == _Tab.trend) {
          setState(() => _tab = _Tab.scorecard);
        }
      },
      child: HdScaffold(title: 'Blood Tests', body: body),
    );
  }

  Widget _syncRow(HdTokens t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: t.panel,
          border: Border(bottom: BorderSide(color: t.border)),
        ),
        child: Row(children: [
          Text(_syncLabel(),
              style: TextStyle(
                  fontSize: 12,
                  color: _refreshError ? t.warning : t.textMuted)),
          const Spacer(),
          OutlinedButton(
            onPressed: _refreshing
                ? null
                : () => _revalidate(
                    _filter.from.isEmpty ? sixMonthsAgo(DateTime.now()) : _filter.from),
            style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 32),
                padding: const EdgeInsets.symmetric(horizontal: 14)),
            child: Text(_refreshing ? 'Syncing…' : 'Sync'),
          ),
        ]),
      );

  Widget _tabBar(HdTokens t) => Container(
        decoration: BoxDecoration(
          color: t.panel,
          border: Border(bottom: BorderSide(color: t.border)),
        ),
        child: Row(children: [
          _tabButton(t, 'Scorecard', _Tab.scorecard),
          _tabButton(t, 'Trend', _Tab.trend),
        ]),
      );

  Widget _tabButton(HdTokens t, String label, _Tab tab) {
    final active = _tab == tab;
    return InkWell(
      onTap: () => setState(() {
        if (tab == _Tab.trend && _filter.marker.isEmpty) return;
        _tab = tab;
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
                color: active ? t.accent : Colors.transparent, width: 2),
          ),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 14,
                color: active ? t.accent : t.textSecondary,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400)),
      ),
    );
  }
}
