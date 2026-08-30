import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';

import '../../core/directorates.dart';
import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/empty_state_card.dart';
import '../../widgets/styled_form_dialog.dart';

/// ICT Directorate → **Yards & Directorates**.
///
/// The yard list and the directorate list used to be `const` in the code, which
/// meant "add a yard" was a code change, a rebuild and a redeploy. They are now
/// rows in `directorates` / `yards` / `yard_directorates`, and this is where
/// ICT maintains them.
///
/// The interesting part is the many-to-many. A yard can sit under SEVERAL
/// directorates — NNR is both CED and PSD, Katunayaka is both B/A and ACD — so
/// the link is edited as a set of checkboxes per yard, not a single dropdown.
/// That is also why an account's SR prefix comes from the USER's directorate
/// rather than from their yard: the yard alone is ambiguous.
class YardDirectorateTab extends ConsumerWidget {
  const YardDirectorateTab({super.key, required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final directorates = ref.watch(directoratesProvider);
    final yards = ref.watch(yardsProvider);
    final links = ref.watch(yardDirectoratesProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: Icons.account_balance_rounded,
            title: 'Directorates',
            subtitle:
                'Head-office divisions. The SR prefix is what goes in front of '
                'every SR number registered under the directorate.',
            accent: accent,
            actionLabel: 'Add Directorate',
            onAction: () => _editDirectorate(context, ref),
          ),
          const Gap(14),
          directorates.when(
            loading: () => const _Loading(),
            error: (e, _) => _LoadFailed(
                what: 'directorates',
                error: e,
                onRetry: () => ref.invalidate(directoratesProvider)),
            data: (list) => _DirectorateTable(
              rows: list,
              accent: accent,
              onEdit: (d) => _editDirectorate(context, ref, existing: d),
              onToggle: (d) async {
                await ref
                    .read(directorateServiceProvider)
                    .setDirectorateActive(d.code, !d.isActive);
                ref.read(directorateConfigRefreshProvider.notifier).trigger();
              },
            ),
          ),
          const Gap(34),
          _SectionHeader(
            icon: Icons.warehouse_rounded,
            title: 'Yards',
            subtitle:
                'Physical yards. Tick every directorate a yard belongs to — '
                'several yards belong to more than one.',
            accent: accent,
            actionLabel: 'Add Yard',
            onAction: () => _editYard(context, ref),
          ),
          const Gap(14),
          yards.when(
            loading: () => const _Loading(),
            error: (e, _) => _LoadFailed(
                what: 'yards',
                error: e,
                onRetry: () => ref.invalidate(yardsProvider)),
            data: (yardList) => links.when(
              loading: () => const _Loading(),
              error: (e, _) => _LoadFailed(
                  what: 'yard/directorate links',
                  error: e,
                  onRetry: () => ref.invalidate(yardDirectoratesProvider)),
              data: (linkMap) => _YardTable(
                rows: yardList,
                links: linkMap,
                accent: accent,
                onEdit: (y) => _editYard(context, ref, existing: y),
                onToggle: (y) async {
                  await ref
                      .read(directorateServiceProvider)
                      .setYardActive(y.code, !y.isActive);
                  ref.read(directorateConfigRefreshProvider.notifier).trigger();
                },
              ),
            ),
          ),
          const Gap(28),
          _SrNumberNote(accent: accent),
        ],
      ),
    );
  }

  // ── Directorate add/edit ──────────────────────────────────────────────────
  Future<void> _editDirectorate(BuildContext context, WidgetRef ref,
      {DirectorateModel? existing}) async {
    final isNew = existing == null;
    final codeC = TextEditingController(text: existing?.code ?? '');
    final nameC = TextEditingController(text: existing?.name ?? '');
    final prefixC = TextEditingController(text: existing?.srPrefix ?? '');
    final orderC =
        TextEditingController(text: (existing?.sortOrder ?? 100).toString());
    String? error;
    bool saving = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        Future<void> save() async {
          final code = codeC.text.trim().toUpperCase();
          final name = nameC.text.trim();
          final prefix = prefixC.text.trim().toUpperCase();
          if (code.isEmpty || name.isEmpty || prefix.isEmpty) {
            setS(() => error = 'Code, name and SR prefix are all required.');
            return;
          }
          // The code is the primary key and is stamped on every profile that
          // registers under it — renaming one would orphan those accounts.
          if (isNew && RegExp(r'[^A-Z0-9_]').hasMatch(code)) {
            setS(() => error =
                'Code may contain only letters, digits and underscores. '
                'Put the display form (e.g. "B/A") in the SR prefix instead.');
            return;
          }
          setS(() {
            saving = true;
            error = null;
          });
          try {
            await ref.read(directorateServiceProvider).upsertDirectorate(
                  code: code,
                  name: name,
                  srPrefix: prefix,
                  sortOrder: int.tryParse(orderC.text.trim()) ?? 100,
                  isActive: existing?.isActive ?? true,
                );
            ref.read(directorateConfigRefreshProvider.notifier).trigger();
            if (ctx.mounted) Navigator.pop(ctx);
          } catch (e) {
            setS(() {
              saving = false;
              error = _writeError(e);
            });
          }
        }

        return StyledFormDialog(
          label: isNew ? 'NEW DIRECTORATE' : 'EDIT DIRECTORATE',
          title: isNew ? 'Add a Directorate' : 'Edit ${existing.code}',
          icon: Icons.account_balance_rounded,
          width: 460,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (error != null) ...[
              _DialogError(message: error!),
              const Gap(12),
            ],
            StyledFormSection(
              title: 'Directorate',
              icon: Icons.badge_outlined,
              children: [
                TextField(
                  controller: codeC,
                  // The code is the primary key referenced by profiles and by
                  // yard_directorates; changing it would strand both.
                  enabled: isNew,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    labelText: 'Code *',
                    helperText: isNew
                        ? 'Short key, e.g. CED. Cannot be changed later.'
                        : 'The code is fixed once created.',
                  ),
                ),
                TextField(
                  controller: nameC,
                  decoration: const InputDecoration(labelText: 'Full name *'),
                ),
                TextField(
                  controller: prefixC,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'SR prefix *',
                    helperText: 'Goes in front of the SR number, e.g. '
                        'CED → CED/GL1/SR/25/2026. May contain "/" (B/A).',
                  ),
                ),
                TextField(
                  controller: orderC,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Sort order',
                    helperText: 'Lower numbers appear first in pickers.',
                  ),
                ),
              ],
            ),
          ]),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            StyledDialogPrimaryButton(
              labelText: isNew ? 'Create' : 'Save Changes',
              icon: Icons.save_rounded,
              loading: saving,
              onPressed: saving ? null : save,
            ),
          ],
        );
      }),
    );
  }

  // ── Yard add/edit (including its directorate set) ─────────────────────────
  Future<void> _editYard(BuildContext context, WidgetRef ref,
      {YardModel? existing}) async {
    final isNew = existing == null;
    final codeC = TextEditingController(text: existing?.code ?? '');
    final nameC = TextEditingController(text: existing?.name ?? '');
    final prefixC = TextEditingController(text: existing?.srPrefix ?? '');
    final orderC =
        TextEditingController(text: (existing?.sortOrder ?? 100).toString());

    final linkMap = await ref.read(yardDirectoratesProvider.future);
    final selected = <String>{...(linkMap[existing?.code] ?? const [])};
    final allDirectorates = await ref.read(directoratesProvider.future);

    String? error;
    bool saving = false;

    if (!context.mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        Future<void> save() async {
          final code = codeC.text.trim().toUpperCase();
          final name = nameC.text.trim();
          final prefix = prefixC.text.trim().toUpperCase();
          if (code.isEmpty || name.isEmpty || prefix.isEmpty) {
            setS(() => error = 'Code, name and SR prefix are all required.');
            return;
          }
          if (isNew && RegExp(r'[^A-Z0-9_]').hasMatch(code)) {
            setS(() =>
                error = 'Code may contain only letters, digits and underscores.');
            return;
          }
          if (selected.isEmpty) {
            setS(() => error =
                'Pick at least one directorate — an account cannot register '
                'against a yard that belongs to none.');
            return;
          }
          setS(() {
            saving = true;
            error = null;
          });
          try {
            final svc = ref.read(directorateServiceProvider);
            await svc.upsertYard(
              code: code,
              name: name,
              srPrefix: prefix,
              sortOrder: int.tryParse(orderC.text.trim()) ?? 100,
              isActive: existing?.isActive ?? true,
            );
            await svc.setYardDirectorates(code, selected.toList());
            ref.read(directorateConfigRefreshProvider.notifier).trigger();
            if (ctx.mounted) Navigator.pop(ctx);
          } catch (e) {
            setS(() {
              saving = false;
              error = _writeError(e);
            });
          }
        }

        return StyledFormDialog(
          label: isNew ? 'NEW YARD' : 'EDIT YARD',
          title: isNew ? 'Add a Yard' : 'Edit ${existing.code}',
          icon: Icons.warehouse_rounded,
          width: 520,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (error != null) ...[
              _DialogError(message: error!),
              const Gap(12),
            ],
            StyledFormSection(
              title: 'Yard',
              icon: Icons.badge_outlined,
              children: [
                TextField(
                  controller: codeC,
                  // Stamped on every package, warehouse entry and audit row the
                  // yard has ever produced.
                  enabled: isNew,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    labelText: 'Code *',
                    helperText: isNew
                        ? 'Short key, e.g. GL1. Cannot be changed later.'
                        : 'The code is fixed once created.',
                  ),
                ),
                TextField(
                  controller: nameC,
                  decoration: const InputDecoration(labelText: 'Display name *'),
                ),
                TextField(
                  controller: prefixC,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'SR prefix *',
                    helperText: 'The middle segment: CED/<GL1>/SR/25/2026.',
                  ),
                ),
                TextField(
                  controller: orderC,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Sort order'),
                ),
              ],
            ),
            const Gap(14),
            StyledFormSection(
              title: 'Belongs to',
              icon: Icons.account_tree_outlined,
              children: [
                Text(
                  'Tick every directorate this yard operates under. Officers '
                  'registering here choose one of them, and that choice sets '
                  'their SR-number prefix.',
                  style: TextStyle(
                      color: context.colors.textMuted,
                      fontSize: 12,
                      height: 1.4),
                ),
                const Gap(4),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final d in allDirectorates.where((d) => d.isActive))
                      FilterChip(
                        label: Text('${d.srPrefix} — ${d.name}'),
                        selected: selected.contains(d.code),
                        onSelected: (on) => setS(() {
                          if (on) {
                            selected.add(d.code);
                          } else {
                            selected.remove(d.code);
                          }
                        }),
                      ),
                  ],
                ),
              ],
            ),
          ]),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            StyledDialogPrimaryButton(
              labelText: isNew ? 'Create' : 'Save Changes',
              icon: Icons.save_rounded,
              loading: saving,
              onPressed: saving ? null : save,
            ),
          ],
        );
      }),
    );
  }

  static String _writeError(Object e) {
    final s = e.toString().toLowerCase();
    if (s.contains('permission denied') ||
        s.contains('row-level security') ||
        s.contains('42501')) {
      return 'Only the ICT Directorate may change these lists.';
    }
    if (s.contains('23505') || s.contains('duplicate')) {
      return 'That code is already in use.';
    }
    if (s.contains('42p01') || s.contains('does not exist')) {
      return 'These tables are not in this database yet. Run '
          'supabase/migrations/20260839_ict_directorates_and_yards.sql.';
    }
    return e.toString().replaceAll('Exception: ', '');
  }
}

