$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$sdk = Join-Path $env:LOCALAPPDATA "Android\Sdk"
$bt = Join-Path $sdk "build-tools\35.0.0"
$androidJar = Join-Path $sdk "platforms\android-34\android.jar"
$out = Join-Path $root "out"
$gen = Join-Path $out "gen"
$classes = Join-Path $out "classes"
$dexDir = Join-Path $out "dex"

Remove-Item -Recurse -Force $out -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $gen, $classes, $dexDir | Out-Null

$aapt = Join-Path $bt "aapt.exe"
& $aapt package -f -M (Join-Path $root "AndroidManifest.xml") `
  -S (Join-Path $root "res") -I $androidJar -J $gen -F (Join-Path $out "base.apk")
if ($LASTEXITCODE -ne 0) { throw "aapt failed" }

$srcDir = Join-Path $root "src\com\local\pictorialhomesync"
$srcs = Get-ChildItem $srcDir -Filter "*.java" | ForEach-Object { $_.FullName }
$rJava = Get-ChildItem -Recurse $gen -Filter "R.java" | Select-Object -First 1 -ExpandProperty FullName
& javac --release 11 -cp $androidJar -d $classes @srcs $rJava
if ($LASTEXITCODE -ne 0) { throw "javac failed" }

Push-Location $classes
$classList = Get-ChildItem -Recurse -Filter "*.class" | ForEach-Object { $_.FullName }
$d8 = Join-Path $bt "d8.bat"
& $d8 --min-api 26 --output $dexDir $classList
if ($LASTEXITCODE -ne 0) { Pop-Location; throw "d8 failed" }
Pop-Location

Copy-Item (Join-Path $out "base.apk") (Join-Path $out "unsigned.apk") -Force
Push-Location $dexDir
& $aapt add (Join-Path $out "unsigned.apk") classes.dex
if ($LASTEXITCODE -ne 0) { Pop-Location; throw "aapt add dex failed" }
Pop-Location

$ks = Join-Path $root "debug.keystore"
if (-not (Test-Path $ks)) {
  & keytool -genkeypair -keystore $ks -storepass android -keypass android `
    -alias androiddebugkey -keyalg RSA -keysize 2048 -validity 10000 `
    -dname "CN=PictorialHomeSync,O=Local,C=CN"
}

$apksigner = Join-Path $bt "apksigner.bat"
& $apksigner sign --ks $ks --ks-pass pass:android --key-pass pass:android `
  --out (Join-Path $root "pictorial-home-sync.apk") (Join-Path $out "unsigned.apk")
if ($LASTEXITCODE -ne 0) { throw "apksigner failed" }

Copy-Item (Join-Path $root "pictorial-home-sync.apk") (Join-Path $root "..\common\pictorial-home-sync.apk") -Force
Write-Host "OK: helper-app/pictorial-home-sync.apk"
