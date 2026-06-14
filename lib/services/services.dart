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

  Future<void> updatePassword(String newPassword) async {
    await supabase.auth.updateUser(
      UserAttributes(password: newPassword),
    );
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

    if (profile.isExpired) {
      await signOut();
      throw Exception('account_expired');
    }

    AppSession.setYard(profile.yard);
  }

  /// Retries [action] a few times on transient network failures
  /// (socket timeouts, dropped Wi-Fi, retryable fetch errors). Real auth
  /// errors (bad credentials, etc.) are NOT retried.
  static Future<T> _withNetworkRetry<T>(Future<T> Function() action,
      {int retries = 2}) async {
    for (int attempt = 0;; attempt++) {
      try {
        return await action();
      } on AuthApiException {
        rethrow; // genuine auth error → don't retry
      } catch (e) {
        final s = e.toString().toLowerCase();
        final transient = s.contains('retryablefetch') ||
            s.contains('socketexception') ||
            s.contains('clientexception') ||
            s.contains('semaphore') ||
            s.contains('failed host lookup') ||
            s.contains('failedtoopensocket') ||
            s.contains('timed out');
        if (!transient || attempt >= retries) rethrow;
        await Future.delayed(Duration(milliseconds: 700 * (attempt + 1)));
      }
    }
  }

  Future<ProfileModel?> signIn(String email, String password) async {
    try {
      print('DEBUG: AuthService.signIn attempting for: "$email"');
      final response = await _withNetworkRetry(
        () => supabase.auth.signInWithPassword(
          email: email.trim(),
          password: password,
        ),
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

      if (profile.isExpired) {
        await signOut();
        throw Exception('account_expired');
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

  /// Sign in with either a username or an email address.
  /// Resolves the identifier to the account email via the `email_for_login`
  /// RPC, then signs in with the password.
  Future<ProfileModel?> signInWithIdentifier(
      String identifier, String password) async {
    final id = identifier.trim();
    String email = id;
    if (!id.contains('@')) {
      final resolved = await _withNetworkRetry(
        () => supabase.rpc('email_for_login', params: {'identifier': id}),
      );
      if (resolved == null || (resolved is String && resolved.isEmpty)) {
        throw Exception('invalid_credentials');
      }
      email = resolved as String;
    }
    return signIn(email, password);
  }

  /// Change the currently signed-in user's password.
  Future<void> changePassword(String newPassword) async {
    await supabase.auth.updateUser(UserAttributes(password: newPassword));
    final user = supabase.auth.currentUser;
    if (user != null) {
      await AuditLogService().recordLog(
        userId: user.id,
        action: 'Changed password',
        entityType: 'auth',
        entityId: user.id,
      );
    }
  }

  /// Change the currently signed-in user's login email. Supabase emails a
  /// confirmation link to the new address; the change only takes effect once
  /// that link is followed. The `profiles` row carries no email, so nothing
  /// there needs updating.
  Future<void> changeEmail(String newEmail) async {
    await supabase.auth.updateUser(UserAttributes(email: newEmail.trim()));
    final user = supabase.auth.currentUser;
    if (user != null) {
      await AuditLogService().recordLog(
        userId: user.id,
        action: 'Requested email change',
        entityType: 'auth',
        entityId: user.id,
        details: {'new_email': newEmail.trim()},
      );
    }
  }

  /// Step 1 of OTP-gated login (Disposal Directorate, every login):
  /// verify the password, then email a one-time code. Returns the resolved
  /// account email to use in [finishOtpLogin].
  Future<String> startOtpLogin(String identifier, String password) async {
    final id = identifier.trim();
    String email = id;
    if (!id.contains('@')) {
      final resolved = await _withNetworkRetry(
          () => supabase.rpc('email_for_login', params: {'identifier': id}));
      if (resolved == null || (resolved is String && resolved.isEmpty)) {
        throw Exception('invalid_credentials');
      }
      email = resolved as String;
    }
    // Verify the password (throws on bad credentials), then discard that
    // session so the user cannot proceed without the emailed code.
    await _withNetworkRetry(() =>
        supabase.auth.signInWithPassword(email: email, password: password));
    await supabase.auth.signOut();
    await _withNetworkRetry(() =>
        supabase.auth.signInWithOtp(email: email, shouldCreateUser: false));
    return email;
  }

  /// Step 2 of OTP-gated login: verify the emailed code and finish signing in.
  Future<ProfileModel?> finishOtpLogin(String email, String otp) async {
    AuthResponse response;
    try {
      response = await supabase.auth
          .verifyOTP(email: email, token: otp, type: OtpType.email);
    } on AuthException {
      response = await supabase.auth
          .verifyOTP(email: email, token: otp, type: OtpType.magiclink);
    }
    final user = response.user ?? supabase.auth.currentUser;
    if (user == null) throw Exception('otp_failed');

    final profileData =
        await supabase.from('profiles').select().eq('id', user.id).single();
    final profile = ProfileModel.fromJson(profileData);

    if (!profile.isActive) {
      await signOut();
      throw Exception('account_deactivated');
    }
    if (profile.isExpired) {
      await signOut();
      throw Exception('account_expired');
    }
    AppSession.setYard(profile.yard);
    try {
      await supabase.from('profiles').update({
        'is_online': true,
        'last_seen_at': DateTime.now().toIso8601String(),
      }).eq('id', profile.id);
    } catch (_) {}
    await AuditLogService().recordLog(
      userId: profile.id,
      action: 'Signed In (OTP)',
      entityType: 'auth',
      entityId: profile.id,
    );
    return profile;
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
      {String? status, String? search, DateTime? since, String? yard}) async {
    var query = supabase.from('packages').select(
        '*, package_items(*), warehouse_entries(*, warehouses(*), returned_profile:profiles!returned_by(full_name, badge_number)), profiles(*)');
    if (status != null && status != 'all' && status != 'returned')
      query = query.eq('status', status);
    // Explicit yard filter (used by the cross-yard Disposal Directorate views).
    if (yard != null) query = query.eq('yard', yard);
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

    // Packages registered or updated today, with their items' statuses.
    final allRes = await supabase
        .from('packages')
        .select('id, status, package_items(status)')
        .or('created_at.gte.${startOfDay.toIso8601String()},updated_at.gte.${startOfDay.toIso8601String()}');

    // Count today's disposition outcomes across all package items (the four the
    // Package Registration form can assign). Status strings are inconsistent
    // (capitalised, lowercase, the `Forfiet` typo, `confiscated` ≡ forfeit),
    // so normalise before matching.
    int forfeit = 0, abandon = 0, destroy = 0, release = 0;

    void tally(String? raw) {
      final s = (raw ?? '').trim().toLowerCase();
      if (s == 'forfeit' || s == 'forfeited' || s == 'forfiet' ||
          s == 'confiscated') {
        forfeit++;
      } else if (s == 'abandoned' || s == 'abandon') {
        abandon++;
      } else if (s == 'destroy' || s == 'destroyed') {
        destroy++;
      } else if (s == 'release' || s == 'released' || s == 'cleared' ||
          s == 'returned') {
        release++;
      }
    }

    for (final p in (allRes as List)) {
      final items = p['package_items'] as List? ?? [];
      if (items.isEmpty) {
        tally(p['status'] as String?); // package-level fallback
      } else {
        for (final i in items) {
          tally(i['status'] as String?);
        }
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
      'forfeit': forfeit,
      'abandon': abandon,
      'destroy': destroy,
      'release': release,
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

  /// Whether a Disposal Directorate position (DC/SDDC) is still free to claim.
  /// Returns false if an account already exists for that position.
  Future<bool> isDisposalPositionAvailable(String code) async {
    final res = await supabase
        .rpc('disposal_position_available', params: {'code': code});
    return res == true;
  }

  /// Whether an Appeal Directorate position (AD/ADD) is still free to claim.
  Future<bool> isAppealPositionAvailable(String code) async {
    final res =
        await supabase.rpc('appeal_position_available', params: {'code': code});
    return res == true;
  }

  Future<void> requestSignupOtp({
    required String email,
    required String fullName,
    required String badgeNumber,
    required String role,
    String? username,
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
        if (username != null) 'username': username,
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
    String? username,
    String? mobileNumber,
    String? jobRole,
    String? department,
    String? yard,
    String? profileImageUrl,
  }) async {
    // `signInWithOtp` issues an email OTP code. Verify it as `email`; fall back
    // to `signup`/`magiclink` so it works regardless of how the project's email
    // template/OTP is configured.
    AuthResponse response;
    try {
      response = await AuthService._withNetworkRetry(() => supabase.auth
          .verifyOTP(email: email, token: otp, type: OtpType.email));
    } on AuthException {
      try {
        response = await AuthService._withNetworkRetry(() => supabase.auth
            .verifyOTP(email: email, token: otp, type: OtpType.signup));
      } on AuthException {
        response = await AuthService._withNetworkRetry(() => supabase.auth
            .verifyOTP(email: email, token: otp, type: OtpType.magiclink));
      }
    }

    final user = response.user ?? supabase.auth.currentUser;
    if (user == null) {
      throw Exception('OTP verification failed. Please try again.');
    }

    final metadata = <String, dynamic>{
      'full_name': fullName,
      'role': role,
      'badge_number': badgeNumber,
      if (username != null) 'username': username,
      if (mobileNumber != null) 'mobile_number': mobileNumber,
      if (jobRole != null) 'job_role': jobRole,
      if (department != null) 'department': department,
      if (yard != null) 'yard': yard,
      if (profileImageUrl != null) 'profile_image_url': profileImageUrl,
    };
    try {
      await supabase.auth
          .updateUser(UserAttributes(password: password, data: metadata));
    } on AuthException catch (e) {
      // The account already existed with this exact password (re-verifying a
      // previously half-created account). Keep the password and just refresh
      // the metadata so the rest of setup (profile/username) still completes.
      final m = e.message.toLowerCase();
      if (e.code == 'same_password' || m.contains('different from the old')) {
        await supabase.auth.updateUser(UserAttributes(data: metadata));
      } else {
        rethrow;
      }
    }

    try {
      await supabase.from('profiles').upsert({
        'id': user.id,
        'full_name': fullName,
        'badge_number': badgeNumber,
        'role': role,
        'is_active': true,
        if (username != null) 'username': username,
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
      String? username,
      String? badgeNumber,
      String? role,
      String? mobileNumber,
      String? jobRole,
      String? department,
      String? yard,
      String? profileImageUrl}) async {
    final updates = <String, dynamic>{};
    if (fullName != null) updates['full_name'] = fullName;
    if (username != null) updates['username'] = username.isEmpty ? null : username;
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

  // ── Officer creation via Edge Function (service_role) ─────────
  // The `admin-officers` Edge Function creates the auth user, generates a
  // random username/password and emails the credentials, so the admin keeps
  // their own session. See supabase/functions/admin-officers/index.ts.

  Future<Map<String, dynamic>> _invokeAdminOfficers(
      Map<String, dynamic> body) async {
    try {
      final res =
          await supabase.functions.invoke('admin-officers', body: body);
      final data = res.data;
      if (data is Map && data['error'] != null) {
        throw Exception(data['error'].toString());
      }
      return data is Map
          ? data.cast<String, dynamic>()
          : <String, dynamic>{};
    } on FunctionException catch (e) {
      final details = e.details;
      if (details is Map && details['error'] != null) {
        throw Exception(details['error'].toString());
      }
      throw Exception(details?.toString() ?? 'Request failed. Please try again.');
    }
  }

  /// Step 1: email an OTP to the prospective officer for verification.
  Future<void> requestOfficerOtp({
    required String email,
    required String fullName,
    String? mobileNumber,
    String? badgeNumber,
  }) async {
    await _invokeAdminOfficers({
      'action': 'request-otp',
      'email': email.trim(),
      'fullName': fullName.trim(),
      'mobileNumber': mobileNumber?.trim(),
      'badgeNumber': badgeNumber?.trim(),
    });
  }

  /// Step 2: verify the OTP, create the officer account and email credentials.
  /// Returns the function payload, e.g. { ok, emailed, username, password? }.
  Future<Map<String, dynamic>> verifyAndCreateOfficer({
    required String email,
    required String otp,
  }) async {
    final result = await _invokeAdminOfficers({
      'action': 'verify-create',
      'email': email.trim(),
      'otp': otp.trim(),
    });
    final admin = supabase.auth.currentUser;
    if (admin != null) {
      await AuditLogService().recordLog(
        userId: admin.id,
        action: 'Created officer account (${result['username'] ?? email})',
        entityType: 'profile',
        entityId: 'new',
      );
    }
    return result;
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

    // 1b. Get IDs of packages already in a disposal request
    final reqData = await supabase.from('disposal_request_items').select('forfeited_package_id');
    final requestedIds = (reqData as List)
        .map((e) => e['forfeited_package_id'].toString())
        .toSet();

    // 2. Fetch forfeited packages (genuine forfeits only — synthetic
    //    source='abandoned' rows belong to the Abandoned page, not here).
    final data = await supabase
        .from('forfeited_packages')
        .select(
            '*, packages(*, package_items(*), warehouse_entries(*, warehouses(*), returned_profile:profiles!returned_by(full_name, badge_number)))')
        .eq('source', 'forfeit')
        .order('appeal_deadline', ascending: true);

    // 3. Filter out tendered and map to models
    return (data as List)
        .where((e) => !tenderedIds.contains(e['id']) && !requestedIds.contains(e['id']))
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

    // 1b. Get IDs of packages already in a disposal request
    final reqData = await supabase.from('disposal_request_items').select('forfeited_package_id');
    final requestedIds = (reqData as List)
        .map((e) => e['forfeited_package_id'].toString())
        .toSet();

    // 2. Fetch expired packages (genuine forfeits only)
    final data = await supabase
        .from('forfeited_packages')
        .select(
            '*, packages(*, package_items(*), warehouse_entries(*, warehouses(*), returned_profile:profiles!returned_by(full_name, badge_number)))')
        .eq('source', 'forfeit')
        .lt('appeal_deadline', DateTime.now().toIso8601String())
        .order('appeal_deadline', ascending: true);

    // 3. Filter out tendered and map to models
    return (data as List)
        .where((e) => !tenderedIds.contains(e['id']) && !requestedIds.contains(e['id']))
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

  /// Forfeited packages whose 30-day appeal window has passed and that are
  /// not yet part of a disposal request — i.e. items a yard can request the
  /// Central Disposal Directorate to dispose of. RLS keeps this to the
  /// caller's own yard.
  Future<List<ForfeitedPackageModel>> getRequestableExpiredPackages() async {
    // ── 1. Genuine forfeits whose appeal window has passed ───────────────────
    // Already-requested forfeited package ids (this yard, via RLS) — also used
    // below to know which abandoned packages already have a synthetic FP row.
    final requested = await AuthService._withNetworkRetry(() =>
        supabase.from('disposal_request_items').select('forfeited_package_id'));
    final requestedIds = (requested as List)
        .map((e) => e['forfeited_package_id'].toString())
        .toSet();

    final fpData = await AuthService._withNetworkRetry(() => supabase
        .from('forfeited_packages')
        .select(
            '*, packages(*, package_items(*), warehouse_entries(*, warehouses(*), returned_profile:profiles!returned_by(full_name, badge_number)))')
        .eq('source', 'forfeit')
        .lt('appeal_deadline', DateTime.now().toIso8601String())
        .order('appeal_deadline', ascending: true));

    final result = (fpData as List)
        .where((e) => !requestedIds.contains(e['id']))
        .map((e) => ForfeitedPackageModel.fromJson(e))
        .toList();

    // ── 2. Abandoned packages (no appeal — requestable immediately) ──────────
    // Abandoned packages live in `packages`/`package_items`; they have no
    // forfeited_packages row until requested. Surface them here as synthetic
    // ForfeitedPackageModels (id == package_id, source='abandoned') so the same
    // request dialog/pipeline can pick them up. A package that already has a
    // source='abandoned' FP row is dropped (it's been requested already).
    final pkgData = await AuthService._withNetworkRetry(() => supabase
        .from('packages')
        .select(
            '*, package_items(*), warehouse_entries(*, warehouses(*), returned_profile:profiles!returned_by(full_name, badge_number))'));

    // package_ids that already have an abandoned FP row (any request state).
    final existingAbandonedFp = await AuthService._withNetworkRetry(() => supabase
        .from('forfeited_packages')
        .select('package_id')
        .eq('source', 'abandoned'));
    final abandonedFpPkgIds = (existingAbandonedFp as List)
        .map((e) => e['package_id'].toString())
        .toSet();

    for (final raw in (pkgData as List)) {
      final pkg = PackageModel.fromJson(raw as Map<String, dynamic>);
      if (abandonedFpPkgIds.contains(pkg.id)) continue; // already requested
      if (!_packageHasAbandonedItem(pkg)) continue;
      result.add(ForfeitedPackageModel(
        id: pkg.id, // synthetic — uses package id until the FP row is created
        packageId: pkg.id,
        srNumber: pkg.srNumber,
        consigneeName: pkg.consigneeName,
        forfeitedAt: pkg.createdAt,
        // No appeal for abandoned goods → already-passed deadline.
        appealDeadline:
            DateTime.now().subtract(const Duration(days: 1)),
        reason: _abandonReasonFor(pkg),
        yard: AppSession.currentYard,
        source: 'abandoned',
        packageDetails: pkg,
      ));
    }

    return result;
  }

  /// True if a package has any abandoned item — either a form-level abandoned
  /// item (status 'abandoned') or an `[ABANDONED]` disposition event. Mirrors
  /// the detection in abandoned_packages_screen.dart, minus the final-
  /// disposition exclusion (a finalised package can't be requested anyway).
  bool _packageHasAbandonedItem(PackageModel p) {
    bool isAbandonedEntry(WarehouseEntryModel e) =>
        e.isReturned &&
        (e.returnNotes ?? '').trim().toUpperCase().startsWith('[ABANDONED]');
    bool hasFinal(String itemId) => p.warehouseEntries.any((e) =>
        e.packageItemId == itemId &&
        (e.returnNotes ?? '').trim().toUpperCase().startsWith('[FINAL:'));

    for (final item in p.items) {
      if (hasFinal(item.id)) continue;
      final entries =
          p.warehouseEntries.where((e) => e.packageItemId == item.id);
      if (entries.any(isAbandonedEntry)) return true;
      if ((item.status ?? '').trim().toLowerCase() == 'abandoned' &&
          !entries.any(isAbandonedEntry)) {
        return true;
      }
    }
    return false;
  }

  String _abandonReasonFor(PackageModel p) {
    for (final item in p.items) {
      final entries =
          p.warehouseEntries.where((e) => e.packageItemId == item.id).toList();
      final tagged = entries.where((e) =>
          (e.returnNotes ?? '').trim().toUpperCase().startsWith('[ABANDONED]'));
      final ctx = tagged.isNotEmpty
          ? tagged.first
          : (entries.isNotEmpty ? entries.first : null);
      if (ctx != null && ctx.holdReason.isNotEmpty) return ctx.holdReason;
      if (item.reasons?.isNotEmpty == true) return item.reasons!;
    }
    return 'Abandoned';
  }

  /// Submit a disposal request for the current yard. [dispositions] maps a
  /// forfeited_package_id to either 'destruction' or 'sale'.
  Future<void> createDisposalRequest({
    required DateTime requestDate,
    required Map<String, String> dispositions,
  }) async {
    if (dispositions.isEmpty) {
      throw Exception('Select at least one package');
    }
    final user = supabase.auth.currentUser;

    final header = await AuthService._withNetworkRetry(() => supabase
        .from('disposal_requests')
        .insert({
          'yard': AppSession.currentYard,
          'request_date': requestDate.toIso8601String().substring(0, 10),
          'created_by': user?.id,
        })
        .select('id')
        .single());

    final requestId = header['id'] as String;

    // Selected keys are forfeited_packages ids for genuine forfeits, but
    // package ids for abandoned packages (their FP row doesn't exist yet). Find
    // which selected keys are real forfeited_packages rows; the rest are
    // abandoned packages needing a synthetic FP row created here.
    final selectedKeys = dispositions.keys.toList();
    final existingFp = await AuthService._withNetworkRetry(() => supabase
        .from('forfeited_packages')
        .select('id')
        .inFilter('id', selectedKeys));
    final realFpIds =
        (existingFp as List).map((e) => e['id'].toString()).toSet();

    // key (selection id) → forfeited_packages id to store on the request item.
    final forfeitedIdFor = <String, String>{};
    for (final key in selectedKeys) {
      if (realFpIds.contains(key)) {
        forfeitedIdFor[key] = key; // genuine forfeit
        continue;
      }
      // Abandoned package → create (or reuse) a source='abandoned' FP row.
      final pkg = await AuthService._withNetworkRetry(() => supabase
          .from('packages')
          .select('id, sr_number, consignee_name')
          .eq('id', key)
          .single());
      final newFp = await AuthService._withNetworkRetry(() => supabase
          .from('forfeited_packages')
          .insert({
            'package_id': key,
            'sr_number': pkg['sr_number'],
            'consignee_name': pkg['consignee_name'] ?? '',
            'forfeited_at': DateTime.now().toIso8601String(),
            'appeal_deadline': DateTime.now()
                .subtract(const Duration(days: 1))
                .toIso8601String(),
            'reason': 'Abandoned',
            'yard': AppSession.currentYard,
            'source': 'abandoned',
          })
          .select('id')
          .single());
      forfeitedIdFor[key] = newFp['id'] as String;
    }

    final items = dispositions.entries
        .map((e) => {
              'request_id': requestId,
              'forfeited_package_id': forfeitedIdFor[e.key],
              'disposition': e.value,
            })
        .toList();
    await AuthService._withNetworkRetry(
        () => supabase.from('disposal_request_items').insert(items));

    if (user != null) {
      await AuditLogService().recordLog(
        userId: user.id,
        action: 'Submitted disposal request',
        entityType: 'disposal_request',
        entityId: requestId,
        details: {
          'yard': AppSession.currentYard,
          'package_count': dispositions.length,
        },
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
    DateTime? saleDate,
    String? saleTime,
  }) async {
    // Create tender record
    final data = await supabase
        .from('tenders')
        .insert({
          'tender_number': tenderNumber,
          'yard': AppSession.currentYard,
          'tender_date': tenderDate.toIso8601String(),
          'sale_date': saleDate?.toIso8601String().substring(0, 10),
          'sale_time': saleTime,
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

  /// Forfeited packages that have been tendered ≥1 time, whose latest tender's
  /// sale window has passed, and that were NOT sold — i.e. eligible to be
  /// re-tendered. Each carries its full tender history (newest first).
  Future<List<ReTenderInfo>> getReTenderablePackages() async {
    final tendersData = await supabase
        .from('tenders')
        .select('*, profiles(full_name)')
        .order('tender_date', ascending: false);
    final tenders =
        (tendersData as List).map((e) => TenderModel.fromJson(e)).toList();

    final disp = await supabase
        .from('tender_disposals')
        .select('forfeited_package_id, disposal_type');
    final soldIds = <String>{};
    for (final d in (disp as List)) {
      if ((d['disposal_type'] as String?) == 'sold') {
        soldIds.add(d['forfeited_package_id'].toString());
      }
    }

    // forfeited id → tenders containing it (already newest-first from the query)
    final byPkg = <String, List<TenderModel>>{};
    for (final t in tenders) {
      for (final id in t.forfeitedPackageIds) {
        byPkg.putIfAbsent(id, () => []).add(t);
      }
    }

    final eligible = <String, List<TenderModel>>{};
    byPkg.forEach((id, ts) {
      if (soldIds.contains(id)) return;
      // ts[0] is the latest tender (query ordered by tender_date desc).
      if (ts.first.saleWindowPassed) eligible[id] = ts;
    });
    if (eligible.isEmpty) return [];

    final fp = await supabase
        .from('forfeited_packages')
        .select(
            '*, packages(*, package_items(*), warehouse_entries(*, warehouses(*)))')
        .inFilter('id', eligible.keys.toList());

    final result = <ReTenderInfo>[];
    for (final e in (fp as List)) {
      final f = ForfeitedPackageModel.fromJson(e as Map<String, dynamic>);
      result.add(ReTenderInfo(forfeited: f, tenders: eligible[f.id] ?? const []));
    }
    // Stable order: most-tendered first, then by SR number.
    result.sort((a, b) {
      final c = b.tenderCount.compareTo(a.tenderCount);
      return c != 0 ? c : a.forfeited.srNumber.compareTo(b.forfeited.srNumber);
    });
    return result;
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

    // A "Sold" tender outcome sends the package to the Sold Packages page —
    // write a [FINAL:SOLD] warehouse entry in the package's own yard.
    if (disposalType == 'sold') {
      await AuthService._withNetworkRetry(() => supabase.rpc(
            'disposal_mark_forfeited_sold',
            params: {
              'p_forfeited_id': forfeitedPackageId,
              'p_receipt': (receiptNumber == null || receiptNumber.trim().isEmpty)
                  ? null
                  : receiptNumber.trim(),
            },
          ));
    }

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

// ── Disposal Directorate Service ───────────────────────────────
// Central Disposal Directorate users can read SOLD packages across ALL yards
// (cross-yard RLS) and manage Tender Sale records.

class DisposalService {
  /// Sold packages for a specific yard. The caller (disposal role) has
  /// cross-yard read access via RLS; the UI filters the [FINAL:SOLD] entries.
  Future<List<PackageModel>> getSoldPackages({required String yard}) async {
    return PackageService().getAllPackages(yard: yard);
  }

  /// Forfeited packages for a specific yard. Disposal users have cross-yard
  /// read access via the `disposal_read_all` RLS policy on forfeited_packages.
  Future<List<ForfeitedPackageModel>> getForfeitedPackages(
      {required String yard}) async {
    // 1. Get IDs of packages already in a tender
    final tendersData = await supabase.from('tenders').select('forfeited_package_ids');
    final tenderedIds = (tendersData as List)
        .expand((t) => (t['forfeited_package_ids'] as List))
        .map((e) => e.toString())
        .toSet();

    // 1b. Get IDs of packages already in a disposal request
    final reqData = await supabase.from('disposal_request_items').select('forfeited_package_id');
    final requestedIds = (reqData as List)
        .map((e) => e['forfeited_package_id'].toString())
        .toSet();

    // Pull the full warehouse context too, so the Central Disposal "Details"
    // popup shows the same Warehouse Summary (warehouse / zone / date range) as
    // the Sold Packages popup — not just item rows.
    final data = await supabase
        .from('forfeited_packages')
        .select(
            '*, packages(*, package_items(*), warehouse_entries(*, warehouses(*), returned_profile:profiles!returned_by(full_name, badge_number)))')
        .eq('yard', yard)
        .order('appeal_deadline', ascending: true);

    return (data as List)
        .where((e) => !tenderedIds.contains(e['id']) && !requestedIds.contains(e['id']))
        .map((e) => ForfeitedPackageModel.fromJson(e))
        .toList();
  }

  Future<List<TenderSaleModel>> getTenderSales() async {
    final data = await AuthService._withNetworkRetry(() => supabase
        .from('tender_sales')
        .select(
            '*, profiles!created_by(full_name), tender_sale_items(*, forfeited_packages(*, packages(*, package_items(*), warehouse_entries(*, warehouses(*)))))')
        .order('created_at', ascending: false));
    return (data as List).map((e) => TenderSaleModel.fromJson(e)).toList();
  }

  Future<List<ReTenderSaleInfo>> getUnsoldTenderSales() async {
    final sales = await getTenderSales();
    // forfeited id → tender sales containing it
    final byPkg = <String, List<TenderSaleModel>>{};
    
    // Find all packages that were sold across any tender sale
    final soldIds = <String>{};
    for (final sale in sales) {
      for (final item in sale.items) {
        if (item.sold) soldIds.add(item.forfeitedPackageId);
        byPkg.putIfAbsent(item.forfeitedPackageId, () => []).add(sale);
      }
    }

    final eligible = <String, List<TenderSaleModel>>{};
    byPkg.forEach((id, ts) {
      if (soldIds.contains(id)) return;
      
      // Let's assume if it is in a sale and not sold, it's eligible if sale date has passed.
      // If sale_date is null, we can consider it not passed yet or just include it. Let's include if sale_date <= today.
      bool passed = true;
      if (ts.first.saleDate != null) {
        final saleDateEnd = ts.first.saleDate!.add(const Duration(days: 1));
        if (DateTime.now().isBefore(saleDateEnd)) passed = false;
      }
      if (passed) eligible[id] = ts;
    });

    if (eligible.isEmpty) return [];

    final fp = await AuthService._withNetworkRetry(() => supabase
        .from('forfeited_packages')
        .select(
            '*, packages(*, package_items(*), warehouse_entries(*, warehouses(*)))')
        .inFilter('id', eligible.keys.toList()));

    final result = <ReTenderSaleInfo>[];
    for (final e in (fp as List)) {
      final f = ForfeitedPackageModel.fromJson(e as Map<String, dynamic>);
      result.add(ReTenderSaleInfo(forfeited: f, sales: eligible[f.id] ?? const []));
    }
    // Stable order: most-tendered first, then by SR number.
    result.sort((a, b) {
      final c = b.tenderCount.compareTo(a.tenderCount);
      return c != 0 ? c : a.forfeited.srNumber.compareTo(b.forfeited.srNumber);
    });
    return result;
  }

  /// "Sale"-tagged disposal-request items that are not yet in a tender sale —
  /// the pool the Tender Sale form can pick from. Cross-yard via RLS; each
  /// carries the forfeited package (incl. yard, items, warehouse location).
  Future<List<DisposalRequestItemModel>> getSaleRequestItems() async {
    final inSale = await AuthService._withNetworkRetry(
        () => supabase.from('tender_sale_items').select('forfeited_package_id'));
    final usedIds = (inSale as List)
        .map((e) => e['forfeited_package_id'].toString())
        .toSet();

    final data = await AuthService._withNetworkRetry(() => supabase
        .from('disposal_request_items')
        .select(
            '*, forfeited_packages(*, packages(*, package_items(*), warehouse_entries(*, warehouses(*))))')
        .eq('disposition', 'sale'));

    final items = (data as List)
        .map((e) => DisposalRequestItemModel.fromJson(e))
        .where((i) => !usedIds.contains(i.forfeitedPackageId))
        .toList();

    // De-duplicate by forfeited package (a package could be requested twice).
    final seen = <String>{};
    return items.where((i) => seen.add(i.forfeitedPackageId)).toList();
  }

  /// "Sale"-tagged disposal-request items NOT yet placed in a tender — the pool
  /// the Central Disposal "Place Tender" form picks from (cross-yard via RLS).
  Future<List<DisposalRequestItemModel>> getSaleRequestItemsNotTendered() async {
    final tendersData = await AuthService._withNetworkRetry(
        () => supabase.from('tenders').select('forfeited_package_ids'));
    final tenderedIds = (tendersData as List)
        .expand((t) => (t['forfeited_package_ids'] as List? ?? const []))
        .map((e) => e.toString())
        .toSet();

    final data = await AuthService._withNetworkRetry(() => supabase
        .from('disposal_request_items')
        .select(
            '*, forfeited_packages(*, packages(*, package_items(*), warehouse_entries(*, warehouses(*))))')
        .eq('disposition', 'sale'));

    final items = (data as List)
        .map((e) => DisposalRequestItemModel.fromJson(e))
        .where((i) => !tenderedIds.contains(i.forfeitedPackageId))
        .toList();
    final seen = <String>{};
    return items.where((i) => seen.add(i.forfeitedPackageId)).toList();
  }

  /// Mark a forfeited package SOLD (used when a tender outcome is "Sold"):
  /// writes a [FINAL:SOLD] warehouse entry in the package's own yard so it
  /// surfaces in that yard's Warehouses + the cross-yard Sold Packages tab.
  Future<void> markForfeitedSold({
    required String forfeitedPackageId,
    String? receipt,
  }) async {
    await AuthService._withNetworkRetry(() => supabase.rpc(
          'disposal_mark_forfeited_sold',
          params: {
            'p_forfeited_id': forfeitedPackageId,
            'p_receipt': (receipt == null || receipt.trim().isEmpty)
                ? null
                : receipt.trim(),
          },
        ));
  }

  /// All yards' disposal requests (cross-yard via RLS), newest first, each with
  /// its line items + the underlying forfeited package detail for display.
  Future<List<DisposalRequestModel>> getDisposalRequests() async {
    // Packages already placed in a tender / tender sale drop off the requests
    // view (they move on to Tender Sales).
    final tendersData = await AuthService._withNetworkRetry(
        () => supabase.from('tenders').select('forfeited_package_ids'));
    final tenderedIds = (tendersData as List)
        .expand((t) => (t['forfeited_package_ids'] as List? ?? const []))
        .map((e) => e.toString())
        .toSet();
    final saleItems = await AuthService._withNetworkRetry(() =>
        supabase.from('tender_sale_items').select('forfeited_package_id'));
    for (final e in (saleItems as List)) {
      tenderedIds.add(e['forfeited_package_id'].toString());
    }

    final data = await AuthService._withNetworkRetry(() => supabase
        .from('disposal_requests')
        .select(
            '*, profiles!created_by(full_name), disposal_request_items(*, forfeited_packages(*, packages(*, package_items(*))))')
        .order('created_at', ascending: false));

    final result = <DisposalRequestModel>[];
    for (final e in (data as List)) {
      final r = DisposalRequestModel.fromJson(e as Map<String, dynamic>);
      final items = r.items
          .where((i) => !tenderedIds.contains(i.forfeitedPackageId))
          .toList();
      if (items.isEmpty) continue; // whole request consumed by tenders
      result.add(DisposalRequestModel(
        id: r.id,
        yard: r.yard,
        requestDate: r.requestDate,
        status: r.status,
        createdAt: r.createdAt,
        createdByName: r.createdByName,
        items: items,
      ));
    }
    return result;
  }

  /// Get the next serial number for tender sales in a given year.
  Future<int> getNextTenderSaleSerial(int year) async {
    final data = await AuthService._withNetworkRetry(() => supabase
        .from('tender_sales')
        .select('serial')
        .eq('year', year));
    if (data == null) return 1;
    int maxSerial = 0;
    for (var row in data as List) {
      final s = int.tryParse(row['serial']?.toString() ?? '0') ?? 0;
      if (s > maxSerial) maxSerial = s;
    }
    return maxSerial + 1;
  }

  /// Create a tender sale. [packageYards] maps each selected forfeited-package
  /// id → its yard; one `tender_sale_items` row is created per entry.
  Future<void> createTenderSale({
    String? saleNumber,
    DateTime? saleDate,
    String? saleTime,
    String? serial,
    int? year,
    String? tenderType,
    String? yard,
    Map<String, String> packageYards = const {},
  }) async {
    final user = supabase.auth.currentUser;
    final sale = await AuthService._withNetworkRetry(() => supabase
        .from('tender_sales')
        .insert({
          'sale_number': saleNumber,
          'sale_date': saleDate == null
              ? null
              : saleDate.toIso8601String().substring(0, 10),
          'sale_time': saleTime,
          'serial': serial,
          'year': year,
          'tender_type': tenderType,
          'yard': yard,
          'created_by': user?.id,
        })
        .select('id')
        .single());

    final saleId = sale['id'] as String;

    if (packageYards.isNotEmpty) {
      final rows = packageYards.entries
          .map((e) => {
                'tender_sale_id': saleId,
                'forfeited_package_id': e.key,
                'yard': e.value,
                // Re-tendering an unsold package moves it to this new sale and
                // resets its sale state (upsert on the unique forfeited id).
                'sold': false,
                'sold_at': null,
              })
          .toList();
      await AuthService._withNetworkRetry(() => supabase
          .from('tender_sale_items')
          .upsert(rows, onConflict: 'forfeited_package_id'));
    }

    if (user != null) {
      await AuditLogService().recordLog(
        userId: user.id,
        action: 'Created tender sale ${saleNumber ?? ''}'.trim(),
        entityType: 'tender_sale',
        entityId: saleId,
        details: {'type': tenderType, 'package_count': packageYards.length},
      );
    }
  }

  /// Mark one tender-sale package SOLD. Server-side RPC writes a [FINAL:SOLD]
  /// warehouse entry in the package's own yard (so it shows in that yard's
  /// Warehouses + the cross-yard Sold Packages tab) and flips the item status.
  Future<void> markTenderSaleItemSold({
    required String tenderSaleItemId,
    String? receipt,
    double soldPrice = 0.0,
    List<dynamic> appliedTaxes = const [],
  }) async {
    await AuthService._withNetworkRetry(() => supabase.rpc(
          'disposal_mark_sale_item_sold',
          params: {
            'p_item_id': tenderSaleItemId,
            'p_receipt': (receipt == null || receipt.trim().isEmpty)
                ? null
                : receipt.trim(),
            'p_sold_price': soldPrice,
            'p_applied_taxes': appliedTaxes,
          },
        ));
    final user = supabase.auth.currentUser;
    if (user != null) {
      await AuditLogService().recordLog(
        userId: user.id,
        action: 'Marked tender-sale package sold',
        entityType: 'tender_sale_item',
        entityId: tenderSaleItemId,
        details: {'receipt': receipt, 'soldPrice': soldPrice},
      );
    }
  }

  Future<void> toggleDeliveryStatus(String tenderSaleItemId, bool isDelivered) async {
    await AuthService._withNetworkRetry(() => supabase.rpc(
          'disposal_toggle_delivery_status',
          params: {
            'p_item_id': tenderSaleItemId,
            'p_is_delivered': isDelivered,
          },
        ));
  }

  // --- Destructions ---

  Future<List<DestructionModel>> getDestructions() async {
    final data = await AuthService._withNetworkRetry(() => supabase
        .from('destructions')
        .select(
            '*, profiles!created_by(full_name), destruction_items(*, forfeited_packages(*, packages(*, package_items(*), warehouse_entries(*, warehouses(*)))))')
        .order('created_at', ascending: false));
    return (data as List).map((e) => DestructionModel.fromJson(e)).toList();
  }

  Future<List<ReDestructionInfo>> getUndestroyedDestructions() async {
    final dests = await getDestructions();
    final byPkg = <String, List<DestructionModel>>{};
    
    final destroyedIds = <String>{};
    for (final dest in dests) {
      for (final item in dest.items) {
        if (item.destroyed) destroyedIds.add(item.forfeitedPackageId);
        byPkg.putIfAbsent(item.forfeitedPackageId, () => []).add(dest);
      }
    }

    final eligible = <String, List<DestructionModel>>{};
    byPkg.forEach((id, ts) {
      if (destroyedIds.contains(id)) return;
      
      bool passed = true;
      if (ts.first.saleDate != null) {
        final saleDateEnd = ts.first.saleDate!.add(const Duration(days: 1));
        if (DateTime.now().isBefore(saleDateEnd)) passed = false;
      }
      if (passed) eligible[id] = ts;
    });

    if (eligible.isEmpty) return [];

    final fp = await AuthService._withNetworkRetry(() => supabase
        .from('forfeited_packages')
        .select(
            '*, packages(*, package_items(*), warehouse_entries(*, warehouses(*)))')
        .inFilter('id', eligible.keys.toList()));

    final result = <ReDestructionInfo>[];
    for (final e in (fp as List)) {
      final f = ForfeitedPackageModel.fromJson(e as Map<String, dynamic>);
      result.add(ReDestructionInfo(forfeited: f, destructions: eligible[f.id] ?? const []));
    }
    result.sort((a, b) {
      final c = b.timesAttempted.compareTo(a.timesAttempted);
      return c != 0 ? c : a.forfeited.srNumber.compareTo(b.forfeited.srNumber);
    });
    return result;
  }

  Future<List<DisposalRequestItemModel>> getDestructionRequestItemsNotDestroyed() async {
    final destsData = await AuthService._withNetworkRetry(
        () => supabase.from('destruction_items').select('forfeited_package_id'));
    final destsIds = (destsData as List)
        .map((e) => e['forfeited_package_id'].toString())
        .toSet();

    final data = await AuthService._withNetworkRetry(() => supabase
        .from('disposal_request_items')
        .select(
            '*, forfeited_packages(*, packages(*, package_items(*), warehouse_entries(*, warehouses(*))))')
        .eq('disposition', 'destruction'));

    final items = (data as List)
        .map((e) => DisposalRequestItemModel.fromJson(e))
        .where((i) => !destsIds.contains(i.forfeitedPackageId))
        .toList();
    final seen = <String>{};
    return items.where((i) => seen.add(i.forfeitedPackageId)).toList();
  }

  Future<int> getNextDestructionSerial(int year) async {
    final data = await AuthService._withNetworkRetry(() => supabase
        .from('destructions')
        .select('serial')
        .eq('year', year));
    if (data == null) return 1;
    int maxSerial = 0;
    for (var row in data as List) {
      final s = int.tryParse(row['serial']?.toString() ?? '0') ?? 0;
      if (s > maxSerial) maxSerial = s;
    }
    return maxSerial + 1;
  }

  Future<void> createDestruction({
    String? saleNumber,
    DateTime? saleDate,
    String? saleTime,
    String? serial,
    int? year,
    String? tenderType,
    String? yard,
    Map<String, String> packageYards = const {},
  }) async {
    final user = supabase.auth.currentUser;
    final dest = await AuthService._withNetworkRetry(() => supabase
        .from('destructions')
        .insert({
          'sale_number': saleNumber,
          'sale_date': saleDate == null
              ? null
              : saleDate.toIso8601String().substring(0, 10),
          'sale_time': saleTime,
          'serial': serial,
          'year': year,
          'tender_type': tenderType,
          'yard': yard,
          'created_by': user?.id,
        })
        .select('id')
        .single());

    final destId = dest['id'] as String;

    if (packageYards.isNotEmpty) {
      final rows = packageYards.entries
          .map((e) => {
                'destruction_id': destId,
                'forfeited_package_id': e.key,
                'yard': e.value,
                'destroyed': false,
                'destroyed_at': null,
              })
          .toList();
      await AuthService._withNetworkRetry(() => supabase
          .from('destruction_items')
          .upsert(rows, onConflict: 'forfeited_package_id'));
    }

    if (user != null) {
      await AuditLogService().recordLog(
        userId: user.id,
        action: 'Created destruction ${saleNumber ?? ''}'.trim(),
        entityType: 'destruction',
        entityId: destId,
        details: {'type': tenderType, 'package_count': packageYards.length},
      );
    }
  }

  Future<void> markDestructionItemDestroyed({
    required String destructionItemId,
    String? receipt,
  }) async {
    await AuthService._withNetworkRetry(() => supabase.rpc(
          'disposal_mark_destruction_item_destroyed',
          params: {
            'p_item_id': destructionItemId,
            'p_receipt': (receipt == null || receipt.trim().isEmpty)
                ? null
                : receipt.trim(),
          },
        ));
    final user = supabase.auth.currentUser;
    if (user != null) {
      await AuditLogService().recordLog(
        userId: user.id,
        action: 'Marked destruction package destroyed',
        entityType: 'destruction_item',
        entityId: destructionItemId,
        details: {'receipt': receipt},
      );
    }
  }

  // --- Taxes ---

  Future<List<DisposalTaxModel>> getTaxes() async {
    final data = await AuthService._withNetworkRetry(() =>
        supabase.from('disposal_taxes').select().order('created_at', ascending: true));
    return (data as List).map((e) => DisposalTaxModel.fromJson(e)).toList();
  }

  Future<void> createTax(String name, double percentage) async {
    await AuthService._withNetworkRetry(() => supabase
        .from('disposal_taxes')
        .insert({'name': name, 'percentage': percentage}));
  }

  Future<void> updateTax(String id, String name, double percentage, bool isActive) async {
    await AuthService._withNetworkRetry(() => supabase
        .from('disposal_taxes')
        .update({'name': name, 'percentage': percentage, 'is_active': isActive})
        .eq('id', id));
  }

  Future<TenderSaleItemModel?> getTenderSaleItemForPackage(String packageId) async {
    // A package can have more than one forfeited row historically, so DON'T use
    // maybeSingle here (it throws on >1 row). Gather all ids, then look up the
    // most recent tender-sale item across them.
    final fpkgs = await AuthService._withNetworkRetry(() => supabase
        .from('forfeited_packages')
        .select('id')
        .eq('package_id', packageId));
    final ids = (fpkgs as List).map((e) => e['id'] as String).toList();
    if (ids.isEmpty) return null;

    final data = await AuthService._withNetworkRetry(() => supabase
        .from('tender_sale_items')
        .select()
        .inFilter('forfeited_package_id', ids)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle());
    if (data == null) return null;
    return TenderSaleItemModel.fromJson(data);
  }

  Future<void> deleteTax(String id) async {
    await AuthService._withNetworkRetry(
        () => supabase.from('disposal_taxes').delete().eq('id', id));
  }
}

// ── Appeal Directorate Service ───────────────────────────────────
// Cross-yard read of forfeited packages (genuine forfeits only) so the Appeal
// Directorate can place / lift an appeal hold while the 30-day window is open.
class AppealService {
  /// Every genuine forfeited package across all yards (newest deadline first),
  /// with full package + warehouse detail. Unlike the disposal query this does
  /// NOT exclude tendered / requested packages — appeals can be raised at any
  /// point before the window passes. Packages already fully sold/destroyed
  /// (every item finalised) ARE dropped — there's nothing left to appeal.
  Future<List<ForfeitedPackageModel>> getForfeitedPackages() async {
    final data = await AuthService._withNetworkRetry(() => supabase
        .from('forfeited_packages')
        .select(
            '*, packages(*, package_items(*), warehouse_entries(*, warehouses(*), returned_profile:profiles!returned_by(full_name, badge_number)))')
        .eq('source', 'forfeit')
        .order('appeal_deadline', ascending: true));
    return (data as List)
        .map((e) => ForfeitedPackageModel.fromJson(e))
        .where((f) => !_isFullyFinalised(f.packageDetails))
        .toList();
  }

  /// True if every package item has moved on to a final disposition
  /// (sold / destroyed / re-exported / released) — via a `[FINAL:…]` warehouse
  /// entry or a terminal item status. Such packages no longer need appeals.
  bool _isFullyFinalised(PackageModel? p) {
    final items = p?.items ?? const [];
    if (p == null || items.isEmpty) return false;
    bool hasFinalEntry(String itemId) => p.warehouseEntries.any((e) =>
        e.packageItemId == itemId &&
        (e.returnNotes ?? '').trim().toUpperCase().startsWith('[FINAL:'));
    const terminal = {'sold', 'destroyed', 're-exported', 'released'};
    return items.every((it) =>
        hasFinalEntry(it.id) ||
        terminal.contains((it.status ?? '').trim().toLowerCase()));
  }

  /// Place (or lift) an appeal hold. Blocked server-side once the window passes.
  Future<void> setAppealHold(String forfeitedId, bool hold,
      {String? note}) async {
    await AuthService._withNetworkRetry(() => supabase.rpc('set_appeal_hold',
        params: {
          'p_forfeited_id': forfeitedId,
          'p_hold': hold,
          'p_note': note,
        }));
    final user = supabase.auth.currentUser;
    if (user != null) {
      await AuditLogService().recordLog(
        userId: user.id,
        action: hold ? 'Placed appeal hold' : 'Lifted appeal hold',
        entityType: 'forfeited_package',
        entityId: forfeitedId,
      );
    }
  }
}
