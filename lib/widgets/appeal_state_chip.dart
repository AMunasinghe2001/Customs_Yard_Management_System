import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import '../core/theme.dart';
import '../models/models.dart';

/// Whether goods are still inside their 30-day appeal window, shown on the
/// yard's status tables (Abandoned / Other / Forfeited).
///
/// The window applies to EVERY status, not just forfeit: while it is open the
/// owner can still appeal, so nothing may be disposed of and no disposal
/// request can be sent to Central Disposal. Once it closes the goods become
/// actionable.
///
/// The clock runs from the goods' ENTRY DATE — see [isWithinAppealWindow].
class AppealStateChip extends StatelessWidget {
  /// When the goods entered the yard. Used when there is no explicit
  /// [deadline] — the window is then entryDate + 30 days.
  final DateTime? entryDate;

  /// An already-recorded deadline, which WINS over [entryDate].
  ///
  /// A genuine forfeit stores its own `appeal_deadline` (forfeited_at + 30
  /// days), and that is later than entry + 30. Deriving from the entry date
  /// there would show a live appeal as "Enabled".
  final DateTime? deadline;

  /// What the Appeal Directorate has ruled, when it has ruled.
  ///
  /// A DECISION ends the wait early: the goods become actionable the moment it
  /// is recorded, without sitting out the remaining days. A HOLD does the
  /// opposite and keeps them frozen even after the deadline passes. Null means
  /// no appeal has touched these goods, so the window alone decides.
  final ItemAppealOutcome? outcome;

  const AppealStateChip(
      {super.key, required this.entryDate, this.deadline, this.outcome});

  @override
  Widget build(BuildContext context) {
    final end =
        deadline ?? (entryDate == null ? null : appealDeadlineFrom(entryDate!));
    if (end == null) {
      return Text('—', style: TextStyle(color: context.colors.textMuted));
    }

    final diff = end.difference(DateTime.now()).inDays;
    final days = diff < 0 ? 0 : diff + 1;

    // A ruling overrides the calendar in both directions.
    final decided = outcome?.unblocksAction ?? false;
    final held = outcome?.onHold ?? false;
    final open = DateTime.now().isBefore(end) && !decided;

    final Color colour;
    final String label;
    final IconData icon;
    final String tip;
    if (held) {
      colour = context.colors.warningAmber;
      label = 'On Appeal Hold';
      icon = Icons.pan_tool_rounded;
      tip = 'An appeal is lodged and still under review. No action can be '
          'taken until the Appeal Directorate rules — the deadline does not '
          'release it.';
    } else if (decided) {
      colour = context.colors.accentLightBlue;
      label = 'Decided · ${outcome!.decision}';
      icon = Icons.gavel_rounded;
      tip = 'The Appeal Directorate decided: ${outcome!.decision}. '
          'Actions are enabled now — the 30-day window no longer applies.';
    } else if (open) {
      colour = context.colors.warningAmber;
      label = 'Appealing · ${days}d';
      icon = Icons.gavel_rounded;
      tip = 'In the 30-day appeal window — $days day'
          '${days == 1 ? '' : 's'} left. No action can be taken and it '
          'cannot be sent to Central Disposal yet.\n'
          'Window closes ${_fmt(end)}.';
    } else {
      colour = context.colors.successGreen;
      label = 'Enabled';
      icon = Icons.check_circle_rounded;
      tip = 'The 30-day appeal window closed on '
          '${_fmt(end)} — actions are enabled.';
    }

    return Tooltip(
      message: tip,
      waitDuration: const Duration(milliseconds: 300),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: colour.withOpacity(0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colour.withOpacity(0.4)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: colour),
          const Gap(5),
          Flexible(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: colour, fontSize: 11, fontWeight: FontWeight.w700)),
          ),
        ]),
      ),
    );
  }

  static String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
