#define MyProgName "SL Customs SR Management"
#define MyProgVersion "1.0.0"
#define MyProgPublisher "SL Customs"
#define MyProgExeName "cus_yard_management.exe"
#define MyProgIconName "app_icon.ico"
#define VCRedistPath "C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Redist\MSVC\14.50.35710\vc_redist.x64.exe"

[Setup]
AppId={{D3E5F6A7-B8C9-4D0E-BF1A-2C3D4E5F6G7H}
AppName={#MyProgName}
AppVersion={#MyProgVersion}
AppPublisher={#MyProgPublisher}
DefaultDirName={autopf}\{#MyProgName}
DisableProgramGroupPage=yes
PrivilegesRequired=admin
OutputDir=d:\Company\Cus_Yard_Management\installer
OutputBaseFilename=SL_Customs_Setup
Compression=lzma
SolidCompression=yes
WizardStyle=modern
SetupIconFile=d:\Company\Cus_Yard_Management\windows\runner\resources\{#MyProgIconName}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; Main EXE and DLLs
Source: "d:\Company\Cus_Yard_Management\build\windows\x64\runner\Release\{#MyProgExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "d:\Company\Cus_Yard_Management\build\windows\x64\runner\Release\*.dll"; DestDir: "{app}"; Flags: ignoreversion
; Data folder
Source: "d:\Company\Cus_Yard_Management\build\windows\x64\runner\Release\data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs
; VC Redistributable
Source: "{#VCRedistPath}"; DestDir: "{tmp}"; Flags: deleteafterinstall

[Icons]
Name: "{autoprograms}\{#MyProgName}"; Filename: "{app}\{#MyProgExeName}"
Name: "{autodesktop}\{#MyProgName}"; Filename: "{app}\{#MyProgExeName}"; Tasks: desktopicon

[Run]
; Install VC Redistributable
Filename: "{tmp}\vc_redist.x64.exe"; Parameters: "/install /quiet /norestart"; Check: not IsVCRedistInstalled; StatusMsg: "Installing Visual C++ Redistributable..."
; Launch app after install
Filename: "{app}\{#MyProgExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyProgName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[Code]
function IsVCRedistInstalled: Boolean;
var
  Version: String;
begin
  // Check for VC++ 2015-2022 Redistributable (x64)
  // This key is used by 2015, 2017, 2019, and 2022 runtimes
  Result := RegQueryStringValue(HKEY_LOCAL_MACHINE, 'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64', 'Version', Version);
end;
