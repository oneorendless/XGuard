# XGuard 0.9.4 无 Root 版

这个目录是在 XGuard 模块版 v0.8.3 基础上制作的无 Root 版本。WebView 页面、液态玻璃样式、导航和交互沿用模块版；网络层改为 Android `VpnService`，只接管发往本地 DNS 的 UDP 查询。项目基于原作者 **惜故里丶** 的原始作品进行二次创作，感谢原作者与各规则维护者，具体见仓库根目录的 `ACKNOWLEDGEMENTS.md`。

## 能力范围

- 不需要 Magisk、KernelSU、SukiSU、APatch 或 Root 授权。
- 首次点击“授权并连接”时请求系统 VPN 授权，之后由前台服务保持运行。
- 内置基线规则从原版 `module/features/shield/rules/baseline.list` 复制到 `app/assets/blocklist.txt`，并带有原版预制订阅目录：AWAvenue、anti-AD、GOODBYEADS、AdAway、AdRules、Hagezi、1Hosts、AdGuard、StevenBlack 等，可在“规则”页勾选后点击“更新规则”下载并合并。
- 底栏有概览、域名、开屏、设置四项。域名下可查看记录和订阅，开屏默认打开 GKD。缓存锁定页面说明所需的 Root 权限。
- 首次安装只保证内置基线离线可用（约 7.6 万条）；预制源按需下载到应用私有缓存，切换源不会修改 hosts 或其他应用文件。
- 规则来源页面可以保存自定义地址；当前自动下载针对原版预制源，自定义地址会保存并显示在列表中。
- 查询按 `223.5.5.5`、`1.1.1.1`、`8.8.8.8` 顺序转发，socket 使用 `VpnService.protect()` 避免 VPN 回环；广告域名返回 NXDOMAIN。
- 只处理 IPv4 UDP DNS。DoH/DoT、QUIC、应用自带 DNS、IPv6 DNS 和已建立连接不会被此版本拦截。
- 更新间隔目前只保存设置，尚无后台定时下载任务；当前以手动更新预制源为准。
- 占用 Android VPN 槽位，通常不能与其他 VPN 同时运行。开屏缓存锁定、hosts 挂载、HTTPDNS IP 拦截等依赖 Root 的功能不可用，保留界面选项不代表已实现对应能力。

## 保活与系统设置

首次打开会显示“保持后台防护”提示：

1. “电量不受限”打开系统电池优化白名单页面。
2. “自启动设置”按小米、华为、OPPO、vivo 顺序尝试厂商页面，找不到时打开应用详情页。
3. VPN 服务使用常驻低优先级通知、`START_STICKY`、`onTaskRemoved` 重启和 `BOOT_COMPLETED` 接收器。系统是否允许厂商自启动仍由用户在系统设置中决定，Android 不允许应用静默修改此开关。

## 构建

在有 Android SDK、JDK 17 和签名密钥的 Windows 环境中，从本目录执行：

```powershell
$env:XGUARD_STORE_PASS='密钥库密码'
$env:XGUARD_KEY_PASS='签名密码'
./build-app.ps1 -AndroidSdk 'C:\Android\Sdk' -KeyStore 'C:\keys\xguard.jks'
```

输出为 `XGuard-v0.9.4-no-root.apk`。无 Root 版使用包名 `com.xuan.xguard`、版本名 `0.9.4-noroot`，最低支持 Android 6.0；两个正式 APK 不能同时安装，切换前先备份所需设置。

v0.9.2 增加 GKD 页面中的隐藏最近任务开关和可选 GKD 风格无障碍 UI 规则，可按来源分别勾选，真实下载和缓存网上 HTTPS 订阅；仅执行安全兼容子集，不支持的复杂选择器整条跳过。首次打开弹窗会显示 VPN 与无障碍状态；规则来源开关由用户控制。详见 [致谢](../ACKNOWLEDGEMENTS.md) 和 `assets/GPL-3.0.txt`。

预构建 APK 与 `SHA256SUMS.txt` 可从仓库的 GitHub Releases 下载；源码目录不重复存放该 APK。自行构建请使用自己的签名密钥。
