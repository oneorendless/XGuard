# XGuard v0.8.3

提供 Root 模块版与免 Root 本地 VPN 版，使用统一的浅色 / 深色玻璃风格界面。

## 下载选择

- **`XGuard-v0.8.3.zip`**：Root 模块安装包。Android 11 及以上，在 Magisk / KernelSU / SukiSU / APatch 管理器中安装并重启。
- **`XGuard-v0.8.3.apk`**：模块配套管理应用，需与模块一起使用。
- **`XGuard-v0.8.3-no-root.apk`**：Android 6.0 及以上免 Root 版，安装后授予系统 VPN 权限即可使用。
- **`XGuard-v0.8.3-source.zip`**：模块和免 Root 版完整源码快照，不能作为模块刷入。
- **`SHA256SUMS.txt`**：以上附件的 SHA-256 校验值。

GitHub 自动生成的 Source code 下载项也是源码，刷入模块时请选择上面的 `XGuard-v0.8.3.zip`。

## 模块版

支持 hosts 域名防护、预制订阅、自定义放行 / 封禁、DNS / TLS SNI 域名观察、开屏缓存规则管理、防护诊断与安全模式。

## 免 Root 版

通过 Android VpnService 处理本地 IPv4 UDP DNS，内置约 76,759 条离线基线，预制订阅可勾选并手动更新，包括 AWAvenue、anti-AD、GOODBYEADS、AdAway、AdRules、Hagezi、1Hosts、AdGuard 和 StevenBlack 等。

提供前台服务、常驻通知、开机接收器和电量 / 自启动设置引导。系统限制仍需用户自行调整；免 Root 版不支持需要 Root 的开屏缓存锁定。自定义来源当前仅保存地址，更新间隔当前仅保存设置，尚无后台定时下载任务。

## 使用须知

两个 APK 同包名，不能共存；签名不同时不能直接覆盖更新。免 Root 版占用 Android VPN 槽位，不能覆盖 DoH/DoT、QUIC、IPv6 DNS、应用自带 DNS 等情况。域名规则也无法保证移除所有广告。

此版本附件基于现有 v0.8.3 交付文件整理，源码快照补入当前免 Root 实现及仓库说明；本次上传未重新编译应用。

## 致谢

感谢原作者 **惜故里丶** 的原始作品。本项目由 **Xuan** 在其基础上进行二次创作，保留原作者和第三方署名。

感谢 AWAvenue、anti-AD、GOODBYEADS、AdAway、AdRules、Hagezi、1Hosts、AdGuard、StevenBlack 等规则维护者，感谢开屏规则参考项目，以及 **Saurav Sajeev / PrismalAGSL** 的视觉算法。具体来源与许可证见仓库的 ACKNOWLEDGEMENTS.md 和 THIRD_PARTY_NOTICES.md。
