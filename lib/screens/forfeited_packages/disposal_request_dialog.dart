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

/// Yard-side form that sends a Disposal Request to the Central Disposal
/// Directorate. Unlike a tender, it has no tender number — just a request
/// date and a set of forfeited packages (appeal window passed), each tagged
/// for either DESTRUCTION or SALE.
class DisposalRequestDialog extends ConsumerStatefulWidget {
  final VoidCallback? onSubmitted;
  const DisposalRequestDialog({super.key, this.onSubmitted});

  @override
  ConsumerState<DisposalRequestDialog> createState() =>
      _DisposalRequestDialogState();
}

class _DisposalRequestDialogState extends ConsumerState<DisposalRequestDialog> {
  DateTime _requestDate = DateTime.now();
  bool _isLoading = false;
  // Guards the one-time pre-selection of appeal-decided packages so the user's
  // later edits aren't overwritten on every rebuild.
  bool _appliedAppealDefaults = false;

  @override
  void initState() {
    super.initState();
    // Start the selection fresh every time the form opens.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(selectedRequestDispositionsProvider.notifier).state = {};
    });
  }

  /// Pre-selects packages the Appeal Directorate already decided to Sell /
  /// Destroy, with that disposition pre-filled — so the yard just confirms.
  /// Runs once, after the requestable list first loads.
  void _applyAppealDecisionDefaults(List<ForfeitedPackageModel> packages) {
    if (_appliedAppealDefaults) return;
    final defaults = <String, String>{};
    for (final p in packages) {
      final d = p.appealRequestDisposition; // 'destruction' | 'sale' | null
      if (d != null) defaults[p.id] = d;
    }
    _appliedAppealDefaults = true;
    if (defaults.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final notifier = ref.read(selectedRequestDispositionsProvider.notifier);
      notifier.state = {...defaults, ...notifier.state};
    });
  }

  String _friendlyError(Object e) {
    final s = e.toString().toLowerCase();
    if (s.contains('semaphore') ||
        s.contains('socketexception') ||
        s.contains('clientexception') ||
        s.contains('failed host lookup') ||
        s.contains('timed out') ||
        s.contains('timeout')) {
      return 'Network timeout reaching the server. Check your connection and try again.';
    }
    if (s.contains('does not exist') ||
        s.contains('relation') && s.contains('disposal_requests')) {
      return 'Disposal request tables not found — run migration 20260611_disposal_requests.sql.';
    }
    return 'Error: $e';
  }

  String _itemSummary(ForfeitedPackageModel f) {
    final items = f.packageDetails?.items ?? const [];
    if (items.isEmpty) return 'Multiple/Unspecified';
    if (items.length == 1) return items.first.itemName;
    return '${items.first.itemName} +${items.length - 1}';
  }

  Future<void> _submit() async {
    final selected = ref.read(selectedRequestDispositionsProvider);
    if (selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one package')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      await ref.read(forfeitedPackageServiceProvider).createDisposalRequest(
            requestDate: _requestDate,
            dispositions: selected,
          );

      ref.read(disposalRequestsRefreshProvider.notifier).trigger();
      ref.invalidate(forfeitedPackagesProvider);
      ref.read(selectedRequestDispositionsProvider.notifier).state = {};

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Disposal request sent (${selected.length} package${selected.length == 1 ? '' : 's'})'),
            backgroundColor: context.colors.successGreen,
            duration: const Duration(seconds: 2),
          ),
        );
        widget.onSubmitted?.call();
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_friendlyError(e)),
            backgroundColor: context.colors.dangerRed,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final expiredAsync = ref.watch(requestableForfeitedPackagesProvider);
    final selected = ref.watch(selectedRequestDispositionsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
                offset: const Offset(0, 15),
              ),
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
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.local_shipping_rounded,
                          color: context.colors.primaryGold, size: 24),
                    ).animate().scale(duration: 400.ms, curve: Curves.easeOutBack),
                    const Gap(16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'CENTRAL DISPOSAL',
                            style: TextStyle(
                              color: context.colors.primaryGold,
                              fontSize: 11,
                              letterSpacing: 1.2,
                              fontWeight: FontWeight.w800,
                            ),
                          ).animate().fadeIn(duration: 400.ms, delay: 100.ms),
                          const Text(
                            'New Disposal Request',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          )
                              .animate()
                              .fadeIn(duration: 400.ms, delay: 150.ms)
                              .slideX(begin: -0.1),
                        ],
                      ),
                    ),
                    const Gap(12),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.close_rounded,
                          color: Colors.white.withOpacity(0.7)),
                      splashRadius: 24,
                    ),
                  ],
                ),
              ),

              // ── Body ──
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      // Request details — date only (no tender number).
                      _SectionContainer(
                        title: 'Request Details',
                        icon: Icons.info_outline_rounded,
                        delay: 100,
                        child: Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                key: ValueKey(_requestDate),
                                initialValue: DateFormat('yyyy-MM-dd')
                                    .format(_requestDate),
                                readOnly: true,
                                onTap: () async {
                                  final date = await showDialog<DateTime>(
                                    context: context,
                                    builder: (_) => OneTapDatePicker(
                                        initialDate: _requestDate),
                                  );
                                  if (date != null) {
                                    setState(() => _requestDate = date);
                                  }
                                },
                                style: TextStyle(
                                    color: context.colors.textPrimary,
                                    fontWeight: FontWeight.bold),
                                decoration: InputDecoration(
                                  labelText: 'Request Date *',
                                  hintText: 'Select Date',
                                  prefixIcon: Icon(Icons.calendar_today_rounded,
                                      color: context.colors.primaryGold,
                                      size: 20),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                        color: context.colors.borderColor),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                        color: context.colors.borderColor),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                        color: context.colors.primaryGold,
                                        width: 2),
                                  ),
                                  filled: true,
                                  fillColor: context.colors.textPrimary
                                      .withOpacity(0.02),
                                ),
                              ),
                            ),
                            const Gap(16),
                            // Live tally chip.
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 14),
                                decoration: BoxDecoration(
                                  color: context.colors.primaryGold
                                      .withOpacity(0.06),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                      color: context.colors.primaryGold
                                          .withOpacity(0.3)),
                                ),
                                child: Row(children: [
                                  Icon(Icons.inventory_2_rounded,
                                      size: 18,
                                      color: context.colors.primaryGold),
                                  const Gap(10),
                                  Text('${selected.length} selected',
                                      style: TextStyle(
                                          color: context.colors.textPrimary,
                                          fontWeight: FontWeight.bold)),
                                  const Spacer(),
                                  _MiniCount(
                                      label: 'Destruction',
                                      count: selected.values
                                          .where((d) => d == 'destruction')
                                          .length,
                                      color: context.colors.dangerRed),
                                  const Gap(8),
                                  _MiniCount(
                                      label: 'Sale',
                                      count: selected.values
                                          .where((d) => d == 'sale')
                                          .length,
                                      color: context.colors.successGreen),
                                ]),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const Gap(16),

                      // Packages
                      _SectionContainer(
                        title:
                            'Select Packages — appeal period passed (${selected.length} selected)',
                        icon: Icons.inventory_2_rounded,
                        delay: 200,
                        child: expiredAsync.when(
                          loading: () => const Padding(
                            padding: EdgeInsets.all(32.0),
                            child: Center(child: CircularProgressIndicator()),
                          ),
                          error: (error, _) => Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: ErrorView(
                              error: error.toString(),
                              onRetry: () => ref.refresh(
                                  requestableForfeitedPackagesProvider),
                            ),
                          ),
                          data: (packages) {
                            // Pre-fill Sale / Destroy for appeal-decided
                            // packages (runs once after the list loads).
                            _applyAppealDecisionDefaults(packages);
                            if (packages.isEmpty) {
                              return Padding(
                                padding: const EdgeInsets.all(32.0),
                                child: Center(
                                  child: Column(
                                    children: [
                                      Icon(Icons.check_circle,
                                          size: 48,
                                          color: context.colors.successGreen
                                              .withOpacity(0.5)),
                                      const Gap(12),
                                      Text(
                                        'No packages awaiting a disposal request',
                                        style: TextStyle(
                                            color:
                                                context.colors.textSecondary),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }

                            return Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      '${selected.length} of ${packages.length} selected',
                                      style: TextStyle(
                                          color: context.colors.textSecondary,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600),
                                    ),
                                    const Spacer(),
                                    TextButton.icon(
                                      onPressed: () {
                                        final map = <String, String>{};
                                        for (final p in packages) {
                                          map[p.id] = selected[p.id] ??
                                              'destruction';
                                        }
                                        ref
                                            .read(
                                                selectedRequestDispositionsProvider
                                                    .notifier)
                                            .state = map;
                                      },
                                      icon: Icon(Icons.done_all_rounded,
                                          size: 16,
                                          color: context.colors.primaryGold),
                                      label: Text('Select All',
                                          style: TextStyle(
                                              color: context.colors.primaryGold,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12)),
                                    ),
                                    TextButton.icon(
                                      onPressed: () => ref
                                          .read(
                                              selectedRequestDispositionsProvider
                                                  .notifier)
                                          .state = {},
                                      icon: Icon(Icons.clear_all_rounded,
                                          size: 16,
                                          color: context.colors.textMuted),
                                      label: Text('Clear All',
                                          style: TextStyle(
                                              color: context.colors.textMuted,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12)),
                                    ),
                                  ],
                                ),
                                const Gap(8),
                                Container(
                                  constraints:
                                      const BoxConstraints(maxHeight: 340),
                                  decoration: BoxDecoration(
                                    color: context.colors.textPrimary
                                        .withOpacity(0.02),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                        color: context.colors.borderColor),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: ListView.separated(
                                      shrinkWrap: true,
                                      itemCount: packages.length,
                                      separatorBuilder: (_, __) => Divider(
                                          height: 1,
                                          color: context.colors.borderColor
                                              .withOpacity(0.5)),
                                      itemBuilder: (context, i) {
                                        final pkg = packages[i];
                                        final disposition = selected[pkg.id];
                                        final isSelected = disposition != null;
                                        return _PackageRequestRow(
                                          srNumber: pkg.srNumber,
                                          itemName: _itemSummary(pkg),
                                          consignee: pkg.consigneeName,
                                          source: pkg.source,
                                          deadline: pkg.appealDeadline,
                                          isSelected: isSelected,
                                          disposition: disposition,
                                          onToggle: () {
                                            final map = Map<String, String>.from(
                                                selected);
                                            if (isSelected) {
                                              map.remove(pkg.id);
                                            } else {
                                              map[pkg.id] = 'destruction';
                                            }
                                            ref
                                                .read(
                                                    selectedRequestDispositionsProvider
                                                        .notifier)
                                                .state = map;
                                          },
                                          onDisposition: (d) {
                                            final map = Map<String, String>.from(
                                                selected);
                                            map[pkg.id] = d;
                                            ref
                                                .read(
                                                    selectedRequestDispositionsProvider
                                                        .notifier)
                                                .state = map;
                                          },
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),

                      const Gap(28),

                      // Actions
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            style: TextButton.styleFrom(
                              foregroundColor: context.colors.textSecondary,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 24, vertical: 16),
                            ),
                            child: const Text('Cancel',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                          const Gap(12),
                          ElevatedButton.icon(
                            icon: _isLoading
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.send_rounded, size: 18),
                            label: const Text('Send Request',
                                style: TextStyle(
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
                            onPressed: _isLoading ? null : _submit,
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

// ── One selectable package row with a Destruction / Sale choice ───────────

class _PackageRequestRow extends StatelessWidget {
  final String srNumber;
  final String itemName;
  final String consignee;
  final String source; // 'forfeit' | 'abandoned'
  final DateTime deadline;
  final bool isSelected;
  final String? disposition;
  final VoidCallback onToggle;
  final ValueChanged<String> onDisposition;

  const _PackageRequestRow({
    required this.srNumber,
    required this.itemName,
    required this.consignee,
    required this.source,
    required this.deadline,
    required this.isSelected,
    required this.disposition,
    required this.onToggle,
    required this.onDisposition,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onToggle,
      child: Container(
        color: isSelected
            ? context.colors.primaryGold.withOpacity(0.06)
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Checkbox(
              activeColor: context.colors.primaryGold,
              value: isSelected,
              onChanged: (_) => onToggle(),
            ),
            const Gap(4),
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Flexible(
                      child: Text(srNumber,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: context.colors.accentLightBlue)),
                    ),
                    const Gap(8),
                    _SourceChip(source: source),
                  ]),
                  Text(itemName,
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
              child: Text(consignee,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13, color: context.colors.textPrimary)),
            ),
            const Gap(8),
            // Disposition picker — active only when the row is selected.
            _DispositionToggle(
              value: disposition,
              enabled: isSelected,
              onChanged: onDisposition,
            ),
          ],
        ),
      ),
    );
  }
}

/// Small Forfeit / Abandoned / Other tag so the yard sees where each
/// requestable package came from.
class _SourceChip extends StatelessWidget {
  final String source; // 'forfeit' | 'abandoned' | 'other'
  const _SourceChip({required this.source});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (source) {
      'abandoned' => ('Abandoned', context.colors.heldOrange),
      'other' => ('Other', context.colors.warningAmber),
      _ => ('Forfeit', context.colors.accentBlue),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 9.5, fontWeight: FontWeight.w800)),
    );
  }
}

