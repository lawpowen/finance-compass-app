#ifndef AppVersion
  #define AppVersion "0.8.0"
#endif
#ifndef SourceDir
  #error SourceDir must point to the Flutter Windows Release directory.
#endif
#ifndef OutputDir
  #define OutputDir "..\..\artifacts\release"
#endif

[Setup]
AppId={{4C92AA20-8BAA-4C4B-B43D-7E91D97A8D56}
AppName=Finance Compass
AppVersion={#AppVersion}
AppVerName=Finance Compass {#AppVersion}
AppPublisher=lawpowen
AppPublisherURL=https://github.com/lawpowen-cte/finance-compass-app
AppSupportURL=https://github.com/lawpowen-cte/finance-compass-app/issues
AppUpdatesURL=https://github.com/lawpowen-cte/finance-compass-app/releases/latest
DefaultDirName={localappdata}\Programs\Finance Compass
DefaultGroupName=Finance Compass
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#OutputDir}
OutputBaseFilename=FinanceCompass-Windows-x64-Setup-v{#AppVersion}
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\FinanceCompass.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
SetupLogging=yes
VersionInfoVersion={#AppVersion}.0
VersionInfoCompany=lawpowen
VersionInfoDescription=Finance Compass Windows installer
VersionInfoProductName=Finance Compass

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Finance Compass"; Filename: "{app}\FinanceCompass.exe"
Name: "{autodesktop}\Finance Compass"; Filename: "{app}\FinanceCompass.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\FinanceCompass.exe"; Description: "Launch Finance Compass"; Flags: nowait postinstall skipifsilent
