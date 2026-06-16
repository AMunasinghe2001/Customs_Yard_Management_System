import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:data_table_2/data_table_2.dart';
import '../../core/theme.dart';
import '../../core/providers.dart';
import '../../core/yards.dart';
import '../../models/models.dart';
import '../../services/services.dart';
import '../../widgets/error_view.dart';
import '../../widgets/empty_table_state.dart';
import '../../widgets/package_details_dialog.dart';
import '../../widgets/disposal_profile_dialog.dart';
import '../../widgets/styled_dropdown.dart';

final _appealSearchProvider = StateProvider<String>((ref) => '');
final _appealYardProvider = StateProvider<String?>((ref) => null); // null = all

/// Appeal Directorate dashboard: a cross-yard list of forfeited packages, where
/// the directorate can place / lift an appeal hold while the 30-day window is
/// still open. A held package can no longer be sold or destroyed.
class AppealDashboardScreen extends ConsumerWidget {
  const AppealDashboardScreen({super.key});

  String _itemName(ForfeitedPackageModel f) {
    final items = f.packageDetails?.items ?? const [];
    if (items.isEmpty) return 'Multiple/Unspecified';
    if (items.length == 1) return items.first.itemName;
    return '${items.first.itemName} +${items.length - 1}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = context.colors.accentBlue;
    final profile = ref.watch(currentProfileProvider);
    final async = ref.watch(appealForfeitedPackagesProvider);
    final storageRate = ref.watch(storageRateProvider).valueOrNull ??
        {DateTime(2020, 1, 1): 50.0};

    return Scaffold(
      backgroundColor: context.colors.scaffoldBg,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Top bar ──────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [accent.withOpacity(0.08), context.colors.cardDark],
              ),
              border: Border(
                  bottom: BorderSide(color: context.colors.borderColor)),
            ),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: accent.withOpacity(0.3)),
                ),
                child: SvgPicture.asset('Sri_Lanka_Customs_logo_tinted.svg',
                    width: 30, height: 30, theme: SvgTheme(currentColor: accent)),
              ),
              const Gap(14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Appeal Directorate',
                      style: TextStyle(
                          color: context.colors.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.w800)),
                  Text('Review forfeited packages · hold appeals before disposal',
                      style: TextStyle(
                          color: context.colors.textMuted, fontSize: 12)),
                ],
              ),
              const Spacer(),
              if (profile != null)
                Tooltip(
                  message: 'View profile',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () => showDialog(
                      context: context,
                      builder: (_) => DisposalProfileDialog(accent: accent),
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: accent.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: accent.withOpacity(0.35)),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.balance_rounded, color: accent, size: 16),
                        const Gap(8),
                        Text(profile.fullName,
                            style: TextStyle(
                                color: accent,
                                fontWeight: FontWeight.w700,
                                fontSize: 13)),
                        const Gap(6),
                        Icon(Icons.chevron_right_rounded,
                            color: accent.withOpacity(0.7), size: 16),
                      ]),
                    ),
                  ),
                ),
              const Gap(8),
              IconButton(
                tooltip: 'Toggle theme',
                icon: Icon(
                    ref.watch(themeModeProvider) == ThemeMode.dark
                        ? Icons.light_mode_rounded
                        : Icons.dark_mode_rounded,
                    color: context.colors.textPrimary),
                onPressed: () {
                  final isDark = ref.read(themeModeProvider) == ThemeMode.dark;
                  ref.read(themeModeProvider.notifier).state =
                      isDark ? ThemeMode.light : ThemeMode.dark;
                },
              ),
              const Gap(4),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.colors.dangerRed,
                  side: BorderSide(
                      color: context.colors.dangerRed.withOpacity(0.5)),
                ),
                icon: const Icon(Icons.logout_rounded, size: 16),
                label: const Text('Sign Out'),
                onPressed: () async {
                  await ref.read(authServiceProvider).signOut();
                  ref.read(currentProfileProvider.notifier).state = null;
                  if (context.mounted) context.go('/');
                },
              ),
            ]),
          ).animate().fadeIn(duration: 350.ms).slideY(begin: -0.15),

          // ── Body ─────────────────────────────────────────────
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text('Forfeited Packages',
                        style: TextStyle(
                            color: context.colors.textPrimary,
                            fontSize: 22,
                            fontWeight: FontWeight.w700)),
                    const Spacer(),
                    SizedBox(
                      width: 320,
                      child: TextField(
                        onChanged: (v) => ref
                            .read(_appealSearchProvider.notifier)
                            .state = v,
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: 'Search SR / item / consignee…',
                          prefixIcon:
                              const Icon(Icons.search_rounded, size: 18),
                          filled: true,
                          fillColor: accent.withOpacity(0.06),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide:
                                  BorderSide(color: accent.withOpacity(0.4))),
                          enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide:
                                  BorderSide(color: accent.withOpacity(0.4))),
                          focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide:
                                  BorderSide(color: accent, width: 1.5)),
                        ),
                      ),
                    ),
                    const Gap(12),
                    _AppealYardFilter(
                      accent: accent,
                      value: ref.watch(_appealYardProvider),
                      onChanged: (v) =>
                          ref.read(_appealYardProvider.notifier).state = v,
                    ),
                  ]).animate().fadeIn(duration: 300.ms),
                  const Gap(14),
                  // Stat chips
                  async.maybeWhen(
                    data: (list) {
                      final held = list.where((f) => f.isAppealHeld).length;
                      final openWindow = list
                          .where((f) => !f.isAppealExpired && !f.isAppealHeld)
                          .length;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Row(children: [
                          _StatChip(
                              label: 'Total',
                              value: '${list.length}',
                              color: context.colors.accentLightBlue),
                          const Gap(12),
                          _StatChip(
                              label: 'In Appeal Window',
                              value: '$openWindow',
                              color: context.colors.successGreen),
                          const Gap(12),
                          _StatChip(
                              label: 'On Appeal Hold',
                              value: '$held',
                              color: context.colors.warningAmber),
                        ]),
                      ).animate().fadeIn(duration: 300.ms);
                    },
                    orElse: () => const SizedBox.shrink(),
                  ),
                  Expanded(
                    child: async.when(
                      skipLoadingOnReload: true,
                      loading: () =>
                          Center(child: CircularProgressIndicator(color: accent)),
                      error: (e, _) => ErrorView(
                          error: e,
                          onRetry: () =>
                              ref.refresh(appealForfeitedPackagesProvider)),
                      data: (list) {
                        final q = ref
                            .watch(_appealSearchProvider)
                            .toLowerCase();
                        final yard = ref.watch(_appealYardProvider);
                        var rows = list;
                        if (yard != null) {
                          rows =
                              rows.where((f) => f.yard == yard).toList();
                        }
                        if (q.isNotEmpty) {
                          rows = rows
                              .where((f) =>
                                  f.srNumber.toLowerCase().contains(q) ||
                                  f.consigneeName.toLowerCase().contains(q) ||
                                  _itemName(f).toLowerCase().contains(q))
                              .toList();
                        }
                        return _listCard(
                          context,
                          DataTable2(
                            columnSpacing: 12,
                            horizontalMargin: 16,
                            fixedTopRows: 1,
                            minWidth: 1000,
                            empty: const EmptyTableState(
                                message: 'No forfeited packages'),
                            headingRowColor: WidgetStateProperty.all(
                                context.colors.surfaceDark),
                            columns: const [
                              DataColumn2(
                                  label: Text('SR Number'), size: ColumnSize.M),
                              DataColumn2(
                                  label: Text('Item'), size: ColumnSize.M),
                              DataColumn2(
                                  label: Text('Consignee'), size: ColumnSize.M),
                              DataColumn2(
                                  label: Text('Yard'),
                                  size: ColumnSize.S,
                                  fixedWidth: 110),
                              DataColumn2(
                                  label: Text('Appeal Deadline'),
                                  size: ColumnSize.S),
                              DataColumn2(
                                  label: Text('Status'),
                                  size: ColumnSize.S,
                                  fixedWidth: 140),
                              DataColumn2(
                                  label: Center(child: Text('Details')),
                                  size: ColumnSize.S,
                                  fixedWidth: 70),
                            ],
                            rows: rows
                                .map((f) => DataRow(cells: [
                                      DataCell(Text(f.srNumber,
                                          style: TextStyle(
                                              color: context
                                                  .colors.accentLightBlue,
                                              fontWeight: FontWeight.w600))),
                                      DataCell(Text(_itemName(f),
                                          overflow: TextOverflow.ellipsis)),
                                      DataCell(Text(f.consigneeName,
                                          overflow: TextOverflow.ellipsis)),
                                      DataCell(Text(yardName(f.yard),
                                          overflow: TextOverflow.ellipsis)),
                                      DataCell(Text(
                                          DateFormat('yyyy-MM-dd')
                                              .format(f.appealDeadline),
                                          style: TextStyle(
                                              color: f.isAppealExpired
                                                  ? context.colors.dangerRed
                                                  : context
                                                      .colors.textSecondary,
                                              fontWeight: FontWeight.w600))),
                                      DataCell(_statusChip(context, f)),
                                      DataCell(Center(
                                        child: IconButton(
                                          icon: Icon(Icons.info_outline_rounded,
                                              color:
                                                  context.colors.accentLightBlue,
                                              size: 18),
                                          onPressed: f.packageDetails == null
                                              ? null
                                              : () => _openDetails(
                                                  context, ref, f, storageRate),
                                        ),
                                      )),
                                    ]))
                                .toList(),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(BuildContext context, ForfeitedPackageModel f) {
    final (label, color) = f.isAppealHeld
        ? ('On Appeal Hold', context.colors.warningAmber)
        : f.hasAppealDecision
            ? ('Decided · ${f.appealDecisionLabel}', context.colors.accentLightBlue)
            : f.isAppealExpired
                ? ('Window Passed', context.colors.dangerRed)
                : ('In Appeal · ${f.daysUntilDeadline}d',
                    context.colors.successGreen);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(label,
          textAlign: TextAlign.center,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }

  // Opens the package details popup with a footer Hold-Appeal / Release action.
  void _openDetails(BuildContext context, WidgetRef ref,
      ForfeitedPackageModel f, Map<DateTime, double> storageRate) {
    // Can place a hold only while the appeal window is open; can always release.
    final canHold = !f.isAppealExpired;
    String? label;
    IconData? icon;
    Color? color;
    String? hint;
    VoidCallback? action;
    if (f.isAppealHeld) {
      label = 'Release Hold & Decide';
      icon = Icons.gavel_rounded;
      color = context.colors.successGreen;
      hint = 'Lift the hold and record what the yard should do with this package';
      action = () => _showDecisionDialog(context, ref, f);
    } else if (canHold) {
      label = 'Hold Appeal';
      icon = Icons.gavel_rounded;
      color = context.colors.warningAmber;
      hint = 'Place an appeal hold — blocks sale/destruction of this package';
      action = () => _setHold(context, ref, f, true);
    }
    showDialog(
      context: context,
      builder: (_) => PackageDetailsDialog(
        package: f.packageDetails!,
        storageRate: storageRate,
        footerActionLabel: label,
        footerActionIcon: icon,
        footerActionColor: color,
        footerActionHint: hint,
        onFooterAction: action,
      ),
    );
  }

  Future<void> _setHold(BuildContext context, WidgetRef ref,
      ForfeitedPackageModel f, bool hold) async {
    try {
      await ref.read(appealServiceProvider).setAppealHold(f.id, hold);
      ref.invalidate(appealForfeitedPackagesProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: hold
              ? context.colors.warningAmber
              : context.colors.successGreen,
          content: Text(hold
              ? 'Appeal hold placed — ${f.srNumber} cannot be sold or destroyed.'
              : 'Appeal hold lifted for ${f.srNumber}.'),
        ));
      }
    } catch (e) {
      if (context.mounted) {
        final msg = e.toString().contains('appeal_window_passed')
            ? 'The appeal window for this package has already passed.'
            : 'Error: $e';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: context.colors.dangerRed,
          content: Text(msg),
        ));
      }
    }
  }

  // Asks the directorate which disposition the yard should carry out, then
  // lifts the hold and records the decision.
  Future<void> _showDecisionDialog(
      BuildContext context, WidgetRef ref, ForfeitedPackageModel f) async {
    final result = await showDialog<_AppealDecisionResult>(
      context: context,
      builder: (_) => _AppealDecisionDialog(srNumber: f.srNumber),
    );
    if (result == null) return; // cancelled
    if (!context.mounted) return;
    try {
      await ref.read(appealServiceProvider).releaseAppealWithDecision(
            f.id,
            result.decision,
            note: result.note,
          );
      ref.invalidate(appealForfeitedPackagesProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: context.colors.successGreen,
          content: Text(
              'Hold lifted — ${f.srNumber} forwarded to yard for: ${result.label}.'),
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: context.colors.dangerRed,
          content: Text('Error: $e'),
        ));
      }
    }
  }

  Widget _listCard(BuildContext context, Widget child) {
    return Container(
      decoration: BoxDecoration(
        color: context.colors.cardDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.colors.borderColor),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: child,
      ),
    );
  }
}

