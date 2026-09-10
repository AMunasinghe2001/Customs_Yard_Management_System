import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import '../core/theme.dart';

/// One selectable option in a styled dropdown.
class StyledDropdownOption<T> {
  final T value;
  final String label;
  final bool enabled;
  const StyledDropdownOption(this.value, this.label, {this.enabled = true});
}

class _PickResult<T> {
  final bool isAll;
  final T? value;
  const _PickResult.all()
      : isAll = true,
        value = null;
  const _PickResult.of(this.value) : isAll = false;
}

/// Opens the shared styled popup anchored under [anchorContext]'s render box.
Future<_PickResult<T>?> _showStyledMenu<T>(
  BuildContext anchorContext, {
  required T? value,
  required String allLabel,
  required List<StyledDropdownOption<T>> options,
  required bool includeAll,
  required int columns,
  required int perPage,
  required double menuWidth,
  Color? accentColor,
}) async {
  final renderBox = anchorContext.findRenderObject() as RenderBox?;
  final overlayBox =
      Overlay.of(anchorContext).context.findRenderObject() as RenderBox?;
  if (renderBox == null || overlayBox == null) return null;

  final offset = renderBox.localToGlobal(Offset.zero, ancestor: overlayBox);
  // Match the popup width to the anchor button so the option cells fill the
  // whole width — no dead white space to the right of the list — but cap it so
  // a full-width form field doesn't open a page-wide, unbalanced menu.
  const double kMaxMenuWidth = 460;
  final anchorWidth = renderBox.size.width;
  final effectiveWidth =
      (menuWidth < anchorWidth ? anchorWidth : menuWidth)
          .clamp(0.0, kMaxMenuWidth);
  final position = RelativeRect.fromLTRB(
    offset.dx,
    offset.dy + renderBox.size.height + 6,
    overlayBox.size.width - offset.dx - renderBox.size.width,
    0,
  );

  return showMenu<_PickResult<T>>(
    context: anchorContext,
    position: position,
    color: anchorContext.colors.surfaceDark,
    elevation: 8,
    constraints: BoxConstraints.tightFor(width: effectiveWidth),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(color: anchorContext.colors.borderColor),
    ),
    items: [
      PopupMenuItem<_PickResult<T>>(
        enabled: false,
        padding: EdgeInsets.zero,
        child: _StyledDropdownContent<T>(
          value: value,
          allLabel: allLabel,
          options: options,
          columns: columns,
          perPage: perPage,
          includeAll: includeAll,
          menuWidth: effectiveWidth,
          accentColor: accentColor,
        ),
      ),
    ],
  );
}

/// App-wide filter dropdown styled like the Packages "All Years" picker:
/// an outlined button that opens an anchored card popup with gold-highlighted
/// option cells and pagination when there are many options.
/// Opens the app's own options popup under [anchorContext] and returns what
/// was picked, or null if it was dismissed.
Future<T?> showStyledOptionsMenu<T>(
  BuildContext anchorContext, {
  required List<StyledDropdownOption<T>> options,
  T? value,
  double menuWidth = 260,
  int columns = 1,
  int perPage = 8,
  Color? accentColor,
}) async {
  final picked = await _showStyledMenu<T>(
    anchorContext,
    value: value,
    allLabel: '',
    options: options,
    includeAll: false,
    columns: columns,
    perPage: perPage,
    menuWidth: menuWidth,
    accentColor: accentColor,
  );
  if (picked == null || picked.isAll) return null;
  return picked.value;
}

class StyledDropdownButton<T> extends StatelessWidget {
  final T? value;
  final String allLabel;
  final List<StyledDropdownOption<T>> options;
  final ValueChanged<T?> onChanged;
  final IconData icon;
  final int columns;
  final int perPage;
  final bool includeAll;
  final double menuWidth;

  /// Draw at the size and weight of the segmented filter chips beside it.
  ///
  /// ⚠️ The default is this button's own long-standing look -- 12pt text, an
  /// 8px radius, no fill. Beside the All / Destroyed / Pending chips, which
  /// are 13pt on a 10px radius with a tinted fill, it read as a smaller,
  /// paler control of a different kind. On a filter line they are the same
  /// KIND of thing and should look it.
  ///
  /// Opt-in, because most callers sit beside a search box rather than a chip
  /// and the smaller shape is right there.
  final bool chipStyle;

