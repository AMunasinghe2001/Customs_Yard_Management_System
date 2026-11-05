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
