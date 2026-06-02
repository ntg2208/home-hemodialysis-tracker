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
class NumberField extends StatefulWidget {
  const NumberField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.integer = false,
    this.required = false,
  });

  final String label;
  final num? value;
  final ValueChanged<num?> onChanged;
  final bool integer;
  final bool required;

  @override
  State<NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<NumberField> {
  late final TextEditingController _c = TextEditingController(text: _fmt(widget.value));
  final _focus = FocusNode();

  @override
  void didUpdateWidget(NumberField old) {
    super.didUpdateWidget(old);
    // Sync external (derived) value into the field, but never while the user is
    // actively editing it.
    if (!_focus.hasFocus && _parse(_c.text) != widget.value) {
      _c.text = _fmt(widget.value);
    }
  }

  num? _parse(String raw) {
    if (raw.isEmpty) return null;
    return widget.integer ? int.tryParse(raw) : num.tryParse(raw);
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
          child: RichText(
            text: TextSpan(
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
              : [FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]'))],
          style: TextStyle(
              fontSize: 18, color: t.textPrimary, fontFeatures: const [
            FontFeature.tabularFigures(),
          ]),
          onChanged: (raw) => widget.onChanged(_parse(raw)),
        ),
      ],
    );
  }
}
