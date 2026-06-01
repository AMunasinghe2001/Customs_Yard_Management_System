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
  });

  factory WarehouseEntryModel.fromJson(Map<String, dynamic> json) {
    final warehouse = json['warehouses'] as Map<String, dynamic>?;
    final package = json['packages'] as Map<String, dynamic>?;
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

  /// Calculates charge considering historical rate changes across all items in the package (or specific item if tied)
  double calculatePackageCharge(
      List<PackageItem> items, Map<DateTime, double> historicalRates) {
    // If the whole package is confiscated, no charge
    if (isPackageConfiscated) return 0;

    // If this specific entry references an item, check if that item is confiscated or forfeited
    if (packageItemId != null) {
      final item = items.where((i) => i.id == packageItemId).firstOrNull;
      if (item?.status == 'confiscated' || item?.status == 'Forfeit') return 0;
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
  final String? badgeNumber;
  final String? mobileNumber;
  final String? jobRole;
  final String? department;
  final String? profileImageUrl;
  final String role;
  final bool isActive;
  final bool isOnline;
  final DateTime? lastSeenAt;
  final DateTime createdAt;

  const ProfileModel({
    required this.id,
    required this.fullName,
    this.badgeNumber,
    this.mobileNumber,
    this.jobRole,
    this.department,
    this.profileImageUrl,
    required this.role,
    required this.isActive,
    this.isOnline = false,
    this.lastSeenAt,
    required this.createdAt,
  });

  factory ProfileModel.fromJson(Map<String, dynamic> json) {
    return ProfileModel(
      id: json['id'] as String,
      fullName: json['full_name'] as String,
      badgeNumber: json['badge_number'] as String?,
      mobileNumber: json['mobile_number'] as String?,
      jobRole: json['job_role'] as String?,
      department: json['department'] as String?,
      profileImageUrl: json['profile_image_url'] as String?,
      role: json['role'] as String,
      isActive: json['is_active'] as bool? ?? true,
      isOnline: json['is_online'] as bool? ?? false,
      lastSeenAt: json['last_seen_at'] != null
          ? DateTime.tryParse(json['last_seen_at'].toString())
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  bool get isAdmin => role == 'admin';

  ProfileModel copyWithOnline(bool online, DateTime? seenAt) {
    return ProfileModel(
      id: id,
      fullName: fullName,
      badgeNumber: badgeNumber,
      mobileNumber: mobileNumber,
      jobRole: jobRole,
      department: department,
      profileImageUrl: profileImageUrl,
      role: role,
      isActive: isActive,
      isOnline: online,
      lastSeenAt: seenAt,
      createdAt: createdAt,
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
  final PackageModel? packageDetails;

  const ForfeitedPackageModel({
    required this.id,
    required this.packageId,
    required this.srNumber,
    required this.consigneeName,
    required this.forfeitedAt,
    required this.appealDeadline,
    required this.reason,
    this.packageDetails,
  });

  bool get isAppealExpired => DateTime.now().isAfter(appealDeadline);
  int get daysUntilDeadline => appealDeadline.difference(DateTime.now()).inDays;

  factory ForfeitedPackageModel.fromJson(Map<String, dynamic> json) {
    return ForfeitedPackageModel(
      id: json['id'] as String,
      packageId: json['package_id'] as String,
      srNumber: json['sr_number'] as String,
      consigneeName: json['consignee_name'] as String,
      forfeitedAt: DateTime.parse(json['forfeited_at'] as String),
      appealDeadline: DateTime.parse(json['appeal_deadline'] as String),
      reason: json['reason'] as String? ?? '',
      packageDetails: json['packages'] != null
          ? PackageModel.fromJson(json['packages'] as Map<String, dynamic>)
          : null,
    );
  }
}

// ── Tender Model ────────────────────────────────────────────

class TenderModel {
  final String id;
  final String tenderNumber;
  final DateTime tenderDate;
  final List<String> forfeitedPackageIds;
  final DateTime createdAt;
  final String? createdByName;

  const TenderModel({
    required this.id,
    required this.tenderNumber,
    required this.tenderDate,
    required this.forfeitedPackageIds,
    required this.createdAt,
    this.createdByName,
  });

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
      forfeitedPackageIds: ids,
      createdAt: DateTime.parse(json['created_at'] as String),
      createdByName:
          (json['profiles'] as Map<String, dynamic>?)?['full_name'] as String?,
    );
  }
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

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'description': description,
      if (targetWarehouseId != null) 'target_warehouse_id': targetWarehouseId,
      if (targetZone != null) 'target_zone': targetZone,
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
