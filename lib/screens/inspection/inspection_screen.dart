import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import 'package:gap/gap.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:uuid/uuid.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';
import '../../core/theme.dart';
import '../../core/providers.dart';
import '../../services/services.dart';
import '../../models/models.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/error_view.dart';
import '../../widgets/custom_dropdown.dart';
import '../../widgets/warehouse_selection_dialog.dart';
import '../../widgets/print_barcode_dialog.dart';
import '../../core/supabase_client.dart';

class InspectionScreen extends ConsumerStatefulWidget {
  const InspectionScreen({super.key});
  @override
  ConsumerState<InspectionScreen> createState() => _InspectionScreenState();
}

class _InspectionScreenState extends ConsumerState<InspectionScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _srNumberCtrl = TextEditingController();
  final _caseNumberCtrl = TextEditingController();
  final _originCtrl = TextEditingController();
  final _valueCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();
  final _consigneeCtrl = TextEditingController();
  final _consigneeNicCtrl = TextEditingController();
  final _consigneePhoneCtrl = TextEditingController();
  final _declarantCtrl = TextEditingController();
  final _cusdecCtrl = TextEditingController();
  final _cusdecDateCtrl = TextEditingController();
  final _entryDateCtrl = TextEditingController(
      text:
          "${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}");
  final _containerNumberCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _reasonCtrlMain = TextEditingController();
  final _notesCtrl = TextEditingController();

  final _dateMask = MaskTextInputFormatter(
    mask: '####-##-##',
    filter: {"#": RegExp(r'[0-9]')},
    type: MaskAutoCompletionType.lazy,
  );

  // Custom SR formatter to handle various formats while maintaining some structure
  final _srMask = MaskTextInputFormatter(
    mask: '********************', // Allow up to 20 generic characters
    filter: {
      "*": RegExp(r'[a-zA-Z0-9/ ]'), // Allow alphanumeric, slash, and spaces
    },
    type: MaskAutoCompletionType.lazy,
  );

  String _statusValue = 'pending';
  final List<_ItemRow> _items = [_ItemRow()];

  bool _isChecking = false;
  bool _isLookingUp = false;
  bool _showValidationErrors = false;
  int _validationRun = 0;
  bool? _passed;
  List<String> _violations = [];
  String? _savedPackageId;
  String? _suggestedWarehouseId;
  bool _isUpdate = false;
  late TabController _tabController;
  PackageModel? _warehouseConfirmedPackage;

  // Temporary storage for package data before warehouse confirmation
  PackageModel? _tempPackageData;
  List<PackageItem>? _tempPackageItems;
  Key _resultPanelKey = UniqueKey();

  /// Fetch an existing package by SR number and populate the form
  Future<void> _loadBySrNumber() async {
    final sr = _srNumberCtrl.text.trim();
    if (sr.isEmpty) return;
    setState(() => _isLookingUp = true);
    try {
      final pkg =
          await ref.read(packageServiceProvider).getPackageBySrNumber(sr);
      if (pkg == null) {
        setState(() => _isUpdate = false);
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('SR "$sr" not found – filling as new entry.'),
              backgroundColor: context.colors.customsBlue));
        return;
      }
      _originCtrl.text = pkg.originCountry ?? '';
      _valueCtrl.text = pkg.declaredValue?.toString() ?? '';
      _weightCtrl.text = pkg.weightKg?.toString() ?? '';
      _consigneeCtrl.text = pkg.consigneeName;
      _consigneeNicCtrl.text = pkg.consigneeNic ?? '';
      _consigneePhoneCtrl.text = pkg.consigneePhone ?? '';
      _declarantCtrl.text = pkg.declarantName ?? '';
      _cusdecCtrl.text = pkg.cusdecNo ?? '';
      _cusdecDateCtrl.text = pkg.cusdecDate ?? '';
      _entryDateCtrl.text = pkg.entryDate != null
          ? '${pkg.entryDate!.year}-${pkg.entryDate!.month.toString().padLeft(2, '0')}-${pkg.entryDate!.day.toString().padLeft(2, '0')}'
          : '';
      _descCtrl.text = pkg.description ?? '';
      _containerNumberCtrl.text = pkg.containerNumber ?? '';
      _reasonCtrlMain.text = pkg.reason ?? '';
      _notesCtrl.text = pkg.notes ?? '';
      setState(() {
        _statusValue = (pkg.status == 'detained' || pkg.status == 'forfeited')
            ? 'held'
            : pkg.status;
        _isUpdate = true;
        _items.clear();
        if (pkg.items != null && pkg.items!.isNotEmpty) {
          for (final item in pkg.items!) {
            final row = _ItemRow();
            row.itemId = item.id;
            row.nameCtrl.text = item.itemName;
            row.goodsDescriptionCtrl.text = item.goodsDescription ?? '';
            row.qtyCtrl.text = item.quantity.toString();
            row.valueCtrl.text = item.unitValue.toString();
            row.categoryCtrl.text = item.category ?? '';
            const statuses = ['Detain', 'Forfeit', 'Abandoned', 'Other'];
            if (statuses.contains(item.status)) {
              row.status = item.status;
              row.otherStatusCtrl.clear();
            } else {
              row.status = 'Other';
              row.otherStatusCtrl.text = item.status;
            }

            if (item.reasons != null && item.reasons!.isNotEmpty) {
              final reasonList =
                  item.reasons!.split(', ').map((s) => s.trim()).toList();
              // Cap at 4 reasons and ensure at least 1
              row.selectedReasons.clear();
              for (int i = 0; i < reasonList.length && i < 4; i++) {
                row.selectedReasons.add(reasonList[i]);
              }
              if (row.selectedReasons.isEmpty) row.selectedReasons.add(null);
            } else {
              row.selectedReasons.clear();
              row.selectedReasons.add(null);
            }

            _items.add(row);
          }
        } else {
          _items.add(_ItemRow());
        }
      });
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('SR "$sr" loaded – you can edit and save.'),
            backgroundColor: context.colors.successGreen));
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Lookup error: $e'),
            backgroundColor: context.colors.dangerRed));
    } finally {
      setState(() => _isLookingUp = false);
    }
  }

  Future<void> _selectDate(TextEditingController controller,
      {DateTime? lastDate}) async {
    DateTime initial = DateTime.tryParse(controller.text) ?? DateTime.now();
    if (lastDate != null && initial.isAfter(lastDate)) {
      initial = lastDate;
    }
    final DateTime? picked = await showDialog<DateTime>(
      context: context,
      builder: (_) =>
          _OneTapDatePicker(initialDate: initial, lastDate: lastDate),
    );
    if (picked != null) {
      setState(() {
        controller.text =
            "${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}";
      });
      _formKey.currentState?.validate();
    }
  }

  InputDecoration _fieldDecoration({
    required String labelText,
    String? hintText,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      suffixIcon: suffixIcon,
      helperText: ' ',
      errorMaxLines: 1,
    );
  }

  String? _requiredValidator(String? value, {String message = 'Required'}) {
    if (!_showValidationErrors) return null;
    return value == null || value.trim().isEmpty ? message : null;
  }

  String? _dateValidator(String? value) {
    if (!_showValidationErrors) return null;
    if (value == null || value.trim().isEmpty) return 'Required';
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value.trim())) {
      return 'Use YYYY-MM-DD format';
    }
    return null;
  }

  void _scheduleValidationHide() {
    final run = ++_validationRun;
    Future.delayed(const Duration(seconds: 3), () {
      if (!mounted || run != _validationRun) return;
      setState(() => _showValidationErrors = false);
      // validate() must run AFTER the rebuild so _ItemRowWidget.showValidationErrors
      // is already false — otherwise validators still see the old true value and re-set errors.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _formKey.currentState?.validate();
      });
    });
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_handleTabChange);
    _generateNextSr();
  }

  void _handleTabChange() {
    if (!mounted) return;
    setState(() {});
    if (_tabController.indexIsChanging) return;
    final idx = _tabController.index;
    final canGoToWarehouse = _tempPackageData != null && _tempPackageItems != null;
    final canGoToQr = _warehouseConfirmedPackage != null;
    if (idx == 1 && !canGoToWarehouse) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _tabController.animateTo(0);
      });
    } else if (idx == 2 && !canGoToQr) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _tabController.animateTo(canGoToWarehouse ? 1 : 0);
      });
    }
  }

  Future<void> _generateNextSr() async {
    try {
      final sr = await ref.read(packageServiceProvider).getNextSrNumber();
      setState(() {
        _srNumberCtrl.text = sr;
      });
    } catch (e) {
      print('Error generating SR: $e');
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChange);
    _tabController.dispose();
    _srNumberCtrl.dispose();
    _originCtrl.dispose();
    _valueCtrl.dispose();
    _weightCtrl.dispose();
    _consigneeCtrl.dispose();
    _consigneeNicCtrl.dispose();
    _consigneePhoneCtrl.dispose();
    _declarantCtrl.dispose();
    _cusdecCtrl.dispose();
    _cusdecDateCtrl.dispose();
    _entryDateCtrl.dispose();
    _containerNumberCtrl.dispose();
    _descCtrl.dispose();
    _reasonCtrlMain.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkPackage() async {
    setState(() => _showValidationErrors = true);
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    if (!_formKey.currentState!.validate()) {
      _scheduleValidationHide();
      return;
    }
    _validationRun++;
    setState(() {
      _isChecking = true;
      _passed = null;
      _violations = [];
    });
    try {
      final items = _items
          .where((r) => r.nameCtrl.text.isNotEmpty)
          .map((r) => PackageItem(
                id: r.itemId ?? const Uuid().v4(),
                packageId: '',
                itemName: r.nameCtrl.text,
                goodsDescription: r.goodsDescriptionCtrl.text.trim().isEmpty
                    ? null
                    : r.goodsDescriptionCtrl.text.trim(),
                quantity: int.tryParse(r.qtyCtrl.text) ?? 1,
                unitOfMeasure: r.unitOfMeasureCtrl.text,
                unitOther: r.unitOfMeasureCtrl.text == 'Other'
                    ? r.unitOtherCtrl.text
                    : null,
                unitValue: double.tryParse(r.valueCtrl.text) ?? 0,
                category: r.categoryCtrl.text,
                status: r.status == 'Other'
                    ? r.otherStatusCtrl.text.trim()
                    : r.status,
                reasons:
                    r.selectedReasons.where((res) => res != null).join(', '),
              ))
          .toList();

      final pkg = PackageModel(
        id: '',
        srNumber: _srNumberCtrl.text.trim(),
        originCountry: _originCtrl.text.trim(),
        declaredValue: double.tryParse(_valueCtrl.text) ?? 0,
        weightKg: double.tryParse(_weightCtrl.text) ?? 0,
        totalItemCount: items.fold(0, (sum, i) => sum + i.quantity),
        description: _descCtrl.text,
        containerNumber: _containerNumberCtrl.text.trim().isEmpty
            ? null
            : _containerNumberCtrl.text.trim(),
        consigneeName: _consigneeCtrl.text.trim(),
        consigneeNic: _consigneeNicCtrl.text,
        consigneePhone: _consigneePhoneCtrl.text,
        declarantName: _declarantCtrl.text.trim(),
        cusdecNo: _cusdecCtrl.text.trim(),
        cusdecDate: _cusdecDateCtrl.text.trim(),
        entryDate: _entryDateCtrl.text.isNotEmpty
            ? DateTime.tryParse(_entryDateCtrl.text)
            : null,
        reason: _reasonCtrlMain.text.trim(),
        status: 'pending', // General status for package
        notes: _notesCtrl.text,
        inspectedBy: supabase.auth.currentUser?.id,
        inspectedAt: DateTime.now(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // Store temporarily - don't save to database yet
      _tempPackageData = pkg;
      _tempPackageItems = items;
      _warehouseConfirmedPackage = null;

      setState(() {
        _passed = true;
        _violations = [];
        _resultPanelKey = UniqueKey();
        _suggestedWarehouseId = null;
        _savedPackageId = null;
      });
      _tabController.animateTo(1);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error: $e'),
            backgroundColor: context.colors.dangerRed));
    } finally {
      setState(() => _isChecking = false);
    }
  }

  void _reset() {
    _formKey.currentState?.reset();
    _srNumberCtrl.clear();
    _originCtrl.clear();
    _valueCtrl.clear();
    _weightCtrl.clear();
    _consigneeCtrl.clear();
    _consigneeNicCtrl.clear();
    _consigneePhoneCtrl.clear();
    _declarantCtrl.clear();
    _cusdecCtrl.clear();
    _cusdecDateCtrl.clear();
    _entryDateCtrl.text =
        "${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}";
    _containerNumberCtrl.clear();
    _descCtrl.clear();
    _reasonCtrlMain.clear();
    _notesCtrl.clear();
    _tempPackageData = null;
    _tempPackageItems = null;
    _tabController.animateTo(0);
    setState(() {
      _statusValue = 'pending';
      _items.clear();
      _items.add(_ItemRow());
      _passed = null;
      _violations = [];
      _savedPackageId = null;
      _suggestedWarehouseId = null;
      _warehouseConfirmedPackage = null;
    });
    _generateNextSr();
  }

  String _formatWarehouseName(String name) {
    // Extract warehouse number from names like "SR Warehouse 03" -> "Warehouse 3"
    final regex = RegExp(r'(\d+)');
    final match = regex.firstMatch(name);
    if (match != null) {
      final number = int.tryParse(match.group(1)!);
      if (number != null) {
        return 'Warehouse $number';
      }
    }
    return name;
  }

  @override
  Widget build(BuildContext context) {
    // Get current user's role to conditionally disable save button
    final currentProfile = ref.watch(currentProfileProvider);
    final isOfficer = currentProfile?.role == 'officer';

    return AppShell(
      currentRoute: '/inspection',
      child: Scaffold(
        backgroundColor: context.colors.scaffoldBg,
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 12),
              child: SizedBox(
                width: double.infinity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Package Registration',
                        style: Theme.of(context).textTheme.headlineLarge),
                    Text('Enter incoming package details for SR registration',
                        style: TextStyle(color: context.colors.textSecondary)),
                  ],
                ),
              ),
            ).animate().fadeIn(),
            Container(
              height: 52,
              margin: const EdgeInsets.fromLTRB(28, 0, 28, 12),
              decoration: BoxDecoration(
                color: context.colors.surfaceDark,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: context.colors.borderColor),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  )
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: TabBar(
                  controller: _tabController,
                  onTap: (idx) {
                    final canGoToWarehouse =
                        _tempPackageData != null && _tempPackageItems != null;
                    final canGoToQr = _warehouseConfirmedPackage != null;
                    if (idx == 1 && !canGoToWarehouse) {
                      _checkPackage();
                    } else if (idx == 2 && !canGoToQr) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: const Text(
                            'Please complete warehouse confirmation first'),
                        backgroundColor: context.colors.heldOrange,
                      ));
                    }
                  },
                  tabs: [
                    Tab(
                      child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.edit_document, size: 16),
                            const Gap(8),
                            const Text('Form',
                                style: TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.w600)),
                          ]),
                    ),
                    Tab(
                      child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.warehouse_rounded,
                                size: 16,
                                color: _tempPackageData == null
                                    ? context.colors.textMuted
                                    : null),
                            const Gap(8),
                            Text('Warehouse Confirmation',
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: _tempPackageData == null
                                        ? context.colors.textMuted
                                        : null)),
                          ]),
                    ),
                    Tab(
                      child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.qr_code_2_rounded,
                                size: 16,
                                color: _warehouseConfirmedPackage == null
                                    ? context.colors.textMuted
                                    : null),
                            const Gap(8),
                            Text('QR Code Generate',
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: _warehouseConfirmedPackage == null
                                        ? context.colors.textMuted
                                        : null)),
                          ]),
                    ),
                  ],
                  indicatorSize: TabBarIndicatorSize.tab,
                  indicatorPadding: const EdgeInsets.all(2),
                  indicator: BoxDecoration(
                    color: context.colors.primaryGold.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: context.colors.primaryGold.withOpacity(0.5)),
                  ),
                  splashBorderRadius: BorderRadius.circular(12),
                  overlayColor:
                      WidgetStateProperty.resolveWith<Color?>((states) {
                    if (states.contains(WidgetState.hovered))
                      return Colors.grey.withOpacity(0.1);
                    return Colors.transparent;
                  }),
                  splashFactory: NoSplash.splashFactory,
                  labelColor: context.colors.primaryGold,
                  unselectedLabelColor: context.colors.textSecondary,
                  dividerColor: Colors.transparent,
                ),
              ),
            ).animate().slideY(begin: 0.1, duration: 400.ms, delay: 100.ms).fadeIn(),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  SingleChildScrollView(
                      padding: const EdgeInsets.all(28),
                      child: Form(
                        key: _formKey,
                        autovalidateMode: _showValidationErrors
                            ? AutovalidateMode.always
                            : AutovalidateMode.disabled,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _SectionCard(
                                    title: 'SR Register Information',
                                    icon: Icons.inventory_2_rounded,
                                    children: [
                                  if (_isUpdate)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 8),
                                      margin: const EdgeInsets.only(bottom: 12),
                                      decoration: BoxDecoration(
                                        color: context.colors.primaryGold
                                            .withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                            color: context.colors.primaryGold
                                                .withOpacity(0.4)),
                                      ),
                                      child: Row(children: [
                                        Icon(Icons.edit_rounded,
                                            color: context.colors.primaryGold,
                                            size: 16),
                                        const Gap(8),
                                        Text(
                                            'Editing existing SR entry – changes will update the record.',
                                            style: TextStyle(
                                                color:
                                                    context.colors.primaryGold,
                                                fontSize: 13)),
                                      ]),
                                    ),
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: TextFormField(
                                          controller: _srNumberCtrl,
                                          inputFormatters: [
                                            FilteringTextInputFormatter.allow(
                                                RegExp(r'[a-zA-Z0-9/ ]')),
                                            LengthLimitingTextInputFormatter(
                                                30),
                                          ],
                                          decoration: _fieldDecoration(
                                            labelText: 'SR Number *',
                                            hintText:
                                                'e.g. GL1/SR/01/2025 or GL1/MISC/187/2025',
                                            suffixIcon: Tooltip(
                                              message: isOfficer
                                                  ? 'Loading existing SR entries is restricted to administrators only'
                                                  : '',
                                              child: IconButton(
                                                icon: _isLookingUp
                                                    ? SizedBox(
                                                        width: 16,
                                                        height: 16,
                                                        child:
                                                            CircularProgressIndicator(
                                                                strokeWidth: 2,
                                                                color: context
                                                                    .colors
                                                                    .primaryGold))
                                                    : Icon(Icons.search_rounded,
                                                        color: isOfficer
                                                            ? context.colors
                                                                .textMuted
                                                            : context.colors
                                                                .primaryGold),
                                                onPressed:
                                                    (isOfficer || _isLookingUp)
                                                        ? null
                                                        : _loadBySrNumber,
                                              ),
                                            ),
                                          ),
                                          validator: _requiredValidator,
                                          onFieldSubmitted: (_) => isOfficer
                                              ? null
                                              : _loadBySrNumber(),
                                          textCapitalization:
                                              TextCapitalization.characters,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const Gap(16),
                                  Row(children: [
                                    Expanded(
                                        child: TextFormField(
                                            controller: _cusdecCtrl,
                                            decoration: _fieldDecoration(
                                                labelText: 'Cusdec No *'),
                                            validator: _requiredValidator)),
                                    const Gap(12),
                                    Expanded(
                                        child: TextFormField(
                                            controller: _entryDateCtrl,
                                            readOnly: true,
                                            onTap: () => _selectDate(
                                                _entryDateCtrl,
                                                lastDate: DateTime.now()),
                                            inputFormatters: [
                                              MaskTextInputFormatter(
                                                mask: '####-##-##',
                                                filter: {"#": RegExp(r'[0-9]')},
                                                type:
                                                    MaskAutoCompletionType.lazy,
                                              )
                                            ],
                                            decoration: _fieldDecoration(
                                              labelText: 'Entry Date *',
                                              hintText: 'YYYY-MM-DD',
                                              suffixIcon: IconButton(
                                                icon: Icon(Icons.calendar_month,
                                                    color: context
                                                        .colors.primaryGold),
                                                onPressed: () => _selectDate(
                                                    _entryDateCtrl,
                                                    lastDate: DateTime.now()),
                                              ),
                                            ),
                                            validator: _dateValidator)),
                                  ]),
                                  const Gap(16),
                                  Row(children: [
                                    Expanded(
                                        child: TextFormField(
                                            controller: _caseNumberCtrl,
                                            decoration: _fieldDecoration(
                                                labelText: 'Case Number'),
                                            validator: (v) => null)),
                                    const Gap(12),
                                    Expanded(
                                        child: TextFormField(
                                            controller: _cusdecDateCtrl,
                                            readOnly: true,
                                            onTap: () => _selectDate(
                                                _cusdecDateCtrl,
                                                lastDate: DateTime.now()),
                                            inputFormatters: [
                                              MaskTextInputFormatter(
                                                mask: '####-##-##',
                                                filter: {"#": RegExp(r'[0-9]')},
                                                type:
                                                    MaskAutoCompletionType.lazy,
                                              )
                                            ],
                                            decoration: _fieldDecoration(
                                              labelText: 'Cusdec Date *',
                                              hintText: 'YYYY-MM-DD',
                                              suffixIcon: IconButton(
                                                icon: Icon(Icons.calendar_month,
                                                    color: context
                                                        .colors.primaryGold),
                                                onPressed: () => _selectDate(
                                                    _cusdecDateCtrl,
                                                    lastDate: DateTime.now()),
                                              ),
                                            ),
                                            validator: _dateValidator)),
                                  ]),
                                  const Gap(16),
                                  TextFormField(
                                    controller: _containerNumberCtrl,
                                    decoration: _fieldDecoration(
                                      labelText: 'Container Number',
                                    ),
                                    textCapitalization:
                                        TextCapitalization.characters,
                                  ),
                                  const Gap(16),
                                  TextFormField(
                                      controller: _descCtrl,
                                      decoration: _fieldDecoration(
                                          labelText: 'Package Description'),
                                      maxLines: 2),
                                ])
                                .animate()
                                .slideY(
                                    begin: 0.1, duration: 400.ms, delay: 100.ms)
                                .fadeIn(),
                            const Gap(16),
                            _SectionCard(
                                    title: 'Consignee Information',
                                    icon: Icons.person_rounded,
                                    children: [
                                  Row(children: [
                                    Expanded(
                                        child: TextFormField(
                                            controller: _consigneeCtrl,
                                            decoration: _fieldDecoration(
                                                labelText: 'Consignee Name *'),
                                            validator: _requiredValidator)),
                                    const Gap(12),
                                    Expanded(
                                        child: TextFormField(
                                            controller: _declarantCtrl,
                                            decoration: _fieldDecoration(
                                                labelText: 'Declarant Name *'),
                                            validator: _requiredValidator)),
                                  ]),
                                  const Gap(16),
                                  Row(children: [
                                    Expanded(
                                        child: TextFormField(
                                            controller: _consigneeNicCtrl,
                                            decoration: _fieldDecoration(
                                                labelText:
                                                    'Declarant Address'))),
                                    const Gap(12),
                                    Expanded(
                                        child: TextFormField(
                                            controller: _consigneePhoneCtrl,
                                            decoration: _fieldDecoration(
                                                labelText:
                                                    'Declarant Phone Number (10 digits) *'),
                                            keyboardType: TextInputType.phone,
                                            validator: (v) {
                                              if (!_showValidationErrors) {
                                                return null;
                                              }
                                              if (v == null || v.isEmpty)
                                                return 'Required';
                                              if (!RegExp(r'^\d{10}$')
                                                  .hasMatch(v)) {
                                                return 'Must be exactly 10 digits';
                                              }
                                              return null;
                                            })),
                                  ]),
                                ])
                                .animate()
                                .slideY(
                                    begin: 0.1, duration: 400.ms, delay: 200.ms)
                                .fadeIn(),
                            const Gap(16),
                            _SectionCard(
                              title: 'Package Items',
                              icon: Icons.list_alt_rounded,
                              headerTrailing: TextButton.icon(
                                icon: const Icon(Icons.add, size: 16),
                                label: const Text('Add Item'),
                                onPressed: () =>
                                    setState(() => _items.add(_ItemRow())),
                              ),
                              children: List.generate(
                                  _items.length,
                                  (i) => Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 12),
                                        child: _ItemRowWidget(
                                          row: _items[i],
                                          index: i + 1,
                                          showValidationErrors:
                                              _showValidationErrors,
                                          onRemove: _items.length > 1
                                              ? () => setState(
                                                  () => _items.removeAt(i))
                                              : null,
                                          onChanged: () => setState(() {}),
                                        ),
                                      )),
                            )
                                .animate()
                                .slideY(
                                    begin: 0.1, duration: 400.ms, delay: 300.ms)
                                .fadeIn(),
                            const Gap(16),
                            _SectionCard(
                              title: 'Office Notice',
                              icon: Icons.note_alt_rounded,
                              children: [
                                TextFormField(
                                  controller: _notesCtrl,
                                  decoration: _fieldDecoration(
                                      labelText: 'Officer Remarks / Notes'),
                                  maxLines: 3,
                                ),
                              ],
                            )
                                .animate()
                                .slideY(
                                    begin: 0.1, duration: 400.ms, delay: 350.ms)
                                .fadeIn(),
                            const Gap(24),
                            Row(
                              children: [
                                Expanded(
                                  child: SizedBox(
                                    height: 52,
                                    child: Tooltip(
                                      message: isOfficer
                                          ? 'Package entry/updates are restricted to administrators only'
                                          : '',
                                      child: ElevatedButton.icon(
                                        icon: _isChecking
                                            ? SizedBox(
                                                width: 18,
                                                height: 18,
                                                child:
                                                    CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                        color: Colors.white))
                                            : const Icon(
                                                Icons.flash_on_rounded),
                                        label: Text(_isChecking
                                            ? 'Processing...'
                                            : 'Next'),
                                        onPressed:
                                            _isChecking ? null : _checkPackage,
                                      ),
                                    ),
                                  ),
                                ),
                                const Gap(12),
                                OutlinedButton(
                                    onPressed: _reset,
                                    child: const Text('Reset')),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  _ResultPanel(
                      key: _resultPanelKey,
                      passed: _passed ?? true,
                      violations: _violations,
                      suggestedWarehouseId: _suggestedWarehouseId,
                      tempPackageData: _tempPackageData,
                      tempPackageItems: _tempPackageItems,
                      onPackageSaved: (pkg) {
                        setState(() {
                          _warehouseConfirmedPackage = pkg;
                        });
                        _tabController.animateTo(2);
                      },
                      onReset: _reset,
                  ),
                  _QrCodePage(
                      package: _warehouseConfirmedPackage,
                      onReset: _reset,
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

// ── Result Panel ───────────────────────────────────────────────

class _OneTapDatePicker extends StatefulWidget {
  final DateTime initialDate;
  final DateTime? lastDate;

  const _OneTapDatePicker({required this.initialDate, this.lastDate});

  @override
  State<_OneTapDatePicker> createState() => _OneTapDatePickerState();
}

class _OneTapDatePickerState extends State<_OneTapDatePicker> {
  late DateTime _visibleMonth;
  bool _textMode = false;
  final _textCtrl = TextEditingController();
  String? _textError;

  static const _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  static const _weekDays = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

  @override
  void initState() {
    super.initState();
    _visibleMonth = DateTime(widget.initialDate.year, widget.initialDate.month);
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  bool get _atLastMonth {
    final ld = widget.lastDate;
    return ld != null &&
        (_visibleMonth.year > ld.year ||
            (_visibleMonth.year == ld.year &&
                _visibleMonth.month >= ld.month));
  }

  void _tryApplyText() {
    final text = _textCtrl.text.trim();
    DateTime? parsed;
    for (final fmt in ['MM/dd/yyyy', 'yyyy-MM-dd', 'dd/MM/yyyy']) {
      try {
        parsed = DateFormat(fmt).parseStrict(text);
        break;
      } catch (_) {}
    }
    if (parsed == null) {
      setState(() => _textError = 'Use MM/DD/YYYY');
      return;
    }
    final d = DateTime(parsed.year, parsed.month, parsed.day);
    final ld = widget.lastDate;
    if (ld != null && d.isAfter(ld)) {
      setState(() => _textError = 'Date must be before today');
      return;
    }
    Navigator.pop(context, d);
  }

  @override
  Widget build(BuildContext context) {
    final firstDay = DateTime(_visibleMonth.year, _visibleMonth.month);
    final leadingEmpty = firstDay.weekday % 7;
    final dayCount = DateUtils.getDaysInMonth(_visibleMonth.year, _visibleMonth.month);
    final cellCount = ((leadingEmpty + dayCount + 6) ~/ 7) * 7;

    final dateLabel = DateFormat('EEE,').format(widget.initialDate);
    final monthDayLabel = DateFormat('MMM d').format(widget.initialDate);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: _textMode ? _buildTextMode(context) : _buildCalendar(context, leadingEmpty, dayCount, cellCount, dateLabel, monthDayLabel),
        ),
      ),
    );
  }

  Widget _buildTextMode(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Enter Date', style: Theme.of(context).textTheme.titleMedium),
        const Gap(16),
        TextField(
          controller: _textCtrl,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'MM/DD/YYYY',
            errorText: _textError,
            isDense: true,
          ),
          onSubmitted: (_) => _tryApplyText(),
        ),
        const Gap(20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              icon: const Icon(Icons.calendar_month_rounded),
              tooltip: 'Switch to calendar',
              onPressed: () => setState(() { _textMode = false; _textError = null; }),
            ),
            Row(children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              const Gap(8),
              ElevatedButton(onPressed: _tryApplyText, child: const Text('OK')),
            ]),
          ],
        ),
      ],
    );
  }

  Widget _buildCalendar(BuildContext context, int leadingEmpty, int dayCount, int cellCount, String dateLabel, String monthDayLabel) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Left panel ────────────────────────────────────────────────
        SizedBox(
          width: 120,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Select date',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: context.colors.textMuted,
                      letterSpacing: 0.5)),
              const Gap(12),
              Text(dateLabel,
                  style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: context.colors.textPrimary,
                      height: 1.1)),
              Text(monthDayLabel,
                  style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: context.colors.textPrimary,
                      height: 1.2)),
              const Gap(32),
              IconButton(
                icon: const Icon(Icons.edit_rounded, size: 18),
                tooltip: 'Enter date manually',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () {
                  _textCtrl.text = DateFormat('MM/dd/yyyy').format(widget.initialDate);
                  setState(() { _textMode = true; _textError = null; });
                },
              ),
            ],
          ),
        ),
        // ── Divider ───────────────────────────────────────────────────
        Container(
          width: 1,
          height: 260,
          margin: const EdgeInsets.symmetric(horizontal: 16),
          color: context.colors.borderColor,
        ),
        // ── Calendar ──────────────────────────────────────────────────
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Month header + nav
              Row(children: [
                Expanded(
                  child: Text(
                    '${_monthNames[_visibleMonth.month - 1]} ${_visibleMonth.year}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'Previous month',
                  icon: const Icon(Icons.chevron_left_rounded),
                  onPressed: () => setState(() =>
                      _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month - 1)),
                ),
                IconButton(
                  tooltip: 'Next month',
                  icon: Icon(Icons.chevron_right_rounded,
                      color: _atLastMonth ? Colors.grey.withOpacity(0.3) : null),
                  onPressed: _atLastMonth
                      ? null
                      : () => setState(() =>
                          _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + 1)),
                ),
              ]),
              const Gap(4),
              // Weekday headers
              Table(
                children: [
                  TableRow(
                    children: _weekDays
                        .map((d) => Center(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Text(d,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700, fontSize: 11)),
                              ),
                            ))
                        .toList(),
                  ),
                ],
              ),
              // Day grid — tap immediately selects (no OK button)
              Table(
                children: List.generate(cellCount ~/ 7, (row) {
                  return TableRow(
                    children: List.generate(7, (col) {
                      final day = row * 7 + col - leadingEmpty + 1;
                      if (day < 1 || day > dayCount) return const SizedBox(height: 36);
                      final date = DateTime(_visibleMonth.year, _visibleMonth.month, day);
                      final selected = DateUtils.isSameDay(date, widget.initialDate);
                      final isDisabled = widget.lastDate != null && date.isAfter(widget.lastDate!);
                      return Padding(
                        padding: const EdgeInsets.all(2),
                        child: GestureDetector(
                          onTap: isDisabled ? null : () => Navigator.pop(context, date),
                          child: Container(
                            height: 32,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: selected && !isDisabled
                                  ? context.colors.primaryGold
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '$day',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: selected && !isDisabled
                                    ? FontWeight.w800
                                    : FontWeight.w500,
                                color: isDisabled
                                    ? Colors.grey.withOpacity(0.3)
                                    : selected && !isDisabled
                                        ? Colors.black
                                        : null,
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  );
                }),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ResultPanel extends ConsumerStatefulWidget {
  final bool passed;
  final List<String> violations;
  final String? suggestedWarehouseId;
  final PackageModel? tempPackageData;
  final List<PackageItem>? tempPackageItems;
  final ValueChanged<PackageModel> onPackageSaved;
  final VoidCallback onReset;
  const _ResultPanel(
      {super.key,
      required this.passed,
      required this.violations,
      this.suggestedWarehouseId,
      this.tempPackageData,
      this.tempPackageItems,
      required this.onPackageSaved,
      required this.onReset});
  @override
  ConsumerState<_ResultPanel> createState() => _ResultPanelState();
}

class _ResultPanelState extends ConsumerState<_ResultPanel> {
  final Map<int, String?> _itemWarehouseSelections = {};
  bool _isSending = false;
  bool _warehouseSent = false;
  PackageModel? _savedPackage;

  @override
  void initState() {
    super.initState();
    _initializeSelections();
  }

  void _initializeSelections() {
    if (widget.tempPackageItems != null) {
      final cats = ref.read(packageCategoriesProvider).value;
      for (int i = 0; i < widget.tempPackageItems!.length; i++) {
        final item = widget.tempPackageItems![i];
        final cat = cats?.where((c) => c.name == item.category).firstOrNull;
        _itemWarehouseSelections[i] = cat?.targetWarehouseId;
      }
    }
  }

  @override
  void didUpdateWidget(_ResultPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.tempPackageItems != oldWidget.tempPackageItems) {
      _initializeSelections();
    }
  }

  String _formatWarehouseName(String name) {
    if (name.contains('GL1/SR/')) return name;
    String cleanName =
        name.replaceAll(RegExp(r'^SR\s+', caseSensitive: false), '');
    return 'GL1/SR/$cleanName';
  }

  Future<void> _sendToWarehouse() async {
    if (widget.tempPackageItems != null) {
      for (int i = 0; i < widget.tempPackageItems!.length; i++) {
        if (_itemWarehouseSelections[i] == null) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Please select a warehouse for Item ${i + 1}')));
          return;
        }
      }
    }

    if (widget.tempPackageData == null || widget.tempPackageItems == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Package data not found')));
      return;
    }

    setState(() => _isSending = true);
    try {
      // First save the package to database
      final saved = await ref.read(packageServiceProvider).upsertPackage(
            widget.tempPackageData!
                .copyWith(status: 'held'), // Set a general status
            widget.tempPackageItems!,
          );

      // Store the saved package for later use
      _savedPackage = saved;

      // Then add entries for EACH item to their respective warehouses
      final cats = ref.read(packageCategoriesProvider).value;
      final warehouseService = ref.read(warehouseServiceProvider);

      // Get existing entries to avoid duplicates on retry
      final existingEntries = await warehouseService.getAllWarehouseEntries();
      final pkgExistingEntries =
          existingEntries.where((e) => e.packageId == saved.id).toList();

      for (int i = 0; i < widget.tempPackageItems!.length; i++) {
        final tempItem = widget.tempPackageItems![i];

        // Use firstWhereOrNull to avoid "No element" error
        final item = saved.items
                .where((ci) =>
                    ci.itemName == tempItem.itemName &&
                    ci.quantity == tempItem.quantity)
                .firstOrNull ??
            (saved.items.length > i
                ? saved.items[i]
                : (saved.items.isNotEmpty ? saved.items.first : tempItem));

        // CHECK: If this item already has a warehouse entry, skip it to avoid duplicates
        final alreadySent =
            pkgExistingEntries.any((e) => e.packageItemId == item.id);
        if (alreadySent) continue;

        final warehouseId = _itemWarehouseSelections[i];
        final cat = cats?.where((c) => c.name == tempItem.category).firstOrNull;

        await warehouseService.addEntry(
          packageId: saved.id,
          packageItemId:
              item.id.isNotEmpty ? item.id : tempItem.id, // Fallback safely
          warehouseId: warehouseId!,
          zone: cat?.targetZone,
          holdReason: (tempItem.reasons != null && tempItem.reasons!.isNotEmpty)
              ? tempItem.reasons!
              : 'System Assigned',
          itemCount: tempItem.quantity,
        );
      }

      if (mounted) {
        setState(() => _warehouseSent = true);
        widget.onPackageSaved(saved);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text('✅ All items sent to respective warehouses'),
            backgroundColor: context.colors.successGreen));
      }
    } catch (e) {
      String userMessage = 'Error: $e';

      // Friendly error mapping
      final errStr = e.toString().toLowerCase();
      if (errStr.contains('socketexception') ||
          errStr.contains('timeout') ||
          errStr.contains('semaphore')) {
        userMessage =
            'Network Signal Error: Please check your internet connection and try again.';
      } else if (errStr.contains('clientexception')) {
        userMessage =
            'Connection Lost: Check your network signal and try again.';
      } else if (errStr.contains('null check operator')) {
        userMessage = 'Please ensure all items have a warehouse selected.';
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(userMessage),
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'RETRY',
              textColor: Colors.white,
              onPressed: _sendToWarehouse,
            ),
            backgroundColor: context.colors.dangerRed));
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final warehousesAsync = ref.watch(warehousesProvider);
    return Container(
      height: double.infinity,
      decoration: BoxDecoration(
          border: Border(left: BorderSide(color: context.colors.borderColor))),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Warehouse Confirmation',
                style: Theme.of(context).textTheme.titleLarge),
            const Gap(20),
            if (_warehouseSent)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: context.colors.successGreen.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: context.colors.successGreen.withOpacity(0.5),
                    width: 2,
                  ),
                ),
                child: Column(children: [
                  Icon(Icons.check_circle_rounded,
                          color: context.colors.successGreen, size: 56)
                      .animate()
                      .scale(duration: 400.ms),
                  const Gap(12),
                  Text(
                    'ENTRY SAVED SUCCESSFULLY',
                    style: TextStyle(
                      color: context.colors.successGreen,
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                    ),
                    textAlign: TextAlign.center,
                  )
                      .animate()
                      .slideY(begin: 0.3, duration: 300.ms, delay: 200.ms),
                  const Gap(20),
                  if (_savedPackage != null)
                    Column(
                      children: [
                        ElevatedButton.icon(
                          onPressed: () => showDialog(
                            context: context,
                            builder: (_) => PrintBarcodeDialog(
                              packages: [_savedPackage!],
                              onPrinted: widget.onReset,
                            ),
                          ),
                          icon: const Icon(Icons.print_rounded),
                          label: const Text('Print QR Code Label'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: context.colors.primaryGold,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                ]),
              )
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: context.colors.primaryGold.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: context.colors.primaryGold.withOpacity(0.5),
                    width: 2,
                  ),
                ),
                child: Column(children: [
                  Icon(Icons.warehouse_rounded,
                          color: context.colors.primaryGold, size: 56)
                      .animate()
                      .scale(duration: 400.ms),
                  const Gap(12),
                  Text(
                    'WAREHOUSE ALLOCATION',
                    style: TextStyle(
                      color: context.colors.primaryGold,
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                    ),
                    textAlign: TextAlign.center,
                  )
                      .animate()
                      .slideY(begin: 0.3, duration: 300.ms, delay: 200.ms),
                  const Gap(8),
                  Text('Assign each item to its destination warehouse.',
                      style: TextStyle(
                          color: context.colors.textSecondary, fontSize: 13),
                      textAlign: TextAlign.center),
                ]),
              ),
            const Gap(24),
            if (widget.tempPackageItems != null && !_warehouseSent) ...[
              Text('Items Distribution',
                  style: Theme.of(context).textTheme.titleMedium),
              const Gap(12),
              ...List.generate(widget.tempPackageItems!.length, (index) {
                final item = widget.tempPackageItems![index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: context.colors.cardDark,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: context.colors.borderColor),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color:
                                    context.colors.primaryGold.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text('Item ${index + 1}',
                                  style: TextStyle(
                                      color: context.colors.primaryGold,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11)),
                            ),
                            const Gap(8),
                            Expanded(
                                child: Text(item.itemName,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600))),
                          ],
                        ),
                        if (item.reasons != null && item.reasons!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Row(
                              children: [
                                Icon(Icons.warning_amber_rounded,
                                    size: 12, color: context.colors.heldOrange),
                                const Gap(6),
                                Expanded(
                                  child: Text('Reasons: ${item.reasons}',
                                      style: TextStyle(
                                          color: context.colors.textMuted,
                                          fontSize: 11,
                                          fontStyle: FontStyle.italic)),
                                ),
                              ],
                            ),
                          ),
                        const Gap(12),
                        warehousesAsync.when(
                          loading: () => const LinearProgressIndicator(),
                          error: (e, _) => Text('Error loading warehouses'),
                          data: (ws) => Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: ws.map((w) {
                              final isSelected =
                                  _itemWarehouseSelections[index] == w.id;
                              final hasAutoSelection =
                                  _itemWarehouseSelections[index] != null;

                              return InkWell(
                                onTap: (hasAutoSelection && !isSelected)
                                    ? null
                                    : () => setState(() =>
                                        _itemWarehouseSelections[index] = w.id),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? context.colors.primaryGold
                                            .withOpacity(0.15)
                                        : (hasAutoSelection
                                            ? context.colors.surfaceDark
                                                .withOpacity(0.5)
                                            : context.colors.surfaceDark),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: isSelected
                                          ? context.colors.primaryGold
                                          : context.colors.borderColor,
                                      width: isSelected ? 1.5 : 1,
                                    ),
                                  ),
                                  child: Text(
                                    _formatWarehouseName(w.name)
                                        .replaceFirst('GL1/SR/', ''),
                                    style: TextStyle(
                                      color: isSelected
                                          ? context.colors.primaryGold
                                          : (hasAutoSelection
                                              ? context.colors.textSecondary
                                                  .withOpacity(0.3)
                                              : context.colors.textSecondary),
                                      fontSize: 12,
                                      fontWeight: isSelected
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
            const Gap(20),
            if (!_warehouseSent)
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: context.colors.heldOrange,
                      foregroundColor: Colors.white),
                  icon: _isSending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.send_rounded),
                  label: Text(_isSending
                      ? 'Saving Entries...'
                      : 'Complete & Send to Warehouses'),
                  onPressed: _isSending ? null : _sendToWarehouse,
                ),
              ),
            if (_warehouseSent)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.add_box_rounded, size: 18),
                  label: const Text('New SR Entry'),
                  onPressed: widget.onReset,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Helper Widgets ───

