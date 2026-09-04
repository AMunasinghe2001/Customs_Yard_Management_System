import 'dart:convert';
import '../core/holidays.dart';

/// Reads a timestamp column that may arrive as either a `DateTime` or a String.
///
/// ⚠️ This is the seam between the two database layers. Supabase returned JSON,
/// so every timestamp arrived as an ISO **String** and the models cast it with
/// `json['x'] as String`. The local PostgreSQL driver decodes `timestamptz`
/// into a real **DateTime** — so that cast throws
/// `type 'DateTime' is not a subtype of type 'String'`, and it throws at
/// SIGN-IN, before any screen renders.
///
/// Returns local time, matching the `.toLocal()` the models always applied.
DateTime? parseDbDate(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value.toLocal();
  if (value is String) {
    if (value.trim().isEmpty) return null;
    return DateTime.tryParse(value)?.toLocal();
  }
  return null;
}

/// [parseDbDate] for a NOT NULL column, falling back to the epoch rather than
/// throwing — a row that somehow lacks a created_at should still render.
DateTime parseDbDateRequired(Object? value) =>
    parseDbDate(value) ?? DateTime.fromMillisecondsSinceEpoch(0);

/// Reads a numeric column that may arrive as a num OR a String.
///
/// ⚠️ The same seam as [parseDbDate]. Supabase serialised `numeric` to a JSON
/// number, so the models cast `json['x'] as num?`. The PostgreSQL driver
/// returns `numeric` as a **String** — deliberately, since a `numeric(12,2)`
/// cannot always survive a round trip through a double — so that cast throws
/// `type 'String' is not a subtype of type 'num?'`.
///
/// Money here is rupees to two decimals, well inside a double's exact range,
/// so converting is safe. Returns null when the value is absent or unparseable
/// rather than throwing, so one odd row cannot blank a whole screen.
double? parseDbNum(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  if (value is String) {
    final t = value.trim();
    if (t.isEmpty) return null;
    return double.tryParse(t);
  }
  return null;
}

/// [parseDbNum] for an integer column (`int4`, `int8`, and counts stored as
/// `numeric`). Truncates toward zero, matching the old `as int?` behaviour.
int? parseDbInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) {
    final t = value.trim();
    if (t.isEmpty) return null;
    return int.tryParse(t) ?? double.tryParse(t)?.toInt();
  }
  return null;
}

class PackageModel {
  final String id;
  final String srNumber;
  // For "Old Entry" registrations only: the SR number the goods carried in the
  // previous/legacy register. NULL for normal (new) registrations.
  final String? oldSrNumber;
  final String? caseNumber;
  final String originCountry;
  final double declaredValue;
  final double weightKg;
  final int totalItemCount;
  final String? description;
  final String? containerNumber;

  /// Deposit the declarant lodges against the cost of destroying the goods.
  /// PACKAGE-level (one figure per SR), not per goods item.
  final double? destroyingDeposit;

  final String consigneeName;
  final String? consigneeNic;
  final String? consigneeAddress;
  final String? consigneePhone;
  final String? declarantName;
  final String? cusdecNo;
  final String? cusdecDate;
  final DateTime? entryDate;
  final String? reason;
  final String status;
  final String? inspectedBy;
  final String? inspectedByName;
  final String? inspectedByBadge;
  final DateTime? inspectedAt;
  final DateTime? clearedAt;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<PackageItem> items;
  final List<WarehouseEntryModel> warehouseEntries;

  const PackageModel({
    required this.id,
    required this.srNumber,
    this.oldSrNumber,
    this.caseNumber,
    this.originCountry = '',
    this.declaredValue = 0,
    this.weightKg = 0,
    this.totalItemCount = 1,
    this.description,
    this.containerNumber,
    this.destroyingDeposit,
    required this.consigneeName,
    this.consigneeNic,
    this.consigneeAddress,
    this.consigneePhone,
    this.declarantName,
    this.cusdecNo,
    this.cusdecDate,
    this.entryDate,
    this.reason,
    required this.status,
    this.inspectedBy,
    this.inspectedByName,
    this.inspectedByBadge,
    this.inspectedAt,
    this.clearedAt,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
    this.items = const [],
    this.warehouseEntries = const [],
  });

  /// Total inner-item count across all items — Cartons expand to their inner
  /// (per-carton contents) count, not the carton count. Falls back to the
  /// stored [totalItemCount] when the item list isn't loaded.
  int get effectiveItemCount => items.isEmpty
      ? totalItemCount
      : items.fold(0, (s, i) => s + i.effectiveQuantity);

  /// Combined cusdec number & date display
  String? get cusdecNoDate {
    if (cusdecNo == null && cusdecDate == null) return null;
    final no = cusdecNo ?? '';
    final date = cusdecDate ?? '';
    if (no.isEmpty && date.isEmpty) return null;
    if (date.isEmpty) return no;
    if (no.isEmpty) return date;
    return '$no / $date';
  }

