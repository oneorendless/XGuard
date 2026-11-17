param([Parameter(Mandatory=$true)][string]$AndroidSdk,[Parameter(Mandatory=$true)][string]$KeyStore,[ValidateSet('root','vpn')][string]$Variant='root')
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$temporary=Join-Path $env:TEMP ('XGuard-RecentsValidation-'+[guid]::NewGuid().ToString('N'))
$package="com.xuan.xguard.validation092$Variant"
New-Item -ItemType Directory -Path $temporary | Out-Null
Copy-Item -LiteralPath (Join-Path $repo 'shared') -Destination $temporary -Recurse
if($Variant -eq 'root'){
    $variantRoot=$temporary
    $builderPath=Join-Path $repo 'build-app.ps1'
    Copy-Item -LiteralPath (Join-Path $repo 'app') -Destination $temporary -Recurse
    New-Item -ItemType Directory -Path (Join-Path $temporary 'module/app') -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $repo 'module/webroot') -Destination (Join-Path $temporary 'module') -Recurse
}else{
    $variantRoot=Join-Path $temporary 'no-root'
    $builderPath=Join-Path $repo 'no-root/build-app.ps1'
    New-Item -ItemType Directory -Path $variantRoot | Out-Null
    Copy-Item -LiteralPath (Join-Path $repo 'no-root/app') -Destination $variantRoot -Recurse
}
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'RecentTasksInstrumentation.java') -Destination (Join-Path $variantRoot 'app/src/com/xuan/xguard')
$manifest=Join-Path $variantRoot 'app/AndroidManifest.xml'
$xml=[IO.File]::ReadAllText($manifest).Replace('package="com.xuan.xguard"',('package="'+$package+'"')).Replace('android:name=".','android:name="com.xuan.xguard.')
$xml=$xml.Replace('</manifest>',('<instrumentation android:name="com.xuan.xguard.RecentTasksInstrumentation" android:targetPackage="'+$package+'" /></manifest>'))
[IO.File]::WriteAllText($manifest,$xml,[Text.UTF8Encoding]::new($false))
$builder=[IO.File]::ReadAllText($builderPath).Replace("name='com.xuan.xguard'",("name='"+$package+"'"))
$script=Join-Path $variantRoot 'build-app.ps1'
[IO.File]::WriteAllText($script,$builder,[Text.UTF8Encoding]::new($false))
& $script -AndroidSdk (Resolve-Path -LiteralPath $AndroidSdk).Path -KeyStore (Resolve-Path -LiteralPath $KeyStore).Path
$built=if($Variant -eq 'root'){Join-Path $variantRoot 'module/app/xguard.apk'}else{Join-Path $variantRoot 'XGuard-v0.9.2-no-root.apk'}
Copy-Item -LiteralPath $built -Destination (Join-Path $repo "dist/device-check/XGuard-v0.9.2-recents-$Variant-validation.apk") -Force
