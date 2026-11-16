# XGuard 0.8.6

作者 **Xuan**。基于原作者 **惜故里丶** 的原始作品二次创作，保留原作者与第三方规则署名。

## 更新

- 概览增加命中比例环图、近 12 分钟的最近记录分布及最多 5 个命中域名排行；图表仅使用保留的域名记录，并非全量请求统计。
- HOSTS 卡片显示实际挂载状态、规则域名数与近期命中域名数。本地 hosts 解析不会产生网络包，无法直接统计真实拦截次数。
- 连接状态先显示，首页使用轻量统计，开屏数量显示后台最近核验结果；打开开屏页时重新检查实际锁定状态。
- 日志改为可关闭弹窗，分区显示核心日志、防护日志及运行状态；扫描深度与自动更新间隔使用统一的玻璃风格选择弹窗。
- 完整更新日志与验证范围见仓库 `docs/RELEASE-v0.8.6.md`。

以下为沿用的界面与基础功能：

- 提高所有卡片、底栏、选中标签、浮动按钮与弹窗的通透度：降低表面底色与渐变浓度，适度减轻模糊，保留三级投影、细描边与边缘高光。浅色主卡片基底不透明度由 76% 降至 46%，普通卡片由 66% 降至 34%。
- 修复浅色模式下选中导航标签只有淡蓝底块的问题。选中项采用独立实时毛玻璃与轻微折射、白色边缘高光和柔和投影，五个标签共享可移动透镜；蓝色图标与文字保留选中提示。
- 模块 ID `xguard`，App 包名 `com.xuan.xguard`，防护引擎 `shield`，命令 `xguard`，数据目录 `/data/adb/xguard`。代理协作使用 `proxy_*` 配置与“代理服务”文案。
- 模块和 App 统一为 `0.8.6` / `8006`，配套 APK、启动器图标与实际安装路径同步更新。
- 强化卡片悬浮层次：主功能、统计、操作卡片使用不同强度的柔和投影与半透明表面，统一 22px 圆角，增加顶部高光和细描边。普通卡片模糊 4px，主功能 5px，操作卡片 3px。
- 采用统一蓝色 `#1677FF` 与双主题中性色。保留类似 0.7.0 的原创抽象光环背景，将图案不透明度降至浅色 52% / 深色 48%，增加分组和卡片留白，减弱纹理穿透。
- 复用 PrismalAGSL 的透镜算法：底部导航、浮动按钮和弹窗采样实时页面背景，加入轻微折射与边缘高光。普通卡片不运行复杂光学滤镜。
- 页面切换立即完成，数据在后台按页面合并读取并短期缓存；保存与 Root 命令不会锁住导航。
- 首次打开显示 Root 授权说明，确认后向系统 Root 管理器请求权限；拒绝可重试，稍后授权仍可浏览界面。
- 防护检查改为可关闭弹窗，详细诊断默认折叠。支持完成、关闭、系统返回与点击外部，不再占据概览页面。
- 保留实际 DNS / TLS 域名观察、搜索、筛选、一键封禁与放行、规则来源、开屏管理、诊断及安全模式。

## 安装或升级

1. 用 Magisk / KernelSU / SukiSU / APatch 管理器安装 `XGuard-v0.8.6-module.zip`，支持 Android 11 及以上。
2. 安装器复制旧版的规则、来源、自定义开屏规则、单独解锁名单、开关和代理设置到新目录，不删除原始数据。已经存在的新配置优先，迁移可重复执行。
3. 旧独立防护模块会停止并被禁用，避免两个引擎同时挂载 hosts；其他同时修改 hosts 的模块仍需由用户处理冲突。
4. 重启手机。模块会安装或更新新的 XGuard App；也可以手动安装 `XGuard-v0.8.6-root.apk`。新包安装成功后，旧 App 会被停用并保留数据以便回退。
5. 首次打开新 App，点击“授权并连接”，在 Root 管理器中允许 XGuard。它与旧包名的 Root 授权独立。

`source.zip` 是源码，不能刷入。运行数据位于 `/data/adb/xguard/shield`，设置位于 `/data/adb/xguard/config/settings.prop`。安装日志 `/data/adb/xguard/logs/install.log`。

## 域名观察范围

被动 AF_PACKET socket 观察实际网络接口上的明文 DNS 和 TLS SNI，支持普通 IPv4/IPv6 DNS、TCP DNS 与连续 TCP 分段 ClientHello，不接管网络、不安装证书。加密 DNS、ECH 内层域名、QUIC、乱序分段、IP 分片、缓存命中及 hosts 提前拦截的请求可能没有可见记录。

“规则命中”表示当前 hosts 规则覆盖该域名，不能据此断言该连接已被阻断。新规则主要对之后按系统 DNS 解析的连接生效；已有连接、缓存及自带解析器可能继续使用旧结果。

界面每 2 秒更新，最多保留 240 条快照记录于 RAM 目录 `/dev/xguard`。暂停采集不影响 hosts 防护。采集权限不足会显示具体错误；模块不会关闭 SELinux。诊断文件 `/data/adb/xguard/state/monitor.err`。

```text
xguard status
xguard enable shield
xguard disable shield
xguard run shield activity
xguard run shield activity enable
xguard run shield activity disable
xguard run shield activity clear
xguard run shield block add ads.example.com
xguard run shield allow add ads.example.com
```

本版的检查范围见仓库 `docs/VALIDATION-v0.8.6.md`。v0.8.5 的迅雷冷启动与 VPN 探针结果属于历史验证，不表示本轮重复执行；域名规则与缓存锁定不能保证移除所有广告。
