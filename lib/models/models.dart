class PackageModel {
  final String id;
  final String srNumber;
  final String originCountry;
  final double declaredValue;
  final double weightKg;
  final int totalItemCount;
  final String? description;
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
    this.originCountry = '',
    this.declaredValue = 0,
    this.weightKg = 0,
    this.totalItemCount = 1,
    this.description,
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
      originCountry: json['origin_country'] as String? ?? '',
      declaredValue: (json['declared_value'] as num?)?.toDouble() ?? 0,
      weightKg: (json['weight_kg'] as num?)?.toDouble() ?? 0,
      totalItemCount: json['total_item_count'] as int? ?? 1,
      description: json['description'] as String?,
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
              ?.map((e) => WarehouseEntryModel.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toInsertJson() {
    return {
      'sr_number': srNumber,
      'origin_country': originCountry,
      'declared_value': declaredValue,
      'weight_kg': weightKg,
      'total_item_count': totalItemCount,
      'description': description,
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
    };
  }

  PackageModel copyWith({
    String? status,
    String? inspectedBy,
    DateTime? inspectedAt,
    DateTime? clearedAt,
    String? notes,
    List<PackageItem>? items,
    List<WarehouseEntryModel>? warehouseEntries,
  }) {
    return PackageModel(
      id: id,
      srNumber: srNumber,
      originCountry: originCountry,
      declaredValue: declaredValue,
      weightKg: weightKg,
      totalItemCount: totalItemCount,
      description: description,
      consigneeName: consigneeName,
      consigneeNic: consigneeNic,
      consigneeAddress: consigneeAddress,
      consigneePhone: consigneePhone,
      declarantName: declarantName,
      cusdecNo: cusdecNo,
      cusdecDate: cusdecDate,
      entryDate: entryDate,
      reason: reason,
      status: status ?? this.status,
      inspectedBy: inspectedBy ?? this.inspectedBy,
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

  bool get isReturned => warehouseEntries.isNotEmpty && warehouseEntries.every((e) => e.isReturned);

  DateTime? get returnedAt {
    if (warehouseEntries.isEmpty) return null;
    final returnedEntries = warehouseEntries.where((e) => e.isReturned && e.returnedAt != null).toList();
    if (returnedEntries.isEmpty) return null;
    return returnedEntries.map((e) => e.returnedAt!).reduce((a, b) => a.isAfter(b) ? a : b);
  }
}

class PackageItem {
  final String id;
  final String packageId;
  final String itemName;
  final int quantity;
  final double unitValue;
  final String? category;
  final bool isProhibited;
  final String? notes;

  const PackageItem({
    required this.id,
    required this.packageId,
    required this.itemName,
    required this.quantity,
    this.unitValue = 0,
    this.category,
    this.isProhibited = false,
    this.notes,
  });

  factory PackageItem.fromJson(Map<String, dynamic> json) {
    return PackageItem(
      id: json['id'] as String,
      packageId: json['package_id'] as String,
      itemName: json['item_name'] as String,
      quantity: json['quantity'] as int,
      unitValue: (json['unit_value'] as num?)?.toDouble() ?? 0,
      category: json['category'] as String?,
      isProhibited: json['is_prohibited'] as bool? ?? false,
      notes: json['notes'] as String?,
    );
  }

  Map<String, dynamic> toInsertJson(String pkgId) {
    return {
      'package_id': pkgId,
      'item_name': itemName,
      'quantity': quantity,
      'unit_value': unitValue,
      'category': category,
      'is_prohibited': isProhibited,
      'notes': notes,
    };
  }
}

class WarehouseEntryModel {
  final String id;
  final String packageId;
  final String warehouseId;
  final String warehouseName;
  final String warehouseCode;
  final String holdReason;
  final int itemCount;
  final String? admittedBy;
  final String? admittedByName;
  final DateTime admittedAt;
  final bool isReturned;
  final DateTime? returnedAt;
  final String? returnedBy;
  final String? returnedByName;
  final String? returnNotes;
  // From joined packages table
  final String? srNumber;
  final String? consigneeName;
  final String? packageStatus;

  const WarehouseEntryModel({
    required this.id,
    required this.packageId,
    required this.warehouseId,
    required this.warehouseName,
    required this.warehouseCode,
    required this.holdReason,
    required this.itemCount,
    this.admittedBy,
    this.admittedByName,
    required this.admittedAt,
    this.isReturned = false,
    this.returnedAt,
    this.returnedBy,
    this.returnedByName,
    this.returnNotes,
    this.srNumber,
    this.consigneeName,
    this.packageStatus,
  });

  factory WarehouseEntryModel.fromJson(Map<String, dynamic> json) {
    final warehouse = json['warehouses'] as Map<String, dynamic>?;
    final package = json['packages'] as Map<String, dynamic>?;
    return WarehouseEntryModel(
      id: json['id'] as String,
      packageId: json['package_id'] as String,
      warehouseId: json['warehouse_id'] as String,
      warehouseName: warehouse?['name'] as String? ?? '',
      warehouseCode: warehouse?['code'] as String? ?? '',
      holdReason: json['hold_reason'] as String,
      itemCount: json['item_count'] as int,
      admittedBy: json['admitted_by'] as String?,
      admittedByName:
          (json['admitted_profile'] as Map<String, dynamic>?)?['full_name'] as String?,
      admittedAt: DateTime.parse(json['admitted_at'] as String),
      isReturned: json['is_returned'] as bool? ?? false,
      returnedAt: json['returned_at'] != null
          ? DateTime.parse(json['returned_at'] as String)
          : null,
      returnedBy: json['returned_by'] as String?,
      returnedByName:
          (json['returned_profile'] as Map<String, dynamic>?)?['full_name'] as String?,
      returnNotes: json['return_notes'] as String?,
      srNumber: package?['sr_number'] as String?,
      consigneeName: package?['consignee_name'] as String?,
      packageStatus: package?['status'] as String?,
    );
  }

  bool get isPackageConfiscated => packageStatus == 'confiscated';
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

class CustomsRule {
  final String id;
  final String ruleName;
  final String ruleType;
  final double? thresholdValue;
  final String? stringValue;
  final bool isActive;
  final String? description;

  const CustomsRule({
    required this.id,
    required this.ruleName,
    required this.ruleType,
    this.thresholdValue,
    this.stringValue,
    required this.isActive,
    this.description,
  });

  factory CustomsRule.fromJson(Map<String, dynamic> json) {
    return CustomsRule(
      id: json['id'] as String,
      ruleName: json['rule_name'] as String,
      ruleType: json['rule_type'] as String,
      thresholdValue: (json['threshold_value'] as num?)?.toDouble(),
      stringValue: json['string_value'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      description: json['description'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'rule_name': ruleName,
      'rule_type': ruleType,
      'threshold_value': thresholdValue,
      'string_value': stringValue,
      'is_active': isActive,
      'description': description,
    };
  }
}

class ProfileModel {
  final String id;
  final String fullName;
  final String? badgeNumber;
  final String role;
  final bool isActive;
  final bool isOnline;
  final DateTime? lastSeenAt;
  final DateTime createdAt;

  const ProfileModel({
    required this.id,
    required this.fullName,
    this.badgeNumber,
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
      role: json['role'] as String,
      isActive: json['is_active'] as bool? ?? true,
      isOnline: json['is_online'] as bool? ?? false,
      lastSeenAt: json['last_seen_at'] != null ? DateTime.tryParse(json['last_seen_at'].toString()) : null,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  bool get isAdmin => role == 'admin';

  ProfileModel copyWithOnline(bool online, DateTime? seenAt) {
    return ProfileModel(
      id: id,
      fullName: fullName,
      badgeNumber: badgeNumber,
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
      userFullName: (json['profiles'] as Map<String, dynamic>?)?['full_name'] as String?,
    );
  }
}

class PackageCategory {
  final String id;
  final String name;
  final String? description;
  final DateTime createdAt;

  const PackageCategory({
    required this.id,
    required this.name,
    this.description,
    required this.createdAt,
  });

  factory PackageCategory.fromJson(Map<String, dynamic> json) {
    return PackageCategory(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'description': description,
    };
  }
}
