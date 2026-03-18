import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/providers.dart';
import '../../models/models.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/status_chip.dart';
import 'package:data_table_2/data_table_2.dart';

class PackagesScreen extends ConsumerStatefulWidget {
  const PackagesScreen({super.key});
  @override
  ConsumerState<PackagesScreen> createState() => _PackagesScreenState();
}

class _PackagesScreenState extends ConsumerState<PackagesScreen> {
  final _tableSearchCtrl = TextEditingController();
  PackageModel? _srResult;
  String? _srError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tableSearchCtrl.text = ref.read(packageSearchProvider);
    });
  }

  @override
  void dispose() {
    _tableSearchCtrl.dispose();
    super.dispose();
  }

  void _onSrSubmitted(String val) {
    final sr = val.trim();
    if (sr.isEmpty) {
      setState(() { _srResult = null; _srError = null; });
      return;
    }
    final packages = ref.read(livePackagesProvider).valueOrNull ?? [];
    final match = packages.where((p) => p.srNumber.toLowerCase().contains(sr.toLowerCase())).firstOrNull;
    setState(() {
      _srResult = match;
      _srError = match == null ? 'No package found matching: "$sr"' : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(packageFilterProvider);
    final packages = ref.watch(livePackagesProvider);

    return AppShell(
      currentRoute: '/packages',
      child: Scaffold(
        backgroundColor: context.colors.scaffoldBg,
        body: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
               Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Package History', style: Theme.of(context).textTheme.headlineLarge),
                      Text('Search and filter all inspected packages',
                          style: TextStyle(color: context.colors.textSecondary)),
                    ],
                  ),
                  Row(children: [
                    Text('Show Returned', style: TextStyle(color: context.colors.textSecondary, fontSize: 13)),
                    const Gap(8),
                    Switch(
                      value: ref.watch(packageShowReturnedProvider),
                      onChanged: (v) => ref.read(packageShowReturnedProvider.notifier).state = v,
                      activeColor: context.colors.primaryGold,
                    ),
                    const Gap(24),
                    packages.when(
                      data: (list) => Text('${list.length} packages', style: TextStyle(color: context.colors.textMuted, fontSize: 14)),
                      loading: () => const SizedBox(),
                      error: (_, __) => const SizedBox()
                    ),
                  ]),
                ],
              ).animate().fadeIn(),
              const Gap(20),

              // ── Unified Search & Filter Bar ──────────────────────
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.colors.cardDark,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: context.colors.primaryGold.withOpacity(0.5)),
                ),
                child: Row(children: [
                  Expanded(
                    child: Autocomplete<PackageModel>(
                      displayStringForOption: (p) => p.srNumber,
                      initialValue: TextEditingValue(text: _tableSearchCtrl.text),
                      optionsBuilder: (textEditingValue) {
                        final query = textEditingValue.text.trim().toLowerCase();
                        if (query.isEmpty) return const [];
                        final packages = ref.read(livePackagesProvider).valueOrNull ?? [];
                        return packages.where((p) => p.srNumber.toLowerCase().contains(query) || p.consigneeName.toLowerCase().contains(query));
                      },
                      onSelected: (package) {
                        setState(() {
                          _srResult = package;
                          _tableSearchCtrl.text = package.srNumber;
                          ref.read(packageSearchProvider.notifier).state = package.srNumber;
                        });
                      },
                      optionsViewBuilder: (context, onSelected, options) {
                        return Align(
                          alignment: Alignment.topLeft,
                          child: Material(
                            color: Colors.transparent,
                            child: Container(
                              width: 500,
                              margin: const EdgeInsets.only(top: 8),
                              decoration: BoxDecoration(
                                color: context.colors.surfaceDark,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: context.colors.borderColor),
                                boxShadow: [
                                  BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 10, offset: const Offset(0, 4))
                                ],
                              ),
                              child: ListView.builder(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                shrinkWrap: true,
                                itemCount: options.length,
                                itemBuilder: (context, index) {
                                  final option = options.elementAt(index);
                                  return InkWell(
                                    onTap: () => onSelected(option),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                      child: Row(
                                        children: [
                                          Text(option.srNumber, style: TextStyle(color: context.colors.accentLightBlue, fontWeight: FontWeight.bold)),
                                          const Gap(12),
                                          Expanded(child: Text(option.consigneeName, style: TextStyle(color: context.colors.textSecondary, fontSize: 13), overflow: TextOverflow.ellipsis)),
                                          StatusChip(status: option.status),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        );
                      },
                      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                        // Sync external controller if needed
                        if (controller.text != _tableSearchCtrl.text && _tableSearchCtrl.text.isNotEmpty && controller.text.isEmpty) {
                           controller.text = _tableSearchCtrl.text;
                        }
                        return TextField(
                          controller: controller,
                          focusNode: focusNode,
                          style: TextStyle(color: context.colors.textPrimary),
                          decoration: InputDecoration(
                            hintText: 'Search SR #, consignee or declarant...',
                            prefixIcon: Icon(Icons.search_rounded, color: context.colors.textMuted),
                            suffixIcon: controller.text.isNotEmpty
                                ? IconButton(
                                    icon: Icon(Icons.clear_rounded, color: context.colors.textMuted),
                                    onPressed: () {
                                      controller.clear();
                                      _tableSearchCtrl.clear();
                                      ref.read(packageSearchProvider.notifier).state = '';
                                      setState(() { _srResult = null; });
                                    },
                                  )
                                : null,
                            isDense: true,
                          ),
                          onChanged: (v) {
                            _tableSearchCtrl.text = v;
                            ref.read(packageSearchProvider.notifier).state = v;
                            setState(() {
                               if (v.trim().isEmpty) _srResult = null;
                            });
                          },
                        );
                      },
                    ),
                  ),
                  const Gap(12),
                  ...['all', 'pending', 'held', 'cleared', 'confiscated'].map((s) => Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: FilterChip(
                      label: Text(s.toUpperCase()),
                      selected: filter == s,
                      onSelected: (_) => ref.read(packageFilterProvider.notifier).state = s,
                      selectedColor: context.colors.primaryGold.withOpacity(0.2),
                      checkmarkColor: context.colors.primaryGold,
                      labelStyle: TextStyle(
                        color: filter == s ? context.colors.primaryGold : context.colors.textSecondary,
                        fontSize: 12, fontWeight: filter == s ? FontWeight.w700 : FontWeight.w400),
                    ),
                  )),
                ]),
              ).animate().slideY(begin: 0.1, duration: 400.ms, delay: 200.ms).fadeIn(),

              if (_srResult != null) ...[
                const Gap(16),
                _SrResultCard(package: _srResult!, onDetails: () => _showDetails(context, _srResult!)).animate().fadeIn(),
              ],
              const Gap(16),
              Expanded(
                child: packages.when(
                  loading: () => Center(child: CircularProgressIndicator(color: context.colors.primaryGold)),
                  error: (e, _) => Center(child: Text('Error: $e')),
                  data: (list) {
                    final showReturned = ref.watch(packageShowReturnedProvider);
                    final filteredList = list.where((p) {
                      if (!showReturned && p.isReturned) return false;
                      return true;
                    }).toList();

                    if (filteredList.isEmpty) {
                      return Center(child: Text('No packages found', style: TextStyle(color: context.colors.textMuted, fontSize: 16)));
                    }

                    return Container(
                          decoration: BoxDecoration(color: context.colors.cardDark, borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: context.colors.borderColor)),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: DataTable2(
                              columnSpacing: 12,
                              horizontalMargin: 12,
                              fixedTopRows: 1,
                              isVerticalScrollBarVisible: true,
                              isHorizontalScrollBarVisible: false,
                              columns: const [
                                DataColumn2(label: Text('SR Number'), size: ColumnSize.L, fixedWidth: 140),
                                DataColumn2(label: Text('Consignee'), size: ColumnSize.L),
                                DataColumn2(label: Text('Declarant'), size: ColumnSize.M),
                                DataColumn2(label: Text('Cusdec No'), size: ColumnSize.S),
                                DataColumn2(label: Text('Cusdec Date'), size: ColumnSize.S),
                                DataColumn2(label: Text('Reason'), size: ColumnSize.M),
                                DataColumn2(label: Text('Status'), size: ColumnSize.S, fixedWidth: 100),
                                DataColumn2(label: Text('Entry Date'), size: ColumnSize.S, fixedWidth: 100),
                                DataColumn2(label: Text('Returned'), size: ColumnSize.S, fixedWidth: 100),
                                DataColumn2(label: Text('Warehouse'), size: ColumnSize.M),
                                DataColumn2(label: Text('Details'), size: ColumnSize.S, fixedWidth: 60),
                              ],
                              rows: list.map((p) => DataRow(cells: [
                                DataCell(Text(p.srNumber, style: TextStyle(color: context.colors.accentLightBlue, fontWeight: FontWeight.w600))),
                                DataCell(Text(p.consigneeName, overflow: TextOverflow.ellipsis)),
                                DataCell(Text(p.declarantName ?? '-', overflow: TextOverflow.ellipsis)),
                                DataCell(Text(p.cusdecNo ?? '-', overflow: TextOverflow.ellipsis)),
                                DataCell(Text(p.cusdecDate ?? '-')),
                                DataCell(Text(p.reason ?? '-', overflow: TextOverflow.ellipsis)),
                                DataCell(StatusChip(status: p.status)),
                                DataCell(Text(p.entryDate != null
                                  ? DateFormat('dd/MM/yy').format(p.entryDate!)
                                  : DateFormat('dd/MM/yy').format(p.createdAt))),
                                DataCell(Text(p.returnedAt != null 
                                  ? DateFormat('dd/MM/yy').format(p.returnedAt!) 
                                  : '—', style: TextStyle(color: context.colors.successGreen, fontWeight: FontWeight.w600))),
                                DataCell(_WarehousePill(warehouseEntries: p.warehouseEntries)),
                                DataCell(IconButton(
                                  icon: Icon(Icons.info_outline_rounded, color: context.colors.accentLightBlue, size: 18),
                                  onPressed: () => _showDetails(context, p),
                                )),
                              ])).toList(),
                            ),
                          ),
                        ).animate().slideY(begin: 0.1, duration: 400.ms, delay: 300.ms).fadeIn();
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDetails(BuildContext context, PackageModel p) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('SR Register Entry: ${p.srNumber}'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              _Row('Status', p.status.toUpperCase()),
              _Row('Reason', p.reason ?? '-'),
              _Row('Consignee', p.consigneeName),
              if (p.consigneeNic != null) _Row('NIC', p.consigneeNic!),
              if (p.consigneePhone != null) _Row('Phone', p.consigneePhone!),
              _Row('Declarant', p.declarantName ?? '-'),
              _Row('Cusdec No', p.cusdecNo ?? '-'),
              _Row('Cusdec Date', p.cusdecDate ?? '-'),
              if (p.entryDate != null) _Row('Entry Date', DateFormat('dd/MM/yyyy').format(p.entryDate!)),
              if (p.originCountry.isNotEmpty) _Row('Origin', p.originCountry),
              if (p.declaredValue > 0) _Row('Value', 'LKR ${NumberFormat('#,##0.00').format(p.declaredValue)}'),
              if (p.weightKg > 0) _Row('Weight', '${p.weightKg} kg'),
              if (p.description != null && p.description!.isNotEmpty) _Row('Description', p.description!),
              if (p.notes != null && p.notes!.isNotEmpty) _Row('Notes', p.notes!),
              _Row('Created At', DateFormat('dd/MM/yyyy HH:mm').format(p.createdAt)),
              if (p.items.isNotEmpty) ...[
                const Gap(16),
                Text('Items', style: TextStyle(color: context.colors.primaryGold, fontWeight: FontWeight.w700)),
                const Gap(8),
                ...p.items.map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(children: [
                    Container(width: 6, height: 6, decoration: BoxDecoration(color: context.colors.primaryGold, shape: BoxShape.circle)),
                    const Gap(8),
                    Expanded(child: Text(item.itemName)),
                    Text('x${item.quantity}', style: TextStyle(color: context.colors.textMuted)),
                    if (item.category != null) ...[const Gap(8), Text('[${item.category}]', style: TextStyle(color: context.colors.textMuted, fontSize: 12))],
                    if (item.isProhibited) ...[const Gap(8), Icon(Icons.warning_amber_rounded, color: context.colors.dangerRed, size: 14)],
                  ]),
                )),
              ],
              if (p.warehouseEntries.isNotEmpty) ...[
                const Gap(16),
                Text('Warehouse History', style: TextStyle(color: context.colors.primaryGold, fontWeight: FontWeight.w700)),
                const Gap(8),
                ...p.warehouseEntries.map((we) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: context.colors.surfaceDark, borderRadius: BorderRadius.circular(8)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(we.warehouseName, style: TextStyle(color: context.colors.primaryGold, fontWeight: FontWeight.w600)),
                    Text('Admitted: ${DateFormat('dd/MM/yy HH:mm').format(we.admittedAt)}', style: TextStyle(color: context.colors.textSecondary, fontSize: 12)),
                    Text('Reason: ${we.holdReason}', style: const TextStyle(fontSize: 13)),
                    Text('Items: ${we.itemCount}', style: TextStyle(color: context.colors.textMuted, fontSize: 12)),
                    if (we.isReturned && we.returnedAt != null)
                      Text('Returned: ${DateFormat('dd/MM/yy').format(we.returnedAt!)}',
                          style: TextStyle(color: context.colors.successGreen, fontSize: 12)),
                  ]),
                )),
              ],
            ]),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
    );
  }
}

