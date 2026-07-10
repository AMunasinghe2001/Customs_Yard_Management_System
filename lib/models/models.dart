import 'dart:convert';

class PackageModel {
  final String id;
  final String srNumber;
  final String? caseNumber;
  final String originCountry;
  final double declaredValue;
  final double weightKg;
  final int totalItemCount;
  final String? description;
  final String? containerNumber;
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
    this.caseNumber,
    this.originCountry = '',
    this.declaredValue = 0,
    this.weightKg = 0,
    this.totalItemCount = 1,
    this.description,
    this.containerNumber,
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
      caseNumber: json['case_number'] as String?,
      originCountry: json['origin_country'] as String? ?? '',
      declaredValue: (json['declared_value'] as num?)?.toDouble() ?? 0,
      weightKg: (json['weight_kg'] as num?)?.toDouble() ?? 0,
      totalItemCount: json['total_item_count'] as int? ?? 1,
      description: json['description'] as String?,
      containerNumber: json['container_number'] as String?,
      consigneeName: json['consignee_name'] as String,
      consigneeNic: json['consignee_nic'] as String?,
      consigneeAddress: json['consignee_address'] as String?,
      consigneePhone: json['consignee_phone'] as String?,
      declarantName: json['declarant_name'] as String?,
      cusdecNo: json['cusdec_no'] as String?,
      cusdecDate: json['cusdec_date'] as String?,
      entryDate: json['entry_date'] != null
          ? DateTime.parse(json['entry_date'] as String)
          : null,
      reason: json['reason'] as String?,
      status: json['status'] as String? ?? 'pending',
      inspectedBy: json['inspected_by'] as String?,
      inspectedByName: json['profiles'] != null
          ? json['profiles']['full_name'] as String?
          : null,
      inspectedByBadge: json['profiles'] != null
          ? json['profiles']['badge_number'] as String?
          : null,
      inspectedAt: json['inspected_at'] != null
          ? DateTime.parse(json['inspected_at'] as String)
          : null,
      clearedAt: json['cleared_at'] != null
          ? DateTime.parse(json['cleared_at'] as String)
          : null,
      notes: json['notes'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
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
      'case_number': caseNumber,
      'origin_country': originCountry,
      'declared_value': declaredValue,
      'weight_kg': weightKg,
      'total_item_count': totalItemCount,
      'description': description,
      'container_number': containerNumber,
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
    String? caseNumber,
    String? originCountry,
    double? declaredValue,
    double? weightKg,
    int? totalItemCount,
    String? description,
    String? containerNumber,
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
      caseNumber: caseNumber ?? this.caseNumber,
      originCountry: originCountry ?? this.originCountry,
      declaredValue: declaredValue ?? this.declaredValue,
      weightKg: weightKg ?? this.weightKg,
      totalItemCount: totalItemCount ?? this.totalItemCount,
      description: description ?? this.description,
      containerNumber: containerNumber ?? this.containerNumber,
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
    if (st == 'forfeit' || st == 'forfeited' || st == 'forfiet' ||
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
  final int quantity;
  final String unitOfMeasure;
  final String? unitOther;
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
    required this.quantity,
    this.unitOfMeasure = 'Pieces',
    this.unitOther,
    this.unitValue = 0,
    this.hsCode,
    this.category,
    this.isProhibited = false,
    this.status = 'pending', // Default to pending
    this.reasons,
    this.notes,
  });

