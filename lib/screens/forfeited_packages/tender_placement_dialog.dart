import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:gap/gap.dart';
import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../widgets/error_view.dart';

class TenderPlacementDialog extends ConsumerStatefulWidget {
  final WidgetRef ref;
  final VoidCallback onTenderCreated;

  const TenderPlacementDialog({
    Key? key,
    required this.ref,
    required this.onTenderCreated,
  }) : super(key: key);

  @override
  ConsumerState<TenderPlacementDialog> createState() =>
      _TenderPlacementDialogState();
}

class _TenderPlacementDialogState extends ConsumerState<TenderPlacementDialog> {
  late TextEditingController _tenderNumberController;
  DateTime? _selectedDate;
  bool _isLoading = false;

  bool _isForfeitStatus(String? status) {
    if (status == null) return false;
    final normalized = status.trim().toLowerCase();
    return normalized == 'forfiet' || normalized == 'forfeit' || normalized == 'forfeited';
  }

  @override
  void initState() {
    super.initState();
    _tenderNumberController = TextEditingController();
  }

  @override
  void dispose() {
    _tenderNumberController.dispose();
    super.dispose();
  }

  void _handleTenderCreation() async {
    final selectedPackageIds = ref.read(selectedTenderPackagesProvider);
    final tenderNumber = _tenderNumberController.text.trim();
    final tenderDate = _selectedDate;

    if (tenderNumber.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a tender number')),
      );
      return;
    }

    if (selectedPackageIds.isEmpty) {
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
        forfeitedPackageIds: selectedPackageIds.toList(),
      );

