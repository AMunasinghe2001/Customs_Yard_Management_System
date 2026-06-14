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
                                  label: Center(child: Text('Appeal Hold')),
                                  size: ColumnSize.S,
                                  fixedWidth: 150),
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
                                      DataCell(
                                          Center(child: _holdChip(context, f))),
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

  // Appeal-hold STATUS chip only — the actual Hold/Release action now lives in
  // the package details popup footer (opened via the Details ⓘ button).
  Widget _holdChip(BuildContext context, ForfeitedPackageModel f) {
    if (f.isAppealHeld) {
      final amber = context.colors.warningAmber;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: amber.withOpacity(0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: amber.withOpacity(0.4)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.lock_rounded, size: 12, color: amber),
          const Gap(5),
          Text('On Hold',
              style: TextStyle(
                  color: amber, fontSize: 11, fontWeight: FontWeight.w700)),
        ]),
      );
    }
    return Text('—', style: TextStyle(color: context.colors.textMuted));
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
      label = 'Release Hold';
      icon = Icons.lock_open_rounded;
      color = context.colors.dangerRed;
      hint = 'Lift the appeal hold — this package may again be sold/destroyed';
      action = () => _setHold(context, ref, f, false);
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
