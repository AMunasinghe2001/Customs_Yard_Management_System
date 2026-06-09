# Auto-Update Release Process

The app checks for updates in the background via the `auto_updater` package
(WinSparkle on Windows). It reads [appcast.xml](appcast.xml) from a **public**
Supabase Storage bucket named `updates`.

- Feed URL (auto-derived in code, [lib/core/app_updater.dart](../lib/core/app_updater.dart)):
  `https://tstlaauujhrrpjxhvorf.supabase.co/storage/v1/object/public/updates/appcast.xml`
- Background check runs on startup + every 6 hours; users get a "New update
  available" prompt only when the appcast advertises a higher `sparkle:version`.

## One-time setup
1. Supabase Dashboard → Storage → **New bucket** → name `updates`, mark **Public**.
2. Upload `appcast.xml` (and optionally `release_notes.html`).

## On every release
1. Bump the version in [pubspec.yaml](../pubspec.yaml) (e.g. `1.0.1+2`).
2. Build: `flutter build windows`.
3. Package the installer with Inno Setup → e.g. `SLCustoms-Setup-1.0.1.exe`.
4. Edit [appcast.xml](appcast.xml):
   - `<title>` / `<sparkle:version>` / `<sparkle:shortVersionString>` → new version
   - `enclosure url` → uploaded installer's public URL
   - `enclosure length` → installer size in **bytes**
   - `pubDate` → current date
   - (production) `sparkle:edSignature` → signature of the .exe (see below)
5. Upload the new `.exe` **and** the updated `appcast.xml` to the `updates` bucket
   (overwrite the old appcast).

## Signing (recommended for production)
WinSparkle verifies updates with an EdDSA signature. Generate a key pair with the
WinSparkle `generate_keys` tool, embed the **public** key in the Windows runner,
sign each installer with the **private** key, and put the result in
`sparkle:edSignature` on the `<enclosure>`. Without signing, only use trusted
networks. See: https://github.com/vslavik/winsparkle/wiki

## Notes
- Version comparison uses the Windows executable version, which Flutter derives
  from `pubspec.yaml`'s `version:` field — always bump it.
- Native plugin linking can only be confirmed with a real `flutter build windows`.
