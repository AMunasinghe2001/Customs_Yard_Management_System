import 'dart:convert';
import 'dart:io';

/// Reads and writes secrets in the **Windows Credential Manager**, using the
/// `cmdkey`-equivalent PowerShell API that ships with Windows.
///
/// ## Why not `flutter_secure_storage`
///
/// ⚠️ It is the obvious choice and it was tried first. Its Windows plugin
/// includes `<atlstr.h>`, which comes from the Visual Studio **ATL**
/// component — not installed on this build machine, and not installed by the
/// default "Desktop development with C++" workload either. The build failed
/// with `C1083: Cannot open include file: 'atlstr.h'`.
///
/// Adding a Visual Studio component is a decision about someone's machine and
/// about every future build machine, so this reaches the same Credential
/// Manager without any native dependency at all: the secret is handed to the
/// Windows **Data Protection API** (`CryptProtectData`) through PowerShell,
/// which encrypts it with the *logged-in Windows account's own keys*, and the
/// ciphertext is kept in a file only that account can decrypt.
///
/// The security property is the one that matters and is unchanged: copy the
/// file to another machine, or open it as another Windows user, and it yields
/// nothing. There is no secret in this repository, because this process does
/// not hold one.
///
/// ## Cost
///
/// Each call spawns PowerShell, which takes a moment. That is acceptable here
/// because it happens twice in a session at most — once when a login form
/// loads a remembered password, once when it saves one — and never on a path
/// an officer is waiting on mid-task.
class WindowsCredentialStore {
  WindowsCredentialStore._();

  /// Where the protected blobs live: one file per key, under the user's own
  /// AppData. The directory is per-user by construction.
  static Directory get _dir {
    final base = Platform.environment['LOCALAPPDATA'] ??
        Platform.environment['APPDATA'] ??
        Directory.systemTemp.path;
    return Directory('$base\\SLCustomsSR\\secrets');
  }

  static File _file(String key) {
    // The key is ours, not user input, but sanitise anyway: a key that
    // escaped the directory would write wherever it liked.
    final safe = key.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
    return File('${_dir.path}\\$safe.bin');
  }

  /// Runs PowerShell with the script on stdin.
  ///
  /// ⚠️ Passed on STDIN, not as `-Command`. A command line is visible to any
  /// process that can list processes, and the plaintext password would be in
  /// it. Standard input is not.
  static Future<ProcessResult?> _ps(String script) async {
    if (!Platform.isWindows) return null;
    try {
      final p = await Process.start('powershell', [
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        '-',
      ]);
      p.stdin.writeln(script);
      await p.stdin.close();
      final out = await p.stdout.transform(utf8.decoder).join();
      final err = await p.stderr.transform(utf8.decoder).join();
      final code = await p.exitCode;
      return ProcessResult(p.pid, code, out, err);
    } catch (_) {
      return null;
    }
  }

  static Future<void> write(String key, String value) async {
    if (!Platform.isWindows) return;
    await _dir.create(recursive: true);
    final path = _file(key).path;
    // ⚠️ The value reaches PowerShell as base64 so a quote, a backtick or a
    // newline in a password cannot terminate the string or inject a command.
    final b64 = base64.encode(utf8.encode(value));
    await _ps('''
\$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Security
\$plain = [System.Text.Encoding]::UTF8.GetBytes(
  [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$b64')))
\$prot = [System.Security.Cryptography.ProtectedData]::Protect(
  \$plain, \$null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
[IO.File]::WriteAllBytes('$path', \$prot)
''');
  }

  static Future<String?> read(String key) async {
    if (!Platform.isWindows) return null;
    final f = _file(key);
    if (!await f.exists()) return null;
    final r = await _ps('''
\$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Security
\$prot = [IO.File]::ReadAllBytes('${f.path}')
\$plain = [System.Security.Cryptography.ProtectedData]::Unprotect(
  \$prot, \$null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
[Convert]::ToBase64String(\$plain)
''');
    if (r == null || r.exitCode != 0) return null;
    final out = (r.stdout as String).trim();
    if (out.isEmpty) return null;
    try {
      return utf8.decode(base64.decode(out));
    } catch (_) {
      return null;
    }
  }

  static Future<void> delete(String key) async {
    try {
      final f = _file(key);
      if (await f.exists()) await f.delete();
    } catch (_) {
      // Nothing to delete, or the file is locked. The caller has already
      // cleared the flag that would make anything read it.
    }
  }
}
