import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/supabase_client.dart';
import '../models/models.dart';

// ── Auth Service ──────────────────────────────────────────────

class AuthService {
  Future<ProfileModel?> signIn(String email, String password) async {
    try {
      print('DEBUG: AuthService.signIn attempting for: "$email"');
      final response = await supabase.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      if (response.user == null) return null;
      final profileData = await supabase.from('profiles').select().eq('id', response.user!.id).single();
      final profile = ProfileModel.fromJson(profileData);
      
      if (!profile.isActive) {
        await signOut();
        throw Exception('account_deactivated');
      }

      try {
        await supabase.from('profiles').update({
          'is_online': true,
          'last_seen_at': DateTime.now().toIso8601String(),
        }).eq('id', profile.id);
      } catch (e) {
        print('DEBUG: AuthService.signIn - Status update failed: $e');
      }

      await AuditLogService().recordLog(
        userId: profile.id,
        action: 'Signed In',
        entityType: 'auth',
        entityId: profile.id,
      );

      return profile;
    } on AuthApiException catch (e) {
      if (e.statusCode == '400' && e.message.contains('email_not_confirmed')) {
        throw Exception('email_not_confirmed');
      }
      if (e.message.contains('Invalid login credentials')) {
        throw Exception('invalid_credentials');
      }
      rethrow;
    } catch (e) {
      rethrow;
    }
  }

  Future<void> signOut() async {
    final user = supabase.auth.currentUser;
    if (user != null) {
      await AuditLogService().recordLog(
        userId: user.id,
        action: 'Signed Out',
        entityType: 'auth',
        entityId: user.id,
      );
      try {
        await supabase.from('profiles').update({'is_online': false}).eq('id', user.id);
      } catch (e) {
        print('DEBUG: AuthService.signOut - Status update failed: $e');
      }
    }
    await supabase.auth.signOut();
  }

  Future<ProfileModel?> getCurrentProfile() async {
    final user = supabase.auth.currentUser;
    if (user == null) return null;
    try {
      final data = await supabase.from('profiles').select().eq('id', user.id).single();
      return ProfileModel.fromJson(data);
    } catch (_) { return null; }
  }

  bool get isLoggedIn => supabase.auth.currentUser != null;

  Future<void> updateHeartbeat() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    try {
      await supabase.from('profiles').update({
        'is_online': true,
        'last_seen_at': DateTime.now().toIso8601String(),
      }).eq('id', user.id);
    } catch (e) {
      print('DEBUG: updateHeartbeat error: $e');
    }
  }
}

// ── Package Service ──────────────────────────────────────────

class PackageService {
  Future<List<PackageModel>> getAllPackages({String? status, String? search}) async {
    var query = supabase.from('packages')
        .select('*, package_items(*), warehouse_entries(*, warehouses(*)), profiles(*)');
    if (status != null && status != 'all' && status != 'returned') query = query.eq('status', status);
    if (search != null && search.isNotEmpty) {
      query = query.or('sr_number.ilike.%$search%,consignee_name.ilike.%$search%');
    }
    final data = await query.order('created_at', ascending: false);
    return data.map((e) => PackageModel.fromJson(e)).toList();
  }

  Future<PackageModel> createPackage(PackageModel pkg, List<PackageItem> items) async {
    final user = supabase.auth.currentUser;
    final data = pkg.toInsertJson();
    if (data['inspected_by'] == null && user != null) {
      data['inspected_by'] = user.id;
      data['inspected_at'] = DateTime.now().toIso8601String();
    }
    final pkgData = await supabase.from('packages').insert(data).select().single();
    final created = PackageModel.fromJson(pkgData);
    if (items.isNotEmpty) {
      await supabase.from('package_items').insert(
        items.map((i) => i.toInsertJson(created.id)).toList(),
      );
    }
    
    if (user != null) {
      await AuditLogService().recordLog(
        userId: user.id,
        action: 'Created new package SR: ${created.srNumber}',
        entityType: 'package',
        entityId: created.id,
        details: {'consignee': created.consigneeName},
      );
    }
    
    return created;
  }