/// Yard dropdown ("All Yards" + every yard) tinted to the appeal accent.
class _AppealYardFilter extends StatelessWidget {
  final Color accent;
  final String? value; // null = all
  final ValueChanged<String?> onChanged;
  const _AppealYardFilter(
      {required this.accent, required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: c, width: w));
    return SizedBox(
      width: 220,
      child: Theme(
        data: Theme.of(context).copyWith(
          inputDecorationTheme:
              Theme.of(context).inputDecorationTheme.copyWith(
                    filled: true,
                    fillColor: accent.withOpacity(0.06),
                    border: border(accent.withOpacity(0.4)),
                    enabledBorder: border(accent.withOpacity(0.4)),
                    focusedBorder: border(accent, 1.5),
                  ),
        ),
        child: StyledDropdownFormField<String>(
          value: value ?? '_all',
          label: 'Yard',
          helperText: null,
          isDense: true,
          menuWidth: 220,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          prefixIcon:
              Icon(Icons.warehouse_rounded, color: accent, size: 20),
          options: [
            const StyledDropdownOption('_all', 'All Yards'),
            for (final y in kYards) StyledDropdownOption(y.code, y.name),
          ],
          onChanged: (v) => onChanged((v == null || v == '_all') ? null : v),
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatChip(
      {required this.label, required this.value, required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value,
              style: TextStyle(
                  color: color,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  height: 1.1)),
          Text(label,
              style: TextStyle(
                  color: context.colors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5)),
        ],
      ),
    );
  }
}

