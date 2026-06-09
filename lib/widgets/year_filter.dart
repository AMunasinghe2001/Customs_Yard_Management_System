import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import '../core/theme.dart';
import 'styled_dropdown.dart';

final RegExp _srYearRegex = RegExp(r'/(\d{4})$');

/// Unique 4-digit years parsed from the trailing "/YYYY" of SR numbers,
/// sorted newest-first. Used to populate the "All Years" filter.
List<String> srYears(Iterable<String> srNumbers) {
  return srNumbers
      .map((s) => _srYearRegex.firstMatch(s)?.group(1))
      .whereType<String>()
      .toSet()
      .toList()
    ..sort((a, b) => b.compareTo(a));
}

/// True when [sr]'s trailing year equals [year]. A null [year] means "all".
bool srYearMatches(String sr, String? year) {
  if (year == null) return true;
  final m = _srYearRegex.firstMatch(sr);
  return m != null && m.group(1) == year;
}

/// "All Years" dropdown + clear button, matching the Package History page.
/// [onChanged] receives the selected year, or null when cleared / "All Years".
class YearFilterButton extends StatelessWidget {
  final String? value;
  final List<String> years;
  final ValueChanged<String?> onChanged;

  const YearFilterButton({
    super.key,
    required this.value,
    required this.years,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        StyledDropdownButton<String>(
          value: value,
          allLabel: 'All Years',
          icon: Icons.calendar_today_rounded,
          columns: 2,
          options: years.map((y) => StyledDropdownOption(y, y)).toList(),
          onChanged: onChanged,
        ),
        if (value != null) ...[
          const Gap(8),
          IconButton(
            icon: Icon(Icons.clear_rounded,
                size: 16, color: context.colors.dangerRed),
            onPressed: () => onChanged(null),
            tooltip: 'Clear Year Filter',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ],
    );
  }
}
