# 构建与打包

## 环境

- Windows PowerShell 7、JDK 17。
- Android SDK Platform 35、Build Tools 35.0.0。
- 自备 APK 签名密钥。密钥与密码不要提交到仓库。
- 如需重新编译域名采集器，使用 Go 1.23 或以上版本。

以下命令从仓库根目录执行。构建脚本会在临时目录生成中间文件，再复制最终 APK。

## 模块版 APK

```powershell
$env:XGUARD_STORE_PASS = '你的密钥库密码'
$env:XGUARD_KEY_PASS = '你的签名密码'
./build-app.ps1 -AndroidSdk 'C:/Android/Sdk' -KeyStore 'C:/keys/xguard.jks' -KeyAlias xguard
```

输出 `module/app/xguard.apk` 和开发副本 `app/xguard.apk`。模块内的 APK 为权威输出。

## 模块 ZIP

```powershell
./build-release.ps1 -Tools 'C:/Android/Sdk/build-tools/35.0.0' -OutputFile './dist/XGuard-v0.9.2-module.zip'
```

脚本检查 APK 名称、包名、版本、签名、WebUI 资源和 ZIP 内嵌 APK 一致性。输出的 ZIP 根目录包含 `module.prop`，可交给 Root 管理器安装。

## 免 Root 版 APK

```powershell
./no-root/build-app.ps1 -AndroidSdk 'C:/Android/Sdk' -KeyStore 'C:/keys/xguard.jks' -KeyAlias xguard
```

输出 `no-root/XGuard-v0.9.2-no-root.apk`，最低 Android 6.0。脚本启用 v1 / v2 / v3 签名并执行校验。

模块 APK 与免 Root APK 都使用包名 `com.xuan.xguard`。自己重新签名的 APK 不一定能覆盖 Releases 中已有签名的应用；版本切换前保留所需数据。

## Go 域名采集器

进入 `monitor/` 后先执行：

```powershell
go test -v ./...
go vet ./...
```

采集器使用 Linux 网络接口，按以下对应关系交叉编译到模块目录：

| 模块 ABI 目录 | GOARCH | 其他环境 |
| --- | --- | --- |
| `arm64-v8a` | `arm64` | `GOOS=linux`、`CGO_ENABLED=0` |
| `armeabi-v7a` | `arm` | `GOOS=linux`、`GOARM=7`、`CGO_ENABLED=0` |
| `x86_64` | `amd64` | `GOOS=linux`、`CGO_ENABLED=0` |
| `x86` | `386` | `GOOS=linux`、`CGO_ENABLED=0` |

对应输出名为 `module/bin/<ABI>/xguard-monitor`。源码 ZIP 不含预编译二进制；从源码包构建时先按上表交叉编译，再构建模块 APK，最后打包模块 ZIP。例如在 `monitor/` 中执行：

```powershell
$env:GOOS='linux'
$env:CGO_ENABLED='0'
$targets=@{ 'arm64-v8a'='arm64'; 'armeabi-v7a'='arm'; 'x86_64'='amd64'; 'x86'='386' }
foreach($abi in $targets.Keys){
    $env:GOARCH=$targets[$abi]
    $env:GOARM='7'
    New-Item -ItemType Directory -Force "../module/bin/$abi" | Out-Null
    go build -trimpath -ldflags='-s -w' -o "../module/bin/$abi/xguard-monitor" .
    if($LASTEXITCODE -ne 0){throw "采集器构建失败：$abi"}
}
```

## GPL 对应源码包

`./build-source.ps1` 打包当前工作区中的源码、资源、规则、GPL 条款、致谢与构建脚本，包含尚未提交的新文件。不包含设备记录、密钥或编译产物。输出 `dist/XGuard-v0.9.2-source.zip`。重新签名后的 APK 无法覆盖签名不同的已安装应用。

## 0.9.2 验证

`node tests/ui-v092.mjs` 检查 Root/VPN 两版的隐藏最近任务开关、首屏位置、开关与页面重载后的状态、桥接失败回滚、旧桥接兼容以及深浅色 320px 布局。

`./tests/build-recents-validation.ps1 -AndroidSdk 'C:/Android/Sdk' -KeyStore 'C:/keys/xguard.jks' -Variant root`（或 `-Variant vpn`）构建隔离测试 APK，输出在 `dist/device-check/`。在设备安装对应 APK 后，使用 `adb shell am instrument -w com.xuan.xguard.validation092root/com.xuan.xguard.RecentTasksInstrumentation`（VPN 包名后缀为 `validation092vpn`），检查原生桥接、任务排除标志和 Activity 重启后的设置恢复。

`node tests/ui-v091.mjs` 验证首次授权、GKD 独立底栏、独立订阅和下载/删除命令、守护开关、GPL 入口与窄屏布局；需要在 `XGUARD_TEST_TOOLS` 或相邻 `.xiezhi-tools` 目录安装 Playwright，并安装 Microsoft Edge。`sh tests/accessibility-guard.sh` 验证守护的授权、用户、解锁、安全模式、冷却与保留其他服务的行为。实机 JSON5/在线订阅测试可通过 `tests/build-gkd-validation.ps1` 构建独立 instrumentation APK，不覆盖正式应用。

## 校验与验证记录

Releases 附 `SHA256SUMS.txt`，可在下载目录中用 `Get-FileHash -Algorithm SHA256` 与文件内值比对。

历史验证记录见 [VALIDATION-ORIGINAL.txt](VALIDATION-ORIGINAL.txt) 和 [模块版本说明](MODULE-RELEASE-NOTES.md)。这些记录描述对应构建时的检查范围；桌面浏览器预览和静态校验不能替代不同 Android / Root 环境下的实际运行验证。
