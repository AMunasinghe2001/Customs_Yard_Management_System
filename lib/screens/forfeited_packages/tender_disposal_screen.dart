import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:data_table_2/data_table_2.dart';
import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../core/supabase_client.dart';
import '../../models/models.dart';
import '../../services/services.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/empty_table_state.dart';
import '../../widgets/error_view.dart';
import 'tender_placement_dialog.dart';

// ── Local providers ────────────────────────────────────────────

final tenderSearchProvider = StateProvider<String>((ref) => '');

// For each forfeited_package_id, what disposal has been recorded?
// We fetch all tender_disposals grouped by forfeitedPackageId
final tenderDisposalsMapProvider = FutureProvider<Map<String, TenderDisposalModel>>((ref) async {
  ref.watch(forfeitedPackagesChangeTriggerProvider);
  final data = await supabase
      .from('tender_disposals')
      .select('*, profiles(full_name)')
      .order('disposed_at', ascending: false);
  final map = <String, TenderDisposalModel>{};
  for (final row in data) {
    final model = TenderDisposalModel.fromJson(row as Map<String, dynamic>);
    // Keep the latest disposal per forfeited_package_id
    map.putIfAbsent(model.forfeitedPackageId, () => model);
  }
  return map;
});

// Full forfeited package detail lookup by id
final forfeitedPackageByIdProvider =
    FutureProvider.family<ForfeitedPackageModel?, String>((ref, id) async {
  ref.watch(forfeitedPackagesChangeTriggerProvider);
  final data = await supabase
      .from('forfeited_packages')
      .select('*, packages(*)')
      .eq('id', id)
      .maybeSingle();
  if (data == null) return null;
  return ForfeitedPackageModel.fromJson(data as Map<String, dynamic>);
});

// ── Screen ─────────────────────────────────────────────────────

class TenderDisposalScreen extends ConsumerStatefulWidget {
  const TenderDisposalScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<TenderDisposalScreen> createState() =>
      _TenderDisposalScreenState();
}

