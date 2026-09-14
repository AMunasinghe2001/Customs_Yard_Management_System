import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:postgres/postgres.dart';

import 'pg_connection.dart';

/// The signed-in user.
///
/// Deliberately the same shape the app already reads off Supabase's `User`:
/// `.id`, `.email`, `.emailConfirmedAt`, `.userMetadata`. Those four are all
/// the 58 `currentUser` call sites touch, so none of them change.
@immutable
class AuthUser {
  const AuthUser({
    required this.id,
    required this.email,
    this.emailConfirmedAt,
    this.userMetadata = const {},
  });

  final String id;
  final String? email;

  /// Accounts are created already confirmed (see auth.sign_up), so this is
  /// non-null in practice. Kept because verifyUserSession() checks it.
  final DateTime? emailConfirmedAt;

  final Map<String, dynamic> userMetadata;

  factory AuthUser.fromRow(Map<String, dynamic> row) {
    final meta = row['meta'];
    return AuthUser(
      id: row['id'].toString(),
      email: row['email'] as String?,
      emailConfirmedAt: row['email_confirmed_at'] as DateTime?,
      userMetadata: meta == null
          ? const {}
          : (meta is String
              ? Map<String, dynamic>.from(jsonDecode(meta) as Map)
              : Map<String, dynamic>.from(meta as Map)),
    );
  }
}

/// Stands in for Supabase's `Session`.
///
/// There is no refresh token to carry: the session is a row in auth.users and
/// a session variable on the connection. `refreshToken` is the user id, so the
/// existing `setSession(session.refreshToken!)` calls keep working.
@immutable
class AuthSession {
  const AuthSession({required this.user});
  final AuthUser user;
  String get accessToken => user.id;
  String? get refreshToken => user.id;
}

@immutable
class AuthResponse {
  const AuthResponse({this.user, this.session});
  final AuthUser? user;
  final AuthSession? session;
}

/// Mirrors Supabase's `UserAttributes` so `updateUser(...)` call sites are
/// unchanged.
@immutable
class UserAttributes {
  const UserAttributes({this.email, this.password, this.data});
  final String? email;
  final String? password;
  final Map<String, dynamic>? data;
}

/// Mirrors Supabase's `AuthException`, including `code`, which the officer
/// creation flow branches on (`user_already_exists`).
class AuthException implements Exception {
  AuthException(this.message, {this.code, this.statusCode});
  final String message;
  final String? code;

  /// Always null locally — there is no HTTP layer to report a status. Kept
  /// because the sign-in error log prints it.
  final String? statusCode;

  @override
  String toString() => 'AuthException($code): $message';
}

/// The SDK split its auth errors into `AuthException` and `AuthApiException`
/// (the latter being one the server returned). There is no such split here —
/// every auth failure comes from the database — so this is the same class
/// under the name the catch clauses already use.
typedef AuthApiException = AuthException;

/// The SDK's name for the signed-in user. Aliased so `User? user` declarations
/// keep compiling.
typedef User = AuthUser;

/// Only Google was ever wired up, and it cannot work without an internet
/// identity provider. Kept as a name so the call site compiles; calling
/// signInWithOAuth throws a clear message.
enum OAuthProvider { google, azure, github }

/// Sign-in, sign-up and session restore against the local database.
///
/// Every method here does two things: run the matching SQL function, and tell
/// [PgDatabase] who is now acting. The second half is what makes RLS work —
/// `auth.uid()` reads the session variable this sets, so the 73 policies that
/// were written for Supabase apply unchanged.
class PgAuth {
  PgAuth._();
  static final PgAuth instance = PgAuth._();

  /// Sessions are deliberately NOT persisted.
  ///
  /// The Supabase build installed a LocalStorage that stored nothing
  /// (_NoPersistLocalStorage in main.dart), so closing the app always signed
  /// the officer out. That is a deliberate choice for a customs system on a
  /// shared office machine — the next person to open the app must sign in as
  /// themselves — and it is preserved here. Persisting a session would be a
  /// silent weakening of an existing control, not an improvement.
  AuthUser? _currentUser;

  AuthUser? get currentUser => _currentUser;
  AuthSession? get currentSession =>
      _currentUser == null ? null : AuthSession(user: _currentUser!);

  final _stateController = StreamController<AuthUser?>.broadcast();
  Stream<AuthUser?> get onAuthStateChange => _stateController.stream;

  /// Always null: nothing is persisted, so a fresh launch has no session.
  ///
  /// Kept as a call so start-up reads the same either way, and so that turning
  /// persistence on later is a change in one place.
  Future<AuthUser?> restoreSession() async => null;