  /// The colour a chosen value is drawn in. Defaults to the app's gold; a
  /// directorate passes its own so the control belongs to its page.
  final Color? accentColor;

  const StyledDropdownButton({
    super.key,
    required this.value,
    required this.allLabel,
    required this.options,
    required this.onChanged,
    this.icon = Icons.filter_list_rounded,
    this.columns = 1,
    this.perPage = 8,
    this.includeAll = true,
    this.menuWidth = 300,
    this.chipStyle = false,
    this.accentColor,
  });

  String _currentLabel() {
    if (value == null) return allLabel;
    for (final o in options) {
      if (o.value == value) return o.label;
    }
    return '$value';
  }

  Future<void> _open(BuildContext context) async {
    final result = await _showStyledMenu<T>(
      context,
      value: value,
      allLabel: allLabel,
      options: options,
      includeAll: includeAll,
      columns: columns,
      perPage: perPage,
      menuWidth: menuWidth,
    );
    if (result == null) return;
    onChanged(result.isAll ? null : result.value);
  }

  @override
  Widget build(BuildContext context) {
    final selected = value != null;
    final accent = accentColor ?? context.colors.primaryGold;
    final fg = selected ? accent : context.colors.textSecondary;

    // ⚠️ The numbers below are the segmented filter chips' own, copied so the
    // two line up exactly: padding 14/8, radius 10, icon 15, gap 6, 13pt, and
    // a 0.15 fill behind a chosen value with a 0.6 border.
    if (chipStyle) {
      return Builder(builder: (btnContext) {
        return InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _open(btnContext),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: selected ? accent.withOpacity(0.15) : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: selected
                      ? accent.withOpacity(0.6)
                      : context.colors.borderColor),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 15, color: fg),
              const SizedBox(width: 6),
              Text(_currentLabel(),
                  style: TextStyle(
                      color: fg,
                      fontSize: 13,
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w500)),
              const SizedBox(width: 4),
              Icon(Icons.expand_more_rounded, size: 16, color: fg),
            ]),
          ),
        );
      });
    }

    return Builder(builder: (btnContext) {
      return OutlinedButton.icon(
        onPressed: () => _open(btnContext),
        icon: Icon(icon, size: 16, color: fg),
        label: Text(
          _currentLabel(),
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              color: fg,
              fontSize: 12,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal),
        ),
        style: OutlinedButton.styleFrom(
          side: BorderSide(
              color: selected ? accent : context.colors.borderColor),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    });
  }
}

/// Form-field variant: keeps the labelled/bordered form-field look but opens
/// the same styled popup. Wraps a [FormField] so it participates in Form
/// validation just like a DropdownButtonFormField.
class StyledDropdownFormField<T> extends StatelessWidget {
  final T? value;
  final String label;
  final List<StyledDropdownOption<T>> options;
  final ValueChanged<T?> onChanged;
  final String? Function(T?)? validator;
  final bool isDense;
  final String? helperText;
  final int columns;
  final int perPage;
  final double menuWidth;
  final Color? fillColor;
  final Widget? prefixIcon;

  /// ⚠️ Optional, and null keeps Material's default 48x48 tap target — which
  /// is what every other portal's dropdowns have always had, so the default
  /// must not change. A caller that puts this field in a row of short
  /// controls has to pass it: a 48px prefix box sets the decorator's
  /// INTRINSIC height to 48, and forcing that into a shorter box makes the
  /// border paint outside the box rather than shrink to it.
  final BoxConstraints? prefixIconConstraints;
  final EdgeInsetsGeometry? contentPadding;
  final TextStyle? valueStyle;
  final TextStyle? labelStyle;

  /// Corner radius of the tap/hover splash. Must match the radius of the
  /// [OutlineInputBorder] the caller themes this field with, or the splash
  /// shows through outside the drawn border. Defaults to the app-wide 12.
  final double splashRadius;

  /// How [label] behaves. The default floats it above the box, which makes the
  /// field TALLER than a plain [TextField] beside it — pass
  /// [FloatingLabelBehavior.never] on a filter row so both line up.
  final FloatingLabelBehavior? floatingLabelBehavior;

  final Color? accentColor;

