#!/system/bin/sh
# 防护引擎 shield（v0.2.20 ③，原 adblock 去广告）：hosts 去广告（多源合并）+ HTTPDNS 拦截 + 开屏缓存锁定
# 契约：配置 $XG_DATA/shield/config.json（core_cfg_get / core_cfg_set，旧 config/adblock.prop 兜底读）、
#       状态 $XG_DATA/shield/status.json（status.sh / start.sh 写）、自定义动作在 actions/。
# v0.2.23 重做（参考 bindhosts / Re-Malwack，调研见 patches/shield-research.md）：
#   · 规则源改成具名目录 sources.list，可单独开关；按源缓存，开关源 / 放行 / 拦截都不用重新下载
#   · 合并 → 去重 → 白名单（支持 *.example.com）→ 上限（默认 20 万，按源优先级截断）
#   · 挂载方式自动选择：ZN-hostsredirect / APatch hosts_file_redirect / zygote 命名空间 bind（失败退 overlay）
#   · hosts 原地写（bind 指向的 inode 不变，更新后不用重挂），首行写标记，「是否生效」= 在 zygote 命名空间读到标记
. "$XG_MODDIR/core/lib.sh"
SHIELD=shield
AD_DIR=$XG_DATA/$SHIELD                 # 原 $XG_DATA/adblock（迁移时改名，旧路径留软链）
HOSTS_SRC=$AD_DIR/hosts              # 生成的 hosts（bind 模式直接挂它）
OVERLAY_ROOT=/dev/.xguard-overlay
SRC_DIR=$AD_DIR/src                  # 每个源的缓存：<id>.list（纯域名）+ <id>.meta
CATALOG=$XG_FDIR/sources.list
MARK="# XGuard"                      # hosts 首行标记
# 旧版的唯一默认源（v0.2.22 及以前写进 config 的 hosts_url）：迁移时从自定义源里剔除
HOSTS_URL_OLD_DEFAULT="https://gcore.jsdelivr.net/gh/TG-Twilight/AWAvenue-Ads-Rule@main/Filters/AWAvenue-Ads-Rule-hosts.txt"
# 列表文件（v0.2.20 起放插件数据目录；原 config/adblock.* 迁移时复制过来，旧文件保留给降级）
ALLOW=$AD_DIR/allow                  # 放行域名：一行一个，*.example.com = 该域名及全部子域名
BLOCK=$AD_DIR/block                  # 自定义拦截域名：一行一个
USER_RULES=$AD_DIR/splash.rules
SKIP=$AD_DIR/skip                    # 用户单独解锁的 App：splash_apply 永久跳过
APP_ALLOW=$AD_DIR/app-allowlist
META=$AD_DIR/hosts.meta              # 更新记录：last_try / last_ok / result / rules / sources_ok / capped
TEST_JSON=$AD_DIR/test.json          # 最近一次自检结果（xguard run shield test）
ACTIVITY=$AD_DIR/activity.log        # 最近域名活动（时间\t域名\t动作\t来源）
ACTIVITY_MAX=240
mkdir -p "$AD_DIR" "$SRC_DIR"

# ---------- 规则源目录 ----------
# v0.2.22 修复：这里以前写 grep -E '^\s*(#|$)'。Android 的 toybox grep 用 bionic（NetBSD）regcomp，不开 REG_GNU 时
# 「\ + 字母」是非法转义（REG_EESCAPE）→ grep 直接报 bad regex 退出、没有任何输出（2>/dev/null 把报错也吞了）。
# 结果真机上目录读出来是空的：规则源列表为空、一个源都不下载、hosts 从没生成、开屏规则 / HTTPDNS IP 也全是 0 条。
# 桌面 Linux 的 GNU / musl / busybox grep 都认 \s，所以沙盒里一直测不出来。一律用 POSIX 字符类 [[:space:]]。
shield_lines() { grep -vE '^[[:space:]]*(#|$)' "$@" 2>/dev/null; }   # 去掉注释和空行
cat_lines() { shield_lines "$CATALOG"; }
cat_ids() { cat_lines | cut -d'|' -f1; }
cat_field() { cat_lines | awk -F'|' -v i="$1" -v c="$2" '$1==i {print $c; exit}'; }   # <id> <列>
cat_default_ids() { cat_lines | awk -F'|' '$2==1{printf "%s ", $1}' | sed 's/ $//'; }
cat_min() { _m=$(cat_field "$1" 6); case "$_m" in ''|*[!0-9]*) _m=50 ;; esac; echo "$_m"; }   # 下载结果至少多少条才算有效
# 内置源（地址写 builtin:<相对插件目录的路径>）：不联网，直接读模块里的文件
src_builtin_file() { _bu=$(cat_field "$1" 5); case "$_bu" in builtin:*) echo "$XG_FDIR/${_bu#builtin:}"; return 0 ;; esac; return 1; }
is_builtin() { case "$(cat_field "$1" 5)" in builtin:*) return 0 ;; esac; return 1; }
# 已启用的内置源（config sources，空格分隔；没写过 = 目录里默认开的）。
# 只认目录里存在的 id（旧版本存的、已下架的 id 会被忽略）；一个都不剩又没有自定义源 → 退回默认，绝不会「没有规则源」
src_enabled_ids() {
  _cf=$(core_cfg_get $SHIELD sources "")
  [ -n "$_cf" ] || { cat_default_ids; return; }
  _ids=" $(cat_ids | tr '\n' ' ') "; _ok=""
  for _x in $_cf; do case "$_ids" in *" $_x "*) _ok="$_ok $_x" ;; esac; done
  [ -n "$_ok" ] || [ -n "$(core_cfg_get $SHIELD hosts_url "")" ] || { cat_default_ids; return; }
  echo ${_ok# }
}
src_enabled() { case " $(src_enabled_ids) " in *" $1 "*) return 0 ;; esac; return 1; }
# 自定义源 URL（config hosts_url，沿用旧键）：剔除旧默认源和目录里已有的地址
custom_urls() {
  _all=$(cat_lines | cut -d'|' -f5)
  for _u in $(core_cfg_get $SHIELD hosts_url ""); do
    [ "$_u" = "$HOSTS_URL_OLD_DEFAULT" ] && continue
    case " $(echo $_all) " in *" $_u "*) continue ;; esac
    printf '%s\n' "$_u"
  done
}
custom_id() { printf 'custom_%s' "$(printf '%s' "$1" | cksum | cut -d' ' -f1)"; }
# 优先级顺序的「已启用源」：目录顺序，再接自定义源
active_ids() {
  _ae=" $(src_enabled_ids) "
  for _i in $(cat_ids); do case "$_ae" in *" $_i "*) echo "$_i" ;; esac; done
  for _u in $(custom_urls); do custom_id "$_u"; echo; done
}
src_list_file() { src_builtin_file "$1" || echo "$SRC_DIR/$1.list"; }
src_count() { _f=$(src_list_file "$1"); _c=0; [ -s "$_f" ] && _c=$(grep -cvE '^[[:space:]]*(#|$)' "$_f" 2>/dev/null); echo "${_c:-0}"; }
BUILTIN_ALLOW=$XG_FDIR/rules/allow.list   # 内置放行（防误杀登录 / 支付 / 聊天），用户「拦截」优先于它
UPSTREAM_ALLOW=$XG_FDIR/rules/allow.upstream.list   # v0.2.27：anti-AD dead-horse / 217heidai / GOODBYEADS 白名单（行尾 # 注出处）
PROTECT=$XG_FDIR/rules/protect.list   # v0.5.12：永不拦截（FCM 推送必需域名，青鸟），连用户「拦截」也不生效
# 是否在内置放行里（两份文件，忽略行尾注释）
builtin_allowed() { cat "$BUILTIN_ALLOW" "$UPSTREAM_ALLOW" 2>/dev/null | sed 's/#.*//; s/[[:space:]]//g' | grep -qixF "$1"; }

# ---------- 代理服务 ----------
# 代理服务是否在接管网络。默认看 mihomo 进程；代理服务可写 /data/adb/proxy/running 作为更准确的约定
proxy_running() {
  # 标记文件里若写了 pid，进程不在就当没运行（代理服务崩溃后残留的标记曾让 hosts 永久撤下）
  _proxy_marker=$(core_cfg_get $SHIELD proxy_marker /data/adb/xguard/proxy/running)
  if [ -f "$_proxy_marker" ]; then
    _hp=$(head -n1 "$_proxy_marker" 2>/dev/null | tr -cd '0-9')
    [ -z "$_hp" ] && return 0
    kill -0 "$_hp" 2>/dev/null && return 0
  fi
  legacy_proxy_active && return 0
  for p in $(core_cfg_get $SHIELD proxy_process "mihomo clash"); do
    pidof "$p" >/dev/null 2>&1 && return 0
  done
  return 1
}
# 代理服务运行时是否撤下 hosts（config proxy_yield，默认 0 = 不撤）。
# v0.2.24：hosts 由 netd 在发 DNS 请求之前本地查，代理服务（mihomo）的 DNS 劫持 / fake-ip 拿不到被拦截的域名，两者不冲突；
# 以前只要有 mihomo/clash 进程就整个撤掉 hosts，而代理服务自己的去广告可能没开，结果就是「去广告根本没用」。
# HTTPDNS IP 拦截（iptables）仍然在代理服务运行时让位，避免和它的 iptables 规则打架。
proxy_yield() { [ "$(core_cfg_get $SHIELD proxy_yield 0)" = 1 ] && proxy_running; }