  Future<PackageModel?> getPackageBySrNumber(String srNumber) async {
    final data = await supabase
        .from('packages')
        .select('*, package_items(*), warehouse_entries(*, warehouses(*)), profiles(*)')
        .eq('sr_number', srNumber)
        .maybeSingle();
    if (data == null) return null;
    return PackageModel.fromJson(data);
  }

  Future<PackageModel?> getPackageById(String id) async {
    final data = await supabase
        .from('packages')
        .select('*, package_items(*), warehouse_entries(*, warehouses(*)), profiles(*)')
        .eq('id', id)
        .maybeSingle();
    if (data == null) return null;
    return PackageModel.fromJson(data);
  }

  Future<PackageModel> upsertPackage(PackageModel pkg, List<PackageItem> items) async {
    final existing = await getPackageBySrNumber(pkg.srNumber);

    if (existing != null) {
      await supabase.from('packages').update(pkg.toInsertJson()).eq('id', existing.id);
      await supabase.from('package_items').delete().eq('package_id', existing.id);
      if (items.isNotEmpty) {
        await supabase.from('package_items').insert(
          items.map((i) => i.toInsertJson(existing.id)).toList(),
        );
      }
      final refreshed = await supabase
          .from('packages')
          .select('*, package_items(*), warehouse_entries(*, warehouses(*)), profiles(*)')
          .eq('id', existing.id)
          .single();
      final resultP = PackageModel.fromJson(refreshed);

      final user = supabase.auth.currentUser;
      if (user != null) {
        await AuditLogService().recordLog(
          userId: user.id,
          action: 'Updated package SR: ${resultP.srNumber}',
          entityType: 'package',
          entityId: resultP.id,
        );
      }
      return resultP;
    } else {
      return createPackage(pkg, items);
    }
  }

  Future<void> updatePackageStatus(String id, String status, {String? notes}) async {
    final data = <String, dynamic>{
      'status': status,
      if (notes != null) 'notes': notes,
      'inspected_by': supabase.auth.currentUser?.id,
      'inspected_at': DateTime.now().toIso8601String(),
    };
    if (status == 'cleared') data['cleared_at'] = DateTime.now().toIso8601String();
    await supabase.from('packages').update(data).eq('id', id);
    
    final user = supabase.auth.currentUser;
    if (user != null) {
      await AuditLogService().recordLog(
        userId: user.id,
        action: 'Updated status to $status',
        entityType: 'package',
        entityId: id,
        details: {'notes': notes},
      );
    }
  }

  Future<Map<String, int>> getDashboardStats() async {
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);
    final all = await supabase.from('packages').select('status')
        .gte('created_at', startOfDay.toIso8601String());
    int cleared = 0, held = 0;
    for (final p in all) {
      if (p['status'] == 'cleared') cleared++;
      if (p['status'] == 'held') held++;
    }
    return {'total': all.length, 'cleared': cleared, 'held': held};
  }
}

// ── Warehouse Service ────────────────────────────────────────

class WarehouseService {
  Future<List<WarehouseModel>> getWarehouses() async {
    final data = await supabase.from('warehouses').select().order('code');
    return data.map((e) => WarehouseModel.fromJson(e)).toList();
  }

  Future<List<WarehouseEntryModel>> getEntriesByWarehouse(String warehouseId, {bool? isReturned}) async {
    var query = supabase.from('warehouse_entries')
        .select('*, warehouses(*), packages(*)')
        .eq('warehouse_id', warehouseId);
    if (isReturned != null) query = query.eq('is_returned', isReturned);
    final data = await query.order('admitted_at', ascending: false);
    return data.map((e) => WarehouseEntryModel.fromJson(e)).toList();
  }

  Future<List<WarehouseEntryModel>> getAllWarehouseEntries({bool? isReturned}) async {
    var query = supabase.from('warehouse_entries')
        .select('*, warehouses(*), packages(*)');
    if (isReturned != null) query = query.eq('is_returned', isReturned);
    final data = await query.order('admitted_at', ascending: false);
    return data.map((e) => WarehouseEntryModel.fromJson(e)).toList();
  }

