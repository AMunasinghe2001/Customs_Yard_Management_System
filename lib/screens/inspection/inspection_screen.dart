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
import '../../widgets/styled_form_dialog.dart';
import '../../core/yards.dart';
import '../../core/directorates.dart';
import '../../core/post_status_activities.dart';
import '../../core/app_session.dart';
import '../../services/services.dart';
import '../../models/models.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/error_view.dart';
import '../../widgets/custom_dropdown.dart';
import '../../widgets/styled_dropdown.dart';
import '../../widgets/one_tap_date_picker.dart';
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
  // Registration mode: 'new' = a fresh SR entry (default), 'old' = migrating a
  // legacy package — captures its previous SR number in [_oldSrNumberCtrl].
  String _entryMode = 'new';
  final _oldSrNumberCtrl = TextEditingController();
  // Yard this SR is being registered under. Defaults to the signed-in user's
  // yard; the prefix of the generated SR number follows this selection.
  // Normalised through yardByCode so it always matches a dropdown item.
  String _selectedYard = yardByCode(AppSession.currentYard).code;
  /// Which register this number is minted from -- SR or OA. Each keeps
  /// its own serial run, so switching this re-mints the number rather
  /// than continuing the other register's count.
  String _srDocType = kDefaultSrDocType;
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

  /// Deposit lodged against the cost of destroying the goods. One figure
  /// per SR (package-level), not per goods item.
  final _destroyingDepositCtrl = TextEditingController();
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
  // The SR number that was loaded for editing (via the search). Edit mode only
  // applies while the SR field still matches this — change the SR and it's a
  // new entry again (so the duplicate-SR guard re-applies).
  String? _loadedSrNumber;
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
        setState(() {
          _isUpdate = false;
          _loadedSrNumber = null;
        });
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
      _destroyingDepositCtrl.text = pkg.destroyingDeposit?.toString() ?? '';
      _reasonCtrlMain.text = pkg.reason ?? '';
      _notesCtrl.text = pkg.notes ?? '';
      _oldSrNumberCtrl.text = pkg.oldSrNumber ?? '';
      setState(() {
        // Follow the loaded number's own register, so editing an OA package
        // does not show "SR" beside an OA number.
        _srDocType = docTypeOfSrNumber(pkg.srNumber) ?? _srDocType;
        _entryMode = (pkg.oldSrNumber != null && pkg.oldSrNumber!.isNotEmpty)
            ? 'old'
            : 'new';
        _statusValue = (pkg.status == 'detained' || pkg.status == 'forfeited')
            ? 'held'
            : pkg.status;
        _isUpdate = true;
        _loadedSrNumber = sr;
        _items.clear();
        if (pkg.items != null && pkg.items!.isNotEmpty) {
          for (final item in pkg.items!) {
            final row = _ItemRow();
            row.itemId = item.id;
            row.nameCtrl.text = item.itemName;
            row.goodsDescriptionCtrl.text = item.goodsDescription ?? '';
            // Reconstruct the form from the inverted Cartons storage: a packaged
            // item keeps 'Cartons' + carton count in innerUnit/innerQuantity and
            // the inner contents in quantity/unitOfMeasure.
            if (item.innerUnit == 'Cartons' && item.innerQuantity != null) {
              row.unitOfMeasureCtrl.text = 'Cartons';
              row.qtyCtrl.text = (item.innerQuantity ?? 1).toString();
              row.innerUnitCtrl.text = item.unitOfMeasure;
              row.innerQtyCtrl.text = item.quantity.toString();
            } else {
              row.qtyCtrl.text = item.quantity.toString();
              row.unitOfMeasureCtrl.text = item.unitOfMeasure;
              if (item.unitOfMeasure == 'Other') {
                row.unitOtherCtrl.text = item.unitOther ?? '';
              }
            }
            row.valueCtrl.text = item.unitValue.toString();
            row.hsCodeCtrl.text = item.hsCode ?? '';
            row.categoryCtrl.text = item.category ?? '';
            const statuses = ['Detain', 'Forfeit', 'Abandoned', 'Other'];
            final rawStatus = item.status;
            // "Other: <text>" marker (current) or any non-standard free text
            // (legacy) → restore as Other with the custom text in its field.
            if (rawStatus.toLowerCase().startsWith('other:')) {
              row.status = 'Other';
              row.otherStatusCtrl.text = rawStatus.substring(6).trim();
            } else if (statuses.contains(rawStatus)) {
              row.status = rawStatus;
              row.otherStatusCtrl.clear();
            } else {
              row.status = 'Other';
              row.otherStatusCtrl.text = rawStatus;
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
          OneTapDatePicker(initialDate: initial, lastDate: lastDate),
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
    // While a Next/save is in flight, don't bounce the tab back — _checkPackage
    // / the save will set the required state and move to the right tab itself.
    // Otherwise tapping the Warehouse tab (which kicks off _checkPackage) would
    // race: the tab index changes to 1 before _checkPackage finishes, this
    // guard sees canGoToWarehouse still false, and bounces to 0 — forcing a
    // second click.
    if (_isChecking) return;
    final idx = _tabController.index;
    final canGoToWarehouse =
        _tempPackageData != null && _tempPackageItems != null;
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
      final sr = await ref
          .read(packageServiceProvider)
          .getNextSrNumber(yard: _selectedYard, docType: _srDocType);
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
    _oldSrNumberCtrl.dispose();
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
    _destroyingDepositCtrl.dispose();
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
    // Duplicate-SR guard: reject an SR that already exists UNLESS we're editing
    // exactly that SR (loaded via the search). This blocks both a fresh new
    // entry AND the case where someone loads SR-A then retypes it to an existing
    // SR-B — so we never create two packages under one SR or silently clobber
    // another package.
    final sr = _srNumberCtrl.text.trim();
    if (_entryMode == 'old' && _oldSrNumberCtrl.text.trim().isEmpty) {
      setState(() => _showValidationErrors = true);
      context.showError('Old SR number is required for an Old Entry.');
      return;
    }
    final isEditingThisSr = _isUpdate && _loadedSrNumber == sr;
    if (!isEditingThisSr) {
      try {
        final existing =
            await ref.read(packageServiceProvider).getPackageBySrNumber(sr);
        if (!mounted) return;
        if (existing != null) {
          context.showError(
              'A package with SR "$sr" already exists. Use the search to edit it.');
          return;
        }
      } catch (_) {
        // Lookup failure shouldn't block registration; fall through to save.
      }
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
                // Cartons are stored "inverted": the operational quantity/unit
                // become the INNER contents (e.g. 1176 Pieces), and the outer
                // packaging (20 Cartons) is kept in innerUnit/innerQuantity.
                quantity: r.unitOfMeasureCtrl.text == 'Cartons'
                    ? (int.tryParse(r.innerQtyCtrl.text) ?? 1)
                    : (int.tryParse(r.qtyCtrl.text) ?? 1),
                unitOfMeasure: r.unitOfMeasureCtrl.text == 'Cartons'
                    ? r.innerUnitCtrl.text
                    : r.unitOfMeasureCtrl.text,
                unitOther: r.unitOfMeasureCtrl.text == 'Other'
                    ? r.unitOtherCtrl.text
                    : null,
                innerUnit: r.unitOfMeasureCtrl.text == 'Cartons'
                    ? r.unitOfMeasureCtrl.text // 'Cartons' (packaging unit)
                    : null,
                innerQuantity: r.unitOfMeasureCtrl.text == 'Cartons'
                    ? (int.tryParse(r.qtyCtrl.text) ?? 1) // carton count
                    : null,
                unitValue: double.tryParse(r.valueCtrl.text) ?? 0,
                hsCode: r.hsCodeCtrl.text.trim().isEmpty
                    ? null
                    : r.hsCodeCtrl.text.trim(),
                category: r.categoryCtrl.text,
                // "Other" disposition: store with an explicit marker prefix
                // ("Other: <custom text>") so it is unambiguously detectable as
                // an Other-status held package (the custom text alone could
                // collide with any word). Detection/label code strips the prefix.
                status: r.status == 'Other'
                    ? 'Other: ${r.otherStatusCtrl.text.trim()}'
                    : r.status,
                reasons:
                    r.selectedReasons.where((res) => res != null).join(', '),
              ))
          .toList();

      final pkg = PackageModel(
        id: '',
        srNumber: _srNumberCtrl.text.trim(),
        // Old Entry mode: keep the legacy SR number; NULL for new entries.
        oldSrNumber:
            _entryMode == 'old' && _oldSrNumberCtrl.text.trim().isNotEmpty
                ? _oldSrNumberCtrl.text.trim()
                : null,
        originCountry: _originCtrl.text.trim(),
        declaredValue: double.tryParse(_valueCtrl.text) ?? 0,
        weightKg: double.tryParse(_weightCtrl.text) ?? 0,
        totalItemCount: items.fold(0, (sum, i) => sum + i.effectiveQuantity),
        description: _descCtrl.text,
        containerNumber: _containerNumberCtrl.text.trim().isEmpty
            ? null
            : _containerNumberCtrl.text.trim(),
        destroyingDeposit: double.tryParse(_destroyingDepositCtrl.text.trim()),
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
    _oldSrNumberCtrl.clear();
    _srDocType = kDefaultSrDocType;
    _entryMode = 'new';
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
    _destroyingDepositCtrl.clear();
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
      // Fresh form — don't show validation errors until the user tries to
      // submit again (they linger as red "Required" from the previous entry).
      _showValidationErrors = false;
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
                    Text('Goods Registration',
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
            )
                .animate()
                .slideY(begin: 0.1, duration: 400.ms, delay: 100.ms)
                .fadeIn(),
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
                                // ── Registration type: New Entry / Old Entry ──
                                StyledDropdownFormField<String>(
                                  label: 'Registration Type',
                                  menuWidth: 260,
                                  // Match the roomier (non-dense) section
                                  // fields below (Old SR Number / SR Number).
                                  isDense: false,
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 16),
                                  valueStyle: TextStyle(
                                      fontSize: 16,
                                      color: context.colors.textPrimary),
                                  labelStyle: const TextStyle(fontSize: 14),
                                  value: _entryMode,
                                  options: const [
                                    StyledDropdownOption('new', 'New Entry'),
                                    StyledDropdownOption('old', 'Old Entry'),
                                  ],
                                  onChanged: (v) =>
                                      setState(() => _entryMode = v ?? 'new'),
                                ),
                                const Gap(12),
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
                                              color: context.colors.primaryGold,
                                              fontSize: 13)),
                                    ]),
                                  ),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      flex: 1,
                                      // Locked to the signed-in user's own
                                      // yard — every role (admins included) is
                                      // scoped to a single yard, so the yard
                                      // is shown for context but not editable.
                                      child: TextFormField(
                                        initialValue:
                                            yardByCode(AppSession.currentYard)
                                                .name,
                                        readOnly: true,
                                        enabled: false,
                                        style: TextStyle(
                                            color: context.colors.textPrimary),
                                        decoration: _fieldDecoration(
                                          // Names the directorate too: it is
                                          // what puts the prefix on the SR
                                          // number beside this field, and a
                                          // yard under two directorates would
                                          // otherwise give no clue which one
                                          // this account writes under.
                                          labelText:
                                              AppSession.currentDirectorate ==
                                                      null
                                                  ? 'Yard'
                                                  : 'Yard · '
                                                      '${directorateSrPrefix(AppSession.currentDirectorate)}',
                                        ).copyWith(
                                          fillColor:
                                              Theme.of(context).brightness ==
                                                      Brightness.dark
                                                  ? Colors.grey.shade900
                                                  : Colors.grey.shade100,
                                          filled: true,
                                        ),
                                      ),
                                    ),
                                    const Gap(12),
                                    // Which register the number comes from.
                                    // SR and OA run INDEPENDENT serials, so
                                    // changing this re-mints the number from
                                    // that register's own count instead of
                                    // continuing the other one's.
                                    SizedBox(
                                      width: 108,
                                      child: StyledDropdownFormField<String>(
                                        label: 'Register',
                                        menuWidth: 140,
                                        isDense: false,
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                                horizontal: 12, vertical: 16),
                                        valueStyle: TextStyle(
                                            fontSize: 16,
                                            color: context.colors.textPrimary),
                                        labelStyle:
                                            const TextStyle(fontSize: 14),
                                        value: _srDocType,
                                        options: [
                                          for (final t in kSrDocTypes)
                                            StyledDropdownOption(t, t),
                                        ],
                                        onChanged: (v) {
                                          // Editing an existing package must
                                          // not re-mint its number.
                                          if (_isUpdate ||
                                              v == null ||
                                              v == _srDocType) {
                                            return;
                                          }
                                          setState(() => _srDocType = v);
                                          _generateNextSr();
                                        },
                                      ),
                                    ),
                                    const Gap(12),
                                    Expanded(
                                      flex: 2,
                                      child: TextFormField(
                                        controller: _srNumberCtrl,
                                        inputFormatters: [
                                          FilteringTextInputFormatter.allow(
                                              RegExp(r'[a-zA-Z0-9/ ]')),
                                          LengthLimitingTextInputFormatter(30),
                                        ],
                                        decoration: _fieldDecoration(
                                          labelText: 'SR Number *',
                                          hintText:
                                              'e.g. GL1/SR/01/2025 or GL1/OA/01/2025',
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
                                                          ? context
                                                              .colors.textMuted
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
                                      child: _CusdecAutocompleteField(
                                          controller: _cusdecCtrl,
                                          decoration: _fieldDecoration(
                                              labelText: 'Cusdec No *'),
                                          validator: _requiredValidator)),
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
                                              type: MaskAutoCompletionType.lazy,
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
                                          controller: _entryDateCtrl,
                                          readOnly: true,
                                          onTap: () => _selectDate(
                                              _entryDateCtrl,
                                              lastDate: DateTime.now()),
                                          inputFormatters: [
                                            MaskTextInputFormatter(
                                              mask: '####-##-##',
                                              filter: {"#": RegExp(r'[0-9]')},
                                              type: MaskAutoCompletionType.lazy,
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
                                // Old SR Number (Old Entry only) + Container
                                // Number — half width each so the row is filled
                                // and neither field runs full-width.
                                Row(children: [
                                  if (_entryMode == 'old') ...[
                                    Expanded(
                                      child: TextFormField(
                                        controller: _oldSrNumberCtrl,
                                        autovalidateMode:
                                            AutovalidateMode.onUserInteraction,
                                        inputFormatters: [
                                          FilteringTextInputFormatter.allow(
                                              RegExp(r'[a-zA-Z0-9/ ]')),
                                          LengthLimitingTextInputFormatter(30),
                                        ],
                                        style: TextStyle(
                                            color: context.colors.textPrimary),
                                        decoration: _fieldDecoration(
                                          labelText: 'Old SR Number *',
                                          hintText: 'Previous register SR',
                                        ),
                                        validator: (v) => _entryMode == 'old' &&
                                                (v == null || v.trim().isEmpty)
                                            ? 'Old SR number is required'
                                            : null,
                                      ),
                                    ),
                                    const Gap(12),
                                  ],
                                  Expanded(
                                    child: TextFormField(
                                      controller: _containerNumberCtrl,
                                      decoration: _fieldDecoration(
                                        labelText: 'Container Number',
                                      ),
                                      textCapitalization:
                                          TextCapitalization.characters,
                                    ),
                                  ),
                                  const Gap(12),
                                  Expanded(
                                    child: TextFormField(
                                      controller: _destroyingDepositCtrl,
                                      decoration: _fieldDecoration(
                                        labelText: 'Destroying Deposit (LKR)',
                                      ),
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                              decimal: true),
                                      inputFormatters: [
                                        FilteringTextInputFormatter.allow(
                                            RegExp(r'[0-9.]')),
                                      ],
                                      validator: (v) {
                                        final t = (v ?? '').trim();
                                        if (t.isEmpty) return null; // optional
                                        final d = double.tryParse(t);
                                        if (d == null) return 'Enter a number';
                                        if (d < 0) return 'Cannot be negative';
                                        return null;
                                      },
                                    ),
                                  ),
                                ]),
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
                                              labelText: 'Declarant Address'))),
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
                            title: 'Package Goods',
                            icon: Icons.list_alt_rounded,
                            children: [
                              ...List.generate(
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
                              // Add Item below the list so registering a new
                              // item needs no scroll back to the top; no item
                              // count limit.
                              const Gap(4),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: OutlinedButton.icon(
                                  icon: const Icon(Icons.add_rounded, size: 18),
                                  label: const Text('Add Goods'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: context.colors.primaryGold,
                                    side: BorderSide(
                                        color: context.colors.primaryGold
                                            .withOpacity(0.5)),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 20, vertical: 14),
                                  ),
                                  onPressed: () =>
                                      setState(() => _items.add(_ItemRow())),
                                ),
                              ),
                            ],
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
                                              child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: Colors.white))
                                          : const Icon(Icons.flash_on_rounded),
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
                    yard: _selectedYard,
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