// ── Tables ──────────────────────────────────────────────────────────────────

class _DirectorateTable extends StatelessWidget {
  const _DirectorateTable({
    required this.rows,
    required this.accent,
    required this.onEdit,
    required this.onToggle,
  });

  final List<DirectorateModel> rows;
  final Color accent;
  final ValueChanged<DirectorateModel> onEdit;
  final ValueChanged<DirectorateModel> onToggle;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const EmptyStateCard(
        icon: Icons.account_balance_outlined,
        message: 'No directorates yet',
        subtitle: 'Add the first one to start assigning yards to it.',
      );
    }
    const widths = [1, 1, 4, 1, 1];
    return _TableShell(
      columns: const ['SR Prefix', 'Code', 'Name', 'Status', ''],
      widths: widths,
      children: [
        for (final d in rows)
          _TableRow(
            faded: !d.isActive,
            widths: widths,
            cells: [
              _MonoChip(text: d.srPrefix, color: accent),
              Text(d.code),
              Text(d.name, overflow: TextOverflow.ellipsis),
              _StatusPill(active: d.isActive),
              _RowActions(
                onEdit: () => onEdit(d),
                onToggle: () => onToggle(d),
                active: d.isActive,
              ),
            ],
          ),
      ],
    );
  }
}

class _YardTable extends StatelessWidget {
  const _YardTable({
    required this.rows,
    required this.links,
    required this.accent,
    required this.onEdit,
    required this.onToggle,
  });

