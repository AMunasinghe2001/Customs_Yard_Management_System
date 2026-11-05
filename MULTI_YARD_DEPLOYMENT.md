# Multi-Yard Deployment Architecture & Release Guide

This document describes the multi-yard build and update pipeline for the Sri Lanka Customs Yard Management System.

Each yard (GL1, GL2, GL3, RCT, Cloud, etc.) can maintain its own isolated server database, installation package, and GitHub update channel without collisions.

---

## 1. Deployment Profiles (`tool/deployment_profiles.json`)

All yard profiles are declared centrally in [`tool/deployment_profiles.json`](tool/deployment_profiles.json).

Supported profiles out of the box:
* `cloud`: Central Supabase cloud database and default update channel.
* `gl1-office`: Grey Line 1 yard office server (`10.10.71.39`).
* `gl2-office`: Grey Line 2 yard office server (`10.10.72.39`).
* `gl3-office`: Grey Line 3 yard office server (`10.10.73.39`).
* `rct-office`: RCT yard office server (`10.10.74.39`).

To add a new yard in the future, simply add an entry to `deployment_profiles.json`. Even if a yard is not declared in JSON, passing a custom deployment name (e.g. `-Deployment gl4-office -OfficeHost 10.10.75.39`) automatically generates the proper profile dynamically.

---

## 2. Building Yard Releases

Building a release for any yard is handled by [`tool/publish_release.ps1`](tool/publish_release.ps1).

### For GL1 Office (GitHub-Hosted Updates):
```powershell
.\tool\publish_release.ps1 `
  -Deployment gl1-office `
  -DbPassword '<GL1 yard_app password>' `
  -GmailPassword '<Gmail app password>' `
  -UseGitHubUpdates `
  -Notes 'GL1 release notes'
```

### For GL2 Office (GitHub-Hosted Updates):
```powershell
.\tool\publish_release.ps1 `
  -Deployment gl2-office `
  -DbPassword '<GL2 yard_app password>' `
  -GmailPassword '<Gmail app password>' `
  -UseGitHubUpdates `
  -Notes 'GL2 release notes'
```

### Overriding Host / Parameters Dynamically:
You can override any profile parameter directly via CLI flags:
```powershell
.\tool\publish_release.ps1 `
  -Deployment gl2-office `
  -OfficeHost 192.168.1.100 `
  -DbPassword '<password>' `
  -GmailPassword '<app-password>' `
  -UseGitHubUpdates
```

---

## 3. Automated Update Channels (GitHub Releases & gh-pages)

When `-UseGitHubUpdates` is supplied:
1. **GitHub Releases Tag Convention**:
   * Cloud: `v1.7.0`
   * GL1: `gl1-office-v1.7.0`
   * GL2: `gl2-office-v1.7.0`
   * Yard X: `<channel>-v<version>`
2. **gh-pages Update Feeds**:
   Feeds are cleanly isolated in branch `gh-pages` under subdirectories:
   * `gh-pages/gl1-office/appcast.xml` & `latest.json`
   * `gh-pages/gl2-office/appcast.xml` & `latest.json`
   * `gh-pages/appcast.xml` & `latest.json` (for Cloud)

### Publishing Checklist per Yard Release:
1. Upload installer `installer\output\SLCustoms-SR-Setup-<version>-<Yard>-Office.exe` to GitHub Releases under tag `<channel>-v<version>`.
2. Commit & push the generated feed files from `installer\output\<channel>\` (`appcast.xml`, `latest.json`) to the corresponding channel directory in branch `gh-pages`.

