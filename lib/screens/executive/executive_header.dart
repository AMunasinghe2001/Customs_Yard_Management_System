import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../core/theme.dart';
import '../../core/yards.dart';
import '../../widgets/styled_dropdown.dart';

/// The header controls every High Panel tab shares, so each page carries the
/// same search box, yard dropdown and filter chips in the same order:
///
///     Title
///     subtitle  ...........  [ Search ]  [ Yard ▾ ]
///     [ All ] [ chip ] [ chip ]
///
/// They live here rather than inside one tab so a page kept in its own file
/// (Financials) uses the SAME controls, not a lookalike that drifts out of
/// step with the rest of the portal.

/// Shared content padding for the header's search field and yard dropdown.
/// BOTH controls derive their height from this, so they render at exactly the
/// same size and sit on one line. Do not set an explicit height on either —
/// the dropdown's InkWell fills whatever box it is given and its hover splash
/// would spill past the drawn border.
const EdgeInsets kExecutiveFilterPadding =
    EdgeInsets.symmetric(horizontal: 12, vertical: 14);

/// The search box every High Panel tab uses.
///
/// Its [kExecutiveFilterPadding] is what gives it the same height as the yard
/// dropdown beside it — never set an explicit height, or the two controls end
/// up on different levels.
class ExecutiveSearchField extends StatelessWidget {
  final String hint;
  final ValueChanged<String> onChanged;
  final double width;

  const ExecutiveSearchField({
    super.key,
    required this.hint,
    required this.onChanged,
    this.width = 300,
  });

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.executiveTeal;
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: c, width: w));

    return SizedBox(
      width: width,
      child: TextField(
        onChanged: onChanged,
        style: TextStyle(
            color: context.colors.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          isDense: true,
          // IDENTICAL padding to the yard dropdown beside it — both controls
          // take their height from this.
          contentPadding: kExecutiveFilterPadding,
          hintText: hint,
          prefixIcon: Icon(Icons.search_rounded, size: 20, color: accent),
          filled: true,
          fillColor: accent.withOpacity(0.06),
          border: border(accent.withOpacity(0.4)),
          enabledBorder: border(accent.withOpacity(0.4)),
          focusedBorder: border(accent, 1.5),
        ),
      ),
    );
  }
}

class ExecutiveYardFilter extends StatelessWidget {
  final String? value;
  final ValueChanged<String?> onChanged;
  const ExecutiveYardFilter({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.executiveTeal;
    // Width comes from the caller; the height comes from contentPadding, so
    // the tap target matches the drawn field exactly and the hover splash
    // stays inside the border.
    return Theme(
        data: Theme.of(context).copyWith(
          inputDecorationTheme: Theme.of(context).inputDecorationTheme.copyWith(
                filled: true,
                fillColor: accent.withOpacity(0.06),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: accent.withOpacity(0.4))),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: accent.withOpacity(0.4))),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: accent, width: 1.5)),
              ),
        ),
        child: StyledDropdownFormField<String>(
          label: 'Yard',
          // Keeps the box the same height as the search field beside it.
          floatingLabelBehavior: FloatingLabelBehavior.never,
          value: value ?? '_all',
          helperText: null,
          isDense: true,
          menuWidth: 220,
          // Same radius as the OutlineInputBorder above, so the hover splash
          // stays inside the drawn border instead of showing at the corners.
          splashRadius: 14,
          // MUST match the search field's padding exactly — this is what sets
          // the height, and a 2px difference here is what put the two controls
          // on different levels.
          contentPadding: kExecutiveFilterPadding,
          prefixIcon: Icon(Icons.warehouse_rounded, color: accent, size: 20),
          options: [
            const StyledDropdownOption('_all', 'All Yards'),
            ...kYards.map((y) => StyledDropdownOption(y.code, y.name)),
          ],
          onChanged: (v) => onChanged((v == null || v == '_all') ? null : v),
        ));
  }
}

Widget executiveFilterChip(
  BuildContext context, {
  required String label,
  required bool selected,
  required VoidCallback onTap,
  IconData? icon,
  Color? colour,
}) {
  final c = colour ?? AppTheme.executiveTeal;
  return Material(
    color: Colors.transparent,
    child: InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? c.withOpacity(0.14) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected ? c.withOpacity(0.6) : context.colors.borderColor,
              width: selected ? 1.4 : 1),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[
            Icon(icon,
                size: 14, color: selected ? c : context.colors.textMuted),
            const Gap(6),
          ],
          Text(label,
              style: TextStyle(
                  color: selected ? c : context.colors.textSecondary,
                  fontSize: 12.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600)),
        ]),
      ),
    ),
  );
}
