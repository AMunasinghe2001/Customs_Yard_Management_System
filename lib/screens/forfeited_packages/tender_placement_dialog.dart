import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:gap/gap.dart';
import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/error_view.dart';
import '../../widgets/one_tap_date_picker.dart';

/// Place a tender. In [reTender] mode the package pool is the tendered-but-unsold
/// packages (`reTenderablePackagesProvider`) instead of fresh appeal-passed
/// forfeited packages — so unsold lots can be tendered again under a new number.
class TenderPlacementDialog extends ConsumerStatefulWidget {
  final WidgetRef ref;
  final VoidCallback onTenderCreated;
  final bool reTender;

  const TenderPlacementDialog({
    super.key,
    required this.ref,
    required this.onTenderCreated,
    this.reTender = false,
  });

  @override
  ConsumerState<TenderPlacementDialog> createState() =>
      _TenderPlacementDialogState();
}

class _TenderPlacementDialogState extends ConsumerState<TenderPlacementDialog> {
  final _tenderNumberController = TextEditingController();
  DateTime _tenderDate = DateTime.now();
  DateTime? _saleDate;
  TimeOfDay? _saleTime;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(selectedTenderPackagesProvider.notifier).state = {};
    });
  }

  @override
  void dispose() {
    _tenderNumberController.dispose();
    super.dispose();
  }

  String _itemSummary(ForfeitedPackageModel f) {
    final items = f.packageDetails?.items ?? const [];
    if (items.isEmpty) return 'Multiple/Unspecified';
    if (items.length == 1) return items.first.itemName;
    return '${items.first.itemName} +${items.length - 1}';
  }

  String? get _saleTimeText =>
      _saleTime == null ? null : '${_saleTime!.hour.toString().padLeft(2, '0')}:${_saleTime!.minute.toString().padLeft(2, '0')}';

  Future<void> _submit(List<ForfeitedPackageModel> packages) async {
    final selected = ref.read(selectedTenderPackagesProvider);
    final tenderNumber = _tenderNumberController.text.trim();
    if (tenderNumber.isEmpty) {
      _snack('Please enter a tender number');
      return;
    }
    if (selected.isEmpty) {
      _snack('Please select at least one package');
      return;
    }

    setState(() => _isLoading = true);
    try {
      await ref.read(tendersServiceProvider).createTender(
            tenderNumber: tenderNumber,
            tenderDate: _tenderDate,
            saleDate: _saleDate,
            saleTime: _saleTimeText,
            forfeitedPackageIds: selected.toList(),
          );
      ref.invalidate(tendersProvider);
      ref.invalidate(forfeitedPackagesProvider);
      ref.invalidate(reTenderablePackagesProvider);
      ref.read(selectedTenderPackagesProvider.notifier).state = {};
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(widget.reTender
              ? 'Re-tender created (${selected.length} package${selected.length == 1 ? '' : 's'})'
              : 'Tender created successfully'),
          backgroundColor: context.colors.successGreen,
          duration: const Duration(seconds: 2),
        ));
        widget.onTenderCreated();
        Navigator.pop(context);
      }
    } catch (e) {
      _snack('Error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selected = ref.watch(selectedTenderPackagesProvider);

    // Package pool + per-package tender count (re-tender mode only).
    final AsyncValue<List<ForfeitedPackageModel>> poolAsync;
    final Map<String, int> tenderCounts = {};
    if (widget.reTender) {
      final re = ref.watch(reTenderablePackagesProvider);
      poolAsync = re.whenData((list) {
        for (final i in list) {
          tenderCounts[i.forfeited.id] = i.tenderCount;
        }
        return list.map((i) => i.forfeited).toList();
      });
    } else {
      poolAsync = ref.watch(expiredAppealPackagesProvider);
    }

    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 400),
      tween: Tween(begin: 0.0, end: 1.0),
      curve: Curves.easeOutBack,
      builder: (context, value, child) => Transform.scale(
        scale: value,
        child: Opacity(opacity: value.clamp(0.0, 1.0), child: child),
      ),
      child: Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Container(
          width: 820,
          decoration: BoxDecoration(
            color: context.colors.scaffoldBg,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.4),
                  blurRadius: 40,
                  offset: const Offset(0, 15)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Header ──
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDark
                        ? [context.colors.surfaceDark, context.colors.cardDark]
                        : [
                            context.colors.customsBlue,
                            context.colors.customsBlueDark
                          ],
                  ),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.gavel_rounded,
                        color: context.colors.primaryGold, size: 24),
                  ).animate().scale(duration: 400.ms, curve: Curves.easeOutBack),
                  const Gap(16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('TENDER MANAGEMENT',
                            style: TextStyle(
                                color: context.colors.primaryGold,
                                fontSize: 11,
                                letterSpacing: 1.2,
                                fontWeight: FontWeight.w800)),
                        Text(widget.reTender ? 'Re-tender Packages' : 'Place New Tender',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close_rounded,
                        color: Colors.white.withOpacity(0.7)),
                    splashRadius: 24,
                  ),
                ]),
              ),

              // ── Body ──
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      _Section(
                        title: 'Tender Details',
                        icon: Icons.info_outline_rounded,
                        child: Column(
                          children: [
                            Row(children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _tenderNumberController,
                                  style: TextStyle(
                                      color: context.colors.textPrimary,
                                      fontWeight: FontWeight.bold),
                                  decoration: _dec(context,
                                      label: 'Tender Number *',
                                      icon: Icons.numbers_rounded),
                                ),
                              ),
                              const Gap(16),
                              Expanded(
                                child: _DateField(
                                  label: 'Tender Date *',
                                  value: _tenderDate,
                                  onTap: () async {
                                    final d = await showDialog<DateTime>(
                                      context: context,
                                      builder: (_) => OneTapDatePicker(
                                          initialDate: _tenderDate),
                                    );
                                    if (d != null) setState(() => _tenderDate = d);
                                  },
                                ),
                              ),
                            ]),
                            const Gap(16),
                            Row(children: [
                              Expanded(
                                child: _DateField(
                                  label: 'Tender Sale Date',
                                  value: _saleDate,
                                  hint: 'Select sale date',
                                  onTap: () async {
                                    final d = await showDialog<DateTime>(
                                      context: context,
                                      builder: (_) => OneTapDatePicker(
                                          initialDate:
                                              _saleDate ?? _tenderDate),
                                    );
                                    if (d != null) setState(() => _saleDate = d);
                                  },
                                ),
                              ),
                              const Gap(16),
                              Expanded(
                                child: InkWell(
                                  onTap: () async {
                                    final t = await showTimePicker(
                                      context: context,
                                      initialTime:
                                          _saleTime ?? TimeOfDay.now(),
                                    );
                                    if (t != null) setState(() => _saleTime = t);
                                  },
                                  child: InputDecorator(
                                    decoration: _dec(context,
                                        label: 'Sale Start Time',
                                        icon: Icons.schedule_rounded),
                                    child: Text(
                                      _saleTimeText ?? 'Select time',
                                      style: TextStyle(
                                          color: _saleTime == null
                                              ? context.colors.textMuted
                                              : context.colors.textPrimary,
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ),
                              ),
                            ]),
                          ],
                        ),
                      ),
                      const Gap(16),
                      _Section(
                        title: widget.reTender
                            ? 'Select Packages — unsold, re-tenderable (${selected.length} selected)'
                            : 'Select Packages — appeal period passed (${selected.length} selected)',
                        icon: Icons.inventory_2_rounded,
                        child: poolAsync.when(
                          loading: () => const Padding(
                              padding: EdgeInsets.all(32),
                              child:
                                  Center(child: CircularProgressIndicator())),
                          error: (e, _) => Padding(
                            padding: const EdgeInsets.all(16),
                            child: ErrorView(
                                error: e.toString(),
                                onRetry: () => widget.reTender
                                    ? ref.refresh(
                                        reTenderablePackagesProvider)
                                    : ref.refresh(
                                        expiredAppealPackagesProvider)),
                          ),
                          data: (packages) =>
                              _packageList(context, packages, selected, tenderCounts),
                        ),
                      ),
                      const Gap(28),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            style: TextButton.styleFrom(
                                foregroundColor: context.colors.textSecondary,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 24, vertical: 16)),
                            child: const Text('Cancel',
                                style:
                                    TextStyle(fontWeight: FontWeight.bold)),
                          ),
                          const Gap(12),
                          ElevatedButton.icon(
                            icon: _isLoading
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.gavel_rounded, size: 18),
                            label: Text(
                                widget.reTender
                                    ? 'Re-tender'
                                    : 'Create Tender',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: context.colors.primaryGold,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 28, vertical: 16),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: _isLoading
                                ? null
                                : () => _submit(poolAsync.valueOrNull ?? []),
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

  Widget _packageList(BuildContext context, List<ForfeitedPackageModel> packages,
      Set<String> selected, Map<String, int> tenderCounts) {
    if (packages.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Column(children: [
            Icon(Icons.check_circle,
                size: 48, color: context.colors.successGreen.withOpacity(0.5)),
            const Gap(12),
            Text(
                widget.reTender
                    ? 'No unsold packages awaiting a re-tender'
                    : 'No packages with expired appeals',
                style: TextStyle(color: context.colors.textSecondary)),
          ]),
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          Text('${selected.length} of ${packages.length} selected',
              style: TextStyle(
                  color: context.colors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
          const Spacer(),
          TextButton.icon(
            onPressed: () => ref
                .read(selectedTenderPackagesProvider.notifier)
                .state = packages.map((p) => p.id).toSet(),
            icon: Icon(Icons.done_all_rounded,
                size: 16, color: context.colors.primaryGold),
            label: Text('Select All',
                style: TextStyle(
                    color: context.colors.primaryGold,
                    fontWeight: FontWeight.bold,
                    fontSize: 12)),
          ),
          TextButton.icon(
            onPressed: () =>
                ref.read(selectedTenderPackagesProvider.notifier).state = {},
            icon: Icon(Icons.clear_all_rounded,
                size: 16, color: context.colors.textMuted),
            label: Text('Clear All',
                style: TextStyle(
                    color: context.colors.textMuted,
                    fontWeight: FontWeight.bold,
                    fontSize: 12)),
          ),
        ]),
        const Gap(8),
        Container(
          constraints: const BoxConstraints(maxHeight: 320),
          decoration: BoxDecoration(
            color: context.colors.textPrimary.withOpacity(0.02),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.colors.borderColor),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: packages.length,
              separatorBuilder: (_, __) => Divider(
                  height: 1,
                  color: context.colors.borderColor.withOpacity(0.5)),
              itemBuilder: (context, i) {
                final pkg = packages[i];
                final isSelected = selected.contains(pkg.id);
                final count = tenderCounts[pkg.id];
                return InkWell(
                  onTap: () => _toggle(pkg.id, isSelected),
                  child: Container(
                    color: isSelected
                        ? context.colors.primaryGold.withOpacity(0.06)
                        : Colors.transparent,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    child: Row(children: [
                      Checkbox(
                        activeColor: context.colors.primaryGold,
                        value: isSelected,
                        onChanged: (_) => _toggle(pkg.id, isSelected),
                      ),
                      Expanded(
                        flex: 5,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(pkg.srNumber,
                                style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: context.colors.accentLightBlue)),
                            Text(_itemSummary(pkg),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 12,
                                    color: context.colors.textSecondary)),
                          ],
                        ),
                      ),
                      Expanded(
                        flex: 4,
                        child: Text(pkg.consigneeName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 13,
                                color: context.colors.textPrimary)),
                      ),
                      if (count != null && count > 0) ...[
                        const Gap(8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: context.colors.warningAmber.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                                color:
                                    context.colors.warningAmber.withOpacity(0.4)),
                          ),
                          child: Text('Tendered ${count}×',
                              style: TextStyle(
                                  color: context.colors.warningAmber,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ]),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  void _toggle(String id, bool isSelected) {
    ref.read(selectedTenderPackagesProvider.notifier).update((state) {
      final s = Set<String>.from(state);
      if (isSelected) {
        s.remove(id);
      } else {
        s.add(id);
      }
      return s;
    });
  }

  InputDecoration _dec(BuildContext context,
      {required String label, required IconData icon}) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: context.colors.primaryGold, size: 20),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: context.colors.borderColor)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: context.colors.borderColor)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              BorderSide(color: context.colors.primaryGold, width: 2)),
      filled: true,
      fillColor: context.colors.textPrimary.withOpacity(0.02),
    );
  }
}

class _DateField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final String? hint;
  final VoidCallback onTap;
  const _DateField(
      {required this.label, required this.value, required this.onTap, this.hint});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(Icons.calendar_today_rounded,
              color: context.colors.primaryGold, size: 20),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: context.colors.borderColor)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: context.colors.borderColor)),
          filled: true,
          fillColor: context.colors.textPrimary.withOpacity(0.02),
        ),
        child: Text(
          value != null
              ? DateFormat('yyyy-MM-dd').format(value!)
              : (hint ?? 'Select date'),
          style: TextStyle(
              color: value == null
                  ? context.colors.textMuted
                  : context.colors.textPrimary,
              fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  const _Section(
      {required this.title, required this.icon, required this.child});
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
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(15)),
              border:
                  Border(bottom: BorderSide(color: context.colors.borderColor)),
            ),
            child: Row(children: [
              Icon(icon, size: 18, color: context.colors.primaryGold),
              const Gap(10),
              Expanded(
                child: Text(title.toUpperCase(),
                    style: TextStyle(
                        color: context.colors.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8)),
              ),
            ]),
          ),
          Padding(padding: const EdgeInsets.all(16), child: child),
        ],
      ),
    );
  }
}
