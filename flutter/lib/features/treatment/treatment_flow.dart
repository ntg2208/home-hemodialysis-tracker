import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/shell.dart';
import '../../app/theme.dart';
import '../chat/command_dispatch.dart' show prefillPreCommandProvider;
import '../chat/screen_context.dart'
    show screenContextProvider, TreatmentState;
import 'models.dart';
import 'providers.dart';
import 'screens/active.dart';
import 'screens/home.dart';
import 'screens/post.dart';
import 'screens/pre.dart';
import 'store.dart';

sealed class _FlowScreen {}

class _Loading extends _FlowScreen {}

class _ErrorScreen extends _FlowScreen {}

class _Home extends _FlowScreen {}

class _Pre extends _FlowScreen {
  _Pre(this.existingIds);
  final List<String> existingIds;
}

class _Active extends _FlowScreen {
  _Active(this.session, this.readings, this.heparinUsed, this.epoUsed,
      {this.countdownStartedAt, this.targetMin});
  final Session session;
  List<PendingReading> readings;
  bool heparinUsed;
  bool epoUsed;
  int? countdownStartedAt;
  int? targetMin;
}

class _Post extends _FlowScreen {
  _Post(this.session, this.consumed);
  final Session session;
  final SessionConsumed consumed;
}

/// Treatment route: bootstraps Firebase auth (with the race fix + 20s timeout),
/// restores any in-progress session, and drives the Home→Pre→Active→Post machine.
/// Port of frontend/src/routes/Treatment/index.tsx.
class TreatmentFlow extends ConsumerStatefulWidget {
  const TreatmentFlow({super.key});

  @override
  ConsumerState<TreatmentFlow> createState() => _TreatmentFlowState();
}

class _TreatmentFlowState extends ConsumerState<TreatmentFlow> {
  _FlowScreen _screen = _Loading();

  @override
  void initState() {
    super.initState();
    _bootstrap();

    // Publish initial treatment state (idle until bootstrap completes).
    _publishTreatmentState();

    // React to AI prefill-pre command — transition to Pre if currently on Home.
    ref.listenManual(prefillPreCommandProvider, (_, cmd) {
      if (cmd != null && _screen is _Home && mounted) {
        final ids = ref.read(treatmentStoreProvider).getCachedSessions()
            ?.map((s) => s.sessionId).toList() ?? [];
        _goPre(ids);
      }
    });
  }

  Future<void> _bootstrap() async {
    setState(() => _screen = _Loading());
    final auth = ref.read(treatmentAuthProvider);
    try {
      await auth.ensure();
    } catch (e) {
      // currentUser may still be set from a previous session — Firestore may work.
      if (!auth.hasCurrentUser) {
        if (mounted) {
          setState(() => _screen = _ErrorScreen());
          _publishTreatmentState();
        }
        return;
      }
    }
    if (!mounted) return;
    _restoreOrHome();
  }

  void _restoreOrHome() {
    final active = ref.read(treatmentStoreProvider).getActiveState();
    if (active == null) {
      setState(() => _screen = _Home());
      _publishTreatmentState();
      return;
    }
    switch (active.screen) {
      case 'pre':
        setState(() => _screen = _Pre(active.existingIds ?? []));
        _publishTreatmentState();
      case 'active' when active.session != null:
        // Demote any in-flight reading to error ("interrupted") on restore.
        final readings = (active.readings ?? []).map((p) {
          if (p.status == SaveStatus.pending) {
            return PendingReading(p.reading,
                status: SaveStatus.error, errorMsg: 'interrupted');
          }
          return p;
        }).toList();
        setState(() => _screen = _Active(
              active.session!,
              readings,
              active.heparinUsed ?? true,
              active.epoUsed ?? true,
              countdownStartedAt: active.countdownStartedAt,
              targetMin: active.targetMin,
            ));
        _publishTreatmentState();
      case 'post' when active.session != null:
        setState(() => _screen = _Post(
            active.session!,
            active.consumed ??
                const SessionConsumed(
                    needles: 2, onOffPacks: 1, heparinUsed: false)));
        _publishTreatmentState();
      default:
        setState(() => _screen = _Home());
        _publishTreatmentState();
    }
  }

  TreatmentStore get _store => ref.read(treatmentStoreProvider);

  void _goPre(List<String> ids) {
    setState(() => _screen = _Pre(ids));
    _publishTreatmentState();
    _store.saveActiveState(ActiveState(
        screen: 'pre',
        existingIds: ids,
        savedAt: DateTime.now().millisecondsSinceEpoch));
  }

  _Active? _lastActive;

  void _goActive(Session session, bool heparinUsed, bool epoUsed) {
    final s = _Active(session, [], heparinUsed, epoUsed);
    _lastActive = s;
    setState(() => _screen = s);
    _publishTreatmentState();
    _persistActive(s);
  }

