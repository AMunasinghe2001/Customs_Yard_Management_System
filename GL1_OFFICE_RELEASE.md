# GL1 Office Release

This branch produces two deployment targets without changing the database target of the other branches:

- `cloud`: Supabase database and the shared cloud update feed.
- `gl1-office`: GL1 PostgreSQL server, with updates disabled so a cloud release cannot replace it.

## Build the GL1 installer

Run from the repository root in PowerShell. Use the real `yard_app` and Gmail app-password values; do not commit them.

```powershell
.\tool\publish_release.ps1 `
  -Deployment gl1-office `
  -OfficeHost 10.10.71.39 `
  -OfficePort 5432 `
  -OfficeDatabase Customs_SR_DB `
  -OfficeUser yard_app `
  -DbPassword '<GL1 yard_app password>' `
  -GmailPassword '<Gmail app password>' `
  -Notes 'GL1 office release'
```

Output:

```text
installer\output\SLCustoms-SR-Setup-<version>-GL1-Office.exe
```

The installer writes a first-install `.env` beside the executable with `PG_PROFILE=office`, the GL1 server address, `Customs_SR_DB`, and the supplied credentials. An existing deliberate `.env` is preserved.

The GL1 build uses the isolated `gl1-office` update channel. Upload the installer first, then upload these two generated files to the `gl1-office/` folder in the public `updates` bucket:

```text
installer\output\gl1-office\appcast.xml
installer\output\gl1-office\latest.json
```

Cloud releases use the root `updates/` folder. Never upload a Cloud feed into `gl1-office/`, or a GL1 feed into the root folder.

## GitHub-only updates

The database and update hosting can both avoid Supabase. The repository must be public, or the PCs need authenticated access; a private repository's raw files and release assets return `404` to the app.

Use a public `gh-pages` branch for the two feed files and a GitHub Release for the installer asset. For version `1.7.0`, create a release tag such as `gl1-office-v1.7.0`, upload the installer there, then build the feeds with:

```powershell
.\tool\publish_release.ps1 `
  -Deployment gl1-office `
  -DbPassword '<GL1 yard_app password>' `
  -GmailPassword '<Gmail app password>' `
  -UpdateFeedUrl 'https://raw.githubusercontent.com/AMunasinghe2001/Customs_Yard_Management_System/gh-pages/gl1-office/appcast.xml' `
  -UpdateManifestUrl 'https://raw.githubusercontent.com/AMunasinghe2001/Customs_Yard_Management_System/gh-pages/gl1-office/latest.json' `
  -UpdateArtifactBaseUrl 'https://github.com/AMunasinghe2001/Customs_Yard_Management_System/releases/download/gl1-office-v1.7.0'
```

Upload the generated `installer\output\gl1-office\appcast.xml` and `latest.json` to the same paths in the public `gh-pages` branch. The next GL1 build uses a new tag and the same feed paths. Cloud builds use their own feed path and release tag.

## Build the cloud installer

```powershell
.\tool\publish_release.ps1 `
  -Deployment cloud `
  -DbPassword '<Supabase yard_app password>' `
  -GmailPassword '<Gmail app password>' `
  -Notes 'Cloud release'
```

Output:

```text
installer\output\SLCustoms-SR-Setup-<version>-Cloud.exe
```

## Requirements

- Run `flutter doctor` successfully.
- Install Inno Setup 6 so `ISCC.exe` is available. The repository build script does not install it automatically.
- Run the server migration and create `yard_app` on the GL1 PostgreSQL server before installing the client.
- Keep the matching `build\symbols\<version>+<build>` directory with the release artifact.

The Git branch for this work is `release/gl1-office`.