  final List<YardModel> rows;
  final Map<String, List<String>> links;
  final Color accent;
  final ValueChanged<YardModel> onEdit;
  final ValueChanged<YardModel> onToggle;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const EmptyStateCard(
        icon: Icons.warehouse_outlined,
        message: 'No yards yet',
        subtitle: 'Add a yard and tick the directorates it belongs to.',
      );
    }
    const widths = [3, 1, 3, 3, 1, 1];
    return _TableShell(
      columns: const [
        'Yard', 'Code', 'Directorates', 'Example SR', 'Status', ''
      ],
      widths: widths,
      children: [
        for (final y in rows)
          _TableRow(
            faded: !y.isActive,
            widths: widths,
            cells: [
              Text(y.name, overflow: TextOverflow.ellipsis),
              Text(y.code),
              _DirectorateChips(codes: links[y.code] ?? const [], accent: accent),
              // Shows the consequence of the mapping in the mapping's own row,
              // which is the fastest way to spot a wrong prefix.
              _ExampleSr(yard: y, directorates: links[y.code] ?? const []),
              _StatusPill(active: y.isActive),
              _RowActions(
                onEdit: () => onEdit(y),
                onToggle: () => onToggle(y),
                active: y.isActive,
              ),
            ],
          ),
      ],
    );
  }
}

