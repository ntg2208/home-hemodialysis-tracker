import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/theme.dart';

String _fmt(num? v) {
  if (v == null) return '';
  if (v == v.roundToDouble()) return v.toInt().toString();
  return v.toString();
}

/// Labelled numeric input. Port of frontend NumberField, including the behaviour
/// the auto-fill pattern depends on: when the parent feeds a new derived [value]
/// (and the user hasn't typed since), the displayed text updates to match.
///
/// [textInputAction] defaults to [TextInputAction.next] so pressing the keyboard
/// action key moves focus to the next field instead of closing the keyboard.
/// [suffix] can be used for an "AUTO" badge or similar overlay inside the field.
class NumberField extends StatefulWidget {
  const NumberField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.integer = false,
    this.required = false,
    this.textInputAction = TextInputAction.next,
    this.suffix,
  });

  final String label;
  final num? value;
  final ValueChanged<num?> onChanged;
  final bool integer;
  final bool required;
  final TextInputAction textInputAction;
  final Widget? suffix;

  @override
  State<NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<NumberField> {
  late final TextEditingController _c =
      TextEditingController(text: _fmt(widget.value));
  final _focus = FocusNode();

  @override
  void didUpdateWidget(NumberField old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && _parse(_c.text) != widget.value) {
      _c.text = _fmt(widget.value);
    }
  }

  num? _parse(String raw) {
    if (raw.isEmpty) return null;
    // iOS decimal keypads on comma-locale devices emit ',' as the decimal
    // separator; normalize it so num.tryParse (which only accepts '.') works.
    final normalized = raw.replaceAll(',', '.');
    return widget.integer ? int.tryParse(normalized) : num.tryParse(normalized);
  }

  @override
  void dispose() {
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.hd;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text.rich(
            TextSpan(
              text: widget.label,
              style: TextStyle(fontSize: 13, color: t.textSecondary),
              children: widget.required
                  ? [TextSpan(text: ' *', style: TextStyle(color: t.danger))]
                  : null,
            ),
          ),
        ),
        TextField(
          controller: _c,
          focusNode: _focus,
          keyboardType: TextInputType.numberWithOptions(
              decimal: !widget.integer, signed: true),
          inputFormatters: widget.integer
              ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9-]'))]
              // Allow ',' as well as '.' — comma-locale iOS keypads emit ',' for
              // the decimal key; _parse normalizes it. Without this the decimal
              // key is silently dropped and decimals can't be entered.
              : [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\-]'))],
          textInputAction: widget.textInputAction,
          style: TextStyle(
              fontSize: 18,
              color: t.textPrimary,
              fontFeatures: const [FontFeature.tabularFigures()]),
          decoration: InputDecoration(suffix: widget.suffix),
          onChanged: (raw) => widget.onChanged(_parse(raw)),
          onSubmitted: (_) => _focus.nextFocus(),
        ),
      ],
    );
  }
}

/// Small "AUTO" badge shown inside a NumberField suffix when a value is derived.
class AutoBadge extends StatelessWidget {
  const AutoBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.hd;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: t.accent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text('AUTO',
          style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: t.accent)),
    );
  }
}
