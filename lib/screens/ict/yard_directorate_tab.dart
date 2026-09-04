import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:gap/gap.dart';

import '../../core/directorates.dart';
import '../../core/providers.dart';
import '../../core/theme.dart';
import 'ict_ui.dart';
import '../../models/models.dart';
import '../../widgets/empty_table_state.dart';
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
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ⚠️ The section title, its explanation and its Add button are ON
          // the card, not floating above it. That is what makes this read as
          // an ERP module rather than a page that happens to have a table:
          // the card is the unit, and its header says what you are looking at
          // and what you can do to it.
          IctSectionCard(
            icon: Icons.account_balance_rounded,
            title: 'Directorates',
            subtitle:
                'Head-office divisions. The SR prefix goes in front of every '
                'SR number registered under the directorate.',
            badge: directorates.valueOrNull == null
                ? null
                : '${directorates.valueOrNull!.length}',
            actions: [
              IctPrimaryButton(
                label: 'Add Directorate',
                icon: Icons.add_rounded,
                accent: accent,
                onPressed: () => _editDirectorate(context, ref),
              ),
            ],
            child: directorates.when(
              skipLoadingOnReload: true,
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
          ).animate().slideY(begin: 0.05, duration: 400.ms).fadeIn(),
          const Gap(24),
          IctSectionCard(
            icon: Icons.warehouse_rounded,
            title: 'Yards',
            subtitle:
                'Physical yards. Tick every directorate a yard belongs to — '
                'several belong to more than one.',
            badge: yards.valueOrNull == null
                ? null
                : '${yards.valueOrNull!.length}',
            actions: [
              IctPrimaryButton(
                label: 'Add Yard',
                icon: Icons.add_rounded,
                accent: accent,
                onPressed: () => _editYard(context, ref),
              ),
            ],
            child: yards.when(
              skipLoadingOnReload: true,
              loading: () => const _Loading(),
              error: (e, _) => _LoadFailed(
                  what: 'yards',
                  error: e,
                  onRetry: () => ref.invalidate(yardsProvider)),
              data: (yardList) => links.when(
                skipLoadingOnReload: true,
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
                    ref
                        .read(directorateConfigRefreshProvider.notifier)
                        .trigger();
                  },
                ),
              ),
            ),
          )
              .animate()
              .slideY(begin: 0.05, duration: 400.ms, delay: 80.ms)
              .fadeIn(delay: 80.ms),
          const Gap(28),
          _SrNumberNote(accent: accent).animate().fadeIn(delay: 200.ms),
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
          headerAccentColor: accent,
          erp: true,
          icon: Icons.account_balance_rounded,
          width: 460,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (error != null) ...[
              _DialogError(message: error!),
              const Gap(12),
            ],
            StyledFormSection(
              erp: true,
              accentColor: accent,
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
              erp: true,
              accentColor: accent,
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
          headerAccentColor: accent,
          erp: true,
          icon: Icons.warehouse_rounded,
          width: 520,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (error != null) ...[
              _DialogError(message: error!),
              const Gap(12),
            ],
            StyledFormSection(
              erp: true,
              accentColor: accent,
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
              erp: true,
              accentColor: accent,
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
                // ⚠️ Two even columns, not a Wrap.
                //
                // A Wrap packs each row until the next chip will not fit, so
                // with names of every length ("B/A — Baggage / Airport" beside
                // "SSD — Social Protection & Security Directorate") the rows
                // came out one, then two, then one — a ragged block that reads
                // as a mistake rather than as a list of eight equal choices.
                // A fixed two-column grid gives every directorate the same
                // box, and the eye can go straight down a column.
                LayoutBuilder(builder: (context, box) {
                  final active =
                      allDirectorates.where((d) => d.isActive).toList();
                  const gap = 8.0;
                  final cellWidth = (box.maxWidth - gap) / 2;
                  return Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      for (final d in active)
                        SizedBox(
                          width: cellWidth,
                          child: _DirectorateTick(
                            accent: accent,
                            label: '${d.srPrefix} — ${d.name}',
                            selected: selected.contains(d.code),
                            onChanged: (on) => setS(() {
                              if (on) {
                                selected.add(d.code);
                              } else {
                                selected.remove(d.code);
                              }
                            }),
                          ),
                        ),
                    ],
                  );
                }),
              ],
            ),
          ]),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            StyledDialogPrimaryButton(
              erp: true,
              accentColor: accent,
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
  final Future<void> Function(DirectorateModel) onToggle;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      // EmptyTableState, not EmptyStateCard: this sits INSIDE the section
      // card, and EmptyStateCard draws a bordered card of its own -- a card
      // inside a card, with two borders a few pixels apart.
      return const EmptyTableState(
        icon: Icons.account_balance_outlined,
        message: 'No directorates yet',
        subtitle: 'Add the first one to start assigning yards to it.',
      );
    }
    // ⚠️ Status and Actions are FIXED, not flex. As flex 1 each they were
    // the narrowest columns in a wide row: the pill and the buttons ended
    // up touching, and the toggle spilled past the card's edge (the 6px
    // overflow stripe). Fixed widths cannot be squeezed by a long name.
    // SR Prefix and Code are short and fixed in shape; the NAME is what
    // varies, so it gets the room.
    const widths = [2, 2, 7];
    const fixed = [kIctStatusColumnWidth, kIctActionsColumnWidth];
    return _TableShell(
      columns: const ['SR Prefix', 'Code', 'Name', 'Status', 'Actions'],
      widths: widths,
      fixed: fixed,
      children: [
        for (var i = 0; i < rows.length; i++)
          _TableRow(
            index: i,
            faded: !rows[i].isActive,
            widths: widths,
            fixed: fixed,
            cells: [
              _MonoChip(text: rows[i].srPrefix, color: accent),
              Text(rows[i].code),
              Text(rows[i].name, overflow: TextOverflow.ellipsis),
              _StatusPill(active: rows[i].isActive),
              _RowActions(
                accent: accent,
                onEdit: () => onEdit(rows[i]),
                onToggle: () => onToggle(rows[i]),
                active: rows[i].isActive,
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
  final Future<void> Function(YardModel) onToggle;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const EmptyTableState(
        icon: Icons.warehouse_outlined,
        message: 'No yards yet',
        subtitle: 'Add a yard and tick the directorates it belongs to.',
      );
    }
    // ⚠️ Balanced against what each column actually holds: a yard name and
    // an example SR are long, a code is four characters, and Directorates
    // is a row of fixed-width chips. At 3/1/3/3 the codes had as much room
    // as the SR numbers, and the names ran out of it.
    const widths = [5, 2, 4, 6];
    const fixed = [kIctStatusColumnWidth, kIctActionsColumnWidth];
    return _TableShell(
      columns: const [
        'Yard', 'Code', 'Directorates', 'Example SR', 'Status', 'Actions'
      ],
      widths: widths,
      fixed: fixed,
      children: [
        for (var i = 0; i < rows.length; i++)
          _TableRow(
            index: i,
            faded: !rows[i].isActive,
            widths: widths,
            fixed: fixed,
            cells: [
              Text(rows[i].name, overflow: TextOverflow.ellipsis),
              Text(rows[i].code),
              _DirectorateChips(
                  codes: links[rows[i].code] ?? const [], accent: accent),
              // Shows the consequence of the mapping in the mapping's own row,
              // which is the fastest way to spot a wrong prefix.
              _ExampleSr(
                  yard: rows[i],
                  directorates: links[rows[i].code] ?? const []),
              _StatusPill(active: rows[i].isActive),
              _RowActions(
                accent: accent,
                onEdit: () => onEdit(rows[i]),
                onToggle: () => onToggle(rows[i]),
                active: rows[i].isActive,
              ),
            ],
          ),
      ],
    );
  }
}

/// One directorate in the "Belongs to" grid.
///
/// A FilterChip sizes itself to its label and carries the app's global chip
/// theme, so eight of them could never line up into a grid and none of them
/// carried the console's accent. This is a plain box that fills the cell it
/// is given.
class _DirectorateTick extends StatelessWidget {
  const _DirectorateTick({
    required this.accent,
    required this.label,
    required this.selected,
    required this.onChanged,
  });

  final Color accent;
  final String label;
  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(kIctControlRadius),
        onTap: () => onChanged(!selected),
        child: Container(
          height: kIctControlHeight,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color:
                selected ? accent.withOpacity(0.1) : context.colors.surfaceDark,
            borderRadius: BorderRadius.circular(kIctControlRadius),
            border: Border.all(
                color: selected
                    ? accent.withOpacity(0.5)
                    : context.colors.borderColor),
          ),
          child: Row(children: [
            Icon(
                selected
                    ? Icons.check_box_rounded
                    : Icons.check_box_outline_blank_rounded,
                size: 17,
                color: selected ? accent : context.colors.textMuted),
            const Gap(8),
            Expanded(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: selected ? accent : context.colors.textPrimary,
                      fontSize: 12,
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w500)),
            ),
          ]),
        ),
      ),
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