class _DirectorateChips extends StatelessWidget {
  const _DirectorateChips({required this.codes, required this.accent});
  final List<String> codes;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    if (codes.isEmpty) {
      return Text('— none —',
          style: TextStyle(
              color: context.colors.warningAmber,
              fontSize: 12,
              fontStyle: FontStyle.italic));
    }
    return Wrap(
      spacing: 5,
      runSpacing: 5,
      children: [
        for (final c in codes) _MonoChip(text: c, color: accent, small: true),
      ],
    );
  }
}

class _ExampleSr extends StatelessWidget {
  const _ExampleSr({required this.yard, required this.directorates});
  final YardModel yard;
  final List<String> directorates;

  @override
  Widget build(BuildContext context) {
    final year = DateTime.now().year;
    if (directorates.isEmpty) {
      return Text('${yard.srPrefix}/SR/01/$year',
          style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 11.5,
              color: context.colors.textMuted));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final d in directorates)
          Text(
            composeSrNumber(
              yardPrefix: yard.srPrefix,
              serial: 1,
              year: year,
              directorateCode: d,
            ),
            style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11.5,
                color: context.colors.textSecondary),
          ),
      ],
    );
  }
}

// ── Small shared pieces ─────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title, subtitle, actionLabel;
  final Color accent;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: accent, size: 20),
      const Gap(10),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w800)),
          const Gap(3),
          Text(subtitle,
              style: TextStyle(
                  color: context.colors.textMuted, fontSize: 12, height: 1.4)),
        ]),
      ),
      const Gap(14),
      FilledButton.icon(
        onPressed: onAction,
        icon: const Icon(Icons.add_rounded, size: 18),
        label: Text(actionLabel),
        style: FilledButton.styleFrom(backgroundColor: accent),
      ),
    ]);
  }
}

class _TableShell extends StatelessWidget {
  const _TableShell({
    required this.columns,
    required this.widths,
    required this.children,
  });

  final List<String> columns;
  final List<int> widths;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.colors.cardDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.colors.borderColor),
      ),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: context.colors.scaffoldBg,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(13)),
          ),
          child: Row(children: [
            for (var i = 0; i < columns.length; i++)
              Expanded(
                flex: widths[i],
                child: Text(columns[i].toUpperCase(),
                    style: TextStyle(
                        color: context.colors.textMuted,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5)),
              ),
          ]),
        ),
        ...children,
      ]),
    );
  }
}

class _TableRow extends StatelessWidget {
  const _TableRow(
      {required this.cells, required this.widths, this.faded = false});

  final List<Widget> cells;

  /// Must match the header's widths, or the columns will not line up.
  final List<int> widths;
  final bool faded;

