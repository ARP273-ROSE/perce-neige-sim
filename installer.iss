; ---------------------------------------------------------------------------
; Installeur Windows — gabarit commun du kit.
;
; Rien ici n'est propre a une application : toutes les valeurs arrivent en
; /D depuis le workflow, qui les lit dans kit.json. Ce fichier est donc
; identique d'un projet a l'autre.
;
; Choix structurants :
;  - PrivilegesRequired=lowest : installation dans le profil de l'utilisateur,
;    donc AUCUNE fenetre UAC et aucun mot de passe administrateur demande.
;  - Le programme installe n'est pas un executable compile mais la
;    distribution embeddable officielle de Python : les antivirus ne s'en
;    emeuvent pas.
;  - Les donnees de l'utilisateur ne sont jamais placees dans le dossier
;    d'installation : elles survivent ainsi aux mises a jour comme a une
;    desinstallation suivie d'une reinstallation.
;
; Compilation :
;   iscc installer.iss /DAppVersion=1.2.3 /DSourceDir=... /DAppName=... \
;        /DAppDisplayName=... /DAppId=... /DIconFile=... /DEntry=...
; ---------------------------------------------------------------------------

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "dist"
#endif
#ifndef AppName
  #define AppName "Application"
#endif
#ifndef AppDisplayName
  #define AppDisplayName AppName
#endif
#ifndef AppId
  #define AppId "{{A0000000-0000-0000-0000-000000000000}"
#endif
#ifndef IconFile
  #define IconFile "logo.ico"
#endif
#ifndef Entry
  #define Entry "app.py"
#endif
#define AppPublisher "Kevin"

[Setup]
AppId={#AppId}
AppName={#AppDisplayName}
AppVersion={#AppVersion}
AppVerName={#AppDisplayName} {#AppVersion}
AppPublisher={#AppPublisher}
VersionInfoVersion={#AppVersion}

; Installation par utilisateur : pas d'elevation, pas d'UAC.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
DefaultDirName={localappdata}\Programs\{#AppName}
DisableDirPage=yes
DefaultGroupName={#AppDisplayName}
DisableProgramGroupPage=yes

OutputDir=installer_out
OutputBaseFilename={#AppName}-Setup-{#AppVersion}
SetupIconFile={#IconFile}
UninstallDisplayIcon={app}\app\{#IconFile}
UninstallDisplayName={#AppDisplayName}

; LZMA2/max : ~360 Mo de source tombent aux alentours de 120-150 Mo.
Compression=lzma2/max
SolidCompression=yes
InternalCompressLevel=max

WizardStyle=modern
ShowLanguageDialog=no
AllowNoIcons=yes
; Windows 10 1809 minimum, impose par Qt 6.11.
MinVersion=10.0.17763

[Languages]
Name: "french"; MessagesFile: "compiler:Languages\French.isl"

[Tasks]
Name: "desktopicon"; Description: "Créer un raccourci sur le Bureau"; \
    GroupDescription: "Raccourcis :"; Flags: checkedonce

[Files]
; Tout le paquet : python embarque, code applicatif, binaires eventuels.
Source: "{#SourceDir}\*"; DestDir: "{app}"; \
    Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
; On lance le .bat via un raccourci qui masque la console : le .bat se contente
; d'appeler pythonw.exe, qui n'ouvre aucune fenetre.
Name: "{group}\{#AppDisplayName}"; Filename: "{app}\python\pythonw.exe"; \
    Parameters: """{app}\app\{#Entry}"""; \
    WorkingDir: "{app}\app"; IconFilename: "{app}\app\{#IconFile}"
; Lanceur de secours : quand rien ne demarre, c'est le seul moyen de voir
; l'erreur. Le guide d'installation y renvoie.
Name: "{group}\Diagnostic"; Filename: "{app}\Diagnostic.bat"; \
    WorkingDir: "{app}"; IconFilename: "{app}\app\{#IconFile}"
Name: "{group}\Désinstaller {#AppDisplayName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppDisplayName}"; Filename: "{app}\python\pythonw.exe"; \
    Parameters: """{app}\app\{#Entry}"""; \
    WorkingDir: "{app}\app"; IconFilename: "{app}\app\{#IconFile}"; \
    Tasks: desktopicon

[Run]
Filename: "{app}\python\pythonw.exe"; Parameters: """{app}\app\{#Entry}"""; \
    WorkingDir: "{app}\app"; \
    Description: "Démarrer {#AppDisplayName}"; \
    Flags: nowait postinstall skipifsilent

[UninstallDelete]
; Bytecode et journaux regeneres a l'execution : ils n'appartiennent pas a
; l'utilisateur, on peut les effacer sans scrupule.
Type: filesandordirs; Name: "{app}\app\__pycache__"
Type: files; Name: "{app}\app\*.log*"

[Code]
// La base de donnees vit hors du dossier d'installation. On previent tout de
// meme l'utilisateur de ce qui est conserve, pour qu'il ne croie pas avoir
// tout perdu, ni au contraire penser que tout a disparu.
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  DataDir: String;
begin
  if CurUninstallStep = usPostUninstall then
  begin
    DataDir := ExpandConstant('{localappdata}\{#AppName}');
    if DirExists(DataDir) then
      // Le nom de l'application n'apparait pas dans ce message, et c'est
      // volontaire : une apostrophe dans le nom (« Machine d'Anticythere »)
      // terminerait la chaine Pascal et le script ne compilerait plus.
      MsgBox('La desinstallation est terminee.' + #13#10 + #13#10 +
             'Vos donnees ont ete conservees dans :' + #13#10 + DataDir + #13#10 + #13#10 +
             'Si vous reinstallez cette application, vous les retrouverez ' +
             'telles quelles. Pour tout effacer, supprimez ce dossier a la main.',
             mbInformation, MB_OK);
  end;
end;