class _DispositionToggle extends StatelessWidget {
  final String? value;
  final bool enabled;
  final ValueChanged<String> onChanged;
  const _DispositionToggle(
      {required this.value, required this.enabled, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget seg(String code, IconData icon, Color color) {
      final active = enabled && value == code;
      return InkWell(
        onTap: enabled ? () => onChanged(code) : null,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: active ? color.withOpacity(0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color:
                    active ? color.withOpacity(0.6) : Colors.transparent),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon,
                size: 14,
                color: active
                    ? color
                    : context.colors.textMuted.withOpacity(enabled ? 1 : 0.5)),
            const Gap(5),
            Text(dispositionLabel(code),
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: active
                        ? color
                        : context.colors.textMuted
                            .withOpacity(enabled ? 1 : 0.5))),
          ]),
        ),
      );
    }

    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: context.colors.textPrimary.withOpacity(0.03),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: context.colors.borderColor),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          seg('destruction', Icons.delete_forever_rounded,
              context.colors.dangerRed),
          const Gap(2),
          seg('sale', Icons.sell_rounded, context.colors.successGreen),
        ]),
      ),
    );
  }
}

class _MiniCount extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  const _MiniCount(
      {required this.label, required this.count, required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Text('$count $label',
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}

// ── Section container (matches the SR / tender form cards) ────────────────

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
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: context.colors.textPrimary.withOpacity(0.03),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(15)),
              border: Border(
                  bottom: BorderSide(color: context.colors.borderColor)),
            ),
            child: Row(
              children: [
                Icon(icon, size: 18, color: context.colors.primaryGold),
                const Gap(10),
                Expanded(
                  child: Text(
                    title.toUpperCase(),
                    style: TextStyle(
                      color: context.colors.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ],
            ),
          )
              .animate()
              .slideX(
                  delay: Duration(milliseconds: delay),
                  duration: 300.ms,
                  begin: -0.1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: child,
          ).animate().fadeIn(
              delay: Duration(milliseconds: delay + 100), duration: 400.ms),
        ],
      ),
    );
  }
}