  factory PackageModel.fromJson(Map<String, dynamic> json) {
    return PackageModel(
      id: json['id'] as String,
      srNumber: json['sr_number'] as String,
      oldSrNumber: json['old_sr_number'] as String?,
      caseNumber: json['case_number'] as String?,
      originCountry: json['origin_country'] as String? ?? '',
      declaredValue: parseDbNum(json['declared_value']) ?? 0,
      weightKg: parseDbNum(json['weight_kg']) ?? 0,
      totalItemCount: parseDbInt(json['total_item_count']) ?? 1,
      description: json['description'] as String?,
      containerNumber: json['container_number'] as String?,
      destroyingDeposit: parseDbNum(json['destroying_deposit']),
      consigneeName: json['consignee_name'] as String,
      consigneeNic: json['consignee_nic'] as String?,
      consigneeAddress: json['consignee_address'] as String?,
      consigneePhone: json['consignee_phone'] as String?,
      declarantName: json['declarant_name'] as String?,
      cusdecNo: json['cusdec_no'] as String?,
      cusdecDate: json['cusdec_date'] as String?,
      entryDate: parseDbDate(json['entry_date']),
      reason: json['reason'] as String?,
      status: json['status'] as String? ?? 'pending',
      inspectedBy: json['inspected_by'] as String?,
      inspectedByName: json['profiles'] != null
          ? json['profiles']['full_name'] as String?
          : null,
      inspectedByBadge: json['profiles'] != null
          ? json['profiles']['badge_number'] as String?
          : null,
      inspectedAt: parseDbDate(json['inspected_at']),
      clearedAt: parseDbDate(json['cleared_at']),
      notes: json['notes'] as String?,
      createdAt: parseDbDateRequired(json['created_at']),
      updatedAt: parseDbDateRequired(json['updated_at']),
      items: (json['package_items'] as List<dynamic>?)
              ?.map((e) => PackageItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      warehouseEntries: (json['warehouse_entries'] as List<dynamic>?)
              ?.map((e) =>
                  WarehouseEntryModel.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toInsertJson() {
    return {
      'sr_number': srNumber,
      'old_sr_number': oldSrNumber,
      'case_number': caseNumber,
      'origin_country': originCountry,
      'declared_value': declaredValue,
      'weight_kg': weightKg,
      'total_item_count': totalItemCount,
      'description': description,
      'container_number': containerNumber,
      'destroying_deposit': destroyingDeposit,
      'consignee_name': consigneeName,
      'consignee_nic': consigneeNic,
      'consignee_address': consigneeAddress,
      'consignee_phone': consigneePhone,
      'declarant_name': declarantName,
      'cusdec_no': cusdecNo,
      'cusdec_date': cusdecDate,
      'entry_date': entryDate?.toIso8601String(),
      'reason': reason,
      'status': status,
      'notes': notes,
      'inspected_by': inspectedBy,
      'inspected_at': inspectedAt?.toIso8601String(),
    };
  }

  PackageModel copyWith({
    String? srNumber,
    String? oldSrNumber,
    String? caseNumber,
    String? originCountry,
    double? declaredValue,
    double? weightKg,
    int? totalItemCount,
    String? description,
    String? containerNumber,
    double? destroyingDeposit,
    String? consigneeName,
    String? consigneeNic,
    String? consigneeAddress,
    String? consigneePhone,
    String? declarantName,
    String? cusdecNo,
    String? cusdecDate,
    DateTime? entryDate,
    String? reason,
    String? status,
    String? inspectedBy,
    String? inspectedByName,
    String? inspectedByBadge,
    DateTime? inspectedAt,
    DateTime? clearedAt,
    String? notes,
    List<PackageItem>? items,
    List<WarehouseEntryModel>? warehouseEntries,
  }) {
    return PackageModel(
      id: id,
      srNumber: srNumber ?? this.srNumber,
      oldSrNumber: oldSrNumber ?? this.oldSrNumber,
      caseNumber: caseNumber ?? this.caseNumber,
      originCountry: originCountry ?? this.originCountry,
      declaredValue: declaredValue ?? this.declaredValue,
      weightKg: weightKg ?? this.weightKg,
      totalItemCount: totalItemCount ?? this.totalItemCount,
      description: description ?? this.description,
      containerNumber: containerNumber ?? this.containerNumber,
      destroyingDeposit: destroyingDeposit ?? this.destroyingDeposit,
      consigneeName: consigneeName ?? this.consigneeName,
      consigneeNic: consigneeNic ?? this.consigneeNic,
      consigneeAddress: consigneeAddress ?? this.consigneeAddress,
      consigneePhone: consigneePhone ?? this.consigneePhone,
      declarantName: declarantName ?? this.declarantName,
      cusdecNo: cusdecNo ?? this.cusdecNo,
      cusdecDate: cusdecDate ?? this.cusdecDate,
      entryDate: entryDate ?? this.entryDate,
      reason: reason ?? this.reason,
      status: status ?? this.status,
      inspectedBy: inspectedBy ?? this.inspectedBy,
      inspectedByName: inspectedByName ?? this.inspectedByName,
      inspectedByBadge: inspectedByBadge ?? this.inspectedByBadge,
      inspectedAt: inspectedAt ?? this.inspectedAt,
      clearedAt: clearedAt ?? this.clearedAt,
      notes: notes ?? this.notes,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      items: items ?? this.items,
      warehouseEntries: warehouseEntries ?? this.warehouseEntries,
    );
  }

  bool get isCleared => status == 'cleared';
  bool get isHeld => status == 'held';
  bool get isPending => status == 'pending';
  bool get isConfiscated => status == 'confiscated';

  bool get isReturned =>
      warehouseEntries.isNotEmpty && warehouseEntries.any((e) => e.isReturned);

  DateTime? get returnedAt {
    if (warehouseEntries.isEmpty) return null;
    final returnedEntries = warehouseEntries
        .where((e) => e.isReturned && e.returnedAt != null)
        .toList();
    if (returnedEntries.isEmpty) return null;
    return returnedEntries
        .map((e) => e.returnedAt!)
        .reduce((a, b) => a.isAfter(b) ? a : b);
  }

  /// Whether a SPECIFIC package item has genuinely been forfeited — used to
  /// filter multi-item packages whose forfeited_packages row is package-level
  /// (item_id == null) so it doesn't blanket-cover items that are still on
  /// Detain. An item counts as forfeited when EITHER its live status is a
  /// forfeit status, OR it has a warehouse entry tagged "[FORFEIT" / "[CONFISCAT".
  /// The single source of truth for "which items of this package are forfeited",
  /// shared by the yard Forfeited table and the Appeal Directorate list.
  bool isItemForfeited(String itemId) {
    final item = items.where((i) => i.id == itemId).firstOrNull;
    final st = (item?.status ?? '').trim().toLowerCase();
    if (st == 'forfeit' ||
        st == 'forfeited' ||
        st == 'forfiet' ||
        st == 'confiscated') {
      return true;
    }
    return warehouseEntries.any((e) {
      if (e.packageItemId != itemId || !e.isReturned) return false;
      final n = (e.returnNotes ?? '').trim().toUpperCase();
      return n.startsWith('[FORFEIT') || n.startsWith('[CONFISCAT');
    });
  }

  /// The subset of item ids that are genuinely forfeited (see [isItemForfeited]).
  List<String> get forfeitedItemIds =>
      items.where((i) => isItemForfeited(i.id)).map((i) => i.id).toList();
}

class PackageItem {
  final String id;
  final String packageId;
  final String itemName;
  final String? goodsDescription;

  /// [kNatureNormal] or [kNaturePerishable] -- see [kGoodsNatures].
  final String nature;
  final int quantity;
  final String unitOfMeasure;
  final String? unitOther;
  // Cartons only: what each carton holds (inner unit type) and how many.
  final String? innerUnit;
  final int? innerQuantity;
  final double unitValue;
  final String? hsCode;
  final String? category;
  final bool isProhibited;
  final String status; // Added status here
  final String? reasons;
  final String? notes;

  const PackageItem({
    required this.id,
    required this.packageId,
    required this.itemName,
    this.goodsDescription,
    this.nature = kNatureNormal,
    required this.quantity,
    this.unitOfMeasure = 'Pieces',
    this.unitOther,
    this.innerUnit,
    this.innerQuantity,
    this.unitValue = 0,
    this.hsCode,
    this.category,
    this.isProhibited = false,
    this.status = 'pending', // Default to pending
    this.reasons,
    this.notes,
  });

  // Cartons registration is stored "inverted": [quantity]/[unitOfMeasure] hold
  // the INNER contents (e.g. 1176 Pieces) — the operational count used across
  // the whole app (warehouse, release, disposal, totals) — while the outer
  // packaging (e.g. 20 Cartons) is kept in [innerUnit]/[innerQuantity] purely
  // for display. So no special-casing is needed for counts: quantity already
  // reflects the goods inside.

  /// The operational item count (already the inner contents count).
  int get effectiveQuantity => quantity;

  /// The unit that [effectiveQuantity] is counted in.
  String get effectiveUnit => unitOfMeasure;

  /// Packaging note, e.g. "20 Cartons" (null when the item has no packaging
  /// wrapper). Read from [innerUnit]/[innerQuantity].
  String? get packagingLabel => (innerUnit != null &&
          innerUnit!.trim().isNotEmpty &&
          innerQuantity != null &&
          innerQuantity! > 0)
      ? '$innerQuantity $innerUnit'
      : null;

  factory PackageItem.fromJson(Map<String, dynamic> json) {
    return PackageItem(
      id: json['id'] as String,
      packageId: json['package_id'] as String,
      itemName: json['item_name'] as String,
      goodsDescription: json['goods_description'] as String?,
      // Defaulted rather than required: a row written before the column
      // existed carries no nature, and it is a normal one.
      nature: (json['nature'] as String?)?.trim().isNotEmpty == true
          ? json['nature'] as String
          : kNatureNormal,
      quantity: (parseDbInt(json['quantity']) ?? 0),
      unitOfMeasure: json['unit_of_measure'] as String? ?? 'Pieces',
      unitOther: json['unit_other'] as String?,
      innerUnit: json['inner_unit'] as String?,
      innerQuantity: parseDbInt(json['inner_quantity']),
      unitValue: parseDbNum(json['unit_value']) ?? 0,
      hsCode: json['hs_code'] as String?,
      category: json['category'] as String?,
      isProhibited: json['is_prohibited'] as bool? ?? false,
      status: json['status'] as String? ?? 'pending',
      reasons: json['reasons'] as String?,
      notes: json['notes'] as String?,
    );
  }

  Map<String, dynamic> toInsertJson(String pkgId) {
    return {
      if (id.isNotEmpty) 'id': id,
      'package_id': pkgId,
      'item_name': itemName,
      'goods_description': goodsDescription,
      'nature': nature,
      'quantity': quantity,
      'unit_of_measure': unitOfMeasure,
      'unit_other': unitOther,
      'inner_unit': innerUnit,
      'inner_quantity': innerQuantity,
      'unit_value': unitValue,
      'hs_code': hsCode,
      'category': category,
      'is_prohibited': isProhibited,
      'status': status,
      'reasons': reasons,
      'notes': notes,
    };
  }

  PackageItem copyWith({
    String? id,
    String? packageId,
    String? itemName,
    String? goodsDescription,
    String? nature,
    int? quantity,
    String? unitOfMeasure,
    String? unitOther,
    String? innerUnit,
    int? innerQuantity,
    double? unitValue,
    String? hsCode,
    String? category,
    bool? isProhibited,
    String? status,
    String? reasons,
    String? notes,
  }) {
    return PackageItem(
      id: id ?? this.id,
      packageId: packageId ?? this.packageId,
      itemName: itemName ?? this.itemName,
      goodsDescription: goodsDescription ?? this.goodsDescription,
      nature: nature ?? this.nature,
      quantity: quantity ?? this.quantity,
      unitOfMeasure: unitOfMeasure ?? this.unitOfMeasure,
      unitOther: unitOther ?? this.unitOther,
      innerUnit: innerUnit ?? this.innerUnit,
      innerQuantity: innerQuantity ?? this.innerQuantity,
      unitValue: unitValue ?? this.unitValue,
      hsCode: hsCode ?? this.hsCode,
      category: category ?? this.category,
      isProhibited: isProhibited ?? this.isProhibited,
      status: status ?? this.status,
      reasons: reasons ?? this.reasons,
      notes: notes ?? this.notes,
    );
  }
}

class WarehouseEntryModel {
  final String id;
  final String packageId;
  final String? packageItemId; // Added: Link to specific item
  final String warehouseId;
  final String warehouseName;
  final String warehouseCode;
  final String? zone;
  final String holdReason;
  final int itemCount;
  final String? admittedBy;
  final String? admittedByName;
  final String? admittedByBadge;
  final DateTime admittedAt;
  final bool isReturned;
  final DateTime? returnedAt;
  final String? returnedBy;
  final String? returnedByName;
  final String? returnedByBadge;
  final String? returnNotes;
  final double? dailyRate;
  final double? accumulatedCharge;
  // From joined packages table
  final String? srNumber;
  final String? caseNumber;
  final String? consigneeName;
  final String? packageStatus;
  // From joined package_items (the item this entry holds, or the package's
  // first item) — so reports can identify the goods, not just the SR number.
  final String? itemName;
  final String? hsCode;

  const WarehouseEntryModel({
    required this.id,
    required this.packageId,
    this.packageItemId, // Added
    required this.warehouseId,
    required this.warehouseName,
    required this.warehouseCode,
    this.zone,
    required this.holdReason,
    required this.itemCount,
    this.admittedBy,
    this.admittedByName,
    this.admittedByBadge,
    required this.admittedAt,
    this.isReturned = false,
    this.returnedAt,
    this.returnedBy,
    this.returnedByName,
    this.returnedByBadge,
    this.returnNotes,
    this.dailyRate,
    this.accumulatedCharge,
    this.srNumber,
    this.caseNumber,
    this.consigneeName,
    this.packageStatus,
    this.itemName,
    this.hsCode,
  });

  factory WarehouseEntryModel.fromJson(Map<String, dynamic> json) {
    final warehouse = json['warehouses'] as Map<String, dynamic>?;
    final package = json['packages'] as Map<String, dynamic>?;
    // Resolve the item this entry holds (or the package's first item) from the
    // joined package_items, so reports can show the goods name + HS code.
    final pkgItems = (package?['package_items'] as List?) ?? const [];
    final entryItemId = json['package_item_id'] as String?;
    Map<String, dynamic>? matchedItem;
    if (pkgItems.isNotEmpty) {
      if (entryItemId != null) {
        matchedItem = pkgItems.cast<Map<String, dynamic>>().firstWhere(
              (i) => i['id'] == entryItemId,
              orElse: () => pkgItems.first as Map<String, dynamic>,
            );
      } else {
        matchedItem = pkgItems.first as Map<String, dynamic>;
      }
    }
    return WarehouseEntryModel(
      id: json['id'] as String,
      packageId: json['package_id'] as String,
      packageItemId: json['package_item_id'] as String?, // Added
      warehouseId: json['warehouse_id'] as String,
      warehouseName: warehouse?['name'] as String? ?? '',
      warehouseCode: warehouse?['code'] as String? ?? '',
      zone: json['zone'] as String?,
      holdReason: json['hold_reason'] as String,
      itemCount: (parseDbInt(json['item_count']) ?? 0),
      admittedBy: json['admitted_by'] as String?,
      admittedByName: (json['admitted_profile']
          as Map<String, dynamic>?)?['full_name'] as String?,
      admittedByBadge: (json['admitted_profile']
          as Map<String, dynamic>?)?['badge_number'] as String?,
      admittedAt: parseDbDateRequired(json['admitted_at']),
      isReturned: json['is_returned'] as bool? ?? false,
      returnedAt: parseDbDate(json['returned_at']),
      returnedBy: json['returned_by'] as String?,
      returnedByName: (json['returned_profile']
          as Map<String, dynamic>?)?['full_name'] as String?,
      returnedByBadge: (json['returned_profile']
          as Map<String, dynamic>?)?['badge_number'] as String?,
      returnNotes: json['return_notes'] as String?,
      dailyRate: parseDbNum(json['daily_rate']) ?? 0,
      accumulatedCharge:
          parseDbNum(json['accumulated_storage_charge']) ?? 0,
      srNumber: package?['sr_number'] as String?,
      consigneeName: package?['consignee_name'] as String?,
      packageStatus: package?['status'] as String?,
      itemName: matchedItem?['item_name'] as String?,
      hsCode: matchedItem?['hs_code'] as String?,
    );
  }

  bool get isPackageConfiscated => packageStatus == 'confiscated';

  int get storageDays {
    final start = DateTime(admittedAt.year, admittedAt.month, admittedAt.day);
    final endDateTime = returnedAt ?? DateTime.now();
    final end = DateTime(endDateTime.year, endDateTime.month, endDateTime.day);

    // Total days spent in the yard
    return end.difference(start).inDays + 1;
  }

  static bool isNoChargeStatus(String s) =>
      s == 'confiscated' ||
      s == 'forfeit' ||
      s == 'forfiet' ||
      s == 'forfeited' ||
      s == 'abandoned' ||
      s == 'destroy' ||
      s == 'destroyed';

  /// Calculates charge considering historical rate changes across all items in the package (or specific item if tied)
  double calculatePackageCharge(
      List<PackageItem> items, Map<DateTime, double> historicalRates) {
    // If the whole package is confiscated, no charge
    if (isPackageConfiscated) return 0;

    // If this specific entry references an item, check if it is confiscated or forfeited
    if (packageItemId != null) {
      final item = items.where((i) => i.id == packageItemId).firstOrNull;
      final s = item?.status?.toLowerCase() ?? '';
      if (isNoChargeStatus(s)) return 0;
    }
    // Fallback: if no packageItemId but ALL items are seized/disposed, no charge
    if (packageItemId == null && items.isNotEmpty) {
      final allSeized =
          items.every((i) => isNoChargeStatus(i.status.toLowerCase()));
      if (allSeized) return 0;
    }

    // We should charge based on this specific entry's itemCount!
    int totalUnits = itemCount;

    // Auto-repair logic: If itemCount is 1 but it's an old bugged entry that should be larger
    if (totalUnits == 1 && packageItemId != null && !isReturned) {
      final item = items.where((i) => i.id == packageItemId).firstOrNull;
      if (item != null && item.quantity > 1) {
        // We can't perfectly know returned sum here without more context, but usually it's fine
        // to fallback to item.quantity for the old un-split ones if we just need an approximation.
        totalUnits = item.quantity;
      }
    }

    final start = DateTime(admittedAt.year, admittedAt.month, admittedAt.day);
    final endDateTime = returnedAt ?? DateTime.now();
    final end = DateTime(endDateTime.year, endDateTime.month, endDateTime.day);

    double totalCharge = 0;

    // Loop through each day from entry to exit/today
    for (int i = 0; i <= end.difference(start).inDays; i++) {
      final currentDay = start.add(Duration(days: i));
      final dayAtMidnight =
          DateTime(currentDay.year, currentDay.month, currentDay.day);

      // Find the active rate for this specific day
      // Rates are matched based on the latest effective_from that is NOT AFTER current day
      double activeRate = 50; // default fallback

      // Rates are expected to be sorted by date ascending from the provider
      historicalRates.forEach((effectiveFrom, rate) {
        final effectiveAtMidnight = DateTime(
            effectiveFrom.year, effectiveFrom.month, effectiveFrom.day);
        if (!dayAtMidnight.isBefore(effectiveAtMidnight)) {
          activeRate = rate;
        }
      });

      // Daily charge = total packages in the SR * that specific day's rate
      totalCharge += (totalUnits * activeRate);
    }

    return totalCharge;
  }
}

/// One zone inside a warehouse, with its own capacity.
///
/// Space is organised zone by zone, so that is where capacity lives. A
/// warehouse's capacity is the SUM of its zones — never entered directly.
class WarehouseZoneModel {
  final String id;
  final String warehouseId;

  /// Short label as it appears on a warehouse entry: 'A', 'B', 'Cold Room' …
  final String name;

  /// The zone's own code, read like the warehouse's: 'W01-A'.
  final String? code;
  final String? description;
  final int capacity;

  const WarehouseZoneModel({
    required this.id,
    required this.warehouseId,
    required this.name,
    this.code,
    this.description,
    this.capacity = 500,
  });

  factory WarehouseZoneModel.fromJson(Map<String, dynamic> json) =>
      WarehouseZoneModel(
        id: json['id'].toString(),
        warehouseId: json['warehouse_id'].toString(),
        name: (json['name'] ?? '').toString(),
        code: json['code'] as String?,
        description: json['description'] as String?,
        capacity: parseDbInt(json['capacity']) ?? 500,
      );

  Map<String, dynamic> toJson() => {
        'warehouse_id': warehouseId,
        'name': name.trim(),
        if (code != null && code!.trim().isNotEmpty) 'code': code!.trim(),
        if (description != null && description!.trim().isNotEmpty)
          'description': description!.trim(),
        'capacity': capacity,
      };
}

/// How full one zone is, and therefore whether more goods fit in it.
class ZoneOccupancy {
  final WarehouseZoneModel zone;
  final int used;

  const ZoneOccupancy({required this.zone, this.used = 0});

  int get capacity => zone.capacity;

  /// Room left. Never negative — an over-filled zone has no room, not
  /// "minus room".
  int get free => (capacity - used) > 0 ? capacity - used : 0;

  double get percent => capacity > 0 ? (used / capacity) * 100 : 0;

  bool get isFull => used >= capacity;

  /// Whether [qty] more items fit.
  bool fits(int qty) => qty <= free;
}

class WarehouseModel {
  final String id;
  final String name;
  final String code;
  final String? description;
  final String? location;
  final int capacity;

  const WarehouseModel({
    required this.id,
    required this.name,
    required this.code,
    this.description,
    this.location,
    this.capacity = 500,
  });

  factory WarehouseModel.fromJson(Map<String, dynamic> json) {
    return WarehouseModel(
      id: json['id'] as String,
      name: json['name'] as String,
      code: json['code'] as String,
      description: json['description'] as String?,
      location: json['location'] as String?,
      capacity: parseDbInt(json['capacity']) ?? 500,
    );
  }
}

class ProfileModel {
  final String id;
  final String fullName;
  final String? username;
  final String? badgeNumber;
  final String? mobileNumber;
  final String? jobRole;
  final String? department;
  final String? yard; // Yard the user belongs to (data isolation)
  /// Head-office directorate (`directorates.code`) this account registered
  /// under. Decides the SR-number prefix, because one yard may sit under
  /// several — NNR is both CED and PSD. Null on pre-directorate accounts.
  final String? directorate;
  final String? profileImageUrl;
  final String role;
  final bool isActive;
  final bool isOnline;
  final DateTime? lastSeenAt;
  final DateTime createdAt;
  final DateTime? passwordUpdatedAt;

  const ProfileModel({
    required this.id,
    required this.fullName,
    this.username,
    this.badgeNumber,
    this.mobileNumber,
    this.jobRole,
    this.department,
    this.yard,
    this.directorate,
    this.profileImageUrl,
    required this.role,
    required this.isActive,
    this.isOnline = false,
    this.lastSeenAt,
    required this.createdAt,
    this.passwordUpdatedAt,
  });

  factory ProfileModel.fromJson(Map<String, dynamic> json) {
    return ProfileModel(
      id: json['id'] as String,
      fullName: json['full_name'] as String,
      username: json['username'] as String?,
      badgeNumber: json['badge_number'] as String?,
      mobileNumber: json['mobile_number'] as String?,
      jobRole: json['job_role'] as String?,
      department: json['department'] as String?,
      yard: json['yard'] as String?,
      directorate: json['directorate'] as String?,
      profileImageUrl: json['profile_image_url'] as String?,
      role: json['role'] as String,
      isActive: json['is_active'] as bool? ?? true,
      isOnline: json['is_online'] as bool? ?? false,
      lastSeenAt: parseDbDate(json['last_seen_at']),
      createdAt: parseDbDateRequired(json['created_at']),
      passwordUpdatedAt: parseDbDate(json['password_updated_at']),
    );
  }

  bool get isAdmin => role == 'admin';

  /// The officer's POST, as shown on their profile and in ICT's staff table.
  ///
  /// `role` is the permission level and has only two yard values -- 'admin'
  /// and 'officer'. DC and SDDC are two DIFFERENT posts that happen to share
  /// the admin permission, so which one an officer holds lives in `job_role`,
  /// set by ICT at provisioning. Falls back to the role's own name for an
  /// account created before ICT recorded a post.
  String get postTitle {
    final j = jobRole?.trim();
    if (j != null && j.isNotEmpty) {
      return kPostTitles[j] ?? j;
    }
    return isAdmin ? 'DC / SDDC' : 'Officer';
  }

  /// [postTitle] shortened for a chip or badge.
  ///
  /// The full title carries the expansion ("DC (Deputy Commissioner)"), which
  /// overflows a table row. Falls back to the same "DC / SDDC" as [postTitle]
  /// for an account with no post recorded -- the two cannot be told apart
  /// without one.
  String get postShortTitle {
    final j = jobRole?.trim();
    if (j != null && j.isNotEmpty) {
      return kPostShortTitles[j] ?? kPostTitles[j] ?? j;
    }
    return isAdmin ? 'DC / SDDC' : 'Officer';
  }

  /// Yard officer (front-line yard staff, not a directorate account).
  bool get isOfficer => role == 'officer';

  /// True for accounts that belong to a physical yard (admin or officer), as
  /// opposed to the head-office directorate roles.
  bool get isYardStaff => isAdmin || isOfficer;

  /// Central Disposal Directorate user (cross-yard sold-package visibility).
  bool get isDisposal => role == 'disposal';

  /// Accounts automatically deactivate 8 months after they were created.
  /// (Applies to admins and officers alike.)
  DateTime get expiresAt => DateTime(createdAt.year, createdAt.month + 8,
      createdAt.day, createdAt.hour, createdAt.minute, createdAt.second);

  /// Appeal Directorate (AD/ADD) user — cross-yard forfeited-package review +
  /// appeal-hold authority.
  bool get isAppeal => role == 'appeal';

  /// Valuation Directorate (DC/SDDC) user — cross-yard valuation of disposal
  /// requests before they reach the Central Disposal Directorate.
  bool get isValuation => role == 'valuation';

  /// Executive Office (DG / ADG) — Customs' two highest posts. Institutional,
  /// cross-yard read-only, never auto-expires.
  bool get isExecutive => role == 'executive';

  /// ICT Directorate (Information & Communication Technology Division) — cross-yard
  /// user provisioning, administration, and system management. Institutional, never auto-expires.
  bool get isIct => role == 'ict';

  /// True once the account is past its 8-month lifetime. Directorate accounts
  /// (Disposal DC/SDDC, Appeal AD/ADD, Valuation DC/SDDC, ICT) are institutional and
  /// never auto-expire (officers transfer in/out of the post).
  bool get isExpired =>
      !isDisposal &&
      !isAppeal &&
      !isValuation &&
      !isExecutive &&
      !isIct &&
      DateTime.now().isAfter(expiresAt);

  /// Whether the account may currently sign in: explicitly active AND not
  /// past its 8-month auto-deactivation window.
  bool get isEffectivelyActive => isActive && !isExpired;

  /// Whole days until the account auto-deactivates (its 8-month lifetime).
  /// Negative once already expired. `null` for institutional directorate
  /// accounts that never auto-expire.
  ///
  /// The exemptions here MUST match [isExpired]'s. ICT was missing, so an ICT
  /// account was counted down towards an expiry [isExpired] would never let
  /// happen -- harmless while only ICT's own staff table read this, wrong the
  /// moment a profile shows the officer their own countdown.
  int? get daysUntilExpiry {
    if (isDisposal || isAppeal || isValuation || isExecutive || isIct) {
      return null;
    }
    return expiresAt.difference(DateTime.now()).inDays;
  }

  // ── Password expiry (90-day rotation policy) ───────────────────────────
  /// Passwords must be rotated every 90 days. The clock starts from
  /// [passwordUpdatedAt] (set by the auth.users trigger), falling back to
  /// [createdAt] for accounts that pre-date the column.
  static const int passwordMaxAgeDays = 90;

  /// A 7-day warning window before the password expires.
  static const int passwordWarnDays = 7;

  DateTime get _passwordAnchor => passwordUpdatedAt ?? createdAt;

  /// Whole days until the current password expires (negative once expired).
  int get daysUntilPasswordExpiry {
    final expiry =
        _passwordAnchor.add(const Duration(days: passwordMaxAgeDays));
    return expiry.difference(DateTime.now()).inDays;
  }

  /// True once the password is past its 90-day life — a change is mandatory.
  bool get isPasswordExpired => daysUntilPasswordExpiry < 0;

  /// True in the final [passwordWarnDays] before expiry (not yet expired).
  bool get isPasswordExpiringSoon =>
      !isPasswordExpired && daysUntilPasswordExpiry <= passwordWarnDays;

  ProfileModel copyWithOnline(bool online, DateTime? seenAt) {
    return ProfileModel(
      id: id,
      fullName: fullName,
      username: username,
      badgeNumber: badgeNumber,
      mobileNumber: mobileNumber,
      jobRole: jobRole,
      department: department,
      yard: yard,
      directorate: directorate,
      profileImageUrl: profileImageUrl,
      role: role,
      isActive: isActive,
      isOnline: online,
      lastSeenAt: seenAt,
      createdAt: createdAt,
      passwordUpdatedAt: passwordUpdatedAt,
    );
  }
}

/// One page of the audit log, and how many rows the filters matched in all.
///
/// ⚠️ [total] is the count of the WHOLE filtered set, not [rows].length. The
/// pager needs both: the rows to draw, and the total to say how many pages
/// there are and where this one sits in them.
class AuditLogPage {
  final List<AuditLogModel> rows;
  final int total;
  const AuditLogPage({required this.rows, required this.total});
}

/// One row of a disposition page, as the `disposition_rows` view returns it.
///
/// ⚠️ A row here is an ITEM or a warehouse ENTRY, never a package: one SR can
/// produce several rows, from three different sources, and the page shows them
/// interleaved by date. The screens used to build this shape in Dart from
/// every package in the yard; the view builds it in SQL so a page can be asked
/// for by number.
class DispositionRow {
  /// Unique across all three sources ('E:<id>' / 'I:<id>' / 'P:<id>'), so a
  /// list of these can be keyed without colliding.
  final String rowKey;

  /// 'entry' | 'item' | 'proposal' — which route recorded this disposition.
  /// The Re-exported page shows it as a Decided By pill (Yard vs Top
  /// Management), since the two carry quite different histories.
  final String source;

  final String packageId;
  final String srNumber;
  final String consigneeName;
  final String? yard;
  final String? itemId;
  final String? entryId;
  final String? proposalId;
  final String finalTag;
  final String itemName;
  final String? hsCode;
  final int quantity;
  final String? note;
  final String? officer;

  /// The one date the page sorts on, whichever source the row came from.
  final DateTime happenedAt;

  const DispositionRow({
    required this.rowKey,
    required this.source,
    required this.packageId,
    required this.srNumber,
    required this.consigneeName,
    required this.yard,
    required this.itemId,
    required this.entryId,
    required this.proposalId,
    required this.finalTag,
    required this.itemName,
    required this.hsCode,
    required this.quantity,
    required this.note,
    required this.officer,
    required this.happenedAt,
  });

  factory DispositionRow.fromJson(Map<String, dynamic> json) => DispositionRow(
        rowKey: json['row_key'].toString(),
        source: json['source']?.toString() ?? 'entry',
        packageId: json['package_id'].toString(),
        srNumber: json['sr_number']?.toString() ?? '',
        consigneeName: json['consignee_name']?.toString() ?? '',
        yard: json['yard']?.toString(),
        itemId: json['item_id']?.toString(),
        entryId: json['entry_id']?.toString(),
        proposalId: json['proposal_id']?.toString(),
        finalTag: json['final_tag']?.toString() ?? '',
        itemName: json['item_name']?.toString() ?? '—',
        hsCode: json['hs_code']?.toString(),
        quantity: (parseDbNum(json['quantity']) ?? 0).round(),
        note: json['note']?.toString(),
        officer: json['officer']?.toString(),
        happenedAt: parseDbDate(json['happened_at']) ?? DateTime(1970),
      );

  /// True when Top Management ruled this, rather than the yard recording it.
  bool get isTopManagement => source == 'proposal';
}

/// One page of [DispositionRow], with the total the pager needs.
class DispositionPage {
  final List<DispositionRow> rows;
  final int total;
  const DispositionPage({required this.rows, required this.total});

  static const empty = DispositionPage(rows: [], total: 0);
}

class AuditLogModel {
  final String id;
  final String userId;
  final String action;
  final String entityType;
  final String entityId;
  final Map<String, dynamic>? details;
  final DateTime createdAt;

  /// The yard the action was performed under, stamped at write time.
  final String? yard;

  // Joined fields — the actor's name and role.
  final String? userFullName;

  /// The actor's role ('officer', 'admin', 'disposal', 'ict', …).
  ///
  /// A yard admin's log view filters this OUT (head-office staff are not the
  /// yard's own activity); ICT's cross-office view filters BY it, so the role
  /// has to travel with the row rather than being dropped on parse.
  final String? userRole;

  const AuditLogModel({
    required this.id,
    required this.userId,
    required this.action,
    required this.entityType,
    required this.entityId,
    this.details,
    required this.createdAt,
    this.yard,
    this.userFullName,
    this.userRole,
  });

  factory AuditLogModel.fromJson(Map<String, dynamic> json) {
    final profile = json['profiles'] as Map<String, dynamic>?;
    return AuditLogModel(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      action: json['action'] as String,
      entityType: json['entity_type'] as String,
      entityId: json['entity_id'] as String,
      details: json['details'] as Map<String, dynamic>?,
      createdAt: parseDbDateRequired(json['created_at']),
      yard: json['yard'] as String?,
      userFullName: profile?['full_name'] as String?,
      userRole: profile?['role'] as String?,
    );
  }
}

// ── Financials (Top Management Directorate) ──────────────────────────────────

/// The three hand-entered outgoings. Income is derived from records the
/// system already holds; these are not, so they are typed in.
const Map<String, String> kExpenseKinds = {
  'destruction_expense': 'Destruction Expenses',
  'advertising_expense': 'Advertising Expenses',
  'labour_expense': 'Labour Costs',
  'transport_expense': 'Transport Costs',
  'auction_expense': 'Auction Expenses',
  'refund': 'Refunds',
};

/// The kinds Central Disposal actually RECORDS. A refund is not typed in — it
/// is what is left of the goods' destroying deposit once these are paid, so it
/// is derived (see [SrFinancials.refund]) rather than entered.
/// What kind of goods an item is, which decides the whole path it takes.
///
/// Asked once on the SR form, then read everywhere downstream:
///
///   normal      -- warehouse, the 30-day appeal window, the existing flow
///   perishable  -- neither. Food, chemicals and the like spoil, so by the
///                  time an appeal window expired there would be nothing left
///                  to dispose of. They go straight to a disposal request.
///
/// ⚠️ 'normal' is the default in the database too, which is what leaves every
/// item registered before this behaving exactly as it did.
const String kNatureNormal = 'normal';
const String kNaturePerishable = 'perishable';

const Map<String, String> kGoodsNatures = {
  kNatureNormal: 'Normal Goods',
  kNaturePerishable: 'Perishable Goods',
};

/// The roles that belong to a head-office DIRECTORATE rather than a yard.
///
/// These accounts are institutional: they belong to a POST, and whoever holds
/// it next may never have signed in. That is why they never auto-expire (see
/// ProfileModel.isExpired) and why ICT reissues their credentials rather than
/// emailing a self-service reset link.
///
/// ⚠️ Keep in step with the exemptions in [ProfileModel.isExpired] and
/// [ProfileModel.daysUntilExpiry]: the same accounts, for the same reason.
const List<String> kDirectorateRoles = [
  'disposal',
  'appeal',
  'valuation',
  'executive',
  'ict',
];

/// The portal each directorate role signs in to, for a picker or a message.
const Map<String, String> kDirectorateRoleNames = {
  'disposal': 'Central Disposal Directorate',
  'appeal': 'Appeal Directorate',
  'valuation': 'Valuation Directorate',
  'executive': 'Top Management Directorate',
  'ict': 'ICT Directorate',
};

/// The posts ICT can assign to a yard account, keyed by what is stored in
/// `profiles.job_role`.
///
/// DC and SDDC are two separate posts. They share the 'admin' permission role,
/// so the role alone cannot tell them apart -- which is why the post is its
/// own field rather than being derived from the role.
const Map<String, String> kPostTitles = {
  'officer': 'Officer',
  'dc': 'DC (Deputy Commissioner)',
  'sddc': 'SDDC (Senior Deputy Commissioner)',
};

/// The SHORT form of each post, for a table chip or a badge where the full
/// title would overflow the row.
const Map<String, String> kPostShortTitles = {
  'officer': 'Officer',
  'dc': 'DC',
  'sddc': 'SDDC',
};

/// The permission role each post carries.
const Map<String, String> kPostRoles = {
  'officer': 'officer',
  'dc': 'admin',
  'sddc': 'admin',
};

const Map<String, String> kRecordableExpenseKinds = {
  'destruction_expense': 'Destruction Expenses',
  'advertising_expense': 'Advertising Expenses',
  'labour_expense': 'Labour Costs',
  'transport_expense': 'Transport Costs',
  'auction_expense': 'Auction Expenses',
};

String expenseKindLabel(String? k) => kExpenseKinds[k] ?? (k ?? '—');

/// One recorded outgoing: a destruction cost, an advertising cost, or a refund.
class FinancialExpenseModel {
  final String id;
  final String kind;
  final double amount;
  final String? description;
  final String? yard;
  final String? srNumber;

  /// The goods item this cost was incurred for. Costs are attributed item by
  /// item — one SR can hold many goods, each destroyed and advertised on its
  /// own — so the Financials tab can break the ledger down goods by goods.
  final String? packageItemId;
  final DateTime incurredOn;
  final DateTime createdAt;

  const FinancialExpenseModel({
    required this.id,
    required this.kind,
    required this.amount,
    this.description,
    this.yard,
    this.srNumber,
    this.packageItemId,
    required this.incurredOn,
    required this.createdAt,
  });

  String get kindLabel => expenseKindLabel(kind);

  factory FinancialExpenseModel.fromJson(Map<String, dynamic> j) =>
      FinancialExpenseModel(
        id: j['id'].toString(),
        kind: (j['kind'] ?? '').toString(),
        amount: parseDbNum(j['amount']) ?? 0,
        description: j['description'] as String?,
        yard: j['yard'] as String?,
        srNumber: j['sr_number'] as String?,
        packageItemId: j['package_item_id']?.toString(),
        incurredOn: DateTime.tryParse(j['incurred_on']?.toString() ?? '') ??
            DateTime.now(),
        createdAt: DateTime.tryParse(j['created_at']?.toString() ?? '') ??
            DateTime.now(),
      );
}

/// How sale proceeds are split, as a share of the SALE PROCEEDS total.
///
///   Reward Fund                       50%
///   Deputy Secretary of the Treasury  50%, and that half splits again:
///       Consolidated Fund   60% of it  (= 30% overall)
///       Comp Fund           40% of it  (= 20% overall)
class SaleProceedsSplit {
  final double proceeds;
  const SaleProceedsSplit(this.proceeds);

  double get rewardFund => proceeds * 0.50;

  /// The Treasury's half, before its own 60/40 split.
  double get deputySecretaryTreasury => proceeds * 0.50;

  double get consolidatedFund => deputySecretaryTreasury * 0.60;
  double get compFund => deputySecretaryTreasury * 0.40;
}

/// One goods item's financial position — the Financials tab's per-goods row.
///
/// Costs are incurred goods by goods, so the whole ledger is built this way
/// and the headline totals are simply the sum of these rows.
///
/// The REFUND is derived, never entered: the destroying deposit is money held
/// against the cost of destroying the goods, so whatever is not spent on the
/// destruction and its advertising goes back.
///
///     refund = destroyingDeposit - (destruction + advertising)
///
/// floored at zero — a deposit cannot refund more than it held. When the costs
/// exceed the deposit the shortfall is reported by [deficit] instead.
class GoodsFinancials {
  final String itemId;
  final String srNumber;
  final String goodsName;
  final String? yard;
  final int quantity;

  /// Income attributable to these goods.
  final double srCharges;
  final double saleProceeds;
  final double taxes;

  /// Breakdown of taxes by tax name (e.g. VAT, PAL).
  final Map<String, double>? _taxesByName;
  Map<String, double> get taxesByName => _taxesByName ?? const {};

  /// Costs Central Disposal recorded against these goods.
  final double destructionExpense;
  final double advertisingExpense;
  final double labourExpense;
  final double transportExpense;
  final double auctionExpense;

  const GoodsFinancials({
    required this.itemId,
    required this.srNumber,
    required this.goodsName,
    this.yard,
    this.quantity = 0,
    this.srCharges = 0,
    this.saleProceeds = 0,
    this.taxes = 0,
    Map<String, double>? taxesByName,
    this.destructionExpense = 0,
    this.advertisingExpense = 0,
    this.labourExpense = 0,
    this.transportExpense = 0,
    this.auctionExpense = 0,
  }) : _taxesByName = taxesByName;

  /// What this item cost to dispose of. Charged against its SR's deposit, not
  /// against a deposit of its own — see [SrFinancials].
  double get depositSpent =>
      destructionExpense +
      advertisingExpense +
      labourExpense +
      transportExpense +
      auctionExpense;

  /// Whether anything at all was recorded for these goods. The deposit is NOT
  /// consulted: it belongs to the SR, so a package whose only figure is its
  /// SR's deposit has nothing of its own to report.
  bool get isEmpty =>
      srCharges == 0 && saleProceeds == 0 && taxes == 0 && depositSpent == 0;
}

/// One SR's financial position — the row the Financials tab and the Expenses
/// tab both list.
///
/// **The destroying deposit is lodged once per SR**, not per goods, so the
/// whole ledger is kept at SR level. An SR holding four packages has ONE
/// deposit, and what is charged against it is the SUM of all four packages'
/// destruction and advertising costs:
///
///     refund = destroyingDeposit - Σ(destruction + advertising)
///
/// floored at zero — a deposit cannot refund more than it held. When the costs
/// exceed it the shortfall is reported by [deficit] instead.
///
/// Deriving the refund from the SR total is the only correct way to do it:
/// splitting the deposit across packages and refunding each separately would
/// let one package's surplus hide another's overspend.
class SrFinancials {
  final String srNumber;
  final String? yard;
  final DateTime? date;

  /// The goods this SR covers, so a row can be expanded to its packages.
  final List<GoodsFinancials> goods;

  /// Lodged once for the whole SR.
  final double destroyingDeposit;

  const SrFinancials({
    required this.srNumber,
    this.yard,
    this.date,
    this.goods = const [],
    this.destroyingDeposit = 0,
  });

  int get packageCount => goods.length;

  /// Combined names of all goods covered by this SR.
  String get goodsName {
    if (goods.isEmpty) return '—';
    final names =
        goods.map((g) => g.goodsName).where((n) => n.trim().isNotEmpty).toSet();
    if (names.isEmpty) return '—';
    return names.join(', ');
  }

  int get quantity => goods.fold(0, (a, g) => a + g.quantity);

  double get srCharges => goods.fold(0.0, (a, g) => a + g.srCharges);
  double get saleProceeds => goods.fold(0.0, (a, g) => a + g.saleProceeds);
  double get taxes => goods.fold(0.0, (a, g) => a + g.taxes);

  Map<String, double> get taxesByName {
    final result = <String, double>{};
    for (final g in goods) {
      g.taxesByName.forEach((k, v) {
        result[k] = (result[k] ?? 0) + v;
      });
    }
    return result;
  }

  double get destructionExpense =>
      goods.fold(0.0, (a, g) => a + g.destructionExpense);
  double get advertisingExpense =>
      goods.fold(0.0, (a, g) => a + g.advertisingExpense);
  double get labourExpense => goods.fold(0.0, (a, g) => a + g.labourExpense);
  double get transportExpense =>
      goods.fold(0.0, (a, g) => a + g.transportExpense);
  double get auctionExpense => goods.fold(0.0, (a, g) => a + g.auctionExpense);

  /// Every package's costs together — this is what the single deposit pays.
  double get depositSpent =>
      destructionExpense +
      advertisingExpense +
      labourExpense +
      transportExpense +
      auctionExpense;

  /// Returned to the depositor: the unspent part of the SR's deposit.
  double get refund => (destroyingDeposit - depositSpent) > 0
      ? destroyingDeposit - depositSpent
      : 0;

  /// Costs beyond what the deposit covered. Zero when the deposit was enough.
  double get deficit => (depositSpent - destroyingDeposit) > 0
      ? depositSpent - destroyingDeposit
      : 0;

  double get totalIncome =>
      srCharges + destroyingDeposit + saleProceeds + taxes;

  double get totalExpenditure => depositSpent + refund;

  double get netBalance => totalIncome - totalExpenditure;

  /// Where this SR's sale proceeds are distributed. The same rule as the page
  /// total, applied per SR, so the columns down the table add up to the cards.
  SaleProceedsSplit get split => SaleProceedsSplit(saleProceeds);

  /// Whether anything at all was recorded against this SR.
  bool get isEmpty => totalIncome == 0 && totalExpenditure == 0;
}

/// What the Appeal Directorate has ruled about one goods item.
///
/// A DECISION ends the 30-day wait: once the directorate has ruled, the yard
/// may act on those goods immediately. A HOLD does the opposite — it freezes
/// them even after the window closes, because the appeal is still open.
class ItemAppealOutcome {
  /// 'RELEASE' / 'SALE' / 'DESTROY' / 'RE-EXPORT' / 'OTHER', or null when the
  /// directorate has not ruled.
  final String? decision;

  /// An appeal is lodged and still under review.
  final bool onHold;

  const ItemAppealOutcome({this.decision, this.onHold = false});

  bool get isDecided => (decision ?? '').trim().isNotEmpty;

  /// Whether the goods are actionable regardless of the appeal window. A hold
  /// always wins: an open appeal blocks action even once the window closes.
  bool get unblocksAction => isDecided && !onHold;

  /// The decision in the wording the yard reads, matching
  /// [ForfeitedPackageModel.appealDecisionLabelForItem].
  String? get label {
    switch ((decision ?? '').toUpperCase()) {
      case 'RELEASE':
        return 'Release to owner';
      case 'SALE':
        return 'Sell';
      case 'DESTROY':
        return 'Destroy';
      case 'RE-EXPORT':
        return 'Re-export';
      case 'OTHER':
        return 'Other';
      default:
        return null;
    }
  }
}

/// How much of a custom 'OTHER' decision note fits in a decision chip.
const kAppealDecisionLabelMaxChars = 28;

// ── Appeal window (shared by EVERY status) ───────────────────
//
// The 30-day appeal window is NOT a forfeit-only rule: a Detain, Abandoned or
// "Other" package is equally frozen for its first 30 days. Nothing can be
// disposed of, and nothing can be sent to Central Disposal, until it passes.
//
// The clock runs from the goods' ENTRY DATE (when they reached the yard), so a
// package that has been sitting for months is actionable immediately — the
// window is about giving the owner 30 days from arrival, not 30 days from the
// moment an officer happened to change its status.

/// How long goods stay open to appeal after entering the yard.
const int kAppealWindowDays = 30;

/// The moment the appeal window closes for goods that entered on [entryDate].
DateTime appealDeadlineFrom(DateTime entryDate) {
  final d = DateTime(entryDate.year, entryDate.month, entryDate.day);
  return d.add(const Duration(days: kAppealWindowDays));
}

/// Whether the appeal window for [entryDate] is still open.
bool isWithinAppealWindow(DateTime? entryDate) {
  if (entryDate == null) return false;
  return DateTime.now().isBefore(appealDeadlineFrom(entryDate));
}

/// Whole days left in the appeal window; 0 once it has closed.
int appealDaysLeft(DateTime? entryDate) {
  if (entryDate == null) return 0;
  final left = appealDeadlineFrom(entryDate).difference(DateTime.now()).inDays;
  return left < 0 ? 0 : left + 1;
}

// ── Forfeited Packages ───────────────────────────────────────

class ForfeitedPackageModel {
  final String id;
  final String packageId;
  final String srNumber;
  final String consigneeName;
  final DateTime forfeitedAt;
  final DateTime appealDeadline;
  final String reason;
  final String? yard;

  /// Where this package entered the disposal pipeline: 'forfeit' (the default,
  /// genuine forfeitures) or 'abandoned' (an abandoned package routed through
  /// the same pipeline via a synthetic forfeited_packages row).
  final String source;

  /// Set by the Appeal Directorate when an appeal is received before the appeal
  /// window passes — a held package cannot be sold or destroyed.
  final bool appealHold;
  final String? appealHoldNote;
  final DateTime? appealHeldAt;

  /// Per-item hold: IDs of specific package_items currently on hold.
  /// Empty = no per-item holds (falls back to appealHold for legacy rows).
  final List<String> heldItemIds;

  /// Recorded by the Appeal Directorate when an appeal hold is lifted — the
  /// decision the owning yard should act on: 'RELEASE', 'SALE', 'DESTROY',
  /// 'RE-EXPORT' or 'OTHER' (custom outcome carried in [appealDecisionNote]).
  final String? appealDecision;
  final String? appealDecisionNote;
  final DateTime? appealDecidedAt;

  /// Per-item appeal decisions: itemId → {decision, note, decided_at, decided_by}.
  /// The Appeal Directorate decides one item at a time, so a multi-item package
  /// can have some items decided (e.g. SALE) while siblings are still in appeal.
  /// Empty = no per-item decisions (falls back to package-level [appealDecision]).
  final Map<String, dynamic> itemAppealDecisions;
  final PackageModel? packageDetails;

  /// For synthetic per-item requestable rows (abandoned / "Other") only: the
  /// specific package item this row represents, so the request dialog lists
  /// each item separately. Null for genuine package-level forfeit rows.
  final String? itemId;
  final String? itemName;

  /// For per-entry abandoned rows: the quantity actually abandoned in that
  /// warehouse entry event (entry.itemCount), not the total item quantity.
  final int? entryQty;

  /// Valuation unit cost set by the Valuation Directorate (LKR per unit).
  final double? valuationCost;

  const ForfeitedPackageModel({
    required this.id,
    required this.packageId,
    required this.srNumber,
    required this.consigneeName,
    required this.forfeitedAt,
    required this.appealDeadline,
    required this.reason,
    this.yard,
    this.source = 'forfeit',
    this.appealHold = false,
    this.appealHoldNote,
    this.appealHeldAt,
    this.heldItemIds = const [],
    this.appealDecision,
    this.appealDecisionNote,
    this.appealDecidedAt,
    this.itemAppealDecisions = const {},
    this.packageDetails,
    this.itemId,
    this.itemName,
    this.entryQty,
    this.valuationCost,
  });

  bool get isAppealExpired => DateTime.now().isAfter(appealDeadline);
  int get daysUntilDeadline => appealDeadline.difference(DateTime.now()).inDays;
  bool get isAbandonedSource => source == 'abandoned';
  bool get isOtherSource => source == 'other';
  bool get isDetainSource => source == 'detain';

  /// True if THIS specific item (identified by [itemId]) is on hold.
  /// Falls back to package-level [appealHold] for single-item / legacy rows.
  bool get isAppealHeld {
    if (itemId != null && heldItemIds.isNotEmpty) {
      return heldItemIds.contains(itemId);
    }
    return appealHold;
  }
  // ── Per-item appeal-decision resolution ──────────────────────────────────
  // A decision is stored per item in [itemAppealDecisions]; a package-level
  // [appealDecision] is the legacy fallback. Callers that know the item (yard
  // Forfeited table) pass its id; the expanded per-item rows (Appeal / disposal)
  // resolve automatically through [itemId].

  /// The decision code ('SALE' / 'DESTROY' / …) for a specific item, or the
  /// package-level decision when this item has none. Null if neither exists.
  ///
  /// Crucially, a MULTI-ITEM package does NOT let its package-level
  /// [appealDecision] bleed onto an item that has no per-item entry — otherwise
  /// deciding one item (or a stale package-level value from the old flow) would
  /// wrongly mark every sibling decided. Only single-item / unknown packages
  /// fall back to the package-level column.
  String? appealDecisionForItem(String? id) {
    if (id != null) {
      final entry = itemAppealDecisions[id];
      if (entry is Map && entry['decision'] != null) {
        final d = entry['decision'].toString().trim();
        if (d.isNotEmpty) return d;
      }
      // Multi-item package with no per-item entry for THIS item → no decision.
      final itemCount = packageDetails?.items.length;
      if (itemCount != null && itemCount > 1) return null;
    }
    return (appealDecision != null && appealDecision!.trim().isNotEmpty)
        ? appealDecision!.trim()
        : null;
  }

  /// The decision note for a specific item (per-item note, else package-level).
  String? appealDecisionNoteForItem(String? id) {
    if (id != null) {
      final entry = itemAppealDecisions[id];
      if (entry is Map && entry['note'] != null) {
        final n = entry['note'].toString().trim();
        if (n.isNotEmpty) return n;
      }
    }
    return appealDecisionNote;
  }

  bool hasAppealDecisionForItem(String? id) =>
      appealDecisionForItem(id) != null;

  /// Whether an appeal decision exists for THIS row — uses [itemId] when the
  /// row is an expanded per-item row, else the package-level decision.
  bool get hasAppealDecision => hasAppealDecisionForItem(itemId);

  /// Whether the yard may now act on this package (Send Disposal Request /
  /// Final Disposition). Allowed once the 30-day appeal window has passed OR
  /// the Appeal Directorate has already returned a decision (no need to wait
  /// out the 30 days in that case).
  bool get isActionable => isAppealExpired || hasAppealDecision;

  /// The disposal-request disposition an item's appeal decision implies
  /// ('destruction' | 'sale'), or null for non-disposal outcomes.
  String? appealRequestDispositionForItem(String? id) {
    switch ((appealDecisionForItem(id) ?? '').toUpperCase()) {
      case 'DESTROY':
        return 'destruction';
      case 'SALE':
        return 'sale';
      default:
        return null;
    }
  }

  /// The disposal-request disposition this row's appeal decision implies.
  String? get appealRequestDisposition =>
      appealRequestDispositionForItem(itemId);

  /// Human-friendly label for a specific item's decision (falls back to the
  /// custom note for 'OTHER').
  ///
  /// ⚠️ The label goes inside a CHIP, so it has to stay short. An 'OTHER'
  /// decision shows its custom note -- which is free text an officer typed, and
  /// a sentence-long one ("Referred back to the yard for further inquiry")
  /// overflowed the chip and was clipped mid-word. Long notes are trimmed here;
  /// the full text stays available through [appealDecisionNoteForItem], which
  /// is what the tooltip and the details dialog read.
  String? appealDecisionLabelForItem(String? id) {
    final dec = appealDecisionForItem(id);
    switch ((dec ?? '').toUpperCase()) {
      case 'RELEASE':
        return 'Release to owner';
      case 'SALE':
        return 'Sell';
      case 'DESTROY':
        return 'Destroy';
      case 'RE-EXPORT':
        return 'Re-export';
      case 'OTHER':
        final note = appealDecisionNoteForItem(id)?.trim();
        if (note == null || note.isEmpty) return 'Other';
        return note.length <= kAppealDecisionLabelMaxChars
            ? note
            : '${note.substring(0, kAppealDecisionLabelMaxChars - 1).trimRight()}…';
      default:
        return dec;
    }
  }

  /// Human-friendly label for this row's decision.
  String? get appealDecisionLabel => appealDecisionLabelForItem(itemId);

  factory ForfeitedPackageModel.fromJson(Map<String, dynamic> json) {
    return ForfeitedPackageModel(
      id: json['id'] as String,
      packageId: json['package_id'] as String,
      srNumber: json['sr_number'] as String,
      consigneeName: json['consignee_name'] as String,
      forfeitedAt: parseDbDateRequired(json['forfeited_at']),
      appealDeadline: parseDbDateRequired(json['appeal_deadline']),
      reason: json['reason'] as String? ?? '',
      yard: json['yard'] as String?,
      source: json['source'] as String? ?? 'forfeit',
      appealHold: json['appeal_hold'] as bool? ?? false,
      appealHoldNote: json['appeal_hold_note'] as String?,
      appealHeldAt: parseDbDate(json['appeal_held_at']),
      heldItemIds:
          (json['held_item_ids'] as List?)?.map((e) => e.toString()).toList() ??
              const [],
      appealDecision: json['appeal_decision'] as String?,
      appealDecisionNote: json['appeal_decision_note'] as String?,
      appealDecidedAt: parseDbDate(json['appeal_decided_at']),
      itemAppealDecisions:
          (json['item_appeal_decisions'] as Map?)?.cast<String, dynamic>() ??
              const {},
      packageDetails: json['packages'] != null
          ? PackageModel.fromJson(json['packages'] as Map<String, dynamic>)
          : null,
      // Per-item pin for synthetic abandoned/"Other" rows (null for genuine
      // package-level forfeits). Lets request rows show exactly their item.
      itemId: json['item_id'] as String?,
      // Exact abandoned qty for per-entry abandoned rows (null otherwise).
      entryQty: parseDbInt(json['entry_qty']),
      // valuation_cost lives on disposal_request_items, not forfeited_packages.
      // When this model is hydrated from a nested join (getTenderSales /
      // getDestructions), the disposal_request_items list is included; pick the
      // first non-null cost from it. Fall back to the direct column in case the
      // column is ever added to the table in future.
      valuationCost: (() {
        final direct = parseDbNum(json['valuation_cost']);
        if (direct != null) return direct;
        final items = json['disposal_request_items'] as List?;
        if (items == null) return null;
        for (final row in items) {
          final cost = parseDbNum(row['valuation_cost']);
          if (cost != null) return cost;
        }
        return null;
      })(),
    );
  }
}

// ── Tender Model ────────────────────────────────────────────

class TenderModel {
  final String id;
  final String tenderNumber;
  final DateTime tenderDate;
  final DateTime? saleDate; // when the tender sale runs
  final String? saleTime; // sale start time, e.g. '10:00'
  final List<String> forfeitedPackageIds;
  final DateTime createdAt;
  final String? createdByName;

  const TenderModel({
    required this.id,
    required this.tenderNumber,
    required this.tenderDate,
    this.saleDate,
    this.saleTime,
    required this.forfeitedPackageIds,
    required this.createdAt,
    this.createdByName,
  });

  /// After the sale date + 1 grace day (to mark outcomes), unsold packages in
  /// this tender become re-tenderable. A null saleDate counts as passed.
  bool get saleWindowPassed =>
      saleDate == null ||
      DateTime.now().isAfter(saleDate!.add(const Duration(days: 1)));

  factory TenderModel.fromJson(Map<String, dynamic> json) {
    final idsJson = json['forfeited_package_ids'];
    List<String> ids = [];
    if (idsJson != null) {
      if (idsJson is List) {
        ids = List<String>.from(idsJson);
      } else if (idsJson is String) {
        ids = (jsonDecode(idsJson) as List).cast<String>();
      }
    }

    return TenderModel(
      id: json['id'] as String,
      tenderNumber: json['tender_number'] as String,
      tenderDate: parseDbDateRequired(json['tender_date']),
      saleDate: json['sale_date'] != null
          ? DateTime.tryParse(json['sale_date'].toString())
          : null,
      saleTime: json['sale_time'] as String?,
      forfeitedPackageIds: ids,
      createdAt: parseDbDateRequired(json['created_at']),
      createdByName:
          (json['profiles'] as Map<String, dynamic>?)?['full_name'] as String?,
    );
  }
}

/// A forfeited package that has been tendered ≥1 time but is still unsold —
/// eligible to be re-tendered. Carries the full tender history for the package.
class ReTenderInfo {
  final ForfeitedPackageModel forfeited;
  final List<TenderModel> tenders; // newest first
  const ReTenderInfo({required this.forfeited, required this.tenders});

  int get tenderCount => tenders.length;
  TenderModel? get latestTender => tenders.isNotEmpty ? tenders.first : null;
}

class ReTenderSaleInfo {
  final ForfeitedPackageModel forfeited;
  final List<TenderSaleModel> sales; // newest first
  const ReTenderSaleInfo({required this.forfeited, required this.sales});

  int get tenderCount => sales.length;
  TenderSaleModel? get latestSale => sales.isNotEmpty ? sales.first : null;
}

/// A single bid amount recorded (by Central Disposal) for an unsold tender
/// package. Keyed by the forfeited package id; viewable in the Appeal portal.
class TenderBidModel {
  final String id;
  final String forfeitedPackageId;
  final String? tenderSaleId; // the tender round this bid belongs to
  final double amount;
  final DateTime createdAt;

  const TenderBidModel({
    required this.id,
    required this.forfeitedPackageId,
    required this.tenderSaleId,
    required this.amount,
    required this.createdAt,
  });

  factory TenderBidModel.fromJson(Map<String, dynamic> json) => TenderBidModel(
        id: json['id'] as String,
        forfeitedPackageId: json['forfeited_package_id'] as String,
        tenderSaleId: json['tender_sale_id'] as String?,
        amount: (parseDbNum(json['amount']) ?? 0),
        createdAt: parseDbDateRequired(json['created_at']),
      );
}

/// How many bid-driven tender rounds a package gets after its first
/// (valuation-driven) attempt. Once these are exhausted and it is still
/// unsold, it goes to the Top Management Directorate's Tender Committees.
/// Combine a sale DATE with an "HH:mm" / "HH:mm:ss" time. Null time ⇒ the
/// date's midnight; null date ⇒ null.
DateTime? combineSaleMoment(DateTime? date, String? time) {
  if (date == null) return null;
  final t = time?.trim();
  if (t == null || t.isEmpty) return date;
  final parts = t.split(':');
  return DateTime(
    date.year,
    date.month,
    date.day,
    int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 0,
    int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0,
    int.tryParse(parts.length > 2 ? parts[2] : '') ?? 0,
  );
}

const int kMaxBidTenderRounds = 3;

/// Human label for a tender attempt, 1-based.
///
/// Attempt 1 is the **Valuation Tender** — its price comes from the Valuation
/// Directorate's Pending Valuation, not from bids, so it is deliberately NOT
/// called "Tender 1". Attempts 2, 3, 4 are **Tender 1, 2, 3** — each priced
/// from the previous round's unsold bids. Anything beyond that is a Top Management Directorate
/// committee round.
String tenderRoundLabel(int attempt) {
  if (attempt <= 1) return 'Valuation Tender';
  final n = attempt - 1;
  if (n <= kMaxBidTenderRounds) return 'Tender $n';
  return 'Committee Tender ${n - kMaxBidTenderRounds}';
}

/// A fresh valuation the Valuation Directorate sets for an unsold tender
/// package, per tender round. Central Disposal reads it before re-tendering.
class TenderRevaluationModel {
  final String id;
  final String forfeitedPackageId;
  final String? tenderSaleId;
  final double valuationCost;
  final String? note;
  final DateTime createdAt;

  const TenderRevaluationModel({
    required this.id,
    required this.forfeitedPackageId,
    required this.tenderSaleId,
    required this.valuationCost,
    required this.note,
    required this.createdAt,
  });

  factory TenderRevaluationModel.fromJson(Map<String, dynamic> json) =>
      TenderRevaluationModel(
        id: json['id'] as String,
        forfeitedPackageId: json['forfeited_package_id'] as String,
        tenderSaleId: json['tender_sale_id'] as String?,
        valuationCost: (parseDbNum(json['valuation_cost']) ?? 0),
        note: json['note'] as String?,
        createdAt: parseDbDateRequired(json['created_at']),
      );
}

/// The FINAL outcome the Top Management Directorate decides for a package that could not be
/// sold by any means — after the Valuation Tender, Tender 1-3, a committee
/// re-valuation and one more tender all failed.
class UnsoldProposalModel {
  final String id;
  final String forfeitedPackageId;

  /// destroy | government_use | auction | re_export | convert |
  /// remove_from_premises
  final String proposal;
  final String? note;
  final String? yard;
  final DateTime decidedAt;

  /// ⚠️ Whether anyone has actually TAKEN the goods.
  ///
  /// A final outcome is a decision, not a hand-over. A package ruled
  /// "Government Use" on 3 July is decided — but it sits in Warehouse 01,
  /// accruing storage, until somebody comes for it. Sold goods have carried
  /// this distinction all along (`tender_sale_items.is_delivered`); the four
  /// outcome pages had no way to record it, so the yard could not say what it
  /// still held and Central Disposal could not see whether it had gone.
  final bool delivered;
  final DateTime? deliveredAt;

  const UnsoldProposalModel({
    required this.id,
    required this.forfeitedPackageId,
    required this.proposal,
    required this.note,
    required this.yard,
    required this.decidedAt,
    this.delivered = false,
    this.deliveredAt,
  });

  String get label => unsoldProposalLabel(proposal);

  factory UnsoldProposalModel.fromJson(Map<String, dynamic> json) =>
      UnsoldProposalModel(
        id: json['id'] as String,
        forfeitedPackageId: json['forfeited_package_id'] as String,
        proposal: json['proposal'] as String,
        note: json['note'] as String?,
        yard: json['yard'] as String?,
        decidedAt: parseDbDateRequired(json['decided_at']),
        delivered: json['delivered'] as bool? ?? false,
        deliveredAt: parseDbDate(json['delivered_at']),
      );
}

/// The outcomes, in the order the Top Management Directorate sees them.
///
/// ⚠️ There is no 'remand' here. Remand is a COURT's act, not a disposal --
/// no yard action stands behind it, and nothing carries it out. Offering it
/// made it a dead end: the goods left Unsold Goods, appeared on a page named
/// Remanded, and stayed there for ever because nothing acts on them. See
/// postgres/08_drop_remand_outcome.sql.
const List<String> kUnsoldProposals = [
  'destroy',
  'government_use',
  'auction',
  're_export',
  'convert',
  'remove_from_premises',
];

String unsoldProposalLabel(String? p) {
  switch (p) {
    case 'destroy':
      return 'Destroy';
    case 'government_use':
      return 'Government Use';
    case 'auction':
      return 'Auction';
    case 're_export':
      return 'Re-export';
    case 'convert':
      return 'Convert';
    case 'remove_from_premises':
      return 'Remove from the Premises';
    default:
      return p ?? '—';
  }
}

/// One committee member (name + optional designation + optional salary no).
class CommitteeMember {
  final String name;
  final String? designation;
  final String? salaryNo;
  const CommitteeMember({required this.name, this.designation, this.salaryNo});

  factory CommitteeMember.fromJson(Map<String, dynamic> j) => CommitteeMember(
        name: (j['name'] as String?)?.trim() ?? '',
        designation: (j['designation'] as String?)?.trim(),
        salaryNo: (j['salary_no'] as String?)?.trim(),
      );
  Map<String, dynamic> toJson() => {
        'name': name,
        if (designation != null && designation!.isNotEmpty)
          'designation': designation,
        if (salaryNo != null && salaryNo!.isNotEmpty) 'salary_no': salaryNo,
      };
}

/// The committee the ADG appoints for a package unsold >3 times. Usually five
/// officers, but the size is not fixed (the form allows 2-10).
class TenderCommitteeModel {
  final String id;
  final String forfeitedPackageId;
  final List<CommitteeMember> members;
  final String? note;
  final DateTime createdAt;

  /// Step 2 — the per-unit price the COMMITTEE itself decided after inspecting
  /// the goods. Null until the appointed committee records it.
  final double? committeeValue;
  final DateTime? committeeValuedAt;
  final String? committeeNote;

  /// Step 3 — the ADG submitting the committee's figure as the FINAL valuation
  /// for the next tender. Null until the ADG signs it off.
  final double? submittedValue;
  final DateTime? submittedAt;

  const TenderCommitteeModel({
    required this.id,
    required this.forfeitedPackageId,
    required this.members,
    required this.note,
    required this.createdAt,
    this.committeeValue,
    this.committeeValuedAt,
    this.committeeNote,
    this.submittedValue,
    this.submittedAt,
  });

  /// The committee exists but has not priced the goods yet.
  bool get isAwaitingCommitteeValue => committeeValue == null;

  /// The committee has priced it, but the ADG has not submitted it yet.
  bool get isAwaitingAdgSubmission =>
      committeeValue != null && submittedValue == null;

  bool get isSubmitted => submittedValue != null;

  factory TenderCommitteeModel.fromJson(Map<String, dynamic> json) =>
      TenderCommitteeModel(
        id: json['id'] as String,
        forfeitedPackageId: json['forfeited_package_id'] as String,
        members: ((json['members'] as List?) ?? const [])
            .map((e) => CommitteeMember.fromJson(e as Map<String, dynamic>))
            .where((m) => m.name.isNotEmpty)
            .toList(),
        note: json['note'] as String?,
        createdAt: parseDbDateRequired(json['created_at']),
        committeeValue: parseDbNum(json['committee_value']),
        committeeValuedAt: json['committee_valued_at'] != null
            ? DateTime.tryParse(json['committee_valued_at'].toString())
            : null,
        committeeNote: json['committee_note'] as String?,
        submittedValue: parseDbNum(json['submitted_value']),
        submittedAt: json['submitted_at'] != null
            ? DateTime.tryParse(json['submitted_at'].toString())
            : null,
      );
}

// ── Tender Disposal Outcome Model ────────────────────────────

class TenderDisposalModel {
  final String id;
  final String tenderPackageId;
  final String forfeitedPackageId;
  final String disposalType; // sold, re_export, govt_use, destroy, other
  final String? receiptNumber; // For 'sold'
  final String? otherDetails; // For 'other'
  final DateTime disposedAt;
  final String? disposedByName;

  const TenderDisposalModel({
    required this.id,
    required this.tenderPackageId,
    required this.forfeitedPackageId,
    required this.disposalType,
    this.receiptNumber,
    this.otherDetails,
    required this.disposedAt,
    this.disposedByName,
  });

  factory TenderDisposalModel.fromJson(Map<String, dynamic> json) {
    return TenderDisposalModel(
      id: json['id'] as String,
      tenderPackageId: json['tender_package_id'] as String,
      forfeitedPackageId: json['forfeited_package_id'] as String,
      disposalType: json['disposal_type'] as String,
      receiptNumber: json['receipt_number'] as String?,
      otherDetails: json['other_details'] as String?,
      disposedAt: parseDbDateRequired(json['disposed_at']),
      disposedByName:
          (json['profiles'] as Map<String, dynamic>?)?['full_name'] as String?,
    );
  }
}

// ── Central Disposal Directorate positions ───────────────────────────────
// Two institutional head-office accounts only (not personal). Whoever holds
// the post logs in with the shared branch email + password.
const Map<String, String> kDisposalPositions = {
  'DC': 'DC (Director)',
  'SDDC': 'SDDC (Senior Deputy Director)',
};

String disposalPositionLabel(String? code) =>
    kDisposalPositions[code] ?? (code ?? 'Disposal Directorate');

// ── Appeal Directorate positions (DC / SDDC — same titles as Disposal) ──────
// Keys are the *usernames* and must stay distinct from the disposal `dc`/`sddc`
// (profiles.username is globally unique), so the Appeal Directorate uses the
// `adc` / `asddc` usernames while displaying the same DC / SDDC titles.
const Map<String, String> kAppealPositions = {
  'ADC': 'DC (Director)',
  'ASDDC': 'SDDC (Senior Deputy Director)',
};

String appealPositionLabel(String? code) =>
    kAppealPositions[code] ?? (code ?? 'Appeal Directorate');

// ── Valuation Directorate positions (DC / SDDC — same titles as Disposal) ───
// Keys are the *usernames* and must stay globally unique (profiles.username),
// so the Valuation Directorate uses the `vdc` / `vsddc` usernames while
// displaying the same DC / SDDC titles.
const Map<String, String> kValuationPositions = {
  'VDC': 'DC (Director)',
  'VSDDC': 'SDDC (Senior Deputy Director)',
};

String valuationPositionLabel(String? code) =>
    kValuationPositions[code] ?? (code ?? 'Valuation Directorate');

// ── Executive Office positions (DG / ADG — Customs' two highest posts) ───────
// Keys are the *usernames* (globally unique in profiles.username).
const Map<String, String> kExecutivePositions = {
  'DG': 'DG (Director General)',
  'ADG': 'ADG (Additional Director General)',
  // Sits on the Top Management Directorate to observe. VIEW-ONLY: no committee appointment,
  // no committee valuation, no final outcome — see [isExecutiveViewOnly].
  'DC': 'DC (Deputy Commissioner)',
};

String executivePositionLabel(String? code) =>
    kExecutivePositions[code] ?? (code ?? "Director General's Office");

// ── ICT Directorate positions ──────────────────────────────────────────────
const Map<String, String> kIctPositions = {
  'IDC': 'DC (Director ICT)',
  'ISDDC': 'SDDC (Senior Deputy Director ICT)',
  'ICT_ADMIN': 'Chief ICT Officer / System Admin',
  'ICT_OFFICER': 'ICT Officer',
};

String ictPositionLabel(String? code) =>
    kIctPositions[code] ?? (code ?? 'ICT Directorate');

// ── Directorates & yards (ICT-maintained reference data) ────────────────────
//  These mirror the `directorates` / `yards` tables. The const lists in
//  lib/core/directorates.dart and lib/core/yards.dart remain as the seed and
//  the offline fallback; these models carry the LIVE rows ICT edits.

/// A head-office directorate — CED, PSD, RTF, B/A, ACD, EXD, PRD, SSD, …
class DirectorateModel {
  final String code;
  final String name;

  /// What goes in FRONT of the SR number. Distinct from [code] because "B/A"
  /// is the real prefix but an awkward key.
  final String srPrefix;
  final int sortOrder;
  final bool isActive;

  const DirectorateModel({
    required this.code,
    required this.name,
    required this.srPrefix,
    this.sortOrder = 100,
    this.isActive = true,
  });

  factory DirectorateModel.fromJson(Map<String, dynamic> json) =>
      DirectorateModel(
        code: json['code'] as String,
        name: json['name'] as String,
        srPrefix: json['sr_prefix'] as String,
        sortOrder: parseDbInt(json['sort_order']) ?? 100,
        isActive: json['is_active'] as bool? ?? true,
      );
}

/// A physical customs yard, as stored rather than hard-coded.
class YardModel {
  final String code;
  final String name;
  final String srPrefix;
  final int sortOrder;
  final bool isActive;

  const YardModel({
    required this.code,
    required this.name,
    required this.srPrefix,
    this.sortOrder = 100,
    this.isActive = true,
  });

  factory YardModel.fromJson(Map<String, dynamic> json) => YardModel(
        code: json['code'] as String,
        name: json['name'] as String,
        srPrefix: json['sr_prefix'] as String,
        sortOrder: parseDbInt(json['sort_order']) ?? 100,
        isActive: json['is_active'] as bool? ?? true,
      );
}


/// True when the signed-in Top Management Directorate officer holds [code].
///
/// The post lives in `profiles.job_role`, but accounts created before the
/// "Top Management Directorate" rename can carry it only in the username or the full
/// name, so all three are checked. Longer codes are tested FIRST because
/// "(ADG)" also contains "DG" — a naive match would read an ADG as a DG.
bool executivePostIs(ProfileModel? p, String code) {
  if (p == null) return false;
  final role = (p.jobRole ?? '').trim().toUpperCase();
  final user = (p.username ?? '').trim().toLowerCase();
  bool matches(String c) =>
      role == c ||
      user == c.toLowerCase() ||
      RegExp(r'\(\s*' + c + r'\s*\)', caseSensitive: false)
          .hasMatch(p.fullName);

  // Anything that matches a LONGER post cannot be this one.
  for (final other in kExecutivePositions.keys) {
    if (other.length > code.length && matches(other)) return false;
  }
  return matches(code);
}

/// The DC observes the Top Management Directorate but changes nothing.
bool isExecutiveViewOnly(ProfileModel? p) => executivePostIs(p, 'DC');

// ── Tender Sale (Central Disposal Directorate) ───────────────────────────

/// The three tender-sale types offered to the Disposal Directorate.
const Map<String, String> kTenderSaleTypes = {
  'special': 'Special Tender Sale (perishable goods)',
  'general_cargo': 'General Cargo Tender Sale (normal goods)',
  'motor_vehicle': 'Motor Vehicle Tender Sale (vehicles)',
};

String tenderSaleTypeLabel(String? code) =>
    kTenderSaleTypes[code] ?? (code ?? '—');

/// One package placed in a Tender Sale, with its sold status.
class TenderSaleItemModel {
  final String id;
  final String tenderSaleId;
  final String forfeitedPackageId;
  final String yard;
  final bool sold;
  final DateTime? soldAt;
  final bool unsold;
  final DateTime? unsoldAt;
  final String? receiptNumber;
  final ForfeitedPackageModel? forfeited;
  final double soldPrice;
  final List<dynamic> appliedTaxes;
  final bool isDelivered;
  final DateTime? deliveredAt;

  const TenderSaleItemModel({
    required this.id,
    required this.tenderSaleId,
    required this.forfeitedPackageId,
    required this.yard,
    this.sold = false,
    this.soldAt,
    this.unsold = false,
    this.unsoldAt,
    this.receiptNumber,
    this.forfeited,
    this.soldPrice = 0.0,
    this.appliedTaxes = const [],
    this.isDelivered = false,
    this.deliveredAt,
  });

  factory TenderSaleItemModel.fromJson(Map<String, dynamic> json) {
    return TenderSaleItemModel(
      id: json['id'] as String,
      tenderSaleId: json['tender_sale_id'] as String,
      forfeitedPackageId: json['forfeited_package_id'] as String,
      yard: json['yard'] as String? ?? '',
      sold: json['sold'] as bool? ?? false,
      soldAt: json['sold_at'] != null
          ? DateTime.tryParse(json['sold_at'].toString())
          : null,
      unsold: json['unsold'] as bool? ?? false,
      unsoldAt: json['unsold_at'] != null
          ? DateTime.tryParse(json['unsold_at'].toString())
          : null,
      receiptNumber: json['receipt_number'] as String?,
      forfeited: json['forfeited_packages'] != null
          ? ForfeitedPackageModel.fromJson(
              json['forfeited_packages'] as Map<String, dynamic>)
          : null,
      soldPrice: parseDbNum(json['sold_price']) ?? 0.0,
      appliedTaxes: json['applied_taxes'] as List<dynamic>? ?? const [],
      isDelivered: json['is_delivered'] as bool? ?? false,
      deliveredAt: json['delivered_at'] != null
          ? DateTime.tryParse(json['delivered_at'].toString())
          : null,
    );
  }

  /// The yard this tender item belongs to; falls back to the forfeited package's
  /// yard when the `yard` column is empty (mirrors [DestructionItemModel]).
  String? get effectiveYard => yard.isNotEmpty ? yard : forfeited?.yard;
}

/// The stage a tender sale has reached, in order.
///
/// Read off the sale's own three moments -- it opens when it is created, starts
/// at [TenderSaleModel.saleMoment], closes at [TenderSaleModel.saleEndMoment],
/// and its items lapse to Unsold at [TenderSaleModel.unsoldDeadline].
enum TenderStage {
  /// Announced, bidding not yet started.
  open('Tender Open', 'Bidding has not started yet'),

  /// Bidding is under way.
  running('Tender Started', 'Bidding is open'),

  /// Bidding has closed; Central Disposal is marking each item sold or unsold.
  awaitingDecision('Awaiting Decision', 'Central Disposal is deciding'),

  /// The window to decide has passed; anything unmarked has gone to Unsold.
  lapsed('Tender Closed', 'The window to decide has passed');

  /// The chip's label.
  final String label;

  /// What it means, for a tooltip.
  final String description;

  const TenderStage(this.label, this.description);
}

class TenderSaleModel {
  final String id;
  final String? saleNumber;
  final DateTime? saleDate;
  final String? serial;
  final int? year;
  final String? tenderType; // special | general_cargo | motor_vehicle
  final String? yard;
  final String? saleTime;
  final String? saleEndTime;
  final DateTime createdAt;
  final String? createdByName;
  final List<TenderSaleItemModel> items;

  const TenderSaleModel({
    required this.id,
    this.saleNumber,
    this.saleDate,
    this.serial,
    this.year,
    this.tenderType,
    this.yard,
    this.saleTime,
    this.saleEndTime,
    required this.createdAt,
    this.createdByName,
    this.items = const [],
  });

  String get typeLabel => tenderSaleTypeLabel(tenderType);

  /// The exact moment the tender sale is scheduled to run — [saleDate] combined
  /// with [saleTime] ("HH:mm" / "HH:mm:ss"). Falls back to the date's midnight
  /// when no time is recorded. Null when there is no sale date at all.
  DateTime? get saleMoment {
    final d = saleDate;
    if (d == null) return null;
    final t = saleTime?.trim();
    if (t == null || t.isEmpty) return d;
    final parts = t.split(':');
    final h = int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 0;
    final m = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0;
    final s = int.tryParse(parts.length > 2 ? parts[2] : '') ?? 0;
    return DateTime(d.year, d.month, d.day, h, m, s);
  }

  /// True once the scheduled sale moment (date + time) has passed — only then
  /// may items be marked Sold. A sale with no date is treated as not-yet-due.
  bool get saleTimePassed {
    final moment = saleMoment;
    if (moment == null) return false;
    return DateTime.now().isAfter(moment);
  }

  /// The moment the sale CLOSES — [saleDate] with [saleEndTime]. Falls back to
  /// [saleMoment] when no end time was recorded, so rows created before the
  /// column existed behave exactly as they did.
  DateTime? get saleEndMoment =>
      combineSaleMoment(saleDate, saleEndTime) ?? saleMoment;

  /// True once the sale has ENDED. This — not [saleTimePassed] — is what
  /// unseals the valuation: the figure is the reserve price, so it may only be
  /// shown after bidding has closed, never while it is open.
  bool get saleEnded {
    final moment = saleEndMoment;
    if (moment == null) return false;
    return DateTime.now().isAfter(moment);
  }

  /// Where this sale has got to, for a watcher who cannot act on it.
  ///
  /// "Pending" said nothing about which of four quite different situations the
  /// item was in, and read as an action the viewer owed. These do not: each
  /// names what the SALE is doing, and the last one names who is being waited
  /// on.
  TenderStage get stage {
    if (saleEnded) {
      // Bidding is over. Until the deadline passes, Central Disposal is
      // deciding each item; after it, an unmarked item has lapsed to Unsold.
      final deadline = unsoldDeadline;
      if (deadline != null && DateTime.now().isAfter(deadline)) {
        return TenderStage.lapsed;
      }
      return TenderStage.awaitingDecision;
    }
    if (saleTimePassed) return TenderStage.running;
    return TenderStage.open;
  }

  /// The moment the package leaves this sale as UNSOLD: the END of the next
  /// WORKING day after the sale date (weekends & public holidays are skipped so
  /// the officer always has an office day to mark it). After this, an item not
  /// yet marked sold drops to the Unsold Tenders pool. Null when no date.
  DateTime? get unsoldDeadline {
    final d = saleDate;
    if (d == null) return null;
    return workingDeadline(d);
  }

  /// De-duplicated items: same (forfeited_package_id, fp.item_id) combination
  /// may appear as multiple TSI rows when the per-item RPC created extra entries.
  /// Prefer the sold row; if equal, keep the latest soldAt.
  List<TenderSaleItemModel> get dedupedItems {
    final map = <String, TenderSaleItemModel>{};
    for (final si in items) {
      final key = '${si.forfeitedPackageId}|${si.forfeited?.itemId ?? ''}';
      final existing = map[key];
      if (existing == null) {
        map[key] = si;
      } else if (si.sold && !existing.sold) {
        map[key] = si;
      } else if (si.sold == existing.sold) {
        final siTime = si.soldAt ?? DateTime(2000);
        final exTime = existing.soldAt ?? DateTime(2000);
        if (siTime.isAfter(exTime)) map[key] = si;
      }
    }
    return map.values.toList();
  }

  int get soldCount => dedupedItems.where((i) => i.sold).length;
  int get totalCount => dedupedItems.length;

  factory TenderSaleModel.fromJson(Map<String, dynamic> json) {
    final itemsJson = json['tender_sale_items'] as List? ?? const [];
    return TenderSaleModel(
      id: json['id'] as String,
      saleNumber: json['sale_number'] as String?,
      saleDate: json['sale_date'] != null
          ? DateTime.tryParse(json['sale_date'].toString())
          : null,
      serial: json['serial'] as String?,
      year: parseDbInt(json['year']),
      tenderType: json['tender_type'] as String?,
      yard: json['yard'] as String?,
      saleTime: json['sale_time'] as String?,
      saleEndTime: json['sale_end_time'] as String?,
      createdAt: parseDbDateRequired(json['created_at']),
      createdByName:
          (json['profiles'] as Map<String, dynamic>?)?['full_name'] as String?,
      items: itemsJson
          .map((e) => TenderSaleItemModel.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

// ── Destruction (Central Disposal Directorate) ─────────────────────────────

const Map<String, String> kDestructionTypes = {
  'special': 'Special Destruction (perishable goods)',
  'general_cargo': 'General Cargo Destruction (normal goods)',
  'motor_vehicle': 'Motor Vehicle Destruction (vehicles)',
};

String destructionTypeLabel(String? code) =>
    kDestructionTypes[code] ?? (code ?? '—');

class DestructionItemModel {
  final String id;
  final String destructionId;
  final String forfeitedPackageId;
  final String yard;
  final bool destroyed;
  final DateTime? destroyedAt;
  final bool undestroyed;
  final DateTime? undestroyedAt;
  final bool delivered;
  final DateTime? deliveredAt;
  final String? notes;

  /// Price recorded when the item was marked destroyed (0 until destroyed).
  final double destroyedPrice;

  /// Taxes applied to [destroyedPrice] — list of {name, percentage, amount}.
  final List<dynamic> appliedTaxes;

  /// The receipt the destruction was recorded against — the destruction's
  /// counterpart to `tender_sale_items.receipt_number`.
  final String? receiptNumber;
  final ForfeitedPackageModel? forfeited;

  const DestructionItemModel({
    required this.id,
    required this.destructionId,
    required this.forfeitedPackageId,
    required this.yard,
    this.destroyed = false,
    this.destroyedAt,
    this.undestroyed = false,
    this.undestroyedAt,
    this.delivered = false,
    this.deliveredAt,
    this.notes,
    this.destroyedPrice = 0,
    this.appliedTaxes = const [],
    this.receiptNumber,
    this.forfeited,
  });

  factory DestructionItemModel.fromJson(Map<String, dynamic> json) {
    return DestructionItemModel(
      id: json['id'] as String,
      destructionId: json['destruction_id'] as String,
      forfeitedPackageId: json['forfeited_package_id'] as String,
      yard: json['yard'] as String? ?? '',
      destroyed: json['destroyed'] as bool? ?? false,
      destroyedAt: json['destroyed_at'] != null
          ? DateTime.tryParse(json['destroyed_at'].toString())
          : null,
      undestroyed: json['undestroyed'] as bool? ?? false,
      undestroyedAt: json['undestroyed_at'] != null
          ? DateTime.tryParse(json['undestroyed_at'].toString())
          : null,
      delivered: json['delivered'] as bool? ?? false,
      deliveredAt: json['delivered_at'] != null
          ? DateTime.tryParse(json['delivered_at'].toString())
          : null,
      notes: json['notes'] as String?,
      destroyedPrice: parseDbNum(json['destroyed_price']) ?? 0,
      appliedTaxes: json['applied_taxes'] as List<dynamic>? ?? const [],
      receiptNumber: json['receipt_number'] as String?,
      forfeited: json['forfeited_packages'] != null
          ? ForfeitedPackageModel.fromJson(
              json['forfeited_packages'] as Map<String, dynamic>)
          : null,
    );
  }

  /// The yard this destruction item belongs to. Older `destruction_items` rows
  /// may have an empty `yard` column, which would wrongly drop the item from a
  /// yard's view-only Destruction Sale list — fall back to the forfeited
  /// package's yard so those rows stay visible (mirrors the Tender Sale page).
  String? get effectiveYard => yard.isNotEmpty ? yard : forfeited?.yard;
}

class DestructionModel {
  final String id;
  final String? saleNumber;
  final DateTime? saleDate;
  final String? serial;
  final int? year;
  final String? tenderType;
  final String? yard;
  final String? saleTime;
  final String? saleEndTime;
  final DateTime createdAt;
  final String? createdByName;
  final List<DestructionItemModel> items;

  const DestructionModel({
    required this.id,
    this.saleNumber,
    this.saleDate,
    this.serial,
    this.year,
    this.tenderType,
    this.yard,
    this.saleTime,
    this.saleEndTime,
    required this.createdAt,
    this.createdByName,
    this.items = const [],
  });

  String get typeLabel => destructionTypeLabel(tenderType);
  int get destroyedCount => items.where((i) => i.destroyed).length;

  /// The scheduled destruction moment — [saleDate] combined with [saleTime].
  /// Falls back to the date's midnight when no time is recorded; null when no
  /// date at all.
  DateTime? get saleMoment {
    final d = saleDate;
    if (d == null) return null;
    final t = saleTime?.trim();
    if (t == null || t.isEmpty) return d;
    final parts = t.split(':');
    final h = int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 0;
    final m = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0;
    final s = int.tryParse(parts.length > 2 ? parts[2] : '') ?? 0;
    return DateTime(d.year, d.month, d.day, h, m, s);
  }

  /// True once the scheduled destruction moment (date + time) has passed — only
  /// then may items be marked Destroyed. No date ⇒ not-yet-due.
  bool get saleTimePassed {
    final moment = saleMoment;
    if (moment == null) return false;
    return DateTime.now().isAfter(moment);
  }

  /// The moment the sale CLOSES — [saleDate] with [saleEndTime]. Falls back to
  /// [saleMoment] when no end time was recorded, so rows created before the
  /// column existed behave exactly as they did.
  DateTime? get saleEndMoment =>
      combineSaleMoment(saleDate, saleEndTime) ?? saleMoment;

  /// True once the sale has ENDED. This — not [saleTimePassed] — is what
  /// unseals the valuation: the figure is the reserve price, so it may only be
  /// shown after bidding has closed, never while it is open.
  bool get saleEnded {
    final moment = saleEndMoment;
    if (moment == null) return false;
    return DateTime.now().isAfter(moment);
  }

  /// The moment the package leaves this destruction as UNDESTROYED: the END of
  /// the next WORKING day after the destruction date (weekends & public holidays
  /// skipped). After this, an item not yet marked destroyed drops to the
  /// Undestroyed pool. Null when no date.
  DateTime? get unsoldDeadline {
    final d = saleDate;
    if (d == null) return null;
    return workingDeadline(d);
  }

  factory DestructionModel.fromJson(Map<String, dynamic> json) {
    final itemsJson = json['destruction_items'] as List? ?? const [];
    return DestructionModel(
      id: json['id'] as String,
      saleNumber: json['sale_number'] as String?,
      saleDate: json['sale_date'] != null
          ? DateTime.tryParse(json['sale_date'].toString())
          : null,
      serial: json['serial']?.toString(),
      year: parseDbInt(json['year']),
      tenderType: json['tender_type'] as String?,
      yard: json['yard'] as String?,
      saleTime: json['sale_time'] as String?,
      saleEndTime: json['sale_end_time'] as String?,
      createdAt: parseDbDateRequired(json['created_at']),
      createdByName:
          (json['profiles'] as Map<String, dynamic>?)?['full_name'] as String?,
      items: itemsJson
          .map((e) => DestructionItemModel.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class ReDestructionInfo {
  final ForfeitedPackageModel forfeited;
  final List<DestructionModel> destructions; // newest first

  const ReDestructionInfo({
    required this.forfeited,
    required this.destructions,
  });

  int get timesAttempted => destructions.length;
  DestructionModel? get latestDestruction =>
      destructions.isNotEmpty ? destructions.first : null;
}

// ── Disposal Requests (Yard → Central Disposal Directorate) ──────────────
//
// A yard submits a request listing forfeited packages whose 30-day appeal
// window has passed. Every requested package is for SALE.
//
// Destruction is NOT a disposal request. A yard destroying goods records it as
// a Final Disposition, which writes the item's destruction tag directly and
// puts it on the Destroyed Goods pages — it never reaches the Valuation
// Directorate or Central Disposal's Disposal Requests, and there is no route
// by which it could. Offering it here produced request rows that then sat in
// both queues with nothing anyone could do to them.

/// The disposition a requested package carries. Sale is the only one: see
/// above for why destruction is not a request.
const Map<String, String> kDispositions = {
  'sale': 'Sale',
};

/// The disposition every new request item is created with.
const String kDefaultDisposition = 'sale';

String dispositionLabel(String? code) => kDispositions[code] ?? (code ?? '—');

class DisposalRequestItemModel {
  final String id;
  final String requestId;
  final String forfeitedPackageId;
  final String disposition; // 'destruction' | 'sale'
  final ForfeitedPackageModel? forfeited;

  /// Per-item cost set by the Valuation Directorate (null until valued).
  final double? valuationCost;

  /// Whether THIS item has been forwarded to Central Disposal (per-item gate).
  final bool forwarded;

  const DisposalRequestItemModel({
    required this.id,
    required this.requestId,
    required this.forfeitedPackageId,
    required this.disposition,
    this.forfeited,
    this.valuationCost,
    this.forwarded = false,
  });

  String get dispositionLabelText => dispositionLabel(disposition);

  /// The package items this disposal-request row covers. For a per-item
  /// (abandoned / "Other") row that names a specific [ForfeitedPackageModel.itemId]
  /// only that item; otherwise every item in the package.
  List<PackageItem> get coveredItems {
    final all = forfeited?.packageDetails?.items ?? const <PackageItem>[];
    final itemId = forfeited?.itemId;
    if (itemId != null) {
      final match = all.where((i) => i.id == itemId).toList();
      if (match.isNotEmpty) return match;
    }
    return all;
  }

  /// Total quantity for this disposal row.
  /// Per-entry abandoned rows store the exact abandoned qty in [entryQty]
  /// (e.g. 15 or 19 for two partial-qty events); falls back to the sum of
  /// covered PackageItem quantities for all other row types.
  int get totalQuantity {
    final entryQty = forfeited?.entryQty;
    if (entryQty != null) return entryQty;
    final items = coveredItems;
    if (items.isEmpty) return 1;
    return items.fold(0, (sum, i) => sum + i.quantity);
  }

  /// HS code to show in the table: the single item's code, or 'Multiple' when
  /// the covered items carry different codes. Null when none is recorded.
  String? get hsCodeLabel {
    final codes = coveredItems
        .map((i) => i.hsCode?.trim())
        .where((c) => c != null && c.isNotEmpty)
        .toSet();
    if (codes.isEmpty) return null;
    if (codes.length == 1) return codes.first;
    return 'Multiple';
  }

  /// The per-unit cost entered by the Valuation Directorate (alias of the
  /// stored [valuationCost]; null until valued).
  double? get unitCost => valuationCost;

  /// Total valuation = per-unit cost × total quantity (null until valued).
  double? get totalCost =>
      valuationCost == null ? null : valuationCost! * totalQuantity;

  factory DisposalRequestItemModel.fromJson(Map<String, dynamic> json) {
    return DisposalRequestItemModel(
      id: json['id'] as String,
      requestId: json['request_id'] as String,
      forfeitedPackageId: json['forfeited_package_id'] as String,
      disposition: json['disposition'] as String? ?? kDefaultDisposition,
      forfeited: json['forfeited_packages'] != null
          ? ForfeitedPackageModel.fromJson(
              json['forfeited_packages'] as Map<String, dynamic>)
          : null,
      valuationCost: parseDbNum(json['valuation_cost']),
      forwarded: json['forwarded'] as bool? ?? false,
    );
  }
}

class DisposalRequestModel {
  final String id;
  final String yard;
  final DateTime requestDate;
  final String status;
  final DateTime createdAt;
  final String? createdByName;
  final List<DisposalRequestItemModel> items;

  /// Valuation gate: 'pending_valuation' (only the Valuation Directorate sees
  /// it) or 'forwarded' (released to the Central Disposal Directorate).
  final String valuationStatus;
  final DateTime? valuedAt;
  final String? valuedByName;

  const DisposalRequestModel({
    required this.id,
    required this.yard,
    required this.requestDate,
    required this.status,
    required this.createdAt,
    this.createdByName,
    this.items = const [],
    this.valuationStatus = 'forwarded',
    this.valuedAt,
    this.valuedByName,
  });

  int get destructionCount =>
      items.where((i) => i.disposition == 'destruction').length;
  int get saleCount => items.where((i) => i.disposition == 'sale').length;
  bool get isForwarded => valuationStatus == 'forwarded';
  bool get isPendingValuation => valuationStatus == 'pending_valuation';

  factory DisposalRequestModel.fromJson(Map<String, dynamic> json) {
    final itemsJson = json['disposal_request_items'] as List? ?? const [];
    final items = itemsJson
        .map(
            (e) => DisposalRequestItemModel.fromJson(e as Map<String, dynamic>))
        .toList();
    // 'profiles' is the created_by join; 'valued_profile' the valued_by join.
    return DisposalRequestModel(
      id: json['id'] as String,
      yard: json['yard'] as String? ?? '',
      requestDate: parseDbDateRequired(json['request_date']),
      status: json['status'] as String? ?? 'pending',
      createdAt: parseDbDateRequired(json['created_at']),
      createdByName:
          (json['profiles'] as Map<String, dynamic>?)?['full_name'] as String?,
      items: items,
      valuationStatus: json['valuation_status'] as String? ?? 'forwarded',
      valuedAt: parseDbDate(json['valued_at']),
      valuedByName: (json['valued_profile']
          as Map<String, dynamic>?)?['full_name'] as String?,
    );
  }
}

class PackageCategory {
  final String id;
  final String name;
  final String? description;
  final String? targetWarehouseId;
  final String? targetWarehouseName;
  final String? targetZone;
  final DateTime createdAt;

  const PackageCategory({
    required this.id,
    required this.name,
    this.description,
    this.targetWarehouseId,
    this.targetWarehouseName,
    this.targetZone,
    required this.createdAt,
  });

  factory PackageCategory.fromJson(Map<String, dynamic> json) {
    return PackageCategory(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      targetWarehouseId: json['target_warehouse_id'] as String?,
      targetWarehouseName:
          (json['warehouses'] as Map<String, dynamic>?)?['name'] as String?,
      targetZone: json['target_zone'] as String?,
      createdAt: parseDbDateRequired(json['created_at']),
    );
  }
}

class DisposalTaxModel {
  final String id;
  final String name;
  final double percentage;
  final bool isActive;
  final DateTime createdAt;

  const DisposalTaxModel({
    required this.id,
    required this.name,
    required this.percentage,
    required this.isActive,
    required this.createdAt,
  });

  factory DisposalTaxModel.fromJson(Map<String, dynamic> json) {
    return DisposalTaxModel(
      id: json['id'] as String,
      name: json['name'] as String,
      percentage: (parseDbNum(json['percentage']) ?? 0),
      isActive: json['is_active'] as bool? ?? true,
      createdAt: parseDbDateRequired(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'percentage': percentage,
      'is_active': isActive,
    };
  }
}