  const StyledDropdownFormField({
    super.key,
    required this.value,
    required this.label,
    required this.options,
    required this.onChanged,
    this.validator,
    this.isDense = true,
    this.helperText,
    this.columns = 1,
    this.perPage = 8,
    this.menuWidth = 260,
    this.fillColor,
    this.prefixIcon,
    this.prefixIconConstraints,
    this.contentPadding,
    this.valueStyle,
    this.labelStyle,
    this.splashRadius = 12,
    this.floatingLabelBehavior,
    this.accentColor,
  });

  String _selectedLabel() {
    if (value == null) return '';
    for (final o in options) {
      if (o.value == value) return o.label;
    }
    return '$value';
  }

  @override
  Widget build(BuildContext context) {
    return FormField<T>(
      initialValue: value,
      validator: validator,
      builder: (field) {
        // Keep the FormField's value synced with the external source of truth.
        if (field.value != value) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (field.mounted) field.didChange(value);
          });
        }
        return Builder(builder: (btnContext) {
          return InkWell(
            borderRadius: BorderRadius.circular(splashRadius),
            onTap: () async {
              final picked = await _showStyledMenu<T>(
                btnContext,
                value: value,
                allLabel: '',
                options: options,
                includeAll: false,
                columns: columns,
                perPage: perPage,
                menuWidth: menuWidth,
                accentColor: accentColor,
              );
              if (picked == null) return;
              final v = picked.isAll ? null : picked.value;
              field.didChange(v);
              onChanged(v);
            },
            child: InputDecorator(
              isEmpty: value == null,
              decoration: InputDecoration(
                labelText: label,
                labelStyle: labelStyle ?? const TextStyle(fontSize: 12),
                floatingLabelBehavior: floatingLabelBehavior,
                isDense: isDense,
                helperText: (helperText == null || helperText!.trim().isEmpty)
                    ? null
                    : helperText,
                filled: fillColor != null,
                fillColor: fillColor,
                errorText: field.errorText,
                prefixIcon: prefixIcon,
                prefixIconConstraints: prefixIconConstraints,
                contentPadding: contentPadding ??
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                suffixIcon: Icon(Icons.arrow_drop_down_rounded,
                    color: accentColor ?? context.colors.primaryGold, size: 24),
                // maxHeight caps the 24px arrow so it cannot make the box
                // taller than a plain TextField with the same contentPadding —
                // without it a dropdown beside a search field sits lower.
                suffixIconConstraints:
                    const BoxConstraints(minWidth: 32, maxHeight: 24),
              ),
              child: Text(
                _selectedLabel(),
                style: valueStyle ??
                    TextStyle(
                        fontSize: 13, color: context.colors.textPrimary),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          );
        });
      },
    );
  }
}

class _StyledDropdownContent<T> extends StatefulWidget {
  final T? value;
  final String allLabel;
  final List<StyledDropdownOption<T>> options;
  final int columns;
  final int perPage;
  final bool includeAll;
  final double menuWidth;
  final Color? accentColor;

  const _StyledDropdownContent({
    required this.value,
    required this.allLabel,
    required this.options,
    required this.columns,
    required this.perPage,
    required this.includeAll,
    required this.menuWidth,
    this.accentColor,
  });

  @override
  State<_StyledDropdownContent<T>> createState() =>
      _StyledDropdownContentState<T>();
}

