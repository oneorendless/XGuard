# 开源与原作者归属

XGuard 作者：Xuan。基于原作者惜故里丶的原始作品二次创作；保留原规则来源、原作者信息和配置兼容。

## PrismalAGSL

- 项目：https://github.com/styropyr0/PrismalAGSL
- 参考版本：`b0ba5fef4a1560e6c75a6d3421807fa33526af09`
- Copyright (c) 2026 Saurav Sajeev
- MIT License，完整许可见 `webroot/PRISMAL-LICENSE.txt`；此文件也随 App 的 assets 分发，可在设置 → 开源致谢中查看。

`webroot/glass.js` 中的圆角矩形距离场、距离梯度和 arc-lift 边缘折射，改编自该项目 `rounded_rect_sdf.agsl`、`rect_refraction.agsl` 和 `rect_refraction_dispersion.agsl`。将其适配为缓存的位移纹理，供浏览器实时 backdrop-filter / SVG 滤镜使用，加入低强度色散与玻璃边缘高光。未直接集成 Compose / AGSL 运行时；未使用示例照片。背景、AD 减号盾牌图标和页面布局为 XGuard 新绘制。
## XGuard 0.9.2 GPL-3.0

新增 GKD 兼容订阅层与修改代码按 GPL-3.0-only 发布，完整条款见 `LICENSE`、`/module/LICENSE` 和 `webroot/GPL-3.0.txt`。GKD 及社区订阅只按上游归属和条款提供参考/在线下载，不随模块捆绑完整订阅数据。
