import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart' show debugPrint;
import '../core/app_log.dart';
import '../core/db/connection_health.dart';
import '../core/parse_isolate.dart';
import '../core/db_client.dart';
import '../core/app_session.dart';
import '../core/session_reset.dart';
import '../core/security_policy.dart';
import '../core/yards.dart';
import '../core/directorates.dart';
import '../models/models.dart';
import 'otp_service.dart';

bool _isForfeitStatus(String? status) {
  if (status == null) return false;
  final normalized = status.trim().toLowerCase();
  return normalized == 'forfiet' ||
      normalized == 'forfeit' ||
      normalized == 'forfeited';
}

String _normalizeLoginIdentifier(String identifier) => identifier.trim();

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
      AppLog.warn('Google sign-in failed', error: e, tag: 'auth');
      rethrow;
    }
  }

  Future<void> updatePassword(String newPassword) async {
    await supabase.auth.updateUser(
      UserAttributes(password: newPassword),
    );
  }

  Future<ProfileModel?> verifyUserSession() async {
    final user = supabase.auth.currentUser;
    if (user == null) return null;

    // Check profile and role. Retry transient failures — right after a fresh
    // login the JWT can still be propagating, so the first profile query may
    // momentarily return nothing/error; retrying avoids a spurious sign-out that
    // bounced the user back to the portal on the first Sign In click.
    final profileData = await _withNetworkRetry(
      () => supabase.from('profiles').select().eq('id', user.id).maybeSingle(),
    );

    if (profileData == null) {
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
    AppSession.setDirectorate(profile.directorate);
    AppSession.applyYardFilterToRealtime(profile.role);
    return profile;
  }

  /// Retries [action] a few times on transient network failures
  /// (socket timeouts, dropped Wi-Fi, retryable fetch errors). Real auth
  /// errors (bad credentials, etc.) are NOT retried.
  static Future<T> _withNetworkRetry<T>(Future<T> Function() action,
      {int retries = 2}) async {
    for (int attempt = 0;; attempt++) {
      try {
        final result = await action();
        // ⚠️ Reported HERE, not at the call sites. This is the one place that
        // knows a query actually reached the server, and 228 callers go
        // through it — the banner cannot be kept honest by asking each of
        // them to remember.
        ConnectionHealth.reportSuccess();
        return result;
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
        if (!transient || attempt >= retries) {
          // ⚠️ Only a TRANSPORT failure raises the banner. A permission
          // denial or a constraint violation is the database answering,
          // which means the link is fine — blaming the network there would
          // send an officer to check their router over a bug in the app.
          if (transient) ConnectionHealth.reportOffline(ConnectionHealth.describe(e));
          rethrow;
        }
        await Future.delayed(Duration(milliseconds: 700 * (attempt + 1)));
      }
    }
  }

  Future<void> _checkLoginLockout(String email) async {
    final trimmed = email.trim();
    if (trimmed.isEmpty) return;

    final rows = await supabase
        .from('auth.users')
        .select()
        .eq('email', trimmed)
        .limit(1);
    final row = rows.isEmpty ? null : (rows.first as Map<String, dynamic>);
    final lockedUntil = row == null || row['locked_until'] == null
        ? null
        : DateTime.tryParse(row['locked_until'].toString());

    if (LoginSecurityPolicy.isLockedOut(
      lockedUntil: lockedUntil,
      now: DateTime.now(),
    )) {
      throw Exception('login_locked');
    }
  }

  Future<void> _recordFailedLogin(String email) async {
    final trimmed = email.trim();
    if (trimmed.isEmpty) return;

    try {
      await supabase.rpc('auth.record_failed_login', params: {'p_email': trimmed});
    } catch (_) {
      // Best-effort only: the login still fails, and the DB is the source of truth.
    }
  }

  Future<void> _clearFailedLogin(String email) async {
    final trimmed = email.trim();
    if (trimmed.isEmpty) return;

    try {
      await supabase.rpc('auth.clear_failed_login', params: {'p_email': trimmed});
    } catch (_) {
      // A failed reset should never block a valid login.
    }
  }

  Future<ProfileModel?> signIn(String email, String password) async {
    try {
      final resolvedEmail = email.trim();
      AppLog.debug('signIn attempting for: "$resolvedEmail"', tag: 'auth');
      await _checkLoginLockout(resolvedEmail);

      final response = await _withNetworkRetry(
        () => supabase.auth.signInWithPassword(
          email: resolvedEmail,
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
      AppSession.setDirectorate(profile.directorate);
      AppSession.applyYardFilterToRealtime(profile.role);

      try {
        await supabase.from('profiles').update({
          'is_online': true,
          'last_seen_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', profile.id);
      } catch (e) {
        AppLog.warn('sign-in status update failed', error: e, tag: 'auth');
      }

      await _clearFailedLogin(resolvedEmail);
      await AuditLogService().recordLog(
        userId: profile.id,
        action: 'Signed In',
        entityType: 'auth',
        entityId: profile.id,
      );

      return profile;
    } on AuthApiException catch (e) {
      AppLog.debug(
          'signIn AuthApiException code=${e.code} status=${e.statusCode} '
          'msg=${e.message}',
          tag: 'auth');
      final msg = e.message.toLowerCase();
      if (e.code == 'email_not_confirmed' || msg.contains('not confirmed')) {
        throw Exception('email_not_confirmed');
      }
      if (e.code == 'invalid_credentials' ||
          msg.contains('invalid login credentials')) {
        await _recordFailedLogin(email);
        throw Exception('invalid_credentials');
      }
      rethrow;
    } catch (e) {
      AppLog.warn('sign-in failed unexpectedly', error: e, tag: 'auth');
      if (e.toString().contains('login_locked')) {
        await AuditLogService().recordLog(
          userId: null,
          action: 'Blocked login after lockout',
          entityType: 'auth',
          entityId: 'login_lockout',
          details: {'email': email.trim()},
        );
      }
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

  /// Step 1 of a forgotten-password reset: email a one-time code.
  ///
  /// Returns the address the code went to, or null when [identifier] matches
  /// no active account. The CALLER must not report which -- saying "no such
  /// account" would let anyone test which usernames and addresses are real, so
  /// the screens say "if that account exists, a code has been sent" either way.
  Future<String?> startPasswordReset(String identifier) async {
    final id = _normalizeLoginIdentifier(identifier);
    if (id.isEmpty) return null;
    final resolved = await _withNetworkRetry(
      () => supabase
          .rpc('reset_email_for_identifier', params: {'p_identifier': id}),
    );
    final email = resolved is String ? resolved.trim() : '';
    if (email.isEmpty) return null;
    await GmailOtpService.instance
        .sendCode(email, purpose: OtpPurpose.passwordReset);
    return email;
  }

  /// Step 2: check the code, then set the new password.
  ///
  /// Throws whatever [GmailOtpService.verifyCode] throws for a wrong or
  /// expired code, so the screens can report those apart from a failure to
  /// save. The code is verified against the address the ACCOUNT is registered
  /// to, never one the caller supplied.
  Future<void> finishPasswordReset({
    required String identifier,
    required String email,
    required String otp,
    required String newPassword,
  }) async {
    final normalizedIdentifier = _normalizeLoginIdentifier(identifier);
    // ⚠️ Check the code WITHOUT spending it. The password can still be
    // refused after this line -- too short, or one used before -- and
    // consuming the code first meant a rejected password also destroyed the
    // code. The next press then reported "No verification code was sent",
    // which sent the officer back to re-enter a code that no longer existed,
    // complaining about the wrong thing entirely.
    GmailOtpService.instance.verifyCode(email.trim(), otp.trim(),
        consume: false);
    await _withNetworkRetry(
      () => supabase.rpc('reset_password_for_identifier', params: {
        'p_identifier': normalizedIdentifier,
        'p_password': newPassword,
      }),
    );
    // Spent only now the reset has actually happened.
    GmailOtpService.instance.consumeCode(email.trim());
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
  ///
  /// [requireRole] rejects an account that belongs to a DIFFERENT portal
  /// BEFORE any code is sent. Without it the wrong-portal check only ran after
  /// verification, so a Valuation officer typing into the Disposal page still
  /// got an email, still reached the OTP screen, and was only turned away
  /// after spending the code — which then made a second tap fail differently.
  Future<String> startOtpLogin(String identifier, String password,
      {String? requireRole}) async {
    final id = _normalizeLoginIdentifier(identifier);
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
    final res = await _withNetworkRetry(() =>
        supabase.auth.signInWithPassword(email: email, password: password));
    // Check the portal BEFORE spending a code. Read the role while the
    // session is still alive — RLS needs it — then sign out either way.
    String? role;
    bool? isActive;
    if (requireRole != null) {
      final uid = res.user?.id ?? supabase.auth.currentUser?.id;
      if (uid != null) {
        try {
          final row = await supabase
              .from('profiles')
              .select('role, is_active')
              .eq('id', uid)
              .single();
          role = row['role'] as String?;
          isActive = row['is_active'] as bool?;
        } catch (_) {
          // Unreadable profile: fall through and let the post-OTP check
          // decide, rather than locking someone out on a transient error.
        }
      }
    }
    await supabase.auth.signOut();
    // This check used to happen only in finishOtpLogin.  An inactive account
    // therefore received a code, then the final check called AuthService's
    // signOut(), which rebuilds the ProviderScope and dumps the login screen
    // at the home page before it can show its error.  Reject it before the
    // code is issued, while this is still an ordinary, disposable auth probe.
    if (isActive == false) {
      throw Exception('account_deactivated');
    }
    if (requireRole != null && role != null && role != requireRole) {
      throw Exception('wrong_portal');
    }
    // Issue our own 6-digit code and e-mail it via Gmail (not Supabase).
    await GmailOtpService.instance.sendCode(email,
        purpose: OtpPurpose.signIn);
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
      // An OTP attempt has not reached a dashboard or filled any data
      // providers.  Do not use AuthService.signOut() here: its cache reset
      // replaces the router and loses the on-screen deactivation message.
      // The portal can now keep the user here and explain the refusal.
      AppSession.clear();
      await supabase.auth.signOut();
      throw Exception('account_deactivated');
    }
    if (profile.isExpired) {
      await signOut();
      throw Exception('account_expired');
    }
    AppSession.setYard(profile.yard);
    AppSession.setDirectorate(profile.directorate);
    AppSession.applyYardFilterToRealtime(profile.role);
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
    final id = _normalizeLoginIdentifier(identifier);
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
    AppSession.setDirectorate(profile.directorate);
    AppSession.applyYardFilterToRealtime(profile.role);
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
        AppLog.warn('sign-out status update failed', error: e, tag: 'auth');
      }
    }
    AppSession.clear();
    await supabase.auth.signOut();
    // Drop every cached provider with the session. Without this the rows
    // fetched for the person who just left stay in memory and render for
    // whoever signs in next — the database is scoped correctly, but the
    // screen never re-asks it. See core/session_reset.dart.
    clearCachedSessionData();
  }

  Future<ProfileModel?> getCurrentProfile() async {
    final user = supabase.auth.currentUser;
    if (user == null) return null;
    try {
      final data =
          await supabase.from('profiles').select().eq('id', user.id).single();
      final profile = ProfileModel.fromJson(data);
      AppSession.setYard(profile.yard);
      AppSession.setDirectorate(profile.directorate);
      AppSession.applyYardFilterToRealtime(profile.role);
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
      AppLog.warn('heartbeat update failed', error: e, tag: 'auth');
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
      AppLog.warn('could not set user offline', error: e, tag: 'auth');
    }
  }
}

// ── Package Service ──────────────────────────────────────────

class PackageService {
  /// The next free SR number for a yard, in the current year.
  ///
  /// Shape is `<DIRECTORATE>/<YARD>/SR/<NN>/<YYYY>` (e.g. `CED/GL1/SR/25/2026`)
  /// when the signed-in account has a directorate, and the original
  /// `<YARD>/SR/<NN>/<YYYY>` when it does not — accounts created before
  /// directorates existed keep working unchanged.
  ///
  /// The serial counts PER YARD PER REGISTER PER YEAR, not per directorate. A
  /// yard under two directorates (NNR is CED and PSD) must not hand out
  /// `CED/NNR/SR/07/2026` and `PSD/NNR/SR/07/2026` to two different packages,
  /// so the search deliberately matches both shapes and takes the highest.
  ///
  /// [docType] picks the register (`SR`, `OA` — see [kSrDocTypes]). Each runs
  /// its own serial: the number after `SR/87` is `SR/88`, and an `OA` number
  /// never continues an `SR` one, so the count is scoped to one register.
  Future<String> getNextSrNumber({
    String? yard,
    String? directorate,
    String docType = kDefaultSrDocType,
  }) async {
    final now = DateTime.now();
    final year = now.year;
    final startOfYear = DateTime(year, 1, 1).toIso8601String();
    final prefix =
        yardSrPrefix(yard ?? AppSession.currentYard); // e.g. GL1, RCT...
    final dir = directorate ?? AppSession.currentDirectorate;
    final type = docType.trim().isEmpty
        ? kDefaultSrDocType
        : docType.trim().toUpperCase();

    // `%` also covers the unprefixed shape, since ilike anchors nothing before
    // it — so one query finds both `GL1/SR/…` and `CED/GL1/SR/…`.
    final response = await supabase
        .from('packages')
        .select('sr_number')
        .gte('created_at', startOfYear)
        .ilike('sr_number', '%$prefix/$type/%/$year');

    // Ordering by created_at picked the most RECENTLY CREATED row, not the
    // HIGHEST serial — a back-dated or repaired row could hand out a duplicate.
    // Take the real maximum instead.
    int nextNum = 1;
    for (final row in (response as List? ?? const [])) {
      final sr = row['sr_number'] as String?;
      if (sr == null) continue;
      final parts = stripDirectoratePrefix(sr).split('/');
      // <YARD>/<REGISTER>/<serial>/<year> — reject a yard that merely ends in
      // `prefix`, and a number from the OTHER register, whose serials run
      // independently of this one.
      if (parts.length < 4) continue;
      if (parts[0].toUpperCase() != prefix.toUpperCase()) continue;
      if (parts[1].trim().toUpperCase() != type) continue;
      final n = int.tryParse(parts[2].trim());
      if (n != null && n >= nextNum) nextNum = n + 1;
    }

    return composeSrNumber(
      yardPrefix: prefix,
      serial: nextNum,
      year: year,
      directorateCode: dir,
      docType: type,
    );
  }

  /// Looks a package up by SR number, matching BOTH shapes.
  ///
  /// `GL1/SR/62/2026` and `CED/GL1/SR/62/2026` name the same package: goods
  /// registered before directorates existed carry the short form, and an
  /// officer reading a number off an older label will type it that way. An
  /// exact match on one shape alone would report "not found" for the other.
  /// The packages this yard touched TODAY, most recently first.
  ///
  /// ⚠️ The dashboards fetched EVERY package -- 176 rows at 159ms, each
  /// with its items and warehouse entries -- to keep the twenty touched today.
  ///
  /// "Touched" includes a warehouse entry admitted or returned today, not just
  /// the package row: Release, Re-export and Forfeit write only to
  /// `warehouse_entries`, so a package's own timestamps cannot answer it.
  /// `recent_package_activity` (postgres/51) settles that in SQL.
  Future<List<PackageModel>> getRecentActivity(
      {int limit = 20, String? yard}) async {
    final effectiveYard =
        yard ?? (AppSession.isYardBound ? AppSession.currentYard : null);
    var query = supabase.from('recent_package_activity').select('package_id');
    if (effectiveYard != null && effectiveYard.isNotEmpty) {
      query = query.eq('yard', effectiveYard);
    }
    final idRows = await AuthService._withNetworkRetry(() => query
        .order('touched_at', ascending: false)
        .limit(limit));
    final ids = [
      for (final e in (idRows as List))
        (e as Map<String, dynamic>)['package_id'].toString()
    ];
    if (ids.isEmpty) return const [];

    final byId = await getPackagesByIds(ids);
    // Keep the view's order and respect yard scoping.
    return [
      for (final id in ids)
        if (byId[id] != null &&
            (effectiveYard == null ||
                yardOfSrNumber(byId[id]!.srNumber) == effectiveYard))
          byId[id]!
    ];
  }

  Future<PackageModel?> getPackageBySrNumber(String srNumber) async {
    const select =
        '*, package_items(*), warehouse_entries(*, warehouses(*), returned_profile:profiles!returned_by(full_name, badge_number)), profiles(*)';
    final typed = srNumber.trim();

    final data = await supabase
        .from('packages')
        .select(select)
        .eq('sr_number', typed)
        .maybeSingle();
    if (data != null) return PackageModel.fromJson(data);

    // Fall back to the other shape: strip a prefix the caller typed, or match
    // any directorate's prefix in front of a bare number.
    final bare = stripDirectoratePrefix(typed);
    if (bare != typed) {
      final alt = await supabase
          .from('packages')
          .select(select)
          .eq('sr_number', bare)
          .maybeSingle();
      if (alt != null) return PackageModel.fromJson(alt);
      return null;
    }

    // `%` before the bare number matches "<ANY-DIRECTORATE>/<bare>". Underscores
    // and percent signs are not legal in an SR number, so no escaping needed.
    final rows = await supabase
        .from('packages')
        .select(select)
        .ilike('sr_number', '%/$bare')
        .limit(2);
    final list = (rows as List? ?? const []);
    // Exactly one match is a confident answer; two would mean two directorates
    // minted the same serial for one yard, which getNextSrNumber prevents.
    if (list.length == 1) return PackageModel.fromJson(list.first);
    return null;
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

  /// The full packages behind a page of rows, keyed by id.
  ///
  /// ⚠️ A page's worth, never the table. The disposition pages need the whole
  /// package for the details popup and for the per-sale cells, but only for
  /// the twenty rows actually on screen -- which is the entire point of paging
  /// in SQL. An empty list asks for nothing rather than fetching everything.
  Future<Map<String, PackageModel>> getPackagesByIds(List<String> ids) async {
    if (ids.isEmpty) return const {};
    final data = await AuthService._withNetworkRetry(() => supabase
        .from('packages')
        .select(
            '*, package_items(*), warehouse_entries(*, warehouses(*), returned_profile:profiles!returned_by(full_name, badge_number)), profiles(*)')
        .inFilter('id', ids.toSet().toList()));
    final out = <String, PackageModel>{};
    for (final e in (data as List)) {
      final m = PackageModel.fromJson(e as Map<String, dynamic>);
      out[m.id] = m;
    }
    return out;
  }

  /// The packages the FINANCIAL ledger needs, and only what it needs.
  ///
  /// ⚠️ [getAllPackages] returns every package with three embeds --
  /// package_items, warehouse_entries with their warehouse AND the returning
  /// officer's profile, plus the inspecting officer's profile. Measured against
  /// the live database that is ~35ms in Postgres and 130-210ms by the time the
  /// driver has decoded it, because the embeds alone are 419 kB of JSON.
  ///
  /// The ledger reads NONE of that. `buildSrFinancials` wants item quantities
  /// and statuses, and the warehouse entries the storage charge is billed
  /// against -- no warehouse names, no officer names. So this asks for those
  /// and nothing else.
  ///
  /// The rows still come back as [PackageModel]; the omitted fields land as
  /// their empty defaults, which no financial calculation touches.
  Future<List<PackageModel>> getPackagesForLedger() async {
    // ⚠️ The COLUMNS the roll-up reads, not `*`.
    //
    // `package_items(*)` and `warehouse_entries(*)` bring 19 and 18 columns;
    // buildSrFinancials and calculatePackageCharge between them read six and
    // three. Measured: 420 kB of embedded JSON becomes 117 kB, and the driver
    // spends its time decoding what nothing looks at -- ~100ms of the page's
    // wait was JSON parse, not Postgres, which answers this in 15ms.
    //
    // The list is exactly what the charge calculation and the roll-up touch:
    //   package -- sr_number, yard, status, created_at, consignee_name and
    //              destroying_deposit, the six the row itself shows
    //   items   -- id (keying the per-item split), quantity (the share),
    //              status (a seized or disposed item is not charged),
    //              item_name (the goods name on the row)
    //   entries -- package_item_id (which item the entry bills), item_count,
    //              admitted_at / returned_at / is_returned (the storage days)
    //
    // Two kinds of column had to stay that the calculation never reads:
    // package_id, warehouse_id and hold_reason, which fromJson casts non-null
    // and which throw "type 'Null' is not a subtype of type 'String'" without
    // them. daily_rate is NOT among them -- the rate comes from the historical
    // rates map, and the stored column is dead weight.
    //
    // Adding a field to that calculation means adding it here; a test asserts
    // the two lists agree.
    final data = await AuthService._withNetworkRetry(() => supabase
        .from('packages')
        .select(
            'id, sr_number, yard, status, created_at, consignee_name, '
            // The destroying deposit is a FIGURE on the ledger row, not an
            // embed. Dropping it does not throw -- it is nullable -- it
            // silently reports every deposit as LKR 0.
            'destroying_deposit, '
            'package_items(id, package_id, item_name, quantity, status), '
            'warehouse_entries(id, package_id, warehouse_id, package_item_id, '
            'item_count, admitted_at, returned_at, is_returned, hold_reason)')
        .order('created_at', ascending: false));
    // ⚠️ Parsed OFF the UI thread. This built 176 PackageModels — each with
    // its items and warehouse entries — synchronously, and a measured frame
    // showed the cost exactly: 1546ms total, of which build was 15ms and
    // raster 5ms. The other ~1.5s was this parse holding the UI thread, and
    // because Flutter only delivers a click BETWEEN frames, the officer's tap
    // on Details was not received at all until it finished. That is the
    // "first click on this page does nothing for two seconds" — the popup
    // itself was never slow (tap to painted: 15-20ms, every time).
    //
    // parsePackages already existed for precisely this and falls back to a
    // direct parse under kIsolateParseThreshold, so a small result pays
    // nothing for the isolate.
    return parsePackages(data as List);
  }

  Future<List<PackageModel>> getAllPackages(
      {String? status, String? search, DateTime? since, String? yard}) async {
    final effectiveYard =
        yard ?? (AppSession.isYardBound ? AppSession.currentYard : null);
    var query = supabase.from('packages').select(
        '*, package_items(*), warehouse_entries(*, warehouses(*), returned_profile:profiles!returned_by(full_name, badge_number)), profiles(*)');
    if (status != null && status != 'all' && status != 'returned') {
      query = query.eq('status', status);
    }
    // Explicit yard filter (or default to current yard for yard-bound staff).
    if (effectiveYard != null && effectiveYard.isNotEmpty) {
      query = query.eq('yard', effectiveYard);
    }
    if (since != null) query = query.gte('created_at', since.toIso8601String());
    if (search != null && search.isNotEmpty) {
      query =
          query.or('sr_number.ilike.%$search%,consignee_name.ilike.%$search%');
    }
    final data = await query.order('created_at', ascending: false);
    // ⚠️ Parsed OFF the UI thread once the list is large enough to matter.
    //
    // This is the app's heaviest parse: every package also parses its items
    // and its warehouse entries, and the Reports screen calls this 21 times
    // across its tabs with no pagination at all. Doing that inline froze the
    // window for the duration — Dart runs the UI and this on the same thread.
    //
    // parsePackages() keeps small lists inline, where an isolate would cost
    // more than it saves; see kIsolateParseThreshold.
    return parsePackages(data as List);
  }

  /// Server-side paged fetch for the Package History page so it opens fast even
  /// with very large tables (only [limit] rows leave the DB per call). Filters
  /// are applied server-side. Returns the page rows + the total matching count
  /// The years Goods History actually holds, newest first.
  ///
  /// ⚠️ Goods History is SERVER-paginated -- only one page of rows ever
  /// reaches the app -- so it cannot derive its year list from loaded data the
  /// way every other page does with `srYears()`. It used a hard-coded
  /// "this year back six years" loop instead, which offered years with nothing
  /// in them (2020-2023) and never offered NEXT year, so the one dropdown in
  /// the app behaved differently from all the others.
  ///
  /// This asks the database instead: the distinct trailing '/YYYY' of every SR
  /// number. [srYears] then adds the current and next year, exactly as it does
  /// elsewhere.
  Future<List<String>> getPackageYears({String? yard}) async {
    final effectiveYard =
        yard ?? (AppSession.isYardBound ? AppSession.currentYard : null);
    var q = supabase.from('packages').select('sr_number');
    if (effectiveYard != null && effectiveYard.isNotEmpty) {
      q = q.eq('yard', effectiveYard);
    }
    final data = await AuthService._withNetworkRetry(() => q);
    return [
      for (final row in (data as List))
        (row as Map<String, dynamic>)['sr_number']?.toString() ?? '',
    ];
  }

  /// One page of Perishable Goods, filtered and paged in SQL.
  ///
  /// ⚠️ `perishableRowsProvider` awaited every package in the yard and walked
  /// it looking for the 47 items registered as perishable. The
  /// `perishable_rows` view (postgres/24) answers both membership rules --
  /// nature is perishable, and it has not been sent unless a decision came
  /// back -- so only a page's worth ever leaves the database.
  Future<
      ({
        List<String> packageIds,
        List<String> itemIds,
        // ⚠️ The item ids that SOLD at tender, with what they fetched.
        //
        // A perishable that sells never reaches the DG -- selling IS its
        // final outcome -- so the page cannot read the outcome from
        // unsold_proposals alone. Without this, CED/GL1/SR/30/2026 sold for
        // Rs 5,533,000 and still read "Awaiting Top Management".
        Map<String, double> soldPriceByItem,
        Map<String, bool> sentByItem,
        Map<String, bool> markedUnsoldByItem,
        int total
      })> getPerishableRowsPaged({
    required int offset,
    required int limit,
    String? search,
    String? yardSrPrefix,
    DateTime? dateStart,
    DateTime? dateEnd,
    String? year,
    String? activity,

    /// The page's Final Outcome filter: one of kUnsoldProposals,
    /// kOutcomeAwaiting, kOutcomeSold, or null for all.
    ///
    /// ⚠️ Sold is one of the choices HERE and nowhere else. A perishable that
    /// sells at tender ends there and never reaches the DG, so on this page a
    /// sale is a final outcome -- but it is not a proposal and must never be
    /// stored as one.
    String? outcome,
  }) async {
    // ⚠️ ONE closure for the rows and the count.
    PgQuery narrow(PgQuery q) {
      final s = search?.trim() ?? '';
      if (s.isNotEmpty) {
        q = q.or('sr_number.ilike.%$s%,consignee_name.ilike.%$s%,'
            'item_name.ilike.%$s%');
      }
      if (year != null && year.isNotEmpty) {
        q = q.ilike('sr_number', '%/$year');
      }
      // ⚠️ Matched on the SR NUMBER's own yard segment, like every other
      // cross-yard page -- the package's `yard` column can be the filing
      // directorate rather than the yard actually holding the goods.
      if (yardSrPrefix != null && yardSrPrefix.isNotEmpty) {
        q = q.ilike('sr_number', '%/$yardSrPrefix/%');
      }
      if (activity != null && activity.isNotEmpty && activity != 'all') {
        q = q.eq('reasons', activity);
      }
      if (dateStart != null) {
        final from =
            DateTime(dateStart.year, dateStart.month, dateStart.day);
        q = q.gte('effective_date', from.toIso8601String());
      }
      if (dateEnd != null) {
        final to =
            DateTime(dateEnd.year, dateEnd.month, dateEnd.day, 23, 59, 59);
        q = q.lte('effective_date', to.toIso8601String());
      }
      // ⚠️ Three kinds of answer, and they are not interchangeable: a Top
      // Management proposal, a sale at tender, or genuinely awaiting DG decision.
      if (outcome == kOutcomeSold) {
        q = q.eq('sold', true);
      } else if (outcome == kOutcomeAwaiting) {
        // Genuinely awaiting DG decision: marked unsold at tender, not sold, no proposal yet
        q = q.eq('marked_unsold', true).isNull('proposal').eq('sold', false);
      } else if (outcome != null && outcome.isNotEmpty) {
        q = q.eq('proposal', outcome);
      }
      return q;
    }

    final rows = await AuthService._withNetworkRetry(() => narrow(supabase
            .from('perishable_rows')
            .select('package_id, item_id, sold, sold_price, sent, marked_unsold'))
        .order('effective_date', ascending: false)
        .range(offset, offset + limit - 1));
    final total = await AuthService._withNetworkRetry(
        () => narrow(supabase.from('perishable_rows')).count());

    return (
      packageIds: [
        for (final e in (rows as List))
          (e as Map<String, dynamic>)['package_id'].toString()
      ],
      itemIds: [
        for (final e in (rows as List))
          (e as Map<String, dynamic>)['item_id'].toString()
      ],
      soldPriceByItem: {
        for (final e in (rows as List))
          if ((e as Map<String, dynamic>)['sold'] == true)
            e['item_id'].toString(): parseDbNum(e['sold_price']) ?? 0,
      },
      sentByItem: {
        for (final e in (rows as List))
          (e as Map<String, dynamic>)['item_id'].toString():
              ((e['sent'] as bool?) ?? false),
      },
      markedUnsoldByItem: {
        for (final e in (rows as List))
          (e as Map<String, dynamic>)['item_id'].toString():
              ((e['marked_unsold'] as bool?) ?? false),
      },
      total: total as int,
    );
  }

  /// One page of a HELD GOODS table (Detained / Abandoned / Other).
  ///
  /// ⚠️ These three pages had NO pager at all -- they rendered the whole yard.
  /// Every row-selection rule now lives in the `held_goods_rows` view
  /// (postgres/25), which is what lets a page be asked for by number.
  ///
  /// [kind] is the page: 'DETAINED', 'ABANDONED', 'OTHER'.
  Future<({List<String> packageIds, List<String> itemIds,
           List<String> rowKeys, int total})> getHeldGoodsPaged({
    required String kind,
    required int offset,
    required int limit,
    String? search,
    String? yardSrPrefix,
    DateTime? dateStart,
    DateTime? dateEnd,
    String? year,
    String? activity,

    /// Items already in a disposal request. The pages hide them; the view
    /// keeps them so the flag can be filtered on rather than the row dropped.
    bool includeSent = false,
  }) async {
    final effectiveYard =
        AppSession.isYardBound ? AppSession.currentYard : null;
    PgQuery narrow(PgQuery q) {
      q = q.eq('kind', kind);
      if (effectiveYard != null && effectiveYard.isNotEmpty) {
        q = q.eq('yard', effectiveYard);
      }
      if (!includeSent) q = q.eq('sent', false);
      final s = search?.trim() ?? '';
      if (s.isNotEmpty) {
        q = q.or('sr_number.ilike.%$s%,consignee_name.ilike.%$s%,'
            'item_name.ilike.%$s%');
      }
      if (year != null && year.isNotEmpty) {
        q = q.ilike('sr_number', '%/$year');
      }
      // The SR number's own yard segment, as every cross-yard page matches.
      if (yardSrPrefix != null && yardSrPrefix.isNotEmpty) {
        q = q.ilike('sr_number', '%/$yardSrPrefix/%');
      }
      if (activity != null && activity.isNotEmpty && activity != 'all') {
        q = q.eq('reason', activity);
      }
      if (dateStart != null) {
        final from = DateTime(dateStart.year, dateStart.month, dateStart.day);
        q = q.gte('held_at', from.toIso8601String());
      }
      if (dateEnd != null) {
        final to =
            DateTime(dateEnd.year, dateEnd.month, dateEnd.day, 23, 59, 59);
        q = q.lte('held_at', to.toIso8601String());
      }
      return q;
    }

    final rows = await AuthService._withNetworkRetry(() => narrow(supabase
            .from('held_goods_rows')
            .select('row_key, package_id, item_id'))
        .order('held_at', ascending: false)
        .range(offset, offset + limit - 1));
    final total = await AuthService._withNetworkRetry(
        () => narrow(supabase.from('held_goods_rows')).count());

    final list = (rows as List).cast<Map<String, dynamic>>();
    return (
      packageIds: [for (final e in list) e['package_id'].toString()],
      itemIds: [for (final e in list) e['item_id'].toString()],
      rowKeys: [for (final e in list) e['row_key'].toString()],
      total: total as int,
    );
  }

  /// The header counts a Held Goods page shows: total, and how many are
  /// actionable rather than waiting on an appeal.
  ///
  /// ⚠️ Counted in SQL. The pages derived these by walking the whole list,
  /// which is exactly the cost the paging removed -- computing them from one
  /// page would have made the header disagree with itself.
  Future<({int total, int inAppeal, int actionable})> getHeldGoodsCounts(
      String kind) async {
    var query = supabase
        .from('held_goods_rows')
        .select('appeal_deadline, appeal_hold, appeal_decision')
        .eq('kind', kind)
        .eq('sent', false);
    if (AppSession.isYardBound && AppSession.currentYard.isNotEmpty) {
      query = query.eq('yard', AppSession.currentYard);
    }
    final rows = await AuthService._withNetworkRetry(() => query);
    var inAppeal = 0;
    final now = DateTime.now();
    final list = (rows as List).cast<Map<String, dynamic>>();
    for (final r in list) {
      final hold = r['appeal_hold'] as bool? ?? false;
      final decided = (r['appeal_decision']?.toString() ?? '').trim().isNotEmpty;
      final deadline = parseDbDate(r['appeal_deadline']);
      // A HOLD always blocks; a decision releases early; otherwise the window.
      if (hold || (!decided && deadline != null && now.isBefore(deadline))) {
        inAppeal++;
      }
    }
    return (
      total: list.length,
      inAppeal: inAppeal,
      actionable: list.length - inAppeal,
    );
  }

  /// The SR numbers on a Held Goods page, for its year filter.
  Future<List<String>> getHeldGoodsYears(String kind) async {
    var query =
        supabase.from('held_goods_rows').select('sr_number').eq('kind', kind);
    if (AppSession.isYardBound && AppSession.currentYard.isNotEmpty) {
      query = query.eq('yard', AppSession.currentYard);
    }
    final data = await AuthService._withNetworkRetry(() => query);
    return [
      for (final row in (data as List))
        (row as Map<String, dynamic>)['sr_number']?.toString() ?? '',
    ];
  }

  /// One page of the Disposal Expenses tab: the SRs with money to account for.
  ///
  /// ⚠️ Returns PACKAGE IDS, not rows. The table and its detail dialog need
  /// the full `SrFinancials` — the nested goods list, per item — so the caller
  /// builds those for the page. What the view settles is WHICH SRs and in what
  /// order, which is the part that used to cost the whole yard.
  Future<({List<String> packageIds, int total})> getExpenseSrPageIds({
    required int offset,
    required int limit,
    String? search,
    String? yardFilter,
    DateTime? dateStart,
    DateTime? dateEnd,
  }) async {
    PgQuery narrow(PgQuery q) {
      final s = search?.trim() ?? '';
      if (s.isNotEmpty) {
        q = q.or('sr_number.ilike.%$s%,consignee_name.ilike.%$s%');
      }
      if (yardFilter != null && yardFilter.isNotEmpty) {
        // ⚠️ The SR prefix as well as the yard column: a row with no yard of
        // its own must not be silently hidden from a yard it plainly belongs
        // to, which is the fallback the tab already applies.
        q = q.or('yard.eq.$yardFilter,sr_number.ilike.%/$yardFilter/%');
      }
      if (dateStart != null) {
        final from = DateTime(dateStart.year, dateStart.month, dateStart.day);
        q = q.gte('activity_date', from.toIso8601String());
      }
      if (dateEnd != null) {
        final to =
            DateTime(dateEnd.year, dateEnd.month, dateEnd.day, 23, 59, 59);
        q = q.lte('activity_date', to.toIso8601String());
      }
      return q;
    }

    final rows = await AuthService._withNetworkRetry(() =>
        narrow(supabase.from('sr_expense_summary').select('package_id'))
            .order('activity_date', ascending: false)
            .range(offset, offset + limit - 1));
    final total = await AuthService._withNetworkRetry(
        () => narrow(supabase.from('sr_expense_summary')).count());

    return (
      packageIds: [
        for (final e in (rows as List))
          (e as Map<String, dynamic>)['package_id'].toString()
      ],
      total: total as int,
    );
  }

  /// The expense totals across every SR the current filter matches.
  ///
  /// ⚠️ Its own query, and it must be. The totals strip sums EVERY filtered
  /// row, not the page — computing it from twenty rows would report a fraction
  /// of the money and quietly understate what the directorate has spent.
  Future<Map<String, double>> getExpenseTotals({
    String? search,
    String? yardFilter,
    DateTime? dateStart,
    DateTime? dateEnd,
  }) async {
    var q = supabase.from('sr_expense_summary').select(
        'destroying_deposit, destruction_expense, advertising_expense, '
        'labour_expense, transport_expense, auction_expense, refund');
    final s = search?.trim() ?? '';
    if (s.isNotEmpty) {
      q = q.or('sr_number.ilike.%$s%,consignee_name.ilike.%$s%');
    }
    if (yardFilter != null && yardFilter.isNotEmpty) {
      q = q.or('yard.eq.$yardFilter,sr_number.ilike.%/$yardFilter/%');
    }
    if (dateStart != null) {
      final from = DateTime(dateStart.year, dateStart.month, dateStart.day);
      q = q.gte('activity_date', from.toIso8601String());
    }
    if (dateEnd != null) {
      final to = DateTime(dateEnd.year, dateEnd.month, dateEnd.day, 23, 59, 59);
      q = q.lte('activity_date', to.toIso8601String());
    }
    final rows = await AuthService._withNetworkRetry(() => q);
    final out = <String, double>{
      'deposit': 0,
      'destruction': 0,
      'advertising': 0,
      'labour': 0,
      'transport': 0,
      'auction': 0,
      'refund': 0,
    };
    for (final e in (rows as List)) {
      final m = e as Map<String, dynamic>;
      out['deposit'] =
          out['deposit']! + (parseDbNum(m['destroying_deposit']) ?? 0);
      out['destruction'] =
          out['destruction']! + (parseDbNum(m['destruction_expense']) ?? 0);
      out['advertising'] =
          out['advertising']! + (parseDbNum(m['advertising_expense']) ?? 0);
      out['labour'] = out['labour']! + (parseDbNum(m['labour_expense']) ?? 0);
      out['transport'] =
          out['transport']! + (parseDbNum(m['transport_expense']) ?? 0);
      out['auction'] =
          out['auction']! + (parseDbNum(m['auction_expense']) ?? 0);
      out['refund'] = out['refund']! + (parseDbNum(m['refund']) ?? 0);
    }
    return out;
  }

  /// One PAGE of the Financials ledger, from the `sr_financials` view.
  ///
  /// ⚠️ The Financials page used to load the WHOLE ledger and filter it in
  /// Dart: every package with its items and warehouse entries, every tender
  /// sale, every expense row -- decoded on the UI isolate so a header strip
  /// could add up ten numbers. That is what made the page take a second or two
  /// to appear.
  ///
  /// The view computes the same ten figures per SR (postgres/41, whose verify
  /// block asserts them against what the page was showing), so filtering,
  /// ordering, paging and totalling all happen in SQL.
  Future<({List<SrLedgerRow> rows, int total})> getSrFinancialsPaged({
    required int offset,
    required int limit,
    String? search,
    String? yardFilter,
    DateTime? dateStart,
    DateTime? dateEnd,
  }) async {
    final rows = await AuthService._withNetworkRetry(() =>
        _narrowFinancials(
                supabase.from('sr_financials').select(
                    'sr_number, yard, consignee_name, goods_name, quantity, '
                    'package_count, sr_charges, destroying_deposit, '
                    'sale_proceeds, taxes, destruction_expense, '
                    'advertising_expense, labour_expense, transport_expense, '
                    'auction_expense, deposit_spent, refund, activity_date'),
                search: search,
                yardFilter: yardFilter,
                dateStart: dateStart,
                dateEnd: dateEnd)
            .order('activity_date', ascending: false)
            .range(offset, offset + limit - 1));
    final total = await AuthService._withNetworkRetry(() => _narrowFinancials(
          supabase.from('sr_financials'),
          search: search,
          yardFilter: yardFilter,
          dateStart: dateStart,
          dateEnd: dateEnd,
        ).count());

    return (
      rows: [
        for (final e in (rows as List))
          SrLedgerRow.fromJson(e as Map<String, dynamic>)
      ],
      total: total as int,
    );
  }

  /// The ten totals across every SR the filter matches.
  ///
  /// ⚠️ Its own query, over the WHOLE filter rather than the page. Summing
  /// twenty rows would report one page of money as the directorate's total --
  /// the same mistake the Expenses tab had to be corrected for.
  Future<FinancialSummary> getSrFinancialTotals({
    String? search,
    String? yardFilter,
    DateTime? dateStart,
    DateTime? dateEnd,
  }) async {
    final rows = await AuthService._withNetworkRetry(() => _narrowFinancials(
          supabase.from('sr_financials').select(
              'sr_charges, destroying_deposit, sale_proceeds, taxes, '
              'destruction_expense, advertising_expense, labour_expense, '
              'transport_expense, auction_expense, refund'),
          search: search,
          yardFilter: yardFilter,
          dateStart: dateStart,
          dateEnd: dateEnd,
        ));

    double col(String key) => (rows as List).fold<double>(
        0, (a, r) => a + (parseDbNum((r as Map<String, dynamic>)[key]) ?? 0));

    return FinancialSummary(
      srCharges: col('sr_charges'),
      destroyingDeposits: col('destroying_deposit'),
      saleProceeds: col('sale_proceeds'),
      taxes: col('taxes'),
      destructionExpenses: col('destruction_expense'),
      advertisingExpenses: col('advertising_expense'),
      labourExpenses: col('labour_expense'),
      transportExpenses: col('transport_expense'),
      auctionExpenses: col('auction_expense'),
      // ⚠️ Summed as the view computed it, per SR and floored at zero. A
      // refund is the unspent part of ONE SR's deposit, so an SR that
      // overspent refunds nothing rather than a negative -- it cannot be
      // derived from the deposit and spend totals.
      refunds: col('refund'),
    );
  }

  /// The filter the ledger page applies, shared by its rows, its count and its
  /// totals.
  ///
  /// ⚠️ ONE closure for all three. When the rows and the totals narrow
  /// separately they drift, and the strip then reports money the table below
  /// it does not list.
  PgQuery _narrowFinancials(
    PgQuery q, {
    String? search,
    String? yardFilter,
    DateTime? dateStart,
    DateTime? dateEnd,
  }) {
    final s = search?.trim() ?? '';
    if (s.isNotEmpty) {
      q = q.or('sr_number.ilike.%$s%,consignee_name.ilike.%$s%,'
          'goods_name.ilike.%$s%');
    }
    if (yardFilter != null && yardFilter.isNotEmpty) {
      // ⚠️ The SR prefix as well as the yard column: a row with no yard of
      // its own must not be hidden from a yard it plainly belongs to, which is
      // the fallback the page already applied in Dart.
      q = q.or('yard.eq.$yardFilter,sr_number.ilike.%/$yardFilter/%');
    }
    if (dateStart != null) {
      final from = DateTime(dateStart.year, dateStart.month, dateStart.day);
      q = q.gte('activity_date', from.toIso8601String());
    }
    if (dateEnd != null) {
      final to = DateTime(dateEnd.year, dateEnd.month, dateEnd.day, 23, 59, 59);
      q = q.lte('activity_date', to.toIso8601String());
    }
    return q;
  }

  /// What has been spent against each of [srNumbers], keyed by SR number.
  ///
  /// ⚠️ ONE query for a whole page. The Destroyed Goods table used to read
  /// `srFinancialsProvider` from inside each row's cell — the entire yard
  /// ledger (getAllPackages + getTenderSales, rolled up per item and per tax
  /// name) fetched to display one figure, then scanned linearly for the
  /// matching SR. That is the lag on that tab.
  Future<Map<String, double>> getDestructionSpendBySr(
      List<String> srNumbers) async {
    if (srNumbers.isEmpty) return const {};
    final rows = await AuthService._withNetworkRetry(() => supabase
        .from('sr_expense_summary')
        .select('sr_number, deposit_spent')
        .inFilter('sr_number', srNumbers.toSet().toList()));
    return {
      for (final e in (rows as List))
        (e as Map<String, dynamic>)['sr_number'].toString():
            parseDbNum(e['deposit_spent']) ?? 0,
    };
  }

  /// The SR numbers on Perishable Goods, for its year filter.
  Future<List<String>> getPerishableYears() async {
    final data = await AuthService._withNetworkRetry(
        () => supabase.from('perishable_rows').select('sr_number'));
    return [
      for (final row in (data as List))
        (row as Map<String, dynamic>)['sr_number']?.toString() ?? '',
    ];
  }

  /// The SR numbers on one disposition page, for its year filter.
  ///
  /// ⚠️ The page now holds only twenty rows, which is nowhere near enough to
  /// know which years the table covers -- the filter would offer only the
  /// years visible on the current page. This asks for the numbers alone (one
  /// small column, no joins) so `srYears()` builds the same list it always did.
  Future<List<String>> getDispositionYears(String finalTag,
      {String? yard}) async {
    var q = supabase
        .from('disposition_rows')
        .select('sr_number')
        .eq('final_tag', finalTag);
    if (yard != null && yard.isNotEmpty) q = q.eq('yard', yard);
    final data = await AuthService._withNetworkRetry(() => q);
    return [
      for (final row in (data as List))
        (row as Map<String, dynamic>)['sr_number']?.toString() ?? '',
    ];
  }

  /// Whether THIS page has any perishable goods on it at all.
  ///
  /// ⚠️ Asked so the Perishable chip is only offered where it can do
  /// something. A filter that can only ever return an empty table is worse
  /// than no filter: leave it switched on and the page reads "0 Destroyed",
  /// which looks like the yard has destroyed nothing rather than like a
  /// filter matched nothing.
  ///
  /// ⚠️ NOT hardcoded per page. Today only Sold carries perishables, but a
  /// perishable can certainly be destroyed — one is ruled `destroy` right
  /// now and simply has not been carried out — so the question has to be
  /// asked of the DATA, or the chip would vanish exactly when it became
  /// useful. A `count` with `head`, so it costs no rows.
  Future<bool> dispositionHasPerishables(String finalTag,
      {String? yard}) async {
    var q = supabase
        .from('disposition_rows')
        .eq('final_tag', finalTag)
        .eq('is_perishable', true);
    if (yard != null && yard.isNotEmpty) q = q.eq('yard', yard);
    final n = await AuthService._withNetworkRetry(() => q.count());
    return (n as int) > 0;
  }

  /// One page of a disposition table (Sold / Destroyed / Re-exported / Other),
  /// straight out of the `disposition_rows` view.
  ///
  /// ⚠️ Filtering and paging both happen in SQL. The screens used to fetch
  /// EVERY package in the yard, expand each into item rows in Dart, sort the
  /// lot and then `.skip().take()` -- so drawing page 1 cost the whole table,
  /// and the cost grew with the yard rather than with the page.
  ///
  /// [finalTag] is the page: 'SOLD', 'DESTROYED', 'RE-EXPORTED', 'OTHER'.
  Future<DispositionPage> getDispositionRowsPaged({
    required String finalTag,
    required int offset,
    required int limit,
    String? search,
    String? yard,
    DateTime? dateStart,
    DateTime? dateEnd,
    String? year,

    /// The Delivered / Pending sub-filter on Sold and Destroyed. Null means
    /// "All", which is not the same as either.
    bool? delivered,

    /// The Reason dropdown on Released Goods. 'all' and null both mean no
    /// filter -- the screen uses the string, so it is accepted here.
    String? holdReason,

    /// Destroyed Goods' Pending / Destroyed filter. ⚠️ Only that page has a
    /// middle state; null means "All", which is a third answer.
    bool? isDestroyed,

    /// Perishable-only narrowing. Null is "all goods", which is not the
    /// same as false — false would hide every perishable row.
    bool? perishableOnly,
  }) async {
    // ⚠️ ONE closure, applied to the rows query and the count query alike. Two
    // separately-written filters drift, and the symptom is a pager whose total
    // disagrees with the rows under it.
    PgQuery narrow(PgQuery q) {
      q = q.eq('final_tag', finalTag);
      if (yard != null && yard.isNotEmpty) q = q.eq('yard', yard);
      // ⚠️ In SQL, like every other filter here: these pages are
      // server-paged and take their total from the server, so narrowing
      // after the page arrives would leave the pager counting rows it had
      // just removed.
      if (perishableOnly == true) q = q.eq('is_perishable', true);
      final s = search?.trim() ?? '';
      if (s.isNotEmpty) {
        // The receipt number is searched too -- on Released Goods it is
        // often the only thing an officer has to go on.
        q = q.or('sr_number.ilike.%$s%,consignee_name.ilike.%$s%,'
            'item_name.ilike.%$s%,receipt_no.ilike.%$s%');
      }
      if (year != null && year.isNotEmpty) {
        q = q.ilike('sr_number', '%/$year');
      }
      if (dateStart != null) {
        final start = DateTime(dateStart.year, dateStart.month, dateStart.day);
        q = q.gte('happened_at', start.toIso8601String());
      }
      if (dateEnd != null) {
        final end =
            DateTime(dateEnd.year, dateEnd.month, dateEnd.day, 23, 59, 59);
        q = q.lte('happened_at', end.toIso8601String());
      }
      if (delivered != null) q = q.eq('delivered', delivered);
      if (holdReason != null &&
          holdReason.isNotEmpty &&
          holdReason != 'all') {
        q = q.eq('hold_reason', holdReason);
      }
      if (isDestroyed != null) q = q.eq('is_destroyed', isDestroyed);
      return q;
    }

    final rowsData = await AuthService._withNetworkRetry(() =>
        narrow(supabase.from('disposition_rows').select('*'))
            .order('happened_at', ascending: false)
            .range(offset, offset + limit - 1));

    // Count only -- no rows cross the wire for the pager's total.
    final total = await AuthService._withNetworkRetry(
        () => narrow(supabase.from('disposition_rows')).count());

    return DispositionPage(
      rows: (rowsData as List)
          .map((e) => DispositionRow.fromJson(e as Map<String, dynamic>))
          .toList(),
      total: total as int,
    );
  }

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
    final effectiveYard =
        yard ?? (AppSession.isYardBound ? AppSession.currentYard : null);

    // Apply the same filters to either query (rows or count).
    PgQuery applyFilters(PgQuery q) {
      if (effectiveYard != null && effectiveYard.isNotEmpty) {
        q = q.eq('yard', effectiveYard);
      }
      if (search != null && search.trim().isNotEmpty) {
        final s = search.trim();
        q = q.or(
            'sr_number.ilike.%$s%,consignee_name.ilike.%$s%,declarant_name.ilike.%$s%,cusdec_no.ilike.%$s%');
      }
      if (year != null && year.isNotEmpty) {
        q = q.ilike('sr_number', '%/$year');
      }
      if (dateStart != null) {
        final start = DateTime(dateStart.year, dateStart.month, dateStart.day);
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
    final total = await AuthService._withNetworkRetry(
        () => applyFilters(supabase.from('packages')).count());

    final rows = (rowsData as List)
        .map((e) => PackageModel.fromJson(e as Map<String, dynamic>))
        .toList();
    return (rows: rows, total: total as int);
  }

  /// One page of Old Entries: packages carrying a LEGACY SR number.
  ///
  /// ⚠️ Its own method rather than a flag on [getPackagesPaged], because both
  /// the search set and the year rule differ. This page searches the OLD SR
  /// number and the CusDec number, and its year filter matches any of four
  /// places a year can appear -- neither of which the main history page does.
  Future<({List<PackageModel> rows, int total})> getOldEntriesPaged({
    required int offset,
    required int limit,
    String? search,
    DateTime? dateStart,
    DateTime? dateEnd,
    String? year,
    String? yard,
  }) async {
    final effectiveYard =
        yard ?? (AppSession.isYardBound ? AppSession.currentYard : null);

    PgQuery narrow(PgQuery q) {
      // ⚠️ The page IS "packages with a legacy number", so this is not a
      // filter the user can clear -- it is the list's definition.
      q = q.not('old_sr_number', 'is', null);
      q = q.neq('old_sr_number', '');
      if (effectiveYard != null && effectiveYard.isNotEmpty) {
        q = q.eq('yard', effectiveYard);
      }
      final s = search?.trim() ?? '';
      if (s.isNotEmpty) {
        q = q.or('old_sr_number.ilike.%$s%,sr_number.ilike.%$s%,'
            'consignee_name.ilike.%$s%,cusdec_no.ilike.%$s%');
      }
      if (year != null && year.isNotEmpty) {
        // ⚠️ FOUR places a year can appear, matching the screen exactly: the
        // old number, the new one, the entry date, or the CusDec date. A
        // legacy entry filed under one numbering and re-registered under
        // another has to be findable by either year.
        q = q.or('old_sr_number.ilike.%$year%,sr_number.ilike.%$year%,'
            'cusdec_date.ilike.%$year%');
      }
      if (dateStart != null) {
        final start = DateTime(dateStart.year, dateStart.month, dateStart.day);
        q = q.gte('created_at', start.toIso8601String());
      }
      if (dateEnd != null) {
        final end =
            DateTime(dateEnd.year, dateEnd.month, dateEnd.day, 23, 59, 59);
        q = q.lte('created_at', end.toIso8601String());
      }
      return q;
    }

    final rowsData = await AuthService._withNetworkRetry(() => narrow(
            supabase.from('packages').select(
                '*, package_items(*), warehouse_entries(*, warehouses(*), returned_profile:profiles!returned_by(full_name, badge_number)), profiles(*)'))
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1));
    final total = await AuthService._withNetworkRetry(
        () => narrow(supabase.from('packages')).count());

    return (
      rows: (rowsData as List)
          .map((e) => PackageModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      total: total as int,
    );
  }

  /// The years Old Entries can be filtered by — every year appearing in any of
  /// the four places the page looks.
  Future<List<String>> getOldEntryYears({String? yard}) async {
    final effectiveYard =
        yard ?? (AppSession.isYardBound ? AppSession.currentYard : null);
    var query = supabase
        .from('packages')
        .select('old_sr_number, sr_number, entry_date, cusdec_date')
        .not('old_sr_number', 'is', null)
        .neq('old_sr_number', '');
    if (effectiveYard != null && effectiveYard.isNotEmpty) {
      query = query.eq('yard', effectiveYard);
    }
    final data = await AuthService._withNetworkRetry(() => query);
    final years = <String>{};
    final re = RegExp(r'(19|20)\d{2}');
    for (final row in (data as List)) {
      final m = row as Map<String, dynamic>;
      for (final key in ['old_sr_number', 'sr_number', 'cusdec_date']) {
        for (final match in re.allMatches(m[key]?.toString() ?? '')) {
          years.add(match.group(0)!);
        }
      }
      final entry = parseDbDate(m['entry_date']);
      if (entry != null) years.add(entry.year.toString());
    }
    // Newest first, as every other year filter reads.
    final out = years.toList()..sort((a, b) => b.compareTo(a));
    return out;
  }

  Future<PackageModel> createPackage(PackageModel pkg, List<PackageItem> items,
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

  Future<PackageModel> upsertPackage(PackageModel pkg, List<PackageItem> items,
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
          final held = rows.where((e) => e['is_returned'] != true).toList();
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

      if (refreshed == null)
        return PackageModel.fromJson({}); // Fallback or handle null
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
        await supabase
            .from('forfeited_packages')
            .delete()
            .eq('package_id', result.id);
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
          entryDate: parseDbDate(pkgData['entry_date']),
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
      if (s == 'forfeit' ||
          s == 'forfeited' ||
          s == 'forfiet' ||
          s == 'confiscated') {
        forfeit++;
      } else if (s == 'abandoned' || s == 'abandon') {
        abandon++;
      } else if (s == 'destroy' || s == 'destroyed') {
        destroy++;
      } else if (s == 'release' ||
          s == 'released' ||
          s == 'cleared' ||
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
        ? (parseDbNum(latestRate.first['rate']) ?? 0)
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
  /// One PAGE of a warehouse's live contents, chosen in SQL.
  ///
  /// ⚠️ The page used to load a whole facility's entries, filter them here
  /// on six conditions -- one of which needed the PACKAGE ITEM behind each
  /// entry, so it read a getPackageById per row -- and then page the result
  /// with `pageSlice`, which still loads everything and only renders less.
  ///
  /// `warehouse_rows` (postgres/48) carries the membership and every filter
  /// column, checked entry-for-entry against the Dart on all four facilities.
  Future<({List<WarehouseEntryModel> rows, int total})> getWarehouseRowsPaged({
    required String warehouseId,
    required int offset,
    required int limit,

    /// The item-status chips: 'all', 'confiscated', or a status like
    /// 'Forfeit' / 'Detain'.
    String status = 'all',
    /// Appeal state: 'all', 'enabled', 'hold' or 'decided'. Resolved once in
    /// `warehouse_rows` so the screen and this query cannot disagree.
    String appeal = 'all',

    /// The hold reason, or 'all'.
    String reason = 'all',
    String? search,
    DateTime? dateStart,
    DateTime? dateEnd,
    String? year,
  }) async {
    // A physical warehouse may hold goods from more than one yard. Scope the
    // query itself (not merely the rendered list) so GL2 never fetches GL1's
    // entry ids, even if a view policy is changed later.
    final effectiveYard =
        AppSession.isYardBound ? AppSession.currentYard : null;
    PgQuery narrow(PgQuery q) {
      q = q.eq('warehouse_id', warehouseId);
      if (effectiveYard != null && effectiveYard.isNotEmpty) {
        q = q.eq('yard', effectiveYard);
      }

      if (status == 'confiscated') {
        // ⚠️ The PACKAGE is confiscated, not the item. That chip has
        // always read the package-level status, and the two are different
        // questions.
        q = q.eq('is_package_confiscated', true);
      } else if (status.toLowerCase() == 'other') {
        // ⚠️ "Other" is EVERYTHING ELSE, not a literal status value.
        //
        // The three named chips cover Detain, Forfeit and Abandoned; every
        // remaining disposition an SR can carry — "supposed to be
        // destroyed" is 22 rows in this yard alone, and ICT can add more —
        // belongs here. Matching the word "Other" literally returned an
        // empty table while those rows sat in the unfiltered list, so a
        // whole category was unreachable from the page holding it.
        // ⚠️ Three negated matches, not `not.in`. The compat layer binds a
        // filter's value as ONE parameter, so an IN list would arrive as a
        // single string and never match.
        for (final named in const ['Detain', 'Forfeit', 'Abandoned']) {
          q = q.not('item_status', 'ilike', named);
        }
      } else if (status != 'all' && status.isNotEmpty) {
        // ⚠️ Case-insensitive. The SR form has written these both ways
        // over time, and an exact match silently returned half the goods.
        q = q.ilike('item_status', status);
      }

      // ⚠️ In SQL, not in Dart. The pager takes its total from the server,
      // so narrowing the page after it arrives would leave the pager
      // counting rows it had just removed.
      if (appeal != 'all' && appeal.isNotEmpty) {
        q = q.eq('appeal_state', appeal);
      }

      if (reason != 'all' && reason.isNotEmpty) {
        q = q.eq('hold_reason', reason);
      }

      final s = search?.trim() ?? '';
      if (s.isNotEmpty) {
        q = q.or('sr_number.ilike.%$s%,consignee_name.ilike.%$s%,'
            'hold_reason.ilike.%$s%');
      }

      if (dateStart != null) {
        final from = DateTime(dateStart.year, dateStart.month, dateStart.day);
        q = q.gte('admitted_at', from.toIso8601String());
      }
      if (dateEnd != null) {
        final to = DateTime(dateEnd.year, dateEnd.month, dateEnd.day, 23, 59, 59);
        q = q.lte('admitted_at', to.toIso8601String());
      }
      if (year != null && year.isNotEmpty) {
        // ⚠️ EITHER year, not both. An SR filed in one year can be
        // admitted in the next, and an officer looking for either should
        // find it -- the screen has always matched this way.
        q = q.or('sr_year.eq.$year,admitted_year.eq.$year');
      }
      return q;
    }

    final idRows = await AuthService._withNetworkRetry(() =>
        narrow(supabase.from('warehouse_rows').select('entry_id'))
            .order('admitted_at', ascending: false)
            .range(offset, offset + limit - 1));
    final total = await AuthService._withNetworkRetry(
        () => narrow(supabase.from('warehouse_rows')).count());

    final ids = [
      for (final e in (idRows as List))
        (e as Map<String, dynamic>)['entry_id'].toString()
    ];
    if (ids.isEmpty) {
      return (rows: const <WarehouseEntryModel>[], total: total as int);
    }

    // ⚠️ The entries for THIS page, not the facility. The screen used to
    // fetch every live entry with its warehouse, package and both officers'
    // profiles -- 83ms for one facility -- purely so a page of ids could be
    // looked up in it.
    final data = await AuthService._withNetworkRetry(() => supabase
        .from('warehouse_entries')
        .select(
            '*, warehouses(*), packages(*), admitted_profile:profiles!admitted_by(full_name, badge_number), returned_profile:profiles!returned_by(full_name, badge_number)')
        .inFilter('id', ids));
    final byId = {
      for (final e in (data as List))
        (e as Map<String, dynamic>)['id'].toString():
            WarehouseEntryModel.fromJson(e)
    };
    // Keep the view's order -- re-sorting here would disagree with the page
    // boundaries the query used.
    return (
      rows: [for (final id in ids) if (byId[id] != null) byId[id]!],
      total: total as int,
    );
  }

  /// The hold reasons and item statuses a warehouse actually holds.
  ///
  /// ⚠️ From the whole facility, not the page. A dropdown built from twenty
  /// rows offers only what is on screen, and an option that is missing reads
  /// as goods that are not there.
  Future<({List<String> reasons, List<String> statuses, List<String> years})>
      getWarehouseFilterOptions(String warehouseId) async {
    var query = supabase
        .from('warehouse_rows')
        .select('hold_reason, item_status, sr_year, admitted_year')
        .eq('warehouse_id', warehouseId);
    if (AppSession.isYardBound && AppSession.currentYard.isNotEmpty) {
      query = query.eq('yard', AppSession.currentYard);
    }
    final data = await AuthService._withNetworkRetry(() => query);

    final reasons = <String>{};
    final statuses = <String>{};
    final years = <String>{};
    for (final e in (data as List)) {
      final m = e as Map<String, dynamic>;
      final r = (m['hold_reason'] as String?)?.trim();
      if (r != null && r.isNotEmpty) reasons.add(r);
      final st = (m['item_status'] as String?)?.trim();
      if (st != null && st.isNotEmpty) statuses.add(st);
      for (final y in [m['sr_year'], m['admitted_year']]) {
        final v = y?.toString().trim();
        if (v != null && v.isNotEmpty) years.add(v);
      }
    }
    return (
      reasons: reasons.toList()..sort(),
      statuses: statuses.toList()..sort(),
      years: years.toList()..sort((a, b) => b.compareTo(a)),
    );
  }

  /// What one facility holds, counted by item status.
  ///
  /// ⚠️ Counted in SQL. The header read `packageDataProvider(...)` from
  /// inside two nested loops -- once to drop the goods that have left the yard
  /// and once per status chip -- so a facility of 75 entries fired the same
  /// per-package fetch four times over. `warehouse_rows` already excludes the
  /// departed goods and carries the normalised status.
  Future<({int total, int detain, int forfeit, int abandoned})>
      getWarehouseStatusCounts(String warehouseId, {String? yard}) async {
    final effectiveYard =
        yard ?? (AppSession.isYardBound ? AppSession.currentYard : null);
    Future<int> countOf(String? status) async {
      var q = supabase.from('warehouse_rows').eq('warehouse_id', warehouseId);
      if (effectiveYard != null && effectiveYard.isNotEmpty) {
        q = q.eq('yard', effectiveYard);
      }
      if (status != null) q = q.eq('item_status', status);
      return await AuthService._withNetworkRetry(() => q.count()) as int;
    }

    return (
      total: await countOf(null),
      detain: await countOf('Detain'),
      forfeit: await countOf('Forfeit'),
      abandoned: await countOf('Abandoned'),
    );
  }

  /// The warehouses of the SIGNED-IN yard, by code.
  ///
  /// ⚠️ No `.eq('yard', ...)` here on purpose: `warehouses.yard` plus the
  /// `warehouses_yard_select` policy (migration 008) scope this in the
  /// database, so a yard cannot be handed another yard's storage even if a
  /// caller forgets to filter. Before that column existed this returned
  /// EVERY warehouse in the system to every yard.
  Future<List<WarehouseModel>> getWarehouses() async {
    final data = await supabase.from('warehouses').select().order('code');
    return [
      for (final e in (data as List))
        WarehouseModel.fromJson(e as Map<String, dynamic>)
    ];
  }

  /// The zones of the SIGNED-IN yard's warehouses, newest warehouse first.
  /// Reference data — the SR form, the capacity view and the admin panel all
  /// read it.
  ///
  /// ⚠️ Zones carry no yard of their own; they inherit it through their parent
  /// warehouse, and `warehouse_zones_yard_select` (migration 008) enforces
  /// that in the database. This used to return every zone in the system, so a
  /// yard with no warehouses still showed 18 zones' worth of capacity.
  Future<List<WarehouseZoneModel>> getWarehouseZones() async {
    try {
      final data = await AuthService._withNetworkRetry(() => supabase
          .from('warehouse_zones')
          .select()
          .order('warehouse_id')
          .order('name'));
      return (data as List)
          .map((e) => WarehouseZoneModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      // The table only exists once 20260832_warehouse_zones.sql has run. Until
      // then report NO zones rather than failing: every capacity view then
      // shows "no zones defined", which is both true and actionable, instead
      // of a red error screen.
      //
      // Logged, though — an empty list here reads on screen as "zone not
      // defined" for every category, which looks like bad DATA when it is
      // really a failed fetch. Swallowing it silently cost real debugging time.
      debugPrint('getWarehouseZones failed, reporting none: $e');
      return const [];
    }
  }

  Future<void> saveWarehouseZone(WarehouseZoneModel zone) async {
    final row = zone.toJson();
    await AuthService._withNetworkRetry(() => zone.id.isEmpty
        ? supabase.from('warehouse_zones').insert(row)
        : supabase.from('warehouse_zones').update({
            ...row,
            'updated_at': DateTime.now().toIso8601String(),
          }).eq('id', zone.id));
  }

  Future<void> deleteWarehouseZone(String id) async {
    await AuthService._withNetworkRetry(
        () => supabase.from('warehouse_zones').delete().eq('id', id));
  }

  /// How full every zone of this yard currently is, keyed by zone id.
  ///
  /// Counts only LIVE entries (`is_returned = false`) — goods that have left
  /// no longer take up space. An entry whose zone does not match any real zone
  /// is counted against the warehouse but against no zone, which is why the
  /// capacity view shows a warehouse total as well.
  Future<Map<String, ZoneOccupancy>> getZoneOccupancy() async {
    final zones = await getWarehouseZones();
    final yard = AppSession.currentYard;

    final data = await AuthService._withNetworkRetry(() => supabase
        .from('warehouse_entries')
        .select('item_count, zone, warehouse_id')
        .eq('yard', yard)
        .eq('is_returned', false));

    // "<warehouseId>|<zone name lowercased>" → items held.
    final used = <String, int>{};
    for (final e in (data as List)) {
      final row = e as Map<String, dynamic>;
      final z = (row['zone'] ?? '').toString().trim().toLowerCase();
      if (z.isEmpty || z == 'n/a') continue;
      final key = '${row['warehouse_id']}|$z';
      used[key] =
          (used[key] ?? 0) + (parseDbInt(row['item_count']) ?? 0);
    }

    return {
      for (final z in zones)
        z.id: ZoneOccupancy(
          zone: z,
          used: used['${z.warehouseId}|${z.name.trim().toLowerCase()}'] ?? 0,
        ),
    };
  }

  Future<List<WarehouseEntryModel>> getEntriesByWarehouse(String warehouseId,
      {bool? isReturned, String? yard}) async {
    final effectiveYard =
        yard ?? (AppSession.isYardBound ? AppSession.currentYard : null);
    var query = supabase
        .from('warehouse_entries')
        .select(
            '*, warehouses(*), packages(*), admitted_profile:profiles!admitted_by(full_name, badge_number), returned_profile:profiles!returned_by(full_name, badge_number)')
        .eq('warehouse_id', warehouseId);
    if (isReturned != null) query = query.eq('is_returned', isReturned);
    if (effectiveYard != null && effectiveYard.isNotEmpty) {
      query = query.eq('yard', effectiveYard);
    }
    final data = await query.order('admitted_at', ascending: false);
    return [
      for (final e in (data as List))
        WarehouseEntryModel.fromJson(e as Map<String, dynamic>)
    ];
  }

  Future<List<WarehouseEntryModel>> getAllWarehouseEntries(
      {bool? isReturned, String? yard}) async {
    final effectiveYard =
        yard ?? (AppSession.isYardBound ? AppSession.currentYard : null);
    var query = supabase.from('warehouse_entries').select(
        '*, warehouses(*), packages(*, package_items(*)), admitted_profile:profiles!admitted_by(full_name, badge_number), returned_profile:profiles!returned_by(full_name, badge_number)');
    if (isReturned != null) query = query.eq('is_returned', isReturned);
    if (effectiveYard != null && effectiveYard.isNotEmpty) {
      query = query.eq('yard', effectiveYard);
    }
    final data = await query.order('admitted_at', ascending: false);
    return [
      for (final e in (data as List))
        WarehouseEntryModel.fromJson(e as Map<String, dynamic>)
    ];
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
    final returnedAtIso = (returnDate ?? DateTime.now()).toIso8601String();
    // Append the specific released package numbers for accurate tracking.
    if (packageNumbers != null && packageNumbers.isNotEmpty) {
      final tag = 'pkgs:${packageNumbers.join(',')}';
      returnNotes = (returnNotes == null || returnNotes.isEmpty)
          ? tag
          : '$returnNotes | $tag';
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
      int currentTotal = parseDbInt(entryRes['item_count']) ?? 0;

      // AUTO-REPAIR OLD DATA (where item_count was saved as 1 due to bug)
      if (itemId != null &&
          currentTotal == 1 &&
          entryRes['is_returned'] == false) {
        final itemRes = await supabase
            .from('package_items')
            .select('quantity')
            .eq('id', itemId)
            .single();
        int trueQty = parseDbInt(itemRes['quantity']) ?? 0;
        if (trueQty > 1) {
          // Find if there are already returned entries
          final returnedRes = await supabase
              .from('warehouse_entries')
              .select('item_count')
              .eq('package_item_id', itemId)
              .eq('is_returned', true);
          int returnedSum = (returnedRes as List)
              .fold(0, (sum, e) => sum + (parseDbInt(e['item_count']) ?? 0));
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
    final returnedAtIso = (forfeitDate ?? DateTime.now()).toIso8601String();

    final entryRes = await supabase
        .from('warehouse_entries')
        .select(
            'package_item_id, item_count, package_id, warehouse_id, zone, hold_reason, admitted_by, admitted_at, daily_rate')
        .eq('id', entryId)
        .single();

    final itemId = entryRes['package_item_id'] as String?;
    final currentTotal = parseDbInt(entryRes['item_count']) ?? 0;
    final disposeQty =
        (qty != null && qty > 0 && qty < currentTotal) ? qty : currentTotal;
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
            entryDate: forfeitDate ?? parseDbDate(pkgRow['entry_date']),
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
    required String
        dispositionType, // RELEASED, SOLD, DESTROYED, RE-EXPORTED, OTHER
    required int qty,
    String? notes,
    // The date the disposition took place (chosen in the confirm dialog).
    // Stored as returned_at; defaults to now when not supplied.
    DateTime? dispositionDate,
  }) async {
    final user = supabase.auth.currentUser;
    final returnedAtIso = (dispositionDate ?? DateTime.now()).toIso8601String();

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
        action:
            'Final disposition: $dispositionType (item: $packageItemId, qty: $qty)',
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
        itemActiveQty = parseDbInt(row['quantity']) ?? 0;

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
          itemActiveQty += parseDbInt(e['item_count']) ?? 0;

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
  /// Capacity of every warehouse in this yard, broken down by ZONE.
  ///
  /// A warehouse's capacity is the SUM of its zones — `warehouses.capacity` is
  /// legacy and no longer consulted. Each row carries a `zoneRows` list so the
  /// capacity view can show zone by zone, which is where space is actually
  /// managed.
  ///
  /// Entries whose `zone` matches no real zone still count towards the
  /// warehouse's `used`, so nothing held goes unreported; they appear under the
  /// `unzoned` figure rather than being attributed to a zone that never had it.
  Future<List<Map<String, dynamic>>> getYardWarehouseCapacity() async {
    final yard = AppSession.currentYard;

    final zones = await getWarehouseZones();
    // ⚠️ `zone_occupancy_entries`, not `is_returned = false`.
    //
    // A release or a re-export CLOSES its warehouse entry the day the
    // disposition is written, so 31 released and 15 re-exported lots
    // vanished from their zones while still physically standing in them --
    // an officer looking for space was told there was room a pallet was
    // sitting in. The view keeps them until the hand-over is recorded
    // (postgres/58); the figure went 187 to 233.
    //
    // ⚠️ The storage CHARGE deliberately does not follow. Billing ends
    // when the yard rules -- the bill is issued and closed at that point,
    // and the goods wait on their owner, not on the yard. Capacity is a
    // physical question and billing a contractual one; they end on
    // different days.
    // ⚠️ FLAT columns, not `warehouses(name, code)`. This is a VIEW, so
    // PostgREST has no foreign key to embed through -- the embed threw
    // "no unique foreign key between zone_occupancy_entries and
    // warehouses" and put a database error across the whole dashboard.
    // postgres/58 carries the name and code for exactly this reason.
    final data = await AuthService._withNetworkRetry(() => supabase
        .from('zone_occupancy_entries')
        .select('item_count, zone, warehouse_id, warehouse_name, '
            'warehouse_code')
        .eq('yard', yard));

    // warehouse_id → { name, code, "<zone lowercased>" → used, unzoned }
    final byWarehouse = <String, Map<String, dynamic>>{};

    Map<String, dynamic> shell(String id, [Map? wh]) => byWarehouse.putIfAbsent(
        id,
        () => {
              'warehouseName': wh?['name']?.toString() ?? 'Unknown',
              'warehouseCode': wh?['code']?.toString() ?? '—',
              'usedByZone': <String, int>{},
              'unzoned': 0,
            });

    for (final e in (data as List)) {
      final row = e as Map<String, dynamic>;
      final whId = row['warehouse_id']?.toString() ?? '';
      if (whId.isEmpty) continue;
      final agg = shell(whId, {
        'name': row['warehouse_name'],
        'code': row['warehouse_code'],
      });
      final qty = parseDbInt(row['item_count']) ?? 0;
      final z = (row['zone'] ?? '').toString().trim().toLowerCase();
      if (z.isEmpty || z == 'n/a') {
        agg['unzoned'] = (agg['unzoned'] as int) + qty;
      } else {
        final m = agg['usedByZone'] as Map<String, int>;
        m[z] = (m[z] ?? 0) + qty;
      }
    }

    // A warehouse with zones but nothing in it still belongs on the list.
    //
    // ⚠️ Names come from `warehouses`, NOT only from the occupancy rows. The
    // occupancy view is filtered to this yard's stored goods, so a warehouse
    // holding nothing contributes no row and therefore no name — every empty
    // warehouse was listed as "Unknown". `warehouses` is itself yard-scoped
    // by RLS (migration 008), so this names the yard's own warehouses and no
    // one else's.
    final whNames = <String, Map<String, String>>{
      for (final w in await getWarehouses())
        w.id: {'name': w.name, 'code': w.code},
    };
    for (final e in (data as List)) {
      final row = e as Map<String, dynamic>;
      final name = row['warehouse_name']?.toString();
      if (name == null) continue;
      whNames[row['warehouse_id'].toString()] = {
        'name': name,
        'code': row['warehouse_code']?.toString() ?? '—',
      };
    }
    for (final z in zones) {
      final agg = shell(z.warehouseId);
      if (agg['warehouseName'] == 'Unknown' && whNames[z.warehouseId] != null) {
        agg['warehouseName'] = whNames[z.warehouseId]!['name']!;
        agg['warehouseCode'] = whNames[z.warehouseId]!['code']!;
      }
    }

    final result = byWarehouse.entries.map((entry) {
      final whId = entry.key;
      final v = entry.value;
      final usedByZone = v['usedByZone'] as Map<String, int>;
      final mine = zones.where((z) => z.warehouseId == whId).toList()
        ..sort((a, b) => a.name.compareTo(b.name));

      final zoneRows = [
        for (final z in mine)
          () {
            final used = usedByZone[z.name.trim().toLowerCase()] ?? 0;
            return {
              'id': z.id,
              'name': z.name,
              'capacity': z.capacity,
              'used': used,
              'free': (z.capacity - used) > 0 ? z.capacity - used : 0,
              'percent': z.capacity > 0 ? (used / z.capacity) * 100 : 0.0,
            };
          }(),
      ];

      // Held in a zone this warehouse no longer defines — still occupying it.
      final knownNames = mine.map((z) => z.name.trim().toLowerCase()).toSet();
      final orphaned = usedByZone.entries
          .where((e) => !knownNames.contains(e.key))
          .fold<int>(0, (a, e) => a + e.value);

      final capacity =
          zoneRows.fold<int>(0, (a, z) => a + (z['capacity'] as int));
      final used = zoneRows.fold<int>(0, (a, z) => a + (z['used'] as int)) +
          (v['unzoned'] as int) +
          orphaned;
      final percent = capacity > 0 ? (used / capacity) * 100 : 0.0;

      return {
        'warehouseId': whId,
        'warehouseName': v['warehouseName'],
        'warehouseCode': v['warehouseCode'],
        'zoneRows': zoneRows,
        'zones': zoneRows.map((z) => z['name'] as String).toList(),
        'unzoned': (v['unzoned'] as int) + orphaned,
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
    // ⚠️ Stamp the yard. A warehouse with no yard belongs to none, and before
    // `warehouses.yard` existed (migration 008) every warehouse an admin added
    // became visible in EVERY yard. The RLS write policy also checks this, so
    // omitting it is rejected rather than silently global.
    final data = await supabase
        .from('warehouses')
        .insert({
          'name': name,
          'code': code,
          'description': description,
          'location': location,
          'capacity': capacity,
          'yard': AppSession.currentYard,
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
      (sum, entry) => sum + (parseDbInt(entry['item_count']) ?? 0),
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
    return [
      for (final e in (data as List))
        ProfileModel.fromJson(e as Map<String, dynamic>)
    ];
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

  /// Turns a failed `profiles` write into something the person reading it can
  /// act on.
  ///
  /// The case that motivated this: the ICT portal shipped before any migration
  /// widened `profiles_role_check`, so every ICT sign-up failed with SQLSTATE
  /// 23514. The screen's error classifier saw an unfamiliar string and fell
  /// through to "Network problem — check your internet connection", which sent
  /// people to look at the Wi-Fi for a schema bug.
  static String _profileWriteMessage(Object e, String role) {
    final s = e.toString().toLowerCase();

    // 23514 = check_violation. For `role` it means the database has not been
    // migrated to know this portal's role yet.
    if (s.contains('23514') ||
        s.contains('check constraint') ||
        s.contains('profiles_role_check')) {
      return 'This database does not accept the "$role" account type yet. '
          'The migration that adds it has not been run on this server — ask '
          'ICT to apply db/migrations (20260839_ict_directorates_and_yards.sql).';
    }
    // 23505 = unique_violation: username or e-mail already taken.
    if (s.contains('23505') || s.contains('duplicate') || s.contains('unique')) {
      return 'An account with that username or e-mail already exists.';
    }
    // 42703 = undefined_column: the app is newer than the database.
    if (s.contains('42703') || s.contains('does not exist')) {
      return 'This database is missing a column this version of the app needs. '
          'Ask ICT to run the pending migrations in db/migrations.';
    }
    if (s.contains('permission denied') ||
        s.contains('row-level security') ||
        s.contains('42501')) {
      return 'This account is not permitted to create that profile. '
          'Check the portal you signed in through.';
    }
    return 'Could not save the account profile: '
        '${e.toString().replaceAll("Exception: ", "")}';
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
    String? directorate,
    String? profileImageUrl,
  }) async {
    // E-mail a self-issued code via Gmail (not Supabase). The account itself is
    // created only after the code is verified, in [verifySignupOtp].
    await GmailOtpService.instance
        .sendCode(email.trim(),
            recipientName: fullName, purpose: OtpPurpose.createAccount);
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
    String? directorate,
    String? profileImageUrl,
  }) async {
    // Verify our self-issued Gmail code (throws on bad/expired code).
    //
    // ⚠️ WITHOUT spending it. Everything below can still fail — a refused
    // role, a duplicate username, a password the policy rejects — and a
    // consumed code turned every one of those into a second, misleading
    // error: the officer was told "No verification code was sent" when the
    // real complaint was about the account. Reported from the ICT sign-up
    // screen: first press showed the real error, second press showed the
    // missing-code one. The code is spent at the end, once nothing can fail.
    GmailOtpService.instance.verifyCode(email.trim(), otp, consume: false);

    final metadata = <String, dynamic>{
      'full_name': fullName,
      'role': role,
      'badge_number': badgeNumber,
      if (username != null) 'username': username,
      if (mobileNumber != null) 'mobile_number': mobileNumber,
      if (jobRole != null) 'job_role': jobRole,
      if (department != null) 'department': department,
      if (yard != null) 'yard': yard,
      if (directorate != null) 'directorate': directorate,
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
        //
        // ⚠️ Only when the account is being RE-CREATED AS ITSELF.
        //
        // This branch exists for an account whose auth.users row was made but
        // whose profile write then failed — signing in and re-writing the
        // profile repairs it. But it was reached for ANY existing e-mail, so
        // signing up on a second portal with an address that already had an
        // account silently signed in as that account and upserted the new
        // role over it. One e-mail, one id: the ICT account became a Disposal
        // account, and ICT ceased to exist.
        //
        // That is privilege escalation by sign-up form: anyone who knows an
        // officer's address and password could re-point their account at a
        // portal of their choosing. The repair is only ever valid when the
        // role being written is the role already there.
        final res = await AuthService._withNetworkRetry(() => supabase.auth
            .signInWithPassword(email: email.trim(), password: password));
        user = res.user;
        final existing = await supabase
            .from('profiles')
            .select('role')
            .eq('id', user!.id)
            .maybeSingle();
        final existingRole = (existing == null)
            ? null
            : (existing as Map<String, dynamic>)['role']?.toString();
        if (existingRole != null && existingRole.isNotEmpty &&
            existingRole != role) {
          await supabase.auth.signOut();
          throw Exception(
              'An account already exists for this e-mail address, in a '
              'different directorate. One e-mail address may hold one '
              'account. Ask ICT to transfer it, or use another address.');
        }
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

    // ⚠️ The profile is written by `auth.sign_up` itself (migration 035), in
    // the same transaction as the account. There is deliberately NO profile
    // write here any more.
    //
    // There used to be an upsert at this point carrying username, job_role and
    // directorate, and it was the reported bug: a person signing up is not
    // signed in, so `auth.uid()` is null and the `yard_profiles_insert` policy
    // refused it with 42501 — surfaced as "This account is not permitted to
    // create that profile". The account had already been committed by the
    // statement before, so it survived the error and the officer found it in
    // the database after being told the sign-up failed.
    //
    // Moving the write inside the SECURITY DEFINER function is what makes the
    // account and its full profile succeed or fail together. Re-adding a
    // client-side profile write here would restore the bug.

    // ⚠️ Spend the code only now. Nothing above can fail any more, so this is
    // the first point at which throwing the code away cannot strand the
    // officer with a working account and a dead code, or a failed account and
    // no way to retry.
    GmailOtpService.instance.consumeCode(email.trim());

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
    if (isActive) {
      // ⚠️ Turning an account back ON goes through reactivate_account, not a
      // plain is_active write. A dormant account still has a 90-day-old
      // last_sign_in_at, so flipping the flag alone would wake it and the
      // next dormancy sweep would switch it straight back off. The function
      // resets that clock and clears the reason in the same statement, and
      // it refuses anyone who is not ICT (migrations 021 and 022).
      await supabase.rpc('reactivate_account', params: {'p_id': profileId});
    } else {
      await supabase.from('profiles').update({
        'is_active': false,
        'deactivated_reason': 'manual',
        'deactivated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', profileId);
    }
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
    if (username != null)
      updates['username'] = username.isEmpty ? null : username;
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
    final base =
        (_slug(parts.first) + (parts.length > 1 ? '.${_slug(parts[1])}' : ''))
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
  /// The e-mail says it is an officer account being set up by an
  /// administrator, which is not something the reader asked for themselves.
  Future<void> requestOfficerOtp({
    required String email,
    required String fullName,
    String? mobileNumber,
    String? badgeNumber,
  }) async {
    await GmailOtpService.instance
        .sendCode(email.trim(),
            recipientName: fullName.trim(),
            purpose: OtpPurpose.officerAccount);
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

  /// When each member of [yard] was activated and deactivated IN THAT YARD.
  ///
  /// ⚠️ Read from `audit_logs`, not from `profiles`. A profile carries only
  /// `is_active` — a single boolean saying where someone stands TODAY — and
  /// `created_at`, which is when the account was made, not when it started
  /// serving here. Neither can answer "what period did this member work in
  /// this yard", which is the question the Admin Panel is being asked.
  ///
  /// The log already records every event with the yard it happened in:
  ///
  ///   Activated user account     → started serving
  ///   Deactivated user account   → stopped
  ///   Transferred officer from X to Y → left X / joined Y
  ///
  /// ⚠️ Scoped to ONE yard on purpose. An officer transferred GL1 → GL2 → GL1
  /// has served two separate stints here, and GL2's spell in between is not
  /// this yard's business. Filtering by `audit_logs.yard` keeps each yard's
  /// panel to its own history.
  ///
  /// Returns, per profile id: the first activation seen in this yard and the
  /// last deactivation, or null where the log has no such event (an account
  /// provisioned before the log recorded them).
  Future<Map<String, ({DateTime? activatedAt, DateTime? deactivatedAt})>>
      getYardServicePeriods(String yard) async {
    if (yard.trim().isEmpty) return const {};

    final rows = await AuthService._withNetworkRetry(() => supabase
        .from('audit_logs')
        .select('entity_id, action, created_at')
        .eq('entity_type', 'profile')
        .eq('yard', yard)
        .order('created_at', ascending: true));

    final out = <String, ({DateTime? activatedAt, DateTime? deactivatedAt})>{};
    for (final r in (rows as List)) {
      final row = r as Map<String, dynamic>;
      final id = row['entity_id']?.toString();
      if (id == null || id.isEmpty) continue;
      final at = parseDbDate(row['created_at']);
      if (at == null) continue;
      final action = (row['action'] ?? '').toString().toLowerCase();

      // A transfer INTO this yard starts a stint here; one OUT ends it. The
      // log writes the row against the yard the action was taken in, so the
      // direction has to come from the wording.
      final joined = action.startsWith('activated user account') ||
          (action.startsWith('transferred officer from') &&
              action.endsWith('to ${yard.toLowerCase()}'));
      final left = action.startsWith('deactivated user account') ||
          (action.startsWith('transferred officer from ${yard.toLowerCase()}'));
      if (!joined && !left) continue;

      final cur = out[id];
      out[id] = (
        // FIRST activation: when this member started here.
        activatedAt: joined ? (cur?.activatedAt ?? at) : cur?.activatedAt,
        // LAST departure: rows arrive oldest-first, so this keeps overwriting
        // until the most recent one wins.
        deactivatedAt: left ? at : cur?.deactivatedAt,
      );
    }
    return out;
  }
}

// ── ICT Service (Information & Communication Technology Division) ──

class IctService {
  /// Fetch all yard staff (Admins and Officers) across all yards, with optional filters.
  Future<List<ProfileModel>> getAllYardStaff({
    String? yard,
    /// Narrows a multi-directorate yard's staff to ONE directorate (e.g.
    /// "CED/NNR" vs "PSD/NNR") -- an officer's own `profiles.directorate` is
    /// checked directly, unlike the SR-number-prefix match a package list
    /// needs, since a profile is not tied to any one SR number.
    String? directorate,
    String? role,
    String? query,
    bool? activeOnly,
  }) async {
    var req = supabase.from('profiles').select();

    if (role != null && role.isNotEmpty && role != 'all') {
      req = req.eq('role', role);
    } else {
      req = req.inFilter('role', ['admin', 'officer']);
    }

    if (yard != null && yard.isNotEmpty && yard != 'all') {
      req = req.eq('yard', yard);
    }
    if (directorate != null && directorate.isNotEmpty) {
      req = req.eq('directorate', directorate);
    }

    if (activeOnly == true) {
      req = req.eq('is_active', true);
    }

    final data = await req.order('created_at', ascending: false);
    var list = (data as List).map((e) => ProfileModel.fromJson(e)).toList();

    if (query != null && query.trim().isNotEmpty) {
      final q = query.trim().toLowerCase();
      list = list.where((p) {
        final name = p.fullName.toLowerCase();
        final uname = (p.username ?? '').toLowerCase();
        final badge = (p.badgeNumber ?? '').toLowerCase();
        final mobile = (p.mobileNumber ?? '').toLowerCase();
        final yardCode = (p.yard ?? '').toLowerCase();
        return name.contains(q) ||
            uname.contains(q) ||
            badge.contains(q) ||
            mobile.contains(q) ||
            yardCode.contains(q);
      }).toList();
    }

    return list;
  }

  /// Request OTP for new account creation
  Future<void> requestUserOtp({
    required String email,
    required String fullName,
    String? mobileNumber,
    String? badgeNumber,
    required String role,
    required String yard,
  }) async {
    await GmailOtpService.instance
        .sendCode(email.trim(),
            recipientName: fullName.trim(),
            purpose: OtpPurpose.officerAccount);
  }

  /// Verify OTP, create account (Admin / DC/SDDC or Officer) with generated credentials,
  /// assign yard, send credentials email, and restore the ICT admin's session.
  Future<Map<String, dynamic>> verifyAndCreateUser({
    required String email,
    required String otp,
    required String fullName,
    String? mobileNumber,
    String? badgeNumber,
    required String role, // 'admin' (SDDC / DDC) or 'officer'
    /// The POST held: a key of `kPostTitles` ('officer', 'dc', 'sddc'). DC and
    /// SDDC share the admin role, so the role alone cannot record which.
    String? jobRole,
    required String yard,
    String? directorate,
  }) async {
    GmailOtpService.instance.verifyCode(email.trim(), otp);

    final ictSession = supabase.auth.currentSession;
    final ictId = supabase.auth.currentUser?.id;

    final username = await AdminService()._uniqueUsername(fullName);
    final password = AdminService._randomOfficerPassword();

    final metadata = <String, dynamic>{
      'full_name': fullName.trim(),
      'role': role,
      'badge_number': badgeNumber?.trim(),
      'mobile_number': mobileNumber?.trim(),
      'yard': yard,
      'username': username,
      if (jobRole != null && jobRole.isNotEmpty) 'job_role': jobRole,
      if (directorate != null && directorate.isNotEmpty)
        'directorate': directorate,
    };

    final String userId;
    try {
      final res = await AuthService._withNetworkRetry(() => supabase.auth
          .signUp(email: email.trim(), password: password, data: metadata));
      final u = res.user;
      if (u == null) throw Exception('Could not create the user account.');
      userId = u.id;
    } on AuthException catch (e) {
      final m = e.message.toLowerCase();
      if (e.code == 'user_already_exists' ||
          m.contains('already registered') ||
          m.contains('already been registered')) {
        if (ictSession != null) {
          try {
            await supabase.auth.setSession(ictSession.refreshToken!);
          } catch (_) {}
        }
        throw Exception('This email is already registered.');
      }
      rethrow;
    }

    try {
      await supabase.from('profiles').upsert({
        'id': userId,
        'full_name': fullName.trim(),
        'username': username,
        'badge_number': badgeNumber?.trim(),
        'mobile_number': mobileNumber?.trim(),
        'role': role,
        'is_active': true,
        'yard': yard,
        if (directorate != null && directorate.isNotEmpty)
          'directorate': directorate,
      });
    } catch (_) {}

    // Restore the ICT admin's session
    if (ictSession != null) {
      try {
        await supabase.auth.setSession(ictSession.refreshToken!);
      } catch (_) {}
    }

    // E-mail credentials via GmailOtpService
    bool emailed = true;
    try {
      await GmailOtpService.instance
          .sendCredentials(email.trim(), fullName.trim(), username, password);
    } catch (_) {
      emailed = false;
    }

    if (ictId != null) {
      await AuditLogService().recordLog(
        userId: ictId,
        action: 'ICT created $role account ($username for $yard)',
        entityType: 'profile',
        entityId: userId,
      );
    }

    return {
      'ok': true,
      'emailed': emailed,
      'username': username,
      'password': password,
    };
  }

  /// Toggle Active / Inactive status of an account
  /// Every directorate account, for the credential-reset page.
  ///
  /// Yard staff are excluded: they reset their own password from the login
  /// page, and only a directorate account -- which is institutional and shared
  /// across whoever holds the post -- needs ICT to reissue its credentials.
  Future<List<ProfileModel>> getDirectorateAccounts() async {
    final rows = await AuthService._withNetworkRetry(() => supabase
        .from('profiles')
        .select('*')
        .inFilter('role', kDirectorateRoles)
        .order('role'));
    return [
      for (final r in (rows as List))
        ProfileModel.fromJson(r as Map<String, dynamic>)
    ];
  }

  /// Issues a fresh username and password for a directorate account and emails
  /// both to the address it is registered to.
  ///
  /// A directorate account belongs to a POST, not a person, so there is nobody
  /// to send a "reset your own password" link to -- whoever holds the post
  /// next may never have signed in. ICT reissues instead, and the holder
  /// changes both from their profile once they are in.
  ///
  /// Returns the new username, so the page can say what was sent without
  /// showing the password on screen: it belongs in the mailbox, not on an
  /// office monitor.
  Future<String> resetDirectorateCredentials(String profileId) async {
    final row = await AuthService._withNetworkRetry(() => supabase
        .from('profiles')
        .select('id, full_name, role')
        .eq('id', profileId)
        .single());

    final fullName = (row['full_name'] as String?)?.trim() ?? 'Directorate';
    final role = (row['role'] as String?)?.trim() ?? '';

    // The address is on auth.users, not profiles.
    final userRow = await AuthService._withNetworkRetry(
        () => supabase.from('auth.users').select('email').eq('id', profileId).single());
    final email = (userRow['email'] as String?)?.trim() ?? '';
    if (email.isEmpty) {
      throw Exception('That account has no email address to send to.');
    }

    final username = await AdminService()._uniqueUsername(fullName);
    final password = AdminService._randomOfficerPassword();

    // Change both values in one database transaction. The email is sent only
    // after this succeeds, so it can never describe a half-applied reset.
    await AuthService._withNetworkRetry(() => supabase.rpc(
      'reset_directorate_credentials',
      params: {
        'p_profile_id': profileId,
        'p_username': username,
        'p_password': password,
      }));

    await GmailOtpService.instance
        .sendCredentials(email, fullName, username, password,
            // ⚠️ A REISSUE, not a welcome. The previous password has
            // just stopped working, and this arrives unannounced -- so it
            // has to say so, and say what to do if it was not the reader
            // who asked.
            isReissue: true, roleLabel: role);

    await AuditLogService().recordLog(
      userId: supabase.auth.currentUser?.id,
      action: 'Reset directorate credentials for $fullName',
      entityType: 'auth',
      entityId: profileId,
      // Deliberately NOT the password.
      details: {'role': role, 'username': username},
    );
    return username;
  }

  Future<void> toggleUserStatus(String profileId, bool active, {String? staffName}) async {
    await supabase
        .from('profiles')
        .update({'is_active': active}).eq('id', profileId);

    await AuditLogService().recordLog(
      userId: supabase.auth.currentUser?.id,
      action: active ? 'Activated user account' : 'Deactivated user account',
      entityType: 'profile',
      entityId: profileId,
      details: {
        'status': active ? 'active' : 'inactive',
        if (staffName != null) 'staff_name': staffName,
      },
    );
  }

  /// Update user details (name, salary, mobile, yard, role)
  Future<void> updateUserProfile(
    String profileId, {
    required String fullName,
    String? username,
    String? badgeNumber,
    String? mobileNumber,
    required String yard,
    required String role,
    /// The POST held — a key of `kPostTitles`. See verifyAndCreateUser.
    String? jobRole,
    String? directorate,
    String? oldYard,
    String? oldPost,
  }) async {
    await supabase.from('profiles').update({
      'full_name': fullName.trim(),
      if (username != null && username.isNotEmpty) 'username': username.trim(),
      'badge_number': badgeNumber?.trim(),
      'mobile_number': mobileNumber?.trim(),
      'yard': yard,
      'role': role,
      if (jobRole != null && jobRole.isNotEmpty) 'job_role': jobRole,
      // Sent even when null: clearing an account's directorate is a legitimate
      // edit, and `if (… != null)` would silently ignore it.
      'directorate': (directorate == null || directorate.isEmpty)
          ? null
          : directorate,
    }).eq('id', profileId);

    final isYardChanged = oldYard != null && oldYard.isNotEmpty && oldYard != yard;
    final isPostChanged = oldPost != null && oldPost.isNotEmpty && jobRole != null && oldPost != jobRole;

    String action;
    final postTitle = (jobRole != null && kPostTitles.containsKey(jobRole)) ? kPostTitles[jobRole]! : (jobRole ?? role);
    final oldPostTitle = (oldPost != null && kPostTitles.containsKey(oldPost)) ? kPostTitles[oldPost]! : oldPost;

    if (isYardChanged && isPostChanged) {
      action = 'Transferred from $oldYard to $yard & changed post from $oldPostTitle to $postTitle';
    } else if (isYardChanged) {
      action = 'Transferred officer from $oldYard to $yard';
    } else if (isPostChanged) {
      action = 'Changed post from $oldPostTitle to $postTitle';
    } else {
      action = 'Updated officer profile details';
    }

    await AuditLogService().recordLog(
      userId: supabase.auth.currentUser?.id,
      action: action,
      entityType: 'profile',
      entityId: profileId,
      details: {
        'staff_name': fullName.trim(),
        if (isYardChanged) 'old_yard': oldYard,
        if (isYardChanged) 'new_yard': yard,
        if (isPostChanged) 'old_post': oldPostTitle,
        if (isPostChanged) 'new_post': postTitle,
        'role': role,
        if (directorate != null) 'directorate': directorate,
      },
    );
  }

  /// Fetches history of lifecycle events (yard transfers, post changes, status toggles, account creation) for a staff member
  Future<List<AuditLogModel>> getStaffHistory(
    String profileId, {
    String? username,
    String? fullName,
  }) async {
    bool isRelevantLog(AuditLogModel log) {
      final a = log.action.toLowerCase();
      // Exclude all login, logout, failed attempt, session and raw privilege trigger noise
      if (a.contains('login') ||
          a.contains('logout') ||
          a.contains('signed in') ||
          a.contains('signed out') ||
          a.contains('sign in') ||
          a.contains('sign out') ||
          a.contains('failed') ||
          a.contains('password') ||
          a.contains('otp') ||
          a.contains('session') ||
          a.contains('privilege change')) {
        return false;
      }

      // Explicitly allow officer lifecycle actions
      return a.contains('transfer') ||
          a.contains('post') ||
          a.contains('role') ||
          a.contains('activated') ||
          a.contains('deactivated') ||
          a.contains('created') ||
          a.contains('profile') ||
          a.contains('yard');
    }

    try {
      final filters = <String>['entity_id.eq.$profileId'];
      if (fullName != null && fullName.trim().isNotEmpty) {
        filters.add('action.ilike.*${fullName.trim()}*');
      }
      if (username != null && username.trim().isNotEmpty) {
        filters.add('action.ilike.*${username.trim()}*');
      }

      final res = await supabase
          .from('audit_logs')
          .select('*, profiles(full_name, role)')
          .or(filters.join(','))
          .order('created_at', ascending: false);

      return (res as List)
          .map((e) => AuditLogModel.fromJson(e as Map<String, dynamic>))
          .where(isRelevantLog)
          .toList();
    } catch (e) {
      AppLog.warn('failed to fetch staff history with relation: $e',
          error: e, tag: 'ict');
      // Resilient fallback query without foreign key embed
      try {
        final fallback = await supabase
            .from('audit_logs')
            .select('*')
            .eq('entity_id', profileId)
            .order('created_at', ascending: false);
        return (fallback as List)
            .map((e) => AuditLogModel.fromJson(e as Map<String, dynamic>))
            .where(isRelevantLog)
            .toList();
      } catch (err) {
        AppLog.error('failed fallback staff history query: $err',
            error: err, tag: 'ict');
        return [];
      }
    }
  }
}

// ── Directorate & Yard Service (ICT-maintained reference data) ──────────────

/// Reads — and, for the ICT Directorate, edits — the yard/directorate lists.
///
/// These used to be `const` lists in the code, which meant adding a yard needed
/// a rebuild and a redeploy. They now live in `directorates`, `yards` and the
/// many-to-many `yard_directorates`, so ICT maintains them from the portal.
///
/// RLS does the enforcing: everyone may SELECT, only `auth_user_is_ict()` may
/// write (see 20260839_ict_directorates_and_yards.sql).
class DirectorateService {
  Future<List<DirectorateModel>> getDirectorates({bool activeOnly = false}) async {
    var req = supabase.from('directorates').select();
    if (activeOnly) req = req.eq('is_active', true);
    final data = await req.order('sort_order');
    return (data as List).map((e) => DirectorateModel.fromJson(e)).toList();
  }

  Future<List<YardModel>> getYards({bool activeOnly = false}) async {
    var req = supabase.from('yards').select();
    if (activeOnly) req = req.eq('is_active', true);
    final data = await req.order('sort_order');
    return (data as List).map((e) => YardModel.fromJson(e)).toList();
  }

  /// Every yard→directorate link, as `{yardCode: [directorateCode, ...]}`.
  ///
  /// A yard can appear under several directorates (NNR is CED and PSD;
  /// Katunayaka is B/A and ACD), which is why this is a list per yard.
  Future<Map<String, List<String>>> getYardDirectorates() async {
    final data = await supabase.from('yard_directorates').select();
    final out = <String, List<String>>{};
    for (final row in (data as List)) {
      final y = row['yard_code'] as String?;
      final d = row['directorate_code'] as String?;
      if (y == null || d == null) continue;
      (out[y] ??= <String>[]).add(d);
    }
    return out;
  }

  /// The yards under [directorateCode], for the registration yard picker.
  Future<List<String>> yardsForDirectorate(String directorateCode) async {
    final data = await supabase
        .from('yard_directorates')
        .select('yard_code')
        .eq('directorate_code', directorateCode);
    return [
      for (final row in (data as List))
        if (row['yard_code'] != null) row['yard_code'] as String
    ];
  }

  // ── Writes (ICT only — RLS rejects everyone else) ────────────────────────

  Future<void> upsertDirectorate({
    required String code,
    required String name,
    required String srPrefix,
    int sortOrder = 100,
    bool isActive = true,
  }) async {
    await supabase.from('directorates').upsert({
      'code': code.trim().toUpperCase(),
      'name': name.trim(),
      'sr_prefix': srPrefix.trim().toUpperCase(),
      'sort_order': sortOrder,
      'is_active': isActive,
    });
    await _log('Saved directorate ${code.trim().toUpperCase()}', code);
  }

  Future<void> upsertYard({
    required String code,
    required String name,
    required String srPrefix,
    int sortOrder = 100,
    bool isActive = true,
  }) async {
    await supabase.from('yards').upsert({
      'code': code.trim().toUpperCase(),
      'name': name.trim(),
      'sr_prefix': srPrefix.trim().toUpperCase(),
      'sort_order': sortOrder,
      'is_active': isActive,
    });
    await _log('Saved yard ${code.trim().toUpperCase()}', code);
  }

  /// Replaces the whole directorate set for one yard.
  ///
  /// Delete-then-insert rather than a diff: the set is a handful of rows, and
  /// this way a link the user unticked genuinely disappears.
  Future<void> setYardDirectorates(
      String yardCode, List<String> directorateCodes) async {
    final code = yardCode.trim().toUpperCase();
    await supabase.from('yard_directorates').delete().eq('yard_code', code);
    if (directorateCodes.isNotEmpty) {
      await supabase.from('yard_directorates').insert([
        for (final d in directorateCodes)
          {'yard_code': code, 'directorate_code': d.trim().toUpperCase()}
      ]);
    }
    await _log(
        'Set directorates for yard $code: ${directorateCodes.join(", ")}', code);
  }

  /// Deactivates rather than deletes.
  ///
  /// A yard code is stamped on every package, warehouse entry and audit row it
  /// ever produced; removing the row would orphan all of it. Deactivating keeps
  /// the history readable while taking the yard out of the pickers.
  Future<void> setYardActive(String yardCode, bool active) async {
    await supabase
        .from('yards')
        .update({'is_active': active}).eq('code', yardCode);
    await _log('${active ? "Activated" : "Deactivated"} yard $yardCode', yardCode);
  }

  Future<void> setDirectorateActive(String code, bool active) async {
    await supabase
        .from('directorates')
        .update({'is_active': active}).eq('code', code);
    await _log(
        '${active ? "Activated" : "Deactivated"} directorate $code', code);
  }

  Future<void> _log(String action, String entityId) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    try {
      await AuditLogService().recordLog(
        userId: user.id,
        action: action,
        entityType: 'directorate_config',
        entityId: entityId,
      );
    } catch (_) {
      // Reference data is already saved; a missing audit line must not undo it.
    }
  }
}

// ── Audit Log Service ──────────────────────────────────────────

class AuditLogService {
  static final Random _rand = Random();

  /// One PAGE of this yard's activity log.
  ///
  /// ⚠️ The Admin screen fetched a YEAR of log rows and paged them in
  /// Dart. Retention keeps twelve months, so the fetch grows all year and is
  /// largest exactly when an admin most wants to look something up.
  ///
  /// The narrowing is the same as [getAllLogs] and is stated once for both the
  /// page and the count: this yard, and only its OWN staff -- directorate
  /// accounts are head-office and must not appear here even when they share a
  /// yard code.
  Future<({List<AuditLogModel> rows, int total})> getYardLogsPaged({
    required int offset,
    required int limit,
  }) async {
    final oneYearAgo =
        DateTime.now().subtract(const Duration(days: 365)).toIso8601String();

    T narrow<T>(T q) {
      var query = q as dynamic;
      query = query
          .eq('yard', AppSession.currentYard)
          .inFilter('profiles.role', ['admin', 'officer'])
          .gte('created_at', oneYearAgo);
      return query as T;
    }

    final rows = await AuthService._withNetworkRetry(() => narrow(supabase
            .from('audit_logs')
            .select('*, profiles!inner(full_name, role)'))
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1));
    final total = await AuthService._withNetworkRetry(() => narrow(supabase
            .from('audit_logs')
            .select('id, profiles!inner(role)'))
        .count());

    return (
      rows: [
        for (final e in (rows as List))
          AuditLogModel.fromJson(e as Map<String, dynamic>)
      ],
      total: total is int ? total : (total as num).toInt(),
    );
  }

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
    return [
      for (final e in (data as List))
        AuditLogModel.fromJson(e as Map<String, dynamic>)
    ];
  }

  /// EVERY log across every yard and directorate, for the ICT Directorate.
  ///
  /// Deliberately the opposite of [getAllLogs], which scopes to one yard and
  /// drops head-office staff: ICT provisions and oversees all of them, so it
  /// needs the whole picture and filters it itself. The actor's role and yard
  /// ride along so it can.
  ///
  /// ⚠️ Paged and filtered IN SQL, one page at a time.
  ///
  /// This used to return the whole table and let the screen filter and slice
  /// it. That is fine at a few hundred rows and hopeless at a few hundred
  /// thousand: every visit sent the entire audit history over the wire, held
  /// all of it in memory, and made the officer wait for rows 25 through
  /// 250,000 that they were never going to look at.
  ///
  /// So EVERY narrowing the screen offers is a WHERE clause here — the date
  /// window, the yard, the role, the entity type and the search box. They have
  /// to be: paging in SQL while filtering in Dart would page the unfiltered
  /// table and then throw most of each page away, so the pages would come back
  /// short and the count would be a different number from the rows.
  ///
  /// [AuditLogPage.total] is a second, count-only query — the row count of the
  /// same WHERE, so "Showing 1–25 of N" counts what the filters actually
  /// matched rather than what fitted on the page.
  Future<AuditLogPage> getAllLogsAcrossOffices({
    DateTime? from,
    DateTime? to,
    String? yard,
    String? role,
    String? entityType,
    String? search,
    int offset = 0,
    int limit = 25,
  }) async {
    // The same narrowing, applied to the page query and to the count query.
    T narrow<T>(T q) {
      var query = q as dynamic;
      if (from != null) {
        query = query.gte('created_at', from.toIso8601String());
      }
      if (to != null) {
        query = query.lte('created_at', to.toIso8601String());
      }
      // ⚠️ Routine session traffic is hidden BY DEFAULT, not deleted and not
      // made unreachable. 690 of the 1046 rows here are sign-ins and
      // sign-outs; what ICT opens this page for is what somebody CHANGED —
      // an SR edited, an appeal decided, goods released, a privilege granted
      // — and those 356 rows were buried under the other 690.
      //
      // ⚠️ Hidden, not dropped. Picking "Sign-in / Sign-out" in the Activity
      // filter brings them straight back, because "who was in the system at
      // 3pm" is a real question an audit trail has to answer — it is just not
      // the question the page is opened with.
      if (entityType == null || entityType.isEmpty) {
        query = query.not('entity_type', 'eq', 'auth');
      }
      if (yard != null && yard.isNotEmpty) query = query.eq('yard', yard);
      if (role != null && role.isNotEmpty) {
        // ⚠️ The role STAMPED on the row, matching what the table displays.
        // Filtering on profiles.role while showing actor_role would have made
        // the two disagree: picking "Officer" would hide the very rows the
        // column labels OFFICER, because the person is an SDDC today.
        query = query.eq('actor_role', role);
      }
      if (entityType != null && entityType.isNotEmpty) {
        query = query.eq('entity_type', entityType);
      }
      final q2 = search?.trim() ?? '';
      if (q2.isNotEmpty) {
        // The same columns the screen's search box used to scan, now as one
        // OR in SQL. profiles.full_name is deliberately absent: it lives on
        // the joined table, and PostgREST cannot OR across an embed.
        final like = '%${q2.replaceAll(',', ' ')}%';
        query = query.or(
            'action.ilike.$like,entity_type.ilike.$like,entity_id.ilike.$like');
      }
      return query as T;
    }

    final rows = await narrow(supabase
            .from('audit_logs')
            .select('*, profiles!inner(full_name, role)'))
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);

    final total = await narrow(supabase
            .from('audit_logs')
            .select('id, profiles!inner(role)'))
        .count();

    return AuditLogPage(
      rows: [
        for (final e in (rows as List))
          AuditLogModel.fromJson(e as Map<String, dynamic>)
      ],
      total: total is int ? total : (total as num).toInt(),
    );
  }

  /// The years the log actually has rows in, newest first, plus the current
  /// year and the next one.
  ///
  /// ⚠️ The DISTINCT runs in Postgres (audit_log_years), not here. Working it
  /// out in Dart means fetching every timestamp in the table to throw all but
  /// a handful away — the same mistake this screen was making before it was
  /// paged in SQL.
  ///
  /// The current year and the next are added whether or not they have rows,
  /// for the same reason [srYears] adds them to the yard's SR filter: on 1
  /// January nothing has been logged yet, and the year an officer is working
  /// in must be in the filter meant to find it.
  Future<List<int>> auditLogYears() async {
    final data = await supabase.rpc('audit_log_years');
    final years = <int>{
      for (final row in (data is List ? data : const []))
        if (row is Map)
          (row.values.first as num).toInt()
        else
          (row as num).toInt(),
      DateTime.now().year,
      DateTime.now().year + 1,
    };
    return years.toList()..sort((a, b) => b.compareTo(a));
  }

  /// Every distinct entity type present, for the Activity filter.
  ///
  /// ⚠️ A separate query, because the screen can no longer derive the list
  /// from the rows it holds — it only holds one page. A filter built from one
  /// page would offer whatever happened to be on it and hide the rest.
  Future<List<String>> auditEntityTypes() async {
    final data = await supabase.from('audit_logs').select('entity_type');
    return {
      for (final e in (data as List)) (e as Map)['entity_type'] as String
    }.toList()
      ..sort();
  }

  Future<void> recordLog({
    required String? userId,
    required String action,
    required String entityType,
    required String entityId,
    Map<String, dynamic>? details,
  }) async {
    try {
      await supabase.from('audit_logs').insert({
        'user_id': userId,
        // ⚠️ stampYard, not currentYard. currentYard falls back to the
        // default code so SR numbers always resolve, and that fallback was
        // being written onto every audit row — so an ICT or Valuation
        // sign-in was logged as happening in Grey Line 1. A directorate is
        // not inside a yard (migration 027).
        'yard': AppSession.stampYard,
        'action': action,
        'entity_type': entityType,
        'entity_id': entityId,
        'details': details,
      });
      // Opportunistically prune logs older than a year. Sampled (~1 in 20
      // writes) so we don't run the delete on every single insert; fire-and-
      // forget so a failure never blocks the action being logged.
      if (_rand.nextInt(20) == 0) {
        unawaited(
            supabase.rpc('purge_old_audit_logs').then((_) {}, onError: (_) {}));
      }
    } catch (e) {
      AppLog.warn('audit log write failed', error: e, tag: 'audit');
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
      AppLog.warn('could not resolve package creator', error: e,
          tag: 'audit');
    }
    return null;
  }
}

// ── Package Category Service ──────────────────────────────────

class PackageCategoryService {
  Future<List<PackageCategory>> getCategories() async {
    final data = await supabase
        .from('package_categories')
        .select('*, warehouses(name)')
        .order('name');
    return [
      for (final e in (data as List))
        PackageCategory.fromJson(e as Map<String, dynamic>)
    ];
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
  /// One PAGE of the yard's Forfeited table, chosen in SQL.
  ///
  /// ⚠️ 122 lines of Dart moved into `forfeit_rows` (postgres/49). The
  /// screen walked every forfeited package with its items and warehouse
  /// entries -- 42 records becoming 48 rows, 259ms -- and had NO pager at
  /// all, so every row rendered at once.
  ///
  /// The view carries all of it: the row-per-forfeit-EVENT rule, the
  /// package-level coverage rule, the appeal-lifecycle exception to the
  /// final-disposition cut, the legacy summary row, and the three separate
  /// ways a record leaves the table (tendered, sold/destroyed, requested).
  /// Checked row-for-row against the Dart on the live data.
  Future<
      ({
        List<ForfeitRowData> rows,
        int total,
        Map<String, ForfeitedPackageModel> packages
      })> getForfeitRowsPaged({
    required int offset,
    required int limit,
    String? search,
    String? yardFilter,
    DateTime? dateStart,
    DateTime? dateEnd,
    String? year,

    /// The Post Status Activity chip, or 'all'.
    String activity = 'all',
  }) async {
    PgQuery narrow(PgQuery q) {
      final s = search?.trim() ?? '';
      if (s.isNotEmpty) {
        // ⚠️ TOKEN match on the SR number, so a partial like "GL1/13"
        // still finds "GL1/SR/13/2026". Every "/"- or space-separated piece
        // must appear; the consignee is matched whole.
        final tokens = s
            .split(RegExp(r'[\s/]+'))
            .where((t) => t.isNotEmpty)
            .toList();
        for (final t in tokens) {
          q = q.or('sr_number.ilike.%$t%,consignee_name.ilike.%$s%');
        }
        if (tokens.isEmpty) {
          q = q.or('sr_number.ilike.%$s%,consignee_name.ilike.%$s%');
        }
      }
      if (yardFilter != null && yardFilter.isNotEmpty) {
        q = q.or('yard.eq.$yardFilter,sr_number.ilike.%/$yardFilter/%');
      }
      if (dateStart != null) {
        final from = DateTime(dateStart.year, dateStart.month, dateStart.day);
        q = q.gte('forfeited_date', from.toIso8601String());
      }
      if (dateEnd != null) {
        final to = DateTime(dateEnd.year, dateEnd.month, dateEnd.day, 23, 59, 59);
        q = q.lte('forfeited_date', to.toIso8601String());
      }
      if (year != null && year.isNotEmpty) {
        q = q.ilike('sr_number', '%/$year');
      }
      if (activity != 'all' && activity.isNotEmpty) {
        q = q.eq('reason', activity);
      }
      return q;
    }

    final data = await AuthService._withNetworkRetry(() =>
        narrow(supabase.from('forfeit_rows').select(
                'forfeited_package_id, package_id, item_id, entry_id, '
                'sr_number, consignee_name, yard, item_name, hs_code, qty, '
                'forfeited_date, officer, item_status, item_decision, '
                'reason, row_kind'))
            // Most-recently forfeited first, by the moment it was recorded.
            .order('sort_moment', ascending: false)
            .range(offset, offset + limit - 1));
    final total = await AuthService._withNetworkRetry(
        () => narrow(supabase.from('forfeit_rows')).count());

    final rows = [
      for (final e in (data as List))
        ForfeitRowData.fromJson(e as Map<String, dynamic>)
    ];
    if (rows.isEmpty) {
      return (rows: rows, total: total as int, packages: const <String, ForfeitedPackageModel>{});
    }

    // ⚠️ The forfeited RECORDS behind this page, one query.
    //
    // The table's appeal column reads a good deal off the record -- the
    // deadline, the hold and its note, the per-item decision and its label --
    // and the details popup wants the whole package. Fetching them for a page
    // is what makes the row itself able to stay flat.
    final fpIds = rows.map((r) => r.forfeitedPackageId).toSet().toList();
    final fpData = await AuthService._withNetworkRetry(() => supabase
        .from('forfeited_packages')
        .select(
            '*, packages(*, package_items(*), warehouse_entries(*, warehouses(*), returned_profile:profiles!returned_by(full_name, badge_number)))')
        .inFilter('id', fpIds));

    return (
      rows: rows,
      total: total as int,
      packages: <String, ForfeitedPackageModel>{
        for (final e in (fpData as List))
          (e as Map<String, dynamic>)['id'].toString():
              ForfeitedPackageModel.fromJson(e)
      },
    );
  }

  /// The two figures the Forfeited header shows.
  ///
  /// ⚠️ Counted over the whole table, not the page -- and counting the
  /// SAME rows the table renders, one per forfeited item or disposition event.
  /// The header used to fold them from the raw package list, which includes
  /// records that produce no forfeit row at all.
  Future<({int total, int actionable})> getForfeitCounts() async {
    final total = await AuthService._withNetworkRetry(
        () => supabase.from('forfeit_rows').count());
    final actionable = await AuthService._withNetworkRetry(() =>
        supabase.from('forfeit_rows').eq('is_actionable', true).count());
    return (total: total as int, actionable: actionable as int);
  }

  /// The SR years the Forfeited table's year filter offers.
  ///
  /// ⚠️ Over the whole table, not the page: a year missing from the
  /// dropdown reads as records that no longer exist.
  Future<List<String>> getForfeitRowYears() async {
    final data = await AuthService._withNetworkRetry(
        () => supabase.from('forfeit_rows').select('sr_number'));
    return [
      for (final e in (data as List))
        (e as Map<String, dynamic>)['sr_number']?.toString() ?? ''
    ];
  }

  /// Get all forfeited packages
  /// Get all forfeited packages (that are not yet in a tender)
  Future<List<ForfeitedPackageModel>> getForfeitedPackages() async {
    // 1. Get IDs of packages already in a tender
    final tendersData =
        await supabase.from('tenders').select('forfeited_package_ids');
    final tenderedIds = (tendersData as List)
        .expand((t) => (t['forfeited_package_ids'] as List))
        .map((e) => e.toString())
        .toSet();

    // 1b. Items already in a disposal request — keyed "<packageId>:<itemId>".
    //     A request stores a forfeited_packages row that may be a synthetic
    //     per-item row, so we match on the originating (package_id, item_id)
    //     rather than the raw FP id, plus keep the raw ids for legacy matches.
    final reqData = await supabase.from('disposal_request_items').select(
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
      return items
          .any((i) => !requestedItemKeys.contains('${f.packageId}:${i.id}'));
    }).toList();
  }

  /// All forfeited_packages rows for a given [source] ('abandoned' | 'other' |
  /// 'forfeit'), with package + item detail — used by the yard reports for the
  /// Abandoned / Other pages (the main getForfeitedPackages() is forfeit-only).
  Future<List<ForfeitedPackageModel>> getForfeitedBySource(
      String source) async {
    final data = await supabase
        .from('forfeited_packages')
        .select(
            '*, packages(*, package_items(*), warehouse_entries(*, warehouses(*)))')
        .eq('source', source)
        .order('forfeited_at', ascending: false);
    // Off the UI thread past the threshold: this join carries each row's whole
    // package, its items AND its warehouse entries, so the Abandoned / Other
    // pages parse the deepest structure in the app in one go.
    return parseForfeitedPackages(data as List);
  }

  /// Every forfeited row for one package, keyed by the ITEM it covers.
  ///
  /// ⚠️ Deliberately UNFILTERED, unlike [getForfeitedPackages], which drops a
  /// package the moment it is tendered, requested, sold or destroyed. This
  /// exists for the SR popup, which has to show an item's whole story
  /// including how it ended -- and the filtered list, by design, no longer
  /// contains the items whose story is worth telling.
  ///
  /// Forfeiture is per item, so one package can produce several rows; rows
  /// with no item_id are skipped rather than being pinned to an arbitrary
  /// item.
  Future<Map<String, ForfeitedPackageModel>> getForfeitedByItemForPackage(
      String packageId) async {
    // ⚠️ The valuation embed. `valuation_cost` lives on
    // `disposal_request_items`, not on `forfeited_packages` -- the model
    // reads it from this embed, and without it every row came back with
    // a null valuation. The Perishable popup's one tender round then
    // vanished entirely: a round with no price, no bids and no seal is
    // dropped from the history, so the section showed an outcome with
    // nothing above it. Same omission as `_reTenderInfoForIds` had.
    final data = await supabase
        .from('forfeited_packages')
        .select('*, disposal_request_items!forfeited_package_id(valuation_cost), '
            'packages(*, package_items(*), warehouse_entries(*, warehouses(*)))')
        .eq('package_id', packageId)
        .order('forfeited_at', ascending: false);
    final out = <String, ForfeitedPackageModel>{};
    for (final e in (data as List)) {
      final f = ForfeitedPackageModel.fromJson(e);
      final itemId = f.itemId;
      if (itemId == null) continue;
      // Newest first from the query, so the FIRST row for an item wins -- the
      // most recent forfeiture is the one whose history is current.
      out.putIfAbsent(itemId, () => f);
    }
    return out;
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
      ...(destroyedData as List)
          .map((e) => e['forfeited_package_id'].toString()),
    };
  }

  /// Get forfeited packages where appeal has expired (> 30 days) and not tendered
  Future<List<ForfeitedPackageModel>> getExpiredAppealPackages() async {
    // 1. Get IDs of packages already in a tender
    final tendersData =
        await supabase.from('tenders').select('forfeited_package_ids');
    final tenderedIds = (tendersData as List)
        .expand((t) => (t['forfeited_package_ids'] as List))
        .map((e) => e.toString())
        .toSet();

    // 1b. Get IDs of packages already in a disposal request
    final reqData = await supabase
        .from('disposal_request_items')
        .select('forfeited_package_id');
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
        .where((e) =>
            !tenderedIds.contains(e['id']) && !requestedIds.contains(e['id']))
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

  /// The appeal outcome for every item of one package, keyed by item id.
  ///
  /// An appeal DECISION ends the wait: once the Appeal Directorate has ruled,
  /// the yard may act on those goods immediately, without sitting out the rest
  /// of the 30-day window. Items still on hold are reported too, because a
  /// hold does the opposite — it freezes them even after the window closes.
  ///
  /// Reads `forfeited_packages` directly (all four sources), so it works for
  /// Detain / Abandoned / "Other" goods as well as genuine forfeits.
  Future<Map<String, ItemAppealOutcome>> getItemAppealOutcomes(
      String packageId) async {
    final data = await AuthService._withNetworkRetry(() => supabase
        .from('forfeited_packages')
        .select('*')
        .eq('package_id', packageId));

    final out = <String, ItemAppealOutcome>{};
    for (final e in (data as List)) {
      final f = ForfeitedPackageModel.fromJson(e as Map<String, dynamic>);
      // A package-level row speaks for every item; a per-item row for its own.
      final ids = <String?>[if (f.itemId != null) f.itemId else null];
      for (final id in ids) {
        final decision = f.appealDecisionForItem(id);
        final held = f.heldItemIds.isNotEmpty
            ? f.heldItemIds.contains(id)
            : f.appealHold;
        if (id != null) {
          out[id] = ItemAppealOutcome(decision: decision, onHold: held);
        } else {
          // Package-level: apply to any item that has no row of its own. The
          // per-item map still wins where it names an item.
          for (final entry in f.itemAppealDecisions.entries) {
            out[entry.key] = ItemAppealOutcome(
                decision: f.appealDecisionForItem(entry.key),
                onHold: f.heldItemIds.contains(entry.key));
          }
          out[''] = ItemAppealOutcome(decision: decision, onHold: held);
        }
      }
    }
    return out;
  }

  /// Appeal outcomes for EVERY item across all packages, keyed by item id.
  ///
  /// The per-package variant issues one query per row, which a table cannot
  /// afford; this fetches the lot once so a list can look each row up.
  Future<Map<String, ItemAppealOutcome>> getAllItemAppealOutcomes() async {
    // ⚠️ Read from `item_appeal_outcomes`, which resolves both rules PER
    // ITEM -- and resolves one of them correctly where this could not.
    //
    // This used to be `forfeited_packages.select('*')`: every column of every
    // forfeited row, 171ms, to build a map of two booleans per item. Worse,
    // `appealDecisionForItem` needs the package item COUNT to know whether a
    // package-level decision may stand in for a missing per-item one -- and
    // `select('*')` embeds no package, so `packageDetails` was always null and
    // the multi-item guard could never fire. A decision on one item therefore
    // reported every sibling decided, which is the exact bleed the model
    // documents and defends against.
    //
    // The view (postgres/47) carries the guard, so the four screens reading
    // this now agree with the Appeal portal about what has been ruled.
    //
    // ⚠️ Its OWN view, not the Appeal portal's `appeal_rows`. That one is
    // that portal's feed and is `source = 'forfeit'` only, while a ruling can
    // exist against detained, abandoned and other goods too -- 65 of them on
    // the live data, which would have vanished from these four screens.
    final data = await AuthService._withNetworkRetry(() => supabase
        .from('item_appeal_outcomes')
        .select('item_id, decision, on_hold'));

    final out = <String, ItemAppealOutcome>{};
    for (final e in (data as List)) {
      final m = e as Map<String, dynamic>;
      final itemId = m['item_id']?.toString();
      if (itemId == null || itemId.isEmpty) continue;
      final decision = (m['decision'] as String?)?.trim();
      out[itemId] = ItemAppealOutcome(
        decision: (decision?.isEmpty ?? true) ? null : decision,
        onHold: m['on_hold'] == true,
      );
    }
    return out;
  }

  /// Detain / Abandoned / "Other" goods whose 30-day appeal window is STILL
  /// OPEN, as synthetic [ForfeitedPackageModel]s the Appeal Directorate can
  /// raise an appeal against.
  ///
  /// Genuine forfeits are NOT included — those already have real
  /// `forfeited_packages` rows and the Appeal portal reads them directly.
  /// This covers the other three statuses, which have no such row until a
  /// disposal request is sent, yet are equally open to appeal.
  ///
  /// Cross-yard: the Appeal Directorate reviews every yard (RLS allows it).
  Future<List<ForfeitedPackageModel>> getInAppealNonForfeitPackages() async {
    // Only goods still inside the 30-day window can be appealed, so ask the
    // DATABASE for those rather than downloading every package in the system
    // and discarding most of them here. Without this the query pulled the
    // whole table plus its items, warehouse entries and profile joins on every
    // load, and the portal sat spinning for a minute.
    //
    // Rows with a NULL entry_date fall back to created_at, matching what the
    // loop below does when it computes the real deadline.
    //
    // The cutoff is a DATE, not a timestamp: PostgREST splits `or(...)` on dots,
    // and an ISO timestamp's fractional seconds ("...T11:25:00.000") would cut
    // the filter in half. A date is unambiguous and, since the window is
    // measured in whole days, loses nothing. One extra day of slack keeps any
    // timezone difference between client and server from clipping a row that
    // is still inside the window; the exact check runs in the loop below.
    final cut =
        DateTime.now().subtract(const Duration(days: kAppealWindowDays + 1));
    final cutoff = '${cut.year}-${cut.month.toString().padLeft(2, '0')}-'
        '${cut.day.toString().padLeft(2, '0')}';
    final pkgData = await AuthService._withNetworkRetry(() => supabase
        .from('packages')
        .select(
            '*, package_items(*), warehouse_entries(*, warehouses(*), returned_profile:profiles!returned_by(full_name, badge_number))')
        .or('entry_date.gte.$cutoff,and(entry_date.is.null,created_at.gte.$cutoff)'));

    // Once an appeal is lodged against Detain / Abandoned / "Other" goods a
    // REAL forfeited_packages row exists (`appeal_ensure_forfeited_row`). Load
    // those so the row we emit carries the actual hold / decision and, above
    // all, the real uuid — a synthetic id cannot be released or decided.
    final realRows = await AuthService._withNetworkRetry(() => supabase
        .from('forfeited_packages')
        .select('*')
        .inFilter('source', ['detain', 'abandoned', 'other']));
    final realByKey = <String, Map<String, dynamic>>{};
    for (final e in (realRows as List)) {
      final row = e as Map<String, dynamic>;
      final pkgId = row['package_id']?.toString();
      final itemId = row['item_id']?.toString();
      if (pkgId == null || itemId == null) continue;
      realByKey['$pkgId:$itemId'] = row;
    }

    final out = <ForfeitedPackageModel>[];
    for (final raw in (pkgData as List)) {
      final row = raw as Map<String, dynamic>;
      final pkg = PackageModel.fromJson(row);
      // PackageModel drops `yard`, and an appeal officer belongs to no yard,
      // so AppSession.currentYard is null here — read it off the raw row.
      final pkgYard = row['yard']?.toString();
      final entryDate = pkg.entryDate ?? pkg.createdAt;
      // Only goods still inside the window — once it closes the yard acts on
      // them and there is nothing left to appeal.
      if (!isWithinAppealWindow(entryDate)) continue;
      // Nothing left to appeal once every item has been finalised.
      final allItems = pkg.items;
      if (allItems.isNotEmpty) {
        bool hasFinalEntry(String itemId) => pkg.warehouseEntries.any((e) =>
            e.packageItemId == itemId &&
            (e.returnNotes ?? '').trim().toUpperCase().startsWith('[FINAL:'));
        const terminal = {'sold', 'destroyed', 're-exported', 'released'};
        final finalised = allItems.every((it) =>
            hasFinalEntry(it.id) ||
            terminal.contains((it.status ?? '').trim().toLowerCase()));
        if (finalised) continue;
      }
      final deadline = appealDeadlineFrom(entryDate);

      for (final item in pkg.items) {
        // Genuine forfeits already have their own forfeited_packages row and
        // reach the portal through AppealService.getForfeitedPackages().
        // Listing them again here would duplicate every forfeit row.
        if (pkg.isItemForfeited(item.id)) continue;

        // Which status this item currently sits under decides its label.
        final abandonedEntries = _abandonedEntriesForItem(pkg, item);
        final otherEntries = _otherEntriesForItem(pkg, item);
        final isAbandoned = abandonedEntries.isNotEmpty ||
            _itemIsRequestableAbandoned(pkg, item);
        final isOther =
            otherEntries.isNotEmpty || _itemIsRequestableOther(pkg, item);

        final String source;
        final String reason;
        if (isAbandoned) {
          source = 'abandoned';
          reason = _abandonReasonFor(pkg);
        } else if (isOther) {
          source = 'other';
          reason = _otherReasonFor(pkg);
        } else {
          // Still held in the warehouse under its original status — Detain.
          // isReturned is the authoritative flag; returnedAt can be null on a
          // row that was still marked returned.
          final held = pkg.warehouseEntries
              .where((e) => e.packageItemId == item.id && !e.isReturned)
              .toList();
          if (held.isEmpty) continue;
          source = 'detain';
          reason = pkg.reason ?? 'Detained';
        }

        final real = realByKey['${pkg.id}:${item.id}'];
        if (real != null) {
          // An appeal has already been lodged: use the STORED row so its hold,
          // decision and real uuid come through. Only the package detail is
          // grafted on, since the stored row was fetched without the join.
          final stored = ForfeitedPackageModel.fromJson(real);
          out.add(ForfeitedPackageModel(
            id: stored.id,
            packageId: stored.packageId,
            srNumber: stored.srNumber,
            consigneeName: stored.consigneeName,
            forfeitedAt: stored.forfeitedAt,
            appealDeadline: stored.appealDeadline,
            reason: stored.reason,
            yard: stored.yard ?? pkgYard,
            source: stored.source,
            appealHold: stored.appealHold,
            appealHoldNote: stored.appealHoldNote,
            appealHeldAt: stored.appealHeldAt,
            heldItemIds: stored.heldItemIds,
            appealDecision: stored.appealDecision,
            appealDecisionNote: stored.appealDecisionNote,
            appealDecidedAt: stored.appealDecidedAt,
            itemAppealDecisions: stored.itemAppealDecisions,
            packageDetails: pkg,
            itemId: item.id,
            itemName: item.itemName,
          ));
          continue;
        }

        out.add(ForfeitedPackageModel(
          // Synthetic id — no forfeited_packages row exists yet. Lodging an
          // appeal materialises one (see _materialiseForfeitedRow).
          id: '${pkg.id}:${item.id}:$source',
          packageId: pkg.id,
          srNumber: pkg.srNumber,
          consigneeName: pkg.consigneeName,
          forfeitedAt: entryDate,
          appealDeadline: deadline,
          reason: reason,
          yard: pkgYard ?? AppSession.currentYard,
          source: source,
          packageDetails: pkg,
          itemId: item.id,
          itemName: item.itemName,
        ));
      }
    }
    out.sort((a, b) => a.appealDeadline.compareTo(b.appealDeadline));
    return out;
  }

  /// Forfeited packages whose 30-day appeal window has passed and that are
  /// not yet part of a disposal request — i.e. items a yard can request the
  /// Central Disposal Directorate to dispose of. RLS keeps this to the
  /// caller's own yard.
  /// Goods the yard can send to Central Disposal.
  ///
  /// By default only ACTIONABLE goods are returned: the appeal window has
  /// closed, or the Appeal Directorate has already ruled. Goods on an appeal
  /// hold are always excluded — that appeal is still open.
  ///
  /// With [includePending] the still-in-appeal goods come back too, so the
  /// request dialog can LIST them (greyed out, not selectable) instead of
  /// hiding them. The officer then sees the whole picture and picks what to
  /// send. Holds stay excluded either way.
  Future<List<ForfeitedPackageModel>> getRequestableExpiredPackages(
      {bool includePending = false}) async {
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

    const _nonDisposalDecisions = {
      'RELEASE',
      'RE-EXPORT',
      'OTHER',
      'DESTROY',
      'DESTRUCTION',
      'SUPPOSED TO BE DESTROYED',
    };
    // An item is requestable when it can go to a disposal request: the window
    // passed (yard picks the disposition) OR the Appeal Directorate gave it a
    // SALE decision. NOT requestable when: it is on appeal hold, or it
    // has a per-item RELEASE/RE-EXPORT/OTHER/DESTROY decision.
    bool itemRequestable(ForfeitedPackageModel f, String itemId) {
      final held = f.heldItemIds.isNotEmpty
          ? f.heldItemIds.contains(itemId)
          : f.appealHold;
      if (held) return false;
      final dec = (f.appealDecisionForItem(itemId) ?? '').toUpperCase();
      if (_nonDisposalDecisions.contains(dec)) return false;
      if (f.reason.toUpperCase().contains('DESTROY')) return false;
      // Listing pending goods keeps them in the pool; the dialog greys them
      // out rather than hiding them.
      if (includePending) return true;
      return f.isAppealExpired || dec == 'SALE';
    }

    final baseForfeit = (fpData as List)
        .where((e) => !requestedIds.contains(e['id']))
        .where((e) => !goneIds.contains(e['id'].toString()))
        // Keep the package-level RELEASE/RE-EXPORT/OTHER exclusion only for the
        // legacy package-level decision (no per-item map) — per-item outcomes are
        // filtered per item during expansion below.
        .where((e) {
          final hasPerItem =
              (e['item_appeal_decisions'] as Map?)?.isNotEmpty ?? false;
          if (hasPerItem) return true;
          return !_nonDisposalDecisions.contains(
              ((e['appeal_decision'] as String?) ?? '').toUpperCase());
        })
        .map((e) => ForfeitedPackageModel.fromJson(e))
        // Keep the package if the window passed OR any item carries a decision —
        // per-item actionability is enforced during expansion.
        .where((f) =>
            includePending ||
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

    // ── 2. Abandoned packages (30-day appeal window from entry date) ────────
    // Abandoned packages live in `packages`/`package_items`; they have no
    // forfeited_packages row until requested. Surface them here as synthetic
    // ForfeitedPackageModels (id == package_id, source='abandoned') so the same
    // request dialog/pipeline can pick them up. A package that already has a
    // source='abandoned' FP row is dropped (it's been requested already).
    final pkgData = await AuthService._withNetworkRetry(() => supabase
        .from('packages')
        .select(
            '*, package_items(*), warehouse_entries(*, warehouses(*), returned_profile:profiles!returned_by(full_name, badge_number))'));

    // package_ids already SENT in a disposal request as abandoned.
    //
    // Scoped to disposal_request_items on purpose: an APPEAL also creates a
    // forfeited_packages row now (`appeal_ensure_forfeited_row`), and goods
    // under appeal must stay requestable once their window closes. Keying on
    // the row's mere existence would strand them forever.
    final existingAbandonedFp = await AuthService._withNetworkRetry(() =>
        supabase
            .from('disposal_request_items')
            .select('forfeited_packages!inner(package_id, source)')
            .eq('forfeited_packages.source', 'abandoned'));
    final abandonedFpPkgIds = (existingAbandonedFp as List)
        .map((row) => ((row as Map<String, dynamic>)['forfeited_packages']
                as Map<String, dynamic>)['package_id']
            .toString())
        .toSet();

    // ── 3. "Other"-status packages (30-day appeal window from entry) ────────
    // Track at item level so that only the specific item that was already
    // requested is excluded — other items in the same package remain requestable.
    final existingOtherFp = await AuthService._withNetworkRetry(() => supabase
        .from('disposal_request_items')
        .select('forfeited_packages!inner(package_id, item_id, source)')
        .eq('forfeited_packages.source', 'other'));
    final otherFpItemKeys = (existingOtherFp as List).map((row) {
      final e = (row as Map<String, dynamic>)['forfeited_packages']
          as Map<String, dynamic>;
      final pkgId = e['package_id'].toString();
      final itemId = e['item_id']?.toString();
      return itemId != null ? '$pkgId:$itemId' : pkgId;
    }).toSet();

    // ── 4. DETAINED items already sent ──────────────────────────────────────
    // Tracked per item, like "other": a detain row is created per item, so a
    // sibling item of the same package must stay requestable.
    final existingDetainFp = await AuthService._withNetworkRetry(() => supabase
        .from('disposal_request_items')
        .select('forfeited_packages!inner(package_id, item_id, source)')
        .eq('forfeited_packages.source', 'detain'));
    final detainFpItemKeys = (existingDetainFp as List).map((row) {
      final e = (row as Map<String, dynamic>)['forfeited_packages']
          as Map<String, dynamic>;
      final pkgId = e['package_id'].toString();
      final itemId = e['item_id']?.toString();
      return itemId != null ? '$pkgId:$itemId' : pkgId;
    }).toSet();

    // ── 5. PERISHABLE items already sent ────────────────────────────────────
    final existingPerishableFp = await AuthService._withNetworkRetry(() =>
        supabase
            .from('disposal_request_items')
            .select('forfeited_packages!inner(package_id, item_id, source)')
            .eq('forfeited_packages.source', 'perishable'));
    final perishableFpItemKeys = (existingPerishableFp as List).map((row) {
      final e = (row as Map<String, dynamic>)['forfeited_packages']
          as Map<String, dynamic>;
      final pkgId = e['package_id'].toString();
      final itemId = e['item_id']?.toString();
      return itemId != null ? '$pkgId:$itemId' : pkgId;
    }).toSet();

    // Appeal rulings, keyed by item id — a decision lets goods into this pool
    // before the window closes, a hold keeps them out after it does.
    final appealOutcomes = await getAllItemAppealOutcomes();

    for (final raw in (pkgData as List)) {
      final pkg = PackageModel.fromJson(raw as Map<String, dynamic>);
      final alreadyAbandoned = abandonedFpPkgIds.contains(pkg.id);

      // The 30-day appeal window applies to detained, abandoned and "other"
      // goods too, counted from the ENTRY DATE. While it is open the goods
      // cannot be sent to Central Disposal at all, so they are left out of
      // this pool.
      //
      // …EXCEPT once the Appeal Directorate has ruled. A decision ends the
      // wait — there is nothing left to appeal — so those goods join the pool
      // straight away rather than sitting out the remaining days. Goods on an
      // appeal HOLD stay out either way: that appeal is still open.
      final entryDate = pkg.entryDate ?? pkg.createdAt;
      final decidedItemIds = <String>{
        for (final item in pkg.items)
          if (appealOutcomes[item.id]?.unblocksAction ?? false) item.id,
      };
      // Perishable goods do not wait. They spoil, so an appeal window would
      // outlast the goods themselves -- a package holding any is never skipped
      // for the window, and each perishable item passes it below.
      final hasPerishable =
          pkg.items.any((i) => i.nature == kNaturePerishable);
      if (!includePending &&
          !hasPerishable &&
          isWithinAppealWindow(entryDate) &&
          decidedItemIds.isEmpty) {
        continue;
      }
      final windowDeadline = appealDeadlineFrom(entryDate);
      // Inside the window only the decided items may be sent; once it closes
      // every item that is not on hold may.
      bool itemPassesWindow(String itemId) {
        // A hold always excludes: that appeal is still open.
        if (appealOutcomes[itemId]?.onHold ?? false) return false;
        // A perishable item has no window to pass -- see above.
        final it = pkg.items.where((i) => i.id == itemId).firstOrNull;
        if (it != null && it.nature == kNaturePerishable) return true;
        if (includePending) return true;
        if (!isWithinAppealWindow(entryDate)) return true;
        return decidedItemIds.contains(itemId);
      }

      // One requestable row PER qualifying ITEM+EVENT:
      //   • Abandoned: one row per [ABANDONED] warehouse entry event, id =
      //     "<pkgId>:<itemId>:<entryId>:abandoned" — mirrors the Abandoned
      //     Packages screen which shows one row per event (partial qty events).
      //   • Other: one row per item, id = "<pkgId>:<itemId>:other".
      for (final item in pkg.items) {
        // Check at item level so only the already-requested item is excluded.
        final alreadyOther = otherFpItemKeys.contains('${pkg.id}:${item.id}') ||
            otherFpItemKeys.contains(pkg.id);
        if (!itemPassesWindow(item.id)) continue;

        // Perishable goods take their own path: no warehouse, no window, so
        // none of the branches below apply to them.
        if (item.nature == kNaturePerishable) {
          final alreadySent =
              perishableFpItemKeys.contains('${pkg.id}:${item.id}') ||
                  perishableFpItemKeys.contains(pkg.id);
          if (!alreadySent) {
            result.add(ForfeitedPackageModel(
              id: '${pkg.id}:${item.id}:perishable',
              packageId: pkg.id,
              srNumber: pkg.srNumber,
              consigneeName: pkg.consigneeName,
              forfeitedAt: pkg.entryDate ?? pkg.createdAt,
              // Already open: nothing is waiting on it.
              appealDeadline: pkg.entryDate ?? pkg.createdAt,
              reason: 'Perishable goods',
              yard: AppSession.currentYard,
              source: 'perishable',
              packageDetails: pkg,
              itemId: item.id,
              itemName: item.itemName,
            ));
          }
          continue;
        }

        if (!alreadyAbandoned) {
          final abandonedEntries = _abandonedEntriesForItem(pkg, item);
          for (final entry in abandonedEntries) {
            result.add(ForfeitedPackageModel(
              id: '${pkg.id}:${item.id}:${entry.id}:abandoned',
              packageId: pkg.id,
              srNumber: pkg.srNumber,
              consigneeName: pkg.consigneeName,
              forfeitedAt: pkg.createdAt,
              appealDeadline: windowDeadline,
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
              appealDeadline: windowDeadline,
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
              appealDeadline: windowDeadline,
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
              appealDeadline: windowDeadline,
              reason: _otherReasonFor(pkg),
              yard: AppSession.currentYard,
              source: 'other',
              packageDetails: pkg,
              itemId: item.id,
              itemName: item.itemName,
            ));
          }
        }

        // Detained goods. Detention is a HOLDING status, not a disposition —
        // there is no `[DETAIN]` event to key off — so one row per item.
        final alreadyDetain =
            detainFpItemKeys.contains('${pkg.id}:${item.id}') ||
                detainFpItemKeys.contains(pkg.id);
        if (!alreadyDetain && _itemIsRequestableDetain(pkg, item)) {
          result.add(ForfeitedPackageModel(
            id: '${pkg.id}:${item.id}:detain',
            packageId: pkg.id,
            srNumber: pkg.srNumber,
            consigneeName: pkg.consigneeName,
            forfeitedAt: pkg.createdAt,
            appealDeadline: windowDeadline,
            reason: _detainReasonFor(pkg),
            yard: AppSession.currentYard,
            source: 'detain',
            packageDetails: pkg,
            itemId: item.id,
            itemName: item.itemName,
          ));
        }
      }
    }

    return result;
  }

  /// What this yard is holding RIGHT NOW, and what is waiting on someone.
  ///
  /// ⚠️ The dashboard could not answer "what is in my yard?".
  ///
  /// Its top row was five "today" cards — forfeited today, abandoned today,
  /// destroyed today, released today — which read 0 on any day nothing
  /// happened, which is most days. Meanwhile the yard held 226 items across
  /// four Held Goods pages and the dashboard said nothing about any of them.
  ///
  /// These read the same views the nav rail's own pages read, so a figure here
  /// and the page it links to cannot disagree.
  /// Storage charges still RUNNING in this yard, and how many entries carry
  /// them.
  ///
  /// ⚠️ This was computed in Dart from `livePackagesProvider` -- every
  /// package in the yard with its items and warehouse entries -- walked to
  /// add up charges. The same whole-table fetch the rest of the app has been
  /// moved off, on the one figure that changes every single day.
  ///
  /// ⚠️ NOT `sr_financials.sr_charges`. That is the whole bill ever
  /// raised, returned goods included (368,984,450 on live data); this is
  /// what is still ticking (242,304,500). Two different questions, both
  /// wanted.
  Future<({double accrued, int entries})> getAccruedStorage() async {
    final yard = AppSession.currentYard;
    var q = supabase
        .from('accrued_storage_by_yard')
        .select('accrued, live_entries');
    if (yard != null && yard.isNotEmpty) {
      q = q.or('yard.eq.$yard,sr_number.ilike.%/$yard/%');
    }
    final rows = await AuthService._withNetworkRetry(() => q);
    var total = 0.0;
    var entries = 0;
    for (final e in (rows as List)) {
      final m = e as Map<String, dynamic>;
      total += parseDbNum(m['accrued']) ?? 0;
      entries += parseDbInt(m['live_entries']) ?? 0;
    }
    return (accrued: total, entries: entries);
  }

  Future<Map<String, int>> getYardHoldingCounts() async {
    final yard = AppSession.currentYard;

    /// ⚠️ The SR NUMBER's yard segment as well as the yard column.
    ///
    /// A row filed by one directorate can sit in another's yard, and matching
    /// the column alone hides it from the yard actually holding the goods —
    /// the rule every cross-yard page in the app already applies.
    PgQuery inYard(PgQuery q) => (yard == null || yard.isEmpty)
        ? q
        : q.or('yard.eq.$yard,sr_number.ilike.%/$yard/%');

    Future<int> countOf(String view,
        [PgQuery Function(PgQuery)? narrow]) async {
      var q = inYard(supabase.from(view));
      if (narrow != null) q = narrow(q);
      return await AuthService._withNetworkRetry(() => q.count()) as int;
    }

    final detained =
        await countOf('held_goods_rows', (q) => q.eq('kind', 'DETAINED'));
    final abandoned =
        await countOf('held_goods_rows', (q) => q.eq('kind', 'ABANDONED'));
    final other = await countOf('held_goods_rows', (q) => q.eq('kind', 'OTHER'));
    final forfeited = await countOf('forfeit_rows');

    // ⚠️ Perishables AWAITING THE DG, not every perishable. The page lists
    // them all; what a yard admin needs from a dashboard is the ones that are
    // stuck — marked unsold at tender, not sold, no ruling yet.
    final perishableAwaiting = await countOf(
        'perishable_rows',
        (q) =>
            q.eq('marked_unsold', true).isNull('proposal').eq('sold', false));

    // Waiting on the Valuation Directorate: requests this yard has sent that
    // nobody has costed yet.
    //
    // ⚠️ Its own narrowing. `valuation_rows` is one row per REQUEST, and a
    // request can hold goods from several yards — so it carries pipe-wrapped
    // `sr_numbers` and `item_yards` rather than the single `sr_number` the
    // per-item views have. Reusing `inYard` here asks for a column that does
    // not exist.
    // ⚠️ In ITEMS, like every other figure on the dashboard.
    //
    // `valuation_rows` is one row per REQUEST, so counting rows gave 9 while
    // the Valuation Directorate had 33 goods to cost -- and every card beside
    // it counts goods. `pending_count` is the items in each request.
    final valuationRows = await AuthService._withNetworkRetry(() {
      var q = supabase.from('valuation_rows').select('pending_count');
      if (yard != null && yard.isNotEmpty) {
        q = q.or('yard.eq.$yard,item_yards.ilike.%|$yard|%,'
            'sr_numbers.ilike.%/$yard/%');
      }
      return q;
    });
    var awaitingValuation = 0;
    for (final e in (valuationRows as List)) {
      awaitingValuation +=
          parseDbInt((e as Map<String, dynamic>)['pending_count']) ?? 0;
    }

    // Waiting on Central Disposal: still re-tenderable, or out of road.
    final reTenderable = await countOf('unsold_retender_pool');
    final exhausted = await countOf('exhausted_unsold');

    return {
      'detained': detained,
      'abandoned': abandoned,
      'other': other,
      'forfeited': forfeited,
      'perishableAwaiting': perishableAwaiting,
      'awaitingValuation': awaitingValuation,
      'reTenderable': reTenderable,
      'exhausted': exhausted,
    };
  }

  /// Forfeit → disposal lifecycle counts for the current yard, used by the
  /// Admin Dashboard summary card. Counts are package-level (one forfeited
  /// package = one unit).
  /// The lifecycle counts the yard dashboard shows.
  ///
  /// ⚠️ Every figure here counts GOODS, not events. That distinction
  /// broke three of them:
  ///
  ///   * appeals were counted from `forfeited_packages` where source is
  ///     'forfeit', so the rulings on detained, abandoned and other goods --
  ///     the majority of them -- were invisible. 3 held and 9 decided, where
  ///     the yard actually had 26 and 77.
  ///
  ///   * tender rows are ATTEMPTS. A package that fails four times has four
  ///     rows, so "Unsold 109" was 109 failed attempts by 27 packages. An
  ///     officer reading it as 109 lots of goods has the wrong number by a
  ///     factor of four.
  ///
  ///   * valuation was counted in REQUESTS while everything beside it was
  ///     counted in goods.
  /// The lifecycle counts the yard dashboard shows.
  ///
  /// ⚠️ Every figure counts GOODS, and every figure is one an officer
  /// can act on. Both took several passes to get right:
  ///
  ///   * appeals were counted from forfeits alone, missing the detained,
  ///     abandoned and other goods that raise them too
  ///   * tender rows are ATTEMPTS, so a package that failed four times was
  ///     counted four times
  ///   * "Sent for destruction" was structurally always 0
  ///   * "Forwarded" counted goods the panel already showed under At Tender
  Future<Map<String, dynamic>> getForfeitLifecycleSummary() async {
    final yard = AppSession.currentYard;

    // ── Appeal Directorate ────────────────────────────────────────────
    //
    // ⚠️ Only goods STILL IN A WAREHOUSE.
    //
    // A ruling on goods that have since left the yard is history: the
    // directorate ruled, the yard acted, the goods are gone. Counting those
    // gave 26 held and 77 decided, of which 15 and 31 are goods the yard is
    // actually still holding -- and only those are anybody's outstanding
    // work.
    //
    // `warehouse_rows` is the same view the Warehouses page reads, so a hold
    // counted here and a row on that page cannot disagree about what is
    // present.
    final heldItemRows = await AuthService._withNetworkRetry(() {
      var q = supabase.from('warehouse_rows').select('package_item_id');
      if (yard != null && yard.isNotEmpty) {
        // ⚠️ `warehouse_rows` carries the SR NUMBER but no yard column
        // -- a warehouse belongs to a facility, not a directorate, and the
        // view is built for one facility's tab. The SR number's own segment
        // is the yard here.
        q = q.ilike('sr_number', '%/$yard/%');
      }
      return q;
    });
    final inWarehouse = <String>{
      for (final e in (heldItemRows as List))
        if ((e as Map<String, dynamic>)['package_item_id'] != null)
          e['package_item_id'].toString()
    };

    var outcomeQ =
        supabase.from('item_appeal_outcomes').select('item_id, decision, on_hold');
    if (yard != null && yard.isNotEmpty) {
      // ⚠️ The view carries `yard` and `sr_number` for exactly this: it
      // is a VIEW, so PostgREST has no foreign key to embed through, and a
      // `package_items!inner(...)` join fails to resolve.
      outcomeQ = outcomeQ.or('yard.eq.$yard,sr_number.ilike.%/$yard/%');
    }
    final outcomeRows = await AuthService._withNetworkRetry(() => outcomeQ);
    int appealHold = 0;
    int appealDecided = 0;
    for (final e in (outcomeRows as List)) {
      final m = e as Map<String, dynamic>;
      final itemId = m['item_id']?.toString();
      if (itemId == null || !inWarehouse.contains(itemId)) continue;
      if (m['on_hold'] == true) appealHold++;
      final dec = (m['decision'] as String?)?.trim();
      if (dec != null && dec.isNotEmpty) appealDecided++;
    }

    // ── Sent to Central Disposal ──────────────────────────────────────
    //
    // ⚠️ Two figures, and neither is what was here before.
    //
    // "Sent for destruction" was structurally always 0: a yard raises a
    // disposal request for SALE, and goods reach destruction another way
    // entirely -- a DG ruling, or a perishable that failed at tender. All 39
    // destruction items in this yard arrived with no request behind them. A
    // tile that can only ever read 0 takes space and teaches nothing.
    //
    // "Forwarded" counted all 135 the yard had ever sent on, of which 113
    // were already at tender and counted again in the group below. What is
    // genuinely in flight is the 22 that have been forwarded and not yet
    // placed anywhere.
    final reqRows = await AuthService._withNetworkRetry(() => supabase
        .from('disposal_request_items')
        .select('forfeited_package_id, disposition, forwarded, '
            'forfeited_packages!inner(yard)')
        .eq('forfeited_packages.yard', yard));
    final forwardedFps = <String>{};
    int requestedSale = 0;
    for (final r in (reqRows as List)) {
      final m = r as Map<String, dynamic>;
      if (m['forwarded'] == true) {
        forwardedFps.add(m['forfeited_package_id'].toString());
      } else if ((m['disposition'] as String?)?.toLowerCase() == 'sale') {
        requestedSale++;
      }
    }

    // ── At tender ─────────────────────────────────────────────────────
    //
    // ⚠️ Per PACKAGE, on its LATEST round. tender_sale_items rows are
    // attempts: a package that fails four times has four of them, so
    // counting rows reported 109 unsold when 27 lots of goods were unsold.
    // And a package that failed twice and then sold is SOLD -- its failures
    // are history, not an outcome.
    final tsRows = await AuthService._withNetworkRetry(() => supabase
        .from('tender_sale_items')
        .select('forfeited_package_id, sold, unsold, is_delivered, '
            'tender_sales!inner(created_at)')
        .eq('yard', yard));
    final everSold = <String>{};
    final deliveredFps = <String>{};
    final atTender = <String>{};
    final latestAt = <String, DateTime>{};
    final latestOutcome = <String, String>{};
    for (final e in (tsRows as List)) {
      final m = e as Map<String, dynamic>;
      final fpId = m['forfeited_package_id'].toString();
      atTender.add(fpId);
      if (m['sold'] == true) {
        everSold.add(fpId);
        if (m['is_delivered'] == true) deliveredFps.add(fpId);
      }
      final sale = m['tender_sales'] as Map<String, dynamic>?;
      final at = parseDbDate(sale?['created_at']);
      if (at == null) continue;
      final seen = latestAt[fpId];
      if (seen == null || at.isAfter(seen)) {
        latestAt[fpId] = at;
        latestOutcome[fpId] = m['sold'] == true
            ? 'sold'
            : (m['unsold'] == true ? 'unsold' : 'undecided');
      }
    }
    final int sold = everSold.length;
    final int soldDelivered = deliveredFps.length;
    final int soldAwaitingDelivery = sold - soldDelivered;
    int unsold = 0, undecided = 0;
    latestOutcome.forEach((fpId, outcome) {
      if (everSold.contains(fpId)) return;
      if (outcome == 'unsold') {
        unsold++;
      } else if (outcome == 'undecided') {
        undecided++;
      }
    });

    // ⚠️ Read for its IDS alone -- which packages are on the
    // destruction list, so "forwarded and not yet placed" can exclude them.
    //
    // Its counts are deliberately NOT shown. `destruction_items` says 16
    // destroyed where the Destroyed Goods page says 17, because one package
    // reached destroyed through a warehouse entry tagged [FINAL:DESTROYED]
    // with no destruction_items row behind it at all. A dashboard tile that
    // opens a page showing a different number is worse than no tile, so the
    // destroyed figure comes from `disposition_rows` -- the page's own view.
    final destRows = await AuthService._withNetworkRetry(() => supabase
        .from('destruction_items')
        .select('forfeited_package_id')
        .eq('yard', yard));
    final inDestruction = <String>{
      for (final r in (destRows as List))
        (r as Map<String, dynamic>)['forfeited_package_id'].toString()
    };
    final int forwardedNotPlaced = forwardedFps
        .where((fp) => !atTender.contains(fp) && !inDestruction.contains(fp))
        .length;

    // ⚠️ Final outcome, from `disposition_rows` -- the SAME view the
    // Sold / Destroyed / Re-exported pages page through, so a figure here
    // and a row count there cannot disagree.
    //
    // Each tag splits by DELIVERY, because a lot handed over is finished
    // and one still standing in the yard is not. Delivery is NULL where
    // there is no hand-over step (an entry tagged final with no tender,
    // destruction or proposal row behind it) -- null is not false, and
    // counting it as pending would say goods are awaiting collection that
    // nobody is coming for. Those rows are the tag's total minus the two.
    final finalRows = await AuthService._withNetworkRetry(() => supabase
        .from('disposition_rows')
        .select('final_tag, delivered, is_destroyed')
        .eq('yard', yard)
        .inFilter('final_tag', ['SOLD', 'DESTROYED', 'RE-EXPORTED']));
    final outcomeTotals = <String, int>{};
    final outcomeDelivered = <String, int>{};
    final outcomePending = <String, int>{};
    int destroyedDone = 0, destroyedAwaiting = 0;
    for (final r in (finalRows as List)) {
      final m = r as Map<String, dynamic>;
      final tag = m['final_tag']?.toString();
      if (tag == null) continue;
      outcomeTotals[tag] = (outcomeTotals[tag] ?? 0) + 1;
      if (tag == 'DESTROYED') {
        // ⚠️ Destroyed splits by WHETHER IT HAS BEEN DESTROYED, never
        // by delivery. Nothing is handed over to be burnt -- 23 of the 39
        // have no delivery state at all, so a delivered/pending split
        // would say 9 and 7 of 39 and leave the reader to wonder about
        // the other 23. The question this page answers is done or not.
        if (m['is_destroyed'] == true) {
          destroyedDone++;
        } else {
          destroyedAwaiting++;
        }
        continue;
      }
      final d = m['delivered'];
      if (d == true) {
        outcomeDelivered[tag] = (outcomeDelivered[tag] ?? 0) + 1;
      } else if (d == false) {
        outcomePending[tag] = (outcomePending[tag] ?? 0) + 1;
      }
    }

    // ⚠️ Top Management's rulings on goods nothing could sell -- the
    // rail's "Final Outcomes" section, one page each, all six reading
    // `unsold_proposals.proposal`.
    //
    // ⚠️ The rail lists FIVE pages here; the panel shows four. Re-export
    // is the exception: its 2 ruled goods are a SUBSET of the 19 counted
    // under RE-EXPORTED above, so a tile of its own would count the same
    // goods twice on one panel. Where that split matters it already exists
    // -- the Re-exported Goods page carries a Decided By column, because
    // the difference is between ROWS on one page, not between two counts.
    //
    // `delivered` here is NOT NULL DEFAULT false, so every proposal is
    // delivered or pending -- no third state, unlike `disposition_rows`.
    final proposalRows = await AuthService._withNetworkRetry(() => supabase
        .from('unsold_proposals')
        .select('proposal, delivered')
        .eq('yard', yard));
    final proposalTotals = <String, int>{};
    final proposalDelivered = <String, int>{};
    for (final r in (proposalRows as List)) {
      final m = r as Map<String, dynamic>;
      final kind = m['proposal']?.toString();
      if (kind == null) continue;
      proposalTotals[kind] = (proposalTotals[kind] ?? 0) + 1;
      if (m['delivered'] == true) {
        proposalDelivered[kind] = (proposalDelivered[kind] ?? 0) + 1;
      }
    }

    // Next scheduled tender-sale date (a sale_date today or in the future).
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final nextSale = await AuthService._withNetworkRetry(() => supabase
        .from('tender_sales')
        .select('sale_date')
        .eq('yard', yard)
        .gte('sale_date', today)
        .order('sale_date', ascending: true)
        .limit(1)
        .maybeSingle());
    // `date` comes back as a DateTime from the local driver and as a String
    // from Supabase; normalise to the yyyy-MM-dd the UI expects.
    final nextSaleRaw = nextSale?['sale_date'];
    final nextTenderSaleDate = nextSaleRaw == null
        ? null
        : (parseDbDate(nextSaleRaw)?.toIso8601String().split('T').first ??
            nextSaleRaw.toString());

    return {
      'appealHold': appealHold,
      'appealDecided': appealDecided,
      'requestedSale': requestedSale,
      'forwardedNotPlaced': forwardedNotPlaced,
      'tenderSold': sold,
      'soldDelivered': soldDelivered,
      'soldAwaitingDelivery': soldAwaitingDelivery,
      'tenderUnsold': unsold,
      'tenderUndecided': undecided,
      'outcomeSoldTotal': outcomeTotals['SOLD'] ?? 0,
      'outcomeSoldDelivered': outcomeDelivered['SOLD'] ?? 0,
      'outcomeSoldPending': outcomePending['SOLD'] ?? 0,
      'outcomeDestroyedTotal': outcomeTotals['DESTROYED'] ?? 0,
      'outcomeDestroyedDone': destroyedDone,
      'outcomeDestroyedAwaiting': destroyedAwaiting,
      // The Disposed page's re-export: goods that left the country by ANY
      // route, only 2 of the 19 from a DG ruling. Kept SEPARATE from the
      // proposal figure below, which is a different page.
      'outcomeReexportTotal': outcomeTotals['RE-EXPORTED'] ?? 0,
      'outcomeReexportDelivered': outcomeDelivered['RE-EXPORTED'] ?? 0,
      'outcomeReexportPending': outcomePending['RE-EXPORTED'] ?? 0,
      // Top Management's rulings, each with its delivery split.
      //
      // ⚠️ FOUR, not the rail's five. `re_export` is left out because
      // its goods are already counted under RE-EXPORTED above -- measured,
      // not assumed: both re_export proposals in this yard resolve to a
      // `disposition_rows` row carrying that tag, while auction,
      // government_use, convert and remove_from_premises resolve to none at
      // all. Emitting it would put the same goods on the panel twice.
      for (final kind in const [
        'government_use',
        'auction',
        'convert',
        'remove_from_premises',
      ]) ...{
        'proposal_${kind}_total': proposalTotals[kind] ?? 0,
        'proposal_${kind}_delivered': proposalDelivered[kind] ?? 0,
        'proposal_${kind}_pending':
            (proposalTotals[kind] ?? 0) - (proposalDelivered[kind] ?? 0),
      },
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
    final entries = p.warehouseEntries.where((e) => e.packageItemId == item.id);
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

  /// True if a single item is DETAINED and can be sent in a disposal request.
  ///
  /// Detention is the yard's holding status: the goods sit under inquiry with
  /// no disposition recorded yet. Unlike Abandoned or "Other" there is no
  /// `[DETAIN]` disposition event — the item simply carries a detain status and
  /// has not been finalised, released or moved on to another status.
  bool _itemIsRequestableDetain(PackageModel p, PackageItem item) {
    const detainStatuses = {'detain', 'detained', 'held'};
    if (!detainStatuses.contains(item.status.trim().toLowerCase())) {
      return false;
    }
    return !p.warehouseEntries
        .where((e) => e.packageItemId == item.id)
        .any((e) {
      final note = (e.returnNotes ?? '').trim().toUpperCase();
      return note.startsWith('[FINAL:') ||
          note.startsWith('[ABANDONED]') ||
          note.startsWith('[OTHER]') ||
          note.startsWith('[FORFEIT');
    });
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
            (e.returnNotes ?? '')
                .trim()
                .toUpperCase()
                .startsWith('[ABANDONED]'))
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
    final entries = p.warehouseEntries.where((e) => e.packageItemId == item.id);
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
    'detain',
    'detained',
    'held',
    'forfeit',
    'forfiet',
    'forfeited',
    'confiscated',
    'abandoned',
    'released',
    'returned',
    'cleared',
    're-export',
    're-exported',
    'reexport',
    'destroy',
    'destroyed',
    'sold',
    'sale',
    'inspecting',
    'pending',
    '',
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

  /// Why a DETAINED package is being disposed of. Prefers the reason recorded
  /// against the goods, falling back to the standard detention wording.
  String _detainReasonFor(PackageModel p) {
    for (final i in p.items) {
      final r = (i.reasons ?? '').trim();
      if (r.isNotEmpty) return r;
    }
    for (final e in p.warehouseEntries) {
      final r = (e.holdReason).trim();
      if (r.isNotEmpty) return r;
    }
    return 'Detained pending inquiry';
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
        final parentFp =
            ForfeitedPackageModel.fromJson(parentRaw as Map<String, dynamic>);
        // Resolve the partial forfeit qty from the named warehouse entry.
        int? forfeitEntryQty;
        if (forfeitEntryId != null) {
          final matches =
              (parentFp.packageDetails?.warehouseEntries ?? const [])
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
      final reason = switch (source) {
        'other' => _otherReasonFor(pkg),
        // A detained package is held pending inquiry; that is what the yard
        // is acting on when it sends the goods for sale or destruction.
        'detain' => _detainReasonFor(pkg),
        _ => _abandonReasonFor(pkg),
      };
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
            // The 30-day appeal window applies to EVERY status, not just
            // forfeit. It runs from the goods' entry date, so a package that
            // has been in the yard for months is actionable immediately while
            // a fresh one stays frozen. (This used to be set to YESTERDAY,
            // which skipped the window for abandoned / "other" goods.)
            'appeal_deadline':
                appealDeadlineFrom(pkg.entryDate ?? pkg.createdAt)
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
    return [
      for (final e in (data as List))
        TenderModel.fromJson(e as Map<String, dynamic>)
    ];
  }

  /// Create a new tender and delete associated forfeited packages
  Future<TenderModel> createTender({
    required String tenderNumber,
    required DateTime tenderDate,
    required List<String> forfeitedPackageIds,
    DateTime? saleDate,
    String? saleTime,
    /// Sale CLOSE time. The valuation stays sealed until it passes.
    String? saleEndTime,
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
          'sale_end_time': saleEndTime,
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
      result
          .add(ReTenderInfo(forfeited: f, tenders: eligible[f.id] ?? const []));
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
              'p_receipt':
                  (receiptNumber == null || receiptNumber.trim().isEmpty)
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
    return [
      for (final e in (data as List))
        TenderDisposalModel.fromJson(e as Map<String, dynamic>)
    ];
  }
}

// ── Disposal Directorate Service ───────────────────────────────
// Central Disposal Directorate users can read SOLD packages across ALL yards
// (cross-yard RLS) and manage Tender Sale records.

class DisposalService {
  // ── Financial expenses (Top Management Directorate Financials tab) ───────────────────────

  /// Every recorded outgoing, newest first.
  Future<List<FinancialExpenseModel>> getFinancialExpenses() async {
    final rows = await AuthService._withNetworkRetry(() => supabase
        .from('financial_expenses')
        .select('*')
        .order('incurred_on', ascending: false));
    return (rows as List)
        .map((e) => FinancialExpenseModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Record one outgoing against a GOODS ITEM. [kind] is a key of
  /// `kRecordableExpenseKinds` — a refund is never recorded, it is derived
  /// from what is left of the item's destroying deposit.
  ///
  /// Re-posting the same kind for the same item OVERWRITES it rather than
  /// adding a second row: a unique index enforces one destruction cost and one
  /// advertising cost per item, so a correction should replace the figure
  /// instead of double-counting it against the deposit.
  Future<void> addFinancialExpense({
    required String kind,
    required double amount,
    String? description,
    String? yard,
    String? srNumber,
    String? packageItemId,
    DateTime? incurredOn,
  }) async {
    final d = incurredOn ?? DateTime.now();
    final row = {
      'kind': kind,
      'amount': amount,
      'description': (description != null && description.trim().isNotEmpty)
          ? description.trim()
          : null,
      if (yard != null) 'yard': yard,
      if (srNumber != null && srNumber.trim().isNotEmpty)
        'sr_number': srNumber.trim(),
      if (packageItemId != null) 'package_item_id': packageItemId,
      'incurred_on': '${d.year}-${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}',
      'created_by': supabase.auth.currentUser?.id,
    };

    await AuthService._withNetworkRetry(() => packageItemId == null
        ? supabase.from('financial_expenses').insert(row)
        // Matches financial_expenses_item_kind_uniq.
        : supabase
            .from('financial_expenses')
            .upsert(row, onConflict: 'package_item_id,kind'));
  }

  Future<void> deleteFinancialExpense(String id) async {
    await AuthService._withNetworkRetry(
        () => supabase.from('financial_expenses').delete().eq('id', id));
  }

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
    final tendersData =
        await supabase.from('tenders').select('forfeited_package_ids');
    final tenderedIds = (tendersData as List)
        .expand((t) => (t['forfeited_package_ids'] as List))
        .map((e) => e.toString())
        .toSet();

    // 1b. Get IDs of packages already in a disposal request
    final reqData = await supabase
        .from('disposal_request_items')
        .select('forfeited_package_id');
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
      ...(destroyedData as List)
          .map((e) => e['forfeited_package_id'].toString()),
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

  /// The sale figures the FINANCIAL ledger needs, and only those.
  ///
  /// ⚠️ [getTenderSales] is the heaviest query in the app -- every sale,
  /// its items, their forfeited rows, those rows' PACKAGES, and every package
  /// item and warehouse entry underneath, five levels deep.
  ///
  /// `buildSrFinancials` reads four things off each item: whether it sold, what
  /// it sold for, its applied taxes, and the forfeited row's item id and SR
  /// number. Nothing below that. So this stops at the forfeited row.
  Future<List<TenderSaleModel>> getTenderSalesForLedger() async {
    final data = await AuthService._withNetworkRetry(() => supabase
        .from('tender_sales')
        // ⚠️ Named columns, not `*`, for the same reason
        // [getPackagesForLedger] names its own: the roll-up reads four fields
        // off each item -- sold, sold_price, applied_taxes, and the forfeited
        // row's item id and SR number -- and `*` brings a dozen more for the
        // driver to decode.
        //
        // The forfeited columns beyond item_id/sr_number are there because
        // ForfeitedPackageModel.fromJson casts them non-null; trimming them
        // throws "type 'Null' is not a subtype of type 'String'" at parse
        // time, which is how that was found the first time.
        .select('id, sale_number, sale_date, sale_time, sale_end_time, '
            'tender_type, yard, created_at, '
            'tender_sale_items(id, tender_sale_id, forfeited_package_id, '
            'yard, sold, sold_price, applied_taxes, '
            'forfeited_packages(id, item_id, sr_number, package_id, '
            'consignee_name, forfeited_at, appeal_deadline))')
        .order('created_at', ascending: false));
    return (data as List).map((e) => TenderSaleModel.fromJson(e)).toList();
  }

  Future<List<TenderSaleModel>> getTenderSales() async {
    final data = await AuthService._withNetworkRetry(() => supabase
        .from('tender_sales')
        .select(
            '*, profiles!created_by(full_name), tender_sale_items(*, forfeited_packages(*, disposal_request_items!forfeited_package_id(valuation_cost), packages(*, package_items(*), warehouse_entries(*, warehouses(*)))))')
        .order('created_at', ascending: false));
    return (data as List).map((e) => TenderSaleModel.fromJson(e)).toList();
  }

  /// One page of Tender Sales, chosen and filtered in SQL.
  ///
  /// ⚠️ [getTenderSales] is the heaviest query in the app — every sale with its
  /// items, their forfeited rows, those rows' packages, and every package item
  /// and warehouse entry underneath. Fine for one yard; Central Disposal shows
  /// all twenty-eight.
  ///
  /// The `tender_sale_summary` view (postgres/26) decides WHICH sales and in
  /// what order, then the full objects are loaded for that page alone.
  ///
  /// ⚠️ [onlyPending] hides sales with nothing left to act on — every item
  /// marked. There is no second half to that rule any more: a sale used to
  /// leave the page when a working-day window closed, which let a public
  /// holiday decide what an officer could see.
  Future<({List<TenderSaleModel> rows, int total})> getTenderSalesPaged({
    required int offset,
    required int limit,
    String? search,
    String? yardFilter,
    bool onlyPending = false,

    /// The yard page's date-range and year filters.
    ///
    /// ⚠️ In SQL, like every other filter here. Applied to a fetched page they
    /// would narrow the twenty rows on screen while the pager went on counting
    /// the sales they had just removed.
    DateTime? dateStart,
    DateTime? dateEnd,
    String? year,
  }) async {
    PgQuery narrow(PgQuery q) {
      if (onlyPending) q = q.eq('has_pending', true);
      final s = search?.trim() ?? '';
      if (s.isNotEmpty) {
        // The SR numbers and consignees a sale TOUCHES, joined into one text
        // column each by the view — see its header.
        q = q.or('sale_number.ilike.%$s%,sr_numbers.ilike.%$s%,'
            'consignees.ilike.%$s%');
      }
      if (yardFilter != null && yardFilter.isNotEmpty) {
        // ⚠️ Any ITEM's yard, not the sale's own: a sale can mix items from a
        // multi-directorate yard, and the sale-level code cannot tell them
        // apart. The view pipe-wraps each value so this cannot match across
        // two neighbouring yards.
        q = q.or('item_yards.ilike.%|$yardFilter|%,'
            'sr_numbers.ilike.%/$yardFilter/%');
      }
      if (dateStart != null) {
        final from = DateTime(dateStart.year, dateStart.month, dateStart.day);
        q = q.gte('sale_date', from.toIso8601String());
      }
      if (dateEnd != null) {
        final to =
            DateTime(dateEnd.year, dateEnd.month, dateEnd.day, 23, 59, 59);
        q = q.lte('sale_date', to.toIso8601String());
      }
      if (year != null && year.isNotEmpty) {
        // ⚠️ A sale with NO date matched no year before and must not start
        // matching one now — so the range, not a string test that a null
        // would slip through.
        q = q.gte('sale_date', '$year-01-01');
        q = q.lte('sale_date', '$year-12-31T23:59:59');
      }
      return q;
    }

    final idRows = await AuthService._withNetworkRetry(() =>
        narrow(supabase.from('tender_sale_summary').select('id'))
            .order('created_at', ascending: false)
            .range(offset, offset + limit - 1));
    final total = await AuthService._withNetworkRetry(
        () => narrow(supabase.from('tender_sale_summary')).count());

    final ids = [
      for (final e in (idRows as List))
        (e as Map<String, dynamic>)['id'].toString()
    ];
    if (ids.isEmpty) {
      return (rows: const <TenderSaleModel>[], total: total as int);
    }

    // The heavy fetch, for this page's sales only.
    final data = await AuthService._withNetworkRetry(() => supabase
        .from('tender_sales')
        .select(
            '*, profiles!created_by(full_name), tender_sale_items(*, forfeited_packages(*, disposal_request_items!forfeited_package_id(valuation_cost), packages(*, package_items(*), warehouse_entries(*, warehouses(*)))))')
        .inFilter('id', ids)
        .order('created_at', ascending: false));
    final byId = {
      for (final e in (data as List))
        (e as Map<String, dynamic>)['id'].toString(): TenderSaleModel.fromJson(e)
    };
    // Keep the view's order — re-sorting here would disagree with the page
    // boundaries the query used.
    return (
      rows: [for (final id in ids) if (byId[id] != null) byId[id]!],
      total: total as int,
    );
  }

  /// The years the year filter offers, from the sale dates themselves.
  ///
  /// ⚠️ Its own query over ALL sales. Derived from a page, the dropdown
  /// would offer only the years that happen to be on screen -- and picking a
  /// year that is not there is how an officer concludes the records are gone.
  Future<List<String>> getTenderSaleYears() async {
    final data = await AuthService._withNetworkRetry(() => supabase
        .from('tender_sale_summary')
        .select('sale_date')
        .order('sale_date', ascending: false));
    final years = <String>{};
    for (final e in (data as List)) {
      final d = parseDbDate((e as Map<String, dynamic>)['sale_date']);
      if (d != null) years.add(d.year.toString());
    }
    final out = years.toList()..sort((a, b) => b.compareTo(a));
    return out;
  }

  /// The ids of sales that RE-TENDER goods from an earlier sale.
  ///
  /// ⚠️ Its own query, over ALL sales. The app used to derive this by scanning
  /// the full list in memory, which a paged list no longer has — and deriving
  /// it from one page would mark a sale as new simply because its predecessor
  /// was on the page before.
  Future<Set<String>> getRetenderSaleIds() async {
    final data = await AuthService._withNetworkRetry(() => supabase
        .from('tender_sale_summary')
        .select('id')
        .eq('is_retender', true));
    return {
      for (final e in (data as List))
        (e as Map<String, dynamic>)['id'].toString()
    };
  }

  /// [includePerishable] is false everywhere except the DG's own perishable
  /// list: goods that spoil never re-enter the tender pool.
  Future<List<ReTenderSaleInfo>> getUnsoldTenderSales(
      {bool includePerishable = false}) async {
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
      // ⚠️ MARKED unsold, never inferred from a clock.
      //
      // A package used to enter this pool once a working-day grace window
      // closed, so the outcome was decided by the calendar: a public holiday
      // moved the deadline, and the package moved with it. Worse, it left
      // Central Disposal no way to record what actually happened -- the sale
      // had already gone from their tab. Now an officer marks it, and until
      // they do the package stays where it is.
      final passed = latest.first.items
          .any((it) => it.forfeitedPackageId == id && it.unsold);
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
      // ⚠️ A PERISHABLE never joins the re-tender pool. Goods that spoil get
      // no second round: one failed Special Tender Sale and they go straight
      // to Top Management, who decide what becomes of them. Offering them
      // again would be offering goods that will not last the wait -- and it
      // would hide them from the DG, who is the only one who can act.
      // getUnsoldPerishables serves that list from the same query.
      if (!includePerishable && f.source == 'perishable') continue;
      result.add(
          ReTenderSaleInfo(forfeited: f, sales: eligible[f.id] ?? const []));
    }
    // Stable order: most-tendered first, then by SR number.
    result.sort((a, b) {
      final c = b.tenderCount.compareTo(a.tenderCount);
      return c != 0 ? c : a.forfeited.srNumber.compareTo(b.forfeited.srNumber);
    });
    return result;
  }

  /// One page of the re-tender pool, chosen in SQL.
  ///
  /// ⚠️ The tab used to read THREE providers, each of which begins by fetching
  /// every tender sale in the yard with its items, forfeited rows, packages,
  /// package items and warehouse entries — three passes over the whole yard to
  /// draw twenty cards. `unsold_retender_pool` (postgres/29) answers the
  /// membership question once.
  Future<({List<ReTenderSaleInfo> rows, Set<String> valued, int total})>
      getUnsoldRetenderPaged({
    required int offset,
    required int limit,
    String? search,
    String? yardFilter,

    /// Only packages Central Disposal can still re-tender on its own.
    ///
    /// ⚠️ The VALUATION portal passes true. Past the fourth round a package
    /// belongs to Top Management -- a committee prices it and the ADG submits
    /// it -- so this directorate has no work left on it, and a row it cannot
    /// act on is worse than no row. Central Disposal's own tab passes false:
    /// it needs to see the committee-priced ones too.
    bool valuationRoundsOnly = false,

    /// Pending (false) or already valued (true). Null is BOTH -- a third
    /// answer, not a default.
    ///
    /// ⚠️ In SQL, not in Dart. This tab pages in the database now, so a
    /// Dart-side filter would narrow the CURRENT page while the pager went on
    /// counting rows the table no longer shows.
    bool? valued,
  }) async {
    PgQuery narrow(PgQuery q) {
      final s = search?.trim() ?? '';
      if (s.isNotEmpty) {
        q = q.or('sr_number.ilike.%$s%,consignee_name.ilike.%$s%,'
            'item_name.ilike.%$s%');
      }
      if (yardFilter != null && yardFilter.isNotEmpty) {
        q = q.or('yard.eq.$yardFilter,sr_number.ilike.%/$yardFilter/%');
      }
      if (valuationRoundsOnly) {
        q = q.lte('round_count', kMaxBidTenderRounds);
      }
      if (valued != null) {
        q = q.eq('valued', valued);
      }
      return q;
    }

    final idRows = await AuthService._withNetworkRetry(() =>
        narrow(supabase
                .from('unsold_retender_pool')
                .select('forfeited_package_id, valued'))
            // Most-tendered first, then by SR number — the app's own order.
            .order('round_count', ascending: false)
            .order('sr_number', ascending: true)
            .range(offset, offset + limit - 1));
    final total = await AuthService._withNetworkRetry(
        () => narrow(supabase.from('unsold_retender_pool')).count());

    final ids = [
      for (final e in (idRows as List))
        (e as Map<String, dynamic>)['forfeited_package_id'].toString()
    ];
    // ⚠️ Read off the SAME rows, not fetched again. This used to be
    // getValuedCurrentRoundIds(), which called getUnsoldTenderSales() -- the
    // heaviest query in the app -- a second time just to learn one boolean
    // per row. The view carries it.
    final valuedIds = <String>{
      for (final e in (idRows as List))
        if ((e as Map<String, dynamic>)['valued'] == true)
          e['forfeited_package_id'].toString()
    };

    if (ids.isEmpty) {
      return (
        rows: const <ReTenderSaleInfo>[],
        valued: const <String>{},
        total: total as int
      );
    }

    final infos = await _reTenderInfoForIds(ids);
    final byId = {for (final i in infos) i.forfeited.id: i};
    // Keep the view's order.
    return (
      rows: [for (final id in ids) if (byId[id] != null) byId[id]!],
      valued: valuedIds,
      total: total as int,
    );
  }

  /// How many of the re-tender pool are still awaiting THIS directorate.
  ///
  /// ⚠️ Its own count, over the whole filter rather than the page. The tab
  /// shows "N of M awaiting valuation", and folding that from twenty rows
  /// would report one page of work as the directorate's whole queue.
  Future<({int pending, int total})> getUnsoldRetenderCounts({
    String? search,
    String? yardFilter,
    bool valuationRoundsOnly = false,
  }) async {
    PgQuery narrow(PgQuery q) {
      final s = search?.trim() ?? '';
      if (s.isNotEmpty) {
        q = q.or('sr_number.ilike.%$s%,consignee_name.ilike.%$s%,'
            'item_name.ilike.%$s%');
      }
      if (yardFilter != null && yardFilter.isNotEmpty) {
        q = q.or('yard.eq.$yardFilter,sr_number.ilike.%/$yardFilter/%');
      }
      if (valuationRoundsOnly) {
        q = q.lte('round_count', kMaxBidTenderRounds);
      }
      return q;
    }

    final total = await AuthService._withNetworkRetry(
        () => narrow(supabase.from('unsold_retender_pool')).count());
    final pending = await AuthService._withNetworkRetry(() =>
        narrow(supabase.from('unsold_retender_pool')).eq('valued', false).count());
    return (pending: pending as int, total: total as int);
  }

  /// One page of the Committees tab, chosen in SQL.
  ///
  /// ⚠️ Its OWN view (`committee_pool`, postgres/39), not the re-tender
  /// pool narrowed.
  ///
  /// It used to read `unsold_retender_pool`, which broke the moment
  /// postgres/38 stopped Central Disposal re-tendering past four rounds
  /// without a committee: that rule holds exactly these packages OUT of the
  /// pool, so the tab that appoints their committee could no longer see them.
  /// CED/GL1/OA/07/2025 (five rounds, no committee) appeared on no page at
  /// all. A package with nowhere to go is worse than one in the wrong place.
  ///
  /// A card LEAVES this tab when the committee-priced tender also fails —
  /// which is when the package becomes exhausted, and the view already
  /// excludes those. So the `movedOn` set the tab used to build is gone.
  /// [appointedOnly] narrows to packages that HAVE a committee.
  ///
  /// ⚠️ The two portals want different halves of the same pool. Central
  /// Disposal watches committees that exist -- it cannot appoint one, so a
  /// package still waiting for one is nothing it can act on. Top Management
  /// APPOINTS them, so its tab must show the packages with none yet, or the
  /// one thing that page is for would be impossible.
  Future<({List<ReTenderSaleInfo> rows, int total})> getCommitteesPaged({
    required int offset,
    required int limit,
    String? search,
    String? yardFilter,
    bool appointedOnly = true,
  }) async {
    PgQuery narrow(PgQuery q) {
      // ⚠️ At LEAST four rounds, not exactly four.
      //
      // Exactly-four missed the packages that had already run a fifth round
      // before postgres/38 stopped that from happening -- CED/GL1/OA/07/2025
      // had five, no committee, and appeared on no page at all: not in the
      // re-tender pool (the new rule holds it out), not on the DG's Unsold
      // Goods (its committee round has not failed, because it never had one),
      // and not here. A package with nowhere to go is worse than one in the
      // wrong place.
      // The view already selects >= 4 rounds -- that IS its membership rule
      // -- so nothing more is needed here.
      if (appointedOnly) q = q.eq('has_committee', true);
      final s = search?.trim() ?? '';
      if (s.isNotEmpty) {
        q = q.or('sr_number.ilike.%$s%,consignee_name.ilike.%$s%,'
            'item_name.ilike.%$s%');
      }
      if (yardFilter != null && yardFilter.isNotEmpty) {
        q = q.or('yard.eq.$yardFilter,sr_number.ilike.%/$yardFilter/%');
      }
      return q;
    }

    final idRows = await AuthService._withNetworkRetry(() =>
        narrow(supabase
                .from('committee_pool')
                .select('forfeited_package_id'))
            .order('sr_number', ascending: true)
            .range(offset, offset + limit - 1));
    final total = await AuthService._withNetworkRetry(
        () => narrow(supabase.from('committee_pool')).count());

    final ids = [
      for (final e in (idRows as List))
        (e as Map<String, dynamic>)['forfeited_package_id'].toString()
    ];
    if (ids.isEmpty) {
      return (rows: const <ReTenderSaleInfo>[], total: total as int);
    }

    final infos = await _reTenderInfoForIds(ids);
    final byId = {for (final i in infos) i.forfeited.id: i};
    return (
      rows: [for (final id in ids) if (byId[id] != null) byId[id]!],
      total: total as int,
    );
  }

  // ── Tender bids (recorded per tender ROUND on unsold packages) ────────────

  /// Bids recorded for an unsold tender package, grouped by tender round
  /// (tender_sale_id → amounts, oldest first). Bids saved before the round
  /// key existed group under the empty-string key ''.
  /// The tender rounds ONE package sat in, oldest first — just `(id,
  /// createdAt)`, which is all the Tender History needs to number a round
  /// ("Valuation Tender", "Tender 1", ...).
  ///
  /// The history used to derive this from `getTenderSales()`, which pulls
  /// EVERY sale with its items, packages, package_items and warehouse_entries
  /// attached. On Central Disposal that was free because the Tender Sales tab
  /// had already cached it, but on the yard's Sold Goods page nothing warms it,
  /// so opening a popup paid for the whole nested fetch and the section
  /// appeared noticeably late.
  Future<
          List<
              ({
                String id,
                DateTime createdAt,
                bool hasRun,
                bool sold,
                double? soldPrice
              })>>
      getTenderRoundsForPackage(String forfeitedPackageId) async {
    final rows = await AuthService._withNetworkRetry(() => supabase
        .from('tender_sale_items')
        .select('tender_sale_id, sold, sold_price, '
            'tender_sales(id, created_at, sale_date, sale_time, sale_end_time)')
        .eq('forfeited_package_id', forfeitedPackageId));
    // ⚠️ `sold` and `soldPrice` ride along because a round that SOLD has
    // nothing else to show: bids are only recorded when goods fail to sell,
    // so the winning round has no bids and no re-valuation of its own. Tender
    // History was dropping it for exactly that reason -- the last thing that
    // happened to the package was the one thing missing from its history.
    final out = <String,
        ({DateTime createdAt, bool hasRun, bool sold, double? soldPrice})>{};
    for (final e in (rows as List)) {
      final sale = e['tender_sales'];
      if (sale is! Map) continue;
      final id = sale['id'] as String?;
      if (id == null || id.isEmpty) continue;
      // `hasRun` drives the per-round seal in the Tender History: a round that
      // has not been tendered yet must not show its price. Judged by the sale
      // MOMENT (date + time), the same clock Mark Sold uses — never by
      // created_at, which is only when the row was inserted.
      // The round has "run" once the sale has ENDED — the valuation is the
      // reserve price, so it may only be shown after bidding has closed.
      // Falls back to the start time for rows created before sale_end_time
      // existed, so their behaviour is unchanged.
      final date = parseDbDate(sale['sale_date']);
      final moment = combineSaleMoment(date, sale['sale_end_time'] as String?) ??
          combineSaleMoment(date, sale['sale_time'] as String?);
      // Same package can appear as several TSI rows in one round; keep one.
      out[id] = (
        createdAt: parseDbDateRequired(sale['created_at']),
        hasRun: moment != null && DateTime.now().isAfter(moment),
        sold: e['sold'] == true,
        soldPrice: parseDbNum(e['sold_price']),
      );
    }
    final list = out.entries
        .map((e) => (
              id: e.key,
              createdAt: e.value.createdAt,
              hasRun: e.value.hasRun,
              sold: e.value.sold,
              soldPrice: e.value.soldPrice,
            ))
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return list;
  }

  /// The bids for a PAGE of packages: package id -> round id -> amounts.
  ///
  /// ⚠️ One query for the page, not one per row. `tenderBidsProvider`
  /// is a family keyed by forfeited package, and the tables read it from
  /// inside their row builders -- so twenty rows meant twenty round trips.
  /// Measured at page size: 57ms as separate calls against 22ms as one.
  ///
  /// It is the mistake the Destroyed Goods tab, and then the Warehouses page,
  /// were both fixed for: paging a table does not page what its CELLS fetch.
  Future<Map<String, Map<String, List<double>>>> getTenderBidsForPackages(
      List<String> forfeitedPackageIds) async {
    if (forfeitedPackageIds.isEmpty) return const {};
    final rows = await AuthService._withNetworkRetry(() => supabase
        .from('tender_bids')
        .select('forfeited_package_id, tender_sale_id, amount')
        .inFilter('forfeited_package_id', forfeitedPackageIds.toSet().toList())
        // ⚠️ Ordered by PACKAGE first, then by when each bid was
        // entered, then by id. Ordering by created_at alone interleaves the
        // packages, and a package's own bids then come back in a different
        // order than the per-package query gives -- which matters, because the
        // edit dialog seeds one text field per bid in exactly this order.
        //
        // ⚠️ The id is the TIEBREAK, and it is not decoration: bids
        // entered together carry the SAME created_at to the microsecond, and
        // Postgres promises no order between tied rows. Without it the same
        // two amounts came back swapped between one read and the next.
        .order('forfeited_package_id', ascending: true)
        .order('created_at', ascending: true)
        .order('id', ascending: true));
    final out = <String, Map<String, List<double>>>{};
    for (final e in (rows as List)) {
      final m = e as Map<String, dynamic>;
      final fpId = m['forfeited_package_id'].toString();
      out
          .putIfAbsent(fpId, () => <String, List<double>>{})
          .putIfAbsent((m['tender_sale_id'] as String?) ?? '', () => [])
          .add(parseDbNum(m['amount']) ?? 0);
    }
    return out;
  }

  /// The re-valuations for a PAGE of packages: package id -> round id -> row.
  ///
  /// ⚠️ One query for the page, for the same reason as
  /// [getTenderBidsForPackages]. Measured at page size: 74ms as separate calls
  /// against 14ms as one.
  Future<Map<String, Map<String, TenderRevaluationModel>>>
      getTenderRevaluationsForPackages(List<String> forfeitedPackageIds) async {
    if (forfeitedPackageIds.isEmpty) return const {};
    final rows = await AuthService._withNetworkRetry(() => supabase
        .from('tender_revaluations')
        .select('*')
        .inFilter('forfeited_package_id', forfeitedPackageIds.toSet().toList())
        // ⚠️ By PACKAGE first, then created_at, then id: "latest wins"
        // below relies on each package's own rows arriving in order, and rows
        // written together share a created_at to the microsecond.
        .order('forfeited_package_id', ascending: true)
        .order('created_at', ascending: true)
        .order('id', ascending: true));
    final out = <String, Map<String, TenderRevaluationModel>>{};
    for (final e in (rows as List)) {
      final model = TenderRevaluationModel.fromJson(e as Map<String, dynamic>);
      // latest wins, as the per-package version does (ordered asc)
      out.putIfAbsent(model.forfeitedPackageId, () => {})[
          model.tenderSaleId ?? ''] = model;
    }
    return out;
  }

  Future<Map<String, List<double>>> getTenderBidsByRound(
      String forfeitedPackageId) async {
    final rows = await AuthService._withNetworkRetry(() => supabase
        .from('tender_bids')
        .select('tender_sale_id, amount')
        .eq('forfeited_package_id', forfeitedPackageId)
        // ⚠️ The id breaks the tie. Bids entered together share a
        // created_at to the microsecond, and Postgres promises no order
        // between tied rows -- so this list came back in a different order
        // from one read to the next, and the edit dialog seeds one text field
        // per bid in exactly this order.
        .order('created_at', ascending: true)
        .order('id', ascending: true));
    final byRound = <String, List<double>>{};
    for (final e in (rows as List)) {
      byRound
          .putIfAbsent((e['tender_sale_id'] as String?) ?? '', () => [])
          .add(parseDbNum(e['amount']) ?? 0);
    }
    return byRound;
  }

  /// Replace the bids of ONE tender round with [amounts] (blanks/zeros skipped).
  /// Other rounds' bids for the same package are untouched.
  ///
  /// ⚠️ PERISHABLES TAKE NO BIDS. They run one special sale, and if it
  /// fails they go straight to the Top Management Directorate through Unsold
  /// Perishables -- there is no re-valuation and no second round to price,
  /// because the goods are rotting. `unsold_retender_pool` has excluded them
  /// since migration 44, so no UI offers the cell; nothing stopped the WRITE,
  /// and 20 bids had been recorded against perishable packages through the
  /// special sale. Migration 62 removed them and added a trigger.
  ///
  /// This checks FIRST so the officer reads a sentence about perishables
  /// rather than a Postgres check_violation.
  Future<void> saveTenderRoundBids(
      String forfeitedPackageId, String tenderSaleId, List<double> amounts,
      {String? yard}) async {
    final fp = await AuthService._withNetworkRetry(() => supabase
        .from('forfeited_packages')
        .select('source')
        .eq('id', forfeitedPackageId)
        .maybeSingle());
    if ((fp?['source'] as String?)?.trim().toLowerCase() == 'perishable') {
      throw Exception(
          'Perishable goods take no bids. They run one special sale, and if '
          'it fails the Top Management Directorate decides the outcome '
          'directly from Unsold Perishables.');
    }
    await AuthService._withNetworkRetry(() => supabase
        .from('tender_bids')
        .delete()
        .eq('forfeited_package_id', forfeitedPackageId)
        .eq('tender_sale_id', tenderSaleId));
    final clean = amounts.where((a) => a > 0).toList();
    if (clean.isEmpty) return;
    final uid = supabase.auth.currentUser?.id;
    await AuthService._withNetworkRetry(
        () => supabase.from('tender_bids').insert([
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
          .add(parseDbNum(e['amount']) ?? 0);
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
    // Latest round id per package (newest createdAt), plus how many rounds it
    // has run — a package past Tender 3 is a Top Management Directorate committee case.
    final latestRound = <String, String>{};
    final roundCount = <String, int>{};
    for (final info in unsold) {
      final sales = [...info.sales]
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (sales.isNotEmpty) {
        latestRound[info.forfeited.id] = sales.first.id;
        roundCount[info.forfeited.id] = sales.length;
      }
    }
    final ids = latestRound.keys.toList();

    // 1. The current round must carry a valuation …
    final revals = await AuthService._withNetworkRetry(() => supabase
        .from('tender_revaluations')
        .select('forfeited_package_id, tender_sale_id')
        .inFilter('forfeited_package_id', ids));

    // 2. … and that valuation must have been decided FROM bids, so the round
    //    must actually have bids recorded against it. Without this a package
    //    could be re-tendered on a price nobody bid against.
    final bidRows = await AuthService._withNetworkRetry(() => supabase
        .from('tender_bids')
        .select('forfeited_package_id, tender_sale_id')
        .inFilter('forfeited_package_id', ids));
    final bidRounds = <String>{};
    for (final e in (bidRows as List)) {
      final fpId = e['forfeited_package_id']?.toString();
      final saleId = e['tender_sale_id']?.toString();
      if (fpId != null && saleId != null) bidRounds.add('$fpId|$saleId');
    }

    // 3. Once a package is past Tender 3 the price is a COMMITTEE decision, and
    //    it only counts when the ADG has submitted it.
    final committees = await AuthService._withNetworkRetry(() => supabase
        .from('tender_committees')
        .select('forfeited_package_id, submitted_value, submitted_at')
        .inFilter('forfeited_package_id', ids));
    final adgSubmitted = <String>{};
    final submittedAt = <String, DateTime>{};
    for (final e in (committees as List)) {
      final fpId = e['forfeited_package_id']?.toString();
      if (fpId == null || e['submitted_value'] == null) continue;
      adgSubmitted.add(fpId);
      final at = DateTime.tryParse(e['submitted_at']?.toString() ?? '');
      if (at != null) submittedAt[fpId] = at;
    }

    // 4. The committee-priced tender is the LAST attempt. If a round was
    //    already created after the ADG's submission and that round also went
    //    unsold, every avenue is exhausted — the package belongs to the DG's
    //    Unsold Packages tab, not to the re-tender pool.
    final exhaustedIds = <String>{};
    for (final info in unsold) {
      final at = submittedAt[info.forfeited.id];
      if (at == null) continue;
      // Judged by when the round RAN, exactly as getExhaustedUnsoldPackages
      // does. Keying on created_at here while that method keys on the sale
      // moment let a package count as exhausted for the DG's tab AND still
      // eligible for re-tender — it would have shown in both places at once.
      if (info.sales.any((s) {
        final m = s.saleMoment;
        return m != null && m.isAfter(at) && s.saleEnded;
      })) {
        exhaustedIds.add(info.forfeited.id);
      }
    }

    // 5. Once the DG has decided a package's FINAL outcome (destroy / remand /
    //    government use / auction) it must stop being offered for re-tender —
    //    the decision ends the tender route for those goods.
    final decided = await AuthService._withNetworkRetry(() => supabase
        .from('unsold_proposals')
        .select('forfeited_package_id')
        .inFilter('forfeited_package_id', ids));
    final decidedIds = {
      for (final e in (decided as List))
        if (e['forfeited_package_id'] != null)
          e['forfeited_package_id'].toString()
    };

    final eligible = <String>{};
    for (final e in (revals as List)) {
      final fpId = e['forfeited_package_id'] as String;
      final saleId = e['tender_sale_id'] as String?;
      // Re-tenderable means the NEXT round has a price, which is the PENDING
      // row. A figure on the latest round is that round's own reserve and says
      // nothing about the next one.
      if (saleId != null) continue;
      // The bids that decided it belong to the latest round.
      if (!bidRounds.contains('$fpId|${latestRound[fpId]}')) continue;
      if (decidedIds.contains(fpId)) continue;
      if (exhaustedIds.contains(fpId)) continue;
      // Committee stage: needs the ADG's submission, not just any valuation.
      final rounds = roundCount[fpId] ?? 0;
      if (rounds > kMaxBidTenderRounds && !adgSubmitted.contains(fpId))
        continue;
      eligible.add(fpId);
    }
    return eligible;
  }

  /// The forfeited-package ids whose CURRENT unsold round already carries a
  /// Valuation Directorate re-valuation.
  ///
  /// Deliberately NOT the same as [getReTenderEligibleIds]: that also demands
  /// bids and, past Tender 3, the ADG's submission. This answers only "has the
  /// Valuation Directorate done its part for this round?", which is what their
  /// own Pending/Valued filter needs.
  Future<Set<String>> getValuedCurrentRoundIds() async {
    final unsold = await getUnsoldTenderSales();
    if (unsold.isEmpty) return {};
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
    final valued = <String>{};
    for (final e in (rows as List)) {
      final fpId = e['forfeited_package_id'] as String;
      final saleId = e['tender_sale_id'] as String?;
      // "Valued" means the NEXT round has been priced, which is the PENDING
      // row. A figure keyed to the latest round is that round's OWN reserve —
      // every held round has one, so counting it marked every package valued
      // and hid the Set Value button. Packages reach this list only after
      // their latest round has been held, so pending is the whole test.
      if (saleId == null) valued.add(fpId);
    }
    return valued;
  }

  /// The re-valuations recorded for a package, keyed by tender round
  /// (tender_sale_id → re-valuation). Round-less rows key under ''.
  Future<Map<String, TenderRevaluationModel>> getTenderRevaluationsByRound(
      String forfeitedPackageId) async {
    final rows = await AuthService._withNetworkRetry(() => supabase
        .from('tender_revaluations')
        .select('*')
        .eq('forfeited_package_id', forfeitedPackageId)
        // ⚠️ Same tiebreak: "latest wins" needs a defined order.
        .order('created_at', ascending: true)
        .order('id', ascending: true));
    final byRound = <String, TenderRevaluationModel>{};
    for (final e in (rows as List)) {
      final m = TenderRevaluationModel.fromJson(e as Map<String, dynamic>);
      byRound[m.tenderSaleId ?? ''] = m; // latest wins (ordered asc)
    }
    return byRound;
  }

  /// ALL forfeited-package rows with their package/item details, unfiltered by
  /// any work-queue rule (unlike [getForfeitedPackages], which hides tendered /
  /// requested / sold rows). Reporting needs the complete history.
  Future<List<ForfeitedPackageModel>> getAllForfeitedForReports() async {
    final data = await AuthService._withNetworkRetry(() => supabase
        .from('forfeited_packages')
        .select(
            '*, disposal_request_items!forfeited_package_id(valuation_cost), packages(*, package_items(*), warehouse_entries(*, warehouses(*)))')
        .order('forfeited_at', ascending: false));
    return (data as List)
        .map((e) => ForfeitedPackageModel.fromJson(e))
        .toList();
  }

  /// Every valuation ever set for a package, oldest first:
  /// `[initial, 2nd, 3rd, final]`. The first entry is the Valuation
  /// Directorate's INITIAL valuation (`disposal_request_items.valuation_cost`);
  /// each later entry is one `tender_revaluations` round, ordered by
  /// `created_at`. Keyed by `forfeited_package_id`.
  ///
  /// Used by the Executive Office valuation reports; the list can be shorter
  /// than 4 (not every package is re-valued) and callers pad/trim as needed.
  Future<Map<String, List<double>>> getValuationChains() async {
    final chains = <String, List<double>>{};

    // 1. Initial valuation — one row per disposal request item.
    final initial = await AuthService._withNetworkRetry(() => supabase
        .from('disposal_request_items')
        .select('forfeited_package_id, valuation_cost'));
    for (final e in (initial as List)) {
      final id = e['forfeited_package_id']?.toString();
      final cost = parseDbNum(e['valuation_cost']);
      if (id == null || cost == null) continue;
      chains.putIfAbsent(id, () => []).add(cost);
    }

    // 2. Re-valuations — one per unsold tender round, oldest first. These
    //    price Tender 1 / 2 / 3.
    final revals = await AuthService._withNetworkRetry(() => supabase
        .from('tender_revaluations')
        .select('forfeited_package_id, valuation_cost, created_at')
        .order('created_at', ascending: true));
    for (final e in (revals as List)) {
      final id = e['forfeited_package_id']?.toString();
      final cost = parseDbNum(e['valuation_cost']);
      if (id == null || cost == null) continue;
      chains.putIfAbsent(id, () => []).add(cost);
    }

    // 3. The HIGH PANEL valuation — the figure the ADG submitted from the
    //    tender committee, which prices the final committee round. It lives on
    //    `tender_committees`, not in the re-valuations, so without this the
    //    last stage of the chain was missing from every report.
    //
    //    Appended last so the chain reads in order:
    //      initial -> Tender 1 -> Tender 2 -> Tender 3 -> Top Management Directorate
    try {
      final committees = await AuthService._withNetworkRetry(() => supabase
          .from('tender_committees')
          .select('forfeited_package_id, submitted_value, submitted_at')
          .not('submitted_value', 'is', null)
          .order('submitted_at', ascending: true));
      for (final e in (committees as List)) {
        final id = e['forfeited_package_id']?.toString();
        final cost = parseDbNum(e['submitted_value']);
        if (id == null || cost == null) continue;
        chains.putIfAbsent(id, () => []).add(cost);
      }
    } catch (e) {
      // A role without read access to tender_committees still gets the rest of
      // the chain rather than an empty report.
      debugPrint('getValuationChains: committee values unavailable: $e');
    }
    return chains;
  }

  /// Set / replace the Valuation Directorate's re-valuation.
  ///
  /// ⚠️ [tenderSaleId] must be **null** when the round it was decided from has
  /// already RUN. A `tender_revaluations` row is the reserve price OF THE ROUND
  /// IT IS KEYED TO, so writing a new figure against a finished round rewrites
  /// what that round actually went to tender at. That is exactly what happened
  /// to CED/GL1/SR/20/2026: round R018 ran at 5,400 and 6,800 per unit, a new
  /// valuation of 5,000 was saved against it, and the history then read 5,000
  /// for both — the real prices were gone.
  ///
  /// A null round means "the price for the NEXT tender, not yet placed". It is
  /// attached to the new round by [createTenderSale] when the package is
  /// re-tendered, which is the moment it stops being pending and starts being
  /// that round's reserve.
  Future<void> saveTenderRevaluation(
      String forfeitedPackageId, String? tenderSaleId, double valuationCost,
      {String? note, String? yard}) async {
    final del = supabase
        .from('tender_revaluations')
        .delete()
        .eq('forfeited_package_id', forfeitedPackageId);
    await AuthService._withNetworkRetry(() => tenderSaleId == null
        ? del.isNull('tender_sale_id')
        : del.eq('tender_sale_id', tenderSaleId));
    final uid = supabase.auth.currentUser?.id;
    await AuthService._withNetworkRetry(
        () => supabase.from('tender_revaluations').insert({
              'forfeited_package_id': forfeitedPackageId,
              'tender_sale_id': tenderSaleId,
              'valuation_cost': valuationCost,
              'note':
                  (note != null && note.trim().isNotEmpty) ? note.trim() : null,
              'yard': yard,
              'created_by': uid,
            }));
  }

  // ── Tender committees (ADG appoints the members for >3× unsold packages) ─

  /// All appointed committees, keyed by forfeited_package_id.
  /// The committees for a PAGE of packages, keyed by forfeited package id.
  ///
  /// ⚠️ Narrowed to the page. The tables read this as a LOOKUP -- one
  /// `[fpId]` per row -- but fetched every committee in the country to serve
  /// it, from six separate places. Eight rows today; the pool is fed by all
  /// twenty-eight yards, and a committee is appointed for every package that
  /// survives four tender rounds.
  Future<Map<String, TenderCommitteeModel>> getTenderCommitteesForPackages(
      List<String> forfeitedPackageIds) async {
    if (forfeitedPackageIds.isEmpty) return const {};
    final rows = await AuthService._withNetworkRetry(() => supabase
        .from('tender_committees')
        .select('*')
        .inFilter('forfeited_package_id',
            forfeitedPackageIds.toSet().toList()));
    final out = <String, TenderCommitteeModel>{};
    for (final e in (rows as List)) {
      final m = TenderCommitteeModel.fromJson(e as Map<String, dynamic>);
      out[m.forfeitedPackageId] = m;
    }
    return out;
  }

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
    await AuthService._withNetworkRetry(
        () => supabase.from('tender_committees').upsert({
              'forfeited_package_id': forfeitedPackageId,
              'members': members
                  .where((m) => m.name.isNotEmpty)
                  .map((m) => m.toJson())
                  .toList(),
              'note':
                  (note != null && note.trim().isNotEmpty) ? note.trim() : null,
              'yard': yard,
              'created_by': uid,
              'updated_at': DateTime.now().toIso8601String(),
            }, onConflict: 'forfeited_package_id'));
  }

  /// Step 2 of the committee flow: the appointed COMMITTEE records the price it
  /// decided after inspecting the goods. Does NOT price the tender yet — the
  /// ADG must submit it (see [submitCommitteeValuation]).
  Future<void> saveCommitteeValuation(
    String forfeitedPackageId,
    double value, {
    String? note,
  }) async {
    await AuthService._withNetworkRetry(
        () => supabase.from('tender_committees').update({
              'committee_value': value,
              'committee_valued_at': DateTime.now().toIso8601String(),
              'committee_note':
                  (note != null && note.trim().isNotEmpty) ? note.trim() : null,
              'updated_at': DateTime.now().toIso8601String(),
            }).eq('forfeited_package_id', forfeitedPackageId));
  }

  /// Step 3: the ADG submits the committee's figure as the FINAL valuation for
  /// the package's next tender round.
  ///
  /// This also writes the normal `tender_revaluations` row for the current
  /// round, so the price reaches the tender through the very same path a
  /// Valuation Directorate re-valuation uses — Central Disposal, the reports
  /// and the valuation chain all pick it up with no extra wiring.
  Future<void> submitCommitteeValuation({
    required String forfeitedPackageId,
    /// Null once the current round has been held — the figure prices the NEXT
    /// round, so it is stored pending. See [saveTenderRevaluation].
    required String? tenderSaleId,
    required double value,
    String? note,
    String? yard,
  }) async {
    await saveTenderRevaluation(
      forfeitedPackageId,
      tenderSaleId,
      value,
      note: (note != null && note.trim().isNotEmpty)
          ? note.trim()
          : 'Committee valuation submitted by the ADG',
      yard: yard,
    );

    final uid = supabase.auth.currentUser?.id;
    await AuthService._withNetworkRetry(
        () => supabase.from('tender_committees').update({
              'submitted_value': value,
              'submitted_at': DateTime.now().toIso8601String(),
              'submitted_by': uid,
              'updated_at': DateTime.now().toIso8601String(),
            }).eq('forfeited_package_id', forfeitedPackageId));
  }

  // ── Unsold proposals (the Top Management Directorate's final outcome) ────────────────────

  /// Every recorded final outcome, keyed by forfeited_package_id.
  /// The DG's rulings for a PAGE of packages, keyed by forfeited package id.
  ///
  /// ⚠️ Narrowed to the page, for the same reason as
  /// [getTenderCommitteesForPackages]: the tables read it one `[fpId]` at a
  /// time and fetched every ruling in the country to do it.
  Future<Map<String, UnsoldProposalModel>> getUnsoldProposalsForPackages(
      List<String> forfeitedPackageIds) async {
    if (forfeitedPackageIds.isEmpty) return const {};
    final rows = await AuthService._withNetworkRetry(() => supabase
        .from('unsold_proposals')
        .select('*')
        .inFilter('forfeited_package_id',
            forfeitedPackageIds.toSet().toList()));
    final out = <String, UnsoldProposalModel>{};
    for (final e in (rows as List)) {
      final m = UnsoldProposalModel.fromJson(e as Map<String, dynamic>);
      out[m.forfeitedPackageId] = m;
    }
    return out;
  }

  Future<Map<String, UnsoldProposalModel>> getUnsoldProposals() async {
    final rows = await AuthService._withNetworkRetry(
        () => supabase.from('unsold_proposals').select('*'));
    final out = <String, UnsoldProposalModel>{};
    for (final e in (rows as List)) {
      final m = UnsoldProposalModel.fromJson(e as Map<String, dynamic>);
      out[m.forfeitedPackageId] = m;
    }
    return out;
  }

  /// Every recorded final outcome, keyed by **package_item_id**.
  ///
  /// ⚠️ The proposals table keys on `forfeited_package_id`, which the pages
  /// that decide already hold. The Perishable Goods page does not: it lists
  /// package ITEMS straight off the packages, and never loads a forfeited row.
  /// Without this it could not show the DG's decision at all -- the yard and
  /// Central Disposal would be looking at goods whose fate had been settled
  /// and see nothing of it.
  /// The valuation set for each PERISHABLE item, keyed by item id.
  ///
  /// ⚠️ ONE query for the page, not one per row. A per-row read here
  /// meant a provider watch inside every cell -- twenty round trips for one
  /// number each, and in a widget test a realtime channel that never
  /// settles, so `pumpAndSettle` timed out with a pending timer.
  ///
  /// ⚠️ `valuation_cost` lives on `disposal_request_items`, not on
  /// `forfeited_packages` -- the same embed the popup needs.
  Future<Map<String, double>> getPerishableValuationsByItem() async {
    final data = await AuthService._withNetworkRetry(() => supabase
        .from('forfeited_packages')
        .select('item_id, entry_qty, '
            'disposal_request_items!forfeited_package_id(valuation_cost)')
        .eq('source', 'perishable'));
    final out = <String, double>{};
    for (final e in (data as List)) {
      final m = e as Map<String, dynamic>;
      final itemId = m['item_id']?.toString();
      if (itemId == null) continue;
      final rows = m['disposal_request_items'] as List?;
      if (rows == null || rows.isEmpty) continue;
      for (final r in rows) {
        final cost = parseDbNum((r as Map<String, dynamic>)['valuation_cost']);
        if (cost != null && cost > 0) {
          out[itemId] = cost;
          break;
        }
      }
    }
    return out;
  }

  Future<Map<String, UnsoldProposalModel>> getUnsoldProposalsByItem() async {
    final rows = await AuthService._withNetworkRetry(() => supabase
        .from('unsold_proposals')
        .select('*, forfeited_packages!inner(item_id)'));
    final out = <String, UnsoldProposalModel>{};
    for (final e in (rows as List)) {
      final row = e as Map<String, dynamic>;
      final fp = row['forfeited_packages'] as Map<String, dynamic>?;
      final itemId = fp?['item_id']?.toString();
      if (itemId == null || itemId.isEmpty) continue;
      out[itemId] = UnsoldProposalModel.fromJson(row);
    }
    return out;
  }

  /// Record (or replace) the Top Management Directorate's final outcome for a package.
  Future<void> saveUnsoldProposal({
    required String forfeitedPackageId,
    required String proposal,
    String? note,
    String? yard,
  }) async {
    final uid = supabase.auth.currentUser?.id;
    await AuthService._withNetworkRetry(
        () => supabase.from('unsold_proposals').upsert({
              'forfeited_package_id': forfeitedPackageId,
              'proposal': proposal,
              'note':
                  (note != null && note.trim().isNotEmpty) ? note.trim() : null,
              'yard': yard,
              'decided_by': uid,
              'decided_at': DateTime.now().toIso8601String(),
              'updated_at': DateTime.now().toIso8601String(),
            }, onConflict: 'forfeited_package_id'));
  }

  /// The packages that have exhausted EVERY avenue and now need (or already
  /// carry) a final outcome: past Tender 3, a committee valuation submitted by
  /// the ADG, tendered again, and still unsold.
  ///
  /// Shared by the Top Management Directorate (who decide), Central Disposal and the yards
  /// (who see the decision), so all three lists agree by construction.
  /// Perishable goods that failed their FIRST Special Tender Sale.
  ///
  /// ⚠️ Perishables do NOT go round again, and never reach a tender committee.
  /// Normal goods run the Valuation Tender plus Tenders 1-3, get a committee
  /// valuation and one more round -- five chances over months. Goods that
  /// spoil do not have months: one failed sale is the end of the road, and
  /// Top Management decides their outcome straight away.
  ///
  /// So this deliberately does NOT test `tenderCount`, a committee, or an ADG
  /// submission the way [getExhaustedUnsoldPackages] does. The single
  /// condition is: it went to a sale, that sale has ended, and it did not sell.
  Future<List<ReTenderSaleInfo>> getUnsoldPerishables() async {
    // ⚠️ `includePerishable: true` -- getUnsoldTenderSales EXCLUDES them by
    // default, because they must never appear in Central Disposal's re-tender
    // pool. This is the one list that wants them, and only them.
    final unsold = await getUnsoldTenderSales(includePerishable: true);
    if (unsold.isEmpty) return [];
    return unsold
        .where((i) => i.forfeited.source == 'perishable' && i.sales.isNotEmpty)
        .toList();
  }

  /// Whether the Unsold page — or one of its Final Outcome pages — has any
  /// perishables on it.
  ///
  /// ⚠️ Scoped by [proposal], because each Final Outcome page is its own
  /// population: Converted has a perishable, Auction has none. Offering the
  /// chip on Auction would only ever empty the table.
  Future<bool> unsoldHasPerishables({String? yard, String? proposal}) async {
    var q = supabase.from('unsold_all_routes').eq('is_perishable', true);
    if (yard != null && yard.isNotEmpty) q = q.eq('yard', yard);
    if (proposal != null && proposal.isNotEmpty) {
      q = q.eq('proposal', proposal);
    }
    final n = await AuthService._withNetworkRetry(() => q.count());
    return (n as int) > 0;
  }

  /// One page of Unsold Goods, decided in SQL.
  ///
  /// ⚠️ [getExhaustedUnsoldPackages] answers the same question by loading
  /// EVERY tender sale with every item and join, then narrowing to the handful
  /// that have run out of road -- so the page costs the entire tender history
  /// of the yard, forever, to show twenty rows. The `exhausted_unsold` view
  /// applies the identical four conditions in the database (see postgres/23),
  /// and only the named page's rounds are loaded afterwards.
  ///
  /// [perishable] serves the Unsold PERISHABLES tab from `unsold_perishables`
  /// (postgres/32) instead.
  ///
  /// ⚠️ The two lists reach Top Management by entirely different routes and
  /// must stay apart: a normal package arrives after five failed chances, a
  /// committee valuation and the ADG's submission; a perishable arrives after
  /// ONE failed Special Tender Sale, because goods that spoil cannot wait for
  /// the long route. The VIEWS encode that difference -- everything after it
  /// (the page, the filters, the rounds loaded for the page) is identical, so
  /// the two share this method rather than drifting apart in two copies.
  Future<({List<ReTenderSaleInfo> rows, int total})> getExhaustedUnsoldPaged({
    required int offset,
    required int limit,
    bool perishable = false,
    String? search,
    String? yard,
    DateTime? dateStart,
    DateTime? dateEnd,
    String? year,

    /// One of the four Final Outcome pages: 'government_use', 'auction',
    /// 'convert', 'remove_from_premises'. Null is the Unsold Goods page
    /// itself, which shows every package whatever its outcome.
    String? proposal,

    /// The page's Final Outcome filter: one of [kUnsoldProposals],
    /// [kOutcomeAwaiting], or null for all of them.
    ///
    /// ⚠️ Distinct from [proposal], which says WHICH PAGE this is. Government
    /// Use passes proposal='government_use' and every row on it is already
    /// that; the filter narrows within whatever page it is.
    String? outcome,

    /// The All / Pending / Delivered filter on the four Final Outcome pages.
    /// Null is "All" -- a third answer, not a default.
    ///
    /// ⚠️ Filtered in SQL, not in Dart. These pages page in the database, so a
    /// Dart-side filter would narrow the CURRENT page and leave the pager
    /// counting rows the table no longer shows.
    bool? delivered,

    /// List goods from BOTH unsold routes -- the committee route and the
    /// perishable one -- as the yard's own pages need.
    ///
    /// ⚠️ Off by default so Top Management's two decision tabs keep reading
    /// one route each; there the distinction is the point of the tab.
    bool includeAllRoutes = false,

    /// Show only perishables. Null/false is "all goods" -- false must not
    /// mean "hide every perishable", which is what the page's chip toggling
    /// off would otherwise do.
    bool? perishableOnly,
  }) async {
    // ⚠️ ONE closure for the rows and the count, or the pager's total and the
    // rows under it disagree.
    PgQuery narrow(PgQuery q) {
      if (yard != null && yard.isNotEmpty) q = q.eq('yard', yard);
      final s = search?.trim() ?? '';
      if (s.isNotEmpty) {
        // The item name and the CASE NUMBER too — Central Disposal's copy of
        // this table searches both, and the view carries them.
        q = q.or('sr_number.ilike.%$s%,consignee_name.ilike.%$s%,'
            'item_name.ilike.%$s%,case_number.ilike.%$s%');
      }
      if (year != null && year.isNotEmpty) {
        q = q.ilike('sr_number', '%/$year');
      }
      if (dateStart != null) {
        final start = DateTime(dateStart.year, dateStart.month, dateStart.day);
        q = q.gte('forfeited_at', start.toIso8601String());
      }
      if (dateEnd != null) {
        final end =
            DateTime(dateEnd.year, dateEnd.month, dateEnd.day, 23, 59, 59);
        q = q.lte('forfeited_at', end.toIso8601String());
      }
      // ⚠️ The page's own filter, by OUTCOME rather than by "decided or not".
      //
      // "Decided" lumped all six outcomes together, which is not a question
      // anyone asks: an officer wants the ones going to auction, or back out
      // of the country. Awaiting is still one of the choices -- "nobody has
      // ruled yet" is an answer like any other -- and it is the null test the
      // old flag used.
      if (outcome == kOutcomeAwaiting) {
        q = q.isNull('proposal');
      } else if (outcome != null && outcome.isNotEmpty) {
        q = q.eq('proposal', outcome);
      }
      if (proposal != null && proposal.isNotEmpty) {
        q = q.eq('proposal', proposal);
      }
      // ⚠️ A package with no outcome decided yet has a NULL delivered (the
      // join found no proposal row), and "not delivered" must include it --
      // eq(false) alone would hide every undecided package from Pending.
      if (delivered == true) q = q.eq('delivered', true);
      if (delivered == false) q = q.or('delivered.is.null,delivered.eq.false');
      // ⚠️ In SQL, like every other filter here, because this page is
      // server-paged: narrowing in Dart would cut rows out of the page the
      // pager had already counted.
      if (perishableOnly == true) q = q.eq('is_perishable', true);
      return q;
    }

    // ⚠️ Three views, because these are three different questions.
    //
    //   unsold_perishables → Top Management's Perishables decision tab
    //   exhausted_unsold   → Top Management's Unsold decision tab
    //   unsold_all_routes  → "what is unsold in this yard", which is BOTH
    //
    // A perishable reaches Top Management after one failed Special Tender
    // Sale and a normal package after four failures and a committee, so the
    // two decision tabs must stay apart. The yard is not deciding anything
    // here -- it is looking at its own goods -- and splitting them there
    // only hid the perishables entirely (see migration 017).
    final view = perishable
        ? 'unsold_perishables'
        : (includeAllRoutes ? 'unsold_all_routes' : 'exhausted_unsold');
    final rows = await AuthService._withNetworkRetry(() =>
        narrow(supabase.from(view).select('forfeited_package_id'))
            .order('forfeited_at', ascending: false)
            .range(offset, offset + limit - 1));
    final total = await AuthService._withNetworkRetry(
        () => narrow(supabase.from(view)).count());

    final ids = [
      for (final e in (rows as List))
        (e as Map<String, dynamic>)['forfeited_package_id'].toString()
    ];
    if (ids.isEmpty) {
      return (rows: const <ReTenderSaleInfo>[], total: total as int);
    }

    // The rounds, for THIS page's packages only. The table shows the round
    // count and the popup the whole history, so they are genuinely needed --
    // but twenty packages' worth, not the yard's.
    final infos = await _reTenderInfoForIds(ids);
    // Keep the database's order: the query sorted it, and re-sorting here
    // would quietly disagree with the page boundaries.
    final byId = {for (final i in infos) i.forfeited.id: i};
    return (
      rows: [for (final id in ids) if (byId[id] != null) byId[id]!],
      total: total as int,
    );
  }

  /// The SR numbers on Unsold Goods, for its year filter.
  Future<List<String>> getExhaustedUnsoldYears() async {
    final data = await AuthService._withNetworkRetry(
        () => supabase.from('exhausted_unsold').select('sr_number'));
    return [
      for (final row in (data as List))
        (row as Map<String, dynamic>)['sr_number']?.toString() ?? '',
    ];
  }

  /// [ReTenderSaleInfo] for a specific set of forfeited packages.
  ///
  /// The per-page counterpart of `getUnsoldTenderSales`, which builds the same
  /// shape for every package in the yard.
  Future<List<ReTenderSaleInfo>> _reTenderInfoForIds(List<String> ids) async {
    if (ids.isEmpty) return const [];
    final fps = await AuthService._withNetworkRetry(() => supabase
        .from('forfeited_packages')
        .select(
            '*, disposal_request_items!forfeited_package_id(valuation_cost), packages(*, package_items(*), warehouse_entries(*, warehouses(*)))')
        .inFilter('id', ids));
    final items = await AuthService._withNetworkRetry(() => supabase
        .from('tender_sale_items')
        .select('*, tender_sales(*)')
        .inFilter('forfeited_package_id', ids));

    final salesByFp = <String, List<TenderSaleModel>>{};
    for (final e in (items as List)) {
      final row = e as Map<String, dynamic>;
      final fpId = row['forfeited_package_id']?.toString();
      final sale = row['tender_sales'];
      if (fpId == null || sale is! Map) continue;
      salesByFp
          .putIfAbsent(fpId, () => [])
          .add(TenderSaleModel.fromJson(Map<String, dynamic>.from(sale)));
    }
    // Newest first, matching ReTenderSaleInfo's contract.
    for (final list in salesByFp.values) {
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }

    return [
      for (final e in (fps as List))
        ReTenderSaleInfo(
          forfeited: ForfeitedPackageModel.fromJson(e as Map<String, dynamic>),
          sales: salesByFp[e['id'].toString()] ?? const [],
        )
    ];
  }

  Future<List<ReTenderSaleInfo>> getExhaustedUnsoldPackages() async {
    final unsold = await getUnsoldTenderSales();
    if (unsold.isEmpty) return [];
    final committees = await getTenderCommittees();
    return unsold.where((i) {
      // 1. The Valuation Tender + Tender 1-3 must all have failed.
      if (i.tenderCount <= kMaxBidTenderRounds) return false;

      // 2. The committee must have valued it AND the ADG submitted that
      //    figure as the tender's price.
      final c = committees[i.forfeited.id];
      final submittedAt = c?.submittedAt;
      if (c?.submittedValue == null || submittedAt == null) return false;

      // 3. …and the package must then have been tendered AGAIN at that price
      //    and STILL not sold. Without this the package reached the DG the
      //    moment the ADG submitted, before the committee-priced tender had
      //    even been placed — so the DG was deciding the final outcome of a
      //    package that still had a live chance of selling.
      //
      //    The test is whether a round RAN after the submission, judged by
      //    its scheduled sale moment — not by `createdAt`, which is merely
      //    when the row was inserted. Central Disposal routinely schedules a
      //    round before the ADG gets round to submitting, and two packages can
      //    share one sale row; keying on `createdAt` then stranded a package
      //    whose committee value was entered after the row existed, even
      //    though the tender itself ran days later and failed. (Seen live:
      //    Toilet Seat Covers and Wash Basins shared round F01 — same row,
      //    created 04:25, scheduled 08-19 — and only Wash Basins, submitted at
      //    03:25, moved on. Toilet Seat Covers, submitted 18:31, stayed stuck
      //    on 5 rounds.)
      //
      //    `getUnsoldTenderSales` already guarantees "not sold" and "the
      //    latest round's deadline has passed".
      return i.sales.any((s) {
        final moment = s.saleMoment;
        return moment != null &&
            moment.isAfter(submittedAt) &&
            s.saleEnded;
      });
    }).toList();
  }

  /// Packages sitting in the COMMITTEE STAGE: the Valuation Tender plus
  /// Tenders 1-3 have all failed, and Central Disposal has not yet re-tendered
  /// them at the committee's price.
  ///
  /// ⚠️ EXACTLY 4 rounds, not `>= 4`. Re-tendering creates a 5th round, and at
  /// that moment the package leaves this pool for good — it then ends up in
  /// Sold, or in the DG's Unsold Goods once that round also fails. `>= 4` kept
  /// re-tendered packages here, listing the same goods on both the Tender
  /// Committees tab and the DG's Unsold Goods tab.
  Future<List<ReTenderSaleInfo>> getCommitteeEligiblePackages() async {
    final all = await getUnsoldTenderSales();
    return all
        .where((i) => i.tenderCount == kMaxBidTenderRounds + 1)
        .toList();
  }

  /// "Sale"-tagged disposal-request items that are not yet in a tender sale —
  /// the pool the Tender Sale form can pick from. Cross-yard via RLS; each
  /// carries the forfeited package (incl. yard, items, warehouse location).
  Future<List<DisposalRequestItemModel>> getSaleRequestItems() async {
    final inSale = await AuthService._withNetworkRetry(() =>
        supabase.from('tender_sale_items').select('forfeited_package_id'));
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
  Future<List<DisposalRequestItemModel>>
      getSaleRequestItemsNotTendered() async {
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
          .where(
              (i) => i.forwarded && !tenderedIds.contains(i.forfeitedPackageId))
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

  /// One page of Disposal Requests, chosen and filtered in SQL.
  ///
  /// ⚠️ [getDisposalRequests] runs three lookups to build the "already
  /// consumed" set, fetches EVERY forwarded request with its items, forfeited
  /// rows, packages, package items and warehouse entries, and only then throws
  /// away the items that are consumed or unforwarded — and any request left
  /// with nothing. A request is visible only because of its items, so it had
  /// to fetch everything to discover what to discard.
  ///
  /// `disposal_request_summary` (postgres/27) answers that per request, so the
  /// heavy fetch runs for one page.
  Future<({List<DisposalRequestModel> rows, int total})>
      getDisposalRequestsPaged({
    required int offset,
    required int limit,
    String? search,
    String? yardFilter,
  }) async {
    PgQuery narrow(PgQuery q) {
      final s = search?.trim() ?? '';
      if (s.isNotEmpty) {
        q = q.or('sr_numbers.ilike.%$s%,consignees.ilike.%$s%');
      }
      if (yardFilter != null && yardFilter.isNotEmpty) {
        // Any ITEM's yard, pipe-wrapped by the view so this cannot match
        // across two neighbouring values.
        q = q.or('item_yards.ilike.%|$yardFilter|%,'
            'sr_numbers.ilike.%/$yardFilter/%');
      }
      return q;
    }

    final idRows = await AuthService._withNetworkRetry(() =>
        narrow(supabase.from('disposal_request_summary').select('id'))
            .order('created_at', ascending: false)
            .range(offset, offset + limit - 1));
    final total = await AuthService._withNetworkRetry(
        () => narrow(supabase.from('disposal_request_summary')).count());

    final ids = [
      for (final e in (idRows as List))
        (e as Map<String, dynamic>)['id'].toString()
    ];
    if (ids.isEmpty) {
      return (rows: const <DisposalRequestModel>[], total: total as int);
    }

    // ⚠️ The consumed set is still needed, but only to filter THIS page's
    // items — the view already decided which requests survive.
    final consumed = await _consumedForfeitedIds();

    final data = await AuthService._withNetworkRetry(() => supabase
        .from('disposal_requests')
        .select(
            '*, profiles!created_by(full_name), valued_profile:profiles!valued_by(full_name), disposal_request_items(*, forfeited_packages(*, packages(*, package_items(*), warehouse_entries(*, warehouses(*)))))')
        .inFilter('id', ids)
        .order('created_at', ascending: false));

    final byId = <String, DisposalRequestModel>{};
    for (final e in (data as List)) {
      final r = DisposalRequestModel.fromJson(e as Map<String, dynamic>);
      final items = r.items
          .where((i) => i.forwarded && !consumed.contains(i.forfeitedPackageId))
          .toList();
      if (items.isEmpty) continue;
      byId[r.id] = DisposalRequestModel(
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
      );
    }
    // Keep the view's order.
    return (
      rows: [for (final id in ids) if (byId[id] != null) byId[id]!],
      total: total as int,
    );
  }

  /// Forfeited rows that have already moved on to a tender, a tender sale or a
  /// destruction — the three sources the requests view excludes.
  Future<Set<String>> _consumedForfeitedIds() async {
    final tendersData = await AuthService._withNetworkRetry(
        () => supabase.from('tenders').select('forfeited_package_ids'));
    final out = (tendersData as List)
        .expand((t) => (t['forfeited_package_ids'] as List? ?? const []))
        .map((e) => e.toString())
        .toSet();
    final saleItems = await AuthService._withNetworkRetry(() =>
        supabase.from('tender_sale_items').select('forfeited_package_id'));
    for (final e in (saleItems as List)) {
      out.add(e['forfeited_package_id'].toString());
    }
    final destItems = await AuthService._withNetworkRetry(() =>
        supabase.from('destruction_items').select('forfeited_package_id'));
    for (final e in (destItems as List)) {
      out.add(e['forfeited_package_id'].toString());
    }
    return out;
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
    /// Sale CLOSE time. The valuation stays sealed until it passes.
    String? saleEndTime,
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
          'sale_end_time': saleEndTime,
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

      // A pending re-valuation (tender_sale_id NULL) is the price the
      // Valuation Directorate set for the NEXT tender — this one. Claim it for
      // this round, so it becomes that round's reserve and stops being
      // pending. Without this the new round would carry no reserve at all and
      // the pending row would linger against every future tender.
      for (final fpId in packageYards.keys) {
        await AuthService._withNetworkRetry(() => supabase
            .from('tender_revaluations')
            .update({'tender_sale_id': saleId})
            .eq('forfeited_package_id', fpId)
            .isNull('tender_sale_id'));
      }
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

  /// Mark one tender-sale package UNSOLD explicitly. Moves it immediately to
  /// the Unsold Tenders pool without waiting for the automatic deadline.
  /// How many tender rounds this forfeited package has already sat in.
  ///
  /// ⚠️ Counted in SQL, on demand. The confirmation dialog needs it to say
  /// what happens NEXT -- the route changes at round 4, when the package stops
  /// going back to tender and goes to a Top Management committee instead --
  /// and an officer should not have to know that rule by heart.
  Future<int> tenderRoundCount(String forfeitedPackageId) async {
    final n = await AuthService._withNetworkRetry(() => supabase
        .from('tender_sale_items')
        .eq('forfeited_package_id', forfeitedPackageId)
        .count());
    return n as int;
  }

  Future<void> markTenderSaleItemUnsold({
    required String tenderSaleItemId,
  }) async {
    await AuthService._withNetworkRetry(() => supabase
        .from('tender_sale_items')
        .update({
          'unsold': true,
          'unsold_at': DateTime.now().toIso8601String(),
        })
        .eq('id', tenderSaleItemId));
    final user = supabase.auth.currentUser;
    if (user != null) {
      await AuditLogService().recordLog(
        userId: user.id,
        action: 'Marked tender-sale package unsold',
        entityType: 'tender_sale_item',
        entityId: tenderSaleItemId,
        details: {},
      );
    }
  }

  /// ⚠️ The buyer pays the storage before the goods go, exactly as a
  /// releasing owner does. A sale used to hand them over on a bare flag,
  /// and the yard had been storing them -- sometimes for years -- with the
  /// charge shown on no form and collected on no receipt.
  Future<void> toggleDeliveryStatus(
    String tenderSaleItemId,
    bool isDelivered, {
    String? receiptNo,
    double? charge,
    DateTime? handedAt,
  }) async {
    await AuthService._withNetworkRetry(() => supabase.rpc(
          'disposal_toggle_delivery_status',
          params: {
            'p_item_id': tenderSaleItemId,
            'p_is_delivered': isDelivered,
            'p_receipt_no': receiptNo,
            'p_charge': charge,
            'p_handed_at': handedAt?.toIso8601String(),
          },
        ));
  }

  /// Record that RELEASED goods have actually been collected.
  ///
  /// ⚠️ A release has the same two events a re-export does: an officer
  /// RULES the goods released, writing a receipt, and the owner later COMES
  /// FOR THEM. Released Goods showed the first and had no answer for the
  /// second, so all 33 rows looked finished while the yard could still be
  /// storing every one of them.
  ///
  /// ⚠️ Like [toggleReexportDelivery] and unlike [toggleOutcomeDelivery],
  /// this does not close the warehouse entry -- releasing already did.
  Future<void> toggleReleasedDelivery(
    String entryId,
    bool delivered, {
    String? receiptNo,
    double? charge,
    DateTime? handedAt,
  }) async {
    await AuthService._withNetworkRetry(() => supabase.rpc(
          'yard_toggle_released_delivery',
          params: {
            'p_entry_id': entryId,
            'p_delivered': delivered,
            'p_receipt_no': receiptNo,
            'p_charge': charge,
            'p_handed_at': handedAt?.toIso8601String(),
          },
        ));
  }

  /// Flip a FINAL OUTCOME's hand-over flag (yard OR Central Disposal).
  ///
  /// ⚠️ Delivering also CLOSES THE WAREHOUSE ENTRY, inside the same statement
  /// — see disposal_toggle_outcome_delivery. Doing it here in Dart would leave
  /// a window where the goods are marked gone but still counted in zone
  /// capacity and still accruing storage, and a failure between the two writes
  /// would leave them that way for good.
  /// Record that YARD-DECIDED re-exported goods have actually left.
  ///
  /// ⚠️ A re-export has two events, and they are not the same one: the
  /// yard RULES it (the [FINAL:RE-EXPORTED] tag) and later the goods LEAVE.
  /// The view used to answer the second by asserting `true` for every row,
  /// so the page showed a green Delivered pill on all 17 with nothing to
  /// press -- goods still standing in the yard were indistinguishable from
  /// goods that had gone weeks earlier.
  ///
  /// ⚠️ Unlike [toggleOutcomeDelivery] this does NOT close the warehouse
  /// entry: writing the tag already closed it, on the day the disposition
  /// was recorded. Re-closing would overwrite `returned_at` with today.
  /// ⚠️ The receipt lands in the SAME statement as the flag. Two writes
  /// leave a window where the goods are marked gone with no record of the
  /// money, and a failure between them leaves it that way for good.
  /// Record that goods disposed under an "Other" status have actually left.
  ///
  /// ⚠️ Its own RPC, not the re-export one. That function rejects any entry
  /// not tagged re-export and writes `re_export_delivered` — which would
  /// file these goods as re-exported, which they are not. Like the
  /// re-export and release flags it does NOT close the warehouse entry:
  /// recording the disposition already did.
  Future<void> toggleOtherDelivery(
    String entryId,
    bool delivered, {
    String? receiptNo,
    double? charge,
    DateTime? handedAt,
  }) async {
    await AuthService._withNetworkRetry(() => supabase.rpc(
          'yard_toggle_other_delivery',
          params: {
            'p_entry_id': entryId,
            'p_delivered': delivered,
            'p_receipt_no': receiptNo,
            'p_charge': charge,
            'p_handed_at': handedAt?.toIso8601String(),
          },
        ));
  }

  Future<void> toggleReexportDelivery(
    String entryId,
    bool delivered, {
    String? receiptNo,
    double? charge,
    DateTime? handedAt,
  }) async {
    await AuthService._withNetworkRetry(() => supabase.rpc(
          'yard_toggle_reexport_delivery',
          params: {
            'p_entry_id': entryId,
            'p_delivered': delivered,
            'p_receipt_no': receiptNo,
            'p_charge': charge,
            'p_handed_at': handedAt?.toIso8601String(),
          },
        ));
  }

  Future<void> toggleOutcomeDelivery(String proposalId, bool delivered) async {
    await AuthService._withNetworkRetry(() => supabase.rpc(
          'disposal_toggle_outcome_delivery',
          params: {
            'p_proposal_id': proposalId,
            'p_delivered': delivered,
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
    final fpIds = (fpkgItems as List).map((e) => e['id'] as String).toList();
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

  /// One PAGE of destructions, chosen in SQL.
  ///
  /// ⚠️ The yard's page loaded EVERY destruction with its items, their
  /// forfeited rows, packages, package items and warehouse entries, filtered
  /// by yard, search, date range and year in Dart, and paged the result with
  /// `pageSlice` -- which still loads everything and only renders less.
  ///
  /// `destruction_summary` (postgres/50) answers the filters and the count;
  /// the heavy fetch then runs for one page.
  Future<({List<DestructionModel> rows, int total})> getDestructionsPaged({
    required int offset,
    required int limit,
    String? search,
    String? yardFilter,
    DateTime? dateStart,
    DateTime? dateEnd,
    String? year,
  }) async {
    PgQuery narrow(PgQuery q) {
      final s = search?.trim() ?? '';
      if (s.isNotEmpty) {
        q = q.or('sale_number.ilike.%$s%,sr_numbers.ilike.%$s%,'
            'consignees.ilike.%$s%');
      }
      if (yardFilter != null && yardFilter.isNotEmpty) {
        // ⚠️ Any ITEM's yard, not the destruction's own -- and the
        // forfeited row's yard stands in where destruction_items.yard is
        // empty, which is the screen's `effectiveYard` rule.
        q = q.or('item_yards.ilike.%|$yardFilter|%,'
            'sr_numbers.ilike.%/$yardFilter/%');
      }
      if (dateStart != null) {
        final from = DateTime(dateStart.year, dateStart.month, dateStart.day);
        q = q.gte('sale_date', from.toIso8601String());
      }
      if (dateEnd != null) {
        final to = DateTime(dateEnd.year, dateEnd.month, dateEnd.day, 23, 59, 59);
        q = q.lte('sale_date', to.toIso8601String());
      }
      if (year != null && year.isNotEmpty) {
        // ⚠️ A destruction with NO date matched no year before and must not
        // start matching one now: the range, not a string test on a null.
        q = q.gte('sale_date', '$year-01-01');
        q = q.lte('sale_date', '$year-12-31T23:59:59');
      }
      return q;
    }

    final idRows = await AuthService._withNetworkRetry(() =>
        narrow(supabase.from('destruction_summary').select('id'))
            .order('created_at', ascending: false)
            .range(offset, offset + limit - 1));
    final total = await AuthService._withNetworkRetry(
        () => narrow(supabase.from('destruction_summary')).count());

    final ids = [
      for (final e in (idRows as List))
        (e as Map<String, dynamic>)['id'].toString()
    ];
    if (ids.isEmpty) {
      return (rows: const <DestructionModel>[], total: total as int);
    }

    final data = await AuthService._withNetworkRetry(() => supabase
        .from('destructions')
        .select(
            '*, profiles!created_by(full_name), destruction_items(*, forfeited_packages(*, disposal_request_items!forfeited_package_id(valuation_cost), packages(*, package_items(*), warehouse_entries(*, warehouses(*)))))')
        .inFilter('id', ids)
        .order('created_at', ascending: false));
    final byId = {
      for (final e in (data as List))
        (e as Map<String, dynamic>)['id'].toString(): DestructionModel.fromJson(e)
    };
    // Keep the view's order -- re-sorting here would disagree with the page
    // boundaries the query used.
    return (
      rows: [for (final id in ids) if (byId[id] != null) byId[id]!],
      total: total as int,
    );
  }

  /// The years the destruction year filter offers.
  ///
  /// ⚠️ Over ALL destructions. Built from a page the dropdown would offer
  /// only the years on screen, and a year that is not listed reads as records
  /// that no longer exist.
  Future<List<String>> getDestructionYears() async {
    final data = await AuthService._withNetworkRetry(() => supabase
        .from('destruction_summary')
        .select('sale_date')
        .order('sale_date', ascending: false));
    final years = <String>{};
    for (final e in (data as List)) {
      final d = parseDbDate((e as Map<String, dynamic>)['sale_date']);
      if (d != null) years.add(d.year.toString());
    }
    return years.toList()..sort((a, b) => b.compareTo(a));
  }

  /// The ids of destructions that RE-DESTROY goods from an earlier one.
  ///
  /// ⚠️ Over ALL destructions, not the page: derived from twenty rows a
  /// destruction would be called new simply because its predecessor sat on the
  /// page before.
  Future<Set<String>> getRedestructionIds() async {
    final data = await AuthService._withNetworkRetry(() => supabase
        .from('destruction_summary')
        .select('id, is_redestruction')
        .eq('is_redestruction', true));
    return {
      for (final e in (data as List))
        (e as Map<String, dynamic>)['id'].toString()
    };
  }

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
      // ⚠️ MARKED undestroyed, never inferred from a clock -- and
      // destruction is not a sale, so a selling deadline never belonged here.
      final passed = latest.first.items
          .any((it) => it.forfeitedPackageId == id && it.undestroyed);
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
      result.add(ReDestructionInfo(
          forfeited: f, destructions: eligible[f.id] ?? const []));
    }
    result.sort((a, b) {
      final c = b.timesAttempted.compareTo(a.timesAttempted);
      return c != 0 ? c : a.forfeited.srNumber.compareTo(b.forfeited.srNumber);
    });
    return result;
  }

  Future<List<DisposalRequestItemModel>>
      getDestructionRequestItemsNotDestroyed() async {
    final destsData = await AuthService._withNetworkRetry(() =>
        supabase.from('destruction_items').select('forfeited_package_id'));
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
    /// Sale CLOSE time. The valuation stays sealed until it passes.
    String? saleEndTime,
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
          'sale_end_time': saleEndTime,
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

  /// Mark one destruction package UNDESTROYED explicitly. Moves it immediately
  /// to the Undestroyed pool without waiting for the automatic deadline.
  Future<void> markDestructionItemUndestroyed({
    required String destructionItemId,
  }) async {
    await AuthService._withNetworkRetry(() => supabase
        .from('destruction_items')
        .update({
          'undestroyed': true,
          'undestroyed_at': DateTime.now().toIso8601String(),
        })
        .eq('id', destructionItemId));
    final user = supabase.auth.currentUser;
    if (user != null) {
      await AuditLogService().recordLog(
        userId: user.id,
        action: 'Marked destruction package undestroyed',
        entityType: 'destruction_item',
        entityId: destructionItemId,
        details: {},
      );
    }
  }

  // --- Taxes ---

  /// Set the national daily storage rate.
  ///
  /// ⚠️ Through the RPC, not a direct insert. One row governs every yard
  /// in the country, so "may this user write here" is a question about
  /// their office rather than about a row they own -- and the function
  /// checks that, refuses a rate of zero (which would silently stop every
  /// warehouse charge, showing only as invoices reading LKR 0), and records
  /// WHO set it. The old path inserted straight into the table with no
  /// author column at all, so the history read "System" for every change.
  Future<void> setStorageRate(double rate) async {
    await AuthService._withNetworkRetry(
        () => supabase.rpc('set_storage_rate', params: {'p_rate': rate}));
  }

  Future<List<DisposalTaxModel>> getTaxes() async {
    final data = await AuthService._withNetworkRetry(() => supabase
        .from('disposal_taxes')
        .select()
        .order('created_at', ascending: true));
    return (data as List).map((e) => DisposalTaxModel.fromJson(e)).toList();
  }

  /// Add a levy.
  ///
  /// ⚠️ [isActive] is passed, not assumed. The form offers the switch
  /// when adding as well as editing -- a levy legislated but not yet in
  /// force is a real case, and creating it active would charge it from the
  /// moment it was typed.
  Future<void> createTax(String name, double percentage,
      {bool isActive = true}) async {
    await AuthService._withNetworkRetry(() =>
        supabase.from('disposal_taxes').insert({
          'name': name,
          'percentage': percentage,
          'is_active': isActive,
        }));
  }

  Future<void> updateTax(
      String id, String name, double percentage, bool isActive) async {
    await AuthService._withNetworkRetry(() => supabase
            .from('disposal_taxes')
            .update({
          'name': name,
          'percentage': percentage,
          'is_active': isActive
        }).eq('id', id));
  }

  Future<TenderSaleItemModel?> getTenderSaleItemForPackage(
      String packageId) async {
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
      String packageId, String? packageItemId,
      {String? receipt}) async {
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

    // 3. No sale for THIS item.
    //
    // ⚠️ Return null -- do NOT fall back to the package. A package holds
    // several items with separate histories, and the package-level lookup
    // returns the newest sale row for ANY of them. CED/GL1/OA/07/2026 is
    // exactly that: Truck Tyres was re-exported with no tender at all, and
    // the popup showed it the two rounds, three re-valuations and bids that
    // belong to Ceramic Floor Tiles, the abandoned item still sitting in the
    // yard. Goods that never went to tender were given somebody else's
    // valuation, silently and with no way to tell from the screen.
    //
    // A caller that genuinely wants the package's newest sale can call
    // getTenderSaleItemForPackage directly; asking for one ITEM must not
    // quietly answer about another.
    return null;
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
  /// One PAGE of an Appeal tab, chosen in SQL.
  ///
  /// ⚠️ Both tabs used to fetch EVERY forfeited package in the country --
  /// through packages, their items and their warehouse entries, ~208ms -- then
  /// expand, filter and page the result in Dart with
  /// `pageSlice(rows, page, kClientPageSize)`. Client-side paging still loads
  /// everything; it only renders less.
  ///
  /// Five rules decided what the directorate sees and every one of them ran
  /// here. `appeal_rows` (postgres/45) carries all five, transcribed from the
  /// model and asserted row-for-row against it on the live data -- 136 rows,
  /// 20 active, 9 decided, identical either way.
  ///
  /// The heavy detail is then fetched for THIS page only: the table shows the
  /// goods name and deadline, and its popup the whole package.
  Future<({List<ForfeitedPackageModel> rows, int total, int active, int inWindow, int held})>
      getAppealRowsPaged({
    required int offset,
    required int limit,

    /// Which tab: the appeals still open, or the ones already ruled on.
    required bool decided,
    String? search,
    String? yardFilter,
  }) async {
    PgQuery narrow(PgQuery q) {
      q = decided ? q.eq('has_decision', true) : q.eq('is_active', true);
      final s = search?.trim() ?? '';
      if (s.isNotEmpty) {
        q = q.or('sr_number.ilike.%$s%,consignee_name.ilike.%$s%,'
            'goods_name.ilike.%$s%');
      }
      if (yardFilter != null && yardFilter.isNotEmpty) {
        q = q.or('yard.eq.$yardFilter,sr_number.ilike.%/$yardFilter/%');
      }
      return q;
    }

    final idRows = await AuthService._withNetworkRetry(() =>
        narrow(supabase
                .from('appeal_rows')
                .select('forfeited_package_id, item_id'))
            // ⚠️ Soonest deadline first on the ACTIVE tab, so the appeals
            // needing attention most urgently lead instead of being paged out
            // of sight. The decided tab reads newest-ruling-first, which is
            // the order a record is looked through.
            .order(decided ? 'appeal_decided_at' : 'appeal_deadline',
                ascending: !decided)
            .range(offset, offset + limit - 1));
    final total = await AuthService._withNetworkRetry(
        () => narrow(supabase.from('appeal_rows')).count());

    // ⚠️ The three stat chips count the whole ACTIVE set under the same
    // search and yard, whichever tab is open -- never the page, and never the
    // decided rows. They were folded from the fetched list, which was every
    // forfeit in the country; folded from a page they would report twenty.
    //
    // Their own narrowing, because `narrow` above answers to `decided`: on the
    // Decided tab it would have counted rulings and labelled them Active.
    PgQuery narrowActive(PgQuery q) {
      q = q.eq('is_active', true);
      final s = search?.trim() ?? '';
      if (s.isNotEmpty) {
        q = q.or('sr_number.ilike.%$s%,consignee_name.ilike.%$s%,'
            'goods_name.ilike.%$s%');
      }
      if (yardFilter != null && yardFilter.isNotEmpty) {
        q = q.or('yard.eq.$yardFilter,sr_number.ilike.%/$yardFilter/%');
      }
      return q;
    }

    final active = await AuthService._withNetworkRetry(
        () => narrowActive(supabase.from('appeal_rows')).count());
    final inWindow = await AuthService._withNetworkRetry(() =>
        narrowActive(supabase.from('appeal_rows'))
            .eq('in_appeal_window', true)
            .count());
    final held = await AuthService._withNetworkRetry(() =>
        narrowActive(supabase.from('appeal_rows')).eq('is_held', true).count());

    final ids = <String>[];
    final itemForFp = <String, String?>{};
    for (final e in (idRows as List)) {
      final m = e as Map<String, dynamic>;
      final fpId = m['forfeited_package_id'].toString();
      ids.add(fpId);
      itemForFp[fpId] = m['item_id']?.toString();
    }
    if (ids.isEmpty) {
      return (
        rows: const <ForfeitedPackageModel>[],
        total: total as int,
        active: active as int,
        inWindow: inWindow as int,
        held: held as int
      );
    }

    final rows = await _appealRowsForIds(ids, itemForFp);
    return (
      rows: rows,
      total: total as int,
      active: active as int,
      inWindow: inWindow as int,
      held: held as int
    );
  }

  /// The full detail behind a page of appeal rows.
  ///
  /// ⚠️ The view names a (forfeited row, item) pair; the model this screen
  /// is built on is one object per ROW, with `itemId` set to the item the row
  /// is about. So the fetched forfeited rows are re-pointed at the item the
  /// view chose -- the same thing the Dart expansion did, for one page.
  Future<List<ForfeitedPackageModel>> _appealRowsForIds(
      List<String> ids, Map<String, String?> itemForFp) async {
    final data = await AuthService._withNetworkRetry(() => supabase
        .from('forfeited_packages')
        .select(
            '*, packages(*, package_items(*), warehouse_entries(*, warehouses(*), returned_profile:profiles!returned_by(full_name, badge_number)))')
        .inFilter('id', ids.toSet().toList()));

    final byId = <String, ForfeitedPackageModel>{
      for (final e in (data as List))
        (e as Map<String, dynamic>)['id'].toString():
            ForfeitedPackageModel.fromJson(e)
    };

    // Keep the view order: it sorted the page, and re-sorting here would
    // quietly disagree with the page boundaries.
    final out = <ForfeitedPackageModel>[];
    for (final fpId in ids) {
      final f = byId[fpId];
      if (f == null) continue;
      final itemId = itemForFp[fpId];
      if (itemId == null) {
        out.add(f);
        continue;
      }
      final item =
          f.packageDetails?.items.where((i) => i.id == itemId).firstOrNull;
      // ⚠️ Re-point even when the id already matches. `forfeited_packages`
      // stores no item_name, so a row fetched straight from it carries a null
      // one — and the screen's fallback then shows the package's FIRST item,
      // which is the wrong goods on any multi-item package. The name has to
      // be read off the item the row is actually about.
      if (itemId == f.itemId && item?.itemName == f.itemName) {
        out.add(f);
        continue;
      }
      out.add(ForfeitedPackageModel(
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
        itemId: itemId,
        itemName: item?.itemName ?? f.itemName,
      ));
    }
    return out;
  }

  /// Every genuine forfeited package across all yards (newest deadline first),
  /// with full package + warehouse detail. Unlike the disposal query this does
  /// NOT exclude tendered / requested packages — appeals can be raised at any
  /// point before the window passes. Packages already fully sold/destroyed
  /// (every item finalised) ARE dropped — there's nothing left to appeal.
  Future<List<ForfeitedPackageModel>> getForfeitedPackages() async {
    // Deliberately NOT narrowed by deadline: the Decided tab needs forfeits
    // whose window has long closed, and a held appeal outlives its deadline
    // too. Per-item decisions live in a jsonb map that PostgREST cannot filter
    // on, so any server-side cut risks hiding rows the portal must show.
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

    // One row per (package, item), whatever the table holds.
    //
    // A PACKAGE-level row (item_id IS NULL) expands into every item, so when
    // an SR carries several of them each one expands again and the list
    // multiplies — three package-level rows over three items rendered nine
    // times. De-duplicating here keeps the portal readable even before the
    // underlying rows are cleaned up (see fix_appeal_duplicate_rows.sql).
    //
    // The row carrying the most appeal state wins, so a hold or a decision is
    // never the copy that gets dropped.
    final byTarget = <String, ForfeitedPackageModel>{};
    for (final f in expanded) {
      final key = '${f.packageId}:${f.itemId ?? ''}';
      final existing = byTarget[key];
      if (existing == null) {
        byTarget[key] = f;
        continue;
      }
      int weight(ForfeitedPackageModel m) =>
          (m.hasAppealDecisionForItem(m.itemId) ? 2 : 0) +
          (m.appealHold ? 1 : 0);
      if (weight(f) > weight(existing)) byTarget[key] = f;
    }
    return byTarget.values.toList();
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
  /// Turn a SYNTHETIC appeal-row id into a real `forfeited_packages` id.
  ///
  /// Detain / Abandoned / "Other" goods carry no forfeited_packages row until
  /// something acts on them, so [getInAppealNonForfeitPackages] hands the UI
  /// composite ids of the form "<packageId>:<itemId>:<source>". The appeal
  /// RPCs take a uuid, so the first appeal against such goods creates the row.
  ///
  /// The insert goes through `appeal_ensure_forfeited_row` (SECURITY DEFINER)
  /// because the appeal role holds only SELECT on `forfeited_packages` — a
  /// direct insert from here is refused by RLS. A plain uuid passes straight
  /// through.
  Future<String> _materialiseForfeitedRow(String id) async {
    final parts = id.split(':');
    if (parts.length < 3) return id; // already a real uuid

    final res = await AuthService._withNetworkRetry(
        () => supabase.rpc('appeal_ensure_forfeited_row', params: {
              'p_package_id': parts[0],
              'p_item_id': parts[1],
              'p_source': parts.last,
            }));
    return res.toString();
  }

  Future<void> setAppealHold(String forfeitedId, bool hold,
      {String? note, String? itemId}) async {
    // Detain / Abandoned / "Other" goods have NO forfeited_packages row until
    // something acts on them, so their rows on this portal are synthetic
    // ("<pkgId>:<itemId>:<source>"). The RPC needs a real uuid, so create the
    // row the first time an appeal is lodged against one.
    final realId = await _materialiseForfeitedRow(forfeitedId);

    await AuthService._withNetworkRetry(
        () => supabase.rpc('set_appeal_hold', params: {
              'p_forfeited_id': realId,
              'p_hold': hold,
              'p_note': note,
              'p_item_id': itemId,
            }));
    forfeitedId = realId;
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
    final realId = await _materialiseForfeitedRow(forfeitedId);
    await AuthService._withNetworkRetry(
        () => supabase.rpc('release_appeal_with_decision', params: {
              'p_forfeited_id': realId,
              'p_decision': decision,
              'p_note': note,
              'p_item_id': itemId,
            }));
    forfeitedId = realId;
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

/// Valuation Directorate (SDDC / DDC). A yard's disposal request lands here
/// FIRST: the directorate reads every yard's pending requests (cross-yard),
/// enters a cost per package item, then forwards the request to the Central
/// Disposal Directorate. Only after forwarding does Central Disposal see it.
class ValuationService {
  /// One PAGE of the valuation feed, chosen in SQL.
  ///
  /// ⚠️ This portal had no paging at all -- not SQL paging, not even a
  /// client-side pager. `ListView.separated(itemCount: list.length)` rendered
  /// every request awaiting valuation, behind a query six levels deep:
  /// requests to items to forfeited rows to packages to their items, and
  /// separately to warehouse entries and their warehouses.
  ///
  /// Both membership rules ran in Dart afterwards, which is precisely why a
  /// page could not be asked for by number:
  ///
  ///   * a request stays while ANY of its items is not yet forwarded
  ///   * it belongs to the Perishable tab when EVERY pending item is
  ///     perishable
  ///
  /// `valuation_rows` (postgres/42) answers both, so the page, the count and
  /// the split are all SQL. The heavy detail is then fetched for THIS page's
  /// requests only -- the per-item cost form genuinely needs it.
  Future<({List<DisposalRequestModel> rows, int total})> getValuationFeedPaged({
    required int offset,
    required int limit,

    /// Which tab: perishable batches, or everything else.
    ///
    /// ⚠️ Not a filter over one list but a partition of it. The two tabs
    /// split the same membership, so a request appears on exactly one of them
    /// and can never fall between.
    required bool perishable,
    String? search,
    String? yardFilter,
  }) async {
    PgQuery narrow(PgQuery q) {
      q = q.eq('is_perishable', perishable);
      final s = search?.trim() ?? '';
      if (s.isNotEmpty) {
        q = q.or('sr_numbers.ilike.%$s%,consignees.ilike.%$s%');
      }
      if (yardFilter != null && yardFilter.isNotEmpty) {
        // ⚠️ The item yards too, not just the request's own. A request is
        // filed by one yard but can hold goods from another, and the view
        // carries a pipe-wrapped list of every yard it touches for exactly
        // this reason.
        q = q.or('yard.eq.$yardFilter,item_yards.ilike.%|$yardFilter|%');
      }
      return q;
    }

    final idRows = await AuthService._withNetworkRetry(() =>
        narrow(supabase.from('valuation_rows').select('id'))
            .order('created_at', ascending: false)
            .range(offset, offset + limit - 1));
    final total = await AuthService._withNetworkRetry(
        () => narrow(supabase.from('valuation_rows')).count());

    final ids = [
      for (final e in (idRows as List))
        (e as Map<String, dynamic>)['id'].toString()
    ];
    if (ids.isEmpty) {
      return (rows: const <DisposalRequestModel>[], total: total as int);
    }

    final rows = await _valuationRequestsByIds(ids);
    // Keep the view's order: it sorted the page, and re-sorting here would
    // quietly disagree with the page boundaries.
    final byId = {for (final r in rows) r.id: r};
    return (
      rows: [for (final id in ids) if (byId[id] != null) byId[id]!],
      total: total as int,
    );
  }

  /// The full detail for a PAGE of requests, and only those.
  ///
  /// ⚠️ The embed is deep because the per-item cost form needs it: the
  /// package's items to name the goods, and its warehouse entries because the
  /// quantity being valued is the FORFEITED quantity, which is read off the
  /// entries a forfeit returned. Narrowing it is a separate question from
  /// paging; what matters here is that it now runs for twenty requests
  /// instead of every one in the country.
  Future<List<DisposalRequestModel>> _valuationRequestsByIds(
      List<String> ids) async {
    if (ids.isEmpty) return const [];
    final data = await AuthService._withNetworkRetry(() => supabase
        .from('disposal_requests')
        .select(
            '*, profiles!created_by(full_name), valued_profile:profiles!valued_by(full_name), disposal_request_items(*, forfeited_packages(*, packages(*, package_items(*), warehouse_entries(*, warehouses(*)))))')
        .inFilter('id', ids)
        .order('created_at', ascending: false));
    return _pendingItemsOnly(data as List);
  }

  /// Keeps each request's NOT-YET-FORWARDED items, dropping any request left
  /// with none.
  ///
  /// ⚠️ Shared by the paged feed and the whole-feed fetch, so the two can
  /// never disagree about which items an officer is being asked to cost.
  /// Already-forwarded items have moved on to Central Disposal.
  List<DisposalRequestModel> _pendingItemsOnly(List data) {
    final result = <DisposalRequestModel>[];
    for (final e in data) {
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
    return _pendingItemsOnly(data as List);
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