/// A column layout shared by the header and every row, so the two cannot
/// drift: [widths] are flex columns from the left, [fixed] are pixel columns
/// pinned to the right.
List<Widget> _ictColumns({
  required List<Widget> cells,
  required List<int> widths,
  required List<double> fixed,
}) {
  final out = <Widget>[];
  for (var i = 0; i < cells.length; i++) {
    final w = i < widths.length ? cells[i] : cells[i];
    if (i > 0) out.add(const Gap(kIctCellGap));
    if (i < widths.length) {
      out.add(Expanded(flex: widths[i], child: w));
    } else {
      out.add(SizedBox(width: fixed[i - widths.length], child: w));
    }
  }
  return out;
}

class _TableShell extends StatelessWidget {
  const _TableShell({
    required this.columns,
    required this.widths,
    required this.fixed,
    required this.children,
  });

  final List<String> columns;
  final List<int> widths;
  final List<double> fixed;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    // ⚠️ No card of its own any more: this table sits INSIDE an
    // IctSectionCard, which draws the border, the radius and the title. A
    // second border here would have shown as a double rule under the header.
    return Column(children: [
      Container(
        height: kIctHeadingHeight,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        color: context.colors.surfaceDark,
        child: Row(
          children: _ictColumns(
            widths: widths,
            fixed: fixed,
            // The same quiet uppercase rule DataTable2 gets from
            // IctTableTheme -- these rows are hand-built, so the two would
            // otherwise be the console's only mismatched headings.
            cells: [
              for (final c in columns)
                Text(c.toUpperCase(),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: context.colors.textMuted,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.9)),
            ],
          ),
        ),
      ),
      ...children,
    ]);
  }
}

