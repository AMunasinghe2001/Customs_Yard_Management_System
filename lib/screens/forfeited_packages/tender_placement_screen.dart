import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../services/report_service.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/error_view.dart';
import '../../widgets/one_tap_date_picker.dart';
import '../../widgets/app_dialog.dart';

class TenderPlacementScreen extends ConsumerStatefulWidget {
  const TenderPlacementScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<TenderPlacementScreen> createState() =>
      _TenderPlacementScreenState();
}

class _TenderPlacementScreenState
    extends ConsumerState<TenderPlacementScreen> {
  late TextEditingController _tenderNumberController;
  DateTime? _selectedDate;
  bool _isLoading = false;
  bool _isGeneratingReport = false;

  @override
  void initState() {
    super.initState();
    _tenderNumberController = TextEditingController();
    _selectedDate = DateTime.now();
  }

  @override
  void dispose() {
    _tenderNumberController.dispose();
    super.dispose();
  }

  Future<void> _handleGenerateReport(
      List<ForfeitedPackageModel> selectedPackages) async {
    if (selectedPackages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please select at least one package first')),
      );
      return;
    }
    setState(() => _isGeneratingReport = true);
    try {
      final pdfBytes = await ReportService().generateTenderPackagesPdf(
        selectedPackages,
        tenderNumber: _tenderNumberController.text.trim().isNotEmpty
            ? _tenderNumberController.text.trim()
            : 'DRAFT',
        tenderDate: _selectedDate ?? DateTime.now(),
      );
      await Printing.layoutPdf(onLayout: (_) async => pdfBytes);
    } catch (e) {
      if (mounted) {
        showErrorSnack(context, e);
      }
    } finally {
      if (mounted) setState(() => _isGeneratingReport = false);
    }
  }

  void _handleTenderCreation(
      List<ForfeitedPackageModel> allExpired) async {
    final selectedIds = ref.read(selectedTenderPackagesProvider);
    final tenderNumber = _tenderNumberController.text.trim();
    final tenderDate = _selectedDate;

    if (tenderNumber.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a tender number')),
      );
      return;
    }
    if (selectedIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one package')),
      );
      return;
    }
    if (tenderDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a tender date')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      await ref.read(tendersServiceProvider).createTender(
            tenderNumber: tenderNumber,
            tenderDate: tenderDate,
            forfeitedPackageIds: selectedIds.toList(),
          );

      ref.invalidate(tendersProvider);
      ref.invalidate(forfeitedPackagesProvider);
      ref.read(selectedTenderPackagesProvider.notifier).state = {};

      context.showSuccess('Tender created successfully');
      if (mounted) context.go('/tender-disposals');
    } catch (e) {
      showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final expiredAsync = ref.watch(expiredAppealPackagesProvider);
    final selectedIds = ref.watch(selectedTenderPackagesProvider);

    return AppShell(
      currentRoute: '/forfeited-packages',
      child: Scaffold(
        backgroundColor: context.colors.scaffoldBg,
        body: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ──────────────────────────────────────────
              Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back_rounded,
                        color: context.colors.textSecondary),
                    onPressed: () => context.go('/forfeited-packages'),
                    tooltip: 'Back to Forfeited Packages',
                  ),
                  const Gap(8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Place Tender',
                          style: Theme.of(context).textTheme.headlineLarge),
                      Text(
                        'Create a new tender for expired-appeal packages',
                        style: TextStyle(color: context.colors.textSecondary),
                      ),
                    ],
                  ),
                ],
              ).animate().fadeIn(),
              const Gap(24),

              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Tender Details Card ──────────────────────
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: context.colors.cardDark,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: context.colors.primaryGold
                                  .withOpacity(0.4)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.assignment_rounded,
                                    color: context.colors.primaryGold,
                                    size: 20),
                                const Gap(8),
                                Text(
                                  'Tender Details',
                                  style: TextStyle(
                                    color: context.colors.primaryGold,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                  ),
                                ),
                              ],
                            ),
                            const Gap(20),
                            Row(
                              children: [
                                // Tender Number
                                Expanded(
                                  child: TextField(
                                    controller: _tenderNumberController,
                                    style: TextStyle(
                                        color: context.colors.textPrimary),
                                    decoration: InputDecoration(
                                      labelText: 'Tender Number *',
                                      prefixIcon: Icon(Icons.tag_rounded,
                                          color: context.colors.textMuted,
                                          size: 18),
                                    ),
                                  ),
                                ),
                                const Gap(16),
                                // Tender Date
                                Expanded(
                                  child: InkWell(
                                    onTap: () async {
                                      // Same custom picker as everywhere else.
                                      // Tender dates can be future (scheduling),
                                      // so no lastDate cap.
                                      final date = await showAppDialog<DateTime>(
                                        context: context,
                                        builder: (_) => OneTapDatePicker(
                                            initialDate:
                                                _selectedDate ?? DateTime.now()),
                                      );
                                      if (date != null) {
                                        setState(
                                            () => _selectedDate = date);
                                      }
                                    },
                                    child: InputDecorator(
                                      decoration: InputDecoration(
                                        labelText: 'Tender Date *',
                                        prefixIcon: Icon(
                                            Icons.calendar_today_rounded,
                                            color: context.colors.textMuted,
                                            size: 18),
                                      ),
                                      child: Text(
                                        _selectedDate != null
                                            ? DateFormat('yyyy-MM-dd')
                                                .format(_selectedDate!)
                                            : 'Select date',
                                        style: TextStyle(
                                            color:
                                                context.colors.textPrimary),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      )
                          .animate()
                          .slideY(
                              begin: 0.1, duration: 400.ms, delay: 100.ms)
                          .fadeIn(),

                      const Gap(20),

                      // ── Package Selection ─────────────────────────
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: context.colors.cardDark,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: context.colors.borderColor),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.checklist_rounded,
                                        color: context.colors.dangerRed,
                                        size: 20),
                                    const Gap(8),
                                    Text(
                                      'Select Packages for Tender',
                                      style: TextStyle(
                                        color: context.colors.dangerRed,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 15,
                                      ),
                                    ),
                                    const Gap(8),
                                    if (selectedIds.isNotEmpty)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: context.colors.dangerRed
                                              .withOpacity(0.15),
                                          borderRadius:
                                              BorderRadius.circular(20),
                                        ),
                                        child: Text(
                                          '${selectedIds.length} selected',
                                          style: TextStyle(
                                              color:
                                                  context.colors.dangerRed,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600),
                                        ),
                                      ),
                                  ],
                                ),
                                // Generate Report button
                                expiredAsync.when(
                                  data: (pkgs) {
                                    final selected = pkgs
                                        .where((p) =>
                                            selectedIds.contains(p.id))
                                        .toList();
                                    return OutlinedButton.icon(
                                      icon: _isGeneratingReport
                                          ? const SizedBox(
                                              width: 14,
                                              height: 14,
                                              child:
                                                  CircularProgressIndicator(
                                                      strokeWidth: 2))
                                          : const Icon(
                                              Icons.print_rounded,
                                              size: 16),
                                      label: const Text(
                                          'Generate Report',
                                          style: TextStyle(fontSize: 13)),
                                      onPressed: _isGeneratingReport
                                          ? null
                                          : () => _handleGenerateReport(
                                              selected),
                                    );
                                  },
                                  loading: () => const SizedBox(),
                                  error: (_, __) => const SizedBox(),
                                ),
                              ],
                            ),
                            const Gap(4),
                            Text(
                              'Only packages with expired 30-day appeal periods are eligible for tendering',
                              style: TextStyle(
                                  color: context.colors.textMuted,
                                  fontSize: 12),
                            ),
                            const Gap(16),

                            // Package table
                            expiredAsync.when(
                              loading: () => const Padding(
                                padding: EdgeInsets.all(32.0),
                                child: Center(
                                    child: CircularProgressIndicator()),
                              ),
                              error: (error, _) => ErrorView(
                                error: error.toString(),
                                onRetry: () => ref.refresh(
                                    expiredAppealPackagesProvider),
                              ),
                              data: (packages) {
                                if (packages.isEmpty) {
                                  return Container(
                                    padding: const EdgeInsets.all(32),
                                    alignment: Alignment.center,
                                    child: Column(
                                      children: [
                                        Icon(Icons.check_circle_outline,
                                            color:
                                                context.colors.successGreen,
                                            size: 36),
                                        const Gap(12),
                                        Text(
                                          'No packages with expired appeals available for tendering',
                                          style: TextStyle(
                                              color: context
                                                  .colors.textSecondary),
                                          textAlign: TextAlign.center,
                                        ),
                                      ],
                                    ),
                                  );
                                }

                                return Container(
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                        color: context.colors.borderColor),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Column(
                                    children: [
                                      // Select All row
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 8),
                                        child: Row(
                                          children: [
                                            Checkbox(
                                              value: selectedIds.length ==
                                                  packages.length,
                                              tristate: true,
                                              onChanged: (_) {
                                                ref
                                                    .read(
                                                        selectedTenderPackagesProvider
                                                            .notifier)
                                                    .update((state) {
                                                  if (state.length ==
                                                      packages.length) {
                                                    return {};
                                                  }
                                                  return packages
                                                      .map((p) => p.id)
                                                      .toSet();
                                                });
                                              },
                                              activeColor:
                                                  context.colors.primaryGold,
                                            ),
                                            const Gap(8),
                                            Text(
                                              'Select All (${packages.length} packages)',
                                              style: TextStyle(
                                                  color: context
                                                      .colors.textSecondary,
                                                  fontSize: 13),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Divider(
                                          height: 1,
                                          color: context.colors.borderColor),
                                      ...packages.map((pkg) {
                                        final isSelected =
                                            selectedIds.contains(pkg.id);
                                        return _PackageSelectRow(
                                          pkg: pkg,
                                          isSelected: isSelected,
                                          onToggle: () {
                                            ref
                                                .read(
                                                    selectedTenderPackagesProvider
                                                        .notifier)
                                                .update((state) {
                                              final newState =
                                                  Set<String>.from(state);
                                              if (isSelected) {
                                                newState.remove(pkg.id);
                                              } else {
                                                newState.add(pkg.id);
                                              }
                                              return newState;
                                            });
                                          },
                                        );
                                      }),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      )
                          .animate()
                          .slideY(
                              begin: 0.1, duration: 400.ms, delay: 200.ms)
                          .fadeIn(),

                      const Gap(24),

                      // ── Create Tender Button ──────────────────────
                      expiredAsync.when(
                        data: (pkgs) => SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton.icon(
                            icon: _isLoading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2))
                                : const Icon(Icons.check_circle_outline_rounded),
                            label: const Text('Create Tender',
                                style: TextStyle(fontSize: 16)),
                            onPressed: _isLoading
                                ? null
                                : () => _handleTenderCreation(pkgs),
                          ),
                        ),
                        loading: () => const SizedBox(),
                        error: (_, __) => const SizedBox(),
                      )
                          .animate()
                          .slideY(
                              begin: 0.1, duration: 400.ms, delay: 300.ms)
                          .fadeIn(),
                      const Gap(24),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Package Row in Selection Table ──────────────────────────────

class _PackageSelectRow extends StatelessWidget {
  final ForfeitedPackageModel pkg;
  final bool isSelected;
  final VoidCallback onToggle;

  const _PackageSelectRow({
    required this.pkg,
    required this.isSelected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onToggle,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? context.colors.primaryGold.withOpacity(0.08)
              : Colors.transparent,
          border: Border(
              bottom:
                  BorderSide(color: context.colors.borderColor, width: 0.5)),
        ),
        child: Row(
          children: [
            Checkbox(
              value: isSelected,
              onChanged: (_) => onToggle(),
              activeColor: context.colors.primaryGold,
            ),
            const Gap(8),
            Expanded(
              flex: 2,
              child: Text(
                pkg.srNumber,
                style: TextStyle(
                  color: context.colors.accentLightBlue,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                pkg.consigneeName,
                style: TextStyle(
                    color: context.colors.textPrimary, fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Deadline: ${DateFormat('yyyy-MM-dd').format(pkg.appealDeadline)}',
                    style: TextStyle(
                        color: context.colors.dangerRed,
                        fontSize: 11,
                        fontWeight: FontWeight.w600),
                  ),
                  Text(
                    'Forfeited: ${DateFormat('yyyy-MM-dd').format(pkg.forfeitedAt)}',
                    style: TextStyle(
                        color: context.colors.textMuted, fontSize: 11),
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