  Future<void> addEntry({
    required String packageId,
    required String warehouseId,
    String? zone,
    required String holdReason,
    required int itemCount,
  }) async {
    final rate = await CustomsRulesService().getStorageRate();

    await supabase.from('warehouse_entries').insert({
      'package_id': packageId,
      'warehouse_id': warehouseId,
      'zone': zone,
      'hold_reason': holdReason,
      'item_count': itemCount,
      'daily_rate': rate,
      'admitted_by': supabase.auth.currentUser?.id,
      'admitted_at': DateTime.now().toIso8601String(),
    });

    final user = supabase.auth.currentUser;
    if (user != null) {
      await AuditLogService().recordLog(
        userId: user.id,
        action: 'Sent package to warehouse',
        entityType: 'warehouse_entry',
        entityId: 'new',
        details: {'package_id': packageId, 'warehouse_id': warehouseId, 'rate': rate},
      );
    }
  }

  Future<void> markAsReturned(String entryId, {String? returnNotes}) async {
    await supabase.from('warehouse_entries').update({
      'is_returned': true,
      'returned_at': DateTime.now().toIso8601String(),
      'returned_by': supabase.auth.currentUser?.id,
      if (returnNotes != null) 'return_notes': returnNotes,
    }).eq('id', entryId);

    final user = supabase.auth.currentUser;
    if (user != null) {
      await AuditLogService().recordLog(
        userId: user.id,
        action: 'Marked warehouse entry as returned',
        entityType: 'warehouse_entry',
        entityId: entryId,
      );
    }
  }

  Future<Map<String, int>> getWarehouseStats() async {
    final entries = await supabase.from('warehouse_entries')
        .select('warehouse_id, is_returned, warehouses(code)');
    final Map<String, int> stats = {};
    for (final e in entries) {
      if (e['is_returned'] == false) {
        final code = (e['warehouses'] as Map)['code'] as String;
        stats[code] = (stats[code] ?? 0) + 1;
      }
    }
    return stats;
  }
}

// ── Customs Rules Service ───────────────────────────────────

class CustomsRulesService {
  Future<List<CustomsRule>> getActiveRules() async {
    final data = await supabase.from('customs_rules').select().eq('is_active', true);
    return data.map((e) => CustomsRule.fromJson(e)).toList();
  }

  Future<List<CustomsRule>> getAllRules() async {
    final data = await supabase.from('customs_rules').select().order('rule_type');
    return data.map((e) => CustomsRule.fromJson(e)).toList();
  }

  Future<void> createRule(CustomsRule rule) async {
    final json = rule.toJson();
    if (rule.id.isEmpty) json.remove('id');
    await supabase.from('customs_rules').insert({
      ...json,
      'created_by': supabase.auth.currentUser?.id,
    });
    final user = supabase.auth.currentUser;
    if (user != null) {
      await AuditLogService().recordLog(
        userId: user.id,
        action: 'Created rule "${rule.ruleName}"',
        entityType: 'customs_rule',
        entityId: 'new',
      );
    }
  }

  Future<void> toggleRule(String id, bool isActive) async {
    await supabase.from('customs_rules').update({'is_active': isActive}).eq('id', id);
    final user = supabase.auth.currentUser;
    if (user != null) {
      await AuditLogService().recordLog(
        userId: user.id,
        action: '${isActive ? 'Activated' : 'Deactivated'} rule',
        entityType: 'customs_rule',
        entityId: id,
      );
    }
  }

  Future<void> deleteRule(String id) async {
    await supabase.from('customs_rules').delete().eq('id', id);
    final user = supabase.auth.currentUser;
    if (user != null) {
      await AuditLogService().recordLog(
        userId: user.id,
        action: 'Deleted rule',
        entityType: 'customs_rule',
        entityId: id,
      );
    }
  }