class _StyledDropdownContentState<T>
    extends State<_StyledDropdownContent<T>> {
  int _page = 0;

  static const int _searchAbove = 8;

  final _searchCtrl = TextEditingController();
  String _query = '';

  bool get _searchable => widget.options.length > _searchAbove;

  List<StyledDropdownOption<T>> get _filtered {
    if (_query.trim().isEmpty) return widget.options;
    final q = _query.trim().toLowerCase();
    return widget.options
        .where((o) => o.label.toLowerCase().contains(q))
        .toList();
  }

  @override
  void initState() {
    super.initState();
    if (widget.value != null) {
      final idx =
          widget.options.indexWhere((o) => o.value == widget.value);
      if (idx >= 0) _page = idx ~/ widget.perPage;
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final effectiveAccent = widget.accentColor ?? context.colors.primaryGold;
    final options = _filtered;
    final totalPages =
        (options.length / widget.perPage).ceil().clamp(1, 9999);
    final page = _page.clamp(0, totalPages - 1);
    final start = page * widget.perPage;
    final pageOptions = options.skip(start).take(widget.perPage).toList();

    final innerWidth = widget.menuWidth - 24;
    final cellWidth = widget.columns <= 1
        ? innerWidth
        : (innerWidth - (widget.columns - 1) * 8) / widget.columns;

    return SizedBox(
      width: widget.menuWidth,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_searchable) ...[
              SizedBox(
                width: innerWidth,
                child: TextField(
                  controller: _searchCtrl,
                  autofocus: true,
                  style: TextStyle(
                      color: context.colors.textPrimary, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Type to search\u2026',
                    hintStyle: TextStyle(
                      color: context.colors.textMuted, fontSize: 13),
                    prefixIcon: Icon(Icons.search_rounded,
                        size: 18, color: effectiveAccent),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            icon: Icon(Icons.clear_rounded,
                                size: 16, color: context.colors.textMuted),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() {
                                _query = '';
                                _page = 0;
                              });
                            },
                          ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide:
                            BorderSide(color: context.colors.borderColor)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide:
                            BorderSide(color: context.colors.borderColor)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                            color: effectiveAccent, width: 1.5)),
                  ),
                  onChanged: (v) => setState(() {
                    _query = v;
                    _page = 0;
                  }),
                ),
              ),
              const Gap(10),
            ],
            if (widget.includeAll) ...[
              _StyledDropdownCell(
                label: widget.allLabel,
                isSelected: widget.value == null,
                enabled: true,
                width: innerWidth,
                accentColor: effectiveAccent,
                onTap: () =>
                    Navigator.pop(context, _PickResult<T>.all()),
              ),
              const Gap(10),
            ],
            if (pageOptions.isEmpty)
              SizedBox(
                width: innerWidth,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: Text('No match for that search',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: context.colors.textMuted, fontSize: 12.5)),
                ),
              ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: pageOptions
                  .map((o) => _StyledDropdownCell(
                        label: o.label,
                        isSelected: o.value == widget.value,
                        enabled: o.enabled,
                        width: cellWidth,
                        accentColor: effectiveAccent,
                        onTap: o.enabled
                            ? () => Navigator.pop(
                                context, _PickResult<T>.of(o.value))
                            : null,
                      ))
                  .toList(),
            ),
            if (totalPages > 1) ...[
              const Gap(10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left_rounded, size: 20),
                    tooltip: 'Previous',
                    visualDensity: VisualDensity.compact,
                    color: page > 0
                        ? effectiveAccent
                        : context.colors.textMuted.withOpacity(0.4),
                    onPressed:
                        page > 0 ? () => setState(() => _page = page - 1) : null,
                  ),
                  Text('${page + 1} / $totalPages',
                      style: TextStyle(
                          color: context.colors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                  IconButton(
                    icon: const Icon(Icons.chevron_right_rounded, size: 20),
                    tooltip: 'Next',
                    visualDensity: VisualDensity.compact,
                    color: page < totalPages - 1
                        ? effectiveAccent
                        : context.colors.textMuted.withOpacity(0.4),
                    onPressed: page < totalPages - 1
                        ? () => setState(() => _page = page + 1)
                        : null,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StyledDropdownCell extends StatelessWidget {
  final String label;
  final bool isSelected;
  final bool enabled;
  final double width;
  final VoidCallback? onTap;
  final Color? accentColor;

  const _StyledDropdownCell({
    required this.label,
    required this.isSelected,
    required this.enabled,
    required this.width,
    required this.onTap,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveAccent = accentColor ?? context.colors.primaryGold;
    final Color textColor = !enabled
        ? context.colors.textMuted
        : (isSelected ? effectiveAccent : context.colors.textSecondary);
    return SizedBox(
      width: width,
      height: 40,
      child: Material(
        color: isSelected && enabled
            ? effectiveAccent.withOpacity(0.15)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected && enabled
                    ? effectiveAccent.withOpacity(0.6)
                    : context.colors.borderColor,
              ),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: textColor,
                fontSize: 13,
                fontWeight: isSelected && enabled
                    ? FontWeight.bold
                    : FontWeight.w500,
                decoration: !enabled ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