class _TableRow extends StatelessWidget {
  const _TableRow(
      {required this.cells,
      required this.widths,
      required this.fixed,
      required this.index,
      this.faded = false});

  final List<Widget> cells;

  /// Must match the header's, or the columns will not line up.
  final List<int> widths;
  final List<double> fixed;

  /// Row number. Kept because the row above the first needs no rule.
  final int index;
  final bool faded;

  @override
  Widget build(BuildContext context) {
    // A deactivated row stays visible — its code is still stamped on
    // historical data — but reads as switched off.
    final row = Container(
      constraints: const BoxConstraints(minHeight: kIctRowHeight),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      // A light rule between rows, so a wide row can be followed across —
      // the same rule DataTable2 draws from IctTableTheme's dividerColor.
      decoration: index == 0
          ? null
          : BoxDecoration(
              border: Border(
                  top: BorderSide(
                      color: context.colors.borderColor.withOpacity(0.5))),
            ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: _ictColumns(
          widths: widths,
          fixed: fixed,
          cells: [
            for (final c in cells)
              DefaultTextStyle.merge(
                style: TextStyle(
                    color: context.colors.textPrimary, fontSize: 12.5),
                child: c,
              ),
          ],
        ),
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
      // ⚠️ One size for every code. They were padded around their text, so
      // "BA", "ACD" and "B/A" each came out a different width and a column of
      // them read as a ragged edge rather than as a set of labels. A code is
      // at most four characters, so one box fits them all.
      child: Container(
        width: small ? 42 : 52,
        height: small ? 19 : 23,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withOpacity(0.35)),
        ),
        child: Text(text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: color,
                fontFamily: 'monospace',
                fontSize: small ? 10.5 : 12,
                fontWeight: FontWeight.w700)),
      ),
    );
  }
}