# ---------- 命名空间 ----------
# v0.2.24 修正：系统 DNS（getaddrinfo）是 netd 里的 DnsResolver 读 /system/etc/hosts，App 自己不读；
# 所以 hosts 必须出现在 netd 的 mount 命名空间里（另外 zygote 命名空间给 Chrome 这类自带解析器的 App 用）。
# 以前只挂在 zygote 命名空间、也只在 zygote 里检查——两者不同时，界面显示「生效」但系统 DNS 根本没读到。
# 读别的命名空间里的文件一律走 /proc/<pid>/root（不依赖 nsenter）。
shield_ns_pid() { _zp=$(pidof zygote64 2>/dev/null || pidof zygote 2>/dev/null); _zp=${_zp%% *}; echo "${_zp:-1}"; }
shield_netd_pid() { _np=$(pidof netd 2>/dev/null); _np=${_np%% *}; echo "${_np:-}"; }
# 需要挂载的命名空间（按 mnt ns 去重）：netd 优先，再 zygote64 / zygote
shield_ns_targets() {
  _seen=""
  for _p in $(shield_netd_pid) $(pidof zygote64 2>/dev/null) $(pidof zygote 2>/dev/null); do
    _ns=$(readlink "/proc/$_p/ns/mnt" 2>/dev/null) || continue
    [ -n "$_ns" ] || continue
    case " $_seen " in *" $_ns "*) continue ;; esac
    _seen="$_seen $_ns"; echo "$_p"
  done
  [ -n "$_seen" ] || echo 1
}
shield_nsrun() {   # <pid> <cmd...>：在该进程的 mount 命名空间执行；本来就在其中则直接执行
  _p=$1; shift
  _target_ns=$(readlink "/proc/$_p/ns/mnt" 2>/dev/null) || return 1
  [ "$(readlink /proc/$$/ns/mnt 2>/dev/null)" = "$_target_ns" ] && { "$@"; return; }
  if command -v nsenter >/dev/null 2>&1; then nsenter -t "$_p" -m -- "$@"
  elif toybox nsenter --help >/dev/null 2>&1; then toybox nsenter -t "$_p" -m -- "$@"
  else bb nsenter -t "$_p" -m -- "$@"; fi
}
shield_global() { shield_nsrun "$(shield_ns_pid)" "$@"; }   # 兼容旧调用：zygote 命名空间
# 某进程看到的 /system/etc/hosts 是不是防护引擎的（首行标记）
shield_view() { head -n1 "/proc/$1/root/system/etc/hosts" 2>/dev/null | grep -q "^$MARK"; }
shield_view_rules() { _c=$(grep -c '^0\.0\.0\.0 ' "/proc/$1/root/system/etc/hosts" 2>/dev/null); echo "${_c:-0}"; }
shield_overlay_upper() {
  awk '$1 == "shield" && $2 == "/system/etc" && $3 == "overlay" {
    count=split($4, options, ","); for (i=1; i<=count; i++) if (options[i] ~ /^upperdir=/) print substr(options[i], 10)
  }' "/proc/$1/mounts" 2>/dev/null | while IFS= read -r upper; do
    case "$upper" in "$OVERLAY_ROOT"/mnt-*/upper|"$AD_DIR/ov/upper") printf '%s\n' "$upper" ;; esac
  done
}

shield_live_overlay() {
  for target_pid in $(shield_ns_targets); do
    shield_view "$target_pid" || continue
    for upper in $(shield_overlay_upper "$target_pid"); do
      if [ "/proc/$target_pid/root/system/etc/hosts" -ef "$upper/hosts" ] ||
         ! grep -q ' /system/etc/hosts ' "/proc/$target_pid/mounts" 2>/dev/null; then
        printf '%s\n' "$upper"
        return 0
      fi
    done
  done
  return 1
}

# ---------- 挂载方式（参考 bindhosts post-fs-data.sh 的模式探测） ----------
mod_on() { [ -d "/data/adb/modules/$1" ] && [ ! -f "/data/adb/modules/$1/disable" ] && [ ! -f "/data/adb/modules/$1/remove" ]; }
shield_root() {   # magisk / ksu / ksu_next / apatch / unknown
  if [ -e /data/adb/ksud ] || [ -d /data/adb/ksu ]; then
    /data/adb/ksud -V 2>/dev/null | grep -qi next && echo ksu_next || echo ksu
  elif [ -d /data/adb/ap ]; then echo apatch
  elif [ -d /data/adb/magisk ] || command -v magisk >/dev/null 2>&1; then echo magisk
  else echo unknown; fi
}
# mount_mode：auto（默认）/ bind / overlay / zn / hfr
#   zn  = ZN-hostsredirect（Zygisk 注入 netd，不挂载）：写 /data/adb/hostsredirect/hosts
#   hfr = APatch hosts_file_redirect KPM：写 /data/adb/hosts
#   bind = zygote 命名空间 mount --bind（bindhosts mode 2「plain bindhosts」，所有 root 方案都能用）
#   overlay = /system/etc 叠加层（bindhosts mode 7，bind 失败时 auto 才会用）
shield_preferred_method() {
  _m=$(core_cfg_get $SHIELD mount_mode auto)
  [ "$_m" = auto ] || { echo "$_m"; return; }
  if mod_on hostsredirect && mod_on zygisksu; then echo zn
  elif [ -d /data/adb/ap ] && dmesg 2>/dev/null | grep -q hosts_file_redirect; then echo hfr
  else echo bind; fi
}
shield_method() {
  case "$(shield_preferred_method)" in
    zn) echo zn ;;
    hfr) echo hfr ;;
    *) if shield_live_overlay >/dev/null; then echo overlay
       elif hosts_views_mounted; then echo bind
       else shield_preferred_method; fi ;;
  esac
}
shield_target() {   # 该方式下 hosts 实际要写到哪
  case "$(shield_method)" in
    zn) echo /data/adb/hostsredirect/hosts ;;
    hfr) echo /data/adb/hosts ;;
    overlay) upper=$(shield_live_overlay) && printf '%s/hosts\n' "$upper" || echo "$HOSTS_SRC" ;;
    *) echo "$HOSTS_SRC" ;;
  esac
}
hosts_set_perm() {   # 和系统 hosts 同属主 / 权限 / SELinux（参考 bindhosts hosts_set_perm）
  chown 0:0 "$1" 2>/dev/null; chmod 0644 "$1"
  chcon u:object_r:system_file:s0 "$1" 2>/dev/null || bb chcon u:object_r:system_file:s0 "$1" 2>/dev/null
}
# 系统原始 hosts（撤下时恢复 zn / hfr 目标用）
stock_hosts() { printf '127.0.0.1 localhost\n::1 ip6-localhost\n'; }

# 是否生效：bind/overlay = netd（系统 DNS）和 zygote（之后启动的 App）看到的 /system/etc/hosts 都带标记；
# zn/hfr 读目标文件首行
hosts_mounted() {
  case "$(shield_preferred_method)" in
    zn|hfr) head -n1 "$(shield_target)" 2>/dev/null | grep -q "^$MARK" ;;
    *) hosts_views_mounted ;;
  esac
}
hosts_views_mounted() {
  for target_pid in $(shield_ns_targets); do shield_view "$target_pid" || return 1; done
}
shield_bound() { grep -qE ' /system/etc(/hosts)? ' "/proc/$(shield_ns_pid)/mounts" 2>/dev/null; }   # 有任何挂载（含别人的）

# 把 $HOSTS_SRC 的内容送到目标（原地写，保持 inode）
hosts_write() {
  mkdir -p "${1%/*}" && cat "$HOSTS_SRC" >"$1" || return 1
  hosts_set_perm "$1" || :
}
hosts_publish() (
  case "$(shield_preferred_method)" in
    zn) hosts_write /data/adb/hostsredirect/hosts ;;
    hfr) hosts_write /data/adb/hosts ;;
    *)
      for target_pid in $(shield_ns_targets); do
        [ -n "$(shield_overlay_upper "$target_pid")" ] && shield_view "$target_pid" || continue
        view="/proc/$target_pid/root/system/etc/hosts"
        cmp -s "$HOSTS_SRC" "$view" || cat "$HOSTS_SRC" >"$view" || return 1
      done ;;
  esac
)

shield_mount_try() (
  target_pid=$1; operation=$2; shift 2
  namespace=$(readlink "/proc/$target_pid/ns/mnt" 2>/dev/null)
  shield_nsrun "$target_pid" "$@" && return 0
  result=$?
  printf '%s pid=%s ns=%s rc=%s\n' "$operation" "$target_pid" "${namespace:-gone}" "$result" >&2
  return "$result"
)

overlay_mount() (
  for target_pid in $(shield_ns_targets); do
    shield_view "$target_pid" && continue
    namespace=$(readlink "/proc/$target_pid/ns/mnt" 2>/dev/null) || continue
    namespace=${namespace#mnt:\[}; namespace=${namespace%\]}
    case "$namespace" in ''|*[!0-9]*) continue ;; esac
    mkdir -p "$OVERLAY_ROOT" && chmod 0700 "$OVERLAY_ROOT" || return 1
    storage=$(mktemp -d "$OVERLAY_ROOT/mnt-$namespace.XXXXXX") || return 1
    if ! mkdir "$storage/work" || ! hosts_write "$storage/upper/hosts"; then
      printf 'overlay storage failed pid=%s ns=%s\n' "$target_pid" "$namespace" >&2
      rm -rf "$storage"
      continue
    fi
    shield_mount_try "$target_pid" overlay mount -t overlay -o "lowerdir=/system/etc,upperdir=$storage/upper,workdir=$storage/work" shield /system/etc || rm -rf "$storage"
  done
  hosts_views_mounted
)

# 可选隐藏（hide=1）：登记给 KernelSU / susfs 的 try_umount，开了「卸载模块」的 App 里会撤掉挂载。
# 默认不登记：去广告要的是所有 App 都生效（bindhosts 的 mode 1/10 是为了隐藏，方向相反）
shield_hide() {
  [ "$(core_cfg_get $SHIELD hide 0)" = 1 ] || return 0
  if [ -x /data/adb/ksu/bin/ksu_susfs ]; then /data/adb/ksu/bin/ksu_susfs add_try_umount /system/etc/hosts 1 >/dev/null 2>&1
  elif [ -x /data/adb/ksud ]; then /data/adb/ksud kernel umount add /system/etc/hosts --flags 2 >/dev/null 2>&1; fi
}

# bind：在 netd / zygote 各自的命名空间里挂（同一 peer group 时第一次挂载会传播过去，第二个就跳过）
bind_mount_all() (
  for _p in $(shield_ns_targets); do
    shield_view "$_p" && continue
    # 别人（旧防护引擎 / 其他模块）留下的 bind 先卸掉，参考 Re-Malwack remount_hosts
    grep -q ' /system/etc/hosts ' "/proc/$_p/mounts" 2>/dev/null && shield_mount_try "$_p" umount umount -l /system/etc/hosts
    shield_mount_try "$_p" 'mount -o bind' mount -o bind "$HOSTS_SRC" /system/etc/hosts ||
      shield_mount_try "$_p" 'mount --bind' mount --bind "$HOSTS_SRC" /system/etc/hosts
  done
  hosts_views_mounted
)

mount_error_head() { head -c 400 "$AD_DIR/mount.err" 2>/dev/null | tr '[:cntrl:]' ' '; }
mount_fallback() { cat "$AD_DIR/mount.fallback" 2>/dev/null || echo none; }

