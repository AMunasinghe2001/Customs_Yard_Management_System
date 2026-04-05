import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/supabase_client.dart';
import '../models/models.dart';

// ── Auth Service ──────────────────────────────────────────────

class AuthService {
  Future<ProfileModel?> signInWithGoogle() async {
    try {
      await supabase.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: 'com.example.cusyardmanagement://login-callback/',
      );
      return null; // The auth state change will be handled by Supabase listener
    } catch (e) {
      print('DEBUG: AuthService.signInWithGoogle error: $e');
      rethrow;
    }
  }

  Future<void> verifyUserSession() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    // 1. Check email confirmation
    if (user.emailConfirmedAt == null) {
      await signOut();
      throw Exception('email_not_confirmed');
    }

    // 2. Check profile and role
    final profileData = await supabase
        .from('profiles')
        .select()
        .eq('id', user.id)
        .maybeSingle();
    
    if (profileData == null) {
      // If profile doesn't exist yet (first time login), it might need creation via trigger
      // But for security, we sign out if not found in our roles table
      await signOut();
      throw Exception('profile_not_found');
    }

    final profile = ProfileModel.fromJson(profileData);

    if (!profile.isActive) {
      await signOut();
      throw Exception('account_deactivated');
    }
  }

  Future<ProfileModel?> signIn(String email, String password) async {
    try {
      print('DEBUG: AuthService.signIn attempting for: "$email"');
      final response = await supabase.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      if (response.user == null) return null;
      final profileData = await supabase
          .from('profiles')
          .select()
          .eq('id', response.user!.id)
          .single();
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
        await supabase
            .from('profiles')
            .update({'is_online': false}).eq('id', user.id);
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
      final data =
          await supabase.from('profiles').select().eq('id', user.id).single();
      return ProfileModel.fromJson(data);
    } catch (_) {
      return null;
    }
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

  Future<void> setUserOffline() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    try {
      await supabase.from('profiles').update({
        'is_online': false,
      }).eq('id', user.id);
    } catch (e) {
      print('DEBUG: setUserOffline error: $e');
    }
  }
}

// ── Package Service ──────────────────────────────────────────

class PackageService {
  Future<String> getNextSrNumber() async {
    final now = DateTime.now();
    final year = now.year;
    final startOfYear = DateTime(year, 1, 1).toIso8601String();

    // Get the latest SR number for the current year
    final response = await supabase
        .from('packages')
        .select('sr_number')
        .gte('created_at', startOfYear)
        .ilike('sr_number', 'GL1/SR/%/$year')
        .order('created_at', ascending: false)
        .limit(1);

    int nextNum = 1;
    if (response != null && (response as List).isNotEmpty) {
      final lastSr = response[0]['sr_number'] as String;
      // Extract number from GL1/SR/XX/YYYY
      final parts = lastSr.split('/');
      if (parts.length >= 3) {
        final lastNum = int.tryParse(parts[2]);
        if (lastNum != null) {
          nextNum = lastNum + 1;
        }
      }
    }

    final formattedNum = nextNum.toString().padLeft(2, '0');
    return 'GL1/SR/$formattedNum/$year';
  }

  Future<PackageModel?> getPackageBySrNumber(String srNumber) async {
    final data = await supabase
      .from('packages')
      .select(
        '*, package_items(*), warehouse_entries(*, warehouses(*), returned_profile:profiles!returned_by(full_name, badge_number)), profiles(*)')
        .eq('sr_number', srNumber)
        .maybeSingle();
    if (data == null) return null;
    return PackageModel.fromJson(data);
  }

  Future<PackageModel?> getPackageById(String id) async {
    final data = await supabase
      .from('packages')
      .select(
        '*, package_items(*), warehouse_entries(*, warehouses(*), returned_profile:profiles!returned_by(full_name, badge_number)), profiles(*)')
        .eq('id', id)
        .maybeSingle();
    if (data == null) return null;
    return PackageModel.fromJson(data);
  }

  Future<List<PackageModel>> getAllPackages(
      {String? status, String? search, DateTime? since}) async {
    var query = supabase.from('packages').select(
      '*, package_items(*), warehouse_entries(*, warehouses(*), returned_profile:profiles!returned_by(full_name, badge_number)), profiles(*)');
    if (status != null && status != 'all' && status != 'returned')
      query = query.eq('status', status);
    if (since != null) query = query.gte('created_at', since.toIso8601String());
    if (search != null && search.isNotEmpty) {
      query =
          query.or('sr_number.ilike.%$search%,consignee_name.ilike.%$search%');
    }
    final data = await query.order('created_at', ascending: false);
    return data.map((e) => PackageModel.fromJson(e)).toList();
  }