  Future<List<String>> checkPackageAgainstRules({
    required double declaredValue,
    required double weightKg,
    required int itemCount,
    required List<PackageItem> items,
  }) async {
    final rules = await getActiveRules();
    final List<String> violations = [];
    for (final rule in rules) {
      switch (rule.ruleType) {
        case 'max_value':
          if (declaredValue > (rule.thresholdValue ?? 0)) {
            violations.add('${rule.ruleName}: Declared value LKR ${declaredValue.toStringAsFixed(2)} exceeds limit of LKR ${rule.thresholdValue?.toStringAsFixed(2)}');
          }
          break;
        case 'max_weight':
          if (weightKg > (rule.thresholdValue ?? 0)) {
            violations.add('${rule.ruleName}: Weight ${weightKg}kg exceeds limit of ${rule.thresholdValue}kg');
          }
          break;
        case 'max_items':
          if (itemCount > (rule.thresholdValue ?? 0)) {
            violations.add('${rule.ruleName}: Item count $itemCount exceeds limit of ${rule.thresholdValue?.toInt()}');
          }
          break;
        case 'prohibited_category':
          final prohibited = rule.stringValue?.toLowerCase() ?? '';
          for (final item in items) {
            if ((item.category?.toLowerCase() ?? '').contains(prohibited) || item.isProhibited) {
              violations.add('${rule.ruleName}: Item "${item.itemName}" falls under prohibited category');
              break;
            }
          }
          break;
      }
    }
    return violations;
  }

  Future<double> getStorageRate() async {
    try {
      final data = await supabase
          .from('audit_logs')
          .select('details')
          .eq('entity_type', 'storage_rate')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (data == null || data['details'] == null) return 0.0;
      return (data['details']['rate'] as num?)?.toDouble() ?? 0.0;
    } catch (_) { return 0.0; }
  }

  Future<void> updateStorageRate(double rate) async {
    final user = supabase.auth.currentUser;
    if (user != null) {
      await AuditLogService().recordLog(
        userId: user.id,
        action: 'Updated Daily Storage Rate: $rate LKR',
        entityType: 'storage_rate',
        entityId: 'config',
        details: {'rate': rate},
      );
    }
  }

  Future<List<AuditLogModel>> getStorageRateHistory() async {
    final data = await supabase
        .from('audit_logs')
        .select('*, profiles(full_name)')
        .eq('entity_type', 'storage_rate')
        .order('created_at', ascending: false);
    return data.map((e) => AuditLogModel.fromJson(e)).toList();
  }
}

// ── Admin Service ────────────────────────────────────────────

class AdminService {
  Future<List<ProfileModel>> getAllProfiles() async {
    final data = await supabase.from('profiles').select().order('created_at');
    return data.map((e) => ProfileModel.fromJson(e)).toList();
  }

  Future<void> createOfficer({
    required String email,
    required String password,
    required String fullName,
    required String badgeNumber,
    required String role,
  }) async {
    final response = await supabase.auth.signUp(
      email: email,
      password: password,
      data: {'full_name': fullName, 'role': role, 'badge_number': badgeNumber},
    );

    if (response.user != null) {
      try {
        await supabase.from('profiles').upsert({
          'id': response.user!.id,
          'full_name': fullName,
          'badge_number': badgeNumber,
          'role': role,
          'is_active': true,
        });
      } catch (_) {}
    } else {
      throw Exception('Already registered or unable to register this email.');
    }

    final admin = supabase.auth.currentUser;
    if (admin != null) {
      await AuditLogService().recordLog(
        userId: admin.id,
        action: 'Created officer "$fullName"',
        entityType: 'profile',
        entityId: 'new',
      );
    }
  }

  Future<void> toggleUserStatus(String profileId, bool isActive) async {
    await supabase.from('profiles').update({'is_active': isActive}).eq('id', profileId);
    final user = supabase.auth.currentUser;
    if (user != null) {
      await AuditLogService().recordLog(
        userId: user.id,
        action: '${isActive ? 'Activated' : 'Deactivated'} user status',
        entityType: 'profile',
        entityId: profileId,
      );
    }
  }

  Future<void> updateProfile(String id, {String? fullName, String? badgeNumber, String? role}) async {
    final updates = <String, dynamic>{};
    if (fullName != null) updates['full_name'] = fullName;
    if (badgeNumber != null) updates['badge_number'] = badgeNumber;
    if (role != null) updates['role'] = role;
    if (updates.isNotEmpty) {
      await supabase.from('profiles').update(updates).eq('id', id);
      final admin = supabase.auth.currentUser;
      if (admin != null) {
        await AuditLogService().recordLog(
          userId: admin.id,
          action: 'Updated profile info',
          entityType: 'profile',
          entityId: id,
          details: updates,
        );
      }
    }
  }
}

// ── Audit Log Service ──────────────────────────────────────────

