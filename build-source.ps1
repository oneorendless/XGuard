param([string]$OutputFile=(Join-Path $PSScriptRoot 'dist/XGuard-v0.9.3-source.zip'))
$ErrorActionPreference='Stop'
$files=@(& git -C $PSScriptRoot -c core.quotepath=false ls-files --cached --others --exclude-standard)
if($LASTEXITCODE -ne 0){throw '需要在源码工作区运行此脚本'}
$files=@($files | Sort-Object -Unique | Where-Object {
    $_ -notmatch '(^|/)(dist|\.git|device-check|build|\.gradle)/|(^|/)\.env($|\.)|\.(apk|zip|jks|keystore|pem|p12|pfx|key|class|dex|idsig)$|^module/bin/'
})
$required=@('LICENSE','ACKNOWLEDGEMENTS.md','build-app.ps1','no-root/build-app.ps1','monitor/main_linux.go','shared/src/com/xuan/xguard/GkdStore.java','module/core/accessibility_guard.sh')
foreach($file in $required){if($files -notcontains $file){throw "源码包缺少 $file"}}
$parent=Split-Path ([IO.Path]::GetFullPath($OutputFile)) -Parent
New-Item -ItemType Directory -Force $parent | Out-Null
$stream=[IO.File]::Open($OutputFile,[IO.FileMode]::Create)
$archive=[IO.Compression.ZipArchive]::new($stream,[IO.Compression.ZipArchiveMode]::Create)
try {
    foreach($file in $files){
        $full=Join-Path $PSScriptRoot $file
        if(-not (Test-Path -LiteralPath $full -PathType Leaf)){continue}
        [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive,$full,('XGuard/'+$file),[IO.Compression.CompressionLevel]::Optimal) | Out-Null
    }
} finally {$archive.Dispose();$stream.Dispose()}
Write-Output 'SOURCE PASS: working-tree source, GPL and build scripts; no credentials, device data or compiled binaries'
Get-FileHash -LiteralPath $OutputFile -Algorithm SHA256 | Format-List
