# 第三方归属与许可

XGuard 二次创作与维护者：**Xuan**。本项目基于原作者 **惜故里丶** 的原始作品，保留原有署名和规则来源信息。

## GKD 参考实现

XGuard 0.9.2 的可选 UI 规则功能参考 [gkd-kit/gkd 1.13.2](https://github.com/gkd-kit/gkd/tree/v1.13.2) 的订阅规则结构与无障碍动作思路。GKD 采用 GNU General Public License v3.0；本项目只保留独立的轻量适配，不分发 GKD 的原生二进制或 Compose 源码。规则社区入口：[gkd-subscription](https://github.com/topics/gkd-subscription)。

## 原有许可文件

- [模块版第三方归属说明](module/THIRD_PARTY_NOTICES.md)
- [免 Root 版第三方说明](no-root/THIRD_PARTY_NOTICES.md)
- [PrismalAGSL MIT 完整许可](module/webroot/PRISMAL-LICENSE.txt)
- [免 Root APK 内分发的 MIT 许可](no-root/app/assets/PRISMAL-LICENSE.txt)

PrismalAGSL：Copyright (c) 2026 Saurav Sajeev。参考项目 https://github.com/styropyr0/PrismalAGSL ，参考提交 `b0ba5fef4a1560e6c75a6d3421807fa33526af09`。XGuard 将其中的距离场和折射算法改编为 WebView 实现。

## 域名与开屏规则

域名规则来自多个独立维护的项目，内置基线和预制来源不改变各自许可证。项目列表见 [致谢](ACKNOWLEDGEMENTS.md)，具体来源与注释见：

- [预制订阅目录](module/features/shield/sources.list)
- [内置基线](module/features/shield/rules/baseline.list)
- [开屏规则](module/features/shield/rules/splash.rules)

XGuard 0.9.2 的新增与修改部分按 GPL-3.0-only 提供，完整正文见 `LICENSE`，并随两版 APK 的 `assets/GPL-3.0.txt` 及模块 `LICENSE` 分发。PrismalAGSL 的 MIT 许可继续保留；第三方规则保留各自条款和归属，不因本项目声明而重新授权。