class AuditLogService {
  Future<List<AuditLogModel>> getAllLogs() async {
    final data = await supabase
        .from('audit_logs')
        .select('*, profiles(full_name)')
        .order('created_at', ascending: false);
    return data.map((e) => AuditLogModel.fromJson(e)).toList();
  }

  Future<void> recordLog({
    required String userId,
    required String action,
    required String entityType,
    required String entityId,
    Map<String, dynamic>? details,
  }) async {
    try {
      await supabase.from('audit_logs').insert({
        'user_id': userId,
        'action': action,
        'entity_type': entityType,
        'entity_id': entityId,
        'details': details,
      });
    } catch (e) {
      print('DEBUG: AuditLogService.recordLog error: $e');
    }
  }

  Future<String?> getPackageCreator(String packageId) async {
    try {
      final res = await supabase
          .from('audit_logs')
          .select('profiles(full_name, badge_number)')
          .eq('entity_type', 'package')
          .eq('entity_id', packageId)
          .like('action', 'Created new package%')
          .maybeSingle();

      if (res != null && res['profiles'] != null) {
        final profile = res['profiles'];
        final name = profile['full_name'] as String?;
        final badge = profile['badge_number'] as String?;
        if (name != null) {
          return '$name${badge != null ? " (Salary No: $badge)" : ""}';
        }
      }
    } catch (e) {
      print('DEBUG: AuditLogService.getPackageCreator error: $e');
    }
    return null;
  }
}

// ── Hold Reason Service ───────────────────────────────────────

class HoldReasonService {
  Future<List<HoldReasonModel>> getReasons() async {
    final res = await supabase.from('hold_reasons').select().order('reason_text', ascending: true);
    return (res as List).map((json) => HoldReasonModel.fromJson(json)).toList();
  }

  Future<void> addReason(String reasonText, String? description) async {
    await supabase.from('hold_reasons').insert({
      'reason_text': reasonText,
      'description': description,
      'is_active': true,
    });
  }

  Future<void> updateReason(String id, String reasonText, String? description) async {
    await supabase.from('hold_reasons').update({
      'reason_text': reasonText,
      'description': description,
    }).eq('id', id);
  }

  Future<void> toggleReasonActive(String id, bool isActive) async {
    await supabase.from('hold_reasons').update({
      'is_active': isActive,
    }).eq('id', id);
  }

  Future<void> deleteReason(String id) async {
    await supabase.from('hold_reasons').delete().eq('id', id);
  }
}

// ── Package Category Service ──────────────────────────────────

class PackageCategoryService {
  Future<List<PackageCategory>> getCategories() async {
    final data = await supabase.from('package_categories').select('*, warehouses(name)').order('name');
    return data.map((e) => PackageCategory.fromJson(e)).toList();
  }

  Future<void> createCategory(String name, {String? description, String? targetWarehouseId, String? targetZone}) async {
    await supabase.from('package_categories').insert({
      'name': name,
      'description': description,
      'target_warehouse_id': targetWarehouseId,
      'target_zone': targetZone,
    });
    
    final user = supabase.auth.currentUser;
    if (user != null) {
      await AuditLogService().recordLog(
        userId: user.id,
        action: 'Created package category: $name',
        entityType: 'package_category',
        entityId: 'new',
      );
    }
  }

  Future<void> updateCategory(String id, String name, {String? description, String? targetWarehouseId, String? targetZone}) async {
    await supabase.from('package_categories').update({
      'name': name,
      'description': description,
      'target_warehouse_id': targetWarehouseId,
      'target_zone': targetZone,
    }).eq('id', id);
    
    final user = supabase.auth.currentUser;
    if (user != null) {
      await AuditLogService().recordLog(
        userId: user.id,
        action: 'Updated package category: $name',
        entityType: 'package_category',
        entityId: id,
      );
    }
  }

  Future<void> deleteCategory(String id) async {
    await supabase.from('package_categories').delete().eq('id', id);
    
    final user = supabase.auth.currentUser;
    if (user != null) {
      await AuditLogService().recordLog(
        userId: user.id,
        action: 'Deleted package category',
        entityType: 'package_category',
        entityId: id,
      );
    }
  }
}