hosts_on() (
  feat_enabled "$SHIELD" && ! shield_paused || return 0
  recovery_lock mount || return 1
  feat_enabled "$SHIELD" && ! shield_paused || return 0
  [ -s "$HOSTS_SRC" ] || return 1
  head -n1 "$HOSTS_SRC" | grep -q "^$MARK" || return 1
  hosts_set_perm "$HOSTS_SRC"
  rm -f "$AD_DIR/method.overlay"
  _me=$(shield_preferred_method)
  case "$_me" in
    zn|hfr) rm -f "$AD_DIR/mount.fallback" "$AD_DIR/mount.err" "$AD_DIR/mount.fail"
      hosts_mounted && return 0
      hosts_publish && log $SHIELD "hosts 已写入 $(shield_target)（$_me 重定向，新启动的 App 生效）"; return ;;
  esac
  if hosts_views_mounted; then hosts_publish; return; fi
  rm -f "$AD_DIR/mount.fallback"
  : >"$AD_DIR/mount.err"
  if [ "$_me" = overlay ]; then
    if ! overlay_mount 2>>"$AD_DIR/mount.err"; then
      echo bind_after_overlay_fail >"$AD_DIR/mount.fallback"
      bind_mount_all 2>>"$AD_DIR/mount.err"
    fi
  elif ! bind_mount_all 2>>"$AD_DIR/mount.err" && [ "$(core_cfg_get $SHIELD mount_mode auto)" = auto ]; then
    echo overlay_after_bind_fail >"$AD_DIR/mount.fallback"
    overlay_mount 2>>"$AD_DIR/mount.err"
  fi
  if hosts_views_mounted && hosts_publish; then
    rm -f "$AD_DIR/mount.fail"; shield_hide
    log $SHIELD "hosts 已挂载（$(shield_method)，netd pid=$(shield_netd_pid) / zygote pid=$(shield_ns_pid)，fallback=$(mount_fallback)）$(mount_error_head)"
    return 0
  fi
  for target_pid in $(shield_ns_targets); do
    shield_view "$target_pid" || printf 'hosts not visible pid=%s ns=%s\n' "$target_pid" "$(readlink "/proc/$target_pid/ns/mnt" 2>/dev/null)" >>"$AD_DIR/mount.err"
  done
  if [ $(( $(date +%s) - $(cat "$AD_DIR/mount.fail" 2>/dev/null || echo 0) )) -ge 3600 ]; then
    log $SHIELD "hosts 挂载失败（$_me，fallback=$(mount_fallback)）：$(mount_error_head)"
    date +%s >"$AD_DIR/mount.fail"
  fi
  return 1
)
hosts_off() (
  recovery_lock mount || return 1
  rm -f "$AD_DIR/method.overlay" "$AD_DIR/mount.fallback" "$AD_DIR/mount.fail" "$AD_DIR/mount.err"
  # zn / hfr：目标文件还是防护引擎写的就恢复默认
  for _tg in /data/adb/hostsredirect/hosts /data/adb/hosts; do
    head -n1 "$_tg" 2>/dev/null | grep -q "^$MARK" && { stock_hosts >"$_tg"; hosts_set_perm "$_tg"; log $SHIELD "hosts 重定向 $_tg 已恢复默认"; }
  done
  # bind / overlay：不按「当前方式」猜（方式可能在挂上之后变过），对每个能看到防护引擎 hosts 的 mount 命名空间都撤，
  #   bind（/system/etc/hosts）和 overlay（/system/etc，源名 shield）两种都卸。除 netd / zygote 外还扫全部进程的命名空间：
  #   zygote 里挂载之后才 fork 的 App 拿到的是挂载副本（不随 zygote 卸载传播），之前「关了仍残留」就是它们。
  _did=0; _seen=""
  for _p in $(shield_ns_targets) $(ls /proc 2>/dev/null | grep -E '^[0-9]+$'); do
    _ns=$(readlink "/proc/$_p/ns/mnt" 2>/dev/null) || continue
    case " $_seen " in *" $_ns "*) continue ;; esac
    _seen="$_seen $_ns"
    shield_view "$_p" || continue
    _n=0
    while shield_view "$_p" && [ $_n -lt 4 ]; do
      if grep -q ' /system/etc/hosts ' "/proc/$_p/mounts" 2>/dev/null; then shield_nsrun "$_p" umount -l /system/etc/hosts 2>/dev/null
      elif [ -n "$(shield_overlay_upper "$_p")" ]; then shield_nsrun "$_p" umount -l /system/etc 2>/dev/null
      else break; fi
      _n=$((_n+1)); _did=$((_did+1))
    done
    shield_view "$_p" && log $SHIELD "警告：pid $_p 的命名空间里 hosts 卸不掉（$(grep -E ' /system/etc(/hosts)? ' "/proc/$_p/mounts" | head -n1)）"
  done
  [ $_did -gt 0 ] && log $SHIELD "hosts 已撤下（$_did 次卸载）"
  return 0
)
# 残留检查（关闭后 App / 自检用）：输出仍能看到防护引擎 hosts 的进程数，0 = 干净
hosts_residue() {
  _c=0; _seen=""
  for _p in $(ls /proc 2>/dev/null | grep -E '^[0-9]+$'); do
    _ns=$(readlink "/proc/$_p/ns/mnt" 2>/dev/null) || continue
    case " $_seen " in *" $_ns "*) continue ;; esac
    _seen="$_seen $_ns"; shield_view "$_p" && _c=$((_c+1))
  done
  echo $_c
}

# ---------- 规则处理 ----------
# 域名校验：只允许字母数字 . - _，防止写进 hosts 的内容被当成别的东西
valid_domain() { printf '%s' "$1" | grep -qE '^[A-Za-z0-9_]([A-Za-z0-9_.-]{0,251}[A-Za-z0-9_])?$' && case "$1" in *..*) return 1 ;; esac; }
valid_allow() { case "$1" in \*.*.*) ;; \*.*) return 1 ;; esac; valid_domain "${1#\*.}"; }   # 放行允许 *.example.com（不允许 *.com 这种整个后缀）