  factory PackageItem.fromJson(Map<String, dynamic> json) {
    return PackageItem(
      id: json['id'] as String,
      packageId: json['package_id'] as String,
      itemName: json['item_name'] as String,
      goodsDescription: json['goods_description'] as String?,
      quantity: json['quantity'] as int,
      unitOfMeasure: json['unit_of_measure'] as String? ?? 'Pieces',
      unitOther: json['unit_other'] as String?,
      unitValue: (json['unit_value'] as num?)?.toDouble() ?? 0,
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
      'quantity': quantity,
      'unit_of_measure': unitOfMeasure,
      'unit_other': unitOther,
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
    int? quantity,
    String? unitOfMeasure,
    String? unitOther,
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
      quantity: quantity ?? this.quantity,
      unitOfMeasure: unitOfMeasure ?? this.unitOfMeasure,
      unitOther: unitOther ?? this.unitOther,
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
      itemCount: json['item_count'] as int,
      admittedBy: json['admitted_by'] as String?,
      admittedByName: (json['admitted_profile']
          as Map<String, dynamic>?)?['full_name'] as String?,
      admittedByBadge: (json['admitted_profile']
          as Map<String, dynamic>?)?['badge_number'] as String?,
      admittedAt: DateTime.parse(json['admitted_at'] as String),
      isReturned: json['is_returned'] as bool? ?? false,
      returnedAt: json['returned_at'] != null
          ? DateTime.parse(json['returned_at'] as String)
          : null,
      returnedBy: json['returned_by'] as String?,
      returnedByName: (json['returned_profile']
          as Map<String, dynamic>?)?['full_name'] as String?,
      returnedByBadge: (json['returned_profile']
          as Map<String, dynamic>?)?['badge_number'] as String?,
      returnNotes: json['return_notes'] as String?,
      dailyRate: (json['daily_rate'] as num?)?.toDouble() ?? 0,
      accumulatedCharge:
          (json['accumulated_storage_charge'] as num?)?.toDouble() ?? 0,
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
      final allSeized = items.every((i) => isNoChargeStatus(i.status.toLowerCase()));
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
      capacity: json['capacity'] as int? ?? 500,
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
      profileImageUrl: json['profile_image_url'] as String?,
      role: json['role'] as String,
      isActive: json['is_active'] as bool? ?? true,
      isOnline: json['is_online'] as bool? ?? false,
      lastSeenAt: json['last_seen_at'] != null ? DateTime.parse(json['last_seen_at'] as String).toLocal() : null,
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      passwordUpdatedAt: json['password_updated_at'] != null ? DateTime.parse(json['password_updated_at'] as String).toLocal() : null,
    );
  }

  bool get isAdmin => role == 'admin';

  /// Yard officer (front-line yard staff, not a directorate account).
  bool get isOfficer => role == 'officer';

  /// True for accounts that belong to a physical yard (admin or officer), as
  /// opposed to the head-office directorate roles.
  bool get isYardStaff => isAdmin || isOfficer;

  /// Central Disposal Directorate user (cross-yard sold-package visibility).
  bool get isDisposal => role == 'disposal';

  /// Accounts automatically deactivate 8 months after they were created.
  /// (Applies to admins and officers alike.)
  DateTime get expiresAt =>
      DateTime(createdAt.year, createdAt.month + 8, createdAt.day,
          createdAt.hour, createdAt.minute, createdAt.second);

  /// Appeal Directorate (AD/ADD) user — cross-yard forfeited-package review +
  /// appeal-hold authority.
  bool get isAppeal => role == 'appeal';

  /// Valuation Directorate (DC/SDDC) user — cross-yard valuation of disposal
  /// requests before they reach the Central Disposal Directorate.
  bool get isValuation => role == 'valuation';

  /// True once the account is past its 8-month lifetime. Directorate accounts
  /// (Disposal DC/SDDC, Appeal AD/ADD, Valuation DC/SDDC) are institutional and
  /// never auto-expire (officers transfer in/out of the post).
  bool get isExpired =>
      !isDisposal && !isAppeal && !isValuation &&
      DateTime.now().isAfter(expiresAt);

  /// Whether the account may currently sign in: explicitly active AND not
  /// past its 8-month auto-deactivation window.
  bool get isEffectivelyActive => isActive && !isExpired;

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

class AuditLogModel {
  final String id;
  final String userId;
  final String action;
  final String entityType;
  final String entityId;
  final Map<String, dynamic>? details;
  final DateTime createdAt;
  // Joined field
  final String? userFullName;

  const AuditLogModel({
    required this.id,
    required this.userId,
    required this.action,
    required this.entityType,
    required this.entityId,
    this.details,
    required this.createdAt,
    this.userFullName,
  });