// ── Appeal decision picker ────────────────────────────────────────────────────
// Returned when the directorate lifts a hold and chooses what the owning yard
// should do next with the package.
class _AppealDecisionResult {
  final String decision; // RELEASE / SALE / DESTROY / RE-EXPORT / OTHER
  final String? note; // custom outcome text for OTHER
  final String label; // human-friendly label for the snackbar
  const _AppealDecisionResult(this.decision, this.label, {this.note});
}

class _AppealDecisionOption {
  final String key;
  final String label;
  final String description;
  final IconData icon;
  final Color color;
  const _AppealDecisionOption(
      this.key, this.label, this.description, this.icon, this.color);
}

class _AppealDecisionDialog extends StatefulWidget {
  final String srNumber;
  const _AppealDecisionDialog({required this.srNumber});

  @override
  State<_AppealDecisionDialog> createState() => _AppealDecisionDialogState();
}

class _AppealDecisionDialogState extends State<_AppealDecisionDialog> {
  String? _selected;
  final _otherCtrl = TextEditingController();

  static const _options = [
    _AppealDecisionOption('RELEASE', 'Release to owner',
        'Return the goods to the owner.', Icons.assignment_return_rounded,
        Color(0xFF43A047)),
    _AppealDecisionOption('SALE', 'Sell',
        'Dispose of the goods by sale.', Icons.sell_rounded,
        Color(0xFFE8A826)),
    _AppealDecisionOption('DESTROY', 'Destroy',
        'Destroy the goods.', Icons.delete_forever_rounded,
        Color(0xFFE64A19)),
    _AppealDecisionOption('RE-EXPORT', 'Re-export',
        'Send the goods back to country of origin.',
        Icons.flight_takeoff_rounded, Color(0xFF00ACC1)),
    _AppealDecisionOption('OTHER', 'Other',
        'A custom outcome — describe below.', Icons.more_horiz_rounded,
        Color(0xFF7E57C2)),
  ];