# 标准化：任意格式 → 一行一个小写域名
#   hosts（一行多个名字）/ 纯域名 / +.domain、*.domain、.domain（Surge domainset、AdGuardHome 通配，hosts 只能拦主域名本身）/
#   ||domain^、||*.domain^（@@ 例外、带路径 / 正则的规则跳过）。纯 IP、localhost 一类、没有字母后缀的都丢掉。
normalize() {
  tr -d '\r' | sed 's/[[:space:]]#.*$//' | tr 'A-Z' 'a-z' | awk '
    function emit(d) {
      sub(/^(\+\.|\*\.|\.)/, "", d)
      if (d ~ /^[a-z0-9_]([a-z0-9_-]*\.)+[a-z0-9-]*[a-z][a-z0-9-]*$/ && length(d) <= 253) print d
    }
    /^[ \t]*([#!\[]|$)/ { next }
    { sub(/^[ \t]+/, "") }
    /^@@/ { next }
    /^\|\|/ { d=$1; sub(/^\|\|/, "", d); if (index(d, "^") == 0) next; sub(/\^.*$/, "", d); emit(d); next }
    ($1=="0.0.0.0"||$1=="127.0.0.1"||$1=="::"||$1=="::1"||$1=="0") && NF>=2 {
      for (i=2;i<=NF;i++) { d=$i
        if (d ~ /^(localhost|localhost\.localdomain|local|broadcasthost|ip6-.*|0\.0\.0\.0)$/) continue
        emit(d) }
      next }
    NF==1 { emit($1) }'
}

# 由各源缓存 + 自定义拦截 - 放行 生成最终 hosts（不联网）。
# 原地写入 $HOSTS_SRC（bind 指向的 inode 不变，所有 App 立即看到新内容，不必重挂）
hosts_build() (
  recovery_lock build || return 1
  cap=$(core_cfg_get $SHIELD hosts_max 200000)
  case "$cap" in ''|*[!0-9]*) cap=200000 ;; esac
  tmp=$AD_DIR/hosts.new
  # 每行「u 域名」= 用户自定义拦截（不受内置放行影响）、「s 域名」= 规则源；用户放行对两者都生效
  { [ -s "$BLOCK" ] && normalize <"$BLOCK" | sed 's/^/u /'
    normalize <"$XG_FDIR/rules/splash-domains.list" | sed 's/^/s /'
    for _i in $(active_ids); do
      if _bf=$(src_builtin_file "$_i"); then [ -s "$_bf" ] && normalize <"$_bf" | sed 's/^/s /'
      else [ -s "$SRC_DIR/$_i.list" ] && sed 's/^/s /' "$SRC_DIR/$_i.list"; fi
    done
  } | awk -v cap="$cap" -v allowf="$ALLOW" -v ballowf="$BUILTIN_ALLOW" -v uallowf="$UPSTREAM_ALLOW" -v protf="$PROTECT" -v cntf="$AD_DIR/build.cnt" '
    function rd(f, user,   l) { while ((getline l < f) > 0) { sub(/[ \t]*#.*/, "", l); gsub(/\r|[ \t]/, "", l); l=tolower(l)
              if (l=="" || l ~ /^#/) continue
              if (l ~ /^\*\./) { if (user) wild[substr(l,3)]=1 } else if (user) ex[l]=1; else bex[l]=1 } close(f) }
    function rdp(f,   l) { while ((getline l < f) > 0) { sub(/[ \t]*#.*/, "", l); gsub(/\r|[ \t]/, "", l); if (l != "") prot[tolower(l)]=1 } close(f) }
    BEGIN { rd(allowf, 1); rd(ballowf, 0); rd(uallowf, 0); rdp(protf) }
    { d=$2; if (d == "" || (d in seen)) next; seen[d]=1
      if (d in prot) { a++; next }   # v0.5.12 永不拦截（FCM），用户拦截也不生效
      if (d in ex) { a++; next }
      if ($1 == "s" && (d in bex)) { a++; next }
      x=d; ok=1; while (1) { if (x in wild) { ok=0; break }; p=index(x,"."); if (!p) break; x=substr(x,p+1) }
      if (!ok) { a++; next }
      n++; if (n>cap) { c++; next }
      print "0.0.0.0 " d }
    END { printf "total=%d\nallowed=%d\ncut=%d\n", n+0, a+0, c+0 > cntf }' >"$tmp.body"
  rules=$(wc -l <"$tmp.body" | tr -d ' ')
  { printf '%s %s rules=%s\n127.0.0.1 localhost\n::1 ip6-localhost\n' "$MARK" "$(date +%s)" "$rules"; cat "$tmp.body"; } >"$tmp"
  rm -f "$tmp.body"
  if [ "${rules:-0}" -eq 0 ] && [ ! -s "$BLOCK" ]; then rm -f "$tmp"; return 1; fi
  if ! ( recovery_lock mount && hosts_replace "$tmp" ); then rm -f "$tmp"; return 1; fi
  meta_set rules "$rules"; meta_set capped "$(prop_get "$AD_DIR/build.cnt" cut 0)"; meta_set allowed_hits "$(prop_get "$AD_DIR/build.cnt" allowed 0)"
  return 0
)

hosts_replace() {
  tmp=$1
  # 内容没变（忽略首行时间戳）就不动
  if [ ! -s "$HOSTS_SRC" ] || [ "$(sed 1d "$tmp" | cksum)" != "$(sed 1d "$HOSTS_SRC" | cksum)" ]; then
    if [ -f "$HOSTS_SRC" ]; then cp -p "$HOSTS_SRC" "$AD_DIR/hosts.write-backup" || return 1; fi
    if ! cat "$tmp" >"$HOSTS_SRC"; then
      [ ! -f "$AD_DIR/hosts.write-backup" ] || cat "$AD_DIR/hosts.write-backup" >"$HOSTS_SRC"
      rm -f "$AD_DIR/hosts.write-backup"; return 1
    fi
    rm -f "$AD_DIR/hosts.write-backup"; hosts_set_perm "$HOSTS_SRC"
  fi
  rm -f "$tmp"
  if feat_enabled "$SHIELD" && ! shield_paused && ! proxy_yield; then
    case "$(shield_preferred_method)" in
      zn|hfr) if hosts_mounted; then hosts_publish || return 1; fi ;;
      *) hosts_publish || return 1 ;;
    esac
  fi
  return 0
}
meta_set() { prop_set "$META" "$1" "$2"; }

# 下载：curl（系统 CA）→ curl 指定 Android CA 目录 → busybox wget --no-check-certificate（同 bindhosts / Re-Malwack）。
# Android 系统通常没有 curl；以前 wget 不带 --no-check-certificate、找不到 busybox 时退到不支持 https 的 toybox wget，
# 结果所有源都「下载失败」、hosts 一直是空的。失败原因写 src/<id>.err
hosts_fetch_one() {   # <url> <out>
  rm -f "$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --connect-timeout 10 -m 90 -o "$2" "$1" 2>"$2.err" && [ -s "$2" ] && return 0
    curl -fsSL --capath /system/etc/security/cacerts --connect-timeout 10 -m 90 -o "$2" "$1" 2>>"$2.err" && [ -s "$2" ] && return 0
  fi
  for _w in "${XG_BB:-}" /data/adb/ksu/bin/busybox /data/adb/ap/bin/busybox /data/adb/magisk/busybox; do
    [ -n "$_w" ] && [ -x "$_w" ] || continue
    "$_w" wget --no-check-certificate -q -T 30 -O "$2" "$1" 2>>"$2.err" && [ -s "$2" ] && return 0
    "$_w" wget -q -T 30 -O "$2" "$1" 2>>"$2.err" && [ -s "$2" ] && return 0   # 老 busybox 不认 --no-check-certificate
    break
  done
  case "$1" in http://*) wget -q -T 30 -O "$2" "$1" 2>>"$2.err" && [ -s "$2" ] && return 0 ;; esac
  command -v curl >/dev/null 2>&1 || [ -n "${XG_BB:-}" ] || echo "没有可用的下载工具（无 curl / busybox）" >>"$2.err"
  return 1
}
# 下载一个源（依次试镜像），成功写 src/<id>.list；失败保留旧缓存。结果写 src/<id>.meta
src_fetch() {   # <id> <url...>
  _id=$1; shift; _now=$(date +%s); _res=fail; _tmp=$SRC_DIR/$_id.dl
  _min=50; case "$_id" in custom_*) ;; *) _min=$(cat_min "$_id") ;; esac
  for _u in "$@"; do
    if hosts_fetch_one "$_u" "$_tmp"; then
      normalize <"$_tmp" | sort -u >"$_tmp.n"
      _n=$(wc -l <"$_tmp.n" | tr -d ' ')
      if [ "${_n:-0}" -ge "$_min" ]; then
        if [ -s "$SRC_DIR/$_id.list" ] && cmp -s "$_tmp.n" "$SRC_DIR/$_id.list"; then _res=same; rm -f "$_tmp.n"
        else mv -f "$_tmp.n" "$SRC_DIR/$_id.list"; _res=ok; fi
        break
      fi
      _res=invalid; echo "内容过少（$_n 条，至少 $_min 条），可能是镜像返回了错误页" >"$SRC_DIR/$_id.err"; log $SHIELD "规则源内容无效（$_n 条 < $_min）：$_u"
    else log $SHIELD "规则源下载失败：$_u（$(tail -n1 "$_tmp.err" 2>/dev/null | head -c 120)）"; tail -n 3 "$_tmp.err" >"$SRC_DIR/$_id.err" 2>/dev/null; fi
    rm -f "$_tmp.n"
  done
  rm -f "$_tmp" "$_tmp.err"
  case "$_res" in ok|same) rm -f "$SRC_DIR/$_id.err" ;; esac
  [ "$_res" = fail ] && [ ! -s "$SRC_DIR/$_id.err" ] && echo "所有镜像都下载失败" >"$SRC_DIR/$_id.err"
  _lok=$(prop_get "$SRC_DIR/$_id.meta" last_ok 0); [ "$_res" = ok ] || [ "$_res" = same ] && _lok=$_now
  printf 'result=%s\nlast_try=%s\nlast_ok=%s\nurl=%s\n' "$_res" "$_now" "$_lok" "$_u" >"$SRC_DIR/$_id.meta"
}

# 自动更新：默认每天最多一次（hosts_interval_h 可调，0=只手动）；各源并行下载；失败保留旧缓存；结果写 hosts.meta 给 App 看
hosts_update() (   # [force]
  shield_paused && return 0
  if [ "${1:-}" = force ]; then rm -f "$RECOVERY/update-hold"
  else
    _hold=$(cat "$RECOVERY/update-hold" 2>/dev/null); case "$_hold" in ''|*[!0-9]*) _hold=0 ;; esac
    [ "$_hold" -le "$(date +%s)" ] || return 0
  fi
  iv=$(core_cfg_get $SHIELD hosts_interval_h 24)
  if [ "${1:-}" != force ]; then
    lt=$(prop_get "$META" last_ok 0)
    [ "$iv" = 0 ] && [ -s "$HOSTS_SRC" ] && return 0
    [ -s "$HOSTS_SRC" ] && [ $(( $(date +%s) - ${lt:-0} )) -lt $(( iv * 3600 )) ] && return 0
    # 失败后不要每个 tick 都重试：至少隔 1 小时；还有已启用的源从没下载成功（首次安装 / 刚开源）时隔 10 分钟
    _bo=3600; src_missing && _bo=600
    [ -s "$HOSTS_SRC" ] && [ $(( $(date +%s) - $(prop_get "$META" last_try 0) )) -lt $_bo ] && return 0
  fi
  # 上次更新被超时杀掉会留下锁：超过 10 分钟的锁视为残留
  _lk=$XG_RUN/shield-update.lock
  [ -d "$_lk" ] && [ $(( $(date +%s) - $(stat -c %Y "$_lk" 2>/dev/null || echo 0) )) -gt 600 ] && rmdir "$_lk" 2>/dev/null
  recovery_lock rules || return 1
  lock_try shield-update || { log $SHIELD "已有更新在进行，跳过"; return 1; }
  trap 'if [ "${recovery_lock_owned:-false}" = true ]; then rm -f "$recovery_lock_dir/pid"; rmdir "$recovery_lock_dir" 2>/dev/null; fi; rmdir "$XG_RUN/shield-update.lock" 2>/dev/null || :' EXIT
  recovery_stage || { rm -rf "$recovery_stage_dir"; return 1; }
  now=$(date +%s); want=0
  for _i in $(active_ids); do
    case "$_i" in
      custom_*) for _u in $(custom_urls); do [ "$(custom_id "$_u")" = "$_i" ] && { src_fetch "$_i" "$_u" & }; done ;;
      *) is_builtin "$_i" && continue; src_fetch "$_i" $(cat_field "$_i" 5) & ;;
    esac
    want=$((want+1))
  done
  wait
  got=0; chg=0
  for _i in $(active_ids); do
    is_builtin "$_i" && continue
    case "$(prop_get "$SRC_DIR/$_i.meta" result fail)" in ok) got=$((got+1)); chg=1 ;; same) got=$((got+1)) ;; esac
  done
  if [ $got -gt 0 ] || [ $want -eq 0 ]; then
    [ $chg = 1 ] && res=ok || res=same
    [ $want -eq 0 ] && res=ok
  else res=fail; fi
  # 有没有缓存都重建一次（有源失败也用旧缓存）
  if ! hosts_build; then recovery_restore_sources "$recovery_stage_dir/src"; res=fail; fi
  if [ "$res" != fail ]; then
    if ! recovery_commit; then
      recovery_restore_sources "$recovery_stage_dir/src"; hosts_build
      rm -rf "$recovery_stage_dir"; res=fail
    fi
  else rm -rf "$recovery_stage_dir"; fi
  last_ok=$(prop_get "$META" last_ok 0); [ "$res" = fail ] || last_ok=$now
  meta_set last_try "$now"; meta_set last_ok "$last_ok"; meta_set result "$res"; meta_set sources_ok "$got"; meta_set sources_want "$want"
  log $SHIELD "规则更新：$res（$got/$want 个源成功，hosts $(hosts_rules) 条）"
  lock_free shield-update
  [ "$res" != fail ]
)

# 已启用的联网源里有没有从没下载成功过的（没有缓存）
src_missing() {
  for _i in $(active_ids); do
    is_builtin "$_i" && continue
    [ -s "$SRC_DIR/$_i.list" ] || return 0
  done
  return 1
}

# ---------- 首次 / 开机自动更新（后台，等网络 + 重试） ----------
# 开机 service 阶段网络多半还没起来，start.sh 里同步下载必然失败，然后要等 tick 退避；v0.2.22 改成后台任务：
#   等网络（最多 10 分钟）→ 更新 → 有源没下载成功就按 1 / 3 / 10 / 30 分钟重试，全部成功或用完次数就退出。
# 状态写 $AD_DIR/auto.state（state=waiting_net|running|retry|done|gave_up next=<epoch> try=<n>），App 显示真实进度。
AUTO_STATE=$AD_DIR/auto.state
AUTO_PID=$XG_RUN/shield-auto.pid
. "$XG_FDIR/recovery.sh"
shield_net_up() {
  for _h in 223.5.5.5 119.29.29.29 1.1.1.1; do ping -c 1 -W 3 "$_h" >/dev/null 2>&1 && return 0; done
  ip route show table all 2>/dev/null | grep -q '^default ' && return 0
  ip -6 route show table all 2>/dev/null | grep -q '^default ' && return 0
  return 1
}
auto_set() { printf 'state=%s\nnext=%s\ntry=%s\ntime=%s\n' "$1" "${2:-0}" "${3:-0}" "$(date +%s)" >"$AUTO_STATE"; }
auto_running() {
  _ap=$(cat "$AUTO_PID" 2>/dev/null)
  case "$_ap" in ''|*[!0-9]*) return 1 ;; esac
  kill -0 "$_ap" 2>/dev/null || return 1
  case "$(core_proc_args "$_ap")" in *autoupdate.sh*) return 0 ;; esac
  return 1
}
# 后台启动（脱离 xguardd / feat_run 的超时进程组）；已有一个在跑就不重复起
shield_kick_update() {   # [原因]
  shield_paused && return 0
  [ "$(core_cfg_get $SHIELD hosts_interval_h 24)" = 0 ] && return 0
  auto_running && return 0
  mkdir -p "$XG_RUN"
  _sc=$XG_FDIR/actions/autoupdate.sh
  # 用绝对路径的 shell：toybox setsid 遇到同名 applet 会跑自己的 toysh 而不是 /system/bin/sh（mksh）
  _sh=/system/bin/sh; [ -x "$_sh" ] || _sh=$(command -v sh)
  if command -v setsid >/dev/null 2>&1; then
    XG_FEATURE=$SHIELD XG_FDIR=$XG_FDIR setsid "$_sh" "$_sc" "${1:-boot}" </dev/null >>"$AD_DIR/auto.log" 2>&1 &
  else
    XG_FEATURE=$SHIELD XG_FDIR=$XG_FDIR nohup "$_sh" "$_sc" "${1:-boot}" </dev/null >>"$AD_DIR/auto.log" 2>&1 &
  fi
  return 0
}

