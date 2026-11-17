param(
    [Parameter(Mandatory=$true)][string]$AndroidSdk,
    [string]$Platform='android-35',
    [string]$BuildTools='35.0.0',
    [Parameter(Mandatory=$true)][string]$KeyStore,
    [string]$KeyAlias='androiddebugkey'
)
$ErrorActionPreference='Stop'
$sourceRoot=$PSScriptRoot
$buildRoot=Join-Path $env:TEMP ('XGuard-build-' + [guid]::NewGuid().ToString('N'))
$platformJar=Join-Path $AndroidSdk "platforms/$Platform/android.jar"
if(-not (Test-Path $platformJar)){
    $platformJar=Join-Path $AndroidSdk "$Platform/android.jar"
}
$tools=Join-Path $AndroidSdk "build-tools/$BuildTools"
if(-not (Test-Path (Join-Path $tools 'aapt2.exe'))){
    $tools=Join-Path $AndroidSdk 'android-15'
}
if(-not (Test-Path $platformJar)){throw "找不到 $platformJar"}
if(-not $env:XGUARD_STORE_PASS){throw '请先设置 XGUARD_STORE_PASS 环境变量'}
if(-not $env:XGUARD_KEY_PASS){throw '请先设置 XGUARD_KEY_PASS 环境变量'}
New-Item -ItemType Directory -Force "$buildRoot/classes","$buildRoot/dex","$buildRoot/assets","$buildRoot/gen" | Out-Null
Copy-Item "$sourceRoot/module/webroot/*" "$buildRoot/assets" -Recurse -Force
Copy-Item "$sourceRoot/app/res" "$buildRoot/res" -Recurse -Force
Copy-Item "$sourceRoot/app/AndroidManifest.xml" "$buildRoot/AndroidManifest.xml" -Force
Copy-Item $platformJar "$buildRoot/android.jar" -Force
$platformJar=Join-Path $buildRoot 'android.jar'
$sources=@(Get-ChildItem "$sourceRoot/app/src" -Recurse -Filter '*.java' -File | ForEach-Object FullName)
$sources+=Get-ChildItem "$sourceRoot/shared/src" -Recurse -Filter '*.java' -File | ForEach-Object FullName
& javac -source 8 -target 8 -encoding UTF-8 -classpath $platformJar -d "$buildRoot/classes" $sources
if($LASTEXITCODE -ne 0){throw 'javac 失败'}
$classes=Get-ChildItem "$buildRoot/classes" -Recurse -Filter '*.class' -File | ForEach-Object FullName
& "$tools/d8.bat" --min-api 30 --lib $platformJar --output "$buildRoot/dex" $classes
if($LASTEXITCODE -ne 0){throw 'D8 失败'}
& "$tools/aapt2.exe" compile --dir "$buildRoot/res" -o "$buildRoot/resources.zip"
if($LASTEXITCODE -ne 0){throw '资源编译失败'}
& "$tools/aapt2.exe" link -I $platformJar --manifest "$buildRoot/AndroidManifest.xml" --java "$buildRoot/gen" -A "$buildRoot/assets" --min-sdk-version 30 --target-sdk-version 35 -o "$buildRoot/unsigned.apk" "$buildRoot/resources.zip"
if($LASTEXITCODE -ne 0){throw '资源链接失败'}
& jar uf "$buildRoot/unsigned.apk" -C "$buildRoot/dex" classes.dex
if($LASTEXITCODE -ne 0){throw '添加 DEX 失败'}
& "$tools/zipalign.exe" -f 4 "$buildRoot/unsigned.apk" "$buildRoot/aligned.apk"
if($LASTEXITCODE -ne 0){throw 'zipalign 失败'}
& "$tools/apksigner.bat" sign --ks $KeyStore --ks-key-alias $KeyAlias --ks-pass env:XGUARD_STORE_PASS --key-pass env:XGUARD_KEY_PASS --out "$buildRoot/xguard.apk" "$buildRoot/aligned.apk"
if($LASTEXITCODE -ne 0){throw '签名失败'}
& "$tools/apksigner.bat" verify --verbose "$buildRoot/xguard.apk"
if($LASTEXITCODE -ne 0){throw '签名校验失败'}
Copy-Item "$buildRoot/xguard.apk" "$sourceRoot/module/app/xguard.apk" -Force
# Keep the old development output path current as well; module/app is authoritative.
Copy-Item "$buildRoot/xguard.apk" "$sourceRoot/app/xguard.apk" -Force
$badging=& "$tools/aapt.exe" dump badging "$buildRoot/xguard.apk"
if($LASTEXITCODE -ne 0 -or $badging -notcontains "application-label:'XGuard'"){throw '内置 APK 名称校验失败'}
if(($badging -join "`n") -notmatch "package: name='com.xuan.xguard'"){throw '内置 APK 包名校验失败'}
if(($badging -join "`n") -notmatch "versionCode='9002' versionName='0.9.2'"){throw '内置 APK 版本校验失败'}
if((Get-FileHash "$sourceRoot/module/app/xguard.apk").Hash -ne (Get-FileHash "$buildRoot/xguard.apk").Hash){throw '模块内 APK 与新编译结果不一致'}
if((Get-FileHash "$sourceRoot/app/xguard.apk").Hash -ne (Get-FileHash "$buildRoot/xguard.apk").Hash){throw '开发目录 APK 与新编译结果不一致'}
Write-Output "构建完成（模块内 APK）：$sourceRoot/module/app/xguard.apk"
