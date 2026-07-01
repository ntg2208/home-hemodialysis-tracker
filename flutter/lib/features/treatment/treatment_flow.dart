import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../chat/screen_context.dart'
    show screenContextProvider, ScreenContextNotifier, TreatmentState;
import 'screens/active.dart';
import 'screens/home.dart';
import 'screens/post.dart';
import 'screens/pre.dart';
import 'treatment_flow_controller.dart';

/// The treatment lifecycle is now four real routes so the browser/OS back
/// button behaves — Home (`/treatment`), Pre (`/treatment/pre`), Active
/// (`/treatment/active`), Post (`/treatment/post`). Shared session data lives
/// in [treatmentFlowProvider]; these widgets are thin route builders that wire
/// the existing screens to the controller + navigation.

Widget _loading() =>
    const Scaffold(body: Center(child: CircularProgressIndicator()));

void _publish(WidgetRef ref, void Function(ScreenContextNotifier) update) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    update(ref.read(screenContextProvider.notifier));
  });
}

/// `/treatment` — the session list.
class TreatmentHomeRoute extends ConsumerStatefulWidget {
  const TreatmentHomeRoute({super.key});
  @override
  ConsumerState<TreatmentHomeRoute> createState() => _TreatmentHomeRouteState();
}

class _TreatmentHomeRouteState extends ConsumerState<TreatmentHomeRoute> {
  @override
  void initState() {
    super.initState();
    _publish(ref, (n) => n.setTreatmentState(TreatmentState.idle, clearSession: true));
  }

  @override
  Widget build(BuildContext context) {
    return TreatmentHome(
      onStartSession: (ids) {
        ref.read(treatmentFlowProvider.notifier).goPre(ids);
        context.push('/treatment/pre');
      },
    );
  }
}

/// `/treatment/pre` — pushed on top of Home; back returns to the list.
class PreTreatmentRoute extends ConsumerStatefulWidget {
  const PreTreatmentRoute({super.key});
  @override
  ConsumerState<PreTreatmentRoute> createState() => _PreTreatmentRouteState();
}

class _PreTreatmentRouteState extends ConsumerState<PreTreatmentRoute> {
  @override
  void initState() {
    super.initState();
    _publish(ref, (n) => n.setTreatmentState(TreatmentState.preForm, clearSession: true));
  }

  @override
  Widget build(BuildContext context) {
    final existingIds =
        ref.watch(treatmentFlowProvider.select((s) => s.existingIds));
    return PreTreatment(
      existingIds: existingIds,
      onSaved: (session, heparinUsed, epoUsed) {
        ref
            .read(treatmentFlowProvider.notifier)
            .startActive(session, heparinUsed, epoUsed);
        // Replace Pre so back from Active goes to the list, not back to Pre.
        context.pushReplacement('/treatment/active');
      },
      onCancel: () {
        ref.read(treatmentFlowProvider.notifier).finish();
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/treatment');
        }
      },
    );
  }
}

/// `/treatment/active` — back shows the "Cancel session?" confirm.
class ActiveSessionRoute extends ConsumerStatefulWidget {
  const ActiveSessionRoute({super.key});
  @override
  ConsumerState<ActiveSessionRoute> createState() => _ActiveSessionRouteState();
}

class _ActiveSessionRouteState extends ConsumerState<ActiveSessionRoute> {
  late final TreatmentFlowState _snap = ref.read(treatmentFlowProvider);

  @override
  void initState() {
    super.initState();
    final s = _snap;
    if (s.session != null) {
      _publish(
          ref,
          (n) => n.setTreatmentState(TreatmentState.active,
              activeSession: s.session,
              readings: s.readings.map((p) => p.reading).toList()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _snap;
    if (s.session == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/treatment');
      });
      return _loading();
    }
    final ctrl = ref.read(treatmentFlowProvider.notifier);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final cancel = await _confirmCancel(context);
        if (cancel == true && context.mounted) {
          ctrl.finish();
          context.go('/treatment');
        }
      },
      child: ActiveSession(
        key: ValueKey('active_${s.session!.sessionId}'),
        session: s.session!,
        initialReadings: s.readings,
        heparinUsed: s.heparinUsed,
        epoUsed: s.epoUsed,
        initialCountdownStartedAt: s.countdownStartedAt,
        initialTargetMin: s.targetMin,
        initialComment: s.comment,
        onReadingsChanged: ctrl.updateReadings,
        onCountdownChanged: ctrl.updateCountdown,
        onHeparinChanged: ctrl.setHeparin,
        onEpoChanged: ctrl.setEpo,
        onCommentChanged: ctrl.setComment,
        onEnd: (consumed) {
          ctrl.goPost(consumed);
          context.push('/treatment/post');
        },
      ),
    );
  }
}

/// `/treatment/post` — pushed on top of Active; back returns to Active.
class PostTreatmentRoute extends ConsumerStatefulWidget {
  const PostTreatmentRoute({super.key});
  @override
  ConsumerState<PostTreatmentRoute> createState() => _PostTreatmentRouteState();
}

class _PostTreatmentRouteState extends ConsumerState<PostTreatmentRoute> {
  late final TreatmentFlowState _snap = ref.read(treatmentFlowProvider);

  @override
  void initState() {
    super.initState();
    if (_snap.session != null) {
      _publish(
          ref,
          (n) => n.setTreatmentState(TreatmentState.postForm,
              activeSession: _snap.session));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _snap;
    if (s.session == null || s.consumed == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/treatment');
      });
      return _loading();
    }
    final ctrl = ref.read(treatmentFlowProvider.notifier);
    return PostTreatment(
      session: s.session!,
      consumed: s.consumed!,
      initialComment: s.comment,
      onSaved: () {
        ctrl.finish();
        context.go('/treatment');
      },
      onCancel: () {
        // Back to the active session to keep going.
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/treatment');
        }
      },
    );
  }
}

Future<bool?> _confirmCancel(BuildContext context) {
  final t = context.hd;
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: t.panel,
      title: Text('Cancel session?', style: TextStyle(color: t.textPrimary)),
      content: Text(
        'Your readings have been saved. The session will remain and can be '
        'completed later.',
        style: TextStyle(color: t.textSecondary),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text('Stay', style: TextStyle(color: t.accent)),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text('Cancel session', style: TextStyle(color: t.warning)),
        ),
      ],
    ),
  );
}
