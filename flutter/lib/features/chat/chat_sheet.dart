import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart' show aiSettingsControllerProvider;
import '../../app/theme.dart';
import '../kb/kb_providers.dart';
import '../kb/kb_store.dart';
import 'chat_controller.dart';

const _suggestions = [
  'Summarise my last session',
  "When's my next delivery?",
  'Show my recent HRV',
];

/// Opens the Chat assistant as an ~85%-height bottom sheet. UI only — replies
/// come from the mock responder until `/api/chat` is built.
void showChatSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _ChatSheet(),
  );
}

class _ChatSheet extends ConsumerStatefulWidget {
  const _ChatSheet();
  @override
  ConsumerState<_ChatSheet> createState() => _ChatSheetState();
}

class _ChatSheetState extends ConsumerState<_ChatSheet> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _send(String text) {
    if (text.trim().isEmpty) return;
    ref.read(chatControllerProvider.notifier).send(text);
    _input.clear();
    _focus.requestFocus();
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.hd;
    final state = ref.watch(chatControllerProvider);
    _scrollToBottom();

    return FractionallySizedBox(
      heightFactor: 0.85,
      child: Container(
        decoration: BoxDecoration(
          color: t.bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            _grabHandle(t),
            _header(t),
            Divider(height: 1, color: t.border),
            Expanded(child: _body(t, state)),
            if (state.mode == ChatMode.active) _inputRow(t, state),
            if (state.mode == ChatMode.viewing) _readOnlyFooter(t),
          ],
        ),
      ),
    );
  }

  Widget _grabHandle(HdTokens t) => Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 6),
        child: Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
                color: t.textMuted, borderRadius: BorderRadius.circular(2)),
          ),
        ),
      );

  Widget _header(HdTokens t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
        child: Row(children: [
          _avatar(t, 28),
          const SizedBox(width: 8),
          Text('Assistant',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: t.textPrimary)),
          const Spacer(),
          _iconBtn(t, Icons.history, 'History',
              () => ref.read(chatControllerProvider.notifier).openHistory()),
          _iconBtn(t, Icons.add, 'New chat',
              () => ref.read(chatControllerProvider.notifier).newChat()),
          _iconBtn(t, Icons.close, 'Close', () {
            ref.read(chatControllerProvider.notifier).onClose();
            Navigator.of(context).pop();
          }),
        ]),
      );

  Widget _iconBtn(HdTokens t, IconData icon, String tooltip, VoidCallback onTap) =>
      Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: t.border),
            ),
            child: Icon(icon, size: 18, color: t.textSecondary),
          ),
        ),
      );

  Widget _body(HdTokens t, ChatState state) {
    switch (state.mode) {
      case ChatMode.active:
        return state.messages.isEmpty
            ? _emptyState(t)
            : ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.all(16),
                itemCount: state.messages.length,
                itemBuilder: (_, i) => _bubble(t, state.messages[i]),
              );
      case ChatMode.history:
        return _historyList(t, state);
      case ChatMode.viewing:
        return _viewingConversation(t, state);
    }
  }

  Widget _avatar(HdTokens t, double size) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: t.accent, shape: BoxShape.circle),
        child: Icon(Icons.auto_awesome, size: size * 0.55, color: t.accentOn),
      );

  Widget _emptyState(HdTokens t) {
    final ai = ref.watch(aiSettingsControllerProvider);

    if (!ai.enabled) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.smart_toy_outlined, size: 48, color: t.textMuted),
            const SizedBox(height: 12),
            Text('AI assistant is disabled',
                style: TextStyle(color: t.textSecondary)),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () {
                Navigator.of(context).pop();
                context.push('/settings');
              },
              child: const Text('Enable in Settings'),
            ),
          ]),
        ),
      );
    }

    if (!ai.ready) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.key_off_outlined, size: 48, color: t.textMuted),
            const SizedBox(height: 12),
            Text('API key not set — add one in Settings.',
                textAlign: TextAlign.center,
                style: TextStyle(color: t.textSecondary)),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () {
                Navigator.of(context).pop();
                context.push('/settings');
              },
              child: const Text('Go to Settings'),
            ),
          ]),
        ),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _avatar(t, 48),
            const SizedBox(height: 12),
            Text('Ask about your BP, labs, fitness or supplies.',
                textAlign: TextAlign.center,
                style: TextStyle(color: t.textSecondary)),
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: _suggestions
                  .map((s) => ActionChip(
                        label: Text(s),
                        shape: const StadiumBorder(),
                        backgroundColor: t.panel,
                        side: BorderSide(color: t.border),
                        labelStyle:
                            TextStyle(fontSize: 12, color: t.textSecondary),
                        onPressed: () => _send(s),
                      ))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _historyList(HdTokens t, ChatState state) {
    if (state.conversations.isEmpty) {
      return Center(
        child: Text('No past conversations.',
            style: TextStyle(color: t.textMuted)),
      );
    }
    return Column(children: [
      Expanded(
        child: ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: state.conversations.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) {
            final conv = state.conversations[i];
            return InkWell(
              onTap: () => ref
                  .read(chatControllerProvider.notifier)
                  .viewConversation(conv),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: t.panel,
                  border: Border.all(color: t.border),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(conv.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: t.textPrimary)),
                        const SizedBox(height: 2),
                        Text(
                            '${conv.messages.length} messages · '
                            '${_fmtDate(conv.updatedAt)}',
                            style: TextStyle(
                                fontSize: 11, color: t.textMuted)),
                      ],
                    ),
                  ),
                ]),
              ),
            );
          },
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: TextButton.icon(
          onPressed: () =>
              ref.read(chatControllerProvider.notifier).deleteAllHistory(),
          icon: Icon(Icons.delete_outline, size: 16, color: t.danger),
          label: Text('Clear all history',
              style: TextStyle(color: t.danger, fontSize: 13)),
        ),
      ),
    ]);
  }

  String _fmtDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${d.day} ${months[d.month - 1]} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  Widget _viewingConversation(HdTokens t, ChatState state) {
    final conv = state.viewingConversation;
    if (conv == null) return const SizedBox.shrink();
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
        child: Row(children: [
          TextButton.icon(
            onPressed: () =>
                ref.read(chatControllerProvider.notifier).backToHistory(),
            icon: const Icon(Icons.arrow_back, size: 16),
            label: const Text('Back'),
            style: TextButton.styleFrom(padding: EdgeInsets.zero),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(conv.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: t.textMuted)),
          ),
        ]),
      ),
      Divider(height: 1, color: t.border),
      Expanded(
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: conv.messages.length,
          itemBuilder: (_, i) => _bubble(t, conv.messages[i]),
        ),
      ),
    ]);
  }

  Widget _bubble(HdTokens t, ChatMessage m) {
    final isUser = m.role == ChatRole.user;
    final bubble = Container(
      constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.72),
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isUser ? t.accent.withValues(alpha: 0.15) : t.panel,
        border: Border.all(color: isUser ? t.accent : t.border),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(isUser ? 16 : 4),
          bottomRight: Radius.circular(isUser ? 4 : 16),
        ),
      ),
      child: m.thinking
          ? _ThinkingDots(color: t.textMuted)
          : isUser
              ? Text(m.text, style: TextStyle(color: t.textPrimary))
              : MarkdownBody(
                  data: m.text,
                  styleSheet: MarkdownStyleSheet(
                    p: TextStyle(color: t.textPrimary, fontSize: 14),
                    tableBorder: TableBorder.all(color: t.border),
                    tableBody: TextStyle(color: t.textSecondary, fontSize: 13),
                    code: hdMono.copyWith(
                        color: t.textPrimary, backgroundColor: t.bg),
                  ),
                ),
    );

    return Column(
      crossAxisAlignment:
          isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment:
              isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isUser) ...[_avatar(t, 32), const SizedBox(width: 8)],
            Flexible(child: bubble),
          ],
        ),
        if (m.kbUpdate != null && !isUser) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 40),
            child: _KbUpdateChip(
              proposal: m.kbUpdate!,
              onConfirm: () => _applyKbUpdate(m.kbUpdate!),
            ),
          ),
        ],
      ],
    );
  }

  Widget _inputRow(HdTokens t, ChatState state) {
    return Padding(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 8,
        bottom: 24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Row(children: [
        Expanded(
          child: TextField(
            controller: _input,
            focusNode: _focus,
            minLines: 1,
            maxLines: 4,
            textInputAction: TextInputAction.send,
            onSubmitted: state.sending ? null : _send,
            decoration: const InputDecoration(
              hintText: 'Message',
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
          ),
        ),
        const SizedBox(width: 8),
        _SendButton(
          enabled: !state.sending,
          onTap: () => _send(_input.text),
        ),
      ]),
    );
  }

  Widget _readOnlyFooter(HdTokens t) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Text(
          'read-only · start a new chat to ask questions',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: t.textMuted),
        ),
      );

  Future<void> _applyKbUpdate(KbUpdateProposal proposal) async {
    final t = context.hd;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Update Knowledge Base'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Save "${proposal.title}" to your Knowledge Base?',
                style: TextStyle(color: t.textSecondary, fontSize: 13)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: t.panel,
                border: Border.all(color: t.border),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(proposal.content,
                  style: TextStyle(color: t.textPrimary, fontSize: 13)),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save to KB')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final now = DateTime.now();
      final entries = await ref.read(kbStoreProvider).getAll();
      final matching =
          entries.where((e) => e.title == proposal.title).toList();
      final existing = matching.isEmpty ? null : matching.first;
      final entry = KbEntry(
        id: existing?.id ?? KbEntry.newId(),
        title: proposal.title,
        content: proposal.content,
        source: 'ai-proposed',
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
      );
      await ref.read(kbStoreProvider).save(entry);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('"${proposal.title}" saved to Knowledge Base')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save to Knowledge Base.')),
        );
      }
    }
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({required this.enabled, required this.onTap});
  final bool enabled;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final t = context.hd;
    return Material(
      color: enabled ? t.accent : t.border,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(Icons.send, size: 20, color: t.accentOn),
        ),
      ),
    );
  }
}

