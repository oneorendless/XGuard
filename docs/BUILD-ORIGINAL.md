# XGuard 0.8.3

作者 Xuan，基于惜故里丶的原始作品二次创作。第三方规则与 PrismalAGSL 许可见 `module/THIRD_PARTY_NOTICES.md`。

## 工程

- `module/`：可刷入模块的根目录，ID `xguard`。
- `module/features/shield/`：防护引擎，命令 `xguard run shield ...`。
- `module/core/`：调度、配置、安装与域名观察。
- `module/core/legacy.sh`：集中处理旧版本标识、路径、代理键及旧客户端退出。旧标识只作为读取旧数据与识别冲突的兼容边界；不篡改原作者归属，不改写订阅的实际域名/IP。
- `app/`：Java / WebView App，包名 `com.xuan.xguard`，独立 Root 授权桥接和触觉反馈。
- `module/webroot/`：App 与管理器共用界面。主题集中在 `theme.css`，双主题背景 SVG 为原创；卡片使用三级悬浮投影、顶部高光和低强度实时毛玻璃，导航底板与选中透镜为独立同级玻璃表面，浮动控件和弹窗也使用缓存的边缘折射。
- `monitor/`：被动 DNS / TLS SNI 采集器，四种 ABI；无第三方 Go 依赖。
- `docs/liquid-glass.md`：渲染、性能与验证边界。

版本名 `0.8.3`，versionCode `8003`。APK 的权威输出位置为 `module/app/xguard.apk`，`app/xguard.apk` 为相同构建的开发副本。

## 构建

需要 JDK 17、Android Platform 35 和 Build Tools 35.0.0。准备自己的密钥；交付源码不含密钥。

```powershell
$env:XGUARD_STORE_PASS='密钥库密码'
$env:XGUARD_KEY_PASS='密钥密码'
./build-app.ps1 -AndroidSdk C:/Android/Sdk -KeyStore C:/keys/xguard.jks -KeyAlias xguard
./build-release.ps1 -Tools C:/Android/Sdk/build-tools/35.0.0
```

脚本在临时 ASCII 路径构建，兼容中文工程路径；验证 App 名称、包名、版本、签名、WebUI 资源一致性及 ZIP 内实际 APK 的校验值。交付 APK 继续采用现有测试密钥签名；由于包名变更，Android 会将其视为新应用，首次打开需要单独授权 Root。

采集器需要 Go 1.23+，`CGO_ENABLED=0`、`GOOS=linux`，按 arm64 / arm（GOARM=7）/ amd64 / 386 构建到相应 `module/bin/*/xguard-monitor`。先运行 `go test -v ./...`、`go vet ./...`。

## 安装与验证

安装说明、迁移策略和网络采集范围见模块 README。预览图使用测试接口数据。Windows Edge / Playwright 的切页延迟与图形检查结果不能替代 Android 真机验证；本机没有连接 Android 设备。