// ── SR Search Result Card ──────────────────────────────────────

class _SrResultCard extends StatelessWidget {
  final PackageModel package;
  final VoidCallback onDetails;
  const _SrResultCard({required this.package, required this.onDetails});

  @override
  Widget build(BuildContext context) {
    final activeEntries = package.warehouseEntries.where((e) => !e.isReturned).toList();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.surfaceDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.accentLightBlue.withOpacity(0.4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.inventory_2_rounded, color: context.colors.accentLightBlue, size: 18),
          const Gap(8),
          Text(package.srNumber,
              style: TextStyle(color: context.colors.accentLightBlue, fontWeight: FontWeight.w700, fontSize: 15)),
          const Spacer(),
          StatusChip(status: package.status),
        ]),
        const Gap(8),
        Text('Consignee: ${package.consigneeName}',
            style: TextStyle(color: context.colors.textSecondary, fontSize: 13)),
        if (package.declarantName != null)
          Text('Declarant: ${package.declarantName}',
              style: TextStyle(color: context.colors.textSecondary, fontSize: 13)),
        const Gap(12),
        if (activeEntries.isEmpty)
          Row(children: [
            Icon(Icons.check_circle_outline, color: context.colors.successGreen, size: 16),
            const Gap(6),
            Text('Not currently held in any warehouse.',
                style: TextStyle(color: context.colors.successGreen, fontSize: 13)),
          ])
        else ...[
          Text('Current Warehouse Location:', style: TextStyle(color: context.colors.textMuted, fontSize: 12)),
          const Gap(6),
          ...activeEntries.map((e) => Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: context.colors.heldOrange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: context.colors.heldOrange.withOpacity(0.35)),
            ),
            child: Row(children: [
              Icon(Icons.warehouse_rounded, color: context.colors.heldOrange, size: 18),
              const Gap(10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(e.warehouseName,
                    style: TextStyle(color: context.colors.heldOrange, fontWeight: FontWeight.w700)),
                Text('Held since: ${DateFormat('dd/MM/yyyy HH:mm').format(e.admittedAt)}',
                    style: TextStyle(color: context.colors.textMuted, fontSize: 12)),
                Text('Reason: ${e.holdReason}',
                    style: TextStyle(color: context.colors.textSecondary, fontSize: 12)),
              ])),
              Text('${e.itemCount} items', style: TextStyle(color: context.colors.textMuted, fontSize: 12)),
            ]),
          )),
        ],
        const Gap(16),
        Center(
          child: OutlinedButton.icon(
            onPressed: onDetails,
            icon: const Icon(Icons.info_outline_rounded, size: 16),
            label: const Text('View Full Details', style: TextStyle(fontSize: 12)),
            style: OutlinedButton.styleFrom(
              foregroundColor: context.colors.accentLightBlue,
              side: BorderSide(color: context.colors.accentLightBlue.withOpacity(0.5)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            ),
          ),
        ),
      ]),
    );
  }
}

// ── Warehouse Pill (for table) ──────────────────────────────────

class _WarehousePill extends StatelessWidget {
  final List<WarehouseEntryModel> warehouseEntries;
  const _WarehousePill({required this.warehouseEntries});

  @override
  Widget build(BuildContext context) {
    final active = warehouseEntries.where((e) => !e.isReturned).toList();
    if (active.isEmpty) return Text('—', style: TextStyle(color: context.colors.textMuted));
    return Wrap(spacing: 4, children: active.map((e) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: context.colors.heldOrange.withOpacity(0.12),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: context.colors.heldOrange.withOpacity(0.4)),
      ),
      child: Text(e.warehouseName, style: TextStyle(color: context.colors.heldOrange, fontSize: 11, fontWeight: FontWeight.w600)),
    )).toList());
  }
}

class _Row extends StatelessWidget {
  final String label, value;
  const _Row(this.label, this.value);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 130, child: Text(label, style: TextStyle(color: context.colors.textMuted, fontSize: 13, fontWeight: FontWeight.w500))),
        Expanded(child: Text(value, style: TextStyle(color: context.colors.textPrimary, fontSize: 13))),
      ]),
    );
  }
}
