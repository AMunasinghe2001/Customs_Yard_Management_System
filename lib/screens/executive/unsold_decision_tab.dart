import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:data_table_2/data_table_2.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../core/providers.dart';
import '../../core/yards.dart';
import '../../models/models.dart';
import '../../widgets/error_view.dart';
import '../../widgets/empty_table_state.dart';
import '../../widgets/styled_form_dialog.dart';
import '../../widgets/table_pager.dart';
import '../../widgets/package_details_dialog.dart';
import 'executive_header.dart';
import 'unsold_shared.dart';

/// True when the signed-in Top Management Directorate officer is the DG — the only post that
/// rules on an unsold package's final outcome. The ADG and the DC both see the
/// table read-only. See [executivePostIs] for how the post is resolved.
bool _isDg(ProfileModel? p) => executivePostIs(p, 'DG');

final _uSearchProvider = StateProvider<String>((ref) => '');
final _uYardProvider = StateProvider<String?>((ref) => null); // null = all
/// null = all · false = still undecided · true = decided
final _uDecidedProvider = StateProvider<bool?>((ref) => null);
final _uPageProvider = StateProvider<int>((ref) => 0);

/// Top Management Directorate tab: packages that have exhausted EVERY avenue — the Valuation
/// Tender plus Tender 1-3 all failed, a committee re-valued them, the ADG
/// submitted that figure, they were tendered again, and they STILL did not
/// sell. The DG decides the final outcome here; Central Disposal and the
/// owning yard then see that decision on their own Unsold pages.
///
/// Laid out to match the Tender Committees tab — same header row (title,
/// subtitle, search, yard dropdown), same table shell and column set.
class UnsoldDecisionTab extends ConsumerWidget {
  const UnsoldDecisionTab({super.key});

