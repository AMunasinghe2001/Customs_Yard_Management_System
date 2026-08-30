import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';

import '../core/providers.dart';
import '../core/theme.dart';
import '../models/models.dart';
import 'styled_dropdown.dart';

/// The paired "which directorate / which yard" question every account
/// registration now asks.
///
/// The two are one control rather than two independent dropdowns because they
/// constrain each other: picking CED narrows the yard list to CED's yards, and
/// picking a yard that is not in the chosen directorate is not a thing a valid
/// account can be. Keeping the pair in one widget is what stops the four
/// screens that ask this question (officer sign-up, DC/SDDC sign-up, the ICT
/// portal's Add Staff and Edit Staff dialogs) from drifting apart.
///
/// It also matters for the SR number: a yard can sit under SEVERAL directorates
/// — NNR is both CED and PSD, Katunayaka is both B/A and ACD — so the yard
/// alone cannot say whether the account mints `CED/NNR/SR/…` or `PSD/NNR/SR/…`.
/// The directorate chosen here is what decides it, for the life of the account.
class DirectorateYardPicker extends ConsumerWidget {
  const DirectorateYardPicker({
    super.key,
    required this.directorate,
    required this.yard,
    required this.onDirectorateChanged,
    required this.onYardChanged,
    this.menuWidth = 384,
    this.gap = 14,
    this.enabled = true,
    this.directorateLabel = 'Directorate *',
    this.yardLabel = 'Yard *',
  });

  /// Currently-selected directorate code, or null when none is chosen yet.
  final String? directorate;

  /// Currently-selected yard code, or null.
  final String? yard;

  /// Called with the new directorate. The caller MUST also clear the yard when
  /// the previous one is not under the new directorate — [yardIsValidFor] is
  /// provided so it can check without re-querying.
  final ValueChanged<String?> onDirectorateChanged;

  final ValueChanged<String?> onYardChanged;

  final double menuWidth;
  final double gap;
  final bool enabled;
  final String directorateLabel;
  final String yardLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final directorates = ref.watch(directoratesProvider);
    final yards = ref.watch(yardsForDirectorateProvider(directorate));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        directorates.when(
          loading: () => const _PickerPlaceholder(label: 'Loading directorates…'),
          error: (e, _) => _PickerError(
              message: 'Could not load the directorate list.',
              onRetry: () => ref.invalidate(directoratesProvider)),
          data: (list) {
            final active = list.where((d) => d.isActive).toList();
            return StyledDropdownFormField<String>(
              // A stale value (its directorate was deactivated) would otherwise
              // throw inside the dropdown for having no matching item.
              value: active.any((d) => d.code == directorate) ? directorate : null,
              label: directorateLabel,
              menuWidth: menuWidth,
              prefixIcon: Icon(Icons.account_balance_outlined,
                  color: context.colors.textMuted),
              options: [
                for (final d in active)
                  StyledDropdownOption(d.code, '${d.srPrefix} — ${d.name}'),
              ],
              onChanged: enabled ? onDirectorateChanged : (_) {},
              validator: (v) =>
                  v == null || v.isEmpty ? 'Select a directorate' : null,
            );
          },
        ),
        Gap(gap),
        yards.when(
          loading: () => const _PickerPlaceholder(label: 'Loading yards…'),
          error: (e, _) => _PickerError(
              message: 'Could not load the yard list.',
              onRetry: () => ref.invalidate(yardsProvider)),
          data: (list) {
            final active = list.where((y) => y.isActive).toList();
            final hasDirectorate =
                directorate != null && directorate!.isNotEmpty;
            return StyledDropdownFormField<String>(
              value: active.any((y) => y.code == yard) ? yard : null,
              label: yardLabel,
              // Says WHY the list is empty, rather than showing a dead control.
              helperText: !hasDirectorate
                  ? 'Choose a directorate first'
                  : active.isEmpty
                      ? 'No yards are assigned to this directorate yet'
                      : null,
              menuWidth: menuWidth,
              prefixIcon: Icon(Icons.warehouse_outlined,
                  color: context.colors.textMuted),
              options: [
                for (final y in active) StyledDropdownOption(y.code, y.name),
              ],
              onChanged:
                  (enabled && hasDirectorate) ? onYardChanged : (_) {},
              validator: (v) => v == null || v.isEmpty ? 'Select a yard' : null,
            );
          },
        ),
      ],
    );
  }
}

/// Whether [yardCode] is one of [directorateCode]'s yards.
///
/// Callers use this when the directorate changes, to decide whether to keep the
/// yard already chosen or clear it.
bool yardIsValidFor(
    Map<String, List<String>> map, String? yardCode, String? directorateCode) {
  if (yardCode == null || directorateCode == null) return false;
  return (map[yardCode] ?? const []).contains(directorateCode);
}

class _PickerPlaceholder extends StatelessWidget {
  const _PickerPlaceholder({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Padding(
          padding: EdgeInsets.all(14),
          child: SizedBox(
              width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      ),
      child: const SizedBox(height: 20),
    );
  }
}

class _PickerError extends StatelessWidget {
  const _PickerError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: context.colors.dangerRed.withOpacity(0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.dangerRed.withOpacity(0.3)),
      ),
      child: Row(children: [
        Icon(Icons.error_outline, size: 18, color: context.colors.dangerRed),
        const Gap(10),
        Expanded(
          child: Text(message,
              style: TextStyle(color: context.colors.dangerRed, fontSize: 12.5)),
        ),
        TextButton(onPressed: onRetry, child: const Text('Retry')),
      ]),
    );
  }
}
