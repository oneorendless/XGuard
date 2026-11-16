param(
    [Parameter(Mandatory=$true)][string]$AndroidSdk,
    [string]$Platform='android-35',
    [string]$BuildTools='35.0.0',
    [Parameter(Mandatory=$true)][string]$KeyStore,
    [string]$KeyAlias='androiddebugkey'
)
$ErrorActionPreference='Stop'
$sourceRoot=$PSScriptRoot
$buildRoot=Join-Path $env:TEMP ('XGuard-NoRoot-build-' + [guid]::NewGuid().ToString('N'))
$platformJar=Join-Path $AndroidSdk "platforms/$Platform/android.jar"
if(-not (Test-Path $platformJar)){$platformJar=Join-Path $AndroidSdk "$Platform/android.jar"}
$tools=Join-Path $AndroidSdk "build-tools/$BuildTools"
if(-not (Test-Path (Join-Path $tools 'aapt2.exe'))){$tools=Join-Path $AndroidSdk 'android-15'}
if(-not (Test-Path $platformJar)){throw "找不到 $platformJar"}
if(-not $env:XGUARD_STORE_PASS){throw '请先设置 XGUARD_STORE_PASS 环境变量'}
if(-not $env:XGUARD_KEY_PASS){throw '请先设置 XGUARD_KEY_PASS 环境变量'}
New-Item -ItemType Directory -Force "$buildRoot/classes","$buildRoot/dex","$buildRoot/assets","$buildRoot/res","$buildRoot/gen" | Out-Null
Copy-Item "$sourceRoot/app/assets/*" "$buildRoot/assets" -Recurse -Force
foreach($resourceDir in @('drawable','mipmap-anydpi-v26','mipmap-anydpi-v33','values','values-night')){
    Copy-Item "$sourceRoot/app/res/$resourceDir" "$buildRoot/res" -Recurse -Force
}
Copy-Item "$sourceRoot/app/AndroidManifest.xml" "$buildRoot/AndroidManifest.xml" -Force
Copy-Item $platformJar "$buildRoot/android.jar" -Force
$sources=Get-ChildItem "$sourceRoot/app/src" -Recurse -Filter '*.java' -File | ForEach-Object FullName
& javac -source 8 -target 8 -encoding UTF-8 -classpath "$buildRoot/android.jar" -d "$buildRoot/classes" $sources
if($LASTEXITCODE -ne 0){throw 'javac 失败'}
$classes=Get-ChildItem "$buildRoot/classes" -Recurse -Filter '*.class' -File | ForEach-Object FullName
& "$tools/d8.bat" --min-api 23 --lib "$buildRoot/android.jar" --output "$buildRoot/dex" $classes
if($LASTEXITCODE -ne 0){throw 'D8 失败'}
& "$tools/aapt2.exe" compile --dir "$buildRoot/res" -o "$buildRoot/resources.zip"
if($LASTEXITCODE -ne 0){throw '资源编译失败'}
& "$tools/aapt2.exe" link -I "$buildRoot/android.jar" --manifest "$buildRoot/AndroidManifest.xml" --java "$buildRoot/gen" -A "$buildRoot/assets" --min-sdk-version 23 --target-sdk-version 35 -o "$buildRoot/unsigned.apk" "$buildRoot/resources.zip"
if($LASTEXITCODE -ne 0){throw '资源链接失败'}
& jar uf "$buildRoot/unsigned.apk" -C "$buildRoot/dex" classes.dex
if($LASTEXITCODE -ne 0){throw '添加 DEX 失败'}
& "$tools/zipalign.exe" -f 4 "$buildRoot/unsigned.apk" "$buildRoot/aligned.apk"
if($LASTEXITCODE -ne 0){throw 'zipalign 失败'}
& "$tools/apksigner.bat" sign --v1-signing-enabled true --v2-signing-enabled true --v3-signing-enabled true --ks $KeyStore --ks-key-alias $KeyAlias --ks-pass env:XGUARD_STORE_PASS --key-pass env:XGUARD_KEY_PASS --out "$buildRoot/xguard-no-root.apk" "$buildRoot/aligned.apk"
if($LASTEXITCODE -ne 0){throw '签名失败'}
& "$tools/apksigner.bat" verify --verbose "$buildRoot/xguard-no-root.apk"
if($LASTEXITCODE -ne 0){throw '签名校验失败'}
Copy-Item "$buildRoot/xguard-no-root.apk" "$sourceRoot/XGuard-v0.8.3-no-root.apk" -Force
Write-Output "构建完成：$sourceRoot/XGuard-v0.8.3-no-root.apk"