# 列表文件增删（放行 / 自定义拦截）
list_add() { mkdir -p "$AD_DIR"; touch "$1"; grep -qxF "$2" "$1" || echo "$2" >>"$1"; }
list_del() { [ -f "$1" ] || return 0; _list_rc=0; grep -vxF "$2" "$1" >"$1.tmp" || _list_rc=$?; [ "$_list_rc" -le 1 ] || return "$_list_rc"; mv -f "$1.tmp" "$1"; }
list_json() { # <file> → ["a","b"]
  printf '['; _f=1
  [ -f "$1" ] && grep -vE '^[[:space:]]*(#|$)' "$1" | while read -r d; do [ $_f = 1 ] || printf ','; _f=0; printf '"%s"' "$(json_esc "$d")"; done
  printf ']'
}
# 记录可解释的域名活动。hosts 本身不会暴露 DNS 查询名，因此活动流记录防护引擎
# 控制面板发起的查询以及规则变更；不会伪装成系统级抓包结果。
activity_record() {
  _d=$(printf '%s' "${1:-}" | tr 'A-Z' 'a-z')
  _a=${2:-query}; _s=${3:-shield}
  valid_domain "$_d" || return 0
  case "$_a" in query|blocked|allowed|unblocked) ;; *) _a=query ;; esac
  case "$_s" in *[!A-Za-z0-9_.:-]*) _s=shield ;; esac
  mkdir -p "$AD_DIR"
  printf '%s\t%s\t%s\t%s\n' "$(date +%s)" "$_d" "$_a" "$_s" >>"$ACTIVITY"
  if [ -f "$ACTIVITY" ]; then
    tail -n "$ACTIVITY_MAX" "$ACTIVITY" >"$ACTIVITY.tmp" 2>/dev/null && mv -f "$ACTIVITY.tmp" "$ACTIVITY"
  fi
}
activity_json() {
  printf '{"items":['
  if [ -f "$ACTIVITY" ]; then
    tail -n "$ACTIVITY_MAX" "$ACTIVITY" | awk -F '\t' '
      BEGIN { first=1 }
      NF >= 4 && $2 ~ /^[A-Za-z0-9_][A-Za-z0-9_.-]*$/ {
        if (!first) printf ","; first=0;
        printf "{\"time\":%s,\"domain\":\"%s\",\"action\":\"%s\",\"source\":\"%s\"}", $1, $2, $3, $4
      }
    '
  fi
  printf '],"source":"shield-query-and-rules","live":true}\n'
}
activity_clear() { : >"$ACTIVITY"; }
# hosts 里是否拦截了某个域名（App 的「查询域名」）；sources = 哪些源包含它
hosts_query() {
  d=$(printf '%s' "$1" | tr 'A-Z' 'a-z')
  in_hosts=0; grep -qxF "0.0.0.0 $d" "$HOSTS_SRC" 2>/dev/null && in_hosts=1
  srcs=""; in_raw=0
  for _i in $(active_ids); do
    _f=$(src_list_file "$_i")
    grep -qxF "$d" "$_f" 2>/dev/null && { in_raw=1; srcs="$srcs${srcs:+,}\"$_i\""; }
  done
  allowed=0; [ -f "$ALLOW" ] && grep -qixF "$d" "$ALLOW" && allowed=1
  builtin_allow=0; builtin_allowed "$d" && builtin_allow=1
  if [ $allowed = 0 ] && [ -f "$ALLOW" ]; then
    x=$d; while :; do grep -qixF "*.$x" "$ALLOW" && { allowed=1; break; }; case "$x" in *.*) x=${x#*.} ;; *) break ;; esac; done
  fi
  custom=0; [ -f "$BLOCK" ] && grep -qixF "$d" "$BLOCK" && custom=1
  printf '{"domain":"%s","blocked":%s,"in_source":%s,"allowed":%s,"custom":%s,"builtin_allow":%s,"sources":[%s]}\n' "$(json_esc "$d")" $in_hosts $in_raw $allowed $custom $builtin_allow "$srcs"
}

hosts_rules() {
  _r=$(head -n1 "$HOSTS_SRC" 2>/dev/null | sed -n "s/^$MARK .*rules=\([0-9]*\).*/\1/p")
  [ -n "$_r" ] && { echo "$_r"; return; }
  [ -s "$HOSTS_SRC" ] && grep -c '^0\.0\.0\.0 ' "$HOSTS_SRC" || echo 0
}

# ---------- HTTPDNS IP 拦截（可选，guard=1）：iptables 拒绝已知 HTTPDNS 服务 IP 的 TCP 80/443 ----------
GUARD_CHAIN=XGUARD_HTTPDNS
# v0.2.26 改回默认关（v0.2.24 默认开导致支付宝/余额宝白屏、123云盘转圈等）：国内 App / 广告 SDK 大量用阿里、腾讯、百度的 HTTPDNS 纯 IP 接口解析，完全不经过 hosts；
# 拒掉这些 IP 后 SDK 按设计退回系统 DNS，才会命中 hosts（Re-Malwack / 「去广告模块」lingeringsound 同样用 iptables 补这一块）
guard_wanted() { [ "$(core_cfg_get $SHIELD guard 0)" = 1 ]; }
allowlisted_uids() {
  [ -s "$APP_ALLOW" ] || return 0
  while IFS= read -r allowed_pkg; do
    valid_pkg "$allowed_pkg" || continue
    for app_dir in /data/user/[0-9]*/"$allowed_pkg" /data/user_de/[0-9]*/"$allowed_pkg"; do
      stat -c %u "$app_dir" 2>/dev/null || :
    done
  done <"$APP_ALLOW" | awk '/^[0-9]+$/ && $1 % 100000 >= 10000' | sort -u
}
guard_signature() {
  { printf '%s\n' "$1"; cksum "$XG_FDIR/rules/httpdns.ip"; } | cksum | awk '{print $1}'
}
guard_on() (
  feat_enabled "$SHIELD" && ! shield_paused && ! proxy_running || return 0
  command -v iptables >/dev/null 2>&1 || return 1
  guard_uids=$(allowlisted_uids)
  iptables -w -N "$GUARD_CHAIN" 2>/dev/null || :
  iptables -w -F "$GUARD_CHAIN" || return 1
  for guard_uid in $guard_uids; do
    iptables -w -A "$GUARD_CHAIN" -m owner --uid-owner "$guard_uid" -j RETURN 2>/dev/null || return 1
  done
  grep -vE '^[[:space:]]*(#|$)' "$XG_FDIR/rules/httpdns.ip" | while read -r ip; do
    iptables -w -A $GUARD_CHAIN -d "$ip" -p tcp -m multiport --dports 80,443 -j REJECT --reject-with tcp-reset 2>/dev/null ||
      iptables -w -A $GUARD_CHAIN -d "$ip" -p tcp --dport 443 -j REJECT 2>/dev/null || exit 1
  done || return 1
  iptables -w -A "$GUARD_CHAIN" -m comment --comment "xguard-$(guard_signature "$guard_uids")" -j RETURN || return 1
  iptables -w -C OUTPUT -j $GUARD_CHAIN 2>/dev/null || iptables -w -I OUTPUT -j $GUARD_CHAIN
)
guard_off() {
  # 撤干净：IPv4 / IPv6 两张表都查（AdAway / Re-Malwack 撤规则同样不假设只有一处）；OUTPUT 里所有跳转到本链的规则删到删不动为止
  for _ipt in iptables ip6tables; do
    command -v $_ipt >/dev/null 2>&1 || continue
    _n=0; while $_ipt -w -D OUTPUT -j $GUARD_CHAIN 2>/dev/null && [ $_n -lt 20 ]; do _n=$((_n + 1)); done
    $_ipt -w -F $GUARD_CHAIN 2>/dev/null; $_ipt -w -X $GUARD_CHAIN 2>/dev/null
  done
  return 0
}
# 残留检查：任何表里还有本插件的链 / 跳转 → 输出描述（空 = 干净）
guard_residue() {
  for _ipt in iptables ip6tables; do
    command -v $_ipt >/dev/null 2>&1 || continue
    $_ipt -w -S 2>/dev/null | grep -q "$GUARD_CHAIN" && echo "$_ipt 仍有 $GUARD_CHAIN"
  done
}
guard_active() { iptables -w -C OUTPUT -j $GUARD_CHAIN 2>/dev/null; }

guard_sync() {
  if ! feat_enabled "$SHIELD" || shield_paused || proxy_running || ! guard_wanted; then
    guard_active && guard_off
    return 0
  fi
  guard_hash=$(guard_signature "$(allowlisted_uids)")
  if guard_active && iptables -w -C "$GUARD_CHAIN" -m comment --comment "xguard-$guard_hash" -j RETURN 2>/dev/null; then return 0; fi
  guard_on
}

# hosts：默认一直挂（proxy_yield=1 才在代理服务运行时撤）；HTTPDNS IP 拦截：代理服务运行时撤，避免和它的 iptables 打架
reconcile() {
  feat_enabled "$SHIELD" || return 0
  shield_paused && return 0
  if proxy_yield; then hosts_off; else hosts_on; fi
  ( splash_mutex && guard_sync )
  return 0
}

cache_skipped() { [ -f "$SKIP" ] && grep -Fxq "$1" "$SKIP"; }
app_allowlisted() { [ -f "$APP_ALLOW" ] && grep -Fxq "$1" "$APP_ALLOW"; }
skipped() { cache_skipped "$1" || app_allowlisted "$1"; }

# 规则合并：模块内置 + 用户自定义（$XG_DATA/shield/splash.rules）
splash_rules() { grep -hvE '^[[:space:]]*(#|$)' "$XG_FDIR/rules/splash.rules" "$USER_RULES" 2>/dev/null | awk 'NF>=2 {p=$1; sub(/^.*:/,"",p); k=p " " $2; if (!seen[k]++) print k}'; }

