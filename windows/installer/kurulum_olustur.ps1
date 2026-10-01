# BarkoPro — Windows kurulum paketi üretici.
# Çalıştırma:  windows\installer\kurulum_olustur.bat   (çift tık)
#
# 1) flutter build windows  (Release)
# 2) VC++ çalışma zamanı DLL'lerini Release klasörüne kopyalar (hedef
#    bilgisayarda Visual C++ Yeniden Dağıtılabilir paketi kurulu olmasa da
#    uygulama açılsın diye)
# 3) Taşınabilir ZIP üretir (build\kurulum\BarkoPro_Tasinabilir_<surum>.zip)
# 4) Inno Setup (ISCC.exe) kuruluysa tek dosyalık kurulum sihirbazı üretir
#    (build\kurulum\BarkoPro_Kurulum_<surum>.exe)

$ErrorActionPreference = 'Stop'
$kok = Resolve-Path (Join-Path $PSScriptRoot '..\..')
Set-Location $kok

# Sürüm: pubspec.yaml  version: 2.3.0+2  -> 2.3.0
$surum = ((Select-String -Path 'pubspec.yaml' -Pattern '^version:\s*([0-9.]+)').Matches[0].Groups[1].Value)
Write-Host "Sürüm: $surum"

if (Get-Process halk_market -ErrorAction SilentlyContinue) {
  Write-Host 'HATA: BarkoPro açık. Kapatıp tekrar çalıştırın (dosyalar kilitli).' -ForegroundColor Red
  exit 1
}

Write-Host '1/4  Derleniyor (flutter build windows)...'
flutter build windows -t lib/ana.dart
if ($LASTEXITCODE -ne 0) { Write-Host 'Derleme başarısız.' -ForegroundColor Red; exit 1 }

$release = Join-Path $kok 'build\windows\x64\runner\Release'

Write-Host '2/4  VC++ çalışma zamanı kopyalanıyor...'
foreach ($dll in 'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll') {
  $kaynak = Join-Path $env:WINDIR "System32\$dll"
  if (Test-Path $kaynak) { Copy-Item $kaynak $release -Force }
  else { Write-Host "  uyarı: $dll bulunamadı" -ForegroundColor Yellow }
}

$cikis = Join-Path $kok 'build\kurulum'
New-Item -ItemType Directory -Force $cikis | Out-Null

Write-Host '3/4  Taşınabilir ZIP hazırlanıyor...'
# Geliştirme veritabanı (.dart_tool, *.db) pakete girmesin.
$gecici = Join-Path $cikis 'BarkoPro'
if (Test-Path $gecici) { Remove-Item $gecici -Recurse -Force }
Copy-Item $release $gecici -Recurse
Get-ChildItem $gecici -Force -Recurse -Include '*.db', '*.db-wal', '*.db-shm' | Remove-Item -Force
$dartTool = Join-Path $gecici '.dart_tool'
if (Test-Path $dartTool) { Remove-Item $dartTool -Recurse -Force }
$zip = Join-Path $cikis "BarkoPro_Tasinabilir_$surum.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path $gecici -DestinationPath $zip
Remove-Item $gecici -Recurse -Force
Write-Host "  -> $zip"

Write-Host '4/4  Kurulum sihirbazı (Inno Setup)...'
$iscc = @(
  "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
  "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
  "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1

if ($iscc) {
  & $iscc (Join-Path $PSScriptRoot 'BarkoPro.iss')
  if ($LASTEXITCODE -eq 0) {
    Write-Host "  -> $cikis\BarkoPro_Kurulum_$surum.exe" -ForegroundColor Green
  } else {
    Write-Host 'Inno Setup derlemesi başarısız.' -ForegroundColor Red; exit 1
  }
} else {
  Write-Host '  Inno Setup bulunamadı — kurulum sihirbazı üretilmedi.' -ForegroundColor Yellow
  Write-Host '  https://jrsoftware.org/isdl.php adresinden "Inno Setup 6" kurup bu betiği tekrar çalıştırın.'
}
Write-Host 'Bitti.'
