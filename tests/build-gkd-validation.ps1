param([Parameter(Mandatory=$true)][string]$AndroidSdk,[Parameter(Mandatory=$true)][string]$KeyStore)
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$temporary=Join-Path $env:TEMP ('XGuard-GkdValidation-'+[guid]::NewGuid().ToString('N'))
$variant=Join-Path $temporary 'no-root'
New-Item -ItemType Directory -Path $variant | Out-Null
Copy-Item -LiteralPath (Join-Path $repo 'no-root/app') -Destination $variant -Recurse
Copy-Item -LiteralPath (Join-Path $repo 'shared') -Destination $temporary -Recurse
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'GkdInstrumentation.java') -Destination (Join-Path $variant 'app/src/com/xuan/xguard')
$manifest=Join-Path $variant 'app/AndroidManifest.xml'
$xml=[IO.File]::ReadAllText($manifest).Replace('package="com.xuan.xguard"','package="com.xuan.xguard.validation091"').Replace('android:name=".','android:name="com.xuan.xguard.')
$xml=$xml.Replace('</manifest>','<instrumentation android:name="com.xuan.xguard.GkdInstrumentation" android:targetPackage="com.xuan.xguard.validation091" /></manifest>')
[IO.File]::WriteAllText($manifest,$xml,[Text.UTF8Encoding]::new($false))
$builder=[IO.File]::ReadAllText((Join-Path $repo 'no-root/build-app.ps1')).Replace("name='com.xuan.xguard'","name='com.xuan.xguard.validation091'")
$script=Join-Path $variant 'build-app.ps1'
[IO.File]::WriteAllText($script,$builder,[Text.UTF8Encoding]::new($false))
& $script -AndroidSdk (Resolve-Path -LiteralPath $AndroidSdk).Path -KeyStore (Resolve-Path -LiteralPath $KeyStore).Path
New-Item -ItemType Directory -Force (Join-Path $repo 'dist') | Out-Null
Copy-Item -LiteralPath (Join-Path $variant 'XGuard-v0.9.4-no-root.apk') -Destination (Join-Path $repo 'dist/XGuard-v0.9.4-gkd-validation.apk') -Force
