# 致谢与项目来源

## 原作者

XGuard 由 **Xuan** 在原作者 **惜故里丶** 的原始作品基础上进行二次创作。感谢原作者在广告防护、规则整理和模块实现上的工作。原有来源注释、兼容逻辑和第三方署名继续保留。

## GKD UI 规则引擎参考

`0.9.2` 的 UI 自动规则采用轻量实现，参考 **gkd-kit/gkd 1.13.2** 的订阅模型、包名范围、文本匹配和动作语义。感谢 GKD 社区维护者及 [gkd-subscription](https://github.com/topics/gkd-subscription) 主题中的规则作者。XGuard 没有复制 GKD 的 Compose 应用或选择器实现；规则以 JSON 形式保存，仅在启用无障碍服务且勾选对应订阅时执行。每个来源独立启停，不使用隐藏的总开关。

本次改编包括：纯 Java JSON5 解析器、开屏规则兼容子集、HTTPS 下载及原子缓存、按包名与启动时间限定的事件扫描。复杂关系、全局规则、版本过滤、前置动作和未支持的条件均跳过整条；界面显示可执行及未导入数量。内置来源目录引用 AIsouler、Lin-arm、ganlinte 的订阅地址；社区规则按其上游条款下载，未随安装包捆绑这些完整订阅。

GKD 项目遵循 GNU General Public License v3.0。XGuard 的修改部分按 GPL-3.0-only 发布，完整条款见 [LICENSE](LICENSE)；GKD 本体、社区订阅和其中的第三方规则仍以各自仓库中的许可证、署名和使用条件为准。

## 规则维护者

感谢以下项目为广告域名过滤、隐私保护及相关规则提供持续维护。规则目录提供的是可选来源，各项目的许可证、使用要求及规则覆盖范围以其上游为准。

| 项目 | 主页 |
| --- | --- |
| AWAvenue Ads Rule | https://github.com/TG-Twilight/AWAvenue-Ads-Rule |
| anti-AD | https://github.com/privacy-protection-tools/anti-AD |
| GOODBYEADS | https://github.com/8680/GOODBYEADS |
| AdAway hosts | https://github.com/AdAway/adaway.github.io |
| AdRules | https://github.com/Cats-Team/AdRules |
| Hagezi DNS Blocklists | https://github.com/hagezi/dns-blocklists |
| 1Hosts | https://github.com/badmojr/1Hosts |
| AdGuard DNS Filter | https://github.com/AdguardTeam/AdGuardSDNSFilter |
| StevenBlack hosts | https://github.com/StevenBlack/hosts |
| Mobile hosts | https://github.com/r-a-y/mobile-hosts |

内置基线的组合来源和生成信息见 [baseline.list](module/features/shield/rules/baseline.list) 文件头；来源地址、默认开关及解析说明见 [sources.list](module/features/shield/sources.list)。基线中的原始域名与注释保留。

## 开屏规则与来源目录参考

开屏路径规则保留了对 [liuzq2002/Adguard-Home-For-Magisk-Mod](https://github.com/liuzq2002/Adguard-Home-For-Magisk-Mod) 的 `scripts/NoAdsService.sh` 的来源说明，文件头注明参考提交 `0a0717ba`；相关逻辑注释同时致谢 lingeringsound 的去广告模块。具体说明见 [splash.rules](module/features/shield/rules/splash.rules)。

预制来源目录的原有注释也保留了对 Re-Malwack profiles、bindhosts sources.txt 和 AdAway 默认来源的参考说明。

## 液态玻璃视觉算法

- 项目：[PrismalAGSL](https://github.com/styropyr0/PrismalAGSL)
- 作者：**Saurav Sajeev**
- 参考提交：`b0ba5fef4a1560e6c75a6d3421807fa33526af09`
- 许可证：MIT

圆角矩形距离场、梯度与边缘折射算法改编为 WebView 可用的缓存位移纹理，未直接集成 Compose / AGSL 运行时。完整 MIT 许可随模块 [PRISMAL-LICENSE.txt](module/webroot/PRISMAL-LICENSE.txt) 和免 Root 应用 [PRISMAL-LICENSE.txt](no-root/app/assets/PRISMAL-LICENSE.txt) 保留。

## 归属说明

本次公开仓库整理不改变原作者、第三方代码或规则的归属，也不为上游材料重新指定许可证。继续分发或修改第三方内容时，请查阅对应上游许可与文件内说明。
