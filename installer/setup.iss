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
#define AppVersion     "1.3.0"
#define AppPublisher   "Sri Lanka Customs Department"
#define AppExeName     "cus_yard_management.exe"
#define BuildDir       "..\build\windows\x64\runner\Release"

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
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

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
; ⚠️ Files the APP writes, which the installer never copied and so would
; otherwise be left behind: the connection settings the operator placed here,
; and the diagnostic log. Everything else came from [Files] and is removed by
; Inno Setup itself.
Type: files; Name: "{app}\.env"
Type: files; Name: "{app}\frame_watch.log"
; The templates themselves came from [Files] and Inno Setup removes them, but
; the folder holding them is not cleaned up on its own once they are gone.
Type: dirifempty; Name: "{app}\env-templates"
