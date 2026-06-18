import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../../app/theme.dart';

const _author = 'Truong Giang Nguyen';
const _email = 'ntg2208@gmail.com';
// Replace with the real URL once the repo is public.
const _repoUrl = 'github.com/ntg2208/homehd';

class AboutSection extends StatelessWidget {
  const AboutSection({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.hd;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Built by $_author',
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: t.textPrimary),
        ),
        const SizedBox(height: 4),
        Text(
          'Released under the MIT License',
          style: TextStyle(fontSize: 12, color: t.textMuted),
        ),
        const SizedBox(height: 12),
        _CopyRow(
          icon: Icons.code_outlined,
          label: _repoUrl,
          copyValue: _repoUrl,
          tooltip: 'Copy repo URL',
        ),
        const SizedBox(height: 8),
        _CopyRow(
          icon: Icons.mail_outline,
          label: _email,
          copyValue: _email,
          tooltip: 'Copy email',
        ),
      ],
    );
  }
}

class _CopyRow extends StatefulWidget {
  const _CopyRow({
    required this.icon,
    required this.label,
    required this.copyValue,
    required this.tooltip,
  });
  final IconData icon;
  final String label;
  final String copyValue;
  final String tooltip;

  @override
  State<_CopyRow> createState() => _CopyRowState();
}

class _CopyRowState extends State<_CopyRow> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.copyValue));
    setState(() => _copied = true);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.hd;
    return Row(children: [
      Icon(widget.icon, size: 15, color: t.textMuted),
      const SizedBox(width: 8),
      Expanded(
        child: Text(widget.label,
            style: TextStyle(fontSize: 12, color: t.textSecondary)),
      ),
      GestureDetector(
        onTap: _copy,
        child: Tooltip(
          message: widget.tooltip,
          child: Icon(
            _copied ? Icons.check : Icons.copy_outlined,
            size: 15,
            color: _copied ? t.accent : t.textMuted,
          ),
        ),
      ),
    ]);
  }
}