  factory AuditLogModel.fromJson(Map<String, dynamic> json) {
    return AuditLogModel(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      action: json['action'] as String,
      entityType: json['entity_type'] as String,
      entityId: json['entity_id'] as String,
      details: json['details'] as Map<String, dynamic>?,
      createdAt: DateTime.parse(json['created_at'] as String),
      userFullName:
          (json['profiles'] as Map<String, dynamic>?)?['full_name'] as String?,
    );
  }
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
        final note = appealDecisionNoteForItem(id);
        return (note?.trim().isNotEmpty == true) ? note!.trim() : 'Other';
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
      forfeitedAt: DateTime.parse(json['forfeited_at'] as String),
      appealDeadline: DateTime.parse(json['appeal_deadline'] as String),
      reason: json['reason'] as String? ?? '',
      yard: json['yard'] as String?,
      source: json['source'] as String? ?? 'forfeit',
      appealHold: json['appeal_hold'] as bool? ?? false,
      appealHoldNote: json['appeal_hold_note'] as String?,
      appealHeldAt: json['appeal_held_at'] != null
          ? DateTime.parse(json['appeal_held_at'] as String).toLocal()
          : null,
      heldItemIds: (json['held_item_ids'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      appealDecision: json['appeal_decision'] as String?,
      appealDecisionNote: json['appeal_decision_note'] as String?,
      appealDecidedAt: json['appeal_decided_at'] != null
          ? DateTime.parse(json['appeal_decided_at'] as String).toLocal()
          : null,
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
      entryQty: json['entry_qty'] as int?,
      // valuation_cost lives on disposal_request_items, not forfeited_packages.
      // When this model is hydrated from a nested join (getTenderSales /
      // getDestructions), the disposal_request_items list is included; pick the
      // first non-null cost from it. Fall back to the direct column in case the
      // column is ever added to the table in future.
      valuationCost: (() {
        final direct = (json['valuation_cost'] as num?)?.toDouble();
        if (direct != null) return direct;
        final items = json['disposal_request_items'] as List?;
        if (items == null) return null;
        for (final row in items) {
          final cost = (row['valuation_cost'] as num?)?.toDouble();
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
      tenderDate: DateTime.parse(json['tender_date'] as String),
      saleDate: json['sale_date'] != null
          ? DateTime.tryParse(json['sale_date'].toString())
          : null,
      saleTime: json['sale_time'] as String?,
      forfeitedPackageIds: ids,
      createdAt: DateTime.parse(json['created_at'] as String),
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
      disposedAt: DateTime.parse(json['disposed_at'] as String),
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
      receiptNumber: json['receipt_number'] as String?,
      forfeited: json['forfeited_packages'] != null
          ? ForfeitedPackageModel.fromJson(
              json['forfeited_packages'] as Map<String, dynamic>)
          : null,
      soldPrice: (json['sold_price'] as num?)?.toDouble() ?? 0.0,
      appliedTaxes: json['applied_taxes'] as List<dynamic>? ?? const [],
      isDelivered: json['is_delivered'] as bool? ?? false,
      deliveredAt: json['delivered_at'] != null
          ? DateTime.tryParse(json['delivered_at'].toString())
          : null,
    );
  }

  /// The yard this tender item belongs to; falls back to the forfeited package's
  /// yard when the `yard` column is empty (mirrors [DestructionItemModel]).
  String? get effectiveYard =>
      yard.isNotEmpty ? yard : forfeited?.yard;
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

  /// The moment the package leaves this sale as UNSOLD: the END of the day AFTER
  /// the sale date (i.e. the sale day + its following day). After this, an item
  /// not yet marked sold drops to the Unsold Tenders pool. Null when no date.
  DateTime? get unsoldDeadline {
    final d = saleDate;
    if (d == null) return null;
    // End of (saleDate + 1 day): 23:59:59.999 of the day after the sale day.
    return DateTime(d.year, d.month, d.day + 1, 23, 59, 59, 999);
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
      year: (json['year'] as num?)?.toInt(),
      tenderType: json['tender_type'] as String?,
      yard: json['yard'] as String?,
      saleTime: json['sale_time'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
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
  final bool delivered;
  final DateTime? deliveredAt;
  final String? notes;
  /// Price recorded when the item was marked destroyed (0 until destroyed).
  final double destroyedPrice;
  /// Taxes applied to [destroyedPrice] — list of {name, percentage, amount}.
  final List<dynamic> appliedTaxes;
  final ForfeitedPackageModel? forfeited;

  const DestructionItemModel({
    required this.id,
    required this.destructionId,
    required this.forfeitedPackageId,
    required this.yard,
    this.destroyed = false,
    this.destroyedAt,
    this.delivered = false,
    this.deliveredAt,
    this.notes,
    this.destroyedPrice = 0,
    this.appliedTaxes = const [],
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
      delivered: json['delivered'] as bool? ?? false,
      deliveredAt: json['delivered_at'] != null
          ? DateTime.tryParse(json['delivered_at'].toString())
          : null,
      notes: json['notes'] as String?,
      destroyedPrice: (json['destroyed_price'] as num?)?.toDouble() ?? 0,
      appliedTaxes: (json['applied_taxes'] as List?) ?? const [],
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
  String? get effectiveYard =>
      yard.isNotEmpty ? yard : forfeited?.yard;
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

  /// The moment the package leaves this destruction as UNDESTROYED: the END of
  /// the day AFTER the destruction date. After this, an item not yet marked
  /// destroyed drops to the Undestroyed pool. Null when no date.
  DateTime? get unsoldDeadline {
    final d = saleDate;
    if (d == null) return null;
    return DateTime(d.year, d.month, d.day + 1, 23, 59, 59, 999);
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
      year: (json['year'] as num?)?.toInt(),
      tenderType: json['tender_type'] as String?,
      yard: json['yard'] as String?,
      saleTime: json['sale_time'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
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
// window has passed. Each package is tagged for either DESTRUCTION or SALE.

/// The two disposition options offered per requested package.
const Map<String, String> kDispositions = {
  'destruction': 'Destruction',
  'sale': 'Sale',
};

String dispositionLabel(String? code) =>
    kDispositions[code] ?? (code ?? '—');

class DisposalRequestItemModel {
  final String id;
  final String requestId;
  final String forfeitedPackageId;
  final String disposition; // 'destruction' | 'sale'
  final ForfeitedPackageModel? forfeited;
  /// Per-item cost set by the Valuation Directorate (null until valued).
  final double? valuationCost;

  const DisposalRequestItemModel({
    required this.id,
    required this.requestId,
    required this.forfeitedPackageId,
    required this.disposition,
    this.forfeited,
    this.valuationCost,
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
      disposition: json['disposition'] as String? ?? 'destruction',
      forfeited: json['forfeited_packages'] != null
          ? ForfeitedPackageModel.fromJson(
              json['forfeited_packages'] as Map<String, dynamic>)
          : null,
      valuationCost: (json['valuation_cost'] as num?)?.toDouble(),
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
        .map((e) =>
            DisposalRequestItemModel.fromJson(e as Map<String, dynamic>))
        .toList();
    // 'profiles' is the created_by join; 'valued_profile' the valued_by join.
    return DisposalRequestModel(
      id: json['id'] as String,
      yard: json['yard'] as String? ?? '',
      requestDate: DateTime.parse(json['request_date'].toString()),
      status: json['status'] as String? ?? 'pending',
      createdAt: DateTime.parse(json['created_at'] as String),
      createdByName:
          (json['profiles'] as Map<String, dynamic>?)?['full_name'] as String?,
      items: items,
      valuationStatus: json['valuation_status'] as String? ?? 'forwarded',
      valuedAt: json['valued_at'] != null
          ? DateTime.parse(json['valued_at'] as String)
          : null,
      valuedByName: (json['valued_profile'] as Map<String, dynamic>?)?[
          'full_name'] as String?,
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
      createdAt: DateTime.parse(json['created_at'] as String),
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
      percentage: (json['percentage'] as num).toDouble(),
      isActive: json['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'].toString()),
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

class HoldReasonModel {
  final String id;
  final String reasonText;
  final String? description;
  final bool isActive;
  final DateTime createdAt;

  const HoldReasonModel({
    required this.id,
    required this.reasonText,
    this.description,
    this.isActive = true,
    required this.createdAt,
  });

  factory HoldReasonModel.fromJson(Map<String, dynamic> json) {
    return HoldReasonModel(
      id: json['id'] as String,
      reasonText: json['reason_text'] as String,
      description: json['description'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