class _KbUpdateChip extends StatelessWidget {
  const _KbUpdateChip({required this.proposal, required this.onConfirm});
  final KbUpdateProposal proposal;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final t = context.hd;
    return ActionChip(
      avatar: Icon(Icons.save_outlined, size: 14, color: t.accent),
      label: Text('Save "${proposal.title}" to KB',
          style: TextStyle(fontSize: 11, color: t.accent)),
      backgroundColor: t.accent.withValues(alpha: 0.08),
      side: BorderSide(color: t.accent.withValues(alpha: 0.3)),
      shape: const StadiumBorder(),
      onPressed: onConfirm,
    );
  }
}

class _ThinkingDots extends StatefulWidget {
  const _ThinkingDots({required this.color});
  final Color color;
  @override
  State<_ThinkingDots> createState() => _ThinkingDotsState();
}

class _ThinkingDotsState extends State<_ThinkingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))
        ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final phase = (_c.value - i * 0.2) % 1.0;
            final opacity = 0.3 + 0.7 * (phase < 0.5 ? phase * 2 : (1 - phase) * 2);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Opacity(
                opacity: opacity.clamp(0.3, 1.0),
                child: CircleAvatar(radius: 3, backgroundColor: widget.color),
              ),
            );
          }),
        );
      },
    );
  }
}