  /// [email] may equally be a username — auth.sign_in resolves either.
  Future<AuthResponse> signInWithPassword({
    required String email,
    required String password,
  }) async {
    final rows = await PgDatabase.instance.query(
      'select id, email, raw_user_meta_data as meta, email_confirmed_at '
          'from auth.sign_in(@id, @pw)',
      parameters: {'id': email.trim(), 'pw': password},
    );
    if (rows.isEmpty) {
      // Same message and code the SDK used, so existing catch blocks match.
      throw AuthException('Invalid login credentials',
          code: 'invalid_credentials');
    }
    final user = AuthUser.fromRow(rows.first);
    await _adopt(user);
    return AuthResponse(user: user, session: AuthSession(user: user));
  }

  Future<AuthResponse> signUp({
    required String email,
    required String password,
    Map<String, dynamic>? data,
  }) async {
    try {
      final rows = await PgDatabase.instance.query(
        'select id, email, meta, email_confirmed_at from auth.sign_up(@e, @pw, @meta)',
        parameters: {
          'e': email.trim(),
          'pw': password,
          'meta': jsonEncode(data ?? const {}),
        },
      );
      final user = AuthUser.fromRow(rows.first);
      // Note: unlike Supabase, creating an account does NOT switch the active
      // session. The admin stays signed in, which is what the officer-creation
      // flow wanted all along — its save/restore dance is now a no-op.
      return AuthResponse(user: user, session: AuthSession(user: user));
    } on ServerException catch (e) {
      // 23505 is unique_violation; auth.sign_up raises it by name for a
      // duplicate email so this maps back to the SDK's own error code.
      if (e.code == '23505' || e.message.contains('user_already_exists')) {
        throw AuthException('User already registered',
            code: 'user_already_exists');
      }
      rethrow;
    }
  }

  /// Password and/or email and/or metadata, matching the SDK's shape.
  Future<AuthResponse> updateUser(UserAttributes attrs) async {
    final user = _currentUser;
    if (user == null) {
      throw AuthException('Not signed in', code: 'not_authenticated');
    }

    if (attrs.password != null) {
      await PgDatabase.instance.execute(
        'select auth.change_password(@id, @pw)',
        parameters: {'id': user.id, 'pw': attrs.password},
      );
      // ⚠️ Drop the pool so every connection re-asks whether this password is
      // still expired.
      //
      // `setCurrentUser` cannot notice a password change -- the user id is
      // the same, so the pool is never dropped -- and the idle connections
      // still carry the `app.password_expired = on` they were opened with.
      // The officer would have set a valid new password and still been shut
      // out by whichever stale connection their next query landed on. Here
      // rather than in the caller, so every route to a password change gets
      // it. See migration 018.
      await PgDatabase.instance.refreshSessionState();
    }

    if (attrs.email != null || attrs.data != null) {
      try {
        final rows = await PgDatabase.instance.query(
          'select id, email, meta from auth.update_user(@id, @e, @meta)',
          parameters: {
            'id': user.id,
            'e': attrs.email,
            'meta': attrs.data == null ? null : jsonEncode(attrs.data),
          },
        );
        if (rows.isNotEmpty) {
          _currentUser = AuthUser.fromRow(rows.first);
          _stateController.add(_currentUser);
        }
      } on ServerException catch (e) {
        if (e.code == '23505') {
          throw AuthException('This email is already registered.',
              code: 'user_already_exists');
        }
        rethrow;
      }
    }

    return AuthResponse(user: _currentUser, session: currentSession);
  }

  /// Restores a session from the id kept in [AuthSession.refreshToken].
  ///
  /// Supabase needed this because signUp() hijacked the active session; here
  /// nothing hijacks it, so this is normally a no-op that simply re-affirms
  /// who is signed in. Kept so those call sites compile and stay correct.
  Future<AuthResponse> setSession(String refreshToken) async {
    final rows = await PgDatabase.instance.query(
      'select id, email, meta, email_confirmed_at from auth.user_by_id(@id)',
      parameters: {'id': refreshToken},
    );
    if (rows.isEmpty) {
      throw AuthException('Session expired', code: 'session_not_found');
    }
    final user = AuthUser.fromRow(rows.first);
    await _adopt(user);
    return AuthResponse(user: user, session: AuthSession(user: user));
  }

  Future<void> signOut() async {
    _currentUser = null;
    // Clear the database's idea of the user too, or the next query on this
    // shared connection would still run as the person who just left.
    await PgDatabase.instance.setCurrentUser(null);
    _stateController.add(null);
  }

  /// OAuth has no local equivalent — there is no identity provider on an
  /// office LAN. Fails clearly rather than appearing to work.
  Future<bool> signInWithOAuth(Object provider, {String? redirectTo}) async {
    throw AuthException(
      'Google sign-in is not available on the local server. '
      'Sign in with your username and password.',
      code: 'oauth_unavailable',
    );
  }

  /// Records who is signed in, and — the part that matters for security —
  /// tells the database, so auth.uid() starts returning this id and the RLS
  /// policies apply to the right person.
  Future<void> _adopt(AuthUser user) async {
    _currentUser = user;
    await PgDatabase.instance.setCurrentUser(user.id);
    _stateController.add(user);
  }
}
