; ============================================================
; PrezioHub Installer - Inno Setup Script
; Soleco AG
;
; Voraussetzung: Zuerst build_all.py ausfuehren!
; Dann diese Datei in Inno Setup oeffnen und kompilieren.
;
; Download Inno Setup: https://jrsoftware.org/isdl.php
; ============================================================

#define MyAppName "PrezioHub"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "Soleco AG"
#define MyAppURL "https://soleco.ch"
#define MyAppExeName "PrezioHub.exe"
#define MyAppCopyright "© 2026 Soleco AG - Noé Gloor"

[Setup]
AppId={{B3F7A2D1-9E4C-4A8B-B5D6-7F2E1C3A9D8E}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppCopyright={#MyAppCopyright}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName=Soleco AG\{#MyAppName}
AllowNoIcons=yes
OutputDir=installer_output
OutputBaseFilename=PrezioHub_Setup_{#MyAppVersion}
SetupIconFile=prezio_hub.ico
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\{#MyAppExeName}
UninstallDisplayName={#MyAppName}
VersionInfoVersion={#MyAppVersion}.0
VersionInfoCompany={#MyAppPublisher}
VersionInfoCopyright={#MyAppCopyright}
VersionInfoProductName={#MyAppName}

[Languages]
Name: "german"; MessagesFile: "compiler:Languages\German.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Desktop-Verknuepfung erstellen"; GroupDescription: "Zusaetzliche Optionen:"
Name: "imagericon"; Description: "PrezioImager Desktop-Verknuepfung"; GroupDescription: "Zusaetzliche Optionen:"

[Files]
Source: "dist\PrezioHub\PrezioHub.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "dist\PrezioHub\PrezioImager.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "dist\PrezioHub\PrezioRecorder.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "dist\PrezioHub\PrezioDummy.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "dist\PrezioHub\prezio_hub.ico"; DestDir: "{app}"; Flags: ignoreversion
Source: "dist\PrezioHub\docs\*"; DestDir: "{app}\docs"; Flags: ignoreversion recursesubdirs

[Icons]
Name: "{group}\PrezioHub"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\PrezioImager"; Filename: "{app}\PrezioImager.exe"
Name: "{group}\Deinstallieren"; Filename: "{uninstallexe}"
Name: "{autodesktop}\PrezioHub"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon
Name: "{autodesktop}\PrezioImager"; Filename: "{app}\PrezioImager.exe"; Tasks: imagericon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "PrezioHub jetzt starten"; Flags: nowait postinstall skipifsilent
