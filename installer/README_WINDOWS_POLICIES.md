# "An Application Control policy has blocked this file"

Written for: the Department's IT / network administrators.

An officer installing the SR Management System sees:

```
Unable to execute file:
C:\Program Files\SL Customs\SR Management System\cus_yard_management.exe

CreateProcess failed; code 4551.
An Application Control policy has blocked this file.
```

## What this is

**Code 4551 is Windows refusing to start the program, not a fault in it.**
Nothing is corrupt and nothing is infected. The build is not
*code-signed*, and this PC runs a policy — Smart App Control, WDAC or
AppLocker — that only starts signed executables.

The same setup file runs normally on a PC without that policy, which is
why it works on some machines and not others.

## The three ways out

| | Cost | Scope | Permanent |
|---|---|---|---|
| **1. A path rule** | none | this Department | yes |
| **2. Sign the build** | ~$200–400/yr | everywhere | yes |
| 3. Turn the policy off | none | one PC | ⚠️ see below |

### 1. A path rule — recommended for now

Allow the one folder the app installs into. It needs administrator rights
on the PC, or a Group Policy push for the whole Department.

**AppLocker** (Group Policy):

```
Computer Configuration
  └ Windows Settings
      └ Security Settings
          └ Application Control Policies
              └ AppLocker
                  └ Executable Rules
```

New Rule → **Allow** → Everyone → **Path** →

```
C:\Program Files\SL Customs\*
```

`Program Files` is itself writable only by administrators, so a path rule
there does not let an ordinary user drop in something new and have it
allowed. A rule over a user-writable folder — `Downloads`, `%TEMP%`,
`C:\Users\*` — would, so do not widen it.

**WDAC**: add a `FilePath` rule for the same folder, or a `Publisher` rule
once the build is signed (option 2).

**Smart App Control**: ⚠️ it takes no exceptions. It is all-or-nothing per
PC, and once turned off it **cannot be turned back on** without
reinstalling Windows. If it is enabled on the office PCs, the practical
answers are option 2 or an AppLocker/WDAC policy that replaces it.

### 2. Sign the build — the real fix

A code-signing certificate ends this for every machine, present and
future, and removes the SmartScreen "unknown publisher" warning as well.

- **OV** (Organisation Validation) — ~$200–400/year. The Department is
  validated once; the certificate then signs every release.
- **EV** (Extended Validation) — dearer, ships on a hardware token, and
  carries SmartScreen reputation from the first download.

Issuers include Sectigo, DigiCert and GlobalSign. Signing is then one step
in the release:

```powershell
signtool sign /fd SHA256 /tr http://timestamp.sectigo.com /td SHA256 `
  /f customs-codesign.pfx /p <password> `
  installer\output\SLCustoms-SR-Setup-<version>.exe
```

⚠️ **Always timestamp** (`/tr`). Without it every signature expires with
the certificate, and installers already distributed stop being trusted.

⚠️ Sign the **setup** *and* the app `.exe` inside it. A signed installer
that unpacks an unsigned program is blocked at the moment the officer
starts the app rather than at install — harder to diagnose, not safer.

### 3. Turning the policy off

Only sensible on a single test machine.

⚠️ **Smart App Control cannot be re-enabled.** Turning it off is a
one-way door; the only way back is reinstalling Windows. Do not do this on
an officer's PC to work around an install.

## What to tell the officer

> This is our own Department software. Windows blocks it because it is not
> yet digitally signed. Please ask IT to allow
> `C:\Program Files\SL Customs\` — no setting on your PC needs changing.

## For whoever builds the release

The unsigned build is what the Department uses today, and the installer is
correct in every other respect: it carries the Visual C++ runtime, and
writes a working `.env` on a first install. Signing is the only missing
piece, and it is a purchasing decision rather than a code change.
