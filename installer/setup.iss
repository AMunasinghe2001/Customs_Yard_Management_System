; ============================================================================
;  Sri Lanka Customs — SR Management System
;  Windows installer (Inno Setup 6)
;
;  Build:
;      flutter build windows --release
;      "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" installer\setup.iss
;
;  The .exe lands in  installer\output\SLCustoms-SR-Setup-<version>.exe
; ============================================================================

#define AppName        "Sri Lanka Customs SR Management System"
#define AppShortName   "SR Management System"
; ⚠️ Bump this for every release. The AppId below stays the SAME, which is
; what makes Windows treat a new setup as an UPGRADE of the installed copy
; rather than a second product: the officer runs it over the old one and
; keeps their shortcuts, their install folder and their .env.
#define AppVersion     "1.5.2"
#define AppPublisher   "Sri Lanka Customs Department"
#define AppExeName     "cus_yard_management.exe"
#define BuildDir       "..\build\windows\x64\runner\Release"

; ⚠️ The database password, for the .env this installer writes on a
; first install. Passed in at COMPILE time, never committed:
;
;     ISCC.exe /DDbPassword="..." installer\setup.iss
;
; tool\publish_release.ps1 -DbPassword '<...>' does that. Left out,
; no .env is written and the officer copies a template as before.
#ifndef DbPassword
  #define DbPassword ""
#endif

; ⚠️ THE GMAIL APP PASSWORD, for the same .env.
;
; Without it the app reaches the database fine and then stops at
; "E-mail is not configured" -- because sign-in sends a one-time code,
; so no mail means nobody can get in at all. A fresh install with no
; Gmail keys is not a half-configured app; it is a locked one.
;
; Passed at COMPILE time, never committed, exactly like DbPassword:
;
;     ISCC.exe /DGmailPassword="..." installer\setup.iss
;
; tool\publish_release.ps1 -GmailPassword '<...>' does that.
#ifndef GmailPassword
  #define GmailPassword ""
#endif
#ifndef GmailUser
  #define GmailUser "otpproject3@gmail.com"
#endif
#ifndef GmailFromName
  #define GmailFromName "SL Customs"
#endif

; The Supabase project. Every PC reaches this; there is no office
; server.
;
; ⚠️ THE SESSION POOLER, never db.<ref>.supabase.co. The direct host
; is IPv6-ONLY and fails from an IPv4 network -- most of Sri Lanka --
; as "Network is unreachable", which reads like a dead server and is
; not. The project ref belongs in the USERNAME here, not the host.
#define DbHost     "aws-0-ap-south-1.pooler.supabase.com"
#define DbPort     "5432"
#define DbName     "postgres"
#define DbUser     "yard_app.knqpwufqpcoevjaxuihp"