      // Refresh providers
      ref.invalidate(tendersProvider);
      ref.invalidate(forfeitedPackagesProvider);
      ref.read(selectedTenderPackagesProvider.notifier).state = {};

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tender created successfully'),
          duration: Duration(seconds: 2),
        ),
      );

      widget.onTenderCreated();
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ')),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final expiredAsync = ref.watch(expiredAppealPackagesProvider);
    final selectedPackages = ref.watch(selectedTenderPackagesProvider);
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
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Container(
          width: 750,
          decoration: BoxDecoration(
            color: context.colors.scaffoldBg,
            borderRadius: BorderRadius.circular(24),
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
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
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
                            'TENDER MANAGEMENT',
                            style: TextStyle(
                              color: context.colors.primaryGold,
                              fontSize: 11,
                              letterSpacing: 1.2,
                              fontWeight: FontWeight.w800,
                            ),
                          ).animate().fadeIn(duration: 400.ms, delay: 100.ms),
                          const Text(
                            'Place New Tender',
                            style: TextStyle(
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
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.close_rounded, color: Colors.white.withOpacity(0.7)),
                      splashRadius: 24,
                    ),
                  ],
                ),
              ),

              // ── Dialog Body ──
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      // Tender Info Section
                      _SectionContainer(
                        title: 'Tender Details',
                        icon: Icons.info_outline_rounded,
                        delay: 100,
                        child: Row(
                          children: [
                            Expanded(
                              child: _InputContainer(
                                icon: Icons.numbers_rounded,
                                child: TextField(
                                  controller: _tenderNumberController,
                                  style: TextStyle(color: context.colors.textPrimary, fontWeight: FontWeight.bold),
                                  decoration: InputDecoration(
                                    labelText: 'Tender Number *',
                                    labelStyle: TextStyle(color: context.colors.textMuted, fontSize: 12),
                                    border: InputBorder.none,
                                    isDense: true,
                                    contentPadding: EdgeInsets.zero,
                                    floatingLabelBehavior: FloatingLabelBehavior.always,
                                  ),
                                ),
                              ),
                            ),
                            const Gap(16),
                            Expanded(
                              child: _InputContainer(
                                icon: Icons.calendar_today_rounded,
                                child: InkWell(
                                  onTap: () async {
                                    final date = await showDatePicker(
                                      context: context,
                                      initialDate: _selectedDate ?? DateTime.now(),
                                      firstDate: DateTime(2020),
                                      lastDate: DateTime(2100),
                                      builder: (context, child) {
                                        return Theme(
                                          data: Theme.of(context).copyWith(
                                            colorScheme: isDark 
                                                ? const ColorScheme.dark().copyWith(primary: context.colors.primaryGold)
                                                : const ColorScheme.light().copyWith(primary: context.colors.customsBlue),
                                          ),
                                          child: child!,
                                        );
                                      },
                                    );
                                    if (date != null) {
                                      setState(() => _selectedDate = date);
                                    }
                                  },
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text('Tender Date *', style: TextStyle(color: context.colors.textMuted, fontSize: 11, fontWeight: FontWeight.bold)),
                                      const Gap(4),
                                      Text(
                                        _selectedDate != null ? DateFormat('yyyy-MM-dd').format(_selectedDate!) : 'Select Date',
                                        style: TextStyle(
                                          color: _selectedDate != null ? context.colors.textPrimary : context.colors.textMuted,
                                          fontSize: 13,
                                          fontWeight: _selectedDate != null ? FontWeight.bold : FontWeight.normal,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      const Gap(16),

                      // Packages Section
                      _SectionContainer(
                        title: 'Select Packages (${selectedPackages.length} selected)',
                        icon: Icons.inventory_2_rounded,
                        delay: 200,
                        child: expiredAsync.when(
                          loading: () => const Padding(
                            padding: EdgeInsets.all(32.0),
                            child: Center(child: CircularProgressIndicator()),
                          ),
                          error: (error, stackTrace) => Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: ErrorView(
                              error: error.toString(),
                              onRetry: () => ref.refresh(expiredAppealPackagesProvider),
                            ),
                          ),
                          data: (packages) {
                            if (packages.isEmpty) {
                              return Padding(
                                padding: const EdgeInsets.all(32.0),
                                child: Center(
                                  child: Column(
                                    children: [
                                      Icon(Icons.check_circle, size: 48, color: context.colors.successGreen.withOpacity(0.5)),
                                      const Gap(12),
                                      Text(
                                        'No packages with expired appeals',
                                        style: TextStyle(color: context.colors.textSecondary),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }

                            return Container(
                              height: 300,
                              decoration: BoxDecoration(
                                color: context.colors.textPrimary.withOpacity(0.02),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: context.colors.borderColor),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: SingleChildScrollView(
                                  child: DataTable(
                                    headingRowColor: MaterialStateProperty.all(context.colors.textPrimary.withOpacity(0.05)),
                                    dataRowMinHeight: 45,
                                    dataRowMaxHeight: 55,
                                    horizontalMargin: 16,
                                    columns: [
                                      DataColumn(label: Text('Select', style: TextStyle(color: context.colors.textMuted, fontWeight: FontWeight.bold))),
                                      DataColumn(label: Text('SR Number', style: TextStyle(color: context.colors.textMuted, fontWeight: FontWeight.bold))),
                                      DataColumn(label: Text('Item Name', style: TextStyle(color: context.colors.textMuted, fontWeight: FontWeight.bold))),
                                      DataColumn(label: Text('Consignee', style: TextStyle(color: context.colors.textMuted, fontWeight: FontWeight.bold))),
                                      DataColumn(label: Text('Deadline', style: TextStyle(color: context.colors.textMuted, fontWeight: FontWeight.bold))),
                                    ],
                                    rows: packages.expand((pkg) {
                                      final forfeitedItems = pkg.packageDetails?.items.where((i) => _isForfeitStatus(i.status)).toList() ?? [];
                                      final itemsToShow = forfeitedItems.isEmpty ? [null] : forfeitedItems;
                                      
                                      return itemsToShow.map((item) {
                                        final isSelected = selectedPackages.contains(pkg.id);
                                        return DataRow(
                                          selected: isSelected,
                                          color: MaterialStateProperty.resolveWith<Color?>((states) {
                                            if (states.contains(MaterialState.selected)) {
                                              return context.colors.primaryGold.withOpacity(0.1);
                                            }
                                            return null;
                                          }),
                                          cells: [
                                            DataCell(
                                              Checkbox(
                                                activeColor: context.colors.primaryGold,
                                                value: isSelected,
                                                onChanged: (_) {
                                                  ref.read(selectedTenderPackagesProvider.notifier).update(
                                                    (state) {
                                                      final newState = Set<String>.from(state);
                                                      if (isSelected) {
                                                        newState.remove(pkg.id);
                                                      } else {
                                                        newState.add(pkg.id);
                                                      }
                                                      return newState;
                                                    },
                                                  );
                                                },
                                              ),
                                            ),
                                            DataCell(
                                              Text(
                                                pkg.srNumber,
                                                style: TextStyle(fontWeight: FontWeight.w700, color: context.colors.textPrimary),
                                              ),
                                            ),
                                            DataCell(
                                              Text(
                                                item?.itemName ?? 'Multiple/Unspecified',
                                                style: TextStyle(color: context.colors.textPrimary, fontWeight: FontWeight.w500),
                                              ),
                                            ),
                                            DataCell(Text(pkg.consigneeName, style: TextStyle(color: context.colors.textSecondary))),
                                            DataCell(
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: context.colors.dangerRed.withOpacity(0.1),
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: Text(
                                                  DateFormat('MM/dd').format(pkg.appealDeadline),
                                                  style: TextStyle(
                                                    color: context.colors.dangerRed,
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        );
                                      });
                                    }).toList(),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      
                      const Gap(32),

                      // Action Buttons
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            style: TextButton.styleFrom(
                              foregroundColor: context.colors.textSecondary,
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                            ),
                            child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                          const Gap(12),
                          ElevatedButton.icon(
                            icon: _isLoading 
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.check_circle_rounded),
                            label: const Text('Create Tender', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: context.colors.primaryGold,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: _isLoading ? null : _handleTenderCreation,
                          ),
                        ],
                      ).animate().fadeIn(delay: 300.ms),
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

class _SectionContainer extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  final int delay;

  const _SectionContainer({
    required this.title,
    required this.icon,
    required this.child,
    required this.delay,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark 
            ? context.colors.surfaceDark.withOpacity(0.5) 
            : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.colors.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: context.colors.textPrimary.withOpacity(0.03),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
              border: Border(bottom: BorderSide(color: context.colors.borderColor)),
            ),
            child: Row(
              children: [
                Icon(icon, size: 18, color: context.colors.primaryGold),
                const Gap(10),
                Text(
                  title.toUpperCase(),
                  style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ).animate().slideX(delay: Duration(milliseconds: delay), duration: 300.ms, begin: -0.1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: child,
          ).animate().fadeIn(delay: Duration(milliseconds: delay + 100), duration: 400.ms),
        ],
      ),
    );
  }
}

class _InputContainer extends StatelessWidget {
  final IconData icon;
  final Widget child;

  const _InputContainer({
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.colors.textPrimary.withOpacity(0.02),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.borderColor.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: context.colors.primaryGold.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: context.colors.primaryGold),
          ),
          const Gap(16),
          Expanded(child: child),
        ],
      ),
    );
  }
}