/// The console's status pill, at the console's one width — so this column
/// lines up with the status column on every other ICT screen.
/// ⚠️ ENABLED / DISABLED here, not ACTIVE / INACTIVE.
///
/// A yard or a directorate is a configuration row that ICT switches on and
/// off, and the control beside it IS a switch — "enabled" is what a switch
/// does. An ACCOUNT is a different thing: it is active, expired or
/// deactivated as a fact of its own lifetime, not because someone flipped it,
/// so the Staff and Directorate Access tables keep ACTIVE. One word for both
/// would have said these two very different states are the same thing.
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.active});
  final bool active;

  @override
  Widget build(BuildContext context) {
    return IctStatusPill(
      label: active ? 'Enabled' : 'Disabled',
      color: active
          ? context.colors.successGreen
          : context.colors.textMuted,
    );
  }
}

class _RowActions extends StatelessWidget {
  const _RowActions({
    required this.onEdit,
    required this.onToggle,
    required this.active,
    required this.accent,
  });

  final VoidCallback onEdit;
  final Future<void> Function() onToggle;
  final bool active;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    // ⚠️ Two controls at the console's one icon size. This was the shared Edit
    // button (a 27px tinted square) beside a 34px IconButton holding a toggle
    // glyph -- two sizes for two actions on the same row, and the oversized
    // one is what pushed this column past the card's edge.
    //
    // Disabling, not deleting: the code is stamped on historical rows.
    return Row(mainAxisAlignment: MainAxisAlignment.start, children: [
      IctIconButton(
        icon: Icons.edit_rounded,
        color: accent,
        tooltip: 'Edit',
        onPressed: onEdit,
      ),
      const Gap(8),
      _EnableSwitch(active: active, onChanged: onToggle),
    ]);
  }
}

/// The enable/disable switch on a Yards & Directorates row.
///
/// ⚠️ It flips FIRST and asks the server after.
///
/// It used to await the write and then invalidate the providers, so the switch
/// sat still for the length of a round trip and the page then rebuilt from
/// underneath it. Moving the local state first is what makes it read as a
/// switch rather than as a form submission — and if the write fails the switch
/// goes back and says why, which is the only thing waiting ever bought.
class _EnableSwitch extends StatefulWidget {
  const _EnableSwitch({required this.active, required this.onChanged});

  final bool active;
  final Future<void> Function() onChanged;

  @override
  State<_EnableSwitch> createState() => _EnableSwitchState();
}

class _EnableSwitchState extends State<_EnableSwitch> {
  /// What the switch is SHOWING, which runs ahead of what the server holds.
  bool? _optimistic;

  @override
  void didUpdateWidget(covariant _EnableSwitch old) {
    super.didUpdateWidget(old);
    // Once the refreshed row agrees with us, stop overriding it — otherwise a
    // change made anywhere else would never show on this row again.
    if (_optimistic != null && widget.active == _optimistic) _optimistic = null;
  }

  Future<void> _flip() async {
    setState(() => _optimistic = !(_optimistic ?? widget.active));
    try {
      await widget.onChanged();
    } catch (e) {
      if (!mounted) return;
      setState(() => _optimistic = null);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString().replaceAll('Exception: ', '')),
        backgroundColor: context.colors.dangerRed,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final on = _optimistic ?? widget.active;
    final track = on ? context.colors.successGreen : context.colors.textMuted;
    return Tooltip(
      message: on ? 'Disable (hides it from pickers)' : 'Enable',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: _flip,
          child: SizedBox(
            width: kIctIconButtonSize,
            height: kIctIconButtonSize,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                width: 30,
                height: 17,
                decoration: BoxDecoration(
                  color: track.withOpacity(on ? 0.9 : 0.3),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: AnimatedAlign(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  alignment: on ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    width: 13,
                    height: 13,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: const BoxDecoration(
                        color: Colors.white, shape: BoxShape.circle),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
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