splash_mutex() {
  mkdir -p "$XG_RUN"
  _wait=0
  until mkdir "$XG_RUN/splash.lock" 2>/dev/null; do
    _owner=$(cat "$XG_RUN/splash.lock/pid" 2>/dev/null)
    case "$_owner" in ''|*[!0-9]*) ;; *)
      if ! kill -0 "$_owner" 2>/dev/null; then rm -f "$XG_RUN/splash.lock/pid"; rmdir "$XG_RUN/splash.lock" 2>/dev/null; continue; fi ;;
    esac
    _wait=$((_wait+1)); [ "$_wait" -lt 50 ] || { echo '开屏规则正在处理，请重试'; return 1; }
    sleep 0.1
  done
  echo $$ >"$XG_RUN/splash.lock/pid"
  trap 'rm -f "$XG_RUN/splash.lock/pid"; rmdir "$XG_RUN/splash.lock" 2>/dev/null' EXIT
}

# 规则路径校验：相对路径、不含 ..、不以 / 开头，可带 @sdcard: 前缀
valid_rel() {
  r=${1#@sdcard:}
  case "$r" in ""|/*|*..*|*" "*|.|./*|*/./*|*/.|*/) return 1 ;; esac
  case "$r" in *[!A-Za-z0-9_./-]*) return 1 ;; esac
  return 0
}
valid_pkg() { printf '%s' "$1" | grep -qE '^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z0-9_]+)+$'; }

