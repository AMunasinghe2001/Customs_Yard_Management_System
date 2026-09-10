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
import '../../widgets/app_dialog.dart';

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
      final d = p.appealRequestDisposition; // 'sale' | null
      if (d == 'sale') defaults[p.id] = 'sale';
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
    // Synthetic per-item rows (abandoned / "Other") name their specific item.
    if (f.itemName != null && f.itemName!.trim().isNotEmpty) {
      return f.itemName!;
    }
    final items = f.packageDetails?.items ?? const [];
    if (items.isEmpty) return 'Multiple/Unspecified';
    if (items.length == 1) return items.first.itemName;
    return '${items.first.itemName} +${items.length - 1}';
  }

  /// A returned warehouse entry that represents a forfeit / confiscation event.
  /// Its [itemCount] is the quantity actually forfeited in that event.
  bool _isForfeitEntry(WarehouseEntryModel e) {
    if (!e.isReturned) return false;
    final notes = (e.returnNotes ?? '').trim().toUpperCase();
    return notes.startsWith('[FORFEIT') || notes.startsWith('[CONFISCATED');
  }

  /// Quantity for a disposal request row.
  /// Per-entry abandoned/other rows carry the exact qty in [entryQty]. For a
  /// forfeited item we show the quantity actually FORFEITED (sum of the forfeit
  /// warehouse-entry counts, e.g. 5 of 20) — matching the Forfeited table —
  /// rather than the full registered item quantity. Falls back to the item's
  /// (effective) quantity when there is no forfeit event.
  int? _itemQty(ForfeitedPackageModel f) {
    if (f.entryQty != null) return f.entryQty;
    final pkg = f.packageDetails;
    final items = pkg?.items ?? const [];
    PackageItem? target;
    if (f.itemId != null) {
      target = items.where((i) => i.id == f.itemId).firstOrNull;
    }
    target ??= items.length == 1 ? items.first : null;
    if (target == null)
      return null; // multi-item row without per-item expansion

    final forfeitQty = (pkg?.warehouseEntries ?? const [])
        .where((e) => e.packageItemId == target!.id && _isForfeitEntry(e))
        .fold<int>(0, (s, e) => s + e.itemCount);
    if (forfeitQty > 0) return forfeitQty;
    return target.effectiveQuantity;
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
    // Lists EVERY candidate, including goods still inside their appeal window
    // — those render greyed out and cannot be ticked, so the officer sees the
    // whole picture instead of wondering where an SR went.
    final expiredAsync = ref.watch(allDisposalCandidatesProvider);
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
                    )
                        .animate()
                        .scale(duration: 400.ms, curve: Curves.easeOutBack),
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
                                  final date = await showAppDialog<DateTime>(
                                    context: context,
                                    builder: (_) => OneTapDatePicker(
                                        initialDate: _requestDate,
                                        // Match the other pickers — no future dates.
                                        lastDate: DateTime.now()),
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
                                      label: 'Tender Sale',
                                      count: selected.length,
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
                            // The list now includes goods still in appeal
                            // (greyed out), so the old "appeal period passed"
                            // wording no longer describes it.
                            'Select Goods (${selected.length} selected)',
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
                                      // Counts only what CAN be sent, so the
                                      // denominator matches Select All.
                                      '${selected.length} of '
                                      '${packages.where((p) => p.isActionable).length} selected',
                                      style: TextStyle(
                                          color: context.colors.textSecondary,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600),
                                    ),
                                    const Spacer(),
                                    TextButton.icon(
                                      onPressed: () {
                                        // Skip the pending rows: they are
                                        // listed for visibility only and
                                        // cannot be sent yet.
                                        final map = <String, String>{};
                                        for (final p in packages) {
                                          if (!p.isActionable) continue;
                                          map[p.id] = 'sale';
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
                                        // Still in its window with no ruling
                                        // yet — listed, but not selectable.
                                        final pending = !pkg.isActionable;
                                        return _PackageRequestRow(
                                          srNumber: pkg.srNumber,
                                          itemName: _itemSummary(pkg),
                                          quantity: _itemQty(pkg),
                                          consignee: pkg.consigneeName,
                                          source: pkg.source,
                                          deadline: pkg.appealDeadline,
                                          pending: pending,
                                          daysLeft: pkg.appealDeadline
                                              .difference(DateTime.now())
                                              .inDays
                                              .clamp(0, 999),
                                          isSelected: isSelected,
                                          disposition: disposition,
                                          onToggle: () {
                                            final map =
                                                Map<String, String>.from(
                                                    selected);
                                            if (isSelected) {
                                              map.remove(pkg.id);
                                            } else {
                                              map[pkg.id] = 'sale';
                                            }
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
  final int? quantity;
  final String consignee;
  final String source; // 'forfeit' | 'abandoned'
  final DateTime deadline;
  final bool isSelected;
  final String? disposition;
  final VoidCallback onToggle;

  /// Still inside its 30-day appeal window with no decision yet, so it cannot
  /// be sent. Listed anyway — greyed out — so the officer can see it is there
  /// and how long is left.
  final bool pending;

  /// Days remaining in that window, for the row's note.
  final int daysLeft;

  const _PackageRequestRow({
    required this.srNumber,
    required this.itemName,
    this.quantity,
    required this.consignee,
    required this.source,
    required this.deadline,
    required this.isSelected,
    required this.disposition,
    required this.onToggle,
    this.pending = false,
    this.daysLeft = 0,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      // A pending row is inert: tapping it must not select it.
      onTap: pending ? null : onToggle,
      child: Opacity(
        opacity: pending ? 0.55 : 1,
        child: Container(
          color: isSelected
              ? context.colors.primaryGold.withOpacity(0.06)
              : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Checkbox(
                activeColor: context.colors.primaryGold,
                value: isSelected,
                onChanged: pending ? null : (_) => onToggle(),
              ),
              const Gap(4),
              // Goods block. The SR line and the item line each wrap on their
              // own, so a long name or an extra chip pushes nothing into the
              // column beside it -- they used to sit in bare Rows where the
              // chips had no room to give and collided with the text.
              Expanded(
                flex: 5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(srNumber,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: context.colors.accentLightBlue)),
                        _SourceChip(source: source),
                        if (pending)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color:
                                  context.colors.warningAmber.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                  color: context.colors.warningAmber
                                      .withOpacity(0.4)),
                            ),
                            child: Text(
                                daysLeft > 0
                                    ? 'In appeal · ${daysLeft}d'
                                    : 'In appeal',
                                style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                    color: context.colors.warningAmber)),
                          ),
                      ],
                    ),
                    const Gap(3),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(itemName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12,
                                color: context.colors.textSecondary)),
                        if (quantity != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color:
                                  context.colors.primaryGold.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'Qty $quantity',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: context.colors.primaryGold,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const Gap(12),
              Expanded(
                flex: 4,
                child: Text(consignee,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13, color: context.colors.textPrimary)),
              ),
              const Gap(12),
              // Disposition indicator — every item in this dialog is for Sale.
              // Fixed width so the badges line up down the list instead of
              // sitting at a different x on every row.
              SizedBox(
                width: 74,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: context.colors.successGreen.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: context.colors.successGreen.withOpacity(0.4)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.sell_rounded,
                        size: 12, color: context.colors.successGreen),
                    const Gap(4),
                    Text('Sale',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: context.colors.successGreen)),
                  ]),
                ),
              ),
            ],
          ),
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
      'perishable' => ('Perishable', context.colors.dangerRed),
      'detain' => ('Detained', context.colors.primaryGold),
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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: context.colors.textPrimary.withOpacity(0.03),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(15)),
              border:
                  Border(bottom: BorderSide(color: context.colors.borderColor)),
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
          ).animate().slideX(
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