  Future<PackageModel> createPackage(
      PackageModel pkg, List<PackageItem> items) async {
    final user = supabase.auth.currentUser;
    final data = pkg.toInsertJson();
    if (data['inspected_by'] == null && user != null) {
      data['inspected_by'] = user.id;
      data['inspected_at'] = DateTime.now().toIso8601String();
    }
    final pkgData =
        await supabase.from('packages').insert(data).select().single();
    final createdId = pkgData['id'] as String;

    if (items.isNotEmpty) {
      await supabase.from('package_items').insert(
            items.map((i) => i.toInsertJson(createdId)).toList(),
          );
    }

    final refreshedData = await supabase
        .from('packages')
        .select(
            '*, package_items(*), warehouse_entries(*, warehouses(*)), profiles(*)')
        .eq('id', createdId)
        .single();
    final created = PackageModel.fromJson(refreshedData);

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

  Future<PackageModel> upsertPackage(PackageModel pkg, List<PackageItem> items) async {
    // If an ID is provided, it's an explicit update to an existing record
    if (pkg.id.isNotEmpty) {
      await supabase
          .from('packages')
          .update({
            ...pkg.toInsertJson(),
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', pkg.id);
      
      // Manage items for the existing record
      if (items.isNotEmpty) {
        final existingItemsData = await supabase
            .from('package_items')
            .select('id')
            .eq('package_id', pkg.id);
        
        final existingItemIds = (existingItemsData as List)
            .map((row) => row['id'].toString())
            .toSet();
        
        final newItemIds = items
          .map((i) => i.id)
          .where((id) => id.isNotEmpty && existingItemIds.contains(id))
          .toSet();
        
        final idsToDelete = existingItemIds.difference(newItemIds).toList();
        if (idsToDelete.isNotEmpty) {
          await supabase.from('package_items').delete().inFilter('id', idsToDelete);
        }

        for (final item in items) {
          if (item.id.isNotEmpty && existingItemIds.contains(item.id)) {
            await supabase.from('package_items').update(item.toInsertJson(pkg.id)).eq('id', item.id);
          } else {
            await supabase.from('package_items').insert(item.toInsertJson(pkg.id));
          }
        }
      }

      final refreshed = await supabase
          .from('packages')
          .select('*, package_items(*), warehouse_entries(*, warehouses(*)), profiles(*)')
          .eq('id', pkg.id)
          .single();
      
      return PackageModel.fromJson(refreshed);
    } else {
      // If no ID is provided, create a new record even if sr_number exists 
      // (This requires that the UNIQUE constraint on sr_number is removed from the DB)
      return createPackage(pkg, items);
    }
  }

  Future<void> updatePackageStatus(String id, String status,
      {String? notes}) async {
    final data = <String, dynamic>{
      'status': status,
      if (notes != null) 'notes': notes,
      'inspected_by': supabase.auth.currentUser?.id,
      'inspected_at': DateTime.now().toIso8601String(),
    };
    if (status == 'cleared')
      data['cleared_at'] = DateTime.now().toIso8601String();
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

  Future<Map<String, dynamic>> getDashboardStats() async {
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);

    // Get all packages created or updated today
    final allRes = await supabase
        .from('packages')
        .select('id, status, package_items(status)')
        .or('created_at.gte.${startOfDay.toIso8601String()},updated_at.gte.${startOfDay.toIso8601String()}');

    int clearedOrReturned = 0;
    int held = 0;
    int seized = 0;

    for (final p in (allRes as List)) {
      final status = p['status'] as String;
      final items = p['package_items'] as List? ?? [];
      final hasConfiscatedItem = items.any((i) => i['status'] == 'confiscated');

      // Priority: Seized/Confiscated > Cleared/Returned > Held
      if (status == 'seized' || status == 'forfeited' || hasConfiscatedItem) {
        seized++;
      } else if (status == 'cleared' || status == 'returned') {
        clearedOrReturned++;
      } else if (status == 'held') {
        held++;
      }
    }

    // Get current storage rate (latest effective_from)
    final latestRate = await supabase
      .from('storage_rates')
      .select('rate, effective_from')
      .order('effective_from', ascending: false)
      .limit(1);

    final storageRate = latestRate.isNotEmpty
      ? (latestRate.first['rate'] as num).toDouble()
      : 0.0;

    return {
      'seized': seized,
      'cleared': clearedOrReturned,
      'held': held,
      'storageRate': storageRate,
    };
  }
}

// ── Warehouse Service ────────────────────────────────────────

class WarehouseService {
  Future<List<WarehouseModel>> getWarehouses() async {
    final data = await supabase.from('warehouses').select().order('code');
    return data.map((e) => WarehouseModel.fromJson(e)).toList();
  }

  Future<List<WarehouseEntryModel>> getEntriesByWarehouse(String warehouseId,
      {bool? isReturned}) async {
    var query = supabase
        .from('warehouse_entries')
        .select('*, warehouses(*), packages(*), admitted_profile:profiles!admitted_by(full_name, badge_number), returned_profile:profiles!returned_by(full_name, badge_number)')
        .eq('warehouse_id', warehouseId);
    if (isReturned != null) query = query.eq('is_returned', isReturned);
    final data = await query.order('admitted_at', ascending: false);
    return data.map((e) => WarehouseEntryModel.fromJson(e)).toList();
  }

  Future<List<WarehouseEntryModel>> getAllWarehouseEntries(
      {bool? isReturned}) async {
    var query = supabase
        .from('warehouse_entries')
        .select('*, warehouses(*), packages(*), admitted_profile:profiles!admitted_by(full_name, badge_number), returned_profile:profiles!returned_by(full_name, badge_number)');
    if (isReturned != null) query = query.eq('is_returned', isReturned);
    final data = await query.order('admitted_at', ascending: false);
    return data.map((e) => WarehouseEntryModel.fromJson(e)).toList();
  }

  Future<void> addEntry({
    required String packageId,
    String? packageItemId, // Added
    required String warehouseId,
    String? zone,
    required String holdReason,
    required int itemCount,
  }) async {
    final rate = 0.0;

    await supabase.from('warehouse_entries').insert({
      'package_id': packageId,
      'package_item_id': packageItemId, // Added
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
        action: 'Sent item to warehouse',
        entityType: 'warehouse_entry',
        entityId: 'new',
        details: {
          'package_id': packageId,
          'package_item_id': packageItemId,
          'warehouse_id': warehouseId
        },
      );
    }
  }

  Future<void> markAsReturned(String entryId, {String? returnNotes, int? returnQty}) async {
    final user = supabase.auth.currentUser;
    
    // Attempt to get name from local providers first to avoid extra DB calls
    // But since this is a service, we'll try a simpler check
    
    try {
      // 1. Get the entry details
      final entryRes = await supabase
          .from('warehouse_entries')
          .select('package_item_id, item_count, package_id, warehouse_id, zone, hold_reason, admitted_by, admitted_at, daily_rate, is_returned')
          .eq('id', entryId)
          .single();
      
      final itemId = entryRes['package_item_id'] as String?;
      int currentTotal = entryRes['item_count'] as int;
      
      // AUTO-REPAIR OLD DATA (where item_count was saved as 1 due to bug)
      if (itemId != null && currentTotal == 1 && entryRes['is_returned'] == false) {
         final itemRes = await supabase.from('package_items').select('quantity').eq('id', itemId).single();
         int trueQty = itemRes['quantity'] as int;
         if (trueQty > 1) {
            // Find if there are already returned entries
            final returnedRes = await supabase.from('warehouse_entries').select('item_count').eq('package_item_id', itemId).eq('is_returned', true);
            int returnedSum = (returnedRes as List).fold(0, (sum, e) => sum + (e['item_count'] as int));
            if (returnedSum < trueQty) {
                currentTotal = trueQty - returnedSum;
                await supabase.from('warehouse_entries').update({'item_count': currentTotal}).eq('id', entryId);
            }
         }
      }

      final releaseQty = returnQty ?? currentTotal;

      if (releaseQty >= currentTotal) {
        // Full return of the remaining held portion
        await supabase.from('warehouse_entries').insert({
          'package_id': entryRes['package_id'],
          'package_item_id': itemId,
          'warehouse_id': entryRes['warehouse_id'],
          'zone': entryRes['zone'],
          'hold_reason': entryRes['hold_reason'],
          'item_count': currentTotal,
          'admitted_by': entryRes['admitted_by'],
          'admitted_at': entryRes['admitted_at'],
          'daily_rate': entryRes['daily_rate'],
          'is_returned': true,
          'returned_at': DateTime.now().toIso8601String(),
          'returned_by': user?.id,
          'return_notes': returnNotes,
        });

        // Delete the held entry since it's fully returned
        await supabase.from('warehouse_entries').delete().eq('id', entryId);

        // Update the package item status to 'returned' since full quantity is now returned
        if (itemId != null) {
          await supabase
              .from('package_items')
              .update({'status': 'returned'})
              .eq('id', itemId);
        }
      } else {
        // Partial return - always create a new returned entry (no merge)
        await supabase.from('warehouse_entries').insert({
          'package_id': entryRes['package_id'],
          'package_item_id': itemId,
          'warehouse_id': entryRes['warehouse_id'],
          'zone': entryRes['zone'],
          'hold_reason': entryRes['hold_reason'],
          'item_count': releaseQty,
          'admitted_by': entryRes['admitted_by'],
          'admitted_at': entryRes['admitted_at'],
          'daily_rate': entryRes['daily_rate'],
          'is_returned': true,
          'returned_at': DateTime.now().toIso8601String(),
          'returned_by': user?.id,
          'return_notes': returnNotes,
        });

        // Update the existing held entry with remaining quantity
        await supabase.from('warehouse_entries').update({
          'item_count': currentTotal - releaseQty,
        }).eq('id', entryId);
      }
    } catch (e) {
      // If update fails, rethrow with better context
      rethrow;
    }

    if (user != null) {
      await AuditLogService().recordLog(
        userId: user.id,
        action: 'Marked warehouse entry as returned (Qty: ${returnQty ?? "Full"})',
        entityType: 'warehouse_entry',
        entityId: entryId,
      );
    }
  }

  Future<Map<String, int>> getWarehouseStats() async {
    final entries = await supabase
        .from('warehouse_entries')
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

  Future<Map<String, int>> getZoneStats() async {
    return {}; // Logic moved to Combined stats
  }

  Future<Map<String, int>> getCategoryStats() async {
    return {}; // Logic moved to Combined stats
  }

  Future<List<Map<String, dynamic>>> getCategoryZoneCombinedSummary() async {
    // 1. Fetch Categories mapping
    final categoriesData = await supabase.from('package_categories').select('name, target_zone');
    final Map<String, String> categoryZoneMap = {};
    final Map<String, String> originalNamesMap = {};
    
    for (final cat in (categoriesData as List)) {
      final cName = cat['name']?.toString();
      if (cName != null) {
        final lower = cName.toLowerCase().trim();
        categoryZoneMap[lower] = cat['target_zone']?.toString() ?? 'N/A';
        originalNamesMap[lower] = cName;
      }
    }

    // 2. Fetch all package_items with related package and warehouse entries
    final response = await supabase
        .from('package_items')
        .select('*, packages(*), warehouse_entries(*, warehouses(*))');

    final Map<String, Map<String, dynamic>> summary = {};

    for (final row in (response as List)) {
      final pkg = row['packages'] as Map?;
      if (pkg == null) continue;
      
      final pkgStatus = pkg['status'] as String?;
      final itemStatus = row['status'] as String?;
      
      // Skip returned/cleared items unless it's confiscated
      if (itemStatus == 'returned') continue;
      if ((pkgStatus == 'cleared' || pkgStatus == 'returned') && itemStatus != 'confiscated') {
        continue;
      }
      
      String cat = row['category']?.toString() ?? 'Uncategorized';
      if (cat.trim().isEmpty) cat = 'Uncategorized';
      
      final catLower = cat.toLowerCase().trim();
      final finalCat = categoryZoneMap.containsKey(catLower) ? originalNamesMap[catLower]! : 'Uncategorized';
      
      if (!summary.containsKey(finalCat)) {
         summary[finalCat] = {
            'category': finalCat,
            'warehouses': <String>{},
            'zones': <String>{},
            'count': 0,
         };
      }

      final entries = row['warehouse_entries'] as List? ?? [];
      final activeEntries = entries.where((e) => e['is_returned'] == false).toList();
      
      int itemActiveQty = 0;
      
      if (activeEntries.isEmpty) {
        // e.g. pending or confiscated without a warehouse entry
        itemActiveQty = (row['quantity'] as num?)?.toInt() ?? 0;
        
        // Add default targeted zone if available and not already held somewhere
        if (categoryZoneMap.containsKey(catLower)) {
           final defaultZone = categoryZoneMap[catLower];
           if (defaultZone != null && defaultZone.isNotEmpty && defaultZone != 'null' && defaultZone != 'N/A') {
              (summary[finalCat]!['zones'] as Set<String>).add(defaultZone);
           }
        }
      } else {
        // It has warehouse entries, sum the active counts
        for (final e in activeEntries) {
           itemActiveQty += (e['item_count'] as num?)?.toInt() ?? 0;
           
           final wh = e['warehouses'] as Map?;
           if (wh != null && wh['code'] != null) {
              (summary[finalCat]!['warehouses'] as Set<String>).add(wh['code'].toString());
           }
           if (e['zone'] != null && e['zone'].toString().isNotEmpty && e['zone'].toString().toUpperCase() != 'N/A') {
              (summary[finalCat]!['zones'] as Set<String>).add(e['zone'].toString());
           }
        }
      }
      
      if (itemActiveQty > 0) {
        summary[finalCat]!['count'] = (summary[finalCat]!['count'] as int) + itemActiveQty;
      }
    }

    // Return mapped values, excluding zero-count aggregations to keep table clean
    return summary.values
      .where((v) => (v['count'] as int) > 0)
      .map((v) {
        final whSet = v['warehouses'] as Set<String>;
        final zoneSet = v['zones'] as Set<String>;
        
        final whString = whSet.isEmpty ? 'Pending' : whSet.join(',');
        final zoneString = zoneSet.isEmpty ? 'N/A' : zoneSet.join(',');
        
        return {
          'category': v['category'],
          'warehouse': whString,
          'zone': zoneString,
          'count': v['count'],
        };
    }).toList();
  }
}

// ── Customs Rules Service ───────────────────────────────────

// Removed per request (Customs Rules logic no longer needed)

// ── Admin Service ────────────────────────────────────────────

class AdminService {
  Future<List<ProfileModel>> getAllProfiles() async {
    final data = await supabase.from('profiles').select().order('created_at');
    return data.map((e) => ProfileModel.fromJson(e)).toList();
  }

  Future<void> requestSignupOtp({
    required String email,
    required String fullName,
    required String badgeNumber,
    required String role,
    String? mobileNumber,
    String? jobRole,
    String? department,
    String? profileImageUrl,
  }) async {
    final cleanEmail = email.trim();
    print('DEBUG: Requesting OTP for clean email: "$cleanEmail"');
    await supabase.auth.signInWithOtp(
      email: cleanEmail,
      shouldCreateUser: true,
      data: {
        'full_name': fullName,
        'role': role,
        'badge_number': badgeNumber,
        if (mobileNumber != null) 'mobile_number': mobileNumber,
        if (jobRole != null) 'job_role': jobRole,
        if (department != null) 'department': department,
        if (profileImageUrl != null) 'profile_image_url': profileImageUrl,
      },
    );
  }

  Future<void> verifySignupOtp({
    required String email,
    required String otp,
    required String password,
    required String fullName,
    required String badgeNumber,
    required String role,
    String? mobileNumber,
    String? jobRole,
    String? department,
    String? profileImageUrl,
  }) async {
    final response = await supabase.auth.verifyOTP(
      email: email,
      token: otp,
      type: OtpType.signup,
    );

    final user = response.user ?? supabase.auth.currentUser;
    if (user == null) {
      throw Exception('OTP verification failed. Please try again.');
    }

    await supabase.auth.updateUser(
      UserAttributes(
        password: password,
        data: {
          'full_name': fullName,
          'role': role,
          'badge_number': badgeNumber,
          if (mobileNumber != null) 'mobile_number': mobileNumber,
          if (jobRole != null) 'job_role': jobRole,
          if (department != null) 'department': department,
          if (profileImageUrl != null) 'profile_image_url': profileImageUrl,
        },
      ),
    );

    try {
      await supabase.from('profiles').upsert({
        'id': user.id,
        'full_name': fullName,
        'badge_number': badgeNumber,
        'role': role,
        'is_active': true,
        if (mobileNumber != null) 'mobile_number': mobileNumber,
        if (jobRole != null) 'job_role': jobRole,
        if (department != null) 'department': department,
        if (profileImageUrl != null) 'profile_image_url': profileImageUrl,
      });
    } catch (_) {}

    await supabase.auth.signOut();
  }

  Future<void> createOfficer({
    required String email,
    required String password,
    required String fullName,
    required String badgeNumber,
    required String role,
    String? mobileNumber,
    String? jobRole,
    String? department,
    String? profileImageUrl,
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
          if (mobileNumber != null) 'mobile_number': mobileNumber,
          if (jobRole != null) 'job_role': jobRole,
          if (department != null) 'department': department,
          if (profileImageUrl != null) 'profile_image_url': profileImageUrl,
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
    await supabase
        .from('profiles')
        .update({'is_active': isActive}).eq('id', profileId);
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

  Future<void> updateProfile(String id,
      {String? fullName,
      String? badgeNumber,
      String? role,
      String? mobileNumber,
      String? jobRole,
      String? department,
      String? profileImageUrl}) async {
    final updates = <String, dynamic>{};
    if (fullName != null) updates['full_name'] = fullName;
    if (badgeNumber != null) updates['badge_number'] = badgeNumber;
    if (role != null) updates['role'] = role;
    if (mobileNumber != null) updates['mobile_number'] = mobileNumber;
    if (jobRole != null) updates['job_role'] = jobRole;
    if (department != null) updates['department'] = department;
    if (profileImageUrl != null) updates['profile_image_url'] = profileImageUrl;
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
    final res = await supabase
        .from('hold_reasons')
        .select()
        .order('reason_text', ascending: true);
    return (res as List).map((json) => HoldReasonModel.fromJson(json)).toList();
  }

  Future<void> addReason(String reasonText, String? description) async {
    await supabase.from('hold_reasons').insert({
      'reason_text': reasonText,
      'description': description,
      'is_active': true,
    });

    final user = supabase.auth.currentUser;
    if (user != null) {
      await AuditLogService().recordLog(
        userId: user.id,
        action: 'Added hold reason',
        entityType: 'hold_reason',
        entityId: 'new',
        details: {
          'reason_text': reasonText,
          'description': description,
        },
      );
    }
  }

  Future<void> updateReason(
      String id, String reasonText, String? description) async {
    await supabase.from('hold_reasons').update({
      'reason_text': reasonText,
      'description': description,
    }).eq('id', id);

    final user = supabase.auth.currentUser;
    if (user != null) {
      await AuditLogService().recordLog(
        userId: user.id,
        action: 'Updated hold reason',
        entityType: 'hold_reason',
        entityId: id,
        details: {
          'reason_text': reasonText,
          'description': description,
        },
      );
    }
  }

  Future<void> toggleReasonActive(String id, bool isActive) async {
    await supabase.from('hold_reasons').update({
      'is_active': isActive,
    }).eq('id', id);

    final user = supabase.auth.currentUser;
    if (user != null) {
      await AuditLogService().recordLog(
        userId: user.id,
        action: isActive ? 'Activated hold reason' : 'Deactivated hold reason',
        entityType: 'hold_reason',
        entityId: id,
        details: {
          'is_active': isActive,
        },
      );
    }
  }

  Future<void> deleteReason(String id) async {
    await supabase.from('hold_reasons').delete().eq('id', id);

    final user = supabase.auth.currentUser;
    if (user != null) {
      await AuditLogService().recordLog(
        userId: user.id,
        action: 'Deleted hold reason',
        entityType: 'hold_reason',
        entityId: id,
      );
    }
  }
}

// ── Package Category Service ──────────────────────────────────

class PackageCategoryService {
  Future<List<PackageCategory>> getCategories() async {
    final data = await supabase
        .from('package_categories')
        .select('*, warehouses(name)')
        .order('name');
    return data.map((e) => PackageCategory.fromJson(e)).toList();
  }

  Future<void> createCategory(String name,
      {String? description,
      String? targetWarehouseId,
      String? targetZone}) async {
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

  Future<void> updateCategory(String id, String name,
      {String? description,
      String? targetWarehouseId,
      String? targetZone}) async {
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
