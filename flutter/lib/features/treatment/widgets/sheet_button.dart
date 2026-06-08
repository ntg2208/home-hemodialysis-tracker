import 'package:flutter/material.dart';

import '../../../app/theme.dart';

/// Pill-shaped sheet action button. [accent] = cyan fill; otherwise dark fill.
class SheetButton extends StatelessWidget {
  const SheetButton({
    super.key,
    required this.label,
    required this.onPressed,
    required this.accent,
    this.icon,
    this.loading = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool accent;
  final IconData? icon;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final t = context.hd;
    final bg = accent ? t.accent : t.panel;
    final fg = accent ? t.accentOn : t.textPrimary;
    return GestureDetector(
      onTap: onPressed,
      child: AnimatedOpacity(
        opacity: onPressed == null ? 0.5 : 1.0,
        duration: const Duration(milliseconds: 150),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(999),
            border: accent ? null : Border.all(color: t.border),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (loading)
                SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: fg))
              else if (icon != null) ...[
                Icon(icon, size: 16, color: fg),
                const SizedBox(width: 6),
              ],
              Text(label,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}
