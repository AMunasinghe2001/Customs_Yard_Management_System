import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import '../core/theme.dart';
import '../core/providers.dart';
import '../models/models.dart';

class WarehouseSelectionDialog extends ConsumerStatefulWidget {
  final String? initialSelectedId;
  final String? suggestedWarehouseId;
  final bool allowSuggestedOnly;

  const WarehouseSelectionDialog({
    super.key,
    this.initialSelectedId,
    this.suggestedWarehouseId,
    this.allowSuggestedOnly = false,
  });

  @override
  ConsumerState<WarehouseSelectionDialog> createState() =>
      _WarehouseSelectionDialogState();
}

class _WarehouseSelectionDialogState
    extends ConsumerState<WarehouseSelectionDialog> {
  late String? _selectedWarehouseId;

  @override
  void initState() {
    super.initState();
    _selectedWarehouseId = widget.initialSelectedId ?? widget.suggestedWarehouseId;
  }

  @override
  Widget build(BuildContext context) {
    final warehouses = ref.watch(warehousesProvider);

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: context.colors.surfaceDark,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Select Warehouse',
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: Icon(
                  Icons.close_rounded,
                  color: context.colors.textMuted,
                  size: 20,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const Gap(4),
          Text(
            'Choose which warehouse should hold this package.',
            style: TextStyle(
              color: context.colors.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.normal,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: warehouses.when(
          loading: () => const Center(
            child: CircularProgressIndicator(),
          ),
          error: (error, _) => Center(
            child: Text(
              'Error loading warehouses: $error',
              style: TextStyle(color: context.colors.dangerRed),
            ),
          ),
          data: (ws) {
            if (ws.isEmpty) {
              return Center(
                child: Text(
                  'No warehouses available',
                  style: TextStyle(color: context.colors.textMuted),
                ),
              );
            }
            return ListView.builder(
              shrinkWrap: true,
              itemCount: ws.length,
              itemBuilder: (context, index) {
                final w = ws[index];
                final isSuggested = widget.suggestedWarehouseId == w.id;
                final isOther = widget.suggestedWarehouseId != null &&
                    widget.suggestedWarehouseId != w.id &&
                    widget.allowSuggestedOnly;
                final isSelected = _selectedWarehouseId == w.id;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: isOther ? null : () => setState(() => _selectedWarehouseId = w.id),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isOther
                            ? context.colors.cardDark.withOpacity(0.5)
                            : (isSelected
                                ? context.colors.primaryGold.withOpacity(0.15)
                                : context.colors.cardDark),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected
                              ? context.colors.primaryGold
                              : (isOther
                                  ? context.colors.borderColor.withOpacity(0.3)
                                  : context.colors.borderColor),
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.warehouse_rounded,
                            color: isOther
                                ? context.colors.textMuted.withOpacity(0.3)
                                : (isSelected
                                    ? context.colors.primaryGold
                                    : context.colors.textMuted),
                            size: 20,
                          ),
                          const Gap(12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  w.name,
                                  style: TextStyle(
                                    color: isOther
                                        ? context.colors.textMuted
                                            .withOpacity(0.5)
                                        : (isSelected
                                            ? context.colors.primaryGold
                                            : context.colors.textPrimary),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (w.location != null)
                                  Text(
                                    w.location!,
                                    style: TextStyle(
                                      color: isOther
                                          ? context.colors.textMuted
                                              .withOpacity(0.3)
                                          : context.colors.textMuted,
                                      fontSize: 12,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (isSelected)
                            Icon(
                              Icons.check_circle,
                              color: context.colors.primaryGold,
                              size: 20,
                            ),
                          if (isSuggested)
                            Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: Container(
                                padding:
                                    const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                decoration: BoxDecoration(
                                  color: context.colors.primaryGold
                                      .withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: context.colors.primaryGold
                                        .withOpacity(0.3),
                                  ),
                                ),
                                child: Text(
                                  'Suggested',
                                  style: TextStyle(
                                    color: context.colors.primaryGold,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            'Cancel',
            style: TextStyle(color: context.colors.textMuted),
          ),
        ),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: context.colors.heldOrange,
            foregroundColor: Colors.white,
          ),
          icon: const Icon(Icons.check_rounded, size: 18),
          label: const Text('Confirm'),
          onPressed: _selectedWarehouseId != null
              ? () => Navigator.pop(context, _selectedWarehouseId)
              : null,
        ),
      ],
    );
  }
}
