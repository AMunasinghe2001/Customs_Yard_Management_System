import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';

import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../core/yards.dart';
import '../../widgets/styled_dropdown.dart';

/// The header widgets every Central Disposal tab shares, so each page carries
/// the same search box, yard dropdown and count chip in the same order:
///
///     Title  ...............  [ Search ]  [ Yard ▾ ]
///     [ N  label ]
///
/// They live here rather than inside the dashboard so a tab kept in its own
/// file (Taxes, Expenses) uses the SAME widgets, not a lookalike that drifts
/// out of step with the rest of the portal.

// Per-tab search query (keyed by tab name).
final disposalSearchProvider =
    StateProvider.family<String, String>((ref, key) => '');

// Per-tab yard filter (null = All Yards) for the cross-yard list tabs.
final disposalYardFilterProvider =
    StateProvider.family<String?, String>((ref, key) => null);

/// Styled search box shared by every Central Disposal tab.
class DisposalSearch extends ConsumerStatefulWidget {
  final String tabKey;
  final String hint;
  final double width;
  const DisposalSearch(
      {required this.tabKey, this.hint = 'Search…', this.width = 300});
  @override
  ConsumerState<DisposalSearch> createState() => DisposalSearchState();
}

class DisposalSearchState extends ConsumerState<DisposalSearch> {
  late final TextEditingController _c;

  @override
  void initState() {
    super.initState();
    _c = TextEditingController(
        text: ref.read(disposalSearchProvider(widget.tabKey)));
  }

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: c, width: w));
    return SizedBox(
      width: widget.width,
      child: TextField(
        controller: _c,
        style: TextStyle(
            color: context.colors.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w600),
        onChanged: (v) {
          ref.read(disposalSearchProvider(widget.tabKey).notifier).state = v;
          setState(() {});
        },
        decoration: InputDecoration(
          isDense: true,
          hintText: widget.hint,
          hintStyle:
              TextStyle(color: context.colors.textSecondary, fontSize: 13),
          prefixIcon: Icon(Icons.search_rounded,
              size: 20, color: context.colors.primaryGold),
          suffixIcon: _c.text.isEmpty
              ? null
              : IconButton(
                  splashRadius: 16,
                  icon: Icon(Icons.close_rounded,
                      size: 16, color: context.colors.textMuted),
                  onPressed: () {
                    _c.clear();
                    ref
                        .read(disposalSearchProvider(widget.tabKey).notifier)
                        .state = '';
                    setState(() {});
                  },
                ),
          filled: true,
          fillColor: context.colors.primaryGold.withOpacity(0.06),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 13.5),
          border: border(context.colors.primaryGold.withOpacity(0.4)),
          enabledBorder: border(context.colors.primaryGold.withOpacity(0.4)),
          focusedBorder: border(context.colors.primaryGold, 1.5),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }
}

/// Yard dropdown with an "All Yards" option, bound to a provided value/onChanged.
/// Used by tabs that filter their own (cross-yard) list locally.
///
/// [value] / the string [onChanged] reports is a [YardFilterOption.value]:
/// a bare yard code, or `"<yard>|<directorate>"` for one entry of a
/// multi-directorate yard (e.g. "NNR|CED", shown as "CED/NNR"). Apply it to a
/// row with [matchesYardFilter], never a bare `==` on `yard` — a split entry
/// also has to match the row's SR-number directorate prefix.
class YardAllFilter extends ConsumerWidget {
  final String? value; // null = all
  final ValueChanged<String?> onChanged;
  const YardAllFilter({required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final optionsAsync = ref.watch(yardFilterOptionsProvider);
    // ICT-maintained list; kYards is only the offline fallback while it loads
    // or a query fails, so the dropdown is never empty.
    final options = optionsAsync.valueOrNull ??
        [for (final y in kYards) YardFilterOption(value: y.code, label: y.name, filterYard: y.code)];
    return SizedBox(
      width: 220,
      child: Theme(
        data: Theme.of(context).copyWith(
          inputDecorationTheme: Theme.of(context).inputDecorationTheme.copyWith(
                filled: true,
                fillColor: context.colors.primaryGold.withOpacity(0.06),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                        color: context.colors.primaryGold.withOpacity(0.4))),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                        color: context.colors.primaryGold.withOpacity(0.4))),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                        color: context.colors.primaryGold, width: 1.5)),
              ),
        ),
        child: StyledDropdownFormField<String>(
          value: value ?? '_all',
          label: 'Yard',
          helperText: null,
          isDense: true,
          menuWidth: 220,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 13.5),
          prefixIcon: Icon(Icons.warehouse_rounded,
              color: context.colors.primaryGold, size: 20),
          options: [
            const StyledDropdownOption('_all', 'All Yards'),
            for (final o in options) StyledDropdownOption(o.value, o.label),
          ],
          onChanged: (v) => onChanged((v == null || v == '_all') ? null : v),
        ),
      ),
    );
  }
}

class StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const StatChip(
      {required this.label, required this.value, required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(value,
            style: TextStyle(
                color: color, fontSize: 14, fontWeight: FontWeight.w800)),
        const Gap(6),
        Text(label,
            style: TextStyle(
                color: context.colors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
      ]),
    );
  }
}
