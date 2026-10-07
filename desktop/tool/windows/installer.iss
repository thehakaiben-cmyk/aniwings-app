; Inno Setup Script for AniWings Desktop
; Creates a lightweight, single-file setup installer without requiring admin rights.

#define MyAppName "AniWings Desktop"
#define MyAppPublisher "AniWings"
#define MyAppURL "https://aniwings-app.pages.dev"
#define MyAppExeName "aniwings.exe"

#ifndef MyAppVersion
  #define MyAppVersion "1.2.5"
#endif

#ifndef MySourceDir
  #define MySourceDir "..\..\build\windows\x64\runner\Release"
#endif

#ifndef MyOutputDir
  #define MyOutputDir "..\..\release"
#endif

#ifndef MyOutputBaseFilename
  #define MyOutputBaseFilename "aniwings-desktop-windows-v" + MyAppVersion + "-setup"
#endif

#ifndef MyIconPath
  #define MyIconPath "..\..\windows\runner\resources\app_icon.ico"
#endif

[Setup]
AppId={{E591F79A-4BB1-44B4-8461-9042BD37C64B}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={localappdata}\Programs\AniWings
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir={#MyOutputDir}
OutputBaseFilename={#MyOutputBaseFilename}
SetupIconFile={#MyIconPath}
UninstallDisplayIcon={app}\{#MyAppExeName}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#MySourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
