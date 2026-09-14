import 'package:shared_preferences/shared_preferences.dart';

import 'windows_credential_store.dart';

/// Where a "remember me" sign-in is kept.
///
/// The password is protected by the **Windows Data Protection API**, keyed to
/// the logged-in Windows account; the e-mail and the remember-me flag stay in
/// SharedPreferences, because neither is a secret and the login form needs
/// them before any credential prompt.
///
/// ## ⚠️ What this replaced, and why it had to go
///
/// The previous version XOR-ed the password against a SHA-256 digest and wrote
/// the result to SharedPreferences — a plain JSON file in the user's roaming
/// profile. Three things were wrong with it:
///
///   * **XOR with a repeating key is not encryption.** Given any guess at the
///     plaintext — and "the password field of a login form" is a narrow guess —
///     the key falls out by subtraction, and the same key then decrypts every
///     other portal's saved password on that machine.
///   * **The key was in the source.** It derived from `APP_SECRET`, whose
///     fallback was a string literal in this very file. Every build that did
///     not pass `--dart-define=APP_SECRET=...` shipped with the same secret,
///     and anyone holding the repository held the key.
///   * **It was reversible by design.** The file could be copied off the
///     machine and decrypted anywhere; nothing bound it to the PC it was
///     written on.
///
/// [WindowsCredentialStore] hands the value to the Windows Data Protection
/// API, which encrypts it with the **logged-in Windows account's own keys**.
/// Copying the file to another machine, or opening it as another Windows user,
/// yields nothing. There is no secret for this repository to leak, because
/// this process no longer holds one.
///
/// ⚠️ `flutter_secure_storage` would be the obvious choice and was tried
/// first. Its Windows plugin needs the Visual Studio ATL component, which is
/// not in the default C++ workload — the build failed with
/// `C1083: Cannot open include file: 'atlstr.h'`. Requiring a Visual Studio
/// component of every future build machine is a worse trade than calling the
/// same DPAPI directly. See [WindowsCredentialStore].
class SecureCredentialStore {
  static String _pwKey(String keyPrefix) => '${keyPrefix}_password';

  static Future<void> save(
    String keyPrefix, {
    required String emailOrId,
    required String password,
    required bool rememberMe,
  }) async {
    if (!rememberMe) {
      await clear(keyPrefix);
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('${keyPrefix}_email', emailOrId.trim());
    await prefs.setBool('${keyPrefix}_remember_me', true);

    await WindowsCredentialStore.write(_pwKey(keyPrefix), password);

    // ⚠️ Remove the old XOR blob if this machine still carries one. Left in
    // place it would sit in the profile for the life of the installation,
    // holding a recoverable password that nothing reads any more.
    await prefs.remove('${keyPrefix}_password_enc');
  }

  static Future<Map<String, dynamic>> load(String keyPrefix) async {
    final prefs = await SharedPreferences.getInstance();
    final rememberMe = prefs.getBool('${keyPrefix}_remember_me') ?? false;
    final emailOrId = prefs.getString('${keyPrefix}_email') ?? '';

    var password = '';
    if (rememberMe) {
      try {
        password = await WindowsCredentialStore.read(_pwKey(keyPrefix)) ?? '';
      } catch (_) {
        // A credential store that refuses to open must not stop the officer
        // signing in — it only means they type the password.
        password = '';
      }
      // ⚠️ A password saved by the OLD build is deliberately NOT migrated.
      // Reading it would mean decrypting the weak blob to re-encrypt it, and
      // the officer types the password on this one sign-in instead. The blob
      // is deleted either way, below.
      if (prefs.getString('${keyPrefix}_password_enc') != null) {
        await prefs.remove('${keyPrefix}_password_enc');
      }
    }

    return {
      'email': emailOrId,
      'password': password,
      'remember_me': rememberMe,
    };
  }

  static Future<void> clear(String keyPrefix) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('${keyPrefix}_email');
    await prefs.remove('${keyPrefix}_remember_me');
    await prefs.remove('${keyPrefix}_password_enc');
    try {
      await WindowsCredentialStore.delete(_pwKey(keyPrefix));
    } catch (_) {
      // Nothing to delete, or the store is unavailable. The flag above is
      // already gone, so nothing will be loaded.
    }
  }
}
