; Template Inno Setup custom do Cockpit (plano 47). Referenciado por
; `script_template: inno_template.iss` no make_config.yaml. Baseado no template
; default do fastforge (flutter_app_packager) + as diretivas de self-update.
; As variáveis {{...}}/{% %} são preenchidas pelo fastforge (Liquid).
[Setup]
AppId={{APP_ID}}
AppVersion={{APP_VERSION}}
AppName={{DISPLAY_NAME}}
AppPublisher={{PUBLISHER_NAME}}
AppPublisherURL={{PUBLISHER_URL}}
AppSupportURL={{PUBLISHER_URL}}
AppUpdatesURL={{PUBLISHER_URL}}
DefaultDirName={{INSTALL_DIR_NAME}}
DisableProgramGroupPage=yes
OutputDir=.
OutputBaseFilename={{OUTPUT_BASE_FILENAME}}
Compression=lzma
SolidCompression=yes
SetupIconFile={{SETUP_ICON_FILE}}
WizardStyle=modern
PrivilegesRequired={{PRIVILEGES_REQUIRED}}
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
; Plano 47 — self-update via WinSparkle. Num update silencioso o cockpit pode
; estar rodando: o Restart Manager fecha a instância (CloseApplications) e a
; relança após instalar (RestartApplications). O WinSparkle encerra o app antes
; de rodar o instalador, então o RM vê uma instância só — sem duplo-launch.
; VALIDAR no Windows real (não testável neste Mac).
CloseApplications=yes
RestartApplications=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: {% if CREATE_DESKTOP_ICON != true %}unchecked{% else %}checkedonce{% endif %}

[Files]
Source: "{{SOURCE_DIR}}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; NOTE: Don't use "Flags: ignoreversion" on any shared system files

[Icons]
Name: "{autoprograms}\{{DISPLAY_NAME}}"; Filename: "{app}\{{EXECUTABLE_NAME}}"
Name: "{autodesktop}\{{DISPLAY_NAME}}"; Filename: "{app}\{{EXECUTABLE_NAME}}"; Tasks: desktopicon

[Run]
Filename: "{app}\{{EXECUTABLE_NAME}}"; Description: "{cm:LaunchProgram,{{DISPLAY_NAME}}}"; Flags: nowait postinstall skipifsilent
