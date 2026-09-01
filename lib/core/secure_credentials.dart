import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Encrypts password values before persisting them in SharedPreferences so they
/// are not stored in plain text on disk.
///
/// This is intentionally platform-neutral and does not require any native C++
/// bindings. For production hardening, pass a strong runtime secret via
/// --dart-define=APP_SECRET=... and avoid using the fallback value.
class SecureCredentialStore {
  static const String _defaultAppSecret =
      'SriLankaCustomsYardManagement-LOCAL-DEV-DO-NOT-USE-IN-PROD';

  static String _appSecret() {
    return const String.fromEnvironment(
      'APP_SECRET',
      defaultValue: _defaultAppSecret,
    );
  }

  static String _deriveKey(String seed) {
    final material = utf8.encode('${_appSecret()}::$seed::${Platform.operatingSystemVersion}');
    final digest = sha256.convert(material).bytes;
    return base64Url.encode(digest).replaceAll('=', '');
  }

  static String _encrypt(String plainText, String seed) {
    final key = utf8.encode(_deriveKey(seed));
    final value = utf8.encode(plainText);
    final out = <int>[];
    for (var i = 0; i < value.length; i++) {
      final k = key[i % key.length];
      out.add(value[i] ^ k);
    }
    return base64Url.encode(out);
  }

  static String _decrypt(String cipherText, String seed) {
    final encoded = base64Url.decode(cipherText);
    final key = utf8.encode(_deriveKey(seed));
    final out = <int>[];
    for (var i = 0; i < encoded.length; i++) {
      final k = key[i % key.length];
      out.add(encoded[i] ^ k);
    }
    return utf8.decode(out);
  }

  static Future<void> save(
    String keyPrefix, {
    required String emailOrId,
    required String password,
    required bool rememberMe,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    if (!rememberMe) {
      await clear(keyPrefix);
      return;
    }

    await prefs.setString('${keyPrefix}_email', emailOrId.trim());
    await prefs.setBool('${keyPrefix}_remember_me', true);

    final cipher = _encrypt(password, keyPrefix);
    await prefs.setString('${keyPrefix}_password_enc', cipher);
  }

  static Future<Map<String, dynamic>> load(String keyPrefix) async {
    final prefs = await SharedPreferences.getInstance();
    final rememberMe = prefs.getBool('${keyPrefix}_remember_me') ?? false;
    final emailOrId = prefs.getString('${keyPrefix}_email') ?? '';

    String password = '';
    if (rememberMe) {
      final encrypted = prefs.getString('${keyPrefix}_password_enc') ?? '';
      if (encrypted.isNotEmpty) {
        password = _decrypt(encrypted, keyPrefix);
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
  }
}
