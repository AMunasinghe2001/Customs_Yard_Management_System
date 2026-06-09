import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/supabase_client.dart';
import '../core/app_session.dart';
import '../core/yards.dart';
import '../models/models.dart';

bool _isForfeitStatus(String? status) {
  if (status == null) return false;
  final normalized = status.trim().toLowerCase();
  return normalized == 'forfiet' || normalized == 'forfeit' || normalized == 'forfeited';
}

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

    AppSession.setYard(profile.yard);
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

      AppSession.setYard(profile.yard);

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
      print('DEBUG: signIn AuthApiException code=${e.code} status=${e.statusCode} msg=${e.message}');
      final msg = e.message.toLowerCase();
      if (e.code == 'email_not_confirmed' || msg.contains('not confirmed')) {
        throw Exception('email_not_confirmed');
      }
      if (e.code == 'invalid_credentials' ||
          msg.contains('invalid login credentials')) {
        throw Exception('invalid_credentials');
      }
      rethrow;
    } catch (e) {
      print('DEBUG: signIn unexpected error: $e');
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
    AppSession.clear();
    await supabase.auth.signOut();
  }

  Future<ProfileModel?> getCurrentProfile() async {
    final user = supabase.auth.currentUser;
    if (user == null) return null;
    try {
      final data =
          await supabase.from('profiles').select().eq('id', user.id).single();
      final profile = ProfileModel.fromJson(data);
      AppSession.setYard(profile.yard);
      return profile;
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
  Future<String> getNextSrNumber({String? yard}) async {
    final now = DateTime.now();
    final year = now.year;
    final startOfYear = DateTime(year, 1, 1).toIso8601String();
    final prefix =
        yardSrPrefix(yard ?? AppSession.currentYard); // e.g. GL1, RCT...

    // Get the latest SR number for the current yard & year
    final response = await supabase
        .from('packages')
        .select('sr_number')
        .gte('created_at', startOfYear)
        .ilike('sr_number', '$prefix/SR/%/$year')
        .order('created_at', ascending: false)
        .limit(1);

    int nextNum = 1;
    if (response != null && (response as List).isNotEmpty) {
      final lastSr = response[0]['sr_number'] as String;
      // Extract number from <PREFIX>/SR/XX/YYYY
      final parts = lastSr.split('/');
      if (parts.length >= 3) {
        final lastNum = int.tryParse(parts[2]);
        if (lastNum != null) {
          nextNum = lastNum + 1;
        }
      }
    }

    final formattedNum = nextNum.toString().padLeft(2, '0');
    return '$prefix/SR/$formattedNum/$year';
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
      PackageModel pkg, List<PackageItem> items,
      {String? yard}) async {
    final user = supabase.auth.currentUser;
    final effectiveYard = yard ?? AppSession.currentYard;
    final data = pkg.toInsertJson();
    data['yard'] = effectiveYard;
    if (data['inspected_by'] == null && user != null) {
      data['inspected_by'] = user.id;
      data['inspected_at'] = DateTime.now().toIso8601String();
    }
    final pkgData =
        await supabase.from('packages').insert(data).select().single();
    final createdId = pkgData['id'] as String;

    if (items.isNotEmpty) {
      await supabase.from('package_items').upsert(
            items
                .map((i) => {
                      ...i.toInsertJson(createdId),
                      'yard': effectiveYard,
                    })
                .toList(),
          );
    }

    final refreshedData = await supabase
        .from('packages')
        .select(
            '*, package_items(*), warehouse_entries(*, warehouses(*)), profiles(*)')
        .eq('id', createdId)
        .limit(1)
        .maybeSingle();
    final created = PackageModel.fromJson(refreshedData ?? {});

    // Sync to Forfeited Packages if applicable
    final hasForfeit = _isForfeitStatus(pkg.status) ||
      items.any((i) => _isForfeitStatus(i.status));
    if (hasForfeit) {
      final existingForfeited = await supabase
          .from('forfeited_packages')
          .select('id')
          .eq('package_id', created.id)
          .maybeSingle();
      if (existingForfeited == null) {
        await ForfeitedPackageService().createForfeitedPackage(
          packageId: created.id,
          srNumber: created.srNumber,
          consigneeName: created.consigneeName,
          reason: created.reason ?? 'Forfeited item added',
        );
      }
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

  Future<PackageModel> upsertPackage(
      PackageModel pkg, List<PackageItem> items,
      {String? yard}) async {
    final effectiveYard = yard ?? AppSession.currentYard;
    // If an ID is provided, it's an explicit update to an existing record.
    // The package keeps its original yard on edit (toInsertJson omits `yard`),
    // so editing never moves a record between yards.
    if (pkg.id.isNotEmpty) {
      await supabase.from('packages').update({
        ...pkg.toInsertJson(),
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', pkg.id);

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
          await supabase
              .from('package_items')
              .delete()
              .inFilter('id', idsToDelete);
        }

        // Use upsert to handle both updates and inserts efficiently
        await supabase.from('package_items').upsert(
              items
                  .map((item) => {
                        ...item.toInsertJson(pkg.id),
                        'yard': effectiveYard,
                      })
                  .toList(),
            );
      }

      final refreshed = await supabase
          .from('packages')
          .select(
              '*, package_items(*), warehouse_entries(*, warehouses(*)), profiles(*)')
          .eq('id', pkg.id)
          .limit(1)
          .maybeSingle();

      if (refreshed == null) return PackageModel.fromJson({}); // Fallback or handle null
      final result = PackageModel.fromJson(refreshed);

      // Sync to Forfeited Packages if applicable
        final hasForfeit = _isForfeitStatus(pkg.status) ||
          items.any((i) => _isForfeitStatus(i.status));
      if (hasForfeit) {
        final existingForfeited = await supabase
            .from('forfeited_packages')
            .select('id')
            .eq('package_id', result.id)
            .maybeSingle();
        if (existingForfeited == null) {
          await ForfeitedPackageService().createForfeitedPackage(
            packageId: result.id,
            srNumber: result.srNumber,
            consigneeName: result.consigneeName,
            reason: result.reason ?? 'Item marked as forfeited',
          );
        }
      } else {
        // Remove if no items are forfeited anymore
        await supabase.from('forfeited_packages').delete().eq('package_id', result.id);
      }

      return result;
    } else {
      // If no ID is provided, create a new record even if sr_number exists
      // (This requires that the UNIQUE constraint on sr_number is removed from the DB)
      return createPackage(pkg, items, yard: effectiveYard);
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

    // Sync to Forfeited Packages if applicable
    final isForfeited = _isForfeitStatus(status);
    
    if (isForfeited) {
      final pkgData = await supabase
          .from('packages')
          .select('sr_number, consignee_name, reason')
          .eq('id', id)
          .single();
      final existingForfeited = await supabase
          .from('forfeited_packages')
          .select('id')
          .eq('package_id', id)
          .maybeSingle();
      if (existingForfeited == null) {
        await ForfeitedPackageService().createForfeitedPackage(
          packageId: id,
          srNumber: pkgData['sr_number'] as String,
          consigneeName: pkgData['consignee_name'] as String,
          reason: pkgData['reason'] as String? ?? 'Status updated to forfeited',
        );
      }
    } else {
      // If status is no longer forfeited, remove from forfeited_packages
      await supabase.from('forfeited_packages').delete().eq('package_id', id);
    }

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
        .select(
            '*, warehouses(*), packages(*), admitted_profile:profiles!admitted_by(full_name, badge_number), returned_profile:profiles!returned_by(full_name, badge_number)')
        .eq('warehouse_id', warehouseId);
    if (isReturned != null) query = query.eq('is_returned', isReturned);
    final data = await query.order('admitted_at', ascending: false);
    return data.map((e) => WarehouseEntryModel.fromJson(e)).toList();
  }

  Future<List<WarehouseEntryModel>> getAllWarehouseEntries(
      {bool? isReturned}) async {
    var query = supabase.from('warehouse_entries').select(
        '*, warehouses(*), packages(*), admitted_profile:profiles!admitted_by(full_name, badge_number), returned_profile:profiles!returned_by(full_name, badge_number)');
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
      'yard': AppSession.currentYard,
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

  Future<void> markAsReturned(String entryId,
      {String? returnNotes, int? returnQty, List<int>? packageNumbers}) async {
    final user = supabase.auth.currentUser;
    // Append the specific released package numbers for accurate tracking.
    if (packageNumbers != null && packageNumbers.isNotEmpty) {
      final tag = 'pkgs:${packageNumbers.join(',')}';
      returnNotes =
          (returnNotes == null || returnNotes.isEmpty) ? tag : '$returnNotes | $tag';
    }

    // Attempt to get name from local providers first to avoid extra DB calls
    // But since this is a service, we'll try a simpler check

    try {
      // 1. Get the entry details
      final entryRes = await supabase
          .from('warehouse_entries')
          .select(
              'package_item_id, item_count, package_id, warehouse_id, zone, hold_reason, admitted_by, admitted_at, daily_rate, is_returned')
          .eq('id', entryId)
          .single();

      final itemId = entryRes['package_item_id'] as String?;
      int currentTotal = entryRes['item_count'] as int;

      // AUTO-REPAIR OLD DATA (where item_count was saved as 1 due to bug)
      if (itemId != null &&
          currentTotal == 1 &&
          entryRes['is_returned'] == false) {
        final itemRes = await supabase
            .from('package_items')
            .select('quantity')
            .eq('id', itemId)
            .single();
        int trueQty = itemRes['quantity'] as int;
        if (trueQty > 1) {
          // Find if there are already returned entries
          final returnedRes = await supabase
              .from('warehouse_entries')
              .select('item_count')
              .eq('package_item_id', itemId)
              .eq('is_returned', true);
          int returnedSum = (returnedRes as List)
              .fold(0, (sum, e) => sum + (e['item_count'] as int));
          if (returnedSum < trueQty) {
            currentTotal = trueQty - returnedSum;
            await supabase
                .from('warehouse_entries')
                .update({'item_count': currentTotal}).eq('id', entryId);
          }
        }
      }

      final releaseQty = returnQty ?? currentTotal;

      if (releaseQty >= currentTotal) {
        // Full return of the remaining held portion
        await supabase.from('warehouse_entries').insert({
          'package_id': entryRes['package_id'],
          'yard': AppSession.currentYard,
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
              .update({'status': 'returned'}).eq('id', itemId);
        }
      } else {
        // Partial return - always create a new returned entry (no merge)
        await supabase.from('warehouse_entries').insert({
          'package_id': entryRes['package_id'],
          'yard': AppSession.currentYard,
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
        action:
            'Marked warehouse entry as released (Qty: ${returnQty ?? "Full"})',
        entityType: 'warehouse_entry',
        entityId: entryId,
      );
    }
  }

  /// Dispose a warehouse item with a specific status (Forfeit, Abandoned, Re-export, Destroy).
  /// Closes the active warehouse entry and updates the item's status.
  /// If [qty] is provided and less than full entry count, performs a partial disposal.
  Future<void> disposeWarehouseItem(
    String entryId, {
    required String dispositionStatus,
    String? notes,
    int? qty,
    List<int>? packageNumbers,
  }) async {
    final user = supabase.auth.currentUser;

    final entryRes = await supabase
        .from('warehouse_entries')
        .select(
            'package_item_id, item_count, package_id, warehouse_id, zone, hold_reason, admitted_by, admitted_at, daily_rate')
        .eq('id', entryId)
        .single();

    final itemId = entryRes['package_item_id'] as String?;
    final currentTotal = entryRes['item_count'] as int;
    final disposeQty = (qty != null && qty > 0 && qty < currentTotal)
        ? qty
        : currentTotal;
    // Record the specific package numbers chosen so they (not just a count)
    // are tracked as processed: "pkgs:2,5,17".
    final pkgTag = (packageNumbers != null && packageNumbers.isNotEmpty)
        ? ' pkgs:${packageNumbers.join(',')}'
        : '';
    final returnNotes =
        '[${dispositionStatus.toUpperCase()}]$pkgTag${notes != null && notes.isNotEmpty ? ' — $notes' : ''}';

    if (disposeQty >= currentTotal) {
      // Full disposal — create closed history entry, delete held entry, update item status
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

      await supabase.from('warehouse_entries').delete().eq('id', entryId);

      if (itemId != null) {
        await supabase
            .from('package_items')
            .update({'status': dispositionStatus}).eq('id', itemId);
      }
    } else {
      // Partial disposal — create disposed history entry for selected qty,
      // reduce the remaining held entry count (item status stays unchanged)
      await supabase.from('warehouse_entries').insert({
        'package_id': entryRes['package_id'],
        'package_item_id': itemId,
        'warehouse_id': entryRes['warehouse_id'],
        'zone': entryRes['zone'],
        'hold_reason': entryRes['hold_reason'],
        'item_count': disposeQty,
        'admitted_by': entryRes['admitted_by'],
        'admitted_at': entryRes['admitted_at'],
        'daily_rate': entryRes['daily_rate'],
        'is_returned': true,
        'returned_at': DateTime.now().toIso8601String(),
        'returned_by': user?.id,
        'return_notes': returnNotes,
      });

      await supabase.from('warehouse_entries').update({
        'item_count': currentTotal - disposeQty,
      }).eq('id', entryId);
    }

    // If this disposition is a forfeit, register the package into the
    // forfeited-packages flow (appeal period + tender eligibility).
    // Idempotent: only one forfeited_packages record per package.
    if (_isForfeitStatus(dispositionStatus)) {
      final pkgId = entryRes['package_id'] as String;
      final existing = await supabase
          .from('forfeited_packages')
          .select('id')
          .eq('package_id', pkgId)
          .maybeSingle();
      if (existing == null) {
        final pkgRow = await supabase
            .from('packages')
            .select('sr_number, consignee_name, reason')
            .eq('id', pkgId)
            .maybeSingle();
        if (pkgRow != null) {
          await ForfeitedPackageService().createForfeitedPackage(
            packageId: pkgId,
            srNumber: pkgRow['sr_number'] as String? ?? '',
            consigneeName: pkgRow['consignee_name'] as String? ?? '',
            reason: (notes != null && notes.isNotEmpty)
                ? notes
                : (pkgRow['reason'] as String? ?? 'Forfeited via disposition'),
          );
        }
      }
    }

    if (user != null) {
      await AuditLogService().recordLog(
        userId: user.id,
        action:
            'Package item disposed: $dispositionStatus (qty: $disposeQty/$currentTotal, entry: $entryId)',
        entityType: 'warehouse_entry',
        entityId: entryId,
      );
    }
  }

  /// Records a FINAL disposition for an already abandoned/forfeited item —
  /// Released, Sale, Destroy, Re-export, or Other. Creates a closed warehouse
  /// entry tagged "[FINAL:<TYPE>]" and updates the item's status so it moves
  /// out of the Abandoned/Forfeit tables into the matching category table.
  Future<void> recordFinalDisposition({
    required String packageItemId,
    required String dispositionType, // RELEASED, SOLD, DESTROYED, RE-EXPORTED, OTHER
    required int qty,
    String? notes,
  }) async {
    final user = supabase.auth.currentUser;

    // Copy package/warehouse context from the item's most recent entry.
    final refEntry = await supabase
        .from('warehouse_entries')
        .select(
            'package_id, warehouse_id, zone, hold_reason, admitted_by, admitted_at, daily_rate')
        .eq('package_item_id', packageItemId)
        .order('admitted_at', ascending: false)
        .limit(1)
        .maybeSingle();
    if (refEntry == null) {
      throw Exception('No warehouse record found for this item');
    }

    final tag = dispositionType.toUpperCase();
    final returnNotes =
        '[FINAL:$tag]${notes != null && notes.isNotEmpty ? ' — $notes' : ''}';

    await supabase.from('warehouse_entries').insert({
      'package_id': refEntry['package_id'],
      'yard': AppSession.currentYard,
      'package_item_id': packageItemId,
      'warehouse_id': refEntry['warehouse_id'],
      'zone': refEntry['zone'],
      'hold_reason': refEntry['hold_reason'],
      'item_count': qty,
      'admitted_by': refEntry['admitted_by'],
      'admitted_at': refEntry['admitted_at'],
      'daily_rate': refEntry['daily_rate'],
      'is_returned': true,
      'returned_at': DateTime.now().toIso8601String(),
      'returned_by': user?.id,
      'return_notes': returnNotes,
    });

    const statusMap = {
      'RELEASED': 'released',
      'SOLD': 'sold',
      'DESTROYED': 'destroyed',
      'RE-EXPORTED': 're-exported',
      'OTHER': 'other',
    };
    final newStatus = statusMap[tag] ?? dispositionType.toLowerCase();
    await supabase
        .from('package_items')
        .update({'status': newStatus}).eq('id', packageItemId);

    // Goods have left the yard — remove any remaining held (non-returned)
    // warehouse entry for this item so it no longer appears in / is charged
    // by the Warehouses view.
    await supabase
        .from('warehouse_entries')
        .delete()
        .eq('package_item_id', packageItemId)
        .eq('is_returned', false);

    if (user != null) {
      await AuditLogService().recordLog(
        userId: user.id,
        action: 'Final disposition: $dispositionType (item: $packageItemId, qty: $qty)',
        entityType: 'package_item',
        entityId: packageItemId,
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
    final categoriesData =
        await supabase.from('package_categories').select('name, target_zone');
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
      if ((pkgStatus == 'cleared' || pkgStatus == 'returned') &&
          itemStatus != 'confiscated') {
        continue;
      }

      String cat = row['category']?.toString() ?? 'Uncategorized';
      if (cat.trim().isEmpty) cat = 'Uncategorized';

      final catLower = cat.toLowerCase().trim();
      final finalCat = categoryZoneMap.containsKey(catLower)
          ? originalNamesMap[catLower]!
          : 'Uncategorized';

      if (!summary.containsKey(finalCat)) {
        summary[finalCat] = {
          'category': finalCat,
          'warehouses': <String>{},
          'zones': <String>{},
          'count': 0,
        };
      }

      final entries = row['warehouse_entries'] as List? ?? [];
      final activeEntries =
          entries.where((e) => e['is_returned'] == false).toList();

      int itemActiveQty = 0;

      if (activeEntries.isEmpty) {
        // e.g. pending or confiscated without a warehouse entry
        itemActiveQty = (row['quantity'] as num?)?.toInt() ?? 0;

        // Add default targeted zone if available and not already held somewhere
        if (categoryZoneMap.containsKey(catLower)) {
          final defaultZone = categoryZoneMap[catLower];
          if (defaultZone != null &&
              defaultZone.isNotEmpty &&
              defaultZone != 'null' &&
              defaultZone != 'N/A') {
            (summary[finalCat]!['zones'] as Set<String>).add(defaultZone);
          }
        }
      } else {
        // It has warehouse entries, sum the active counts
        for (final e in activeEntries) {
          itemActiveQty += (e['item_count'] as num?)?.toInt() ?? 0;

          final wh = e['warehouses'] as Map?;
          if (wh != null && wh['code'] != null) {
            (summary[finalCat]!['warehouses'] as Set<String>)
                .add(wh['code'].toString());
          }
          if (e['zone'] != null &&
              e['zone'].toString().isNotEmpty &&
              e['zone'].toString().toUpperCase() != 'N/A') {
            (summary[finalCat]!['zones'] as Set<String>)
                .add(e['zone'].toString());
          }
        }
      }

      if (itemActiveQty > 0) {
        summary[finalCat]!['count'] =
            (summary[finalCat]!['count'] as int) + itemActiveQty;
      }
    }

    // Return mapped values, excluding zero-count aggregations to keep table clean
    return summary.values.where((v) => (v['count'] as int) > 0).map((v) {
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

  // ── Warehouse Management (CRUD) ────────────────────────────

  /// Add a new warehouse
  Future<WarehouseModel> addWarehouse({
    required String name,
    required String code,
    String? description,
    String? location,
    int capacity = 500,
  }) async {
    final data = await supabase
        .from('warehouses')
        .insert({
          'name': name,
          'code': code,
          'description': description,
          'location': location,
          'capacity': capacity,
        })
        .select()
        .single();

    final user = supabase.auth.currentUser;
    if (user != null) {
      await AuditLogService().recordLog(
        userId: user.id,
        action: 'Added warehouse',
        entityType: 'warehouse',
        entityId: data['id'],
        details: {'name': name, 'code': code},
      );
    }

    return WarehouseModel.fromJson(data);
  }

  /// Update an existing warehouse
  Future<WarehouseModel> updateWarehouse({
    required String id,
    String? name,
    String? code,
    String? description,
    String? location,
    int? capacity,
  }) async {
    final updates = <String, dynamic>{};
    if (name != null) updates['name'] = name;
    if (code != null) updates['code'] = code;
    if (description != null) updates['description'] = description;
    if (location != null) updates['location'] = location;
    if (capacity != null) updates['capacity'] = capacity;

    final data = await supabase
        .from('warehouses')
        .update(updates)
        .eq('id', id)
        .select()
        .single();

    final user = supabase.auth.currentUser;
    if (user != null) {
      await AuditLogService().recordLog(
        userId: user.id,
        action: 'Updated warehouse',
        entityType: 'warehouse',
        entityId: id,
        details: updates,
      );
    }

    return WarehouseModel.fromJson(data);
  }

  /// Delete a warehouse (only if it has no active entries)
  Future<void> deleteWarehouse(String id) async {
    // Check if warehouse has any entries
    final entries = await supabase
        .from('warehouse_entries')
        .select('id')
        .eq('warehouse_id', id)
        .eq('is_returned', false);

    if (entries.isNotEmpty) {
      throw Exception('Cannot delete warehouse with active entries');
    }

    await supabase.from('warehouses').delete().eq('id', id);

    final user = supabase.auth.currentUser;
    if (user != null) {
      await AuditLogService().recordLog(
        userId: user.id,
        action: 'Deleted warehouse',
        entityType: 'warehouse',
        entityId: id,
      );
    }
  }

  /// Get detailed warehouse statistics (for a specific warehouse)
  Future<Map<String, dynamic>> getWarehouseDetailedStats(
      String warehouseId) async {
    final warehouse = await supabase
        .from('warehouses')
        .select()
        .eq('id', warehouseId)
        .single();

    final activeEntries = await supabase
        .from('warehouse_entries')
        .select('item_count')
        .eq('warehouse_id', warehouseId)
        .eq('is_returned', false);

    final totalItems = activeEntries.fold<int>(
      0,
      (sum, entry) => sum + (entry['item_count'] as int),
    );

    return {
      'warehouse': WarehouseModel.fromJson(warehouse),
      'activeEntries': activeEntries.length,
      'totalItemsHeld': totalItems,
      'capacityUtilization':
          ((totalItems / warehouse['capacity']) * 100).toStringAsFixed(1),
    };
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
    String? yard,
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
        if (yard != null) 'yard': yard,
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
    String? yard,
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
          if (yard != null) 'yard': yard,
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
        if (yard != null) 'yard': yard,
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
    String? yard,
    String? profileImageUrl,
  }) async {
    final response = await supabase.auth.signUp(
      email: email,
      password: password,
      data: {
        'full_name': fullName,
        'role': role,
        'badge_number': badgeNumber,
        if (yard != null) 'yard': yard,
      },
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
          if (yard != null) 'yard': yard,
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
      String? yard,
      String? profileImageUrl}) async {
    final updates = <String, dynamic>{};
    if (fullName != null) updates['full_name'] = fullName;
    if (badgeNumber != null) updates['badge_number'] = badgeNumber;
    if (role != null) updates['role'] = role;
    if (mobileNumber != null) updates['mobile_number'] = mobileNumber;
    if (jobRole != null) updates['job_role'] = jobRole;
    if (department != null) updates['department'] = department;
    if (yard != null) updates['yard'] = yard;
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
        'yard': AppSession.currentYard,
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

// ── Forfeited Packages Service ──────────────────────────────

class ForfeitedPackageService {
  /// Get all forfeited packages
  /// Get all forfeited packages (that are not yet in a tender)
  Future<List<ForfeitedPackageModel>> getForfeitedPackages() async {
    // 1. Get IDs of packages already in a tender
    final tendersData = await supabase.from('tenders').select('forfeited_package_ids');
    final tenderedIds = (tendersData as List)
        .expand((t) => (t['forfeited_package_ids'] as List))
        .map((e) => e.toString())
        .toSet();

    // 2. Fetch forfeited packages
    final data = await supabase
        .from('forfeited_packages')
        .select(
            '*, packages(*, package_items(*), warehouse_entries(*, warehouses(*), returned_profile:profiles!returned_by(full_name, badge_number)))')
        .order('appeal_deadline', ascending: true);

    // 3. Filter out tendered and map to models
    return (data as List)
        .where((e) => !tenderedIds.contains(e['id']))
        .map((e) => ForfeitedPackageModel.fromJson(e))
        .toList();
  }

  /// Get forfeited packages where appeal has expired (> 30 days) and not tendered
  Future<List<ForfeitedPackageModel>> getExpiredAppealPackages() async {
    // 1. Get IDs of packages already in a tender
    final tendersData = await supabase.from('tenders').select('forfeited_package_ids');
    final tenderedIds = (tendersData as List)
        .expand((t) => (t['forfeited_package_ids'] as List))
        .map((e) => e.toString())
        .toSet();

    // 2. Fetch expired packages
    final data = await supabase
        .from('forfeited_packages')
        .select(
            '*, packages(*, package_items(*), warehouse_entries(*, warehouses(*), returned_profile:profiles!returned_by(full_name, badge_number)))')
        .lt('appeal_deadline', DateTime.now().toIso8601String())
        .order('appeal_deadline', ascending: true);

    // 3. Filter out tendered and map to models
    return (data as List)
        .where((e) => !tenderedIds.contains(e['id']))
        .map((e) => ForfeitedPackageModel.fromJson(e))
        .toList();
  }

  /// Create a forfeited package record
  Future<ForfeitedPackageModel> createForfeitedPackage({
    required String packageId,
    required String srNumber,
    required String consigneeName,
    required String reason,
  }) async {
    final appealDeadline = DateTime.now().add(const Duration(days: 30));
    final data = await supabase
        .from('forfeited_packages')
        .insert({
          'package_id': packageId,
          'yard': AppSession.currentYard,
          'sr_number': srNumber,
          'consignee_name': consigneeName,
          'forfeited_at': DateTime.now().toIso8601String(),
          'appeal_deadline': appealDeadline.toIso8601String(),
          'reason': reason,
        })
        .select(
            '*, packages(*, package_items(*), warehouse_entries(*, warehouses(*), returned_profile:profiles!returned_by(full_name, badge_number)))')
        .limit(1)
        .maybeSingle();

    final user = supabase.auth.currentUser;
    if (user != null && data != null) {
      await AuditLogService().recordLog(
        userId: user.id,
        action: 'Created forfeited package record',
        entityType: 'forfeited_package',
        entityId: data['id'],
        details: {'sr_number': srNumber},
      );
    }

    return ForfeitedPackageModel.fromJson(data ?? {});
  }

  /// Delete forfeited packages by ID
  Future<void> deleteForfeitedPackages(List<String> packageIds) async {
    if (packageIds.isEmpty) return;

    await supabase
        .from('forfeited_packages')
        .delete()
        .inFilter('id', packageIds);

    final user = supabase.auth.currentUser;
    if (user != null) {
      await AuditLogService().recordLog(
        userId: user.id,
        action: 'Deleted forfeited packages',
        entityType: 'forfeited_package',
        entityId: packageIds.first,
        details: {'deleted_count': packageIds.length},
      );
    }
  }
}

// ── Tenders Service ────────────────────────────────────────────

class TendersService {
  /// Get all tenders
  Future<List<TenderModel>> getTenders() async {
    final data = await supabase
        .from('tenders')
        .select('*, profiles(full_name)')
        .order('tender_date', ascending: false);
    return data.map((e) => TenderModel.fromJson(e)).toList();
  }

  /// Create a new tender and delete associated forfeited packages
  Future<TenderModel> createTender({
    required String tenderNumber,
    required DateTime tenderDate,
    required List<String> forfeitedPackageIds,
  }) async {
    // Create tender record
    final data = await supabase
        .from('tenders')
        .insert({
          'tender_number': tenderNumber,
          'yard': AppSession.currentYard,
          'tender_date': tenderDate.toIso8601String(),
          'forfeited_package_ids': forfeitedPackageIds,
          'created_by': supabase.auth.currentUser?.id,
        })
        .select('*, profiles(full_name)')
        .single();

    // Note: We no longer delete forfeited packages because tender_disposals
    // needs to reference them via FK. They are filtered in UI.
    // await ForfeitedPackageService().deleteForfeitedPackages(forfeitedPackageIds);

    final user = supabase.auth.currentUser;
    if (user != null) {
      await AuditLogService().recordLog(
        userId: user.id,
        action: 'Created tender',
        entityType: 'tender',
        entityId: data['id'],
        details: {
          'tender_number': tenderNumber,
          'packages_count': forfeitedPackageIds.length,
        },
      );
    }

    return TenderModel.fromJson(data);
  }

  /// Record disposal outcome for a package in a tender
  Future<TenderDisposalModel> recordDisposal({
    required String tenderPackageId,
    required String forfeitedPackageId,
    required String disposalType, // sold, re_export, govt_use, destroy, other
    String? receiptNumber,
    String? otherDetails,
  }) async {
    final data = await supabase
        .from('tender_disposals')
        .insert({
          'tender_package_id': tenderPackageId,
          'yard': AppSession.currentYard,
          'forfeited_package_id': forfeitedPackageId,
          'disposal_type': disposalType,
          'receipt_number': receiptNumber,
          'other_details': otherDetails,
          'disposed_by': supabase.auth.currentUser?.id,
          'disposed_at': DateTime.now().toIso8601String(),
        })
        .select('*, profiles(full_name)')
        .single();

    final user = supabase.auth.currentUser;
    if (user != null) {
      await AuditLogService().recordLog(
        userId: user.id,
        action: 'Recorded tender disposal',
        entityType: 'tender_disposal',
        entityId: data['id'],
        details: {
          'disposal_type': disposalType,
          'receipt_number': receiptNumber,
        },
      );
    }

    return TenderDisposalModel.fromJson(data);
  }

  /// Get disposals for a tender
  Future<List<TenderDisposalModel>> getDisposalsForTender(
      String tenderPackageId) async {
    final data = await supabase
        .from('tender_disposals')
        .select('*, profiles(full_name)')
        .eq('tender_package_id', tenderPackageId)
        .order('disposed_at', ascending: false);
    return data.map((e) => TenderDisposalModel.fromJson(e)).toList();
  }
}
