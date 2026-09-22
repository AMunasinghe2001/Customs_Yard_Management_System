import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'windows_credential_store.dart';

/// A stable identifier for THIS PC, sent to the database at connection time so
/// an unapproved machine can be refused a session.
///
/// ## What it is, and what it is not
///
/// ⚠️ It is **not a secret and not a credential.** It says *which computer*
/// this is; the password and the one-time code still say *who* the officer is.
/// Its only job is to bound where a leaked password can be used — a password
/// taken from a Grey Line officer is no use on a laptop at home, because that
/// laptop is not in the register.
///
/// Treating it as a secret would be a mistake in the other direction: anyone
/// who can read the machine can read it, so the database must never accept it
/// *instead of* authentication. `sr_auth.sign_in` checks it **as well as**, never
/// in place of.
///
/// ## How it is derived
///
/// The Windows machine GUID, salted and hashed. The GUID is stable across
/// reboots, upgrades and user accounts, and unique per installation of
/// Windows — which is exactly the grain ICT approves at ("this PC in Grey Line
/// 1"), rather than per user or per session.
///
/// ⚠️ Hashed rather than sent raw. The raw GUID identifies the machine to
/// anything that sees it, including in an audit row an officer can read; the
/// hash identifies it only to this system. The salt is a fixed string, not a
/// secret: it stops the value colliding with the same GUID hashed by some
/// other application.
///
/// The result is cached in the credential store so the registry is read once
/// per installation rather than once per connection.
class DeviceId {
  DeviceId._();

  static const _salt = 'slc-sr-device-v1';
  static const _cacheKey = 'device_id_v1';

  static String? _cached;

  /// This machine's id, or an empty string if it cannot be determined.
  ///
  /// ⚠️ Empty is NOT a failure the app should refuse to start on. With an
  /// empty device register the database allows every machine, so a PC whose
  /// GUID cannot be read keeps working until ICT actually turns enforcement
  /// on — at which point the honest answer is that this machine needs
  /// approving, and the sign-in error says so.
  static Future<String> get() async {
    if (_cached != null) return _cached!;

    try {
      final cached = await WindowsCredentialStore.read(_cacheKey);
      if (cached != null && cached.isNotEmpty) {
        _cached = cached;
        return cached;
      }
    } catch (_) {
      // The credential store is unavailable; derive it again below.
    }

    final raw = await _machineGuid();
    if (raw.isEmpty) {
      _cached = '';
      return '';
    }

    final id = sha256
        .convert(utf8.encode('$_salt::$raw'))
        .toString()
        .substring(0, 32)
        .toUpperCase();

    try {
      await WindowsCredentialStore.write(_cacheKey, id);
    } catch (_) {
      // Not cached this time; it is derived again next start.
    }
    _cached = id;
    return id;
  }

  /// The Windows machine GUID from the registry.
  ///
  /// ⚠️ Read through `reg query` rather than a registry package: this is the
  /// one value needed, the command ships with Windows, and adding a native
  /// dependency for a single read is a poor trade.
  static Future<String> _machineGuid() async {
    if (!Platform.isWindows) {
      // Nothing else is supported today. Returning empty leaves the machine
      // unidentified rather than inventing an id that changes every run.
      return '';
    }
    try {
      final r = await Process.run('reg', [
        'query',
        r'HKLM\SOFTWARE\Microsoft\Cryptography',
        '/v',
        'MachineGuid',
      ]);
      if (r.exitCode != 0) return '';
      final out = (r.stdout as String).trim();
      // The line reads: MachineGuid    REG_SZ    <guid>
      final m = RegExp(r'MachineGuid\s+REG_SZ\s+(\S+)').firstMatch(out);
      return m?.group(1) ?? '';
    } catch (_) {
      return '';
    }
  }
}
