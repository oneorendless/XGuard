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
./build-release.ps1 -Tools 'C:/Android/Sdk/build-tools/35.0.0' -OutputFile './XGuard-v0.8.3.zip'
```

脚本检查 APK 名称、包名、版本、签名、WebUI 资源和 ZIP 内嵌 APK 一致性。输出的 ZIP 根目录包含 `module.prop`，可交给 Root 管理器安装。

## 免 Root 版 APK

```powershell
./no-root/build-app.ps1 -AndroidSdk 'C:/Android/Sdk' -KeyStore 'C:/keys/xguard.jks' -KeyAlias xguard
```

输出 `no-root/XGuard-v0.8.3-no-root.apk`，最低 Android 6.0。脚本启用 v1 / v2 / v3 签名并执行校验。

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

对应输出名为 `module/bin/<ABI>/xguard-monitor`。仓库保留交付版本的四种 ABI 预编译文件，方便检查和重新打包。

## 校验与验证记录

Releases 附 `SHA256SUMS.txt`，可在下载目录中用 `Get-FileHash -Algorithm SHA256` 与文件内值比对。

历史验证记录见 [VALIDATION-ORIGINAL.txt](VALIDATION-ORIGINAL.txt) 和 [模块版本说明](MODULE-RELEASE-NOTES.md)。这些记录描述对应构建时的检查范围；桌面浏览器预览和静态校验不能替代不同 Android / Root 环境下的实际运行验证。