[Setup]
; ⚠️ Never reuse this GUID for another product. Windows identifies the
; installation by it, so a second app sharing it would upgrade over this one.
AppId={{7B3E1C42-9A6D-4F58-BE21-0C5D8A4F17E9}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
DefaultDirName={autopf}\SL Customs\SR Management System
DefaultGroupName=Sri Lanka Customs
DisableProgramGroupPage=yes

; ── The agreement the officer must accept ──────────────────────────────────
; ⚠️ This is what puts the "I accept the agreement" page in front of Next.
; Without LicenseFile the wizard skips straight past it.
LicenseFile=LICENSE.txt

; Installing into Program Files needs administrator rights. Asking up front is
; better than failing halfway through the copy.
PrivilegesRequired=admin

; The window's own icon, and the icon Add/Remove Programs shows.
;
; ⚠️ Taken from the SOURCE tree, not the build output. Flutter compiles the
; icon INTO the exe as a resource, so there is no .ico file under Release\ to
; point at — a path there fails the compile with "file not found".
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExeName}
UninstallDisplayName={#AppShortName}

; ⚠️ CLOSING THE APP BEFORE REPLACING ITS FILES.
;
; Windows locks the DLLs of a running process, so an install over a copy
; that is still open failed partway through with
;
;     \auto_updater_windows_plugin.dll
;     DeleteFile failed; code 5. Access is denied.
;
; and offered the officer "Try again", "Skip this file (not recommended)"
; or "Cancel". None of those is safe -- skipping leaves a half-updated
; install where the .exe is new and a plugin is old.
;
; AppMutex names a mutex the app creates at start-up (windows/runner/
; main.cpp). Setup waits for it to disappear and asks the officer to close
; the app, instead of discovering the lock mid-copy. The name must match
; that file EXACTLY.
AppMutex=Global\SLCustomsSRManagementSystem

; Let Setup close the app itself where it can, and restart it afterwards.
;
; ⚠️ `force` also covers a window that is not responding to a polite
; close. Without it, an app sitting on a modal dialog -- the update notice
; itself, for instance -- blocks the install it was telling the officer to
; run.
CloseApplications=force
RestartApplications=yes

; ⚠️ And do NOT let the officer wave the failure through. The default
; offers "Skip this file", which produces an install nobody can diagnose
; later. With this, a locked file stops the install cleanly and it can be
; run again once the app is closed.
CloseApplicationsFilter=*.exe,*.dll

OutputDir=output
OutputBaseFilename=SLCustoms-SR-Setup-{#AppVersion}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern

; The app is 64-bit only; offering it on 32-bit Windows would install
; something that cannot start.
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Shortcuts:"

[Files]
; The whole release folder: the exe, the Flutter runtime, the plugin DLLs and
; the assets. Recursesubdirs picks up data\ and its flutter_assets.
; ⚠️ EXCLUDES .env AND THE LOG.
;
; `flutter run` leaves a copy of the DEVELOPER'S .env in this folder, and
; a bare wildcard swept it into the installer -- so every officer received
; the developer's database password and the live Gmail App Password, and
; their app pointed at `localhost` instead of the office server. Verified
; by installing a build and reading the .env it produced.
;
; The [Code] section writes a correct .env after the copy; without this
; exclusion it would find the stale one already there and leave it alone.
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs; Excludes: ".env,frame_watch.log"

; ⚠️ The .env is NOT installed.
;
; It names the database server and carries the application password, and it
; differs per office. Shipping one inside the installer would put a live
; credential in every copy of the setup file and point every branch at
; whichever server happened to be in the build. The Deployment note tells the
; officer to place it beside the exe after installing.
; ⚠️ THE VISUAL C++ RUNTIME, beside the exe.
;
; cus_yard_management.exe imports msvcp140.dll, vcruntime140.dll and
; vcruntime140_1.dll. They are NOT part of Windows -- they arrive with the
; Visual C++ 2015-2022 Redistributable, which a development machine has and
; a freshly-imaged office PC may not. Without them the app does not show an
; error: Windows refuses to start the process at all, with
;
;     The code execution cannot proceed because VCRUNTIME140.dll was not
;     found. Reinstalling the program may fix this problem.
;
; -- which is the one fault our own "Cannot reach the database" screen can
; never explain, because no Dart code has run yet.
;
; ⚠️ Copied into the app folder rather than System32, and only if
; absent. Windows looks beside the .exe first, so a local copy is enough;
; writing to System32 would need to version-check against every other
; program on the machine, and a wrong answer there breaks THEM.
;
; These are the redistributable copies from the VC toolset (not the ones in
; System32), which Microsoft licenses for shipping alongside an application.
Source: "vcredist\msvcp140.dll";     DestDir: "{app}"; Flags: onlyifdoesntexist
Source: "vcredist\vcruntime140.dll"; DestDir: "{app}"; Flags: onlyifdoesntexist
Source: "vcredist\vcruntime140_1.dll"; DestDir: "{app}"; Flags: onlyifdoesntexist

Source: "DEPLOYMENT.txt"; DestDir: "{app}"; Flags: ignoreversion

; ⚠️ TEMPLATES, deliberately named .env.txt and put in a SUBFOLDER.
;
; They carry no password and no real hostname, so nothing secret ships. Two
; of them because one installer serves both cases: an office wired to the
; local server, and one reaching the cloud. The operator copies the right one
; up a level, renames it to .env and fills in the two blanks.
;
; ⚠️ NOT dropped straight into {app} as ".env". `onlyifdoesntexist` would
; look like the safe way to do that, but a template placed there on a fresh
; install would leave the app with a file full of placeholders instead of no
; file at all -- and "cannot reach the database" while a .env plainly exists
; is a far more confusing fault than the same message with none.
Source: "env-templates\local-server.env.txt"; DestDir: "{app}\env-templates"; Flags: ignoreversion
Source: "env-templates\cloud-server.env.txt"; DestDir: "{app}\env-templates"; Flags: ignoreversion
Source: "env-templates\supabase.env.txt"; DestDir: "{app}\env-templates"; Flags: ignoreversion
; The Supabase pooler is signed by Supabase's OWN root CA, which is not in
; the Windows trust store. Without this file PG_SSL_VERIFY=true fails as
; "Bad server certificate". It is a public certificate, not a secret.
Source: "certs\supabase-root-2021.crt"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\{#AppShortName}"; Filename: "{app}\{#AppExeName}"
Name: "{group}\Uninstall {#AppShortName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppShortName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "Start {#AppShortName}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; ⚠️ EVERYTHING THE APP WROTE, which the installer never copied and
; so would otherwise be left behind for the next install to inherit.
;
; That inheritance is not hypothetical: a stale .env left in place is
; exactly what made an installed copy keep reaching for `localhost` and
; keep using a revoked Gmail password, long after the build carried the
; right settings. An uninstall has to leave nothing behind, or "uninstall
; and reinstall" -- the first thing anybody tries -- fixes nothing.
;
; Order matters: files and subfolders first, the folder itself last.

; The connection settings, and the copy this installer set aside when it
; replaced a stale one.
Type: files; Name: "{app}\.env"
Type: files; Name: "{app}\.env.replaced-by-setup"

; Diagnostic logs -- frame_watch.log today, by wildcard whatever is added
; later, so this does not have to be revisited.
Type: files; Name: "{app}\*.log"

; ⚠️ `data` HOLDS ONLY SHIPPED ASSETS -- the Flutter runtime, fonts,
; icons. The app keeps nothing of the officer's there (its logs live in
; %APPDATA%, and the records are in PostgreSQL), so removing it destroys
; no work. Inno removes the files it copied, but a stray file dropped in
; beside them leaves the tree standing.
Type: filesandordirs; Name: "{app}\data"

; The templates came from [Files] and are removed with them; the folder
; holding them is not cleaned up on its own once they are gone.
Type: filesandordirs; Name: "{app}\env-templates"

; ⚠️ AND THE FOLDER ITSELF, last.
;
; `dirifempty` and not a blanket delete, deliberately: if anything the
; installer does not know about is still in there -- an export somebody
; saved next to the program, a note -- it stays, and so does the folder.
; Removing a directory by wildcard would take those with it, and an
; uninstaller has no business deleting files it never created.
Type: dirifempty; Name: "{app}"

[Code]
//  ⚠️ WRITE A .env ON A FIRST INSTALL, AND ONLY THEN.
//
//  Zero-configuration: the officer runs the setup and signs in. Without
//  this they must find env-templates, copy a file up one level, rename it
//  past Windows hidden-extension behaviour and type a password -- while
//  the app says "Cannot reach the database", which reads like a broken
//  install rather than an unfinished one.
//
//  ⚠️ AN EXISTING .env IS NEVER TOUCHED. It is how a branch points at
//  its own server, and an upgrade that overwrote it would silently move
//  every such office back to the default one. That is also why this is
//  written here rather than in [Files]: `onlyifdoesntexist` would cover
//  the overwrite, but not the "no password was compiled in" case below.
//  Whether an existing .env still points somewhere this build can use.
//
//  ⚠️ AN UPGRADE MUST NOT SILENTLY RE-POINT A BRANCH PC. A .env is
//  how a machine is deliberately aimed at a local copy, a backup or a
//  test database, and overwriting every one of them on upgrade would
//  move those back to the default server with nothing said.
//
//  But a file left by an OLD installer is a different thing: the
//  wildcard copy used to sweep the developer's own .env into the
//  package, so installed copies carried `PG_HOST=localhost` and a
//  since-revoked Gmail password. Those are not a choice anybody made
//  and they cannot work -- the app shows "Cannot reach the database"
//  or fails to send the sign-in code.
//
//  So: replace a file that is BROKEN, keep one that is merely
//  DIFFERENT. A .env naming a real server -- any host that is not
//  loopback -- is somebody's decision and is left alone.
function EnvLooksStale(const Path: string): Boolean;
var
  Lines: TArrayOfString;
  I: Integer;
  L, HostVal: string;
begin
  Result := False;
  HostVal := '';
  if not LoadStringsFromFile(Path, Lines) then
    Exit;

  for I := 0 to GetArrayLength(Lines) - 1 do
  begin
    L := Trim(Lines[I]);
    if (L = '') or (Copy(L, 1, 1) = '#') then
      Continue;
    if Pos('PG_HOST=', L) = 1 then
      HostVal := LowerCase(Trim(Copy(L, Length('PG_HOST=') + 1,
                                     Length(L))));
  end;

  //  ⚠️ Only a LOOPBACK host counts as stale. `localhost` in an
  //  installed copy means the sweep put it there -- no officer PC runs
  //  its own PostgreSQL. A LAN address or any other hostname is a
  //  deliberate choice and is never touched.
  //
  //  A .env with no PG_HOST at all is also replaced: it cannot connect
  //  anywhere, so there is nothing to preserve.
  Result := (HostVal = '') or (HostVal = 'localhost') or
            (HostVal = '127.0.0.1') or (HostVal = '[::1]');
end;

procedure WriteDefaultEnv();
var
  Path, Backup: string;
  Lines: TArrayOfString;
  Pw, GmailPw: string;
begin
  Path := ExpandConstant('{app}\.env');

  Pw := '{#DbPassword}';
  GmailPw := '{#GmailPassword}';
  if Pw = '' then
    Exit;

  if FileExists(Path) then
  begin
    if not EnvLooksStale(Path) then
      Exit;

    //  ⚠️ KEPT, NOT DISCARDED. It may hold a password or a note
    //  nobody else has a copy of. Renaming costs nothing and makes
    //  this reversible; deleting it would not be.
    Backup := Path + '.replaced-by-setup';
    DeleteFile(Backup);
    RenameFile(Path, Backup);
  end;

  //  ⚠️ QUOTE THE PASSWORD, ALWAYS.
  //
  //  dotenv treats an unquoted `#` as the start of a comment, so a
  //  password containing one is silently truncated -- and the app then
  //  reports "password authentication failed", which sends the reader to
  //  the server instead of to this line. Quoting every password rather
  //  than only the awkward ones leaves no rule to remember.
  SetArrayLength(Lines, 18);
  Lines[0] := '# Written by the installer on first install.';
  Lines[1] := '# Edit this file to point this PC at another server, then';
  Lines[2] := '# restart the app. An upgrade keeps it, unless it still';
  Lines[12] := '# points at localhost, which no officer PC can serve.';
  Lines[3] := 'PG_HOST={#DbHost}';
  Lines[4] := 'PG_PORT={#DbPort}';
  Lines[5] := 'PG_DATABASE={#DbName}';
  Lines[6] := 'PG_USER={#DbUser}';
  Lines[7] := 'PG_PASSWORD="' + Pw + '"';
  //  ⚠️ TLS, VERIFIED, against Supabase's own root.
  //
  //  This connection crosses the public internet carrying the
  //  password and every seizure record. PG_SSL alone encrypts but
  //  accepts ANY certificate, so anything on the path could present
  //  its own and read the lot -- PG_SSL_VERIFY is what stops that.
  //
  //  ⚠️ And the pooler is signed by Supabase's OWN root, which
  //  Windows does not trust: without the .crt (shipped beside the
  //  exe) a verified connection fails as "Bad server certificate".
  //  Never answer that by setting PG_SSL_VERIFY=false.
  Lines[8]  := 'PG_SSL=true';
  Lines[9]  := 'PG_SSL_VERIFY=true';
  Lines[10] := 'PG_SSL_ROOT_CERT=supabase-root-2021.crt';
  //  The cloud is further away than a LAN server.
  Lines[11] := 'PG_CONNECT_TIMEOUT=30';

  //  ⚠️ The Gmail keys go in the SAME file, because sign-in needs
  //  them. Quoted like the database password: a Google App Password is
  //  shown as four space-separated groups, and an unquoted value with
  //  spaces is a different string once dotenv has read it.
  //
  //  Left blank at compile time, the keys are written empty rather
  //  than omitted, so the file still SHOWS what is missing when an
  //  officer opens it after "E-mail is not configured".
  Lines[13] := '';
  Lines[14] := '# The account that sends the sign-in codes.';
  Lines[15] := 'GMAIL_USER={#GmailUser}';
  Lines[16] := 'GMAIL_APP_PASSWORD="' + GmailPw + '"';
  Lines[17] := 'GMAIL_FROM_NAME={#GmailFromName}';

  //  ⚠️ Written WITHOUT a BOM. Innos UTF-8 mode prefixes one, and
  //  dotenv reads those three bytes as part of the first key -- so
  //  `PG_HOST` becomes an unrecognised name and the app falls back to
  //  localhost with no visible reason. Every byte written above is plain
  //  ASCII, so the ANSI form is exact.
  SaveStringsToFile(Path, Lines, False);
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
    WriteDefaultEnv();
end;
