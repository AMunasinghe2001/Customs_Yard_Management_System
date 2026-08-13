import 'dart:async';
import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/supabase_client.dart';
import '../core/app_session.dart';
import '../core/yards.dart';
import '../models/models.dart';
import 'otp_service.dart';

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

    // 2. Check profile and role. Retry transient failures — right after a fresh
    // login the JWT can still be propagating, so the first profile query may
    // momentarily return nothing/error; retrying avoids a spurious sign-out that
    // bounced the user back to the portal on the first Sign In click.
    final profileData = await _withNetworkRetry(
      () => supabase.from('profiles').select().eq('id', user.id).maybeSingle(),
    );

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
          'last_seen_at': DateTime.now().toUtc().toIso8601String(),
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
    // Issue our own 6-digit code and e-mail it via Gmail (not Supabase).
    await GmailOtpService.instance.sendCode(email);
    return email;
  }

  /// Step 2 of OTP-gated login: verify the Gmail code, then create the session
  /// with the already-verified [password].
  Future<ProfileModel?> finishOtpLogin(
      String email, String otp, String password) async {
    // Verify the self-issued code (throws on bad/expired code).
    GmailOtpService.instance.verifyCode(email, otp);
    // Code is good — sign in with the password checked in startOtpLogin.
    final response = await _withNetworkRetry(() =>
        supabase.auth.signInWithPassword(email: email, password: password));
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
        'last_seen_at': DateTime.now().toUtc().toIso8601String(),
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

  /// DEV/TESTING ONLY (guarded by [kDevSkipOtp] at the call sites): verify the
  /// password and sign in directly, skipping the emailed OTP step. Mirrors the
  /// post-OTP checks of [finishOtpLogin] (active/expired gates, presence, audit)
  /// so the resulting session is identical — only the one-time code is skipped.
  Future<ProfileModel?> passwordOnlyLogin(
      String identifier, String password) async {
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
    final response = await _withNetworkRetry(() =>
        supabase.auth.signInWithPassword(email: email, password: password));
    final user = response.user ?? supabase.auth.currentUser;
    if (user == null) throw Exception('invalid_credentials');

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
        'last_seen_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', profile.id);
    } catch (_) {}
    await AuditLogService().recordLog(
      userId: profile.id,
      action: 'Signed In (password, OTP skipped — dev)',
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
        // Null last_seen_at as well: the online list is judged purely by a
        // fresh heartbeat, so leaving a recent last_seen would keep the user
        // "online" for up to ~90s after signing out. Nulling it = instant off.
        await supabase.from('profiles').update({
          'is_online': false,
          'last_seen_at': null,
        }).eq('id', user.id);
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
        'last_seen_at': DateTime.now().toUtc().toIso8601String(),
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
        'last_seen_at': null, // instant offline (see signOut note)
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

  /// Server-side paged fetch for the Package History page so it opens fast even
  /// with very large tables (only [limit] rows leave the DB per call). Filters
  /// are applied server-side. Returns the page rows + the total matching count
  /// (for the pager). [year] matches the SR-number suffix '/YYYY'.
  Future<({List<PackageModel> rows, int total})> getPackagesPaged({
    required int offset,
    required int limit,
    String? search,
    DateTime? dateStart,
    DateTime? dateEnd,
    String? year,
    String? yard,
  }) async {
    // Apply the same filters to any PostgrestFilterBuilder (rows or count).
    PostgrestFilterBuilder<T> applyFilters<T>(PostgrestFilterBuilder<T> q) {
      if (yard != null) q = q.eq('yard', yard);
      if (search != null && search.trim().isNotEmpty) {
        final s = search.trim();
        q = q.or(
            'sr_number.ilike.%$s%,consignee_name.ilike.%$s%,declarant_name.ilike.%$s%,cusdec_no.ilike.%$s%');
      }
      if (year != null && year.isNotEmpty) {
        q = q.ilike('sr_number', '%/$year');
      }
      if (dateStart != null) {
        final start =
            DateTime(dateStart.year, dateStart.month, dateStart.day);
        q = q.gte('created_at', start.toIso8601String());
      }
      if (dateEnd != null) {
        final end =
            DateTime(dateEnd.year, dateEnd.month, dateEnd.day, 23, 59, 59);
        q = q.lte('created_at', end.toIso8601String());
      }
      return q;
    }

    final rowsData = await AuthService._withNetworkRetry(() => applyFilters(
            supabase.from('packages').select(
                '*, package_items(*), warehouse_entries(*, warehouses(*), returned_profile:profiles!returned_by(full_name, badge_number)), profiles(*)'))
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1));

    // Count-only query (no rows transferred) for the pager total.
    final total = await AuthService._withNetworkRetry(() =>
        applyFilters(supabase.from('packages').count(CountOption.exact)));

    final rows =
        (rowsData as List).map((e) => PackageModel.fromJson(e)).toList();
    return (rows: rows, total: total);
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
          entryDate: created.entryDate,
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

        // Keep the warehouse held quantity in sync with the (possibly edited)
        // item quantity, so the Warehouse table's "No. of Packages" and the
        // "Currently Held" breakdown reflect the correction. Only safe when the
        // item hasn't been partially disposed: if any of its entries are already
        // returned (released/forfeited/…), we must not overwrite the held count
        // and disturb those recorded quantities, so we skip such items.
        for (final item in items) {
          if (item.id.isEmpty) continue;
          final entries = await supabase
              .from('warehouse_entries')
              .select('id, is_returned')
              .eq('package_item_id', item.id);
          final rows = entries as List;
          final held =
              rows.where((e) => e['is_returned'] != true).toList();
          final anyDisposed = rows.any((e) => e['is_returned'] == true);
          if (anyDisposed) continue; // partial disposal — leave counts alone
          if (held.length == 1) {
            await supabase.from('warehouse_entries').update(
                {'item_count': item.quantity}).eq('id', held.first['id']);
          }
        }
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

      // Re-anchor any EXISTING forfeited record to the (possibly edited) Entry
      // Date — independent of hasForfeit below, so simply editing the Entry Date
      // on an already-forfeited package updates its forfeited date + 30-day
      // appeal deadline in the Forfeited table.
      if (result.entryDate != null) {
        final anchor = result.entryDate!;
        await supabase.from('forfeited_packages').update({
          'forfeited_at': anchor.toIso8601String(),
          'appeal_deadline':
              anchor.add(const Duration(days: 30)).toIso8601String(),
        }).eq('package_id', result.id);
      }

      // Sync to Forfeited Packages if applicable.
      // A PARTIAL forfeit is recorded as a returned "[FORFEIT]/[CONFISCATED]"
      // warehouse entry while the item's own status stays 'detain' (part of it
      // is still held). So we must also treat a forfeit warehouse event as
      // "has forfeit" — otherwise editing such a package (e.g. its Entry Date)
      // would wrongly delete its forfeited_packages row below and drop it from
      // the Forfeited table.
      final hasForfeitEntry = result.warehouseEntries.any((e) {
        if (!e.isReturned) return false;
        final n = (e.returnNotes ?? '').trim().toUpperCase();
        return n.startsWith('[FORFEIT') || n.startsWith('[CONFISCATED');
      });
      final hasForfeit = _isForfeitStatus(pkg.status) ||
          items.any((i) => _isForfeitStatus(i.status)) ||
          hasForfeitEntry;
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
            entryDate: result.entryDate,
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
          .select('sr_number, consignee_name, reason, entry_date')
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
          entryDate: pkgData['entry_date'] != null
              ? DateTime.tryParse(pkgData['entry_date'] as String)
              : null,
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
      {bool? isReturned, String? yard}) async {
    var query = supabase.from('warehouse_entries').select(
        '*, warehouses(*), packages(*, package_items(*)), admitted_profile:profiles!admitted_by(full_name, badge_number), returned_profile:profiles!returned_by(full_name, badge_number)');
    if (isReturned != null) query = query.eq('is_returned', isReturned);
    // Executive-Office reports scope by yard; officers rely on RLS.
    if (yard != null) query = query.eq('yard', yard);
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
      {String? returnNotes,
      int? returnQty,
      List<int>? packageNumbers,
      DateTime? returnDate}) async {
    final user = supabase.auth.currentUser;
    // The release date (defaults to now) — stored as returned_at so the
    // warehouse charge and Released Packages date reflect the chosen date.
    final returnedAtIso =
        (returnDate ?? DateTime.now()).toIso8601String();
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
          'returned_at': returnedAtIso,
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
          'returned_at': returnedAtIso,
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
    // The date the disposition took place (chosen in the dialog, defaults to
    // today). Stored as returned_at; for Forfeit it also anchors the appeal
    // deadline. Falls back to now when not provided.
    DateTime? forfeitDate,
  }) async {
    final user = supabase.auth.currentUser;
    // returned_at reflects the officer-chosen disposition date (not the moment
    // the button was pressed), so back-dated actions record correctly.
    final returnedAtIso =
        (forfeitDate ?? DateTime.now()).toIso8601String();

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
        'returned_at': returnedAtIso,
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
        'returned_at': returnedAtIso,
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
            .select('sr_number, consignee_name, reason, entry_date')
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
            // The officer-chosen Forfeit Date wins; fall back to the SR Entry
            // Date. Both forfeited_at and the 30-day appeal deadline anchor here.
            entryDate: forfeitDate ??
                (pkgRow['entry_date'] != null
                    ? DateTime.tryParse(pkgRow['entry_date'] as String)
                    : null),
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
    // The date the disposition took place (chosen in the confirm dialog).
    // Stored as returned_at; defaults to now when not supplied.
    DateTime? dispositionDate,
  }) async {
    final user = supabase.auth.currentUser;
    final returnedAtIso =
        (dispositionDate ?? DateTime.now()).toIso8601String();

    // Copy package/warehouse context from the item's most recent entry.
    final refEntry = await supabase
        .from('warehouse_entries')
        .select(
            'package_id, warehouse_id, zone, hold_reason, admitted_by, admitted_at, daily_rate')
        .eq('package_item_id', packageItemId)
        .order('admitted_at', ascending: false)
        .limit(1)
        .maybeSingle();
    final tag = dispositionType.toUpperCase();
    final returnNotes =
        '[FINAL:$tag]${notes != null && notes.isNotEmpty ? ' — $notes' : ''}';

    if (refEntry != null) {
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
        'returned_at': returnedAtIso,
        'returned_by': user?.id,
        'return_notes': returnNotes,
      });
    }
    // If no warehouse entry exists (item was never admitted), skip the
    // warehouse_entries insert — just update the item status below.

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

  /// Per-warehouse capacity utilisation for the current admin's yard.
  /// Returns one map per warehouse that holds active (not-returned) stock for
  /// this yard:
  ///   { 'warehouseName', 'warehouseCode', 'zones' (sorted List<String>),
  ///     'used' (int), 'capacity' (int), 'percent' (double 0..100+) }
  /// Warehouses are global, but the used count is scoped to AppSession yard.
  Future<List<Map<String, dynamic>>> getYardWarehouseCapacity() async {
    final yard = AppSession.currentYard;

    final data = await supabase
        .from('warehouse_entries')
        .select('item_count, zone, warehouse_id, warehouses(name, code, capacity)')
        .eq('yard', yard)
        .eq('is_returned', false);

    // warehouse_id → aggregate
    final Map<String, Map<String, dynamic>> byWarehouse = {};

    for (final e in (data as List)) {
      final wh = e['warehouses'] as Map?;
      if (wh == null) continue;
      final whId = e['warehouse_id']?.toString() ?? '';
      final agg = byWarehouse.putIfAbsent(whId, () => {
            'warehouseName': wh['name']?.toString() ?? 'Unknown',
            'warehouseCode': wh['code']?.toString() ?? '—',
            'capacity': (wh['capacity'] as num?)?.toInt() ?? 500,
            'used': 0,
            'zones': <String>{},
          });
      agg['used'] = (agg['used'] as int) + ((e['item_count'] as num?)?.toInt() ?? 0);
      final z = e['zone']?.toString();
      if (z != null && z.trim().isNotEmpty && z.toUpperCase() != 'N/A') {
        (agg['zones'] as Set<String>).add(z.trim());
      }
    }

    final result = byWarehouse.values.map((v) {
      final used = v['used'] as int;
      final capacity = v['capacity'] as int;
      final zones = (v['zones'] as Set<String>).toList()..sort();
      final percent = capacity > 0 ? (used / capacity) * 100 : 0.0;
      return {
        'warehouseName': v['warehouseName'],
        'warehouseCode': v['warehouseCode'],
        'zones': zones,
        'used': used,
        'capacity': capacity,
        'percent': percent,
      };
    }).toList();

    result.sort((a, b) =>
        (a['warehouseCode'] as String).compareTo(b['warehouseCode'] as String));
    return result;
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

  Future<bool> isValuationPositionAvailable(String code) async {
    final res = await supabase
        .rpc('valuation_position_available', params: {'code': code});
    return res == true;
  }

  /// Whether an Executive Office position (DG / ADG) is still free to claim.
  Future<bool> isExecutivePositionAvailable(String code) async {
    final res = await supabase
        .rpc('executive_position_available', params: {'code': code});
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
    // E-mail a self-issued code via Gmail (not Supabase). The account itself is
    // created only after the code is verified, in [verifySignupOtp].
    await GmailOtpService.instance
        .sendCode(email.trim(), recipientName: fullName);
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
    // Verify our self-issued Gmail code (throws on bad/expired code).
    GmailOtpService.instance.verifyCode(email.trim(), otp);

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

    // Create the account now (the Gmail code was our e-mail verification).
    // Requires Supabase → Authentication → Providers → Email → "Confirm email"
    // to be OFF, so signUp yields a usable account without Supabase e-mailing
    // its own confirmation link.
    User? user;
    try {
      final res = await AuthService._withNetworkRetry(() => supabase.auth
          .signUp(email: email.trim(), password: password, data: metadata));
      user = res.user;
    } on AuthException catch (e) {
      final m = e.message.toLowerCase();
      final exists = e.code == 'user_already_exists' ||
          m.contains('already registered') ||
          m.contains('already been registered') ||
          m.contains('user already');
      if (exists) {
        // Half-created / re-verified account: sign in and refresh metadata.
        final res = await AuthService._withNetworkRetry(() => supabase.auth
            .signInWithPassword(email: email.trim(), password: password));
        user = res.user;
        try {
          await supabase.auth.updateUser(UserAttributes(data: metadata));
        } catch (_) {}
      } else {
        rethrow;
      }
    }
    if (user == null) {
      throw Exception('Sign-up failed. Please try again.');
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

  // ── Officer creation (client-side, Gmail OTP — no Supabase OTP / no Edge
  //    Function). The OTP is e-mailed via Gmail; on verify we create the auth
  //    account with signUp, then restore the admin's session so the admin stays
  //    logged in, and e-mail the generated credentials via Gmail.

  static String _randomOfficerPassword([int len = 12]) {
    const upper = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
    const lower = 'abcdefghijkmnpqrstuvwxyz';
    const digits = '23456789';
    const symbols = '@#%&*!?';
    const all = upper + lower + digits + symbols;
    final r = Random.secure();
    String pick(String s) => s[r.nextInt(s.length)];
    var pw = pick(upper) + pick(lower) + pick(digits) + pick(symbols);
    for (var i = pw.length; i < len; i++) {
      pw += pick(all);
    }
    final chars = pw.split('')..shuffle(r);
    return chars.join();
  }

  static String _slug(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  Future<String> _uniqueUsername(String fullName) async {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    final base = (_slug(parts.first) +
            (parts.length > 1 ? '.${_slug(parts[1])}' : ''))
        .replaceAll(RegExp(r'^\.+|\.+$'), '');
    final seed = base.isEmpty ? 'officer' : base;
    final r = Random.secure();
    for (var i = 0; i < 12; i++) {
      final candidate = i == 0
          ? '$seed${100 + r.nextInt(900)}'
          : '$seed${1000 + r.nextInt(9000)}';
      final clash = await supabase
          .from('profiles')
          .select('id')
          .ilike('username', candidate)
          .maybeSingle();
      if (clash == null) return candidate;
    }
    return 'officer${DateTime.now().millisecondsSinceEpoch}';
  }

  /// Step 1: e-mail an OTP (via Gmail) to the prospective officer.
  Future<void> requestOfficerOtp({
    required String email,
    required String fullName,
    String? mobileNumber,
    String? badgeNumber,
  }) async {
    await GmailOtpService.instance
        .sendCode(email.trim(), recipientName: fullName.trim());
  }

  /// Step 2: verify the Gmail OTP, create the officer account (keeping the
  /// admin signed in) and e-mail the generated credentials.
  /// Returns { ok, emailed, username, password }.
  Future<Map<String, dynamic>> verifyAndCreateOfficer({
    required String email,
    required String otp,
    required String fullName,
    String? mobileNumber,
    String? badgeNumber,
  }) async {
    GmailOtpService.instance.verifyCode(email.trim(), otp);

    // Remember the admin's session + yard so we can restore them afterwards
    // (signUp switches the active session to the new officer).
    final adminSession = supabase.auth.currentSession;
    final adminId = supabase.auth.currentUser?.id;
    final officerYard = AppSession.currentYard;

    final username = await _uniqueUsername(fullName);
    final password = _randomOfficerPassword();

    final metadata = <String, dynamic>{
      'full_name': fullName.trim(),
      'role': 'officer',
      'badge_number': badgeNumber?.trim(),
      'mobile_number': mobileNumber?.trim(),
      'yard': officerYard,
      'username': username,
    };

    // Create the officer account (Confirm email must be OFF in Supabase).
    final String officerId;
    try {
      final res = await AuthService._withNetworkRetry(() => supabase.auth
          .signUp(email: email.trim(), password: password, data: metadata));
      final u = res.user;
      if (u == null) throw Exception('Could not create the officer account.');
      officerId = u.id;
    } on AuthException catch (e) {
      final m = e.message.toLowerCase();
      if (e.code == 'user_already_exists' ||
          m.contains('already registered') ||
          m.contains('already been registered')) {
        // Restore the admin before surfacing the error.
        if (adminSession != null) {
          try {
            await supabase.auth.setSession(adminSession.refreshToken!);
          } catch (_) {}
        }
        throw Exception('This email is already registered.');
      }
      rethrow;
    }

    // Write the officer's profile while their session is active (self-insert).
    try {
      await supabase.from('profiles').upsert({
        'id': officerId,
        'full_name': fullName.trim(),
        'username': username,
        'badge_number': badgeNumber?.trim(),
        'mobile_number': mobileNumber?.trim(),
        'role': 'officer',
        'is_active': true,
        'yard': officerYard,
      });
    } catch (_) {}

    // Restore the admin's own session so they stay logged in.
    if (adminSession != null) {
      try {
        await supabase.auth.setSession(adminSession.refreshToken!);
      } catch (_) {}
    }

    // E-mail the credentials via Gmail. If it fails, hand them back so the
    // admin can relay them manually.
    bool emailed = true;
    try {
      await GmailOtpService.instance
          .sendCredentials(email.trim(), fullName.trim(), username, password);
    } catch (_) {
      emailed = false;
    }

    if (adminId != null) {
      await AuditLogService().recordLog(
        userId: adminId,
        action: 'Created officer account ($username)',
        entityType: 'profile',
        entityId: officerId,
      );
    }

    return {
      'ok': true,
      'emailed': emailed,
      'username': username,
      'password': password,
    };
  }
}

// ── Audit Log Service ──────────────────────────────────────────

class AuditLogService {
  static final Random _rand = Random();

  Future<List<AuditLogModel>> getAllLogs() async {
    // Admins only see activity from their OWN yard, and ONLY from the yard's own
    // staff — yard admins and officers. Directorate accounts (disposal / appeal
    // / valuation) are head-office and must NOT appear here even if they share a
    // yard code; we filter them out by joining the actor's role.
    // Retention: only the last 12 months are kept on screen — older rows are
    // pruned from the table by purge_old_audit_logs() (migration
    // 20260615_audit_log_retention.sql).
    final oneYearAgo =
        DateTime.now().subtract(const Duration(days: 365)).toIso8601String();
    final data = await supabase
        .from('audit_logs')
        .select('*, profiles!inner(full_name, role)')
        .eq('yard', AppSession.currentYard)
        .inFilter('profiles.role', ['admin', 'officer'])
        .gte('created_at', oneYearAgo)
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
      // Opportunistically prune logs older than a year. Sampled (~1 in 20
      // writes) so we don't run the delete on every single insert; fire-and-
      // forget so a failure never blocks the action being logged.
      if (_rand.nextInt(20) == 0) {
        unawaited(supabase.rpc('purge_old_audit_logs').then((_) {},
            onError: (_) {}));
      }
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

    // 1b. Items already in a disposal request — keyed "<packageId>:<itemId>".
    //     A request stores a forfeited_packages row that may be a synthetic
    //     per-item row, so we match on the originating (package_id, item_id)
    //     rather than the raw FP id, plus keep the raw ids for legacy matches.
    final reqData = await supabase
        .from('disposal_request_items')
        .select(
            'forfeited_package_id, forfeited_packages(package_id, item_id)');
    final requestedIds = <String>{};
    final requestedItemKeys = <String>{};
    for (final e in (reqData as List)) {
      requestedIds.add(e['forfeited_package_id'].toString());
      final fp = e['forfeited_packages'] as Map<String, dynamic>?;
      final pkgId = fp?['package_id']?.toString();
      final itemId = fp?['item_id']?.toString();
      if (pkgId != null && itemId != null) {
        requestedItemKeys.add('$pkgId:$itemId');
      }
    }

    // 1c. Get IDs of packages that have already been SOLD or DESTROYED — these
    //     belong on the Sold / Destroyed pages, not the Forfeited list. Unsold
    //     tender entries (sold=false) stay so they remain actionable here.
    final goneIds = await _soldOrDestroyedForfeitedIds();

    // 2. Fetch forfeited packages (genuine forfeits only — synthetic
    //    source='abandoned' rows belong to the Abandoned page, not here).
    final data = await supabase
        .from('forfeited_packages')
        .select(
            '*, packages(*, package_items(*), warehouse_entries(*, warehouses(*), returned_profile:profiles!returned_by(full_name, badge_number)))')
        .eq('source', 'forfeit')
        .order('appeal_deadline', ascending: true);

    // 3. Filter out tendered / sold / destroyed at the FP level. Disposal
    //    requests are NOT excluded at the FP level (a multi-item forfeit can
    //    have one item requested while another is still pending / on appeal
    //    hold) — that is handled item-by-item below.
    return (data as List)
        .where((e) =>
            !tenderedIds.contains(e['id']) &&
            !goneIds.contains(e['id'].toString()))
        .map((e) => ForfeitedPackageModel.fromJson(e))
        .where((f) {
          // Keep the FP only while it has at least one item NOT yet requested.
          // Whole-FP legacy requests (no per-item key) are caught by the raw id.
          final items = f.packageDetails?.items ?? const [];
          if (items.isEmpty) return !requestedIds.contains(f.id);
          return items.any(
              (i) => !requestedItemKeys.contains('${f.packageId}:${i.id}'));
        })
        .toList();
  }

  /// All forfeited_packages rows for a given [source] ('abandoned' | 'other' |
  /// 'forfeit'), with package + item detail — used by the yard reports for the
  /// Abandoned / Other pages (the main getForfeitedPackages() is forfeit-only).
  Future<List<ForfeitedPackageModel>> getForfeitedBySource(String source) async {
    final data = await supabase
        .from('forfeited_packages')
        .select(
            '*, packages(*, package_items(*), warehouse_entries(*, warehouses(*)))')
        .eq('source', source)
        .order('forfeited_at', ascending: false);
    return (data as List).map((e) => ForfeitedPackageModel.fromJson(e)).toList();
  }

  /// Forfeited package ids that have reached a terminal sale/destruction
  /// outcome (a sold tender-sale item, or a destroyed destruction item) and
  /// should therefore no longer appear in the Forfeited list.
  Future<Set<String>> _soldOrDestroyedForfeitedIds() async {
    final soldData = await supabase
        .from('tender_sale_items')
        .select('forfeited_package_id')
        .eq('sold', true);
    final destroyedData = await supabase
        .from('destruction_items')
        .select('forfeited_package_id')
        .eq('destroyed', true);
    return {
      ...(soldData as List).map((e) => e['forfeited_package_id'].toString()),
      ...(destroyedData as List).map((e) => e['forfeited_package_id'].toString()),
    };
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

  /// Create a forfeited package record.
  ///
  /// Both the forfeited date and the 30-day appeal window are anchored to the
  /// package's SR-form Entry Date ([entryDate]) — not the moment of forfeiture —
  /// so the deadline reflects when the goods actually entered. The appeal
  /// deadline is Entry Date + 30 days. Falls back to now if no entry date.
  Future<ForfeitedPackageModel> createForfeitedPackage({
    required String packageId,
    required String srNumber,
    required String consigneeName,
    required String reason,
    DateTime? entryDate,
  }) async {
    final forfeitedAt = entryDate ?? DateTime.now();
    final appealDeadline = forfeitedAt.add(const Duration(days: 30));
    final data = await supabase
        .from('forfeited_packages')
        .insert({
          'package_id': packageId,
          'yard': AppSession.currentYard,
          'sr_number': srNumber,
          'consignee_name': consigneeName,
          'forfeited_at': forfeitedAt.toIso8601String(),
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
    // ── 1. Genuine forfeits whose appeal window has PASSED ───────────────────
    // Only appeal-expired forfeits can be sent in a disposal request. Excludes:
    //   • appeals still open (window not yet passed),
    //   • packages currently on an appeal hold,
    //   • packages the Appeal Directorate decided as RELEASE / RE-EXPORT / OTHER
    //     (those are handled directly by the yard, not via a request).
    // Already-requested items (this yard, via RLS). A disposal request stores a
    // forfeited_packages row that carries the originating (package_id, item_id);
    // because forfeit rows in this list use a SYNTHETIC composite id
    // ("<fpId>:<itemId>:forfeit"), matching on the raw FP id alone misses them.
    // So we also build a set of "<packageId>:<itemId>" keys from the requested
    // rows' forfeited package, and exclude any item that already has a request.
    final requested = await AuthService._withNetworkRetry(() => supabase
        .from('disposal_request_items')
        .select(
            'forfeited_package_id, forfeited_packages(package_id, item_id)'));
    final requestedIds = <String>{};
    final requestedItemKeys = <String>{};
    for (final e in (requested as List)) {
      requestedIds.add(e['forfeited_package_id'].toString());
      final fp = e['forfeited_packages'] as Map<String, dynamic>?;
      final pkgId = fp?['package_id']?.toString();
      final itemId = fp?['item_id']?.toString();
      if (pkgId != null && itemId != null) {
        requestedItemKeys.add('$pkgId:$itemId');
      }
    }

    // Packages already SOLD or DESTROYED can't be requested again — drop them.
    final goneIds = await _soldOrDestroyedForfeitedIds();

    // Pull all (non-hold) genuine forfeits; the appeal-window / decision gate is
    // applied client-side via [ForfeitedPackageModel.isActionable] so packages
    // that received an appeal DECISION are requestable immediately (no need to
    // wait out the 30-day window).
    // NOTE: we do NOT filter appeal_hold at the SQL level. The flag is
    // package-level, so a single held item would wrongly exclude the WHOLE
    // package — hiding its decided/expired siblings. Holds are enforced PER ITEM
    // in itemRequestable below instead.
    final fpData = await AuthService._withNetworkRetry(() => supabase
        .from('forfeited_packages')
        .select(
            '*, packages(*, package_items(*), warehouse_entries(*, warehouses(*), returned_profile:profiles!returned_by(full_name, badge_number)))')
        .eq('source', 'forfeit')
        .order('appeal_deadline', ascending: true));

    const _nonDisposalDecisions = {'RELEASE', 'RE-EXPORT', 'OTHER'};
    // An item is requestable when it can go to a disposal request: the window
    // passed (yard picks the disposition) OR the Appeal Directorate gave it a
    // SALE/DESTROY decision. NOT requestable when: it is on appeal hold, or it
    // has a per-item RELEASE/RE-EXPORT/OTHER decision (handled directly).
    bool itemRequestable(ForfeitedPackageModel f, String itemId) {
      final held = f.heldItemIds.isNotEmpty
          ? f.heldItemIds.contains(itemId)
          : f.appealHold;
      if (held) return false;
      final dec = (f.appealDecisionForItem(itemId) ?? '').toUpperCase();
      if (_nonDisposalDecisions.contains(dec)) return false;
      return f.isAppealExpired || dec == 'SALE' || dec == 'DESTROY';
    }

    final baseForfeit = (fpData as List)
        .where((e) => !requestedIds.contains(e['id']))
        .where((e) => !goneIds.contains(e['id'].toString()))
        // Keep the package-level RELEASE/RE-EXPORT/OTHER exclusion only for the
        // legacy package-level decision (no per-item map) — per-item outcomes are
        // filtered per item during expansion below.
        .where((e) {
          final hasPerItem = (e['item_appeal_decisions'] as Map?)?.isNotEmpty
              ?? false;
          if (hasPerItem) return true;
          return !_nonDisposalDecisions
              .contains(((e['appeal_decision'] as String?) ?? '').toUpperCase());
        })
        .map((e) => ForfeitedPackageModel.fromJson(e))
        // Keep the package if the window passed OR any item carries a decision —
        // per-item actionability is enforced during expansion.
        .where((f) =>
            f.isAppealExpired ||
            f.itemAppealDecisions.isNotEmpty ||
            f.hasAppealDecisionForItem(null))
        .toList();

    // Expand multi-item forfeited packages into per-item rows so every item
    // can be individually tagged for Destruction or Sale.
    final result = <ForfeitedPackageModel>[];
    for (final f in baseForfeit) {
      final items = f.packageDetails?.items ?? const [];
      if (items.length <= 1) {
        // Single-item (or no details): skip if this item already has a request.
        if (items.isNotEmpty &&
            requestedItemKeys.contains('${f.packageId}:${items.first.id}')) {
          continue;
        }
        // Skip if this item is not (yet) requestable per-item.
        if (items.isNotEmpty && !itemRequestable(f, items.first.id)) {
          continue;
        }
        // Keep as-is, populate itemName if known.
        final itemName = items.isNotEmpty ? items.first.itemName : f.itemName;
        result.add(ForfeitedPackageModel(
          id: items.isNotEmpty ? '${f.id}:${items.first.id}:forfeit' : f.id,
          packageId: f.packageId,
          srNumber: f.srNumber,
          consigneeName: f.consigneeName,
          forfeitedAt: f.forfeitedAt,
          appealDeadline: f.appealDeadline,
          reason: f.reason,
          yard: f.yard,
          source: f.source,
          appealHold: f.appealHold,
          appealHoldNote: f.appealHoldNote,
          appealHeldAt: f.appealHeldAt,
          heldItemIds: f.heldItemIds,
          appealDecision: f.appealDecision,
          appealDecisionNote: f.appealDecisionNote,
          appealDecidedAt: f.appealDecidedAt,
          itemAppealDecisions: f.itemAppealDecisions,
          packageDetails: f.packageDetails,
          itemId: items.isNotEmpty ? items.first.id : f.itemId,
          itemName: itemName,
        ));
      } else {
        // Multi-item: one row per item with a synthetic composite id so each
        // can be independently selected in the disposal request form.
        for (final item in items) {
          // Skip items already sent in a disposal request.
          if (requestedItemKeys.contains('${f.packageId}:${item.id}')) {
            continue;
          }
          // Skip items not (yet) requestable — still in appeal with no decision,
          // or given a non-disposal (RELEASE/RE-EXPORT/OTHER) decision.
          if (!itemRequestable(f, item.id)) continue;
          result.add(ForfeitedPackageModel(
            id: '${f.id}:${item.id}:forfeit',
            packageId: f.packageId,
            srNumber: f.srNumber,
            consigneeName: f.consigneeName,
            forfeitedAt: f.forfeitedAt,
            appealDeadline: f.appealDeadline,
            reason: f.reason,
            yard: f.yard,
            source: f.source,
            appealHold: f.appealHold,
            appealHoldNote: f.appealHoldNote,
            appealHeldAt: f.appealHeldAt,
            heldItemIds: f.heldItemIds,
            appealDecision: f.appealDecision,
            appealDecisionNote: f.appealDecisionNote,
            appealDecidedAt: f.appealDecidedAt,
          itemAppealDecisions: f.itemAppealDecisions,
            packageDetails: f.packageDetails,
            itemId: item.id,
            itemName: item.itemName,
          ));
        }
      }
    }

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

    // ── 3. "Other"-status packages (no appeal — requestable immediately) ─────
    // Track at item level so that only the specific item that was already
    // requested is excluded — other items in the same package remain requestable.
    final existingOtherFp = await AuthService._withNetworkRetry(() => supabase
        .from('forfeited_packages')
        .select('package_id, item_id')
        .eq('source', 'other'));
    final otherFpItemKeys = (existingOtherFp as List).map((e) {
      final pkgId = e['package_id'].toString();
      final itemId = e['item_id']?.toString();
      return itemId != null ? '$pkgId:$itemId' : pkgId;
    }).toSet();

    final expiredDeadline = DateTime.now().subtract(const Duration(days: 1));

    for (final raw in (pkgData as List)) {
      final pkg = PackageModel.fromJson(raw as Map<String, dynamic>);
      final alreadyAbandoned = abandonedFpPkgIds.contains(pkg.id);

      // One requestable row PER qualifying ITEM+EVENT:
      //   • Abandoned: one row per [ABANDONED] warehouse entry event, id =
      //     "<pkgId>:<itemId>:<entryId>:abandoned" — mirrors the Abandoned
      //     Packages screen which shows one row per event (partial qty events).
      //   • Other: one row per item, id = "<pkgId>:<itemId>:other".
      for (final item in pkg.items) {
        // Check at item level so only the already-requested item is excluded.
        final alreadyOther = otherFpItemKeys.contains('${pkg.id}:${item.id}') ||
            otherFpItemKeys.contains(pkg.id);
        if (!alreadyAbandoned) {
          final abandonedEntries = _abandonedEntriesForItem(pkg, item);
          for (final entry in abandonedEntries) {
            result.add(ForfeitedPackageModel(
              id: '${pkg.id}:${item.id}:${entry.id}:abandoned',
              packageId: pkg.id,
              srNumber: pkg.srNumber,
              consigneeName: pkg.consigneeName,
              forfeitedAt: pkg.createdAt,
              // No appeal for abandoned goods → already-passed deadline.
              appealDeadline: expiredDeadline,
              reason: _abandonReasonFor(pkg),
              yard: AppSession.currentYard,
              source: 'abandoned',
              packageDetails: pkg,
              itemId: item.id,
              itemName: item.itemName,
              entryQty: entry.itemCount,
            ));
          }
          // Form-level abandoned (status='abandoned', no warehouse entry event).
          if (abandonedEntries.isEmpty &&
              _itemIsRequestableAbandoned(pkg, item)) {
            result.add(ForfeitedPackageModel(
              id: '${pkg.id}:${item.id}:abandoned',
              packageId: pkg.id,
              srNumber: pkg.srNumber,
              consigneeName: pkg.consigneeName,
              forfeitedAt: pkg.createdAt,
              appealDeadline: expiredDeadline,
              reason: _abandonReasonFor(pkg),
              yard: AppSession.currentYard,
              source: 'abandoned',
              packageDetails: pkg,
              itemId: item.id,
              itemName: item.itemName,
            ));
          }
        }

        if (!alreadyOther && _itemIsRequestableOther(pkg, item)) {
          // One row PER "[OTHER]" disposition event (partial qty), id =
          // "<pkgId>:<itemId>:<entryId>:other" — mirrors the Other Packages
          // screen which shows a separate row, with its own qty, per event.
          final otherEntries = _otherEntriesForItem(pkg, item);
          for (final entry in otherEntries) {
            result.add(ForfeitedPackageModel(
              id: '${pkg.id}:${item.id}:${entry.id}:other',
              packageId: pkg.id,
              srNumber: pkg.srNumber,
              consigneeName: pkg.consigneeName,
              forfeitedAt: pkg.createdAt,
              appealDeadline: expiredDeadline,
              reason: _otherReasonFor(pkg),
              yard: AppSession.currentYard,
              source: 'other',
              packageDetails: pkg,
              itemId: item.id,
              itemName: item.itemName,
              entryQty: entry.itemCount,
            ));
          }
          // Form-level "Other" status with no "[OTHER]" disposition event —
          // a single row for the whole item.
          if (otherEntries.isEmpty) {
            result.add(ForfeitedPackageModel(
              id: '${pkg.id}:${item.id}:other',
              packageId: pkg.id,
              srNumber: pkg.srNumber,
              consigneeName: pkg.consigneeName,
              forfeitedAt: pkg.createdAt,
              // No appeal for "Other" goods → already-passed deadline.
              appealDeadline: expiredDeadline,
              reason: _otherReasonFor(pkg),
              yard: AppSession.currentYard,
              source: 'other',
              packageDetails: pkg,
              itemId: item.id,
              itemName: item.itemName,
            ));
          }
        }
      }
    }

    return result;
  }

  /// Forfeit → disposal lifecycle counts for the current yard, used by the
  /// Admin Dashboard summary card. Counts are package-level (one forfeited
  /// package = one unit).
  Future<Map<String, dynamic>> getForfeitLifecycleSummary() async {
    final yard = AppSession.currentYard;

    // Forfeited packages in this yard → appeal hold / appeal decision counts.
    final fpRows = await supabase
        .from('forfeited_packages')
        .select('id, appeal_hold, appeal_decision')
        .eq('yard', yard)
        .eq('source', 'forfeit');
    int appealHold = 0;
    int appealDecided = 0;
    for (final r in (fpRows as List)) {
      if (r['appeal_hold'] == true) appealHold++;
      final dec = (r['appeal_decision'] as String?)?.trim();
      if (dec != null && dec.isNotEmpty) appealDecided++;
    }

    // Disposal requests (this yard) → how many asked for sale vs destruction.
    final reqRows = await supabase
        .from('disposal_request_items')
        .select('disposition, forfeited_packages!inner(yard)')
        .eq('forfeited_packages.yard', yard);
    int requestedSale = 0;
    int requestedDestruction = 0;
    for (final r in (reqRows as List)) {
      final d = (r['disposition'] as String?)?.toLowerCase();
      if (d == 'sale') requestedSale++;
      if (d == 'destruction') requestedDestruction++;
    }

    // Tender-sale items (this yard) → sold vs not-yet-sold (unsold).
    final tsRows = await supabase
        .from('tender_sale_items')
        .select('sold')
        .eq('yard', yard);
    int tenderTotal = (tsRows as List).length;
    int sold = tsRows.where((r) => r['sold'] == true).length;
    int unsold = tenderTotal - sold;

    // Destruction items (this yard) → queued vs destroyed.
    final deRows = await supabase
        .from('destruction_items')
        .select('destroyed')
        .eq('yard', yard);
    int destroyed = (deRows as List).where((r) => r['destroyed'] == true).length;

    // Next scheduled tender-sale date (a sale_date today or in the future).
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final nextSale = await supabase
        .from('tender_sales')
        .select('sale_date')
        .eq('yard', yard)
        .gte('sale_date', today)
        .order('sale_date', ascending: true)
        .limit(1)
        .maybeSingle();
    final nextTenderSaleDate = nextSale?['sale_date'] as String?;

    return {
      'appealHold': appealHold,
      'appealDecided': appealDecided,
      'requestedSale': requestedSale,
      'requestedDestruction': requestedDestruction,
      'tenderSold': sold,
      'tenderUnsold': unsold,
      'destroyed': destroyed,
      'nextTenderSaleDate': nextTenderSaleDate,
    };
  }

  /// True if a package has any abandoned item — either a form-level abandoned
  /// item (status 'abandoned') or an `[ABANDONED]` disposition event. Mirrors
  /// the detection in abandoned_packages_screen.dart, minus the final-
  /// disposition exclusion (a finalised package can't be requested anyway).
  bool _packageHasAbandonedItem(PackageModel p) =>
      p.items.any((item) => _itemIsRequestableAbandoned(p, item));

  /// True if a single item is an abandoned item that can be sent in a disposal
  /// request — a form-level 'abandoned' status or an `[ABANDONED]` disposition
  /// event, and not already finalised ([FINAL:…]).
  bool _itemIsRequestableAbandoned(PackageModel p, PackageItem item) {
    final entries =
        p.warehouseEntries.where((e) => e.packageItemId == item.id);
    final hasFinal = entries.any((e) =>
        (e.returnNotes ?? '').trim().toUpperCase().startsWith('[FINAL:'));
    if (hasFinal) return false;
    bool isAbandonedEntry(WarehouseEntryModel e) =>
        e.isReturned &&
        (e.returnNotes ?? '').trim().toUpperCase().startsWith('[ABANDONED]');
    if (entries.any(isAbandonedEntry)) return true;
    if ((item.status ?? '').trim().toLowerCase() == 'abandoned' &&
        !entries.any(isAbandonedEntry)) {
      return true;
    }
    return false;
  }

  /// Returns all [ABANDONED] warehouse entry events for a single item that are
  /// not already finalised — one entry per partial-qty abandonment event.
  List<WarehouseEntryModel> _abandonedEntriesForItem(
      PackageModel p, PackageItem item) {
    final entries =
        p.warehouseEntries.where((e) => e.packageItemId == item.id).toList();
    final hasFinal = entries.any((e) =>
        (e.returnNotes ?? '').trim().toUpperCase().startsWith('[FINAL:'));
    if (hasFinal) return const [];
    return entries
        .where((e) =>
            e.isReturned &&
            (e.returnNotes ?? '').trim().toUpperCase().startsWith('[ABANDONED]'))
        .toList();
  }

  /// Partial/full "[OTHER]" disposition events for an item — one per event, so
  /// the disposal-request list mirrors the Other Packages table (which shows a
  /// separate row, with its own qty, per "[OTHER: …]" warehouse event). Skipped
  /// once any final disposition ([FINAL:…]) exists for the item.
  List<WarehouseEntryModel> _otherEntriesForItem(
      PackageModel p, PackageItem item) {
    final entries =
        p.warehouseEntries.where((e) => e.packageItemId == item.id).toList();
    final hasFinal = entries.any((e) =>
        (e.returnNotes ?? '').trim().toUpperCase().startsWith('[FINAL:'));
    if (hasFinal) return const [];
    return entries.where((e) {
      if (!e.isReturned) return false;
      final notes = (e.returnNotes ?? '').trim().toUpperCase();
      return notes.startsWith('[OTHER:') ||
          notes.startsWith('[OTHER]') ||
          notes.startsWith('[OTHER ');
    }).toList();
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

  /// True if a package has any "Other"-status item still held in the warehouse.
  /// "Other" is set on the SR registration form (a custom disposition, e.g.
  /// court-held / pending-decision). Like abandoned goods it has NO appeal
  /// period — the yard admin can release / re-export / record an outcome
  /// directly, or send it to Central Disposal for sale / destruction.
  /// An item already finalised ([FINAL:…]) is ignored.
  bool _packageHasOtherItem(PackageModel p) =>
      p.items.any((item) => _itemIsRequestableOther(p, item));

  /// True if a single item is an "Other" item that can be sent in a disposal
  /// request — a form-level Other status, OR a partial "[OTHER:]" disposition
  /// event from the warehouse Actions dialog (those leave item.status as
  /// 'detain'). Not already finalised ([FINAL:…]).
  bool _itemIsRequestableOther(PackageModel p, PackageItem item) {
    final entries =
        p.warehouseEntries.where((e) => e.packageItemId == item.id);
    final hasFinal = entries.any((e) =>
        (e.returnNotes ?? '').trim().toUpperCase().startsWith('[FINAL:'));
    if (hasFinal) return false;
    // A partial "[OTHER:]" disposition event (status stays 'detain').
    final hasOtherEntry = entries.any((e) =>
        e.isReturned &&
        (e.returnNotes ?? '').trim().toUpperCase().startsWith('[OTHER'));
    if (hasOtherEntry) return true;
    final st = (item.status ?? '').trim().toLowerCase();
    // Explicit "Other"/"Other: <text>" marker always qualifies.
    if (st == 'other' || st.startsWith('other:')) return true;
    // Legacy free-text status only when the item is actually held.
    if (st.isNotEmpty &&
        !_knownStatuses.contains(st) &&
        entries.any((e) => !e.isReturned)) {
      return true;
    }
    return false;
  }

  /// An item status is "Other" when it is neither one of the built-in
  /// dispositions (detain / forfeit / abandoned / released / re-export /
  /// destroy / sold) nor empty/cleared. The SR form stores the custom text the
  /// officer typed in the "Other Status" field, so we treat anything outside
  /// the known set as an "Other" disposition.
  static const Set<String> _knownStatuses = {
    'detain', 'detained', 'held',
    'forfeit', 'forfiet', 'forfeited', 'confiscated',
    'abandoned',
    'released', 'returned', 'cleared',
    're-export', 're-exported', 'reexport',
    'destroy', 'destroyed',
    'sold', 'sale',
    'inspecting', 'pending', '',
  };

  bool _statusIsOther(String? s) {
    final v = (s ?? '').trim().toLowerCase();
    if (v.isEmpty) return false;
    if (v == 'other' || v.startsWith('other:')) return true;
    return !_knownStatuses.contains(v);
  }

  /// Custom "Other" disposition label — strips the "Other:" marker prefix.
  String _otherLabelFor(String? s) {
    final raw = (s ?? '').trim();
    if (raw.toLowerCase().startsWith('other:')) {
      final t = raw.substring(6).trim();
      return t.isEmpty ? 'Other' : t;
    }
    if (raw.isEmpty || raw.toLowerCase() == 'other') return 'Other';
    return raw;
  }

  String _otherReasonFor(PackageModel p) {
    for (final item in p.items) {
      if (!_statusIsOther(item.status)) continue;
      // The custom "Other Status" text is the most descriptive label.
      final label = _otherLabelFor(item.status);
      if (label != 'Other') return label;
      if (item.reasons?.isNotEmpty == true) return item.reasons!;
      final entries =
          p.warehouseEntries.where((e) => e.packageItemId == item.id).toList();
      if (entries.isNotEmpty && entries.first.holdReason.isNotEmpty) {
        return entries.first.holdReason;
      }
    }
    return 'Other';
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

    // Key formats in [dispositions]:
    //   • Plain UUID                       → genuine forfeited_package id
    //   • "<fpId>:<itemId>:forfeit"        → per-item expanded forfeit row
    //   • "<pkgId>:<itemId>:abandoned"     → synthetic (form-level abandoned)
    //   • "<pkgId>:<itemId>:<entryId>:abandoned" → per-entry abandoned event
    //   • "<pkgId>:<itemId>:other"         → synthetic Other row
    // The forfeit variants already have a real FP row — map them directly.
    // Abandoned/Other synthetic rows need a new FP row created on the fly.
    (String packageId, String? itemId, String? entryId, String source)
        parseSynthetic(String key) {
      final parts = key.split(':');
      // 4-part: pkgId:itemId:entryId:source
      if (parts.length == 4) return (parts[0], parts[1], parts[2], parts[3]);
      // 3-part: pkgId:itemId:source  OR  fpId:itemId:forfeit
      if (parts.length == 3) return (parts[0], parts[1], null, parts[2]);
      if (parts.length == 2) return (parts[0], null, null, parts[1]);
      return (key, null, null, 'abandoned');
    }

    final selectedKeys = dispositions.keys.toList();
    // All keys without ':' are plain forfeited_package UUIDs.
    // Keys ending in ':forfeit' are per-item expanded rows — the first part IS
    // the real forfeited_package id.
    final directFpKeys = selectedKeys
        .where((k) => !k.contains(':') || k.endsWith(':forfeit'))
        .toList();
    final directFpIds = directFpKeys.map((k) {
      if (!k.contains(':')) return k;
      return k.split(':').first; // fpId from "<fpId>:<itemId>:forfeit"
    }).toSet();
    final realFpIds = directFpIds; // they're all real FP rows

    // key (selection id) → forfeited_packages id to store on the request item.
    final forfeitedIdFor = <String, String>{};
    // Cache so one (package, item, source) creates exactly one FP row — each
    // selected item gets its own row (with item_id) so it never aggregates with
    // the package's other items.
    final fpIdByPkgItemSource = <String, String>{};
    for (final key in selectedKeys) {
      // Plain UUID → already a real FP row.
      if (!key.contains(':')) {
        forfeitedIdFor[key] = key;
        continue;
      }
      // Per-item forfeit synthetic key:
      //   3-part: "<fpId>:<itemId>:forfeit"            (full-item forfeit)
      //   4-part: "<fpId>:<itemId>:<entryId>:forfeit"  (partial forfeit event)
      // Create a new per-item FP row (copying the parent FP's fields but with
      // item_id set) so Valuation / Central Disposal can show each item
      // separately with the correct name, HS code, and quantity. For the 4-part
      // variant we also store the partial forfeit warehouse entry's itemCount as
      // entry_qty, so Valuation/Central Disposal price the partial qty (e.g. 2)
      // rather than the full registered item quantity (e.g. 48).
      if (key.endsWith(':forfeit')) {
        final cached = fpIdByPkgItemSource[key];
        if (cached != null) {
          forfeitedIdFor[key] = cached;
          continue;
        }
        final parts = key.split(':');
        final parentFpId = parts[0];
        final itemId = parts[1];
        // 4-part key carries the originating forfeit warehouse entry id.
        final forfeitEntryId = parts.length == 4 ? parts[2] : null;
        // Fetch the parent FP row to copy its fields.
        final parentRaw = await AuthService._withNetworkRetry(() => supabase
            .from('forfeited_packages')
            .select(
                '*, packages(*, package_items(*), warehouse_entries(*, warehouses(*)))')
            .eq('id', parentFpId)
            .single());
        final parentFp = ForfeitedPackageModel.fromJson(
            parentRaw as Map<String, dynamic>);
        // Resolve the partial forfeit qty from the named warehouse entry.
        int? forfeitEntryQty;
        if (forfeitEntryId != null) {
          final matches = (parentFp.packageDetails?.warehouseEntries ?? const [])
              .where((e) => e.id == forfeitEntryId)
              .toList();
          if (matches.isNotEmpty) forfeitEntryQty = matches.first.itemCount;
        }
        final newFp = await AuthService._withNetworkRetry(() => supabase
            .from('forfeited_packages')
            .insert({
              'package_id': parentFp.packageId,
              'item_id': itemId,
              if (forfeitEntryQty != null) 'entry_qty': forfeitEntryQty,
              'sr_number': parentFp.srNumber,
              'consignee_name': parentFp.consigneeName,
              'forfeited_at': parentFp.forfeitedAt.toIso8601String(),
              'appeal_deadline': parentFp.appealDeadline?.toIso8601String() ??
                  DateTime.now()
                      .subtract(const Duration(days: 1))
                      .toIso8601String(),
              'reason': parentFp.reason ?? 'Forfeited',
              'yard': parentFp.yard ?? AppSession.currentYard,
              'source': 'forfeit',
              if (parentFp.appealDecision != null)
                'appeal_decision': parentFp.appealDecision,
            })
            .select('id')
            .single());
        final newId = newFp['id'] as String;
        fpIdByPkgItemSource[key] = newId;
        forfeitedIdFor[key] = newId;
        continue;
      }
      final (packageId, itemId, entryId, source) = parseSynthetic(key);
      // Use the full key as cache key so per-entry abandoned rows (same
      // pkg+item but different warehouse entry) each get their own FP row.
      final cacheKey = key;
      final cached = fpIdByPkgItemSource[cacheKey];
      if (cached != null) {
        forfeitedIdFor[key] = cached;
        continue;
      }
      final pkgRaw = await AuthService._withNetworkRetry(() => supabase
          .from('packages')
          .select('*, package_items(*), warehouse_entries(*)')
          .eq('id', packageId)
          .single());
      final pkg = PackageModel.fromJson(pkgRaw);
      final reason =
          source == 'other' ? _otherReasonFor(pkg) : _abandonReasonFor(pkg);
      // For per-entry abandoned rows, store the exact abandoned qty from the
      // originating warehouse entry so the Valuation / Central Disposal screens
      // price against that quantity (15 / 19) rather than the full item qty.
      int? entryQty;
      if (entryId != null) {
        final matches =
            pkg.warehouseEntries.where((e) => e.id == entryId).toList();
        if (matches.isNotEmpty) entryQty = matches.first.itemCount;
      }
      final newFp = await AuthService._withNetworkRetry(() => supabase
          .from('forfeited_packages')
          .insert({
            'package_id': packageId,
            if (itemId != null) 'item_id': itemId,
            if (entryQty != null) 'entry_qty': entryQty,
            'sr_number': pkg.srNumber,
            'consignee_name': pkg.consigneeName,
            'forfeited_at': DateTime.now().toIso8601String(),
            'appeal_deadline': DateTime.now()
                .subtract(const Duration(days: 1))
                .toIso8601String(),
            'reason': reason,
            'yard': AppSession.currentYard,
            'source': source,
          })
          .select('id')
          .single());
      final newId = newFp['id'] as String;
      fpIdByPkgItemSource[cacheKey] = newId;
      forfeitedIdFor[key] = newId;
    }

    // Several selected items can resolve to the same FP row (same package+
    // source). Collapse to unique (forfeited_package_id, disposition) pairs so
    // we don't insert duplicate request items for one package.
    final seenItemRows = <String>{};
    final items = <Map<String, dynamic>>[];
    for (final e in dispositions.entries) {
      final fpId = forfeitedIdFor[e.key];
      if (fpId == null) continue;
      if (!seenItemRows.add('$fpId|${e.value}')) continue;
      items.add({
        'request_id': requestId,
        'forfeited_package_id': fpId,
        'disposition': e.value,
      });
    }
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
  /// Sold packages for a yard, or — when [yard] is null — across ALL yards.
  Future<List<PackageModel>> getSoldPackages({String? yard}) async {
    return PackageService().getAllPackages(yard: yard);
  }

  /// Destroyed packages for a yard, or — when [yard] is null — across ALL yards.
  /// Mirrors [getSoldPackages]; the screen filters to "[FINAL:DESTROYED]" entries.
  Future<List<PackageModel>> getDestroyedPackages({String? yard}) async {
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

    // 1c. Sold / destroyed packages belong on the Sold / Destroyed pages.
    final soldData = await supabase
        .from('tender_sale_items')
        .select('forfeited_package_id')
        .eq('sold', true);
    final destroyedData = await supabase
        .from('destruction_items')
        .select('forfeited_package_id')
        .eq('destroyed', true);
    final goneIds = <String>{
      ...(soldData as List).map((e) => e['forfeited_package_id'].toString()),
      ...(destroyedData as List).map((e) => e['forfeited_package_id'].toString()),
    };

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
        .where((e) =>
            !tenderedIds.contains(e['id']) &&
            !requestedIds.contains(e['id']) &&
            !goneIds.contains(e['id'].toString()))
        .map((e) => ForfeitedPackageModel.fromJson(e))
        .toList();
  }

  Future<List<TenderSaleModel>> getTenderSales() async {
    final data = await AuthService._withNetworkRetry(() => supabase
        .from('tender_sales')
        .select(
            '*, profiles!created_by(full_name), tender_sale_items(*, forfeited_packages(*, disposal_request_items!forfeited_package_id(valuation_cost), packages(*, package_items(*), warehouse_entries(*, warehouses(*)))))')
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

      // A package can sit in SEVERAL tender sales (original + each re-tender).
      // The CURRENT tender is the most-recently-CREATED sale (createdAt always
      // increases; a re-tender with no date yet must still count as the latest).
      // The package is "unsold / re-tenderable" only once that current sale's
      // moment has passed AND it is not sold. A freshly placed re-tender's
      // moment is in the future / unset, so the package is a PENDING tender on
      // the Tender Sales page — it leaves this pool until it goes unsold again.
      final latest = [...ts]
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt)); // newest first
      // Unsold only after the sale-day's GRACE window closes (sale date + the
      // following day) — matches the "Sell within" countdown on the card. Until
      // then the item is still markable on the Tender Sales page.
      final deadline = latest.first.unsoldDeadline;
      // No date ⇒ treat as not-yet-due (pending), so not unsold.
      final passed = deadline != null && DateTime.now().isAfter(deadline);
      if (passed) eligible[id] = ts;
    });

    if (eligible.isEmpty) return [];

    final fp = await AuthService._withNetworkRetry(() => supabase
        .from('forfeited_packages')
        .select(
            '*, disposal_request_items!forfeited_package_id(valuation_cost), packages(*, package_items(*), warehouse_entries(*, warehouses(*)))')
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

  // ── Tender bids (recorded per tender ROUND on unsold packages) ────────────

  /// Bids recorded for an unsold tender package, grouped by tender round
  /// (tender_sale_id → amounts, oldest first). Bids saved before the round
  /// key existed group under the empty-string key ''.
  Future<Map<String, List<double>>> getTenderBidsByRound(
      String forfeitedPackageId) async {
    final rows = await AuthService._withNetworkRetry(() => supabase
        .from('tender_bids')
        .select('tender_sale_id, amount')
        .eq('forfeited_package_id', forfeitedPackageId)
        .order('created_at', ascending: true));
    final byRound = <String, List<double>>{};
    for (final e in (rows as List)) {
      byRound
          .putIfAbsent((e['tender_sale_id'] as String?) ?? '', () => [])
          .add((e['amount'] as num).toDouble());
    }
    return byRound;
  }

  /// Replace the bids of ONE tender round with [amounts] (blanks/zeros skipped).
  /// Other rounds' bids for the same package are untouched.
  Future<void> saveTenderRoundBids(
      String forfeitedPackageId, String tenderSaleId, List<double> amounts,
      {String? yard}) async {
    await AuthService._withNetworkRetry(() => supabase
        .from('tender_bids')
        .delete()
        .eq('forfeited_package_id', forfeitedPackageId)
        .eq('tender_sale_id', tenderSaleId));
    final clean = amounts.where((a) => a > 0).toList();
    if (clean.isEmpty) return;
    final uid = supabase.auth.currentUser?.id;
    await AuthService._withNetworkRetry(() => supabase.from('tender_bids').insert([
          for (final a in clean)
            {
              'forfeited_package_id': forfeitedPackageId,
              'tender_sale_id': tenderSaleId,
              'amount': a,
              'yard': yard,
              'created_by': uid,
            }
        ]));
  }

  /// For the Appeal portal: every forfeited package that has ≥1 recorded bid,
  /// hydrated with its package details, the recorded rounds (each a tender sale
  /// + its bid amounts, highest first) newest round first.
  Future<
      List<
          ({
            ForfeitedPackageModel forfeited,
            List<({TenderSaleModel? sale, List<double> bids})> rounds
          })>> getPackagesWithBids() async {
    final rows = await AuthService._withNetworkRetry(() => supabase
        .from('tender_bids')
        .select('forfeited_package_id, tender_sale_id, amount')
        .order('created_at', ascending: true));
    // fp id → (round key → amounts)
    final byPkg = <String, Map<String, List<double>>>{};
    for (final e in (rows as List)) {
      byPkg
          .putIfAbsent(e['forfeited_package_id'] as String, () => {})
          .putIfAbsent((e['tender_sale_id'] as String?) ?? '', () => [])
          .add((e['amount'] as num).toDouble());
    }
    if (byPkg.isEmpty) return [];

    final saleIds = <String>{};
    for (final rounds in byPkg.values) {
      for (final k in rounds.keys) {
        if (k.isNotEmpty) saleIds.add(k);
      }
    }

    // Hydrate the tender sales referenced by the bids (for round labels/dates).
    final saleById = <String, TenderSaleModel>{};
    if (saleIds.isNotEmpty) {
      final sr = await AuthService._withNetworkRetry(() => supabase
          .from('tender_sales')
          .select('*, tender_sale_items(*)')
          .inFilter('id', saleIds.toList()));
      for (final e in (sr as List)) {
        final s = TenderSaleModel.fromJson(e as Map<String, dynamic>);
        saleById[s.id] = s;
      }
    }

    final fp = await AuthService._withNetworkRetry(() => supabase
        .from('forfeited_packages')
        .select(
            '*, disposal_request_items!forfeited_package_id(valuation_cost), packages(*, package_items(*), warehouse_entries(*, warehouses(*)))')
        .inFilter('id', byPkg.keys.toList()));

    final result = <({
      ForfeitedPackageModel forfeited,
      List<({TenderSaleModel? sale, List<double> bids})> rounds
    })>[];
    for (final e in (fp as List)) {
      final f = ForfeitedPackageModel.fromJson(e as Map<String, dynamic>);
      final roundMap = byPkg[f.id] ?? const {};
      final rounds = <({TenderSaleModel? sale, List<double> bids})>[];
      roundMap.forEach((k, amounts) {
        final bids = [...amounts]..sort((a, b) => b.compareTo(a));
        rounds.add((sale: k.isEmpty ? null : saleById[k], bids: bids));
      });
      // Newest round first (by sale date/createdAt; null-round last).
      rounds.sort((a, b) {
        final da = a.sale?.createdAt;
        final db = b.sale?.createdAt;
        if (da == null && db == null) return 0;
        if (da == null) return 1;
        if (db == null) return -1;
        return db.compareTo(da);
      });
      result.add((forfeited: f, rounds: rounds));
    }
    result.sort((a, b) => a.forfeited.srNumber.compareTo(b.forfeited.srNumber));
    return result;
  }

  // ── Tender re-valuations (Valuation sets a new value per unsold round) ─────

  /// The set of forfeited_package_ids whose CURRENT (latest) unsold tender round
  /// has a Valuation re-valuation — the only packages Central Disposal may
  /// re-tender. A package with no re-valuation yet is "awaiting valuation".
  Future<Set<String>> getReTenderEligibleIds() async {
    final unsold = await getUnsoldTenderSales();
    if (unsold.isEmpty) return {};
    // Latest round id per package (newest createdAt).
    final latestRound = <String, String>{};
    for (final info in unsold) {
      final sales = [...info.sales]
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (sales.isNotEmpty) latestRound[info.forfeited.id] = sales.first.id;
    }
    final rows = await AuthService._withNetworkRetry(() => supabase
        .from('tender_revaluations')
        .select('forfeited_package_id, tender_sale_id')
        .inFilter('forfeited_package_id', latestRound.keys.toList()));
    final eligible = <String>{};
    for (final e in (rows as List)) {
      final fpId = e['forfeited_package_id'] as String;
      final saleId = e['tender_sale_id'] as String?;
      if (saleId != null && latestRound[fpId] == saleId) eligible.add(fpId);
    }
    return eligible;
  }

  /// The re-valuations recorded for a package, keyed by tender round
  /// (tender_sale_id → re-valuation). Round-less rows key under ''.
  Future<Map<String, TenderRevaluationModel>> getTenderRevaluationsByRound(
      String forfeitedPackageId) async {
    final rows = await AuthService._withNetworkRetry(() => supabase
        .from('tender_revaluations')
        .select('*')
        .eq('forfeited_package_id', forfeitedPackageId)
        .order('created_at', ascending: true));
    final byRound = <String, TenderRevaluationModel>{};
    for (final e in (rows as List)) {
      final m = TenderRevaluationModel.fromJson(e as Map<String, dynamic>);
      byRound[m.tenderSaleId ?? ''] = m; // latest wins (ordered asc)
    }
    return byRound;
  }

  /// Set / replace the Valuation Directorate's re-valuation for ONE tender round.
  Future<void> saveTenderRevaluation(
      String forfeitedPackageId, String tenderSaleId, double valuationCost,
      {String? note, String? yard}) async {
    await AuthService._withNetworkRetry(() => supabase
        .from('tender_revaluations')
        .delete()
        .eq('forfeited_package_id', forfeitedPackageId)
        .eq('tender_sale_id', tenderSaleId));
    final uid = supabase.auth.currentUser?.id;
    await AuthService._withNetworkRetry(() =>
        supabase.from('tender_revaluations').insert({
          'forfeited_package_id': forfeitedPackageId,
          'tender_sale_id': tenderSaleId,
          'valuation_cost': valuationCost,
          'note': (note != null && note.trim().isNotEmpty) ? note.trim() : null,
          'yard': yard,
          'created_by': uid,
        }));
  }

  // ── Tender committees (DG appoints 5 members for >3× unsold packages) ─────

  /// All appointed committees, keyed by forfeited_package_id.
  Future<Map<String, TenderCommitteeModel>> getTenderCommittees() async {
    final rows = await AuthService._withNetworkRetry(
        () => supabase.from('tender_committees').select('*'));
    final out = <String, TenderCommitteeModel>{};
    for (final e in (rows as List)) {
      final m = TenderCommitteeModel.fromJson(e as Map<String, dynamic>);
      out[m.forfeitedPackageId] = m;
    }
    return out;
  }

  /// Appoint / update the committee for a package (upsert by fp id).
  Future<void> saveTenderCommittee(
      String forfeitedPackageId, List<CommitteeMember> members,
      {String? note, String? yard}) async {
    final uid = supabase.auth.currentUser?.id;
    await AuthService._withNetworkRetry(() =>
        supabase.from('tender_committees').upsert({
          'forfeited_package_id': forfeitedPackageId,
          'members':
              members.where((m) => m.name.isNotEmpty).map((m) => m.toJson()).toList(),
          'note': (note != null && note.trim().isNotEmpty) ? note.trim() : null,
          'yard': yard,
          'created_by': uid,
          'updated_at': DateTime.now().toIso8601String(),
        }, onConflict: 'forfeited_package_id'));
  }

  /// Unsold tender packages that have gone unsold MORE THAN 3 times
  /// (≥4 tender attempts) — the pool for DG committee appointment.
  Future<List<ReTenderSaleInfo>> getCommitteeEligiblePackages() async {
    final all = await getUnsoldTenderSales();
    return all.where((i) => i.tenderCount >= 4).toList();
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

    // Only items whose parent request the Valuation Directorate has FORWARDED
    // are saleable — same gate the Disposal Requests feed uses. A request still
    // awaiting valuation must NOT surface in the tender-sale pool.
    final data = await AuthService._withNetworkRetry(() => supabase
        .from('disposal_request_items')
        .select(
            '*, disposal_requests!inner(valuation_status), forfeited_packages(*, packages(*, package_items(*), warehouse_entries(*, warehouses(*))))')
        .eq('disposition', 'sale')
        .eq('forwarded', true));

    final items = (data as List)
        .map((e) => DisposalRequestItemModel.fromJson(e))
        .where((i) => !usedIds.contains(i.forfeitedPackageId))
        .toList();

    // De-duplicate by disposal_request_items.id (not forfeitedPackageId) so
    // multi-item packages each appear as their own row in the picker.
    final seen = <String>{};
    return items.where((i) => seen.add(i.id)).toList();
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

    // Only items whose parent request the Valuation Directorate has FORWARDED
    // are tenderable — same gate the Disposal Requests feed uses. A request
    // still awaiting valuation must NOT surface in the Place-Tender pool.
    final data = await AuthService._withNetworkRetry(() => supabase
        .from('disposal_request_items')
        .select(
            '*, disposal_requests!inner(valuation_status), forfeited_packages(*, packages(*, package_items(*), warehouse_entries(*, warehouses(*))))')
        .eq('disposition', 'sale')
        .eq('forwarded', true));

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
    // Packages placed in a DESTRUCTION sale also leave the requests view (they
    // move on to the Destructions tab) — same as tendered packages.
    final destItems = await AuthService._withNetworkRetry(() =>
        supabase.from('destruction_items').select('forfeited_package_id'));
    for (final e in (destItems as List)) {
      tenderedIds.add(e['forfeited_package_id'].toString());
    }

    final data = await AuthService._withNetworkRetry(() => supabase
        .from('disposal_requests')
        // Pull package_items AND warehouse_entries so the details popup can show
        // full Item Details + Warehouse Summary (like the Forfeited screen).
        .select(
            '*, profiles!created_by(full_name), valued_profile:profiles!valued_by(full_name), disposal_request_items(*, forfeited_packages(*, packages(*, package_items(*), warehouse_entries(*, warehouses(*)))))')
        // Mandatory valuation gate: Central Disposal only sees requests the
        // Valuation Directorate has forwarded.
        .eq('valuation_status', 'forwarded')
        .order('created_at', ascending: false));

    final result = <DisposalRequestModel>[];
    for (final e in (data as List)) {
      final r = DisposalRequestModel.fromJson(e as Map<String, dynamic>);
      final items = r.items
          // Only items the Valuation Directorate has actually forwarded
          // (per-item gate) and not already tendered/destroyed.
          .where((i) =>
              i.forwarded && !tenderedIds.contains(i.forfeitedPackageId))
          .toList();
      if (items.isEmpty) continue; // nothing forwarded / all consumed
      result.add(DisposalRequestModel(
        id: r.id,
        yard: r.yard,
        requestDate: r.requestDate,
        status: r.status,
        createdAt: r.createdAt,
        createdByName: r.createdByName,
        items: items,
        valuationStatus: r.valuationStatus,
        valuedAt: r.valuedAt,
        valuedByName: r.valuedByName,
      ));
    }
    return result;
  }

  /// Get the next serial number for tender sales in a given year.
  /// Next tender-sale serial for a [year], scoped to a [yard] when given so each
  /// yard keeps its own running sequence (GL1's 6th sale is serial 6 even if
  /// GL2 already has 3). A null [yard] falls back to the global max.
  Future<int> getNextTenderSaleSerial(int year, {String? yard}) async {
    final data = await AuthService._withNetworkRetry(() {
      var q = supabase.from('tender_sales').select('serial').eq('year', year);
      if (yard != null && yard.isNotEmpty) q = q.eq('yard', yard);
      return q;
    });
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
  /// [packageItems] maps each forfeited-package id → the specific package_item
  /// id it covers (when known) so the TSI row is item-scoped — this lets
  /// Mark Sold sell exactly that item instead of the whole package.
  Future<void> createTenderSale({
    String? saleNumber,
    DateTime? saleDate,
    String? saleTime,
    String? serial,
    int? year,
    String? tenderType,
    String? yard,
    Map<String, String> packageYards = const {},
    Map<String, String?> packageItems = const {},
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
                // Item-scope the row so Mark Sold sells exactly this item, not
                // the whole package. Falls back to the FP's own item_id in the
                // RPC when null (legacy package-level rows).
                'package_item_id': packageItems[e.key],
                'yard': e.value,
                'sold': false,
                'sold_at': null,
              })
          .toList();
      // Scope the conflict key to THIS sale so re-tendering an unsold item
      // INSERTS a new row here and leaves the original sale's row untouched
      // (the item stays Unsold there and shows Pending here).
      await AuthService._withNetworkRetry(() => supabase
          .from('tender_sale_items')
          .upsert(rows,
              onConflict:
                  'tender_sale_id,forfeited_package_id,package_item_id'));
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
            'p_price': soldPrice,
            'p_taxes': appliedTaxes,
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

  /// Flip a destroyed package's delivery flag (yard OR Central Disposal).
  Future<void> toggleDestructionDelivery(
      String destructionItemId, bool delivered) async {
    await AuthService._withNetworkRetry(() => supabase.rpc(
          'disposal_toggle_destruction_delivery',
          params: {
            'p_item_id': destructionItemId,
            'p_delivered': delivered,
          },
        ));
  }

  /// The destruction item for a given package id (delivery state). Mirrors
  /// [getTenderSaleItemForPackage]. Used by the Destroyed tables + popup.
  Future<DestructionItemModel?> getDestructionItemForPackage(
      String packageId) async {
    final fpkgs = await AuthService._withNetworkRetry(() => supabase
        .from('forfeited_packages')
        .select('id')
        .eq('package_id', packageId));
    final ids = (fpkgs as List).map((e) => e['id'] as String).toList();
    if (ids.isEmpty) return null;
    final data = await AuthService._withNetworkRetry(() => supabase
        .from('destruction_items')
        .select(
            '*, forfeited_packages(*, disposal_request_items!forfeited_package_id(valuation_cost), packages(*, package_items(*), warehouse_entries(*, warehouses(*))))')
        .inFilter('forfeited_package_id', ids)
        .eq('destroyed', true)
        .order('destroyed_at', ascending: false)
        .limit(1)
        .maybeSingle());
    if (data == null) return null;
    return DestructionItemModel.fromJson(data);
  }

  /// Per-item variant: finds the destruction_item whose forfeited_package has
  /// item_id == [packageItemId]. Falls back to package-level when null.
  Future<DestructionItemModel?> getDestructionItemForPackageItem(
      String packageId, String? packageItemId) async {
    if (packageItemId == null) {
      return getDestructionItemForPackage(packageId);
    }
    // An item can have SEVERAL forfeited_packages rows (one per partial
    // disposition), so we gather ALL of them — using maybeSingle() here was the
    // bug that returned null when an item had multiple partial FP rows.
    final fpkgItems = await AuthService._withNetworkRetry(() => supabase
        .from('forfeited_packages')
        .select('id')
        .eq('package_id', packageId)
        .eq('item_id', packageItemId));
    final fpIds =
        (fpkgItems as List).map((e) => e['id'] as String).toList();
    if (fpIds.isNotEmpty) {
      final data = await AuthService._withNetworkRetry(() => supabase
          .from('destruction_items')
          .select(
              '*, forfeited_packages(*, disposal_request_items!forfeited_package_id(valuation_cost), packages(*, package_items(*), warehouse_entries(*, warehouses(*))))')
          .inFilter('forfeited_package_id', fpIds)
          .eq('destroyed', true)
          .order('destroyed_at', ascending: false)
          .limit(1)
          .maybeSingle());
      if (data != null) return DestructionItemModel.fromJson(data);
    }
    return getDestructionItemForPackage(packageId);
  }

  /// Bulk delivery-status map for DESTROYED packages, keyed by package id:
  /// package_id → delivered (bool). Mirrors [getDeliveryStatusByPackageId].
  Future<Map<String, bool>> getDestroyedDeliveryStatusByPackageId() async {
    final data = await AuthService._withNetworkRetry(() => supabase
        .from('destruction_items')
        .select('delivered, destroyed_at, forfeited_packages(package_id)')
        .eq('destroyed', true)
        .order('destroyed_at', ascending: true));
    final out = <String, bool>{};
    for (final e in (data as List)) {
      final fp = e['forfeited_packages'] as Map<String, dynamic>?;
      final pkgId = fp?['package_id']?.toString();
      if (pkgId == null) continue;
      out[pkgId] = (e['delivered'] as bool?) ?? false;
    }
    return out;
  }

  // --- Destructions ---

  Future<List<DestructionModel>> getDestructions() async {
    final data = await AuthService._withNetworkRetry(() => supabase
        .from('destructions')
        .select(
            '*, profiles!created_by(full_name), destruction_items(*, forfeited_packages(*, disposal_request_items!forfeited_package_id(valuation_cost), packages(*, package_items(*), warehouse_entries(*, warehouses(*)))))')
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

      // The current destruction is the most-recently-CREATED one (createdAt
      // always increases). A freshly placed re-destruction's moment is future /
      // unset, so the package is a PENDING destruction on the Destructions page;
      // it leaves the Undestroyed pool until it genuinely goes undestroyed again.
      final latest = [...ts]
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt)); // newest first
      // Undestroyed only after the destruction-day grace window closes (date +
      // the following day) — matches the "Destroy within" countdown.
      final deadline = latest.first.unsoldDeadline;
      final passed = deadline != null && DateTime.now().isAfter(deadline);
      if (passed) eligible[id] = ts;
    });

    if (eligible.isEmpty) return [];

    final fp = await AuthService._withNetworkRetry(() => supabase
        .from('forfeited_packages')
        .select(
            '*, disposal_request_items!forfeited_package_id(valuation_cost), packages(*, package_items(*), warehouse_entries(*, warehouses(*)))')
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

    // Only items whose parent request the Valuation Directorate has FORWARDED
    // are destructible — same gate the Disposal Requests feed uses. A request
    // still awaiting valuation must NOT surface in the Destruction pool.
    final data = await AuthService._withNetworkRetry(() => supabase
        .from('disposal_request_items')
        .select(
            '*, disposal_requests!inner(valuation_status), forfeited_packages(*, packages(*, package_items(*), warehouse_entries(*, warehouses(*))))')
        .eq('disposition', 'destruction')
        .eq('forwarded', true));

    final items = (data as List)
        .map((e) => DisposalRequestItemModel.fromJson(e))
        .where((i) => !destsIds.contains(i.forfeitedPackageId))
        .toList();
    // De-duplicate by disposal_request_items.id so multi-item packages each
    // appear as their own row in the picker.
    final seen = <String>{};
    return items.where((i) => seen.add(i.id)).toList();
  }

  /// Next destruction serial for a [year], scoped to a [yard] when given so each
  /// yard keeps its own running sequence. A null [yard] falls back to the
  /// global max.
  Future<int> getNextDestructionSerial(int year, {String? yard}) async {
    final data = await AuthService._withNetworkRetry(() {
      var q = supabase.from('destructions').select('serial').eq('year', year);
      if (yard != null && yard.isNotEmpty) q = q.eq('yard', yard);
      return q;
    });
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
    Map<String, String?> packageItems = const {},
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
                // Item-scope the row so Mark Destroyed destroys exactly this
                // item, not the whole package.
                'package_item_id': packageItems[e.key],
                'yard': e.value,
                'destroyed': false,
                'destroyed_at': null,
              })
          .toList();
      // Scope the conflict key to THIS destruction so re-scheduling an
      // undestroyed item INSERTS here and keeps the original sale's row.
      await AuthService._withNetworkRetry(() => supabase
          .from('destruction_items')
          .upsert(rows,
              onConflict:
                  'destruction_id,forfeited_package_id,package_item_id'));
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
    double destroyedPrice = 0.0,
    List<dynamic> appliedTaxes = const [],
  }) async {
    await AuthService._withNetworkRetry(() => supabase.rpc(
          'disposal_mark_destruction_item_destroyed',
          params: {
            'p_item_id': destructionItemId,
            'p_receipt': (receipt == null || receipt.trim().isEmpty)
                ? null
                : receipt.trim(),
            'p_price': destroyedPrice,
            'p_taxes': appliedTaxes,
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
        .select(
            '*, forfeited_packages(*, disposal_request_items!forfeited_package_id(valuation_cost))')
        .inFilter('forfeited_package_id', ids)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle());
    if (data == null) return null;
    return TenderSaleItemModel.fromJson(data);
  }

  /// Like [getTenderSaleItemForPackage] but scoped to a specific package item.
  /// First tries the per-item TSI row (package_item_id column added in
  /// 20260622_tender_sale_item_per_item.sql), then falls back to FP-level lookup,
  /// then to package-level. Falls back to package-level when [packageItemId] is null.
  Future<TenderSaleItemModel?> getTenderSaleItemForPackageItem(
      String packageId, String? packageItemId, {String? receipt}) async {
    if (packageItemId == null) {
      return getTenderSaleItemForPackage(packageId);
    }

    // 1. Direct per-item TSI lookup (new schema: package_item_id on TSI row).
    final fpkgs = await AuthService._withNetworkRetry(() => supabase
        .from('forfeited_packages')
        .select('id')
        .eq('package_id', packageId));
    final fpIds = (fpkgs as List).map((e) => e['id'] as String).toList();
    if (fpIds.isNotEmpty) {
      // When a receipt is given, pin the exact TSI row for THIS partial sale
      // (an item sold across several tenders shares one package_item_id but has
      // a distinct receipt / price per sale). Falls back to the latest row.
      if (receipt != null && receipt.isNotEmpty) {
        final byReceipt = await AuthService._withNetworkRetry(() => supabase
            .from('tender_sale_items')
            .select(
                '*, forfeited_packages(*, disposal_request_items!forfeited_package_id(valuation_cost))')
            .inFilter('forfeited_package_id', fpIds)
            .eq('package_item_id', packageItemId)
            .eq('receipt_number', receipt)
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle());
        if (byReceipt != null) return TenderSaleItemModel.fromJson(byReceipt);
      }
      final perItem = await AuthService._withNetworkRetry(() => supabase
          .from('tender_sale_items')
          .select(
              '*, forfeited_packages(*, disposal_request_items!forfeited_package_id(valuation_cost))')
          .inFilter('forfeited_package_id', fpIds)
          .eq('package_item_id', packageItemId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle());
      if (perItem != null) return TenderSaleItemModel.fromJson(perItem);
    }

    // 2. Try per-item FP row (old schema: item_id on forfeited_packages).
    if (fpIds.isNotEmpty) {
      final fpkgItem = await AuthService._withNetworkRetry(() => supabase
          .from('forfeited_packages')
          .select('id')
          .eq('package_id', packageId)
          .eq('item_id', packageItemId)
          .maybeSingle());
      if (fpkgItem != null) {
        final fpId = fpkgItem['id'] as String;
        final data = await AuthService._withNetworkRetry(() => supabase
            .from('tender_sale_items')
            .select(
                '*, forfeited_packages(*, disposal_request_items!forfeited_package_id(valuation_cost))')
            .eq('forfeited_package_id', fpId)
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle());
        if (data != null) return TenderSaleItemModel.fromJson(data);
      }
    }

    // 3. Fall back to package-level lookup.
    return getTenderSaleItemForPackage(packageId);
  }

  Future<void> deleteTax(String id) async {
    await AuthService._withNetworkRetry(
        () => supabase.from('disposal_taxes').delete().eq('id', id));
  }

  /// Bulk delivery-status map keyed by "packageId|packageItemId" (or
  /// "packageId|" when package_item_id is null). Matches the saleItemKey used
  /// by _SoldRow so the Delivered/Pending filter works per-item when a package
  /// has multiple sold items priced and delivered independently.
  Future<Map<String, bool>> getDeliveryStatusByPackageId() async {
    final data = await AuthService._withNetworkRetry(() => supabase
        .from('tender_sale_items')
        .select(
            'is_delivered, created_at, package_item_id, receipt_number, forfeited_packages(package_id)')
        .order('created_at', ascending: true));
    final out = <String, bool>{};
    for (final e in (data as List)) {
      final fp = e['forfeited_packages'] as Map<String, dynamic>?;
      final pkgId = fp?['package_id']?.toString();
      if (pkgId == null) continue;
      final itemId = e['package_item_id']?.toString() ?? '';
      final receipt = e['receipt_number']?.toString() ?? '';
      final delivered = (e['is_delivered'] as bool?) ?? false;
      // Package-level + per-item keys (latest wins) for legacy callers.
      out['$pkgId|$itemId'] = delivered;
      out[pkgId] = delivered;
      // Receipt-pinned key so a single item sold across several partial tenders
      // exposes each sale's own delivery state (matches the table/cell keys).
      if (receipt.isNotEmpty) out['$pkgId|$itemId|$receipt'] = delivered;
    }
    return out;
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

    final packageRows = (data as List)
        .map((e) => ForfeitedPackageModel.fromJson(e))
        .where((f) => !_isFullyFinalised(f.packageDetails))
        .toList();

    // Expand each forfeited record into one row per package item so the Appeal
    // Directorate sees every item separately (same SR can appear N times).
    // A package-level forfeited_packages row (item_id == null) does NOT mean
    // every item was forfeited — items are disposed individually, so only the
    // items with genuine forfeit evidence (isItemForfeited) belong on appeal.
    // This keeps the Appeal Directorate list in lock-step with the yard's
    // Forfeited table (both use PackageModel.isItemForfeited).
    final expanded = <ForfeitedPackageModel>[];
    for (final f in packageRows) {
      final pkg = f.packageDetails;
      final allItems = pkg?.items ?? const [];
      // For a package-level FP, restrict to genuinely-forfeited items; a per-item
      // FP already names its single item so it is kept as-is.
      final items = (f.itemId == null && allItems.length > 1)
          ? allItems.where((i) => pkg!.isItemForfeited(i.id)).toList()
          : allItems;
      if (items.length <= 1) {
        // Single genuinely-forfeited item → emit that one item's row (not the
        // raw multi-item f, which would show the wrong item name/qty).
        if (items.length == 1 && allItems.length > 1) {
          final only = items.first;
          expanded.add(ForfeitedPackageModel(
            id: f.id,
            packageId: f.packageId,
            srNumber: f.srNumber,
            consigneeName: f.consigneeName,
            forfeitedAt: f.forfeitedAt,
            appealDeadline: f.appealDeadline,
            reason: f.reason,
            yard: f.yard,
            source: f.source,
            appealHold: f.appealHold,
            appealHoldNote: f.appealHoldNote,
            appealHeldAt: f.appealHeldAt,
            heldItemIds: f.heldItemIds,
            appealDecision: f.appealDecision,
            appealDecisionNote: f.appealDecisionNote,
            appealDecidedAt: f.appealDecidedAt,
          itemAppealDecisions: f.itemAppealDecisions,
            packageDetails: f.packageDetails,
            itemId: only.id,
            itemName: only.itemName,
          ));
        } else {
          expanded.add(f);
        }
      } else {
        for (final item in items) {
          expanded.add(ForfeitedPackageModel(
            id: f.id,
            packageId: f.packageId,
            srNumber: f.srNumber,
            consigneeName: f.consigneeName,
            forfeitedAt: f.forfeitedAt,
            appealDeadline: f.appealDeadline,
            reason: f.reason,
            yard: f.yard,
            source: f.source,
            appealHold: f.appealHold,
            appealHoldNote: f.appealHoldNote,
            appealHeldAt: f.appealHeldAt,
            heldItemIds: f.heldItemIds,
            appealDecision: f.appealDecision,
            appealDecisionNote: f.appealDecisionNote,
            appealDecidedAt: f.appealDecidedAt,
          itemAppealDecisions: f.itemAppealDecisions,
            packageDetails: f.packageDetails,
            itemId: item.id,
            itemName: item.itemName,
          ));
        }
      }
    }
    return expanded;
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

  /// Place (or lift) an appeal hold on a specific item (or all items if itemId null).
  Future<void> setAppealHold(String forfeitedId, bool hold,
      {String? note, String? itemId}) async {
    await AuthService._withNetworkRetry(() => supabase.rpc('set_appeal_hold',
        params: {
          'p_forfeited_id': forfeitedId,
          'p_hold': hold,
          'p_note': note,
          'p_item_id': itemId,
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

  /// Lift an appeal hold AND record the directorate's decision so the owning
  /// yard knows what to do next: [decision] is one of 'RELEASE', 'SALE',
  /// 'DESTROY', 'RE-EXPORT' or 'OTHER' (custom outcome carried in [note]).
  Future<void> releaseAppealWithDecision(
    String forfeitedId,
    String decision, {
    String? note,
    String? itemId,
  }) async {
    await AuthService._withNetworkRetry(
        () => supabase.rpc('release_appeal_with_decision', params: {
              'p_forfeited_id': forfeitedId,
              'p_decision': decision,
              'p_note': note,
              'p_item_id': itemId,
            }));
    final user = supabase.auth.currentUser;
    if (user != null) {
      await AuditLogService().recordLog(
        userId: user.id,
        action: 'Appeal decision: $decision',
        entityType: 'forfeited_package',
        entityId: forfeitedId,
      );
    }
  }
}

/// Valuation Directorate (DC / SDDC). A yard's disposal request lands here
/// FIRST: the directorate reads every yard's pending requests (cross-yard),
/// enters a cost per package item, then forwards the request to the Central
/// Disposal Directorate. Only after forwarding does Central Disposal see it.
class ValuationService {
  /// Requests still awaiting valuation (across all yards), newest first, with
  /// full package + item detail for the per-item cost form.
  Future<List<DisposalRequestModel>> getValuationRequests() async {
    final data = await AuthService._withNetworkRetry(() => supabase
        .from('disposal_requests')
        // Include warehouse_entries too so the details popup shows the full
        // Item Details + Warehouse Summary (mirrors the Forfeited screen).
        .select(
            '*, profiles!created_by(full_name), valued_profile:profiles!valued_by(full_name), disposal_request_items(*, forfeited_packages(*, packages(*, package_items(*), warehouse_entries(*, warehouses(*)))))')
        .order('created_at', ascending: false));
    // Per-item forwarding: a request stays in the Pending Valuation feed while
    // ANY of its items is not yet forwarded. Only the not-yet-forwarded items
    // are shown (already-forwarded items have moved on to Central Disposal).
    final result = <DisposalRequestModel>[];
    for (final e in (data as List)) {
      final r = DisposalRequestModel.fromJson(e as Map<String, dynamic>);
      final pending = r.items.where((i) => !i.forwarded).toList();
      if (pending.isEmpty) continue;
      result.add(DisposalRequestModel(
        id: r.id,
        yard: r.yard,
        requestDate: r.requestDate,
        status: r.status,
        createdAt: r.createdAt,
        createdByName: r.createdByName,
        valuationStatus: r.valuationStatus,
        items: pending,
      ));
    }
    return result;
  }

  /// Save per-item costs (map of disposal_request_items.id → cost). When
  /// [forward] is true the request is released to the Central Disposal
  /// Directorate (server requires every item to have a cost first).
  Future<void> setValuationCosts(
    String requestId,
    Map<String, double> costs, {
    bool forward = false,
  }) async {
    await AuthService._withNetworkRetry(() => supabase.rpc(
          'valuation_set_costs',
          params: {
            'p_request_id': requestId,
            'p_costs': costs.map((k, v) => MapEntry(k, v)),
            'p_forward': forward,
          },
        ));
    final user = supabase.auth.currentUser;
    if (user != null) {
      await AuditLogService().recordLog(
        userId: user.id,
        action: forward
            ? 'Forwarded valued disposal request to Central Disposal'
            : 'Saved valuation costs',
        entityType: 'disposal_request',
        entityId: requestId,
      );
    }
  }

  // ── Per-item valuation & forwarding ───────────────────────────────────────

  /// Set ONE disposal-request item's valuation cost (does not forward it).
  Future<void> setValuationItemCost(String itemId, double cost) async {
    await AuthService._withNetworkRetry(() => supabase.rpc(
          'valuation_set_item_cost',
          params: {'p_item_id': itemId, 'p_cost': cost},
        ));
  }

  /// Forward ONE valued item to Central Disposal (server requires its cost set).
  Future<void> forwardValuationItem(String itemId) async {
    await AuthService._withNetworkRetry(() => supabase.rpc(
          'valuation_forward_item',
          params: {'p_item_id': itemId},
        ));
    final user = supabase.auth.currentUser;
    if (user != null) {
      await AuditLogService().recordLog(
        userId: user.id,
        action: 'Forwarded valued item to Central Disposal',
        entityType: 'disposal_request_item',
        entityId: itemId,
      );
    }
  }

  /// Forward EVERY item of a request (all must be valued first).
  Future<void> forwardAllValuationItems(String requestId) async {
    await AuthService._withNetworkRetry(() => supabase.rpc(
          'valuation_forward_all',
          params: {'p_request_id': requestId},
        ));
    final user = supabase.auth.currentUser;
    if (user != null) {
      await AuditLogService().recordLog(
        userId: user.id,
        action: 'Forwarded all valued items to Central Disposal',
        entityType: 'disposal_request',
        entityId: requestId,
      );
    }
  }
}