  static const int _pageSize = 20;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = AppTheme.executiveTeal;
    final async = ref.watch(exhaustedUnsoldProvider);
    final proposals =
        ref.watch(unsoldProposalsProvider).valueOrNull ?? const {};
    final q = ref.watch(_uSearchProvider).trim().toLowerCase();
    final yardFilter = ref.watch(_uYardProvider);
    final decidedFilter = ref.watch(_uDecidedProvider);
    final storageRate = ref.watch(storageRateProvider).valueOrNull ??
        const <DateTime, double>{};
    // Only the DG may decide; the ADG sees the same table, read-only.
    final canDecide = _isDg(ref.watch(currentProfileProvider));

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search field and yard dropdown sit on ONE line: the dropdown's
          // label never floats (a floating label draws above the box) and both
          // take their height from the same kExecutiveFilterPadding.
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Unsold Goods',
                      style: TextStyle(
                          color: context.colors.textPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.w700)),
                  const Gap(2),
                  Text(
                      canDecide
                          ? 'Every avenue exhausted — decide the final outcome'
                          : 'Every avenue exhausted — the DG decides the final outcome',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: context.colors.textMuted, fontSize: 13)),
                ],
              ),
            ),
            const Gap(16),
            ExecutiveSearchField(
              hint: 'Search SR / item / consignee…',
              onChanged: (v) {
                ref.read(_uSearchProvider.notifier).state = v;
                ref.read(_uPageProvider.notifier).state = 0;
              },
            ),
            const Gap(12),
            // Width only — NO fixed height. The dropdown's InkWell fills
            // whatever box it is given, so forcing a height made the hover
            // splash spill past the field's border as a pale band underneath.
            // Its contentPadding already matches the search field.
            SizedBox(
              width: 220,
              child: ExecutiveYardFilter(
                value: yardFilter,
                onChanged: (v) {
                  ref.read(_uYardProvider.notifier).state = v;
                  ref.read(_uPageProvider.notifier).state = 0;
                },
              ),
            ),
          ]).animate().fadeIn(duration: 300.ms),
          const Gap(12),
          Row(children: [
            executiveFilterChip(context,
                label: 'All', selected: decidedFilter == null, onTap: () {
              ref.read(_uDecidedProvider.notifier).state = null;
              ref.read(_uPageProvider.notifier).state = 0;
            }),
            const Gap(8),
            executiveFilterChip(context,
                label: 'Pending decision',
                icon: Icons.hourglass_bottom_rounded,
                colour: context.colors.warningAmber,
                selected: decidedFilter == false, onTap: () {
              ref.read(_uDecidedProvider.notifier).state = false;
              ref.read(_uPageProvider.notifier).state = 0;
            }),
            const Gap(8),
            executiveFilterChip(context,
                label: 'Decided',
                icon: Icons.check_circle_rounded,
                colour: context.colors.successGreen,
                selected: decidedFilter == true, onTap: () {
              ref.read(_uDecidedProvider.notifier).state = true;
              ref.read(_uPageProvider.notifier).state = 0;
            }),
          ]),
          const Gap(14),
          Expanded(
            child: async.when(
              skipLoadingOnReload: true,
              loading: () =>
                  Center(child: CircularProgressIndicator(color: accent)),
              error: (e, _) => ErrorView(
                  error: e,
                  onRetry: () => ref.refresh(exhaustedUnsoldProvider)),
              data: (list) {
                var rows = list;
                if (yardFilter != null) {
                  rows = rows
                      .where((i) => i.forfeited.yard == yardFilter)
                      .toList();
                }
                if (q.isNotEmpty) {
                  rows = rows.where((i) {
                    final f = i.forfeited;
                    return f.srNumber.toLowerCase().contains(q) ||
                        f.consigneeName.toLowerCase().contains(q) ||
                        unsoldItemName(f).toLowerCase().contains(q) ||
                        (f.packageDetails?.caseNumber ?? '')
                            .toLowerCase()
                            .contains(q);
                  }).toList();
                }
                if (decidedFilter != null) {
                  rows = rows
                      .where((i) =>
                          proposals.containsKey(i.forfeited.id) ==
                          decidedFilter)
                      .toList();
                }

                final maxPage =
                    rows.isEmpty ? 0 : (rows.length - 1) ~/ _pageSize;
                final page = ref.watch(_uPageProvider).clamp(0, maxPage);
                final pageRows =
                    rows.skip(page * _pageSize).take(_pageSize).toList();

                return Column(
                  children: [
                    Expanded(
                      child: Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: context.colors.cardDark,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: context.colors.borderColor),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: DataTable2(
                            columnSpacing: 12,
                            horizontalMargin: 16,
                            fixedTopRows: 1,
                            minWidth: kUnsoldTableMinWidth,
                            empty: const EmptyTableState(
                                message:
                                    'No packages awaiting a final outcome'),
                            headingRowColor: WidgetStateProperty.all(
                                context.colors.surfaceDark),
                            columns: kUnsoldColumns,
                            rows: pageRows.map((info) {
                              final f = info.forfeited;
                              final pkg = f.packageDetails;
                              final qty = unsoldQty(f);
                              return DataRow(
                                cells: unsoldCells(
                                  context,
                                  info: info,
                                  srColor: accent,
                                  outcome: Center(
                                    child: _DecisionCell(
                                        info: info,
                                        proposal: proposals[f.id],
                                        canDecide: canDecide),
                                  ),
                                  onDetails: pkg == null
                                      ? null
                                      : () => showDialog(
                                            context: context,
                                            builder: (_) =>
                                                PackageDetailsDialog(
                                              package: pkg,
                                              storageRate: storageRate,
                                              headerAccentColor: accent,
                                              useLegacySummary: true,
                                              highlightItemId: f.itemId,
                                              yardLabel: yardName(f.yard),
                                              valuationUnitCost:
                                                  f.valuationCost,
                                              valuationTotalCost:
                                                  f.valuationCost != null
                                                      ? f.valuationCost! * qty
                                                      : null,
                                              valuationQty: qty,
                                              tenderHistoryFor: f,
                                            ),
                                          ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ),
                    TablePager(
                      total: rows.length,
                      page: page,
                      pageSize: _pageSize,
                      onPageChanged: (p) =>
                          ref.read(_uPageProvider.notifier).state = p,
                    ),
                  ],
                ).animate().fadeIn(duration: 350.ms).slideY(begin: 0.05);
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// The decision cell. For the DG: a "Decide" button until an outcome is set,
/// then the outcome itself (still tappable, so it can be revised). For the ADG
/// and anyone else: the read-only chip the other portals show.
class _DecisionCell extends ConsumerWidget {
  final ReTenderSaleInfo info;
  final UnsoldProposalModel? proposal;
  final bool canDecide;
  const _DecisionCell({
    required this.info,
    required this.proposal,
    required this.canDecide,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Inside the Top Management Directorate's own portal "Awaiting Top Management Directorate" would tell the
    // ADG to wait for themselves — name the officer who actually decides.
    if (!canDecide) {
      return UnsoldOutcomeChip(
          proposal: proposal, pendingLabel: UnsoldOutcomeChip.kAwaitingDg);
    }

    void open() => showDialog(
          context: context,
          builder: (_) => _DecisionDialog(info: info, existing: proposal),
        );

    final p = proposal;
    if (p == null) {
      return FilledButton.icon(
        style: FilledButton.styleFrom(
            backgroundColor: context.colors.warningAmber,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            visualDensity: VisualDensity.compact),
        icon: const Icon(Icons.rule_rounded, size: 15),
        label: const Text('Decide', style: TextStyle(fontSize: 12)),
        onPressed: open,
      );
    }

    final st = unsoldOutcomeStyle(context, p.proposal);
    return Tooltip(
      message: p.note?.trim().isNotEmpty == true
          ? p.note!.trim()
          : 'Decided ${DateFormat('yyyy-MM-dd').format(p.decidedAt)} — tap to revise',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: open,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: st.colour.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: st.colour.withOpacity(0.45)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(st.icon, size: 13, color: st.colour),
              const Gap(5),
              Flexible(
                child: Text(p.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: st.colour,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Pick one of the four outcomes, with an optional reason. DG only.
class _DecisionDialog extends ConsumerStatefulWidget {
  final ReTenderSaleInfo info;
  final UnsoldProposalModel? existing;
  const _DecisionDialog({required this.info, this.existing});
  @override
  ConsumerState<_DecisionDialog> createState() => _DecisionDialogState();
}

class _DecisionDialogState extends ConsumerState<_DecisionDialog> {
  late String? _choice = widget.existing?.proposal;
  late final _noteCtrl =
      TextEditingController(text: widget.existing?.note ?? '');
  bool _saving = false;

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final choice = _choice;
    if (choice == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Choose a final outcome.'),
          backgroundColor: context.colors.dangerRed));
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(disposalServiceProvider).saveUnsoldProposal(
            forfeitedPackageId: widget.info.forfeited.id,
            proposal: choice,
            note: _noteCtrl.text,
            yard: widget.info.forfeited.yard,
          );
      ref.invalidate(unsoldProposalsProvider);
      // A decision ends the tender route for these goods, so Central
      // Disposal's re-tender pool must drop them straight away.
      ref.invalidate(reTenderEligibleProvider);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Final outcome set: ${unsoldProposalLabel(choice)}'),
          backgroundColor: context.colors.successGreen));
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to save: $e'),
          backgroundColor: context.colors.dangerRed));
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.executiveTeal;
    final f = widget.info.forfeited;
    return StyledFormDialog(
      label: 'Final Outcome',
      title: f.srNumber,
      headerAccentColor: accent,
      icon: Icons.rule_rounded,
      width: 480,
      child: StyledFormSection(
        title: 'Decide · ${unsoldItemName(f)}',
        icon: Icons.gavel_rounded,
        children: [
          Text(
              'This package could not be sold by any means — the Valuation '
              'Tender, Tender 1-3 and the committee-valued tender all failed. '
              'Choose what happens to the goods.',
              style: TextStyle(color: context.colors.textMuted, fontSize: 11)),
          const Gap(12),
          for (final p in kUnsoldProposals) ...[
            _option(p),
            const Gap(6),
          ],
          const Gap(6),
          TextField(
            controller: _noteCtrl,
            minLines: 2,
            maxLines: 4,
            keyboardType: TextInputType.multiline,
            textCapitalization: TextCapitalization.sentences,
            style: TextStyle(color: context.colors.textPrimary, fontSize: 13),
            decoration: InputDecoration(
              isDense: true,
              labelText: 'Reason (optional)',
              alignLabelWithHint: true,
              hintText: 'Why this outcome was chosen…',
              hintStyle:
                  TextStyle(color: context.colors.textMuted, fontSize: 12),
              filled: true,
              fillColor: context.colors.cardDark,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: context.colors.borderColor)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: context.colors.borderColor)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: accent, width: 1.4)),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: _saving ? null : _save,
          style: FilledButton.styleFrom(backgroundColor: accent),
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : Text(widget.existing == null ? 'Save Outcome' : 'Update'),
        ),
      ],
    );
  }

  /// One selectable outcome, styled as a radio card.
  Widget _option(String p) {
    final st = unsoldOutcomeStyle(context, p);
    final selected = _choice == p;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: _saving ? null : () => setState(() => _choice = p),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? st.colour.withOpacity(0.12)
                : context.colors.cardDark,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: selected
                    ? st.colour.withOpacity(0.6)
                    : context.colors.borderColor,
                width: selected ? 1.4 : 1),
          ),
          child: Row(children: [
            Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 17,
                color: selected ? st.colour : context.colors.textMuted),
            const Gap(10),
            Icon(st.icon, size: 16, color: st.colour),
            const Gap(8),
            Text(unsoldProposalLabel(p),
                style: TextStyle(
                    color: selected ? st.colour : context.colors.textPrimary,
                    fontSize: 13.5,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600)),
          ]),
        ),
      ),
    );
  }
}

/// Yard dropdown with an "All Yards" option, styled to sit on exactly the same
/// line as the search field beside it.
///
/// The "Yard" caption is deliberately NOT a floating label: a floating label
/// renders above the box and makes the control taller than a plain TextField,
/// which is what left the two controls on two different levels. The caption is
/// drawn as a prefix inside the box instead.