# 用户规则增删（App 规则编辑器）
rule_add() (
  valid_pkg "$1" || { echo "包名无效：$1"; return 2; }
  valid_rel "$2" || { echo "目录无效：$2（需相对 data 目录，不能含 .. 或空格）"; return 2; }
  splash_mutex || return 1
  mkdir -p "$AD_DIR"; touch "$USER_RULES"
  awk -v p="$1" -v r="$2" '$1==p && $2==r {found=1} END {exit !found}' "$USER_RULES" || printf '%s\t%s\n' "$1" "$2" >>"$USER_RULES"
  if feat_enabled "$SHIELD" && ! skipped "$1"; then
    splash_target "$1" "$2"
    if splash_lock_one "$_sb" "$_st"; then
      printf '%s %s\n' "$1" "$2" >>"$AD_DIR/locked.list"
    fi
  fi
  log $SHIELD "新增开屏规则 $1 $2"; return 0
)
rule_remove() (
  valid_pkg "$1" && valid_rel "$2" || return 2
  splash_mutex || return 1
  [ -f "$USER_RULES" ] || return 0
  awk -v p="$1" -v r="$2" '!($1==p && $2==r)' "$USER_RULES" >"$USER_RULES.tmp" && mv -f "$USER_RULES.tmp" "$USER_RULES"
  # 只解锁这一条
  splash_rules | awk -v p="$1" -v r="$2" '$1==p && $2==r {found=1} END {exit !found}' && return 0
  splash_target "$1" "$2"; splash_unlock_one "$_st"
  [ -f "$AD_DIR/locked.list" ] && { awk -v p="$1" -v r="$2" '!($1==p && $2==r)' "$AD_DIR/locked.list" >"$AD_DIR/l.tmp"; mv -f "$AD_DIR/l.tmp" "$AD_DIR/locked.list"; }
  log $SHIELD "删除开屏规则 $1 $2"
)
rules_json() {
  printf '{"builtin":'; rules_file_json "$XG_FDIR/rules/splash.rules"
  printf ',"user":'; rules_file_json "$USER_RULES"; printf '}\n'
}
rules_file_json() {
  printf '['; _f=1
  [ -f "$1" ] && grep -vE '^[[:space:]]*(#|$)' "$1" | while read -r pkg rel; do
    [ -n "$rel" ] || continue
    [ $_f = 1 ] || printf ','; _f=0
    printf '{"pkg":"%s","path":"%s"}' "$(json_esc "${pkg#*:}")" "$(json_esc "$rel")"
  done
  printf ']'
}

# 开屏缓存目录发现：扫已安装 App 的 data / Android/data，找名字像开屏广告缓存的目录（只列候选，不自动锁）
# 输出 {"candidates":[{"pkg","path","kb"}]}，path 与规则格式一致（相对路径或 @sdcard:相对路径）
SPLASH_NAME_RE='(splash|launch_?ad|open_?screen_?ad|kaiping|ad_?cache|adcache|tt_?ad|ksad|gdt_?ad|pangle|mintegral|bdad|sigmob)'
splash_discover() {   # [包名]
  [ -z "${1:-}" ] || valid_pkg "$1" || { echo '包名无效'; return 2; }
  _depth=${2:-8}
  case "$_depth" in 6|8|12) ;; *) echo '扫描深度需为 6、8 或 12'; return 2 ;; esac
  _scanrules=$AD_DIR/discover.rules.$$
  splash_rules >"$_scanrules"
  printf '{"depth":%s,"limit_per_app":60,"candidates":[' "$_depth"; _f=1
  for base in /data/data /data/media/0/Android/data; do
    for d in "$base"/${1:-*}; do
      [ -d "$d" ] || continue
      pkg=${d##*/}
      skipped "$pkg" && continue
      find "$d" -mindepth 1 -maxdepth "$_depth" -type d 2>/dev/null | grep -iE "/[^/]*${SPLASH_NAME_RE}[^/]*\$" | head -n 60 |
      while read -r hit; do
        rel=${hit#"$d"/}
        [ "$base" = /data/media/0/Android/data ] && rel="@sdcard:$rel"
        valid_rel "$rel" || continue
        awk -v p="$pkg" -v r="$rel" '$1==p && $2==r {found=1} END {exit !found}' "$_scanrules" && continue
        kb=$(du -sk "$hit" 2>/dev/null | cut -f1)
        printf '%s\t%s\t%s\n' "$pkg" "$rel" "${kb:-0}"
      done
    done
  done | sort -u | while IFS="$(printf '\t')" read -r pkg rel kb; do
    [ $_f = 1 ] || printf ','; _f=0
    printf '{"pkg":"%s","path":"%s","kb":%s}' "$(json_esc "$pkg")" "$(json_esc "$rel")" "${kb:-0}"
  done
  printf ']}\n'
  rm -f "$_scanrules"
}

# ---------- 开屏缓存锁定 ----------
# v0.2.24 改用 chattr +i（参考 Adguard-Home-For-Magisk-Mod NoAdsService.sh 的 block_ad、lingeringsound「去广告模块」）：
#   目录 → 清空后保留空目录并设不可变（App 无法再写入素材，也删不掉它）；文件 → 清空后设不可变。
#   以前是「删目录 → 建同名 0400 空文件」：文件属主是 App 自己，SDK 发现不是目录直接 delete() 再 mkdirs() 就绕过了。
#   @sdcard: 路径改用真实路径 /data/media/0（/sdcard 是 FUSE，chattr 无效）。
#   目标的上级目录不存在就先不锁（以前会以 root 身份 mkdir -p，造出 App 自己写不了的 root 目录）。
splash_target() {   # <pkg> <rel> → 设置 _sb（App 目录）_st（目标）
  case "$2" in
    @sdcard:*) _sb=/data/media/0/Android/data/$1; _st=$_sb/${2#@sdcard:} ;;
    *) _sb=/data/data/$1; _st=$_sb/$2 ;;
  esac
}
shield_chattr() { chattr "$@" 2>/dev/null || bb chattr "$@" 2>/dev/null; }
shield_immutable() {
  _la=$(lsattr -d "$1" 2>/dev/null || bb lsattr -d "$1" 2>/dev/null) || return 1
  case "${_la%% *}" in *i*) return 0 ;; esac; return 1
}
splash_is_locked() { [ -e "$1" ] && shield_immutable "$1"; }
splash_is_weak() { [ -f "$1" ] && [ ! -s "$1" ] && [ "$(stat -c %a "$1" 2>/dev/null)" = 400 ]; }
splash_lock_one() {   # <app 目录> <目标>；0 = 已锁，1 = 暂不能锁（未安装 / 上级目录还没建）
  _b=$1; _t=$2; _par=${_t%/*}
  [ -d "$_b" ] || return 1
  _realbase=$(readlink -f "$_b")
  _walk=$_b; _rest=${_par#"$_b"}
  while [ -n "$_rest" ]; do
    _rest=${_rest#/}; _part=${_rest%%/*}; _walk=$_walk/$_part
    case "$_rest" in */*) _rest=${_rest#*/} ;; *) _rest= ;; esac
    [ ! -L "$_walk" ] || return 1
    if [ ! -d "$_walk" ]; then
      _parent=${_walk%/*}
      mkdir "$_walk" 2>/dev/null || return 1
      chown "$(stat -c %u:%g "$_parent")" "$_walk" 2>/dev/null
      chmod "$(stat -c %a "$_parent")" "$_walk" 2>/dev/null
      _pc=$(ls -Zd "$_parent" | awk '{print $1}'); chcon "$_pc" "$_walk" 2>/dev/null
    fi
  done
  [ ! -L "$_t" ] || return 1
  case "$(readlink -f "$_par")/" in "$_realbase"/*) ;; *) return 1 ;; esac
  shield_immutable "$_t" && return 0
  splash_is_weak "$_t" && return 0
  _own=$(stat -c %u:%g "$_par" 2>/dev/null); _ctx=$(ls -Zd "$_par" 2>/dev/null | awk '{print $1}')
  if [ -d "$_t" ]; then rm -rf "$_t"/* "$_t"/.[!.]* 2>/dev/null
  elif [ -f "$_t" ]; then : >"$_t"
  else mkdir "$_t" 2>/dev/null || return 1; fi
  [ -n "$_own" ] && chown "$_own" "$_t" 2>/dev/null
  case "$_ctx" in u:*) chcon "$_ctx" "$_t" 2>/dev/null ;; esac
  shield_chattr +i "$_t" && return 0
  # 文件系统不支持 chattr：退回旧做法（空文件占位，弱）
  if [ ! -f "$_t" ]; then rm -rf "$_t"; : >"$_t"; [ -n "$_own" ] && chown "$_own" "$_t" 2>/dev/null; fi
  chmod 0400 "$_t"
  [ -f "$AD_DIR/chattr.warn" ] || { touch "$AD_DIR/chattr.warn"; log $SHIELD "chattr +i 不可用，开屏锁定退回空文件占位（App 可能自行删除）"; }
  return 0
}
splash_unlock_one() {   # <目标>
  [ -e "$1" ] || return 0
  if shield_immutable "$1"; then shield_chattr -i "$1" || return 1; fi
  if [ -f "$1" ] && [ ! -s "$1" ]; then rm -f "$1" || return 1; fi
  return 0
}

splash_apply() (
  feat_enabled "$SHIELD" || return 0
  shield_paused && return 0
  splash_mutex || return 1
  splash_apply_locked "$@"
  splash_network_sync
)
splash_apply_locked() (
  feat_enabled "$SHIELD" && ! shield_paused || return 0
  _ll=$AD_DIR/locked.list.$$; : >"$_ll"
  splash_rules |
  while read -r pkg rel; do
    pkg=${pkg#*:}
    [ -z "${1:-}" ] || [ "$pkg" = "$1" ] || continue
    [ -n "$rel" ] || continue
    valid_pkg "$pkg" && valid_rel "$rel" || continue
    skipped "$pkg" && continue          # 用户在 App 里单独解锁过
    splash_target "$pkg" "$rel"
    splash_lock_one "$_sb" "$_st" && echo "$pkg $rel" >>"$_ll"
  done
  if [ -n "${1:-}" ]; then
    awk -v p="$1" '$1!=p' "$AD_DIR/locked.list" 2>/dev/null >>"$_ll"
  fi
  sort -u "$_ll" >"$_ll.sorted"; mv -f "$_ll.sorted" "$AD_DIR/locked.list"; rm -f "$_ll"
)
splash_network_off() {
  for _ipt in iptables ip6tables; do
    command -v "$_ipt" >/dev/null 2>&1 || continue
    while "$_ipt" -w -D OUTPUT -j XGUARD_SPLASH 2>/dev/null; do :; done
    "$_ipt" -w -F XGUARD_SPLASH 2>/dev/null
    "$_ipt" -w -F XGUARD_SPLASH_HOST 2>/dev/null
    "$_ipt" -w -X XGUARD_SPLASH_HOST 2>/dev/null
    "$_ipt" -w -X XGUARD_SPLASH 2>/dev/null
  done
  return 0
}
splash_network_sync() {
  _uids=""
  if feat_enabled "$SHIELD" && ! shield_paused; then
    exempt_uids=$(allowlisted_uids | tr '\n' ' ')
    for _pkg in com.chaoxing.mobile com.chinamobile.mcloud com.xunlei.downloadprovider; do
      skipped "$_pkg" && continue
      _uid=$(stat -c %u /data/user/0/$_pkg 2>/dev/null)
      case "$_uid" in ''|*[!0-9]*) continue ;; esac
      [ "$_uid" -ge 10000 ] || continue
      case " $exempt_uids " in *" $_uid "*) continue ;; esac
      case " $_uids " in *" $_uid "*) ;; *) _uids="$_uids $_uid" ;; esac
    done
  fi
  for _ipt in iptables ip6tables; do
    command -v "$_ipt" >/dev/null 2>&1 || continue
    if [ -z "$_uids" ]; then
      while "$_ipt" -w -D OUTPUT -j XGUARD_SPLASH 2>/dev/null; do :; done
      "$_ipt" -w -F XGUARD_SPLASH 2>/dev/null
      "$_ipt" -w -F XGUARD_SPLASH_HOST 2>/dev/null
      "$_ipt" -w -X XGUARD_SPLASH_HOST 2>/dev/null
      "$_ipt" -w -X XGUARD_SPLASH 2>/dev/null
      continue
    fi
    _signature=$(printf '%s\n%s\n%s' "$_uids" "$(cksum "$XG_FDIR/rules/splash-domains.list")" "$(cksum "$ALLOW" 2>/dev/null)" | cksum | awk '{print $1}')
    if "$_ipt" -w -C XGUARD_SPLASH_HOST -m comment --comment "xguard-$_signature" -j RETURN 2>/dev/null && "$_ipt" -w -C OUTPUT -j XGUARD_SPLASH 2>/dev/null; then continue; fi
    "$_ipt" -w -N XGUARD_SPLASH 2>/dev/null
    "$_ipt" -w -F XGUARD_SPLASH 2>/dev/null || continue
    "$_ipt" -w -N XGUARD_SPLASH_HOST 2>/dev/null
    "$_ipt" -w -F XGUARD_SPLASH_HOST 2>/dev/null || continue
    _ok=1
    for _uid in $_uids; do
      "$_ipt" -w -A XGUARD_SPLASH -p tcp -m owner --uid-owner "$_uid" -j XGUARD_SPLASH_HOST 2>/dev/null || _ok=0
    done
    grep -vE '^[[:space:]]*(#|$)' "$XG_FDIR/rules/splash-domains.list" | while read -r _host; do
      _allowed=0; _suffix=$_host
      [ -f "$ALLOW" ] && grep -Fixq "$_host" "$ALLOW" && _allowed=1
      while [ "$_allowed" = 0 ] && [ -f "$ALLOW" ]; do
        grep -Fixq "*.$_suffix" "$ALLOW" && { _allowed=1; break; }
        case "$_suffix" in *.*) _suffix=${_suffix#*.} ;; *) break ;; esac
      done
      [ "$_allowed" = 0 ] || continue
      valid_domain "$_host" || exit 1
      "$_ipt" -w -A XGUARD_SPLASH_HOST -p tcp -m string --algo kmp --string "$_host" -j REJECT --reject-with tcp-reset 2>/dev/null || exit 1
    done || _ok=0
    if [ "$_ok" = 1 ]; then
      "$_ipt" -w -A XGUARD_SPLASH_HOST -m comment --comment "xguard-$_signature" -j RETURN
      "$_ipt" -w -C OUTPUT -j XGUARD_SPLASH 2>/dev/null || "$_ipt" -w -I OUTPUT 1 -j XGUARD_SPLASH
    else
      "$_ipt" -w -F XGUARD_SPLASH 2>/dev/null
      "$_ipt" -w -F XGUARD_SPLASH_HOST 2>/dev/null
      log "$SHIELD" "$_ipt 不支持广告主机补防，仍使用 hosts 与缓存锁定"
    fi
  done
  return 0
}
splash_unlock_targets() (
  [ -f "$AD_DIR/locked.list" ] || return 0
  unlock_failed=0
  : >"$AD_DIR/l.tmp" || return 1
  while read -r pkg rel; do
    if [ -n "${1:-}" ] && [ "$pkg" != "$1" ]; then
      printf '%s %s\n' "$pkg" "$rel" >>"$AD_DIR/l.tmp"
      continue
    fi
    splash_target "$pkg" "$rel"
    if ! splash_unlock_one "$_st"; then
      printf '%s %s\n' "$pkg" "$rel" >>"$AD_DIR/l.tmp"
      unlock_failed=1
    fi
  done <"$AD_DIR/locked.list"
  mv -f "$AD_DIR/l.tmp" "$AD_DIR/locked.list" && [ "$unlock_failed" = 0 ]
)
splash_unlock() ( splash_mutex || return 1; splash_unlock_targets "${1:-}"; )

# 单个 App 解锁并记住（之后的 config/开机事件不再锁它）；relock 撤销
splash_skip() ( valid_pkg "$1" || return 2; splash_mutex || return 1; mkdir -p "$AD_DIR"; splash_unlock_targets "$1" || return 1; cache_skipped "$1" || echo "$1" >>"$SKIP"; splash_network_sync; log $SHIELD "已单独解锁 $1"; )
splash_relock() { valid_pkg "$1" || return 2; ( splash_mutex || exit 1; [ -f "$SKIP" ] && { grep -Fvx "$1" "$SKIP" >"$SKIP.tmp"; mv -f "$SKIP.tmp" "$SKIP"; }; exit 0; ) || return 1; splash_apply "$1"; log $SHIELD "已恢复锁定 $1"; }

# 非注释行数；文件不存在 = 0（grep -c 无匹配时退出码 1，旧写法会输出 "0\n0"）
cnt_lines() { _n=0; [ -f "$1" ] && _n=$(grep -cvE '^[[:space:]]*(#|$)' "$1" 2>/dev/null); printf '%s' "${_n:-0}"; }

json_esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

# 规则命中情况（JSON）：每条规则 = 包名 + 目录 + 状态
# state: locked 已锁 / skipped 用户解锁 / allowlisted 应用白名单 / pending 待锁 / absent 未安装
splash_states() {
  splash_rules | while read -r pkg rel; do
    pkg=${pkg#*:}
    [ -z "${1:-}" ] || [ "$pkg" = "$1" ] || continue
    splash_target "$pkg" "$rel"
    if app_allowlisted "$pkg"; then st=allowlisted
    elif cache_skipped "$pkg"; then st=skipped
    elif [ ! -d "$_sb" ] && [ ! -d "/data/data/$pkg" ]; then st=absent
    elif splash_is_locked "$_st"; then st=locked
    elif splash_is_weak "$_st"; then st=weak
    else st=pending; fi
    printf '%s\t%s\t%s\n' "$pkg" "$rel" "$st"
  done
}
splash_locked_count() { splash_states | awk '$3=="locked" {apps[$1]=1} END {for (p in apps) n++; print n+0}'; }
splash_hits_json() {
  printf '{"rules":['
  first=1
  splash_states "${1:-}" | while read -r pkg rel st; do
    [ $first = 1 ] || printf ','; first=0
    printf '{"pkg":"%s","path":"%s","state":"%s"}' "$(json_esc "$pkg")" "$(json_esc "$rel")" "$st"
  done
  printf ']}\n'
}

# ---------- 状态 ----------
shield_mode() { if proxy_yield; then echo proxy; elif hosts_mounted; then echo hosts; else echo off; fi; }

# 规则源明细（JSON 数组）：内置目录 + 自定义
sources_json() {
  printf '['; _f=1
  _en=" $(src_enabled_ids) "
  cat_lines | while IFS='|' read -r id def name desc urls min; do
    [ $_f = 1 ] || printf ','; _f=0
    en=false; case "$_en" in *" $id "*) en=true ;; esac
    err=""
    case "$urls" in
      builtin:*) bi=true; res=builtin; lok=0; cnt=$(src_count "$id") ;;
      *) bi=false; res=$(prop_get "$SRC_DIR/$id.meta" result none); lok=$(prop_get "$SRC_DIR/$id.meta" last_ok 0)
         cnt=0; [ -s "$SRC_DIR/$id.list" ] && cnt=$(wc -l <"$SRC_DIR/$id.list" | tr -d ' ')
         [ -s "$SRC_DIR/$id.err" ] && err=$(tail -n 1 "$SRC_DIR/$id.err" | head -c 240 | tr '\t"\\' '   ') ;;
    esac
    printf '{"id":"%s","name":"%s","desc":"%s","default":%s,"enabled":%s,"builtin":%s,"count":%s,"result":"%s","last_ok":%s,"url":"%s","mirrors":%s,"err":"%s"}' \
      "$id" "$(json_esc "$name")" "$(json_esc "$desc")" "$([ "$def" = 1 ] && echo true || echo false)" "$en" "$bi" \
      "${cnt:-0}" "$res" "${lok:-0}" "$(json_esc "${urls%% *}")" "$(echo $urls | wc -w | tr -d ' ')" "$(json_esc "$err")"
  done
  for u in $(custom_urls); do
    id=$(custom_id "$u")
    # 目录非空（模块自带），所以自定义项前面总有逗号
    err=""; [ -s "$SRC_DIR/$id.err" ] && err=$(tail -n 1 "$SRC_DIR/$id.err" | head -c 240 | tr '\t"\\' '   ')
    printf ',{"id":"%s","name":"%s","desc":"自定义源","default":false,"enabled":true,"builtin":false,"custom":true,"count":%s,"result":"%s","last_ok":%s,"url":"%s","mirrors":1,"err":"%s"}' \
      "$id" "$(json_esc "${u#*://}")" \
      "$(src_count "$id")" "$(prop_get "$SRC_DIR/$id.meta" result none)" "$(prop_get "$SRC_DIR/$id.meta" last_ok 0)" "$(json_esc "$u")" "$(json_esc "$err")"
  done
  printf ']'
}

# 拦截统计（JSON）：App / WebUI 的防护引擎页一次读全。旧字段全部保留（mode / hosts_rules / last_try / last_ok / result /
# interval_h / splash_* / url / sources(数量) / sources_ok / user_rules / allow_count / block_count）
stats_json() {
  mode=$(shield_mode)
  locked_cached=false; locked_checked=0
  if [ "${1:-}" = quick ]; then
    locked=$(core_json_get "$AD_DIR/status.json" splash_locked_apps)
    case "$locked" in ''|*[!0-9]*) locked=null ;; esac
    locked_checked=$(core_json_get "$AD_DIR/status.json" updated_at)
    case "$locked_checked" in ''|*[!0-9]*) locked_checked=0 ;; esac
    locked_cached=true
  else
    locked=$(splash_locked_count)
  fi
  skip=$(cnt_lines "$SKIP")
  user_rules=$(cnt_lines "$USER_RULES"); allow_n=$(cnt_lines "$ALLOW"); block_n=$(cnt_lines "$BLOCK")
  ids=$(active_ids); srcs=$(echo $ids | wc -w)
  urls=""
  if [ "${1:-}" != quick ]; then
    for _i in $ids; do case "$_i" in custom_*) ;; *) is_builtin "$_i" || urls="$urls $(cat_field "$_i" 5 | cut -d' ' -f1)" ;; esac; done
    urls="${urls# }$(custom_urls | tr '\n' ' ' | sed 's/^/ /; s/ *$//')"
  fi
  tv=$(sed -n 's/.*"verdict":"\([^"]*\)".*/\1/p' "$TEST_JSON" 2>/dev/null)
  tt=$(sed -n 's/.*"time":\([0-9]*\).*/\1/p' "$TEST_JSON" 2>/dev/null)
  upd=false; [ -d "$XG_RUN/shield-update.lock" ] && upd=true
  printf '{"mode":"%s","hosts_rules":%s,"last_try":%s,"last_ok":%s,"result":"%s","interval_h":%s,"splash_locked_apps":%s,"splash_skipped_apps":%s,"url":"%s","sources":%s,"sources_ok":%s,"user_rules":%s,"allow_count":%s,"block_count":%s' \
    "$mode" "$(hosts_rules)" "$(prop_get "$META" last_try 0)" "$(prop_get "$META" last_ok 0)" "$(prop_get "$META" result none)" \
    "$(core_cfg_get $SHIELD hosts_interval_h 24)" "$locked" "$skip" "$(json_esc "$urls")" "$srcs" "$(prop_get "$META" sources_ok 0)" \
    "$user_rules" "$allow_n" "$block_n"
  printf ',"method":"%s","mount_mode":"%s","root":"%s","target":"%s","hosts_max":%s,"capped":%s,"allowed_hits":%s,"sources_want":%s,"updating":%s,"guard":%s,"guard_active":%s,"hide":%s,"test_verdict":"%s","test_time":%s,"splash_rules":%s,"proxy_running":%s,"proxy_yield":%s,' \
    "$(shield_method)" "$(core_cfg_get $SHIELD mount_mode auto)" "$(shield_root)" "$(json_esc "$(shield_target)")" "$(core_cfg_get $SHIELD hosts_max 200000)" \
    "$(prop_get "$META" capped 0)" "$(prop_get "$META" allowed_hits 0)" "$(prop_get "$META" sources_want 0)" "$upd" \
    "$(core_cfg_get $SHIELD guard 0)" "$(guard_active && echo 1 || echo 0)" "$(core_cfg_get $SHIELD hide 0)" "${tv:-none}" "${tt:-0}" \
    "$(splash_rules | grep -c .)" "$(proxy_running && echo true || echo false)" "$(core_cfg_get $SHIELD proxy_yield 0)"
  # v0.2.22：目录条数（0 = 模块文件缺失 / 读不出来）、内置放行条数、后台自动更新进度
  _as=$(prop_get "$AUTO_STATE" state ""); auto_running || case "$_as" in waiting_net|running|retry) _as=stopped ;; esac
  printf '"catalog":%s,"builtin_allow":%s,"auto_state":"%s","auto_next":%s,"auto_try":%s,"source_list":' \
    "$(cat_ids | grep -c .)" "$(cnt_lines "$BUILTIN_ALLOW")" "$_as" "$(prop_get "$AUTO_STATE" next 0)" "$(prop_get "$AUTO_STATE" try 0)"
  if [ "${1:-}" = quick ]; then printf '[]'; else sources_json; fi
  printf ',"locked_count_cached":%s,"locked_checked_at":%s' "$locked_cached" "$locked_checked"
  printf ',"mount_fallback":"%s","mount_err_head":"%s"' "$(mount_fallback)" "$(json_esc "$(mount_error_head)")"
  printf '}\n'
}

# 一行摘要（status.sh / xguard status 用）
shield_summary() {
  if shield_paused; then echo "临时暂停中，预计 $(pause_until) 恢复"; return; fi
  n=$(splash_locked_count); r=$(hosts_rules)
  sr=$(splash_rules | grep -c .)
  if [ "${sr:-0}" -eq 0 ]; then sp=""; else sp=" · 锁定 $n 个开屏"; fi
  ns=$(active_ids | grep -c .)
  case "$(sed -n 's/.*"verdict":"\([^"]*\)".*/\1/p' "$TEST_JSON" 2>/dev/null)" in
    app_unmounted) tw=" · 部分 App 被卸载模块" ;; resolve_leak) tw=" · 自检：测试域名未拦截" ;; *) tw="" ;;
  esac
  hw=""; proxy_running && hw=" · 代理服务运行中"
  if proxy_yield; then echo "代理服务接管（防护引擎不拦截网络）$sp"
  elif hosts_mounted; then echo "拦截中 · $r 条 · $ns 个源$hw$tw$sp"
  elif [ -s "$HOSTS_SRC" ]; then echo "未生效（hosts 未挂载，见日志）$sp"
  else echo "未生效（规则还没下载）$sp"; fi
}
# 契约状态文件 $XG_DATA/shield/status.json（App / WebUI 只读）
shield_write_status() {
  mode=$(shield_mode)
  locked=$(splash_locked_count)
  core_status_write $SHIELD summary="${1:-$(shield_summary)}" mode="$mode" method="$(shield_method)" hosts_rules="$(hosts_rules)" \
    mount_fallback="$(mount_fallback)" mount_err_head="$(mount_error_head)" \
    last_ok="$(prop_get "$META" last_ok 0)" result="$(prop_get "$META" result none)" sources="$(active_ids | grep -c .)" \
    splash_locked_apps="$locked" splash_skipped_apps="$(cnt_lines "$SKIP")" \
    allow_count="$(cnt_lines "$ALLOW")" block_count="$(cnt_lines "$BLOCK")" user_rules="$(cnt_lines "$USER_RULES")"
}