class _ResultPanel extends ConsumerStatefulWidget {
  final bool passed;
  final List<String> violations;
  final String? suggestedWarehouseId;
  final String yard;
  final PackageModel? tempPackageData;
  final List<PackageItem>? tempPackageItems;
  final ValueChanged<PackageModel> onPackageSaved;
  final VoidCallback onReset;
  const _ResultPanel(
      {super.key,
      required this.passed,
      required this.violations,
      this.suggestedWarehouseId,
      required this.yard,
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

  /// Zones this consignment would overfill, as ready-to-show problems.
  ///
  /// Items are grouped by the zone they would land in, because several goods
  /// of one SR can share a zone — checking them one at a time would let a
  /// consignment slip past that its total does not fit.
  Future<List<_CapacityProblem>> _findCapacityProblems() async {
    final items = widget.tempPackageItems;
    if (items == null || items.isEmpty) return const [];

    final occupancy = await ref.read(zoneOccupancyProvider.future);
    final zones = await ref.read(warehouseZonesProvider.future);
    final cats = ref.read(packageCategoriesProvider).valueOrNull;

    // "<warehouseId>|<zone lowercased>" → items this consignment adds.
    final wanted = <String, int>{};
    final labels = <String, String>{};
    for (int i = 0; i < items.length; i++) {
      final whId = _itemWarehouseSelections[i];
      if (whId == null) continue;
      final cat = cats?.where((c) => c.name == items[i].category).firstOrNull;
      final zoneName = (cat?.targetZone ?? '').trim();
      if (zoneName.isEmpty) continue; // no zone chosen → nothing to check
      final key = '$whId|${zoneName.toLowerCase()}';
      wanted[key] = (wanted[key] ?? 0) + items[i].quantity;
      labels[key] = zoneName;
    }

    final problems = <_CapacityProblem>[];
    for (final entry in wanted.entries) {
      final parts = entry.key.split('|');
      final whId = parts.first;
      final zoneName = labels[entry.key] ?? parts.last;

      final zone = zones
          .where((z) =>
              z.warehouseId == whId &&
              z.name.trim().toLowerCase() == parts.last)
          .firstOrNull;
      // A zone the admin never defined cannot be capacity-checked; admitting
      // is still allowed, and the capacity view reports it as unzoned.
      if (zone == null) continue;

      final occ = occupancy[zone.id];
      final free = occ?.free ?? zone.capacity;
      if (entry.value <= free) continue;

      // Where else the same warehouse has room.
      final alternatives = zones
          .where((z) => z.warehouseId == whId && z.id != zone.id)
          .map((z) => (z, occupancy[z.id]?.free ?? z.capacity))
          .where((e) => e.$2 >= entry.value)
          .map((e) => '${e.$1.name} (${e.$2} free)')
          .toList();

      problems.add(_CapacityProblem(
        zoneName: zoneName,
        needed: entry.value,
        free: free,
        capacity: zone.capacity,
        alternatives: alternatives,
      ));
    }
    return problems;
  }

  Future<void> _sendToWarehouse() async {
    // Guard against the SnackBar "RETRY" action firing after this widget is
    // gone (e.g. user navigated away) — setState would throw otherwise.
    if (!mounted) return;
    if (widget.tempPackageItems != null) {
      for (int i = 0; i < widget.tempPackageItems!.length; i++) {
        if (_itemWarehouseSelections[i] == null) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Please select a warehouse for Goods ${i + 1}')));
          return;
        }
      }
    }

    if (widget.tempPackageData == null || widget.tempPackageItems == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Package data not found')));
      return;
    }

    // ── Capacity check ──────────────────────────────────────────────────────
    // Nothing used to stop goods being admitted into a full warehouse, which
    // is how one reached 128%. Space is managed zone by zone, so the check is
    // per zone — and it counts EVERY item in this consignment together, since
    // several can land in the same zone.
    final blocked = await _findCapacityProblems();
    if (blocked.isNotEmpty) {
      if (!mounted) return;
      final proceed = await showDialog<bool>(
            context: context,
            builder: (_) => _CapacityBlockedDialog(problems: blocked),
          ) ??
          false;
      if (!proceed) return;
    }

    setState(() => _isSending = true);
    try {
      // First save the package to database
      final saved = await ref.read(packageServiceProvider).upsertPackage(
            widget.tempPackageData!
                .copyWith(status: 'held'), // Set a general status
            widget.tempPackageItems!,
            yard: widget.yard,
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
      if (errStr.contains('duplicate key') ||
          errStr.contains('unique constraint') ||
          errStr.contains('23505')) {
        userMessage =
            'A package with SR "${widget.tempPackageData?.srNumber ?? ''}" already exists. Use the search to edit it.';
      } else if (errStr.contains('socketexception') ||
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
              Text('Goods Distribution',
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
                              child: Text('Goods ${index + 1}',
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
                          error: (e, _) {
                            // Usually a transient network/DNS hiccup — the app
                            // reached other data fine. Offer a Retry rather than
                            // dead-ending the whole SR entry.
                            final isNetwork = e
                                    .toString()
                                    .contains('SocketException') ||
                                e.toString().contains('Failed host lookup') ||
                                e.toString().contains('ClientException');
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  Icon(Icons.wifi_off_rounded,
                                      size: 16,
                                      color: context.colors.dangerRed),
                                  const Gap(8),
                                  Expanded(
                                    child: Text(
                                      isNetwork
                                          ? 'Couldn\'t reach the server. Check your internet connection and try again.'
                                          : 'Error loading warehouses: $e',
                                      style: TextStyle(
                                          color: context.colors.dangerRed,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ]),
                                const Gap(10),
                                OutlinedButton.icon(
                                  icon: const Icon(Icons.refresh_rounded,
                                      size: 16),
                                  label: const Text('Retry'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: context.colors.primaryGold,
                                    side: BorderSide(
                                        color: context.colors.primaryGold
                                            .withOpacity(0.5)),
                                  ),
                                  onPressed: () =>
                                      ref.invalidate(warehousesProvider),
                                ),
                              ],
                            );
                          },
                          data: (ws) => Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: ws.map((w) {
                              final isSelected =
                                  _itemWarehouseSelections[index] == w.id;
                              final hasAutoSelection =
                                  _itemWarehouseSelections[index] != null;

                              return InkWell(
                                onTap: () => setState(() =>
                                    _itemWarehouseSelections[index] = w.id),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? context.colors.primaryGold
                                            .withOpacity(0.15)
                                        : context.colors.surfaceDark,
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
                                          : context.colors.textSecondary,
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

/// Cusdec No input with prefix autocomplete. Common Cusdec numbers start with a
/// fixed prefix (CBHQI / ECC / I) followed by a space and a number. As the user
/// types, matching prefixes are suggested; picking one fills "<PREFIX> " so they
/// only type the digits. It's still a free-text field — any other format can be
/// typed directly (the suggestions just never match, so no menu shows).
class _CusdecAutocompleteField extends StatefulWidget {
  final TextEditingController controller;
  final InputDecoration decoration;
  final String? Function(String?)? validator;

  const _CusdecAutocompleteField({
    required this.controller,
    required this.decoration,
    this.validator,
  });

  static const List<String> _prefixes = ['CBHQI', 'CBMVI', 'ECC', 'I'];

  @override
  State<_CusdecAutocompleteField> createState() =>
      _CusdecAutocompleteFieldState();
}

class _CusdecAutocompleteFieldState extends State<_CusdecAutocompleteField> {
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<String>(
      textEditingController: widget.controller,
      focusNode: _focusNode,
      optionsBuilder: (TextEditingValue value) {
        final text = value.text.trimLeft();
        if (text.isEmpty) return const Iterable<String>.empty();
        // Once a space (i.e. the number part) is typed, stop suggesting.
        if (text.contains(' ')) return const Iterable<String>.empty();
        final upper = text.toUpperCase();
        final matches = _CusdecAutocompleteField._prefixes
            .where((p) => p.startsWith(upper) && p != upper)
            .map((p) => '$p ') // trailing space → caret lands on the number
            .toList();
        return matches;
      },
      onSelected: (selection) {
        widget.controller.text = selection;
        widget.controller.selection =
            TextSelection.collapsed(offset: selection.length);
      },
      fieldViewBuilder: (context, textController, focusNode, onFieldSubmitted) {
        return TextFormField(
          controller: textController,
          focusNode: focusNode,
          decoration: widget.decoration,
          validator: widget.validator,
          textCapitalization: TextCapitalization.characters,
          onFieldSubmitted: (_) => onFieldSubmitted(),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        final opts = options.toList();
        // The index RawAutocomplete highlights as the user presses ↑/↓ (Enter
        // then selects it). We mirror it visually and keep it scrolled into view.
        final highlighted = AutocompleteHighlightedOption.of(context);
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(10),
            color: context.colors.surfaceDark,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220, maxWidth: 320),
              child: _CusdecOptionsList(
                options: opts,
                highlightedIndex: highlighted,
                onSelected: onSelected,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The suggestion list for the Cusdec autocomplete. Highlights the option that
/// RawAutocomplete has selected via ↑/↓ and scrolls it into view, so keyboard
/// navigation is visible; Enter selects the highlighted one, tap selects any.
class _CusdecOptionsList extends StatefulWidget {
  final List<String> options;
  final int highlightedIndex;
  final AutocompleteOnSelected<String> onSelected;

  const _CusdecOptionsList({
    required this.options,
    required this.highlightedIndex,
    required this.onSelected,
  });

  @override
  State<_CusdecOptionsList> createState() => _CusdecOptionsListState();
}

class _CusdecOptionsListState extends State<_CusdecOptionsList> {
  final ScrollController _scrollController = ScrollController();

  @override
  void didUpdateWidget(_CusdecOptionsList old) {
    super.didUpdateWidget(old);
    if (old.highlightedIndex != widget.highlightedIndex) {
      // Keep the highlighted row visible as the user arrows through the list.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollController.hasClients) return;
        const rowHeight = 48.0;
        final target = widget.highlightedIndex * rowHeight;
        _scrollController.animateTo(
          target.clamp(0.0, _scrollController.position.maxScrollExtent),
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
        );
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: _scrollController,
      padding: EdgeInsets.zero,
      shrinkWrap: true,
      itemCount: widget.options.length,
      itemBuilder: (context, i) {
        final option = widget.options[i];
        final isHighlighted = i == widget.highlightedIndex;
        return InkWell(
          onTap: () => widget.onSelected(option),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isHighlighted
                  ? context.colors.primaryGold.withOpacity(0.15)
                  : null,
              border: Border(
                bottom: BorderSide(
                    color: context.colors.borderColor.withOpacity(0.5)),
              ),
            ),
            child: Row(children: [
              Icon(Icons.tag_rounded,
                  size: 16, color: context.colors.primaryGold),
              const Gap(10),
              Text(option.trim(),
                  style: TextStyle(
                      color: context.colors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 14)),
              const Gap(8),
              Text('+ number',
                  style:
                      TextStyle(color: context.colors.textMuted, fontSize: 12)),
            ]),
          ),
        );
      },
    );
  }
}

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
          Text('QR Code Generate',
              style: Theme.of(context).textTheme.titleLarge),
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
  // Cartons only: inner unit type + inner quantity per carton.
  final innerUnitCtrl = TextEditingController(text: 'Pieces');
  final innerQtyCtrl = TextEditingController(text: '1');
  final valueCtrl = TextEditingController(text: '0');
  final hsCodeCtrl = TextEditingController();
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
    final zones = ref.watch(warehouseZonesProvider).valueOrNull ??
        const <WarehouseZoneModel>[];
    final occupancy = ref.watch(zoneOccupancyProvider).valueOrNull ??
        const <String, ZoneOccupancy>{};
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
              child: Text('Goods ${widget.index}',
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
              flex: 5,
              child: TextFormField(
                  controller: widget.row.nameCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Goods Name *',
                      isDense: true,
                      helperText: ' ',
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
                  validator: (v) => widget.showValidationErrors &&
                          (v == null || v.trim().isEmpty)
                      ? 'Required'
                      : null,
                  onChanged: (_) => widget.onChanged()),
            ),
            const Gap(10),
            Expanded(
              flex: 2,
              child: StyledDropdownFormField<String>(
                label: 'Unit Type *',
                menuWidth: 220,
                columns: 2,
                value: const [
                  'Pieces',
                  'Cartons',
                  'Boxes',
                  'Bags',
                  'Pallets',
                  'Rolls',
                  'Packages',
                  'No of',
                  'Bottles',
                  'KG',
                  'Meters',
                  'Other'
                ].contains(widget.row.unitOfMeasureCtrl.text)
                    ? widget.row.unitOfMeasureCtrl.text
                    : 'Pieces',
                options: const [
                  'Pieces',
                  'Cartons',
                  'Boxes',
                  'Bags',
                  'Pallets',
                  'Rolls',
                  'Packages',
                  'No of',
                  'Bottles',
                  'KG',
                  'Meters',
                  'Other'
                ].map((u) => StyledDropdownOption(u, u)).toList(),
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
                      labelText: 'Name *',
                      isDense: true,
                      helperText: ' ',
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
                  validator: (v) => widget.showValidationErrors &&
                          widget.row.unitOfMeasureCtrl.text == 'Other' &&
                          (v == null || v.trim().isEmpty)
                      ? 'Req'
                      : null,
                  onChanged: (_) => widget.onChanged(),
                ),
              ),
            ],
            // Quantity of the selected unit type — shown right beside Unit Type.
            const Gap(10),
            Expanded(
              flex: 1,
              child: TextFormField(
                controller: widget.row.qtyCtrl,
                decoration: const InputDecoration(
                    labelText: 'Quantity *',
                    isDense: true,
                    helperText: ' ',
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
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
            // Cartons only: inner unit + its quantity, shown right after Qty.
            if (widget.row.unitOfMeasureCtrl.text == 'Cartons') ...[
              const Gap(10),
              Expanded(
                flex: 2,
                child: StyledDropdownFormField<String>(
                  label: 'Inner Unit *',
                  menuWidth: 220,
                  columns: 2,
                  value: const [
                    'Pieces',
                    'Boxes',
                    'Bags',
                    'Pallets',
                    'Rolls',
                    'Packages',
                    'No of',
                    'Bottles',
                    'KG',
                    'Meters',
                  ].contains(widget.row.innerUnitCtrl.text)
                      ? widget.row.innerUnitCtrl.text
                      : 'Pieces',
                  options: const [
                    'Pieces',
                    'Boxes',
                    'Bags',
                    'Pallets',
                    'Rolls',
                    'Packages',
                    'No of',
                    'Bottles',
                    'KG',
                    'Meters',
                  ].map((u) => StyledDropdownOption(u, u)).toList(),
                  onChanged: (v) {
                    setState(
                        () => widget.row.innerUnitCtrl.text = v ?? 'Pieces');
                    widget.onChanged();
                  },
                ),
              ),
              const Gap(8),
              Expanded(
                flex: 1,
                child: TextFormField(
                  controller: widget.row.innerQtyCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Inner Qty *',
                      isDense: true,
                      helperText: ' ',
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: (v) {
                    if (!widget.showValidationErrors) return null;
                    if (widget.row.unitOfMeasureCtrl.text == 'Cartons' &&
                        (v == null || v.trim().isEmpty)) return 'Req';
                    return null;
                  },
                  onChanged: (_) => widget.onChanged(),
                ),
              ),
            ],
            const Gap(10),
            Expanded(
              flex: 2,
              child: StyledDropdownFormField<String>(
                label: 'Status *',
                menuWidth: 200,
                value: const ['Detain', 'Forfeit', 'Abandoned', 'Other']
                        .contains(widget.row.status)
                    ? widget.row.status
                    : 'Other',
                options: const ['Detain', 'Forfeit', 'Abandoned', 'Other']
                    .map((s) => StyledDropdownOption(s, s))
                    .toList(),
                onChanged: (v) {
                  setState(() {
                    final previous = widget.row.status;
                    widget.row.status = v!;
                    // Detain and the disposal statuses offer different
                    // activities — drop selections that no longer apply.
                    if (postStatusActivitiesFor(previous) !=
                        postStatusActivitiesFor(widget.row.status)) {
                      widget.row.selectedReasons
                        ..clear()
                        ..add(null);
                    }
                  });
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
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
                  return StyledDropdownFormField<String>(
                    label: 'Category',
                    menuWidth: 280,
                    value: selectedCategory?.name,
                    options: list.map((c) {
                      final zn = c.targetZone?.trim();
                      final zone = (zn != null && zn.isNotEmpty)
                          ? zones
                              .where((z) =>
                                  z.warehouseId == c.targetWarehouseId &&
                                  z.name.trim().toLowerCase() ==
                                      zn.toLowerCase())
                              .firstOrNull
                          : null;
                      final occ = zone != null ? occupancy[zone.id] : null;
                      final free = occ?.free ?? zone?.capacity ?? 0;
                      final isFull = zone != null && free <= 0;

                      final label = isFull
                          ? '${c.name} [Zone $zn FULL 🔴]'
                          : c.name;
                      return StyledDropdownOption(c.name, label);
                    }).toList(),
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
        // ── HS Code & Value (per item) ──
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                controller: widget.row.hsCodeCtrl,
                decoration: const InputDecoration(
                    labelText: 'HS Code *', isDense: true, helperText: ' '),
                validator: (v) => widget.showValidationErrors &&
                        (v == null || v.trim().isEmpty)
                    ? 'Required'
                    : null,
                onChanged: (_) => widget.onChanged(),
              ),
            ),
            const Gap(12),
            Expanded(
              child: TextFormField(
                controller: widget.row.valueCtrl,
                decoration: const InputDecoration(
                    labelText: 'Value *',
                    isDense: true,
                    helperText: ' ',
                    prefixText: 'LKR '),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
                ],
                validator: (v) {
                  if (!widget.showValidationErrors) return null;
                  if (v == null || v.trim().isEmpty) return 'Required';
                  final parsed = double.tryParse(v.trim());
                  if (parsed == null || parsed <= 0) return 'Enter a value';
                  return null;
                },
                onChanged: (_) => widget.onChanged(),
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
                  final zn = (cat.targetZone ?? '').trim();
                  final zone = zn.isNotEmpty
                      ? zones
                          .where((z) =>
                              z.warehouseId == cat.targetWarehouseId &&
                              z.name.trim().toLowerCase() ==
                                  zn.toLowerCase())
                          .firstOrNull
                      : null;
                  final occ = zone != null ? occupancy[zone.id] : null;
                  final free = occ?.free ?? zone?.capacity ?? 0;
                  final isFull = zone != null && free <= 0;

                  if (isFull) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                          color: context.colors.dangerRed.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color: context.colors.dangerRed
                                  .withOpacity(0.4),
                              width: 1)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.warning_amber_rounded,
                            size: 15, color: context.colors.dangerRed),
                        const Gap(6),
                        Text(
                            '${_formatWarehouseName(cat.targetWarehouseName ?? cat.targetWarehouseId ?? '')} | Zone ${cat.targetZone ?? '—'} (FULL - No space available)',
                            style: TextStyle(
                                color: context.colors.dangerRed,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700))
                      ]),
                    );
                  }

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
                                  : '') +
                              (zone != null ? ' ($free free)' : ''),
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
        // ── Post Status Activity Section ──
        // Options are driven by the item's Status: `Detain` gets the pending
        // activities, every other status gets the disposal activities.
        Row(
          children: [
            Icon(Icons.warning_amber_rounded,
                size: 18, color: context.colors.heldOrange),
            const Gap(8),
            Text('Post Status Activity',
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
                label: const Text('Add Activity',
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
            final activities = postStatusActivitiesFor(widget.row.status);
            return SizedBox(
              width: 380,
              child: Row(
                children: [
                  Expanded(
                    child: StyledDropdownFormField<String>(
                      label: 'Activity ${rIdx + 1} *',
                      menuWidth: 300,
                      fillColor: context.colors.cardDark,
                      value:
                          activities.contains(widget.row.selectedReasons[rIdx])
                              ? widget.row.selectedReasons[rIdx]
                              : null,
                      validator: (v) => widget.showValidationErrors && v == null
                          ? 'Required'
                          : null,
                      options: activities.map((a) {
                        final isSelectedSomewhereElse =
                            widget.row.selectedReasons.any((res) => res == a);
                        final isCurrentSelection =
                            widget.row.selectedReasons[rIdx] == a;
                        return StyledDropdownOption(
                          a,
                          a,
                          enabled:
                              !isSelectedSomewhereElse || isCurrentSelection,
                        );
                      }).toList(),
                      onChanged: (v) {
                        setState(() => widget.row.selectedReasons[rIdx] = v);
                        widget.onChanged();
                      },
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
                        tooltip: 'Remove activity',
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

/// One zone this consignment would overfill.
class _CapacityProblem {
  final String zoneName;

  /// Items this consignment wants to put in the zone.
  final int needed;

  /// Room actually left.
  final int free;
  final int capacity;

  /// Zones in the SAME warehouse that could take the whole lot.
  final List<String> alternatives;

  const _CapacityProblem({
    required this.zoneName,
    required this.needed,
    required this.free,
    required this.capacity,
    this.alternatives = const [],
  });
}

/// Stops a consignment that does not fit, and says where it would.
///
/// Not a hard block: the officer can still admit the goods (physical reality
/// sometimes runs ahead of the record, and refusing outright would leave them
/// nowhere to log it). But it can no longer happen by accident — the overflow
/// is stated, and the alternatives are offered first.
class _CapacityBlockedDialog extends StatelessWidget {
  final List<_CapacityProblem> problems;
  const _CapacityBlockedDialog({required this.problems});

  @override
  Widget build(BuildContext context) {
    final red = context.colors.dangerRed;

    return StyledFormDialog(
      label: 'WAREHOUSE CAPACITY',
      title: problems.length == 1
          ? 'Zone ${problems.first.zoneName} is full'
          : '${problems.length} zones are full',
      icon: Icons.warehouse_rounded,
      headerAccentColor: red,
      width: 560,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Change warehouse'),
        ),
        const Gap(8),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
              backgroundColor: red, foregroundColor: Colors.white),
          icon: const Icon(Icons.warning_amber_rounded, size: 18),
          label: const Text('Admit anyway'),
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final p in problems) ...[
            StyledFormSection(
              title: 'Zone ${p.zoneName}',
              icon: Icons.grid_view_rounded,
              children: [
                _CapacityLine(
                    label: 'These goods need', value: '${p.needed} items'),
                _CapacityLine(
                    label: 'Room left',
                    value: '${p.free} of ${p.capacity}',
                    colour: red),
                _CapacityLine(
                    label: 'Over by',
                    value: '${p.needed - p.free} items',
                    colour: red,
                    emphasise: true),
                if (p.alternatives.isNotEmpty) ...[
                  const Gap(10),
                  Text('Zones in this warehouse with room:',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: context.colors.textSecondary)),
                  const Gap(6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final a in p.alternatives)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(
                            color:
                                context.colors.successGreen.withOpacity(0.10),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: context.colors.successGreen
                                    .withOpacity(0.4)),
                          ),
                          child: Text('Zone $a',
                              style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: context.colors.successGreen)),
                        ),
                    ],
                  ),
                ] else ...[
                  const Gap(10),
                  Text(
                      'No other zone in this warehouse has room for them — '
                      'try a different warehouse.',
                      style: TextStyle(
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                          color: context.colors.textMuted)),
                ],
              ],
            ),
            const Gap(12),
          ],
        ],
      ),
    );
  }
}

class _CapacityLine extends StatelessWidget {
  final String label;
  final String value;
  final Color? colour;
  final bool emphasise;
  const _CapacityLine(
      {required this.label,
      required this.value,
      this.colour,
      this.emphasise = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Text(label,
            style: TextStyle(color: context.colors.textMuted, fontSize: 12.5)),
        const Spacer(),
        Text(value,
            style: TextStyle(
                color: colour ?? context.colors.textPrimary,
                fontSize: emphasise ? 14 : 13,
                fontWeight: emphasise ? FontWeight.w800 : FontWeight.w600)),
      ]),
    );
  }
}
