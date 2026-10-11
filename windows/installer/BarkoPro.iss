; BarkoPro — Windows kurulum paketi (Inno Setup 6)
; Üretmek için: windows\installer\kurulum_olustur.bat çalıştırın.
;
; Veritabanı kurulum klasörüne DEĞİL, %APPDATA%\BarkoPro\veri klasörüne
; yazılır (uygulama ilk açılışta eski konumdaki veriyi oraya kopyalar).
; Bu yüzden güncelleme/kaldırma işlemi müşteri verisine dokunmaz.

#define AppAdi "BarkoPro"
; Sürüm kurulum_olustur.ps1'den pubspec.yaml'a göre gelir (/DAppSurum=...).
#ifndef AppSurum
  #define AppSurum "2.3.0"
#endif
#define Yayinci "BarkoPro"
#define ExeAdi "halk_market.exe"
#define KaynakDizin "..\..\build\windows\x64\runner\Release"

[Setup]
AppId={{960DAF8A-5D65-4670-BB60-CF5A50680120}
AppName={#AppAdi}
AppVersion={#AppSurum}
AppPublisher={#Yayinci}
DefaultDirName={autopf}\{#AppAdi}
DefaultGroupName={#AppAdi}
DisableProgramGroupPage=yes
OutputDir=..\..\build\kurulum
OutputBaseFilename=BarkoPro_Kurulum_{#AppSurum}
SetupIconFile=..\runner\resources\app_icon.ico
; Sihirbazın sağ üst köşesinde uygulama logosu
WizardSmallImageFile=..\..\assets\images\logo.png
UninstallDisplayIcon={app}\{#ExeAdi}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
; Çalışan uygulama güncelleme sırasında otomatik kapatılır.
CloseApplications=yes
RestartApplications=no
; Kurulum sonunda Windows'a "simgeler değişti" bildirimi gönderir (önbellek yenilenir).
ChangesAssociations=yes

[Languages]
Name: "turkish"; MessagesFile: "compiler:Languages\Turkish.isl"

[Files]
; Geliştirme klasöründeki .dart_tool (yerel veritabanı) ve *.db dosyaları
; ASLA pakete girmez.
Source: "{#KaynakDizin}\*"; DestDir: "{app}"; \
  Excludes: ".dart_tool\*,*.db,*.db-wal,*.db-shm"; \
  Flags: recursesubdirs createallsubdirs ignoreversion
; Kısayol simgesi: ayrı bir .ico dosyası (Windows simge önbelleği, aynı yoldaki
; exe'nin eski simgesini göstermeye devam edebiliyor).
Source: "..\runner\resources\app_icon.ico"; DestName: "BarkoPro.ico"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\{#AppAdi}"; Filename: "{app}\{#ExeAdi}"; IconFilename: "{app}\BarkoPro.ico"
; Masaüstü kısayolu her kurulumda otomatik oluşturulur (uygulama logosuyla).
Name: "{autodesktop}\{#AppAdi}"; Filename: "{app}\{#ExeAdi}"; IconFilename: "{app}\BarkoPro.ico"

[Run]
Filename: "{app}\{#ExeAdi}"; Description: "{#AppAdi} uygulamasını başlat"; \
  Flags: nowait postinstall skipifsilent

[Code]
// Aynı AppId ile kurulu sürüm varsa bu bir GÜNCELLEMEDİR: klasör sorulmaz
// (DisableDirPage=auto), dosyalar üzerine yazılır, veriler (%APPDATA%)
// korunur. Sihirbaz metinleri de "Kur" yerine "Güncelle" der.
var
  Guncelleme: Boolean;
  EskiSurum: String;

function OncekiSurumuBul(var Surum: String): Boolean;
var
  Anahtar: String;
begin
  Anahtar := 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{960DAF8A-5D65-4670-BB60-CF5A50680120}_is1';
  Result := RegQueryStringValue(HKLM64, Anahtar, 'DisplayVersion', Surum)
    or RegQueryStringValue(HKLM32, Anahtar, 'DisplayVersion', Surum)
    or RegQueryStringValue(HKCU, Anahtar, 'DisplayVersion', Surum);
end;

procedure InitializeWizard;
begin
  Guncelleme := OncekiSurumuBul(EskiSurum);
  if Guncelleme then
    WizardForm.Caption := '{#AppAdi} Güncelleme (' + EskiSurum + ' → {#AppSurum})';
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  if not Guncelleme then Exit;
  case CurPageID of
    wpReady:
      begin
        WizardForm.PageNameLabel.Caption := 'Güncellemeye hazır';
        WizardForm.PageDescriptionLabel.Caption :=
          '{#AppAdi} ' + EskiSurum + ' sürümü {#AppSurum} sürümüne güncellenecek.';
        WizardForm.ReadyLabel.Caption :=
          'Satışlarınız, ürünleriniz ve ayarlarınız korunur; yalnızca program dosyaları yenilenir.' + #13#10#13#10 +
          'Devam etmek için Güncelle düğmesine tıklayın.';
        WizardForm.NextButton.Caption := 'Güncelle';
      end;
    wpInstalling:
      begin
        WizardForm.PageNameLabel.Caption := 'Güncelleniyor';
        WizardForm.PageDescriptionLabel.Caption := '{#AppAdi} güncellenirken lütfen bekleyin.';
      end;
    wpFinished:
      begin
        WizardForm.FinishedHeadingLabel.Caption := 'Güncelleme tamamlandı';
        WizardForm.FinishedLabel.Caption :=
          '{#AppAdi} {#AppSurum} sürümüne güncellendi. Verileriniz yerinde.';
      end;
  end;
end;
