param([string]$OutputFile=(Join-Path $PSScriptRoot '../XGuard-v0.8.5.zip'),[Parameter(Mandatory=$true)][string]$Tools)
$ErrorActionPreference='Stop'
$module=Join-Path $PSScriptRoot 'module'
$apk=Join-Path $module 'app/xguard.apk'
$mirror=Join-Path $PSScriptRoot 'app/xguard.apk'
if((Test-Path $mirror) -and (Get-FileHash $mirror).Hash -ne (Get-FileHash $apk).Hash){throw '开发目录携带了旧 APK，请先重建 App'}
$temporary=Join-Path $env:TEMP ('XGuard-verify-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temporary | Out-Null
Copy-Item -LiteralPath $apk -Destination (Join-Path $temporary 'XGuard.apk')
$badging=& (Join-Path $Tools 'aapt.exe') dump badging (Join-Path $temporary 'XGuard.apk')
if($LASTEXITCODE -ne 0 -or $badging -notcontains "application-label:'XGuard'"){throw '模块内携带的 APK 不是 XGuard'}
if(($badging -join "`n") -notmatch "package: name='com.xuan.xguard'"){throw '模块内携带的 APK 包名错误'}
if((Get-Content (Join-Path $module 'module.prop')) -notcontains 'id=xguard'){throw '模块 ID 错误'}
if(($badging -join "`n") -notmatch "versionCode='8005' versionName='0.8.5'"){throw '模块内携带的 APK 版本错误'}
& (Join-Path $Tools 'apksigner.bat') verify (Join-Path $temporary 'XGuard.apk')
if($LASTEXITCODE -ne 0){throw 'APK 签名校验失败'}
$apkZip=[IO.Compression.ZipFile]::OpenRead($apk)
try {
 foreach($file in Get-ChildItem (Join-Path $module 'webroot') -Recurse -File){
  $relative=[IO.Path]::GetRelativePath((Join-Path $module 'webroot'),$file.FullName).Replace('\','/')
  $entry=$apkZip.GetEntry('assets/'+$relative)
  if(-not $entry){throw ('APK 缺少页面资源：'+$relative)}
  $stream=$entry.Open();$memory=[IO.MemoryStream]::new();try{$stream.CopyTo($memory);$bytes=$memory.ToArray()}finally{$stream.Dispose();$memory.Dispose()}
  $actual=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
  if($actual -ne (Get-FileHash -LiteralPath $file.FullName).Hash){throw ('APK 页面资源与模块不一致：'+$relative)}
 }
} finally {$apkZip.Dispose()}
& jar --create --no-manifest --file $OutputFile -C $module .
if($LASTEXITCODE -ne 0){throw 'ZIP 打包失败'}
$zip=[IO.Compression.ZipFile]::OpenRead($OutputFile)
try{
 if(-not $zip.GetEntry('module.prop')){throw 'ZIP 缺少根 module.prop'}
 foreach($entry in $zip.Entries){if($entry.FullName.StartsWith('./') -or $entry.FullName.Contains('\')){throw ('ZIP 路径不兼容：'+$entry.FullName)}}
 $entry=$zip.GetEntry('app/xguard.apk');$stream=$entry.Open();$destination=[IO.File]::Create((Join-Path $temporary 'bundled.apk'));try{$stream.CopyTo($destination)}finally{$stream.Dispose();$destination.Dispose()}
 if((Get-FileHash (Join-Path $temporary 'bundled.apk')).Hash -ne (Get-FileHash $apk).Hash){throw 'ZIP 中的内置 APK 与新构建不一致'}
}finally{$zip.Dispose()}
Write-Output ($badging | Select-Object -First 8)
Write-Output 'RELEASE PASS: module APK label/version/signature, matching WebUI assets, ZIP paths and embedded APK checksum'
Get-FileHash -LiteralPath $OutputFile -Algorithm SHA256 | Format-List
