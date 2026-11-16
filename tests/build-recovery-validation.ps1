param(
    [Parameter(Mandatory=$true)][string]$AndroidSdk,
    [Parameter(Mandatory=$true)][string]$KeyStore,
    [string]$KeyAlias='androiddebugkey'
)
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$temporary=Join-Path $env:TEMP ('XGuard-RecoveryValidation-'+[guid]::NewGuid().ToString('N'))
$variant=Join-Path $temporary 'no-root'
New-Item -ItemType Directory -Path $variant | Out-Null
Copy-Item -LiteralPath (Join-Path $repo 'no-root/app') -Destination $variant -Recurse
Copy-Item -LiteralPath (Join-Path $repo 'shared') -Destination $temporary -Recurse
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'RecoveryInstrumentation.java') -Destination (Join-Path $variant 'app/src/com/xuan/xguard')
$manifest=Join-Path $variant 'app/AndroidManifest.xml'
$xml=[IO.File]::ReadAllText($manifest).Replace('package="com.xuan.xguard"','package="com.xuan.xguard.validation087"').Replace('android:name=".','android:name="com.xuan.xguard.')
$xml=$xml.Replace('</manifest>','<instrumentation android:name="com.xuan.xguard.RecoveryInstrumentation" android:targetPackage="com.xuan.xguard.validation087" /></manifest>')
[IO.File]::WriteAllText($manifest,$xml,[Text.UTF8Encoding]::new($false))
$builder=[IO.File]::ReadAllText((Join-Path $repo 'no-root/build-app.ps1')).Replace("name='com.xuan.xguard'","name='com.xuan.xguard.validation087'")
$script=Join-Path $variant 'build-app.ps1'
[IO.File]::WriteAllText($script,$builder,[Text.UTF8Encoding]::new($false))
& $script -AndroidSdk (Resolve-Path -LiteralPath $AndroidSdk).Path -KeyStore (Resolve-Path -LiteralPath $KeyStore).Path -KeyAlias $KeyAlias
if($LASTEXITCODE -ne 0){throw '验证 APK 构建失败'}
$output=Join-Path $repo 'dist/XGuard-v0.8.7-validation.apk'
New-Item -ItemType Directory -Path (Split-Path $output -Parent) -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $variant 'XGuard-v0.8.7-no-root.apk') -Destination $output -Force
Write-Output "仅供验证，不上传 Release：$output"