  @override
  Widget build(BuildContext context) {
    // A deactivated row stays visible — its code is still stamped on historical
    // data — but reads as switched off.
    final row = Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: context.colors.borderColor)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (var i = 0; i < cells.length; i++)
            Expanded(
              flex: widths[i],
              child: DefaultTextStyle.merge(
                style: TextStyle(
                    color: context.colors.textPrimary, fontSize: 13),
                child: cells[i],
              ),
            ),
        ],
      ),
    );
    return faded ? Opacity(opacity: 0.45, child: row) : row;
  }
}

class _MonoChip extends StatelessWidget {
  const _MonoChip({required this.text, required this.color, this.small = false});
  final String text;
  final Color color;
  final bool small;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: EdgeInsets.symmetric(
            horizontal: small ? 6 : 8, vertical: small ? 2 : 3),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withOpacity(0.35)),
        ),
        child: Text(text,
            style: TextStyle(
                color: color,
                fontFamily: 'monospace',
                fontSize: small ? 10.5 : 12,
                fontWeight: FontWeight.w700)),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.active});
  final bool active;

  @override
  Widget build(BuildContext context) {
    final c = active ? context.colors.successGreen : context.colors.textMuted;
    return Align(
      alignment: Alignment.centerLeft,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const Gap(6),
        Text(active ? 'Active' : 'Off',
            style:
                TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class _RowActions extends StatelessWidget {
  const _RowActions({
    required this.onEdit,
    required this.onToggle,
    required this.active,
  });

  final VoidCallback onEdit, onToggle;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisAlignment: MainAxisAlignment.end, children: [
      IconButton(
        icon: const Icon(Icons.edit_outlined, size: 18),
        tooltip: 'Edit',
        onPressed: onEdit,
      ),
      IconButton(
        icon: Icon(active ? Icons.toggle_on_rounded : Icons.toggle_off_rounded,
            size: 22,
            color:
                active ? context.colors.successGreen : context.colors.textMuted),
        // Deactivating, not deleting: the code is referenced by historical rows.
        tooltip: active ? 'Deactivate (hides it from pickers)' : 'Activate',
        onPressed: onToggle,
      ),
    ]);
  }
}

class _SrNumberNote extends StatelessWidget {
  const _SrNumberNote({required this.accent});
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withOpacity(0.25)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.info_outline_rounded, color: accent, size: 18),
        const Gap(12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('How the SR number is built',
                style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700)),
            const Gap(6),
            Text(
              'DIRECTORATE / YARD / SR / serial / year   —   e.g. CED/GL1/SR/25/2026\n\n'
              'The directorate comes from the signed-in officer, not from the '
              'yard, because a yard can belong to more than one. An officer '
              'registered under CED at NNR writes CED/NNR/…; one registered '
              'under PSD at the same yard writes PSD/NNR/…. The serial still '
              'counts once per yard per year, so the two never collide.\n\n'
              'Accounts created before directorates existed have none, and keep '
              'minting the older GL1/SR/25/2026 form until edited.',
              style: TextStyle(
                  color: context.colors.textSecondary,
                  fontSize: 12,
                  height: 1.55),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator()),
      );
}

class _LoadFailed extends StatelessWidget {
  const _LoadFailed(
      {required this.what, required this.error, required this.onRetry});
  final String what;
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final missing = error.toString().toLowerCase().contains('does not exist') ||
        error.toString().contains('42P01');
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.dangerRed.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.dangerRed.withOpacity(0.3)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.error_outline, color: context.colors.dangerRed, size: 18),
        const Gap(12),
        Expanded(
          child: Text(
            missing
                // The single most likely cause, named outright.
                ? 'The $what table is not in this database yet. Run '
                    'supabase/migrations/20260839_ict_directorates_and_yards.sql, '
                    'then reload.'
                : 'Could not load $what: $error',
            style: TextStyle(
                color: context.colors.textSecondary, fontSize: 12.5, height: 1.5),
          ),
        ),
        const Gap(8),
        TextButton(onPressed: onRetry, child: const Text('Retry')),
      ]),
    );
  }
}

class _DialogError extends StatelessWidget {
  const _DialogError({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: context.colors.dangerRed.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.colors.dangerRed.withOpacity(0.35)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.error_outline, size: 16, color: context.colors.dangerRed),
        const Gap(8),
        Expanded(
          child: Text(message,
              style: TextStyle(
                  color: context.colors.dangerRed, fontSize: 12.5, height: 1.4)),
        ),
      ]),
    );
  }
}
