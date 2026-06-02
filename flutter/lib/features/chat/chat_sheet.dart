import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import 'chat_controller.dart';

const _suggestions = [
  "How's my blood pressure trending?",
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

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send(String text) {
    if (text.trim().isEmpty) return;
    ref.read(chatControllerProvider.notifier).send(text);
    _input.clear();
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
            Expanded(
              child: state.messages.isEmpty
                  ? _emptyState(t)
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.all(16),
                      itemCount: state.messages.length,
                      itemBuilder: (_, i) => _bubble(t, state.messages[i]),
                    ),
            ),
            _inputRow(t, state),
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
          TextButton(
            onPressed: () => ref.read(chatControllerProvider.notifier).newChat(),
            child: const Text('New chat'),
          ),
          IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: Icon(Icons.close, color: t.textSecondary)),
        ]),
      );

  Widget _avatar(HdTokens t, double size) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: t.accent, shape: BoxShape.circle),
        child: Icon(Icons.auto_awesome, size: size * 0.55, color: t.accentOn),
      );

  Widget _emptyState(HdTokens t) => Center(
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

    return Row(
      mainAxisAlignment:
          isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!isUser) ...[_avatar(t, 32), const SizedBox(width: 8)],
        Flexible(child: bubble),
      ],
    );
  }

  Widget _inputRow(HdTokens t, ChatState state) {
    return Padding(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 8,
        bottom: 8 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Row(children: [
        Expanded(
          child: TextField(
            controller: _input,
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