  @override
  void dispose() {
    _otherCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = context.colors.accentBlue;
    final isOther = _selected == 'OTHER';
    final canConfirm = _selected != null &&
        (!isOther || _otherCtrl.text.trim().isNotEmpty);

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        width: 520,
        constraints: const BoxConstraints(maxHeight: 720),
        decoration: BoxDecoration(
          color: context.colors.scaffoldBg,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              decoration: BoxDecoration(
                color: accent,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.gavel_rounded,
                      color: Colors.white, size: 22),
                ),
                const Gap(14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('APPEAL DECISION',
                          style: TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                              letterSpacing: 1.2,
                              fontWeight: FontWeight.w800)),
                      Text(widget.srNumber,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close_rounded,
                      color: Colors.white.withOpacity(0.8)),
                  onPressed: () => Navigator.pop(context),
                ),
              ]),
            ),
            // Body
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'The appeal has been processed. Choose what the owning yard '
                      'should do with this package — the yard will act on this decision.',
                      style: TextStyle(
                          color: context.colors.textSecondary, fontSize: 13),
                    ),
                    const Gap(16),
                    ..._options.map((o) {
                      final selected = _selected == o.key;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => setState(() => _selected = o.key),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              color: o.color
                                  .withOpacity(selected ? 0.10 : 0.04),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: o.color.withOpacity(selected ? 0.7 : 0.2),
                                width: selected ? 1.6 : 1,
                              ),
                            ),
                            child: Row(children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: o.color.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(o.icon, color: o.color, size: 20),
                              ),
                              const Gap(14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(o.label,
                                        style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 14,
                                            color: o.color)),
                                    const Gap(2),
                                    Text(o.description,
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: context.colors.textMuted)),
                                  ],
                                ),
                              ),
                              Icon(
                                selected
                                    ? Icons.radio_button_checked_rounded
                                    : Icons.radio_button_unchecked_rounded,
                                color: selected
                                    ? o.color
                                    : context.colors.textMuted,
                                size: 20,
                              ),
                            ]),
                          ),
                        ),
                      );
                    }),
                    if (isOther) ...[
                      const Gap(4),
                      TextField(
                        controller: _otherCtrl,
                        autofocus: true,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'Describe the outcome *',
                          hintText: 'e.g. Transfer to another authority',
                          isDense: true,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            // Footer
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: context.colors.surfaceDark,
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(20)),
                border:
                    Border(top: BorderSide(color: context.colors.borderColor)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const Gap(8),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text('Confirm & Release Hold'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor:
                          context.colors.textMuted.withOpacity(0.3),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 14),
                    ),
                    onPressed: !canConfirm
                        ? null
                        : () {
                            final opt = _options
                                .firstWhere((o) => o.key == _selected);
                            final note = isOther
                                ? _otherCtrl.text.trim()
                                : null;
                            final label =
                                isOther ? _otherCtrl.text.trim() : opt.label;
                            Navigator.pop(
                                context,
                                _AppealDecisionResult(opt.key, label,
                                    note: note));
                          },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