class _QrCodePage extends StatelessWidget {
  final PackageModel? package;
  final VoidCallback onReset;

  const _QrCodePage({
    required this.package,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('QR Code Generate', style: Theme.of(context).textTheme.titleLarge),
          const Gap(20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: context.colors.cardDark,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: context.colors.borderColor),
            ),
            child: Column(
              children: [
                Icon(Icons.qr_code_2_rounded,
                    color: context.colors.primaryGold, size: 72),
                const Gap(14),
                Text(
                  package == null
                      ? 'WAREHOUSE CONFIRMATION REQUIRED'
                      : 'QR CODE READY',
                  style: TextStyle(
                    color: context.colors.primaryGold,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                  textAlign: TextAlign.center,
                ),
                const Gap(8),
                Text(
                  package == null
                      ? 'Complete warehouse confirmation before generating labels.'
                      : 'Generate and print QR code labels for ${package!.srNumber}.',
                  style: TextStyle(
                      color: context.colors.textSecondary, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
                const Gap(24),
                if (package != null)
                  ElevatedButton.icon(
                    onPressed: () => showDialog(
                      context: context,
                      builder: (_) => PrintBarcodeDialog(
                        packages: [package!],
                        onPrinted: onReset,
                      ),
                    ),
                    icon: const Icon(Icons.print_rounded),
                    label: const Text('Print QR Code Label'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.colors.primaryGold,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 14,
                      ),
                    ),
                  ),
                if (package != null) ...[
                  const Gap(12),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.add_box_rounded, size: 18),
                    label: const Text('New SR Entry'),
                    onPressed: onReset,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemRow {
  String? itemId;
  final nameCtrl = TextEditingController();
  final goodsDescriptionCtrl = TextEditingController();
  final qtyCtrl = TextEditingController(text: '1');
  final unitOfMeasureCtrl = TextEditingController(text: 'Pieces');
  final unitOtherCtrl = TextEditingController();
  final valueCtrl = TextEditingController(text: '0');
  final categoryCtrl = TextEditingController();
  String status = 'Detain';
  final otherStatusCtrl = TextEditingController();
  final List<String?> selectedReasons = [null]; // Start with 1 mandatory reason
}

class _ItemRowWidget extends ConsumerStatefulWidget {
  final _ItemRow row;
  final int index;
  final bool showValidationErrors;
  final VoidCallback? onRemove;
  final VoidCallback onChanged;
  const _ItemRowWidget(
      {required this.row,
      required this.index,
      required this.showValidationErrors,
      this.onRemove,
      required this.onChanged});
  @override
  ConsumerState<_ItemRowWidget> createState() => _ItemRowWidgetState();
}

class _ItemRowWidgetState extends ConsumerState<_ItemRowWidget> {
  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(packageCategoriesProvider);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: context.colors.surfaceDark,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.colors.borderColor),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 4,
                offset: const Offset(0, 2))
          ]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                  color: context.colors.primaryGold.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(6)),
              child: Text('Item ${widget.index}',
                  style: TextStyle(
                      color: context.colors.primaryGold,
                      fontWeight: FontWeight.w700,
                      fontSize: 12))),
          const Spacer(),
          if (widget.onRemove != null)
            IconButton(
                icon: Icon(Icons.delete_outline_rounded,
                    size: 20, color: context.colors.dangerRed),
                onPressed: widget.onRemove,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: 'Remove item'),
        ]),
        const Gap(12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: TextFormField(
                  controller: widget.row.nameCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Item Name *', isDense: true, helperText: ' '),
                  validator: (v) => widget.showValidationErrors &&
                          (v == null || v.trim().isEmpty)
                      ? 'Required'
                      : null,
                  onChanged: (_) => widget.onChanged()),
            ),
            const Gap(12),
            Expanded(
              flex: 1,
              child: TextFormField(
                controller: widget.row.qtyCtrl,
                decoration: const InputDecoration(
                    labelText: 'Pkgs *', isDense: true, helperText: ' '),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: (v) {
                  if (!widget.showValidationErrors) return null;
                  if (v == null || v.trim().isEmpty) return 'Req';
                  if (int.tryParse(v) == null || int.tryParse(v)! <= 0)
                    return 'Err';
                  return null;
                },
                onChanged: (_) => widget.onChanged(),
              ),
            ),
            const Gap(10),
            Expanded(
              flex: 2,
              child: DropdownButtonFormField<String>(
                isDense: true,
                isExpanded: true,
                value: [
                  'Pieces',
                  'Cartons',
                  'Boxes',
                  'Bags',
                  'Pallets',
                  'KG',
                  'Meters',
                  'Other'
                ].contains(widget.row.unitOfMeasureCtrl.text)
                    ? widget.row.unitOfMeasureCtrl.text
                    : 'Pieces',
                decoration: const InputDecoration(
                    labelText: 'Unit *', isDense: true, helperText: ' '),
                items: [
                  'Pieces',
                  'Cartons',
                  'Boxes',
                  'Bags',
                  'Pallets',
                  'KG',
                  'Meters',
                  'Other'
                ]
                    .map((u) => DropdownMenuItem(
                        value: u,
                        child: Text(u,
                            style: const TextStyle(fontSize: 12),
                            overflow: TextOverflow.ellipsis)))
                    .toList(),
                onChanged: (v) {
                  setState(() {
                    widget.row.unitOfMeasureCtrl.text = v ?? 'Pieces';
                  });
                  widget.onChanged();
                },
              ),
            ),
            if (widget.row.unitOfMeasureCtrl.text == 'Other') ...[
              const Gap(8),
              Expanded(
                flex: 2,
                child: TextFormField(
                  controller: widget.row.unitOtherCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Name *', isDense: true, helperText: ' '),
                  validator: (v) => widget.showValidationErrors &&
                          widget.row.unitOfMeasureCtrl.text == 'Other' &&
                          (v == null || v.trim().isEmpty)
                      ? 'Req'
                      : null,
                  onChanged: (_) => widget.onChanged(),
                ),
              ),
            ],
            const Gap(10),
            Expanded(
              flex: 2,
              child: DropdownButtonFormField<String>(
                isDense: true,
                isExpanded: true,
                value: ['Detain', 'Forfeit', 'Abandoned', 'Other']
                        .contains(widget.row.status)
                    ? widget.row.status
                    : 'Other',
                decoration: const InputDecoration(
                    labelText: 'Status *', isDense: true, helperText: ' '),
                items: ['Detain', 'Forfeit', 'Abandoned', 'Other']
                    .map((s) => DropdownMenuItem(
                        value: s,
                        child: Text(s,
                            style: const TextStyle(fontSize: 12),
                            overflow: TextOverflow.ellipsis)))
                    .toList(),
                onChanged: (v) {
                  setState(() => widget.row.status = v!);
                  widget.onChanged();
                },
              ),
            ),
            if (widget.row.status == 'Other') ...[
              const Gap(10),
              Expanded(
                flex: 2,
                child: TextFormField(
                  controller: widget.row.otherStatusCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Other Status *',
                    isDense: true,
                    helperText: ' ',
                  ),
                  validator: (v) => widget.showValidationErrors &&
                          widget.row.status == 'Other' &&
                          (v == null || v.trim().isEmpty)
                      ? 'Required'
                      : null,
                  onChanged: (_) => widget.onChanged(),
                ),
              ),
            ],
            const Gap(10),
            Expanded(
              flex: 2,
              child: categories.when(
                loading: () => const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                error: (e, _) => IconButton(
                    icon: const Icon(Icons.refresh,
                        size: 16, color: Colors.orange),
                    onPressed: () => ref.refresh(packageCategoriesProvider),
                    tooltip: 'Error loading categories'),
                data: (list) {
                  final selectedCategory = list
                      .where((c) => c.name == widget.row.categoryCtrl.text)
                      .firstOrNull;
                  return DropdownButtonFormField<String>(
                    isDense: true,
                    isExpanded: true,
                    value: selectedCategory?.name,
                    decoration: const InputDecoration(
                        labelText: 'Category', isDense: true, helperText: ' '),
                    items: list
                        .map((c) => DropdownMenuItem(
                            value: c.name,
                            child: Text(c.name,
                                style: const TextStyle(fontSize: 12),
                                overflow: TextOverflow.ellipsis)))
                        .toList(),
                    onChanged: (v) {
                      widget.row.categoryCtrl.text = v ?? '';
                      setState(() {});
                      widget.onChanged();
                    },
                  );
                },
              ),
            ),
          ],
        ),
        const Gap(12),
        Row(children: [
          categories.when(
              data: (list) {
                final cat = list
                    .where((c) => c.name == widget.row.categoryCtrl.text)
                    .firstOrNull;
                if (cat != null && cat.targetWarehouseId != null) {
                  return Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                        color: context.colors.primaryGold.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color:
                                context.colors.primaryGold.withOpacity(0.3))),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.route_rounded,
                          size: 14, color: context.colors.primaryGold),
                      const Gap(6),
                      Text(
                          _formatWarehouseName(cat.targetWarehouseName ??
                                  cat.targetWarehouseId ??
                                  '') +
                              (cat.targetZone != null
                                  ? ' | Zone ${cat.targetZone}'
                                  : ''),
                          style: TextStyle(
                              color: context.colors.primaryGold,
                              fontSize: 11,
                              fontWeight: FontWeight.w600))
                    ]),
                  );
                }
                return const SizedBox.shrink();
              },
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink()),
        ]),
        const Gap(16),
        // ── Reasons Section ──
        Row(
          children: [
            Icon(Icons.warning_amber_rounded,
                size: 18, color: context.colors.heldOrange),
            const Gap(8),
            Text('Hold Reasons',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: context.colors.textPrimary)),
            const Spacer(),
            if (widget.row.selectedReasons.length < 4)
              TextButton.icon(
                onPressed: () {
                  setState(() => widget.row.selectedReasons.add(null));
                  widget.onChanged();
                },
                icon: const Icon(Icons.add_circle_outline, size: 16),
                label: const Text('Add Reason',
                    style:
                        TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                style: TextButton.styleFrom(
                  foregroundColor: context.colors.primaryGold,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  backgroundColor: context.colors.primaryGold.withOpacity(0.1),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
          ],
        ),
        const Gap(12),
        Wrap(
          spacing: 12,
          runSpacing: 10,
          children: List.generate(widget.row.selectedReasons.length, (rIdx) {
            return SizedBox(
              width: 380,
              child: Row(
                children: [
                  Expanded(
                    child: ref.watch(holdReasonsProvider).when(
                          loading: () => const LinearProgressIndicator(),
                          error: (e, _) => Text('Error loading reasons',
                              style: TextStyle(
                                  color: context.colors.dangerRed,
                                  fontSize: 11)),
                          data: (reasons) => DropdownButtonFormField<String>(
                            isDense: true,
                            isExpanded: true,
                            value: widget.row.selectedReasons[rIdx],
                            decoration: InputDecoration(
                              labelText: 'Reason ${rIdx + 1} *',
                              labelStyle: const TextStyle(fontSize: 12),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 12),
                              filled: true,
                              fillColor: context.colors.cardDark,
                              helperText: ' ',
                            ),
                            validator: (v) =>
                                widget.showValidationErrors && v == null
                                    ? 'Required'
                                    : null,
                            items: reasons.map((r) {
                              final isSelectedSomewhereElse = widget
                                  .row.selectedReasons
                                  .any((res) => res == r.reasonText);
                              final isCurrentSelection =
                                  widget.row.selectedReasons[rIdx] ==
                                      r.reasonText;

                              return DropdownMenuItem(
                                value: r.reasonText,
                                enabled: !isSelectedSomewhereElse ||
                                    isCurrentSelection,
                                child: Text(
                                  r.reasonText,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: (isSelectedSomewhereElse &&
                                            !isCurrentSelection)
                                        ? context.colors.textMuted
                                        : context.colors.textPrimary,
                                    decoration: (isSelectedSomewhereElse &&
                                            !isCurrentSelection)
                                        ? TextDecoration.lineThrough
                                        : null,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            }).toList(),
                            onChanged: (v) {
                              setState(
                                  () => widget.row.selectedReasons[rIdx] = v);
                              widget.onChanged();
                            },
                          ),
                        ),
                  ),
                  if (widget.row.selectedReasons.length > 1)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: IconButton(
                        icon: const Icon(Icons.remove_circle_outline,
                            size: 20, color: Colors.grey),
                        onPressed: () {
                          setState(
                              () => widget.row.selectedReasons.removeAt(rIdx));
                          widget.onChanged();
                        },
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: 'Remove reason',
                      ),
                    ),
                ],
              ),
            );
          }),
        ),
        const Gap(12),
        TextFormField(
          controller: widget.row.goodsDescriptionCtrl,
          decoration: const InputDecoration(
            labelText: 'Goods Description',
            isDense: true,
            helperText: ' ',
          ),
          maxLines: 2,
          onChanged: (_) => widget.onChanged(),
        ),
      ]),
    );
  }

  String _formatWarehouseName(String name) {
    if (name.isEmpty) return '';
    // If it already has the prefix, don't add it again
    if (name.contains('GL1/SR/')) return name;

    // Convert "SR Warehouse 02" or similar to "Warehouse 02"
    String cleanName =
        name.replaceAll(RegExp(r'^SR\s+', caseSensitive: false), '');
    return 'GL1/SR/$cleanName';
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;
  final Widget? headerTrailing;
  const _SectionCard(
      {required this.title,
      required this.icon,
      required this.children,
      this.headerTrailing});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: context.colors.cardDark,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.colors.borderColor)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: context.colors.primaryGold, size: 18),
          const Gap(10),
          Text(title,
              style: TextStyle(
                  color: context.colors.primaryGold,
                  fontWeight: FontWeight.w700,
                  fontSize: 14)),
          const Spacer(),
          if (headerTrailing != null) headerTrailing!,
        ]),
        const Gap(16),
        ...children,
      ]),
    );
  }
}
