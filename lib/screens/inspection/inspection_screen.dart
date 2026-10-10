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
import '../../core/db_client.dart';
import '../../core/app_log.dart';
import '../../core/idle_lock.dart';
import '../../widgets/app_dialog.dart';

class InspectionScreen extends ConsumerStatefulWidget {
  const InspectionScreen({super.key});
  @override
  ConsumerState<InspectionScreen> createState() => _InspectionScreenState();
}

class _InspectionScreenState extends ConsumerState<InspectionScreen>
    with TickerProviderStateMixin, LockRestorableForm<InspectionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _srNumberCtrl = TextEditingController();
  // ⚠️ So picking a Register (SR/OA) can hand focus straight to the number
  // field afterwards. Without this the officer chose SR or OA, then had to
  // click into the number box separately before they could type or fix it —
  // two clicks to do one thing.
  final _srNumberFocus = FocusNode();
  // Registration mode: 'new' = a fresh SR entry (default), 'old' = migrating a
  // legacy package — captures its previous SR number in [_oldSrNumberCtrl].
  String _entryMode = 'new';
  final _oldSrNumberCtrl = TextEditingController();
  // Yard this SR is being registered under. Defaults to the signed-in user's
  // yard; the prefix of the generated SR number follows this selection.
  // Normalised through yardByCode so it always matches a dropdown item.
  String _selectedYard = yardByCode(AppSession.currentYard).code;

  /// Which register this number is minted from -- SR or OA. Both share the
  /// yard's single running serial, so switching this keeps the serial already
  /// on screen and only rewrites the register segment.
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
  final _formScrollController = ScrollController();

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

  // ── Surviving the idle lock ────────────────────────────────────────────
  //
  // ⚠️ This is the longest form in the app -- a dozen package fields plus a
  // row of controllers per goods item -- so it is the one where losing the
  // typing to a five-minute lock actually costs an officer their afternoon.

  @override
  String get formStateId => '/inspection';

  @override
  Map<String, dynamic> readFormState() => {
        'sr': _srNumberCtrl.text,
        'oldSr': _oldSrNumberCtrl.text,
        'entryMode': _entryMode,
        'yard': _selectedYard,
        'docType': _srDocType,
        'case': _caseNumberCtrl.text,
        'origin': _originCtrl.text,
        'value': _valueCtrl.text,
        'weight': _weightCtrl.text,
        'consignee': _consigneeCtrl.text,
        'consigneeNic': _consigneeNicCtrl.text,
        'consigneePhone': _consigneePhoneCtrl.text,
        'declarant': _declarantCtrl.text,
        'cusdec': _cusdecCtrl.text,
        'cusdecDate': _cusdecDateCtrl.text,
        'entryDate': _entryDateCtrl.text,
        'container': _containerNumberCtrl.text,
        'deposit': _destroyingDepositCtrl.text,
        'desc': _descCtrl.text,
        'reason': _reasonCtrlMain.text,
        'notes': _notesCtrl.text,
        'isUpdate': _isUpdate,
        'loadedSr': _loadedSrNumber,
        'items': [
          for (final r in _items)
            {
              'itemId': r.itemId,
              'name': r.nameCtrl.text,
              'goodsDesc': r.goodsDescriptionCtrl.text,
              'qty': r.qtyCtrl.text,
              'unit': r.unitOfMeasureCtrl.text,
              'unitOther': r.unitOtherCtrl.text,
              'innerUnit': r.innerUnitCtrl.text,
              'innerQty': r.innerQtyCtrl.text,
              'value': r.valueCtrl.text,
              'hs': r.hsCodeCtrl.text,
              'category': r.categoryCtrl.text,
              'status': r.status,
              'nature': r.nature,
              'otherStatus': r.otherStatusCtrl.text,
              'reasons': r.selectedReasons,
            }
        ],
      };

  @override
  void writeFormState(Map<String, dynamic> saved) {
    String str(Object? v) => v?.toString() ?? '';
    setState(() {
      _srNumberCtrl.text = str(saved['sr']);
      _oldSrNumberCtrl.text = str(saved['oldSr']);
      _entryMode = str(saved['entryMode']).isEmpty ? 'new' : str(saved['entryMode']);
      _selectedYard = str(saved['yard']).isEmpty ? _selectedYard : str(saved['yard']);
      _srDocType =
          str(saved['docType']).isEmpty ? kDefaultSrDocType : str(saved['docType']);
      _caseNumberCtrl.text = str(saved['case']);
      _originCtrl.text = str(saved['origin']);
      _valueCtrl.text = str(saved['value']);
      _weightCtrl.text = str(saved['weight']);
      _consigneeCtrl.text = str(saved['consignee']);
      _consigneeNicCtrl.text = str(saved['consigneeNic']);
      _consigneePhoneCtrl.text = str(saved['consigneePhone']);
      _declarantCtrl.text = str(saved['declarant']);
      _cusdecCtrl.text = str(saved['cusdec']);
      _cusdecDateCtrl.text = str(saved['cusdecDate']);
      if (str(saved['entryDate']).isNotEmpty) {
        _entryDateCtrl.text = str(saved['entryDate']);
      }
      _containerNumberCtrl.text = str(saved['container']);
      _destroyingDepositCtrl.text = str(saved['deposit']);
      _descCtrl.text = str(saved['desc']);
      _reasonCtrlMain.text = str(saved['reason']);
      _notesCtrl.text = str(saved['notes']);
      _isUpdate = saved['isUpdate'] == true;
      _loadedSrNumber = saved['loadedSr'] as String?;

      final rows = (saved['items'] as List?) ?? const [];
      if (rows.isNotEmpty) {
        // ⚠️ Rebuilt from scratch, not merged: the officer may have added or
        // removed goods rows before the lock, so the saved list is the truth
        // about how many there were.
        for (final r in _items) {
          r.nameCtrl.dispose();
          r.goodsDescriptionCtrl.dispose();
          r.qtyCtrl.dispose();
          r.unitOfMeasureCtrl.dispose();
          r.unitOtherCtrl.dispose();
          r.innerUnitCtrl.dispose();
          r.innerQtyCtrl.dispose();
          r.valueCtrl.dispose();
          r.hsCodeCtrl.dispose();
          r.categoryCtrl.dispose();
          r.otherStatusCtrl.dispose();
        }
        _items
          ..clear()
          ..addAll([
            for (final raw in rows)
              () {
                final m = (raw as Map).cast<String, dynamic>();
                final row = _ItemRow();
                row.itemId = m['itemId'] as String?;
                row.nameCtrl.text = str(m['name']);
                row.goodsDescriptionCtrl.text = str(m['goodsDesc']);
                row.qtyCtrl.text = str(m['qty']);
                row.unitOfMeasureCtrl.text = str(m['unit']);
                row.unitOtherCtrl.text = str(m['unitOther']);
                row.innerUnitCtrl.text = str(m['innerUnit']);
                row.innerQtyCtrl.text = str(m['innerQty']);
                row.valueCtrl.text = str(m['value']);
                row.hsCodeCtrl.text = str(m['hs']);
                row.categoryCtrl.text = str(m['category']);
                row.status = str(m['status']).isEmpty ? 'Detain' : str(m['status']);
                row.nature =
                    str(m['nature']).isEmpty ? kNatureNormal : str(m['nature']);
                row.otherStatusCtrl.text = str(m['otherStatus']);
                final rs = (m['reasons'] as List?) ?? const [];
                row.selectedReasons
                  ..clear()
                  ..addAll(rs.isEmpty
                      ? <String?>[null]
                      : rs.map((e) => e as String?));
                return row;
              }()
          ]);
      }
    });
  }

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
        if (mounted) {
          context.showInfo('SR "$sr" not found – filling as new entry.');
        }
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
        _savedPackageId = pkg.id;
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
              // ⚠️ Back OUT of the total, since `quantity` now holds
              // cartons × per-carton. Showing the total here would make the
              // form read "20 Cartons of 1176 Pieces each" and, on the next
              // save, multiply it again.
              final cartons = item.innerQuantity ?? 1;
              row.innerQtyCtrl.text =
                  (cartons > 0 ? (item.quantity ~/ cartons) : item.quantity)
                      .toString();
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
      if (mounted) context.showSuccess('SR "$sr" loaded – you can edit and save.');
    } catch (e) {
      if (mounted) context.showError('Lookup error: $e');
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
    final DateTime? picked = await showAppDialog<DateTime>(
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
      AppLog.warn('SR generation failed', error: e, tag: 'inspection');
    }
  }

  /// Fills a starting point for "Old SR Number" when Old Entry is chosen.
  ///
  /// ⚠️ NOT a real serial the way [_generateNextSr] mints one. The old number
  /// belongs to a PAST register this app has no record of, so there is
  /// nothing to count against — only the yard and the current year are known
  /// for certain. This fills in `<YARD PREFIX>/SR/01/<CURRENT YEAR>` as a
  /// template the officer edits down to the real number, using the signed-in
  /// yard so the prefix is never typed by hand.
  ///
  /// The field stays fully editable and this never runs over something the
  /// officer already typed — switching modes back and forth, or loading an
  /// existing package, must not erase a real old number in favour of a guess.
  void _prefillOldSrTemplate() {
    if (_oldSrNumberCtrl.text.trim().isNotEmpty) return;
    final prefix = yardSrPrefix(_selectedYard ?? AppSession.currentYard);
    if (prefix.isEmpty) return;
    // ⚠️ composeSrNumber, the SAME builder the New Entry number comes from —
    // not a hand-assembled string. The first version left the directorate
    // segment off (`GL1/SR/01/2026` instead of `CED/GL1/SR/01/2026`), so the
    // template did not match the shape the officer sees everywhere else on
    // this form, or the shape `_loadBySrNumber` and the duplicate-SR check
    // actually expect. Reusing the builder means the two can never drift
    // apart again.
    _oldSrNumberCtrl.text = composeSrNumber(
      yardPrefix: prefix,
      serial: 1,
      year: DateTime.now().year,
      directorateCode: AppSession.currentDirectorate,
    );
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChange);
    _tabController.dispose();
    _srNumberCtrl.dispose();
    _srNumberFocus.dispose();
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
    _formScrollController.dispose();
    super.dispose();
  }

  Future<void> _checkPackage() async {
    setState(() => _showValidationErrors = true);
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    if (!_formKey.currentState!.validate()) {
      _formScrollController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
      if (mounted) {
        context.showError(
            'Please fill all required fields highlighted in red above.');
      }
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
                nature: r.nature,
                // Cartons are stored "inverted": the operational quantity/unit
                // become the INNER contents (e.g. 1176 Pieces), and the outer
                // packaging (20 Cartons) is kept in innerUnit/innerQuantity.
                //
                // ⚠️ CARTONS × PER-CARTON, not the per-carton figure alone.
                // `innerQtyCtrl` is "how many in ONE carton" -- the form's own
                // label says so -- so storing it raw recorded 20 cartons of 60
                // pieces as 60 pieces. Every count downstream reads `quantity`:
                // the warehouse charge, the zone capacity, the Qty column on
                // every table. They were all short by the carton count.
                quantity: r.unitOfMeasureCtrl.text == 'Cartons'
                    ? ((int.tryParse(r.qtyCtrl.text) ?? 1) *
                        (int.tryParse(r.innerQtyCtrl.text) ?? 1))
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

      final pkgId = (_isUpdate && _loadedSrNumber == _srNumberCtrl.text.trim())
          ? (_savedPackageId ?? '')
          : '';

      final pkg = PackageModel(
        id: pkgId,
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
      });
      _tabController.animateTo(1);
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
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
      _isUpdate = false;
      _loadedSrNumber = null;
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
                      context.showWarning(
                          'Please complete warehouse confirmation first');
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
                    controller: _formScrollController,
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
                                  // ⚠️ No isDense/valueStyle override. These
                                  // made this dropdown taller and its text
                                  // bigger than every field below it, so one
                                  // form showed three different control
                                  // sizes. The theme sets the height once.
                                  value: _entryMode,
                                  options: const [
                                    StyledDropdownOption('new', 'New Entry'),
                                    StyledDropdownOption('old', 'Old Entry'),
                                  ],
                                  onChanged: (v) {
                                    setState(() => _entryMode = v ?? 'new');
                                    // Give the officer a starting point rather
                                    // than a blank required field — see
                                    // _prefillOldSrTemplate for why this is a
                                    // template, not a generated serial.
                                    if (_entryMode == 'old') {
                                      _prefillOldSrTemplate();
                                    }
                                  },
                                ),
                                const Gap(12),
                                if (_isUpdate)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 8),
                                    margin: const EdgeInsets.only(bottom: 12),
                                    decoration: BoxDecoration(
                                      color: context.colors.primaryGold
                                          .withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                          color: context.colors.primaryGold
                                              .withOpacity(0.4)),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(Icons.edit_rounded,
                                            color: context.colors.primaryGold,
                                            size: 16),
                                        const Gap(8),
                                        Expanded(
                                          child: Text(
                                              'Editing existing SR (${_loadedSrNumber ?? ''}) – changes will update the record.',
                                              style: TextStyle(
                                                  color: context
                                                      .colors.primaryGold,
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w500)),
                                        ),
                                        const Gap(8),
                                        InkWell(
                                          onTap: _reset,
                                          borderRadius:
                                              BorderRadius.circular(6),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 10, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: context.colors.dangerRed
                                                  .withOpacity(0.15),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              border: Border.all(
                                                  color: context.colors.dangerRed
                                                      .withOpacity(0.4)),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(Icons.close_rounded,
                                                    size: 14,
                                                    color: context
                                                        .colors.dangerRed),
                                                const Gap(4),
                                                Text(
                                                  'Cancel Edit',
                                                  style: TextStyle(
                                                    color: context
                                                        .colors.dangerRed,
                                                    fontSize: 12,
                                                    fontWeight:
                                                        FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
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
                                          labelText: AppSession
                                                      .currentDirectorate ==
                                                  null
                                              ? 'Yard'
                                              : 'Yard · '
                                                  '${directorateSrPrefix(AppSession.currentDirectorate)}',
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
                                          // Keep the serial the officer is
                                          // already looking at: this is a
                                          // correction to the number's
                                          // REGISTER, not a request for a
                                          // different number. Only when there
                                          // is nothing to rewrite do we mint
                                          // one from the new register's count.
                                          final swapped = withSrDocType(
                                              _srNumberCtrl.text, v);
                                          if (swapped != null) {
                                            setState(() =>
                                                _srNumberCtrl.text = swapped);
                                          } else {
                                            _generateNextSr();
                                          }
                                          // ⚠️ Hand focus to the number field
                                          // right after the pick, so the
                                          // officer can start typing without
                                          // an extra click into the box.
                                          // Selects the current text too, so
                                          // typing replaces the generated
                                          // number rather than landing in the
                                          // middle of it.
                                          WidgetsBinding.instance
                                              .addPostFrameCallback((_) {
                                            if (!mounted) return;
                                            _srNumberFocus.requestFocus();
                                            _srNumberCtrl.selection =
                                                TextSelection(
                                              baseOffset: 0,
                                              extentOffset:
                                                  _srNumberCtrl.text.length,
                                            );
                                          });
                                        },
                                      ),
                                    ),
                                    const Gap(12),
                                    Expanded(
                                      flex: 2,
                                      child: TextFormField(
                                        controller: _srNumberCtrl,
                                        focusNode: _srNumberFocus,
                                        inputFormatters: [
                                          FilteringTextInputFormatter.allow(
                                              RegExp(r'[a-zA-Z0-9/ ]')),
                                          LengthLimitingTextInputFormatter(30),
                                        ],
                                        decoration: _fieldDecoration(
                                          labelText: 'SR Number *',
                                          hintText:
                                              'e.g. GL1/SR/01/2025 or GL1/OA/01/2025',
                                          suffixIcon: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              if (_isUpdate)
                                                Tooltip(
                                                  message:
                                                      'Cancel edit and reset to new entry',
                                                  child: IconButton(
                                                    icon: Icon(
                                                        Icons.close_rounded,
                                                        size: 18,
                                                        color: context.colors
                                                            .dangerRed),
                                                    onPressed: _reset,
                                                  ),
                                                ),
                                              Tooltip(
                                                message: isOfficer
                                                    ? 'Loading existing SR entries is restricted to administrators only'
                                                    : 'Search and load SR entry',
                                                child: IconButton(
                                                  icon: _isLookingUp
                                                      ? SizedBox(
                                                          width: 16,
                                                          height: 16,
                                                          child:
                                                              CircularProgressIndicator(
                                                                  strokeWidth:
                                                                      2,
                                                                  color: context
                                                                      .colors
                                                                      .primaryGold))
                                                      : Icon(
                                                          Icons.search_rounded,
                                                          color: isOfficer
                                                              ? context.colors
                                                                  .textMuted
                                                                  : context
                                                                      .colors
                                                                      .primaryGold),
                                                  onPressed: (isOfficer ||
                                                          _isLookingUp)
                                                      ? null
                                                      : _loadBySrNumber,
                                                ),
                                              ),
                                            ],
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
                                          validator: _requiredValidator,
                                          textCapitalization:
                                              TextCapitalization.characters)),
                                  const Gap(12),
                                  Expanded(
                                      child: TextFormField(
                                          controller: _cusdecDateCtrl,
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
                          const Gap(16),
                          // ⚠️ The two actions read as a PAIR now.
                          //
                          // "Next" was a full-width 52px slab and "Reset" a
                          // small default OutlinedButton beside it, so the
                          // row looked like one button plus an afterthought.
                          // Both are 44 high, both sized to their content,
                          // and they sit at the end of the form the way the
                          // dialogs' Cancel/Save pair does.
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              SizedBox(
                                height: 44,
                                child: OutlinedButton.icon(
                                  onPressed: _isChecking ? null : _reset,
                                  icon: const Icon(Icons.refresh_rounded,
                                      size: 18),
                                  label: const Text('Reset'),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 20),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(10)),
                                  ),
                                ),
                              ),
                              const Gap(12),
                              SizedBox(
                                height: 44,
                                child: Tooltip(
                                  message: isOfficer
                                      ? 'Package entry/updates are restricted to administrators only'
                                      : '',
                                  child: ElevatedButton.icon(
                                    icon: _isChecking
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white))
                                        : const Icon(Icons.flash_on_rounded,
                                            size: 18),
                                    label: Text(
                                        _isChecking ? 'Processing...' : 'Next'),
                                    style: ElevatedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 28),
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(10)),
                                    ),
                                    onPressed:
                                        _isChecking ? null : _checkPackage,
                                  ),
                                ),
                              ),
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
                        // ⚠️ The package now EXISTS, so the form is editing it
                        // rather than creating it. Without this the officer
                        // could not go back to change a warehouse: Next ran
                        // the duplicate-SR guard, found the package that this
                        // very step had just written, and refused with "A
                        // package with SR ... already exists" — blocking the
                        // edit on the strength of its own save.
                        _isUpdate = true;
                        _loadedSrNumber = pkg.srNumber;
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
  final Map<int, String?> _itemZoneSelections = {};
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
        _itemZoneSelections[i] = cat?.targetZone;
      }
      _loadExistingEntriesIfAny();
    }
  }

  Future<void> _loadExistingEntriesIfAny() async {
    final pkgId = widget.tempPackageData?.id;
    if (pkgId == null || pkgId.isEmpty) return;
    try {
      final existingEntries =
          await ref.read(warehouseServiceProvider).getAllWarehouseEntries();
      final pkgEntries =
          existingEntries.where((e) => e.packageId == pkgId).toList();
      if (pkgEntries.isEmpty || !mounted) return;

      setState(() {
        for (int i = 0; i < (widget.tempPackageItems?.length ?? 0); i++) {
          final item = widget.tempPackageItems![i];
          final entry = pkgEntries
              .where((e) => e.packageItemId == item.id)
              .firstOrNull;
          if (entry != null) {
            _itemWarehouseSelections[i] = entry.warehouseId;
            _itemZoneSelections[i] = entry.zone;
          }
        }
      });
    } catch (_) {}
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
  /// Why the SR number's register does not match the chosen warehouses, or
  /// null when they agree.
  ///
  /// Open areas take `OA` numbers, covered warehouses take `SR`. Returns the
  /// message to show the officer, naming the number it should be.
  /// Where each item was headed before a capacity override sent it elsewhere,
  /// keyed by item index. Empty unless the officer accepted an alternative.
  final Map<int, ({String warehouseId, String? zone, String? reason})>
      _displaced = {};

  Future<String?> _findRegisterMismatch() async {
    final data = widget.tempPackageData;
    final items = widget.tempPackageItems;
    if (data == null || items == null || items.isEmpty) return null;

    final current = docTypeOfSrNumber(data.srNumber);
    // A number whose shape names no register is not this check's business.
    if (current == null) return null;

    final warehouses = await ref.read(warehousesProvider.future);
    for (int i = 0; i < items.length; i++) {
      final id = _itemWarehouseSelections[i];
      if (id == null) continue;
      final w = warehouses.where((x) => x.id == id).firstOrNull;
      if (w == null) continue;
      final needed = docTypeOfWarehouse(code: w.code, name: w.name);
      if (needed == current) continue;

      final should = withSrDocType(data.srNumber, needed);
      return needed == 'OA'
          ? 'Goods ${i + 1} is going to ${w.name}, an open area, so the SR '
              'number must be an OA number. Change the Register to OA '
              '(it becomes $should) and try again.'
          : 'Goods ${i + 1} is going to ${w.name}, a covered warehouse, so '
              'the SR number must be an SR number. Change the Register to SR '
              '(it becomes $should) and try again.';
    }
    return null;
  }

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
      final zoneName = (_itemZoneSelections[i] ?? cat?.targetZone ?? '').trim();
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
          .map((e) => 'Zone ${e.$1.name} (${e.$2} free)')
          .toList();

      problems.add(_CapacityProblem(
        warehouseId: whId,
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
          context.showError('Please select a warehouse for Goods ${i + 1}');
          return;
        }
      }
    }

    if (widget.tempPackageData == null || widget.tempPackageItems == null) {
      context.showError('Package data not found');
      return;
    }

    // ── Register check ──────────────────────────────────────────────────────
    // ⚠️ An SR number's register must match where the goods actually go: goods
    // admitted to an OPEN AREA belong to the OA register, everything else to
    // SR. The form lets the officer pick the register up front and the
    // warehouse later, so the two can disagree — and nothing downstream would
    // ever notice, leaving an `SR/...` number on goods sitting in an open
    // area. The number is on the paper file and the label; it cannot be
    // corrected afterwards without reissuing both.
    //
    // This REFUSES rather than silently renumbering: the number may already
    // have been written down, so which one is wrong is the officer's call.
    final mismatch = await _findRegisterMismatch();
    if (mismatch != null) {
      if (!mounted) return;
      context.showError(mismatch);
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
      final warehouses = await ref.read(warehousesProvider.future);
      final zones = await ref.read(warehouseZonesProvider.future);
      final occupancy = await ref.read(zoneOccupancyProvider.future);
      final cats = ref.read(packageCategoriesProvider).valueOrNull ?? [];

      final result = await showAppDialog<
          ({bool proceed, Map<int, String?> updatedSelections, Map<int, String?> updatedZoneSelections})>(
        context: context,
        builder: (_) => _CapacityBlockedDialog(
          problems: blocked,
          items: widget.tempPackageItems ?? [],
          initialSelections: _itemWarehouseSelections,
          initialZoneSelections: _itemZoneSelections,
          warehouses: warehouses,
          categories: cats,
          zones: zones,
          occupancy: occupancy,
        ),
      );

      if (result == null) return;

      // ⚠️ Captured BEFORE the selections are overwritten below: this is the
      // only moment the app knows where the goods were MEANT to go. A line
      // later the intended warehouse is gone, and it cannot be recovered
      // afterwards by re-reading the category target — targets are editable,
      // so a later edit would rewrite history either way.
      for (final entry in result.updatedSelections.entries) {
        final i = entry.key;
        final was = _itemWarehouseSelections[i];
        final now = entry.value;
        final wasZone = _itemZoneSelections[i];
        final nowZone = result.updatedZoneSelections[i];
        if (was == null || (was == now && wasZone == nowZone)) continue;
        // The problem that displaced THIS item: the one about the zone it
        // was headed for. Worded from the figures the officer was just shown.
        final p = blocked
            .where((b) =>
                b.warehouseId == was &&
                (wasZone == null || b.zoneName == wasZone))
            .firstOrNull;
        _displaced[i] = (
          warehouseId: was,
          zone: wasZone,
          reason: p == null
              ? null
              : '${p.zoneName} was full '
                  '(${p.free} free of ${p.capacity}, ${p.needed} needed)',
        );
      }

      // Update the page state so the warehouse and zone confirmation chips change
      setState(() {
        for (final entry in result.updatedSelections.entries) {
          _itemWarehouseSelections[entry.key] = entry.value;
        }
        for (final entry in result.updatedZoneSelections.entries) {
          _itemZoneSelections[entry.key] = entry.value;
        }
      });

      if (!result.proceed) return;
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

      // Get existing entries to update or avoid duplicates on retry
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

        final warehouseId = _itemWarehouseSelections[i];
        final cat = cats?.where((c) => c.name == tempItem.category).firstOrNull;
        final selectedZone = _itemZoneSelections[i] ?? cat?.targetZone;
        final moved = _displaced[i];

        final existingEntry = pkgExistingEntries
            .where((e) => e.packageItemId == item.id)
            .firstOrNull;

        if (existingEntry != null) {
          // UPDATE existing warehouse entry
          await warehouseService.updateEntry(
            entryId: existingEntry.id,
            warehouseId: warehouseId!,
            zone: selectedZone,
            holdReason:
                (tempItem.reasons != null && tempItem.reasons!.isNotEmpty)
                    ? tempItem.reasons!
                    : 'System Assigned',
            itemCount: tempItem.quantity,
            admittedAt: saved.entryDate,
            movedForSpace: moved != null,
            intendedWarehouseId: moved?.warehouseId,
            intendedZone: moved?.zone,
            movedReason: moved?.reason,
          );
        } else {
          // INSERT new warehouse entry
          await warehouseService.addEntry(
            packageId: saved.id,
            packageItemId:
                item.id.isNotEmpty ? item.id : tempItem.id, // Fallback safely
            warehouseId: warehouseId!,
            zone: selectedZone,
            holdReason:
                (tempItem.reasons != null && tempItem.reasons!.isNotEmpty)
                    ? tempItem.reasons!
                    : 'System Assigned',
            itemCount: tempItem.quantity,
            admittedAt: saved.entryDate,
            movedForSpace: moved != null,
            intendedWarehouseId: moved?.warehouseId,
            intendedZone: moved?.zone,
            movedReason: moved?.reason,
          );
        }
      }

      // Trigger refresh so warehouse entries, packages, and zone capacities immediately update across the app
      ref.read(warehouseRefreshTriggerProvider.notifier).trigger();
      ref.invalidate(zoneOccupancyProvider);
      ref.invalidate(warehousesProvider);
      ref.invalidate(warehouseZonesProvider);

      if (mounted) {
        setState(() => _warehouseSent = true);
        widget.onPackageSaved(saved);
        context.showSuccess('All items sent to respective warehouses');
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

      // ⚠️ The SHARED toast, like every other message in the app: floating,
      // rounded, and gone on its own after 3s. This one was a square
      // full-width bar that sat there until the officer pressed DISMISS, so a
      // failure stayed pinned over the page it had just failed on.
      if (mounted) context.showError(userMessage);
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  /// True when every item on this package is perishable, so there is no
  /// warehouse allocation to make at all.
  ///
  /// ⚠️ EVERY item, not any: a mixed package still has normal goods that need
  /// a warehouse, and hiding the allocation for those would strand them.
  bool get _allPerishable {
    final items = widget.tempPackageItems;
    if (items == null || items.isEmpty) return false;
    return items.every((i) => i.nature == kNaturePerishable);
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
            const Gap(14),
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
                  const Gap(14),
                  if (_savedPackage != null)
                    Column(
                      children: [
                        ElevatedButton.icon(
                          onPressed: () => showAppDialog(
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
            // ⚠️ A package of perishables has no allocation to make. Showing
            // "Assign each item to its destination warehouse" over goods that
            // will never see one told the officer to do something impossible;
            // this says what actually happens to them instead.
            else if (_allPerishable)
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
                  Icon(Icons.eco_rounded,
                          color: context.colors.successGreen, size: 56)
                      .animate()
                      .scale(duration: 400.ms),
                  const Gap(12),
                  Text(
                    'NO WAREHOUSE NEEDED',
                    style: TextStyle(
                      color: context.colors.successGreen,
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                    ),
                    textAlign: TextAlign.center,
                  )
                      .animate()
                      .slideY(begin: 0.3, duration: 300.ms, delay: 200.ms),
                  const Gap(8),
                  Text(
                      'These goods spoil, so they are not stored. They go '
                      'straight to the Perishable Goods list and are sent for '
                      'a Special Tender Sale without waiting out an appeal '
                      'window.',
                      style: TextStyle(
                          color: context.colors.textSecondary, fontSize: 13),
                      textAlign: TextAlign.center),
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
            const Gap(14),
            if (widget.tempPackageItems != null && !_warehouseSent) ...[
              Text('Goods Distribution',
                  style: Theme.of(context).textTheme.titleMedium),
              const Gap(12),
              ...List.generate(widget.tempPackageItems!.length, (index) {
                final item = widget.tempPackageItems![index];
                final cats = ref.watch(packageCategoriesProvider).valueOrNull ?? [];
                final zones = ref.watch(warehouseZonesProvider).valueOrNull ?? [];
                final occupancy = ref.watch(zoneOccupancyProvider).valueOrNull ?? {};
                final cat = cats.where((c) => c.name == item.category).firstOrNull;
                final defaultZoneName = (cat?.targetZone ?? '').trim();
                final currentZoneName = (_itemZoneSelections[index] ?? defaultZoneName).trim();
                final selectedWarehouseId = _itemWarehouseSelections[index];

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
                        const Gap(10),
                        warehousesAsync.when(
                          loading: () => const LinearProgressIndicator(),
                          error: (e, _) {
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
                          data: (ws) {
                            // Location summary badge for currently selected warehouse + zone
                            Widget? locationBadge;
                            if (selectedWarehouseId != null) {
                              final selectedWh = ws
                                  .where((w) => w.id == selectedWarehouseId)
                                  .firstOrNull;
                              final whDisplay = selectedWh != null
                                  ? _formatWarehouseName(selectedWh.name)
                                  : selectedWarehouseId;
                              final zoneObj = currentZoneName.isNotEmpty
                                  ? zones
                                      .where((z) =>
                                          z.warehouseId == selectedWarehouseId &&
                                          z.name.trim().toLowerCase() ==
                                              currentZoneName.toLowerCase())
                                      .firstOrNull
                                  : null;
                              final occ = zoneObj != null
                                  ? occupancy[zoneObj.id]
                                  : null;
                              final free = occ?.free ?? zoneObj?.capacity ?? 0;
                              final isFull = zoneObj != null && free <= 0;

                              locationBadge = Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: isFull
                                      ? context.colors.dangerRed
                                          .withOpacity(0.12)
                                      : context.colors.primaryGold
                                          .withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: isFull
                                        ? context.colors.dangerRed
                                            .withOpacity(0.4)
                                        : context.colors.primaryGold
                                            .withOpacity(0.3),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      isFull
                                          ? Icons.warning_amber_rounded
                                          : Icons.route_rounded,
                                      size: 14,
                                      color: isFull
                                          ? context.colors.dangerRed
                                          : context.colors.primaryGold,
                                    ),
                                    const Gap(6),
                                    Text(
                                      whDisplay +
                                          (currentZoneName.isNotEmpty
                                              ? ' | Zone $currentZoneName'
                                              : '') +
                                          (zoneObj != null
                                              ? (isFull
                                                  ? ' (FULL)'
                                                  : ' ($free free)')
                                              : ''),
                                      style: TextStyle(
                                        color: isFull
                                            ? context.colors.dangerRed
                                            : context.colors.primaryGold,
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }

                            final selectedWhZones = selectedWarehouseId != null
                                ? zones
                                    .where((z) =>
                                        z.warehouseId == selectedWarehouseId)
                                    .toList()
                                : <WarehouseZoneModel>[];

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (locationBadge != null) locationBadge,
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: ws.map((w) {
                                    final isSelected =
                                        _itemWarehouseSelections[index] == w.id;
                                    final whName =
                                        _formatWarehouseName(w.name)
                                            .replaceFirst('GL1/SR/', '');

                                    return InkWell(
                                      borderRadius: BorderRadius.circular(8),
                                      onTap: () => setState(() {
                                        _itemWarehouseSelections[index] = w.id;
                                        final wZones = zones
                                            .where((z) => z.warehouseId == w.id)
                                            .toList();
                                        if (wZones.isNotEmpty) {
                                          final curZ = _itemZoneSelections[index] ??
                                              defaultZoneName;
                                          final match = wZones
                                              .where((z) =>
                                                  z.name.toLowerCase() ==
                                                  curZ.toLowerCase())
                                              .firstOrNull;
                                          if (match != null) {
                                            _itemZoneSelections[index] =
                                                match.name;
                                          } else {
                                            _itemZoneSelections[index] =
                                                wZones.first.name;
                                          }
                                        }
                                      }),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 8),
                                        decoration: BoxDecoration(
                                          color: isSelected
                                              ? context.colors.primaryGold
                                                  .withOpacity(0.15)
                                              : context.colors.surfaceDark,
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          border: Border.all(
                                            color: isSelected
                                                ? context.colors.primaryGold
                                                : context.colors.borderColor,
                                            width: isSelected ? 1.5 : 1,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.warehouse_outlined,
                                              size: 14,
                                              color: isSelected
                                                  ? context.colors.primaryGold
                                                  : context.colors.textMuted,
                                            ),
                                            const Gap(6),
                                            Text(
                                              whName,
                                              style: TextStyle(
                                                color: isSelected
                                                    ? context.colors.primaryGold
                                                    : context
                                                        .colors.textSecondary,
                                                fontSize: 12,
                                                fontWeight: isSelected
                                                    ? FontWeight.bold
                                                    : FontWeight.normal,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                                if (selectedWhZones.isNotEmpty) ...[
                                  const Gap(10),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 6,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      Text(
                                        'Zone:',
                                        style: TextStyle(
                                          color: context.colors.textMuted,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      ...selectedWhZones.map((z) {
                                        final isZoneSelected =
                                            currentZoneName.toLowerCase() ==
                                                z.name.trim().toLowerCase();
                                        final occ = occupancy[z.id];
                                        final free = occ?.free ?? z.capacity;
                                        final isFull = free <= 0;

                                        return InkWell(
                                          borderRadius:
                                              BorderRadius.circular(6),
                                          onTap: () => setState(() =>
                                              _itemZoneSelections[index] =
                                                  z.name),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 9, vertical: 5),
                                            decoration: BoxDecoration(
                                              color: isZoneSelected
                                                  ? context.colors.primaryGold
                                                      .withOpacity(0.18)
                                                  : context.colors.surfaceDark,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              border: Border.all(
                                                color: isZoneSelected
                                                    ? context.colors.primaryGold
                                                    : (isFull
                                                        ? context
                                                            .colors.dangerRed
                                                            .withOpacity(0.4)
                                                        : context
                                                            .colors.borderColor),
                                                width: isZoneSelected ? 1.5 : 1,
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  Icons.grid_view_rounded,
                                                  size: 11,
                                                  color: isZoneSelected
                                                      ? context
                                                          .colors.primaryGold
                                                      : (isFull
                                                          ? context
                                                              .colors.dangerRed
                                                          : context
                                                              .colors.textMuted),
                                                ),
                                                const Gap(5),
                                                Text(
                                                  'Zone ${z.name}' +
                                                      (isFull
                                                          ? ' (FULL)'
                                                          : ' ($free free)'),
                                                  style: TextStyle(
                                                    color: isZoneSelected
                                                        ? context
                                                            .colors.primaryGold
                                                        : (isFull
                                                            ? context.colors
                                                                .dangerRed
                                                            : context.colors
                                                                .textSecondary),
                                                    fontSize: 11,
                                                    fontWeight: isZoneSelected
                                                        ? FontWeight.bold
                                                        : FontWeight.normal,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      }),
                                    ],
                                  ),
                                ],
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
            const Gap(16),
            if (!_warehouseSent)
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.colors.primaryGold,
                    foregroundColor: context.colors.primaryNavy,
                    elevation: 1,
                    shadowColor: context.colors.primaryGold.withOpacity(0.3),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                  ),
                  icon: _isSending
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: context.colors.primaryNavy,
                          ),
                        )
                      : const Icon(Icons.send_rounded, size: 18),
                  label: Text(
                    _isSending
                        ? 'Saving Entries...'
                        : 'Complete & Send to Warehouses',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
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
          Text('QR Code Generate',
              style: Theme.of(context).textTheme.titleLarge),
          const Gap(14),
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
                const Gap(14),
                if (package != null)
                  ElevatedButton.icon(
                    onPressed: () => showAppDialog(
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

  /// Normal or perishable -- see [kGoodsNatures]. Perishable goods skip the
  /// warehouse and the appeal window entirely, so this decides the whole path
  /// the item takes and is asked before anything else about it.
  String nature = kNatureNormal;
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
                  ),
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
                  ),
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
                ),
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
                  ),
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
            // Asked before the status, because it decides whether a status is
            // asked at all: a perishable item never reaches a warehouse and
            // never sits out an appeal window, so Detain / Forfeit describe
            // nothing that will happen to it.
            Expanded(
              flex: 2,
              child: StyledDropdownFormField<String>(
                label: 'Nature *',
                menuWidth: 220,
                value: widget.row.nature,
                options: [
                  for (final e in kGoodsNatures.entries)
                    StyledDropdownOption(e.key, e.value),
                ],
                onChanged: (v) {
                  setState(() {
                    widget.row.nature = v ?? kNatureNormal;
                    if (widget.row.nature == kNaturePerishable) {
                      // Its own status, so every screen that groups by status
                      // has somewhere to put it, and none of the disposition
                      // pages claim it by mistake.
                      widget.row.status = 'Perishable';
                      widget.row.selectedReasons
                        ..clear()
                        ..add(null);
                    } else if (widget.row.status == 'Perishable') {
                      widget.row.status = 'Detain';
                      widget.row.selectedReasons
                        ..clear()
                        ..add(null);
                    }
                  });
                  widget.onChanged();
                },
              ),
            ),
            if (widget.row.nature != kNaturePerishable) ...[
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
                      widget.row.status = v!;
                      // ⚠️ Drop any activity the NEW status does not offer.
                      //
                      // Detain and the disposal statuses have different lists,
                      // so a choice made under one can be invalid under the
                      // other. Left in place it would stay on screen but not be
                      // in the dropdown's options -- the field renders empty
                      // while the row still holds the old value, and that value
                      // is what gets saved. Anything the new list DOES contain
                      // is kept, so switching Forfeit to Abandoned costs the
                      // officer nothing.
                      final allowed =
                          postStatusActivitiesFor(widget.row.status);
                      for (var i = 0;
                          i < widget.row.selectedReasons.length;
                          i++) {
                        if (!allowed.contains(widget.row.selectedReasons[i])) {
                          widget.row.selectedReasons[i] = null;
                        }
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
            ],
            // ⚠️ Category exists to route goods to a WAREHOUSE ZONE. A
            // perishable never reaches a warehouse, so the field has nothing
            // to decide -- and the zone-capacity hint below it would report
            // space the goods will never occupy.
            if (widget.row.nature != kNaturePerishable) ...[
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

                        final label =
                            isFull ? '${c.name} [Zone $zn FULL 🔴]' : c.name;
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
                    labelText: 'Value',
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
                  final t = (v ?? '').trim();
                  if (t.isEmpty) return null; // defaults to 0
                  final parsed = double.tryParse(t);
                  if (parsed == null) return 'Enter a valid number';
                  if (parsed < 0) return 'Cannot be negative';
                  return null;
                },
                onChanged: (_) => widget.onChanged(),
              ),
            ),
          ],
        ),
        const Gap(12),
        // The zone-capacity hint follows the Category field, so it goes with
        // it: there is no zone to report on for goods that never enter one.
        if (widget.row.nature != kNaturePerishable)
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
                                z.name.trim().toLowerCase() == zn.toLowerCase())
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
                                color:
                                    context.colors.dangerRed.withOpacity(0.4),
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
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
            // ⚠️ The status decides the list — EXCEPT for a perishable.
            //
            // A Detain item is waiting on something (a licence, a valuation,
            // an inquiry); a Forfeit / Abandoned / Other item is on its way to
            // being disposed of. Those are different questions with different
            // answers, and offering all of them under every status is how an
            // officer ends up recording "Pending Licence" against goods that
            // have already been forfeited.
            //
            // A PERISHABLE is the exception, and the reason the filter was
            // removed wholesale in the first place: it has no status of its
            // own to choose from ('Perishable' is not in either group), so a
            // filtered list left it with nothing to pick. It gets the whole
            // list instead — which is also what the perishable pages filter
            // against, see kAllPostStatusActivities there.
            final activities = widget.row.nature == kNaturePerishable
                ? kAllPostStatusActivities
                : postStatusActivitiesFor(widget.row.status);
            return SizedBox(
              width: 380,
              child: Row(
                children: [
                  Expanded(
                    child: StyledDropdownFormField<String>(
                      label: 'Activity ${rIdx + 1} *',
                      menuWidth: 300,
                      fillColor: context.colors.fieldFill,
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
  final String warehouseId;
  final String zoneName;

  /// Items this consignment wants to put in the zone.
  final int needed;

  /// Room actually left.
  final int free;
  final int capacity;

  /// Zones in the SAME warehouse that could take the whole lot.
  final List<String> alternatives;

  const _CapacityProblem({
    required this.warehouseId,
    required this.zoneName,
    required this.needed,
    required this.free,
    required this.capacity,
    this.alternatives = const [],
  });
}

/// Stops a consignment that does not fit, and allows allocating goods directly
/// to alternative warehouses/zones with real-time capacity reduction.
class _CapacityBlockedDialog extends StatefulWidget {
  final List<_CapacityProblem> problems;
  final List<PackageItem> items;
  final Map<int, String?> initialSelections;
  final Map<int, String?> initialZoneSelections;
  final List<WarehouseModel> warehouses;
  final List<PackageCategory> categories;
  final List<WarehouseZoneModel> zones;
  final Map<String, ZoneOccupancy> occupancy;

  const _CapacityBlockedDialog({
    super.key,
    required this.problems,
    required this.items,
    required this.initialSelections,
    required this.initialZoneSelections,
    required this.warehouses,
    required this.categories,
    required this.zones,
    required this.occupancy,
  });

  @override
  State<_CapacityBlockedDialog> createState() => _CapacityBlockedDialogState();
}

class _CapacityBlockedDialogState extends State<_CapacityBlockedDialog> {
  late Map<int, String?> _warehouseSelections;
  late Map<int, String?> _zoneSelections;

  @override
  void initState() {
    super.initState();
    _warehouseSelections = Map<int, String?>.from(widget.initialSelections);
    _zoneSelections = Map<int, String?>.from(widget.initialZoneSelections);
  }

  String _cleanWhName(String name) {
    if (name.contains('GL1/SR/')) return name;
    String cleanName =
        name.replaceAll(RegExp(r'^SR\s+', caseSensitive: false), '');
    return 'GL1/SR/$cleanName';
  }

  @override
  Widget build(BuildContext context) {
    final red = context.colors.dangerRed;
    final green = context.colors.successGreen;

    // Precompute dropdown options of all warehouse + zone combinations
    final List<StyledDropdownOption<String>> dropdownOptions = [];
    for (final w in widget.warehouses) {
      final whZones =
          widget.zones.where((z) => z.warehouseId == w.id).toList();
      final cleanName = _cleanWhName(w.name);
      if (whZones.isEmpty) {
        dropdownOptions.add(StyledDropdownOption('${w.id}|', cleanName));
      } else {
        for (final z in whZones) {
          final occ = widget.occupancy[z.id];
          final freeSpace = occ?.free ?? z.capacity;
          final label = '$cleanName • Zone ${z.name} ($freeSpace free)';
          dropdownOptions.add(StyledDropdownOption('${w.id}|${z.name}', label));
        }
      }
    }

    return StyledFormDialog(
      yard: true,
      label: 'WAREHOUSE CAPACITY',
      title: widget.problems.length == 1
          ? 'Zone ${widget.problems.first.zoneName} Capacity Allocation'
          : 'Warehouse Capacity Allocation',
      icon: Icons.warehouse_rounded,
      headerAccentColor: context.colors.primaryGold,
      width: 680,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('Cancel'),
        ),
        const Gap(8),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: red,
            side: BorderSide(color: red.withOpacity(0.6)),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          ),
          icon: const Icon(Icons.warning_amber_rounded, size: 16),
          label: const Text('Admit anyway'),
          onPressed: () => Navigator.pop(
            context,
            (
              proceed: true,
              updatedSelections: _warehouseSelections,
              updatedZoneSelections: _zoneSelections
            ),
          ),
        ),
        const Gap(8),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: context.colors.primaryGold,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          ),
          icon: const Icon(Icons.check_circle_rounded, size: 16),
          label: const Text('Apply Changes & Proceed'),
          onPressed: () => Navigator.pop(
            context,
            (
              proceed: true,
              updatedSelections: _warehouseSelections,
              updatedZoneSelections: _zoneSelections
            ),
          ),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final p in widget.problems) ...[
            Builder(builder: (context) {
              // Find items contributing to this problem zone
              final contributingIndices = <int>[];
              int currentNeeded = 0;

              for (int i = 0; i < widget.items.length; i++) {
                final item = widget.items[i];
                final itemCategory = item.category?.trim().toLowerCase() ?? '';
                final cat = widget.categories
                    .where((c) => c.name.trim().toLowerCase() == itemCategory)
                    .firstOrNull;
                final defaultTargetZone = (cat?.targetZone ?? '').trim();

                final curWh = _warehouseSelections[i];
                final curZone =
                    (_zoneSelections[i] ?? defaultTargetZone).trim();

                final initWh = widget.initialSelections[i];
                final initZone =
                    (widget.initialZoneSelections[i] ?? defaultTargetZone).trim();

                final wasInProblem = initWh == p.warehouseId &&
                    initZone.toLowerCase() == p.zoneName.toLowerCase();
                final isCurrentlyInProblem = curWh == p.warehouseId &&
                    curZone.toLowerCase() == p.zoneName.toLowerCase();

                if (wasInProblem || isCurrentlyInProblem) {
                  contributingIndices.add(i);
                }

                if (isCurrentlyInProblem) {
                  currentNeeded += item.quantity;
                }
              }

              final overBy = currentNeeded - p.free;
              final isOver = overBy > 0;

              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: context.colors.cardDark,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isOver
                        ? red.withOpacity(0.4)
                        : green.withOpacity(0.4),
                    width: 1.2,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Zone Header Banner
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: isOver
                            ? red.withOpacity(0.12)
                            : green.withOpacity(0.12),
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(11)),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isOver
                                ? Icons.warning_amber_rounded
                                : Icons.check_circle_rounded,
                            color: isOver ? red : green,
                            size: 20,
                          ),
                          const Gap(10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Zone ${p.zoneName}',
                                  style: TextStyle(
                                    color: context.colors.textPrimary,
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  'Room left: ${p.free} of ${p.capacity} items | Currently assigned: $currentNeeded items',
                                  style: TextStyle(
                                    color: context.colors.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: isOver
                                  ? red.withOpacity(0.2)
                                  : green.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              isOver
                                  ? 'Over by $overBy items'
                                  : 'Fits (${p.free - currentNeeded} room left)',
                              style: TextStyle(
                                color: isOver ? red : green,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Goods rows
                    Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Assign goods to alternative warehouses or zones to reduce zone overflow:',
                            style: TextStyle(
                              color: context.colors.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Gap(10),
                          for (final idx in contributingIndices) ...[
                            Builder(builder: (context) {
                              final item = widget.items[idx];
                              final selectedWh = _warehouseSelections[idx];
                              final itemCategory =
                                  item.category?.trim().toLowerCase() ?? '';
                              final cat = widget.categories
                                  .where((c) =>
                                      c.name.trim().toLowerCase() ==
                                      itemCategory)
                                  .firstOrNull;
                              final defaultTargetZone =
                                  (cat?.targetZone ?? '').trim();
                              final curZone =
                                  (_zoneSelections[idx] ?? defaultTargetZone)
                                      .trim();
                              final currentKey =
                                  '${selectedWh ?? ""}|$curZone';
                              final hasMatch = dropdownOptions
                                  .any((opt) => opt.value == currentKey);
                              final effectiveValue = hasMatch
                                  ? currentKey
                                  : (dropdownOptions.any((opt) => opt.value
                                          .startsWith('${selectedWh ?? ""}|'))
                                      ? dropdownOptions
                                          .firstWhere((opt) => opt.value
                                              .startsWith(
                                                  '${selectedWh ?? ""}|'))
                                          .value
                                      : (dropdownOptions.isNotEmpty
                                          ? dropdownOptions.first.value
                                          : null));

                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  color: context.colors.surfaceDark,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                      color: context.colors.borderColor),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      flex: 3,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Goods ${idx + 1}: ${item.itemName}',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 13,
                                            ),
                                          ),
                                          const Gap(2),
                                          Text(
                                            '${item.quantity} ${item.unitOfMeasure} • ${item.category ?? "General"}',
                                            style: TextStyle(
                                              color: context.colors.textMuted,
                                              fontSize: 11.5,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Gap(12),
                                    Expanded(
                                      flex: 4,
                                      child: StyledDropdownFormField<String>(
                                        value: effectiveValue,
                                        label: 'Warehouse & Zone',
                                        floatingLabelBehavior:
                                            FloatingLabelBehavior.never,
                                        menuWidth: 320,
                                        options: dropdownOptions,
                                        onChanged: (newKey) {
                                          if (newKey != null) {
                                            final parts = newKey.split('|');
                                            final newWhId = parts[0];
                                            final newZoneName =
                                                parts.length > 1 ? parts[1] : '';
                                            setState(() {
                                              _warehouseSelections[idx] =
                                                  newWhId;
                                              _zoneSelections[idx] =
                                                  newZoneName.isNotEmpty
                                                      ? newZoneName
                                                      : null;
                                            });
                                          }
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ],
                          if (p.alternatives.isNotEmpty && isOver) ...[
                            const Gap(8),
                            Text(
                              'Other zones in this warehouse with room: ${p.alternatives.join(", ")}',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontStyle: FontStyle.italic,
                                color: context.colors.textMuted,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
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
