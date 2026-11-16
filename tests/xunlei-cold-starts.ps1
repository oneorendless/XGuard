param([string]$Adb='adb', [string]$OutputDir='dist/device-check/cold-starts')
$ErrorActionPreference='Stop'
New-Item -ItemType Directory -Force $OutputDir | Out-Null
foreach($round in 1..5) {
    & $Adb shell am force-stop com.xunlei.downloadprovider
    $launch = & $Adb shell am start -W -n com.xunlei.downloadprovider/.launch.LaunchActivity
    $launch | Set-Content -LiteralPath (Join-Path $OutputDir "start-$round.txt")
    if($LASTEXITCODE -ne 0 -or ($launch -join "`n") -notmatch 'Status: ok'){throw "Cold launch $round failed"}
    foreach($stage in @('early','late')) {
        if($stage -eq 'late'){Start-Sleep -Milliseconds 1800}
        & $Adb shell screencap -p /sdcard/xguard-cold-check.png
        & $Adb pull /sdcard/xguard-cold-check.png (Join-Path $OutputDir "cold-$round-$stage.png")
    }
}
Write-Output 'Captured five successful cold launches; inspect screenshots for ads.'