  void _goBackToActive() {
    if (_lastActive != null) {
      setState(() => _screen = _lastActive!);
      _publishTreatmentState();
    }
  }

  void _persistActive(_Active s) {
    _store.saveActiveState(ActiveState(
      screen: 'active',
      session: s.session,
      readings: s.readings,
      heparinUsed: s.heparinUsed,
      epoUsed: s.epoUsed,
      countdownStartedAt: s.countdownStartedAt,
      targetMin: s.targetMin,
      savedAt: DateTime.now().millisecondsSinceEpoch,
    ));
  }

  void _goPost(Session session, SessionConsumed consumed) {
    setState(() => _screen = _Post(session, consumed));
    _publishTreatmentState();
    _store.saveActiveState(ActiveState(
      screen: 'post',
      session: session,
      consumed: consumed,
      savedAt: DateTime.now().millisecondsSinceEpoch,
    ));
  }

  void _goHome() {
    _store.clearActiveState();
    setState(() => _screen = _Home());
    _publishTreatmentState();
  }

  void _publishTreatmentState() {
    final notifier = ref.read(screenContextProvider.notifier);
    switch (_screen) {
      case _Home() || _Loading() || _ErrorScreen():
        notifier.setTreatmentState(TreatmentState.idle, clearSession: true);
      case _Pre():
        notifier.setTreatmentState(TreatmentState.preForm, clearSession: true);
      case final _Active s:
        notifier.setTreatmentState(
          TreatmentState.active,
          activeSession: s.session,
          readings: s.readings.map((p) => p.reading).toList(),
        );
      case final _Post s:
        notifier.setTreatmentState(TreatmentState.postForm, activeSession: s.session);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screen = _screen;
    // Allow normal pop (and app exit) only from the Home/Loading/Error states.
    // Pre → back cancels session start (same as the X button).
    // Active → back shows a confirmation to avoid mid-session accidents.
    // Post → back returns to Active so the treatment can continue.
    return PopScope(
      canPop: screen is _Home || screen is _Loading || screen is _ErrorScreen,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (screen is _Pre) {
          _goHome();
        } else if (screen is _Active) {
          _confirmCancelSession(context);
        } else if (screen is _Post) {
          _goBackToActive();
        }
      },
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        child: switch (screen) {
          _Loading() => const HdScaffold(
              key: ValueKey('loading'),
              title: 'Treatment',
              body: Center(child: CircularProgressIndicator()),
            ),
          _ErrorScreen() => _errorView(key: ValueKey('error')),
          _Home() => TreatmentHome(key: ValueKey('home'), onStartSession: _goPre),
          _Pre() => PreTreatment(
              key: ValueKey('pre'),
              existingIds: screen.existingIds,
              onSaved: (session, heparinUsed, epoUsed) =>
                  _goActive(session, heparinUsed, epoUsed),
              onCancel: _goHome,
            ),
          _Active() => ActiveSession(
              key: ValueKey('active_${screen.session.sessionId}'),
              session: screen.session,
              initialReadings: screen.readings,
              heparinUsed: screen.heparinUsed,
              epoUsed: screen.epoUsed,
              initialCountdownStartedAt: screen.countdownStartedAt,
              initialTargetMin: screen.targetMin,
              onReadingsChanged: (rs) {
                screen.readings = rs;
                _persistActive(screen);
              },
              onCountdownChanged: (startedAt, targetMin) {
                screen.countdownStartedAt = startedAt;
                screen.targetMin = targetMin;
                _persistActive(screen);
              },
              onHeparinChanged: (h) {
                screen.heparinUsed = h;
                _persistActive(screen);
              },
              onEpoChanged: (e) {
                screen.epoUsed = e;
                _persistActive(screen);
              },
              onEnd: (consumed) => _goPost(screen.session, consumed),
            ),
          _Post() => PostTreatment(
              key: ValueKey('post'),
              session: screen.session,
              consumed: screen.consumed,
              onSaved: _goHome,
              onCancel: _goBackToActive,
            ),
        },
      ),
    );
  }

  void _confirmCancelSession(BuildContext context) {
    final t = context.hd;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: t.panel,
        title: Text('Cancel session?',
            style: TextStyle(color: t.textPrimary)),
        content: Text(
          'Your readings have been saved. The session will remain in Firestore and can be completed later.',
          style: TextStyle(color: t.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Stay', style: TextStyle(color: t.accent)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _goHome();
            },
            child: Text('Cancel session',
                style: TextStyle(color: t.warning)),
          ),
        ],
      ),
    );
  }

  Widget _errorView({Key? key}) {
    final t = context.hd;
    return HdScaffold(
      key: key,
      title: 'Treatment',
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.warning_amber_rounded, size: 40, color: t.warning),
            const SizedBox(height: 12),
            Text('Could not connect.',
                style: TextStyle(color: t.textPrimary, fontSize: 16)),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _bootstrap,
              icon: const Icon(Icons.refresh_outlined),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