class _TenderDisposalScreenState
    extends ConsumerState<TenderDisposalScreen> {
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchCtrl.text = ref.read(tenderSearchProvider);
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tendersAsync = ref.watch(tendersProvider);
    final disposalsMapAsync = ref.watch(tenderDisposalsMapProvider);
    final forfeitedAsync = ref.watch(forfeitedPackagesProvider);
    final search = ref.watch(tenderSearchProvider);

    return AppShell(
      currentRoute: '/tender-disposals',
      child: Scaffold(
        backgroundColor: context.colors.scaffoldBg,
        body: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ──────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  runSpacing: 16,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Tender Disposals',
                            style: Theme.of(context).textTheme.headlineLarge),
                        Text(
                          'Record and manage disposal outcomes for tendered packages',
                          style: TextStyle(
                              color: context.colors.textSecondary),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        tendersAsync.when(
                          data: (tenders) {
                            final totalPkgs = tenders
                                .fold<int>(0,
                                    (s, t) => s + t.forfeitedPackageIds.length);
                            return Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _StatChip(
                                    label: 'Tenders',
                                    value: '${tenders.length}',
                                    color: context.colors.primaryGold),
                                const Gap(8),
                                _StatChip(
                                    label: 'Packages',
                                    value: '$totalPkgs',
                                    color: context.colors.accentLightBlue),
                                const Gap(16),
                              ],
                            );
                          },
                          loading: () => const SizedBox(),
                          error: (_, __) => const SizedBox(),
                        ),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.add_rounded, size: 16),
                          label: const Text('Place New Tender'),
                          onPressed: () => showDialog(
                            context: context,
                            builder: (ctx) => TenderPlacementDialog(
                              ref: ref,
                              onTenderCreated: () {
                                ref.invalidate(tendersProvider);
                                ref.invalidate(forfeitedPackagesProvider);
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ).animate().fadeIn(),
              const Gap(20),

              // ── Search Bar ──────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.colors.cardDark,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: context.colors.primaryGold.withOpacity(0.5)),
                ),
                child: TextField(
                  controller: _searchCtrl,
                  style: TextStyle(color: context.colors.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Search by tender number or SR number...',
                    prefixIcon: Icon(Icons.search_rounded,
                        color: context.colors.textMuted),
                    suffixIcon: _searchCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.clear_rounded,
                                color: context.colors.textMuted),
                            onPressed: () {
                              _searchCtrl.clear();
                              ref
                                  .read(tenderSearchProvider.notifier)
                                  .state = '';
                            },
                          )
                        : null,
                    isDense: true,
                  ),
                  onChanged: (v) {
                    ref.read(tenderSearchProvider.notifier).state = v;
                  },
                ),
              )
                  .animate()
                  .slideY(begin: 0.1, duration: 400.ms, delay: 200.ms)
                  .fadeIn(),

              const Gap(16),

              // ── Tenders List ─────────────────────────────────────
              Expanded(
                child: tendersAsync.when(
                  loading: () => Center(
                      child: CircularProgressIndicator(
                          color: context.colors.primaryGold)),
                  error: (e, _) => ErrorView(
                      error: e,
                      onRetry: () => ref.refresh(tendersProvider)),
                  data: (tenders) {
                    if (tenders.isEmpty) {
                      return Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: context.colors.cardDark,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: context.colors.borderColor),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.gavel_rounded,
                                color: context.colors.textMuted, size: 48),
                            const Gap(12),
                            Text('No tenders found',
                                style: TextStyle(
                                    color: context.colors.textSecondary,
                                    fontSize: 16)),
                            const Gap(8),
                            OutlinedButton.icon(
                              icon: const Icon(Icons.add_rounded, size: 16),
                              label: const Text('Place First Tender'),
                              onPressed: () {
                                showDialog(
                                  context: context,
                                  builder: (ctx) => TenderPlacementDialog(
                                    ref: ref,
                                    onTenderCreated: () {
                                      Navigator.pop(context);
                                      ref.invalidate(tendersProvider);
                                      ref.invalidate(forfeitedPackagesProvider);
                                    },
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      );
                    }

                    final filtered = search.isEmpty
                        ? tenders
                        : tenders.where((t) {
                            return t.tenderNumber
                                .toLowerCase()
                                .contains(search.toLowerCase());
                          }).toList();

                    return disposalsMapAsync.when(
                      loading: () => Center(
                          child: CircularProgressIndicator(
                              color: context.colors.primaryGold)),
                      error: (e, _) => ErrorView(
                          error: e,
                          onRetry: () =>
                              ref.refresh(tenderDisposalsMapProvider)),
                      data: (disposalsMap) {
                        return forfeitedAsync.when(
                          loading: () => Center(
                              child: CircularProgressIndicator(
                                  color: context.colors.primaryGold)),
                          error: (e, _) => ErrorView(
                              error: e,
                              onRetry: () =>
                                  ref.refresh(forfeitedPackagesProvider)),
                          data: (allForfeited) {
                            // Build lookup map: forfeited_package_id -> ForfeitedPackageModel
                            final forfeitedMap = {
                              for (final f in allForfeited) f.id: f
                            };

                            return ListView.builder(
                              itemCount: filtered.length,
                              itemBuilder: (context, i) {
                                return _TenderCard(
                                  tender: filtered[i],
                                  disposalsMap: disposalsMap,
                                  forfeitedMap: forfeitedMap,
                                );
                              },
                            )
                                .animate()
                                .slideY(
                                    begin: 0.1,
                                    duration: 400.ms,
                                    delay: 300.ms)
                                .fadeIn();
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Tender Card ─────────────────────────────────────────────────

class _TenderCard extends ConsumerWidget {
  final TenderModel tender;
  final Map<String, TenderDisposalModel> disposalsMap;
  final Map<String, ForfeitedPackageModel> forfeitedMap;

  const _TenderCard({
    required this.tender,
    required this.disposalsMap,
    required this.forfeitedMap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final disposedCount = tender.forfeitedPackageIds
        .where((id) => disposalsMap.containsKey(id))
        .length;
    final total = tender.forfeitedPackageIds.length;
    final isComplete = disposedCount == total;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        decoration: BoxDecoration(
          color: context.colors.cardDark,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isComplete
                ? context.colors.successGreen.withOpacity(0.4)
                : context.colors.borderColor,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Tender Header ─────────────────────────────────
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: context.colors.primaryGold.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.gavel_rounded,
                        color: context.colors.primaryGold, size: 22),
                  ),
                  const Gap(14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tender.tenderNumber,
                          style: TextStyle(
                            color: context.colors.textPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        Row(
                          children: [
                            Icon(Icons.calendar_today_rounded,
                                size: 12,
                                color: context.colors.textMuted),
                            const Gap(4),
                            Text(
                              DateFormat('yyyy-MM-dd')
                                  .format(tender.tenderDate),
                              style: TextStyle(
                                  color: context.colors.textMuted,
                                  fontSize: 12),
                            ),
                            if (tender.createdByName != null) ...[
                              const Gap(12),
                              Icon(Icons.person_rounded,
                                  size: 12,
                                  color: context.colors.textMuted),
                              const Gap(4),
                              Text(
                                tender.createdByName!,
                                style: TextStyle(
                                    color: context.colors.textMuted,
                                    fontSize: 12),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Progress / Completion Badge
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: isComplete
                              ? context.colors.successGreen.withOpacity(0.15)
                              : context.colors.warningAmber.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isComplete
                                ? context.colors.successGreen.withOpacity(0.4)
                                : context.colors.warningAmber.withOpacity(0.4),
                          ),
                        ),
                        child: Text(
                          isComplete
                              ? 'Completed'
                              : '$disposedCount / $total disposed',
                          style: TextStyle(
                            color: isComplete
                                ? context.colors.successGreen
                                : context.colors.warningAmber,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            Divider(height: 1, color: context.colors.borderColor),

            // ── Packages Table ────────────────────────────────
            Padding(
              padding: const EdgeInsets.all(12),
              child: _TenderPackagesTable(
                tender: tender,
                disposalsMap: disposalsMap,
                forfeitedMap: forfeitedMap,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Packages Table inside a Tender Card ─────────────────────────

class _TenderPackagesTable extends ConsumerWidget {
  final TenderModel tender;
  final Map<String, TenderDisposalModel> disposalsMap;
  final Map<String, ForfeitedPackageModel> forfeitedMap;

  const _TenderPackagesTable({
    required this.tender,
    required this.disposalsMap,
    required this.forfeitedMap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = tender.forfeitedPackageIds.map((pkgId) {
      final forfeited = forfeitedMap[pkgId];
      final disposal = disposalsMap[pkgId];
      return _PackageRow(
        forfeitedPackageId: pkgId,
        forfeited: forfeited,
        disposal: disposal,
      );
    }).toList();

    return Container(
      height: (rows.length * 52.0 + 56).clamp(100, 340),
      decoration: BoxDecoration(
        border: Border.all(color: context.colors.borderColor),
        borderRadius: BorderRadius.circular(10),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: DataTable2(
          columnSpacing: 10,
          horizontalMargin: 12,
          fixedTopRows: 1,
          isVerticalScrollBarVisible: true,
          empty: const EmptyTableState(message: 'No packages in this tender'),
          columns: const [
            DataColumn2(label: Text('SR Number'), size: ColumnSize.M),
            DataColumn2(label: Text('Consignee'), size: ColumnSize.L),
            DataColumn2(label: Text('Disposal Type'), size: ColumnSize.M),
            DataColumn2(label: Text('Receipt / Details'), size: ColumnSize.M),
            DataColumn2(label: Text('Disposed By'), size: ColumnSize.M),
            DataColumn2(
              label: Center(child: Text('Action')),
              size: ColumnSize.S,
              fixedWidth: 90,
            ),
          ],
          rows: rows.map((row) => DataRow2(
            cells: [
              DataCell(Text(
                row.forfeited?.srNumber ?? row.forfeitedPackageId.substring(0, 8),
                style: TextStyle(
                  color: context.colors.accentLightBlue,
                  fontWeight: FontWeight.w600,
                ),
              )),
              DataCell(Text(
                row.forfeited?.consigneeName ?? '—',
                overflow: TextOverflow.ellipsis,
              )),
              DataCell(row.disposal != null
                  ? _DisposalTypeBadge(type: row.disposal!.disposalType)
                  : Text('—',
                      style:
                          TextStyle(color: context.colors.textMuted))),
              DataCell(Text(
                _receiptOrDetails(row.disposal),
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: context.colors.textSecondary, fontSize: 13),
              )),
              DataCell(Text(
                row.disposal?.disposedByName ?? '—',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: context.colors.textMuted, fontSize: 13),
              )),
              DataCell(Center(
                child: IconButton(
                  icon: Icon(
                    row.disposal != null
                        ? Icons.visibility_rounded
                        : Icons.assignment_ind_rounded,
                    color: row.disposal != null
                        ? context.colors.successGreen
                        : context.colors.primaryGold,
                    size: 20,
                  ),
                  tooltip: row.disposal != null
                      ? 'View Disposal'
                      : 'Record Disposal',
                  onPressed: () => _showDisposalDialog(
                      context, ref, row),
                ),
              )),
            ],
          )).toList(),
        ),
      ),
    );
  }

  String _receiptOrDetails(TenderDisposalModel? disposal) {
    if (disposal == null) return '—';
    if (disposal.receiptNumber != null && disposal.receiptNumber!.isNotEmpty) {
      return 'Receipt: ${disposal.receiptNumber}';
    }
    if (disposal.otherDetails != null && disposal.otherDetails!.isNotEmpty) {
      return disposal.otherDetails!;
    }
    return '—';
  }

  void _showDisposalDialog(
      BuildContext context, WidgetRef ref, _PackageRow row) {
    showDialog(
      context: context,
      builder: (_) => DisposalDialog(
        forfeitedPackageId: row.forfeitedPackageId,
        forfeited: row.forfeited,
        existingDisposal: row.disposal,
        tenderId: tender.id,
      ),
    );
  }
}

class _PackageRow {
  final String forfeitedPackageId;
  final ForfeitedPackageModel? forfeited;
  final TenderDisposalModel? disposal;

  _PackageRow({
    required this.forfeitedPackageId,
    this.forfeited,
    this.disposal,
  });
}

// ── Disposal Type Badge ──────────────────────────────────────────

class _DisposalTypeBadge extends StatelessWidget {
  final String type;
  const _DisposalTypeBadge({required this.type});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (type) {
      'sold' => ('Sold', context.colors.successGreen),
      're_export' => ('Re-export', context.colors.accentLightBlue),
      'govt_use' => ('Govt. Use', context.colors.primaryGold),
      'destroy' => ('Destroy', context.colors.dangerRed),
      'other' => ('Other', context.colors.textSecondary),
      _ => (type, context.colors.textSecondary),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontWeight: FontWeight.w600, fontSize: 11)),
    );
  }
}

// ── Disposal Dialog ─────────────────────────────────────────────

class DisposalDialog extends ConsumerStatefulWidget {
  final String forfeitedPackageId;
  final ForfeitedPackageModel? forfeited;
  final TenderDisposalModel? existingDisposal;
  final String tenderId;

  const DisposalDialog({
    Key? key,
    required this.forfeitedPackageId,
    this.forfeited,
    this.existingDisposal,
    required this.tenderId,
  }) : super(key: key);

  @override
  ConsumerState<DisposalDialog> createState() => _DisposalDialogState();
}

class _DisposalDialogState extends ConsumerState<DisposalDialog> {
  String? _selectedDisposalType;
  late TextEditingController _receiptNumberController;
  late TextEditingController _otherDetailsController;
  bool _isLoading = false;

  final List<(String, String, IconData)> _disposalTypes = const [
    ('sold', 'Sold', Icons.sell_rounded),
    ('re_export', 'Re-export', Icons.flight_takeoff_rounded),
    ('govt_use', 'Government Use', Icons.account_balance_rounded),
    ('destroy', 'Destroy', Icons.delete_forever_rounded),
    ('other', 'Other', Icons.more_horiz_rounded),
  ];

  @override
  void initState() {
    super.initState();
    _receiptNumberController = TextEditingController(
        text: widget.existingDisposal?.receiptNumber ?? '');
    _otherDetailsController = TextEditingController(
        text: widget.existingDisposal?.otherDetails ?? '');
    _selectedDisposalType = widget.existingDisposal?.disposalType;
  }

  @override
  void dispose() {
    _receiptNumberController.dispose();
    _otherDetailsController.dispose();
    super.dispose();
  }

  bool get _isViewOnly => widget.existingDisposal != null;

  Future<void> _handleSave() async {
    if (_selectedDisposalType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a disposal type')),
      );
      return;
    }
    if (_selectedDisposalType == 'sold' &&
        _receiptNumberController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('Receipt number is required for sold items')),
      );
      return;
    }
    if (_selectedDisposalType == 'other' &&
        _otherDetailsController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please provide details for Other')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      await ref.read(tendersServiceProvider).recordDisposal(
            tenderPackageId: widget.tenderId,
            forfeitedPackageId: widget.forfeitedPackageId,
            disposalType: _selectedDisposalType!,
            receiptNumber: _selectedDisposalType == 'sold'
                ? _receiptNumberController.text.trim()
                : null,
            otherDetails: _selectedDisposalType == 'other'
                ? _otherDetailsController.text.trim()
                : null,
          );

      ref.invalidate(tendersProvider);
      ref.invalidate(tenderDisposalsMapProvider);
      ref.invalidate(forfeitedPackagesProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Disposal recorded successfully'),
            duration: Duration(seconds: 2),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final forfeited = widget.forfeited;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 400),
      tween: Tween(begin: 0.0, end: 1.0),
      curve: Curves.easeOutBack,
      builder: (context, value, child) {
        return Transform.scale(
          scale: value,
          child: Opacity(opacity: value.clamp(0.0, 1.0), child: child),
        );
      },
      child: Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: 580,
          constraints: const BoxConstraints(maxHeight: 700),
          decoration: BoxDecoration(
            color: context.colors.scaffoldBg,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.4),
                blurRadius: 40,
                offset: const Offset(0, 15),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Dialog Header ──
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDark
                        ? [context.colors.surfaceDark, context.colors.cardDark]
                        : [context.colors.customsBlue, context.colors.customsBlueDark],
                  ),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.gavel_rounded, color: context.colors.primaryGold, size: 24),
                    ).animate().scale(duration: 400.ms, curve: Curves.easeOutBack),
                    const Gap(16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isViewOnly ? 'DISPOSAL DETAILS' : 'RECORD DISPOSAL',
                            style: TextStyle(
                              color: context.colors.primaryGold,
                              fontSize: 11,
                              letterSpacing: 1.2,
                              fontWeight: FontWeight.w800,
                            ),
                          ).animate().fadeIn(duration: 400.ms, delay: 100.ms),
                          if (forfeited != null)
                            Text(
                              forfeited.srNumber,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ).animate().fadeIn(duration: 400.ms, delay: 150.ms).slideX(begin: -0.1),
                        ],
                      ),
                    ),
                    const Gap(12),
                    IconButton(
                      icon: Icon(Icons.close_rounded, color: Colors.white.withOpacity(0.7)),
                      splashRadius: 24,
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              // ── Dialog Body ──
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Package Details (read-only) ──
                      if (forfeited != null) ...[
                        _SectionLabel(
                          icon: Icons.inventory_2_rounded,
                          label: 'Package Information',
                          color: context.colors.accentLightBlue,
                        ),
                        const Gap(16),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: context.colors.textPrimary.withOpacity(0.02),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: context.colors.borderColor.withOpacity(0.5)),
                          ),
                          child: _InfoGrid(forfeited: forfeited),
                        ).animate().fadeIn(delay: 100.ms),
                        const Gap(24),
                      ],

                      // ── Disposal Type ──
                      _SectionLabel(
                        icon: Icons.assignment_ind_rounded,
                        label: 'Disposal Method',
                        color: context.colors.primaryGold,
                      ).animate().fadeIn(delay: 200.ms),
                      const Gap(16),
                      if (_isViewOnly)
                        _DisposalTypeBadge(
                            type: widget.existingDisposal!.disposalType)
                      else
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: _disposalTypes.map((entry) {
                            final (value, label, icon) = entry;
                            final isSelected = _selectedDisposalType == value;
                            final color = _disposalTypeColor(context, value);
                            return GestureDetector(
                              onTap: () => setState(
                                  () => _selectedDisposalType = value),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 12),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? color.withOpacity(0.12)
                                      : context.colors.textPrimary.withOpacity(0.02),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isSelected
                                        ? color
                                        : context.colors.borderColor.withOpacity(0.5),
                                    width: isSelected ? 2 : 1,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(icon,
                                        color: isSelected
                                            ? color
                                            : context.colors.textMuted,
                                        size: 18),
                                    const Gap(8),
                                    Text(
                                      label,
                                      style: TextStyle(
                                        color: isSelected
                                            ? color
                                            : context.colors.textSecondary,
                                        fontWeight: isSelected
                                            ? FontWeight.w700
                                            : FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ).animate().fadeIn(delay: 250.ms),

                      // ── Sold → Receipt Number ──
                      if (_selectedDisposalType == 'sold' ||
                          (_isViewOnly &&
                              widget.existingDisposal?.disposalType == 'sold')) ...[
                        const Gap(20),
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                          decoration: BoxDecoration(
                            color: context.colors.textPrimary.withOpacity(0.02),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: context.colors.borderColor.withOpacity(0.5)),
                          ),
                          child: TextField(
                            controller: _receiptNumberController,
                            readOnly: _isViewOnly,
                            style:
                                TextStyle(color: context.colors.textPrimary, fontWeight: FontWeight.bold),
                            decoration: InputDecoration(
                              labelText: 'Receipt Number *',
                              labelStyle: TextStyle(color: context.colors.textMuted, fontSize: 13),
                              border: InputBorder.none,
                              prefixIcon: Icon(Icons.receipt_rounded,
                                  color: context.colors.textMuted, size: 20),
                            ),
                          ),
                        ).animate().fadeIn(delay: 300.ms),
                      ],

                      // ── Other → Details ──
                      if (_selectedDisposalType == 'other' ||
                          (_isViewOnly &&
                              widget.existingDisposal?.disposalType == 'other')) ...[
                        const Gap(20),
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                          decoration: BoxDecoration(
                            color: context.colors.textPrimary.withOpacity(0.02),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: context.colors.borderColor.withOpacity(0.5)),
                          ),
                          child: TextField(
                            controller: _otherDetailsController,
                            readOnly: _isViewOnly,
                            maxLines: 3,
                            style:
                                TextStyle(color: context.colors.textPrimary),
                            decoration: InputDecoration(
                              labelText: 'Details *',
                              labelStyle: TextStyle(color: context.colors.textMuted, fontSize: 13),
                              border: InputBorder.none,
                              alignLabelWithHint: true,
                              prefixIcon: Padding(
                                padding: const EdgeInsets.only(bottom: 42),
                                child: Icon(Icons.notes_rounded,
                                    color: context.colors.textMuted, size: 20),
                              ),
                            ),
                          ),
                        ).animate().fadeIn(delay: 300.ms),
                      ],

                      // ── View Only — disposed info ──
                      if (_isViewOnly &&
                          widget.existingDisposal != null) ...[
                        const Gap(24),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: context.colors.successGreen.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: context.colors.successGreen
                                    .withOpacity(0.3)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.check_circle_rounded,
                                  color: context.colors.successGreen),
                              const Gap(12),
                              Expanded(
                                child: Text.rich(
                                  TextSpan(
                                    children: [
                                      const TextSpan(text: 'Disposed on '),
                                      TextSpan(
                                          text: DateFormat('yyyy-MM-dd')
                                              .format(widget.existingDisposal!
                                                  .disposedAt),
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold)),
                                      const TextSpan(text: ' by '),
                                      TextSpan(
                                          text: widget.existingDisposal!
                                              .disposedByName,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                  style: TextStyle(
                                      color: context.colors.textPrimary,
                                      fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        ).animate().fadeIn(delay: 300.ms),
                      ],
                    ],
                  ),
                ),
              ),

              // ── Dialog Footer ──
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                decoration: BoxDecoration(
                  color: context.colors.surfaceDark,
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
                  border: Border(top: BorderSide(color: context.colors.borderColor)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (!_isViewOnly)
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        style: TextButton.styleFrom(
                          foregroundColor: context.colors.textSecondary,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                        ),
                        child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    if (_isViewOnly)
                      OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text('Close'),
                      )
                    else ...[
                      const Gap(12),
                      ElevatedButton.icon(
                        icon: _isLoading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.save_rounded, size: 18),
                        label: const Text('Save Disposal', style: TextStyle(fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: context.colors.primaryGold,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: _isLoading || _selectedDisposalType == null
                            ? null
                            : _handleSave,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _disposalTypeColor(BuildContext context, String type) {
    return switch (type) {
      'sold' => context.colors.successGreen,
      're_export' => context.colors.accentLightBlue,
      'govt_use' => context.colors.primaryGold,
      'destroy' => context.colors.dangerRed,
      _ => context.colors.textSecondary,
    };
  }
}

// ── Info Grid (read-only package details) ───────────────────────

class _InfoGrid extends StatelessWidget {
  final ForfeitedPackageModel forfeited;
  const _InfoGrid({required this.forfeited});

  @override
  Widget build(BuildContext context) {
    final pkg = forfeited.packageDetails;
    final fields = <(String, String)>[
      ('SR Number', forfeited.srNumber),
      ('Consignee', forfeited.consigneeName),
      ('Forfeited Date',
          DateFormat('yyyy-MM-dd').format(forfeited.forfeitedAt)),
      ('Appeal Deadline',
          DateFormat('yyyy-MM-dd').format(forfeited.appealDeadline)),
      ('Reason', forfeited.reason),
      if (pkg != null) ...[
        ('Weight', '${pkg.weightKg} kg'),
        ('Declared Value', 'LKR ${NumberFormat('#,##0').format(pkg.declaredValue)}'),
        if (pkg.cusdecNo != null) ('CUSDEC No.', pkg.cusdecNo!),
        if (pkg.originCountry.isNotEmpty) ('Origin', pkg.originCountry),
        if (pkg.consigneeNic != null && pkg.consigneeNic!.isNotEmpty)
          ('NIC', pkg.consigneeNic!),
      ],
    ];

    return Wrap(
      spacing: 12,
      runSpacing: 10,
      children: fields.map((f) {
        final (label, value) = f;
        return Container(
          width: 220,
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: context.colors.surfaceDark,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: context.colors.borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(
                      color: context.colors.textMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5)),
              const Gap(3),
              Text(value,
                  style: TextStyle(
                      color: context.colors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13),
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ── Section Label ────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _SectionLabel(
      {required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 16),
        const Gap(8),
        Text(label,
            style: TextStyle(
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: 13,
                letterSpacing: 0.3)),
      ],
    );
  }
}

// ── Stat Chip ─────────────────────────────────────────────────────

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatChip(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value,
              style: TextStyle(
                  color: color, fontWeight: FontWeight.w800, fontSize: 16)),
          Text(label,
              style: TextStyle(
                  color: context.colors.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
