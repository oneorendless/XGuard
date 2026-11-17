# XGuard 0.9.2 验证记录

验证日期：2026-11-17（北京时间）。本版本仅本地构建，尚未创建 GitHub Release。

## 改动

- GKD 标题下的第一张卡片提供“隐藏最近任务”开关，采用蓝色重点样式，默认关闭。
- Root 与免 Root 两版通过原生桥接保存 `hide_from_recents`，由 Android `ActivityManager.AppTask.setExcludeFromRecents()` 更新当前任务；Activity 创建时恢复已保存的设置。
- 此设置不需要 Root、VPN 或无障碍授权，也不修改订阅启停状态。
- 版本、构建脚本、页面显示与说明同步为 0.9.2；本地订阅 ID 保持不变。

## 已通过

- `node tests/ui-v091.mjs`：已有首次授权、六个底栏、独立订阅、下载与删除、无障碍守护、GPL 入口及窄屏布局回归。
- `node tests/ui-v092.mjs`：Root/VPN 开关默认值、可见位置、未授权仍可切换、开关与页面重载后的状态、桥接异常恢复、缺少新桥接时禁用，以及 320px 深浅色布局。
- 两版 Java、DEX、资源构建及 APK 签名验证；Root 版本 `0.9.2 / 9002`，免 Root 版本 `0.9.2-noroot / 90021`。
- Root/VPN 隔离原生测试 APK 编译通过，测试代码检查实际任务排除标志及 Activity 重启后的恢复。
- 模块打包检查：APK 名称、包名、版本与签名，WebUI 与 APK assets 相同，ZIP 根路径和内嵌 APK 校验值一致。
- 源码包包含当前工作区源码、许可证、说明与构建脚本，排除密钥、设备记录与编译产物。

## 尚未执行

本轮 `adb devices -l` 未发现已连接设备，因此未运行原生 instrumentation，也未进行厂商最近任务界面的隐藏/恢复实测。页面持久化结果使用浏览器桥接模拟，不能替代 Android 实机验证。本轮未安装到正式手机或刷入模块。
