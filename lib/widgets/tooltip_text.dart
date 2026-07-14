import 'package:flutter/material.dart';

/// A drop-in replacement for [Text] used inside table cells: it renders the
/// same ellipsised text but shows the FULL value in a tooltip on hover, so
/// cropped column data can always be read. Mirrors the common [Text] params
/// used in cells (style / overflow / maxLines / textAlign / softWrap).
class TooltipText extends StatelessWidget {
  final String data;
  final TextStyle? style;
  final TextOverflow? overflow;
  final int? maxLines;
  final TextAlign? textAlign;
  final bool? softWrap;

  const TooltipText(
    this.data, {
    super.key,
    this.style,
    this.overflow,
    this.maxLines,
    this.textAlign,
    this.softWrap,
  });

  @override
  Widget build(BuildContext context) {
    final text = Text(
      data,
      style: style,
      overflow: overflow ?? TextOverflow.ellipsis,
      maxLines: maxLines,
      textAlign: textAlign,
      softWrap: softWrap,
    );
    final msg = data.trim();
    // No point in a tooltip for empty / placeholder cells.
    if (msg.isEmpty || msg == '—' || msg == '-') return text;
    return Tooltip(
      message: msg,
      waitDuration: const Duration(milliseconds: 300),
      child: text,
    );
  }
}