# 新版目录里新增的「默认开」源：用户以前存过自己的源列表（config sources）时自动并进去（只并一次，记在 sources_known）
shield_sources_merge() {
  _known=$(core_cfg_get $SHIELD sources_known "")
  # 第一次跑（v0.2.22 之前没有这个键）：以前目录里就有的源算「已知」，只并入真正新增的默认源（baseline / goodbyeads）
  [ -n "$_known" ] || _known="httpdns awavenue adaway adguard_mobile antiad doh stevenblack hagezi_light hagezi_pro"
  _cur=$(core_cfg_get $SHIELD sources "")
  _def=$(cat_default_ids)
  if [ -n "$_cur" ]; then
    _add=""; for _d in $_def; do case " $_known " in *" $_d "*) ;; *) case " $_cur " in *" $_d "*) ;; *) _add="$_add $_d" ;; esac ;; esac; done
    if [ -n "$_add" ]; then
      _o=""; for _i in $(cat_ids); do case " $_cur $_add " in *" $_i "*) _o="$_o $_i" ;; esac; done
      core_cfg_set $SHIELD sources "${_o# }"; log $SHIELD "新版默认规则源已启用：${_add# }"
    fi
  fi
  _all=$(cat_ids | tr '\n' ' '); [ "$_known" = "${_all% }" ] || core_cfg_set $SHIELD sources_known "${_all% }"
}

# v0.2.27 一次性迁移（标记 migrate_v27）：
#   · HTTPDNS IP 拦截（iptables）恢复为关：v0.2.24 默认开、App 里点过的会把 guard=1 写进配置，升级后仍在拒绝阿里 / 腾讯 HTTPDNS IP，
#     支付宝 / 余额宝白屏、123 云盘转圈的直接原因。要用请重新手动打开。
#   · 内置「HTTPDNS 域名」源改为默认关并从已保存的源列表里摘掉：dns.jd.com 等是京东 / 阿里系 App 的 HTTPDNS，
#     AdAway / 秋风都不拦这一类；拦掉后部分 App 不回退系统 DNS 而是一直重试（京粉转圈）。
shield_migrate_v27() {
  [ "$(core_cfg_get $SHIELD migrate_v27 0)" = 1 ] && return 0
  [ "$(core_cfg_get $SHIELD guard 0)" = 1 ] && log $SHIELD "迁移：HTTPDNS IP 拦截已恢复为关（曾导致支付宝白屏 / 云盘转圈，需要可手动重开）"
  core_cfg_set $SHIELD guard 0; guard_off
  _cur=$(core_cfg_get $SHIELD sources "")
  if [ -n "$_cur" ]; then
    _new=$(echo " $_cur " | sed 's/ httpdns / /g; s/^ *//; s/ *$//')
    [ "$_new" != "$_cur" ] && { core_cfg_set $SHIELD sources "$_new"; log $SHIELD "迁移：内置 HTTPDNS 域名源已关闭"; }
  fi
  core_cfg_set $SHIELD migrate_v27 1
}

# 老版本迁移：没有标记的 hosts / 只有 hosts.raw → 把旧规则当 awavenue 缓存，先能用，再联网更新
shield_migrate() {
  shield_sources_merge
  shield_migrate_v27
  head -n1 "$HOSTS_SRC" 2>/dev/null | grep -q "^$MARK" && return 0
  if [ ! -s "$SRC_DIR/awavenue.list" ]; then
    for f in "$AD_DIR/hosts.raw" "$HOSTS_SRC"; do
      [ -s "$f" ] && { normalize <"$f" | sort -u >"$SRC_DIR/awavenue.list"; break; }
    done
  fi
  hosts_build && log $SHIELD "已迁移旧版 hosts（$(hosts_rules) 条），稍后联网更新全部规则源"
  meta_set last_ok 0; meta_set last_try 0
}
