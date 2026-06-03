import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/shell.dart';
import '../../../app/theme.dart';
import '../../../widgets/pressable_scale.dart';
import '../models.dart';
import '../providers.dart';
import '../treatment_repo.dart';
import '../widgets/session_list_item.dart';
import 'session_detail.dart';

/// Treatment Home — drawer destination. Cache-first session list + dried-weight
/// editor + Start session. Port of frontend Home.tsx.
class TreatmentHome extends ConsumerStatefulWidget {
  const TreatmentHome({super.key, required this.onStartSession});
  final void Function(List<String> existingIds) onStartSession;

  @override
  ConsumerState<TreatmentHome> createState() => _TreatmentHomeState();
}

class _TreatmentHomeState extends ConsumerState<TreatmentHome> {
  List<Session>? _sessions;
  bool _refreshing = false;
  String? _error;
  late double _driedWeight;
  bool _editingDried = false;
  final _driedController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final store = ref.read(treatmentStoreProvider);
    _driedWeight = store.getDriedWeight();
    _sessions = store.getCachedSessions();
    // Auto-load once if never synced before (no cache). Subsequent opens use cache.
    if (_sessions == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
  }

  @override
  void dispose() {
    _driedController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      _refreshing = true;
    });
    try {
      final r = await ref.read(treatmentRepoProvider).getAll();
      final sorted = [...r.sessions]..sort((a, b) => b.date.compareTo(a.date));
      ref.read(treatmentStoreProvider).saveCachedSessions(sorted);
      if (mounted) setState(() => _sessions = sorted);
    } catch (e) {
      if (mounted) setState(() => _error = 'Load failed: ${treatmentErrorCode(e)}');
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _openDetail(Session s) async {
    final deleted = await showSessionDetailSheet(context, s);
    if (deleted == true) _load();
  }

  Future<bool> _confirmDelete(Session s) async {
    final t = context.hd;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete session'),
        content: Text(
            'Delete session ${s.sessionId} and all its readings? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: t.danger, foregroundColor: t.accentOn),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _performDelete(Session s) async {
    setState(() => _sessions =
        _sessions!.where((x) => x.sessionId != s.sessionId).toList());
    ref.read(treatmentStoreProvider).saveCachedSessions(_sessions!);
    try {
      await ref.read(treatmentRepoProvider).deleteSession(s.sessionId);
      // Reverse any inventory deduction logged for this session (best-effort).
      ref.read(inventoryApiProvider)
          .rollbackSession(s.sessionId)
          .catchError((_) {});
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Delete failed — restoring.')));
      }
      _load();
    }
  }

  void _commitDried() {
    final n = num.tryParse(_driedController.text);
    if (n != null && n > 0) {
      setState(() => _driedWeight = n.toDouble());
      ref.read(treatmentStoreProvider).saveDriedWeight(n.toDouble());
    }
    setState(() => _editingDried = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.hd;
    final ids = _sessions?.map((s) => s.sessionId).toList() ?? [];
    final loaded = _sessions != null;

    return HdScaffold(
      title: 'Treatment',
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          PressableScale(
            child: ElevatedButton.icon(
              onPressed: loaded ? () => widget.onStartSession(ids) : null,
              icon: loaded
                  ? const Icon(Icons.play_arrow_outlined)
                  : SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: t.accentOn)),
              label: const Text('Start session'),
            ),
          ),
          const SizedBox(height: 16),
          _driedWeightCard(t),
          const SizedBox(height: 20),
          Row(
            children: [
              Text('RECENT SESSIONS',
                  style: TextStyle(
                      fontSize: 12,
                      letterSpacing: 1,
                      color: t.textMuted,
                      fontWeight: FontWeight.w600)),
              const Spacer(),
              if (_refreshing && loaded)
                Row(children: [
                  SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: t.textMuted)),
                  const SizedBox(width: 4),
                  Text('refreshing',
                      style: TextStyle(fontSize: 12, color: t.textMuted)),
                ]),
            ],
          ),
          const SizedBox(height: 8),
          if (_error != null)
            _errorBanner(t)
          else if (!loaded)
            Text('Loading…', style: TextStyle(color: t.textMuted))
          else if (_sessions!.isEmpty)
            Text('No sessions yet.', style: TextStyle(color: t.textMuted))
          else
            ..._sessions!.take(5).map((s) => Dismissible(
                  key: ValueKey(s.sessionId),
                  direction: DismissDirection.endToStart,
                  confirmDismiss: (_) => _confirmDelete(s),
                  onDismissed: (_) => _performDelete(s),
                  background: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.only(right: 20),
                    alignment: Alignment.centerRight,
                    decoration: BoxDecoration(
                      color: t.danger,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.delete_outline, color: t.accentOn),
                  ),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _openDetail(s),
                    child: SessionListItem(session: s),
                  ),
                )),
        ],
        ),
      ),
    );
  }

  Widget _driedWeightCard(HdTokens t) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: t.panel,
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Text('Dried weight',
              style: TextStyle(fontSize: 14, color: t.textSecondary)),
          const Spacer(),
          if (_editingDried)
            Row(children: [
              SizedBox(
                width: 70,
                child: TextField(
                  controller: _driedController,
                  autofocus: true,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  textAlign: TextAlign.right,
                  decoration: const InputDecoration(isDense: true),
                  onSubmitted: (_) => _commitDried(),
                ),
              ),
              IconButton(
                  onPressed: _commitDried,
                  icon: Icon(Icons.check, color: t.accent)),
              IconButton(
                  onPressed: () => setState(() => _editingDried = false),
                  icon: Icon(Icons.close, color: t.textMuted)),
            ])
          else
            InkWell(
              onTap: () {
                _driedController.text = _fmt(_driedWeight);
                setState(() => _editingDried = true);
              },
              child: Row(children: [
                Text('${_fmt(_driedWeight)} kg',
                    style: TextStyle(
                        fontWeight: FontWeight.w600, color: t.textPrimary)),
                const SizedBox(width: 6),
                Icon(Icons.edit_outlined, size: 14, color: t.textMuted),
              ]),
            ),
        ],
      ),
    );
  }

  Widget _errorBanner(HdTokens t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: t.danger.withValues(alpha: 0.15),
          border: Border.all(color: t.danger),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          Expanded(
              child: Text(_error!,
                  style: TextStyle(color: t.danger, fontSize: 13))),
          TextButton(onPressed: _load, child: const Text('Retry')),
        ]),
      );
}

String _fmt(num v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();
