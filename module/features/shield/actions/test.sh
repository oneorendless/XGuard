#!/system/bin/sh
# xguard run shield test [-v] [域名]   验证去广告是否真的生效（JSON，约 2~5 秒；结果同时存 test.json 给状态页）
#   -v 额外输出一段人能看的中文报告（终端用：su -c 'xguard run shield test -v'）；App 解析时不要带 -v
# v0.2.24 重写（对照 bindhosts / Re-Malwack 的「是否生效」判断）：
#   1. 插件本身：是否启用 / 冲突 / 被调度暂停
#   2. 规则：生成的 hosts 有多少条、各规则源下载结果（失败原因）
#   3. 挂载：netd（系统 DNS 实际读 hosts 的进程）和 zygote（之后启动的 App）各自命名空间里的 /system/etc/hosts
#      是不是我们的（首行标记 + 条数 + 与源文件 inode 比对 + mountinfo 里有没有挂载项）
#   4. 解析：getent / ping 一个确定在规则里的广告域名，0.0.0.0 才算真的拦住
#   5. 绕过：私人 DNS 状态（不绕过 hosts；但主机名被规则拦了会断网）、HTTPDNS IP 拦截、代理服务、其他 hosts 模块
#   verdict：ok / off / proxy / no_rules / not_mounted / resolve_leak / app_unmounted
#   warnings：不影响 verdict 但会让人觉得「没用」的情况（中文，一条一句）
. "$XG_FDIR/lib.sh"
human=0; [ "${1:-}" = -v ] && { human=1; shift; }
d=${1:-}
W=""; warn() { W="$W${W:+,}\"$(json_esc "$1")\""; WL="${WL:-}  ! $1
"; }

# ---------- 1. 插件状态 ----------
feat=on
[ -f "$XG_STATE/conflict.$SHIELD" ] && feat="conflict:$(head -n1 "$XG_STATE/conflict.$SHIELD")"
[ -f "$XG_STATE/paused.$SHIELD" ] && feat="paused:$(head -n1 "$XG_STATE/paused.$SHIELD")"
[ -f "$XG_STATE/brick.$SHIELD" ] && feat="brick:$(head -n1 "$XG_STATE/brick.$SHIELD")"
[ -f "$XG_STATE/safe_mode" ] && feat="safe_mode"
[ "$feat" = on ] && ! feat_enabled "$SHIELD" && feat=disabled

# ---------- 2. 规则 ----------
file_rules=$(hosts_rules); src_mark=false; head -n1 "$HOSTS_SRC" 2>/dev/null | grep -q "^$MARK" && src_mark=true
s_ok=$(prop_get "$META" sources_ok 0); s_want=$(prop_get "$META" sources_want 0); last_ok=$(prop_get "$META" last_ok 0)
fails=""
for _i in $(active_ids); do
  is_builtin "$_i" && continue
  case "$(prop_get "$SRC_DIR/$_i.meta" result none)" in
    ok|same) ;;
    none) fails="$fails $_i(未下载)" ;;
    *) fails="$fails $_i($(head -c 240 "$SRC_DIR/$_i.err" 2>/dev/null | tr '\n"' '  '))" ;;
  esac
done

# ---------- 3. 挂载 ----------
me=$(shield_method); zp=$(shield_ns_pid); np=$(shield_netd_pid)
src_ino=$(stat -Lc '%d:%i' "$HOSTS_SRC" 2>/dev/null)
netd_rules=0; netd_mark=false; netd_ino=""; netd_mnt=0; zy_rules=0; zy_mark=false
case "$me" in
  zn|hfr) g=0; head -n1 "$(shield_target)" 2>/dev/null | grep -q "^$MARK" && g=$(grep -c '^0\.0\.0\.0 ' "$(shield_target)")
          netd_rules=$g; zy_rules=$g; [ "$g" -gt 0 ] && { netd_mark=true; zy_mark=true; } ;;
  *)
    if [ -n "$np" ]; then
      netd_rules=$(shield_view_rules "$np"); shield_view "$np" && netd_mark=true
      netd_ino=$(stat -Lc '%d:%i' "/proc/$np/root/system/etc/hosts" 2>/dev/null)
      netd_mnt=$(grep -cE ' /system/etc(/hosts)? ' "/proc/$np/mountinfo" 2>/dev/null)
    fi
    zy_rules=$(shield_view_rules "$zp"); shield_view "$zp" && zy_mark=true
    g=$zy_rules ;;
esac
ino_match=false; [ -n "$src_ino" ] && [ "$src_ino" = "$netd_ino" ] && ino_match=true
hctx=$(ls -Z "$HOSTS_SRC" 2>/dev/null | awk '{print $1}')

# 抽样 3 个正在运行的普通 App（u0_a*，排除防护引擎自身）：读各自命名空间里的 hosts（Chrome 等自带解析器的 App 用它）
apps=""; bad=0
if [ "$me" = bind ] || [ "$me" = overlay ]; then
  for pid in $(ps -A -o PID,USER,NAME 2>/dev/null | awk '$2 ~ /^u[0-9]+_a[0-9]+$/ && $3 !~ /xguard/ && $3 !~ /:/ {print $1}' | head -n 3); do
    name=$(core_proc_args "$pid" | cut -d' ' -f1)
    n=$(shield_view_rules "$pid")
    [ "${n:-0}" -gt 0 ] || bad=$((bad+1))
    apps="$apps${apps:+,}{\"pkg\":\"$(json_esc "$name")\",\"rules\":${n:-0}}"
  done
fi

# ---------- 4. 解析 ----------
if [ -z "$d" ]; then
  for c in pangolin.snssdk.com api-access.pangolin-sdk-toutiao.com mi.gdt.qq.com adashx.m.taobao.com ad.doubleclick.net pagead2.googlesyndication.com; do
    grep -qxF "0.0.0.0 $c" "$HOSTS_SRC" 2>/dev/null && { d=$c; break; }
  done
  [ -n "$d" ] || d=$(awk '$1=="0.0.0.0" {print $2; exit}' "$HOSTS_SRC" 2>/dev/null)
fi
valid_domain "${d:-x}" || d=""
ip=""; tool=""
if [ -n "$d" ]; then
  # getaddrinfo 走 netd（dnsproxyd），和普通 App 的系统解析是同一条路
  if command -v getent >/dev/null 2>&1; then ip=$(bb timeout 4 getent hosts "$d" 2>/dev/null | awk '{print $1; exit}'); tool=getent; fi
  if [ -z "$ip" ]; then
    ip=$(bb timeout 4 ping -c 1 -W 1 "$d" 2>&1 | sed -n 's/^PING [^(]*(\([^)]*\)).*/\1/p' | head -n1); tool=ping
  fi
fi
blocked_ip() { case "$1" in 0.0.0.0|127.0.0.1|::|::1|0:0:0:0:0:0:0:0) return 0 ;; esac; return 1; }

# ---------- 5. 绕过 / 冲突 ----------
pdns=$(settings get global private_dns_mode 2>/dev/null); case "$pdns" in ''|null) pdns="opportunistic(默认)" ;; esac
pspec=$(settings get global private_dns_specifier 2>/dev/null); case "$pspec" in null) pspec="" ;; esac
pblk=false
case "$pdns" in hostname) [ -n "$pspec" ] && grep -qxF "0.0.0.0 $(printf '%s' "$pspec" | tr 'A-Z' 'a-z')" "$HOSTS_SRC" 2>/dev/null && pblk=true ;; esac
hr=false; proxy_running && hr=true
hy=false; proxy_yield && hy=true
others=""
for m in /data/adb/modules/*; do
  [ -f "$m/system/etc/hosts" ] || continue
  [ -f "$m/disable" ] || [ -f "$m/remove" ] && continue
  others="$others ${m##*/}"
done
locked=$(splash_locked_count)
srules=$(splash_rules | grep -c .)
ga=false; guard_active && ga=true

# ---------- 结论 ----------
case "$feat" in
  on) ;;
  *) v=off ;;
esac
if [ -n "${v:-}" ]; then :
elif [ "$hy" = true ]; then v=proxy
elif [ "$src_mark" != true ] || [ "${file_rules:-0}" -eq 0 ]; then v=no_rules
elif [ "$netd_mark" != true ] || [ "$zy_mark" != true ]; then v=not_mounted
elif [ -n "$ip" ] && ! blocked_ip "$ip"; then v=resolve_leak
elif [ $bad -gt 0 ]; then v=app_unmounted
else v=ok; fi

case "$feat" in disabled) warn "防护引擎开关是关的" ;; conflict:*) warn "与模块 ${feat#conflict:} 冲突，防护引擎没有启动；停用那个模块后重开防护引擎" ;;
  paused:*|brick:*) warn "防护引擎被调度暂停：${feat#*:}；在 WebUI 里重新打开防护引擎" ;; safe_mode) warn "防护引擎处于安全模式，插件没有运行" ;; esac
[ -n "$fails" ] && warn "规则源失败：${fails# }"
[ "$(cat_ids | grep -c .)" -eq 0 ] && warn "规则源目录读不出来（$CATALOG）：模块文件缺失或 grep 不可用，重新刷入模块"
[ "$v" = no_rules ] && [ -z "$fails" ] && warn "还没有生成 hosts：执行 xguard run shield update"
case "$(prop_get "$AUTO_STATE" state "")" in
  waiting_net) auto_running && warn "后台自动更新在等网络" ;;
  retry|running) auto_running && warn "后台自动更新进行中（第 $(prop_get "$AUTO_STATE" try 0) 次）" ;;
  gave_up) warn "后台自动更新多次失败，可能是网络无法访问规则镜像；可在 App 里点「立即更新」重试" ;;
esac
[ "$me" != zn ] && [ "$me" != hfr ] && [ -n "$np" ] && [ "$netd_mark" != true ] && [ "$zy_mark" = true ] &&
  warn "zygote 里挂上了但 netd 里没有：系统 DNS 读不到规则（旧版只挂 zygote 的问题），执行 xguard run shield start 重新挂载"
[ "$me" = bind ] && [ "$netd_mark" = true ] && [ "$ino_match" != true ] && warn "netd 看到的 hosts 带标记但 inode 与源文件不同（可能是旧挂载残留），更新后它不会变"
[ -n "$others" ] && warn "其他模块也带 system/etc/hosts：${others# }（可能互相覆盖）"
[ "$pblk" = true ] && warn "私人 DNS 主机名 $pspec 被规则拦截，私人 DNS 会连不上导致断网：放行它或关掉「加密 DNS 绕过」源"
[ "$hy" = true ] && warn "代理服务运行中且 proxy_yield=1：hosts 已撤下，网络去广告完全依赖代理服务自己的去广告开关"
[ "$hr" = true ] && [ "$ga" != true ] && warn "代理服务运行中，HTTPDNS IP 拦截暂停（避免和代理服务的 iptables 冲突）"
[ "$hr" != true ] && ! guard_wanted && warn "HTTPDNS IP 拦截是关的：抖音 / 淘宝 / 腾讯系等 App 的广告 SDK 用纯 IP 的 HTTPDNS 解析，完全绕过 hosts"
[ "$hr" != true ] && guard_wanted && [ "$ga" != true ] && warn "HTTPDNS IP 拦截开着但 iptables 规则不在（iptables 不可用？）"
[ "${srules:-0}" -gt 0 ] && [ "${locked:-0}" -eq 0 ] && warn "开屏锁定 $srules 条规则，一个都没锁上（对应 App 没装或目录还没生成）"
case "$hctx" in *system_file*|""|"?") ;; *) warn "hosts 源文件 SELinux 标签是 $hctx（应为 system_file），netd 可能读不了" ;; esac
[ "$v" = ok ] && warn "hosts 只能拦独立的广告域名：和内容同域名的信息流广告（抖音、微信朋友圈、淘宝首页等）拦不住，这是 DNS 去广告的上限"

out=$(printf '{"verdict":"%s","time":%s,"method":"%s","root":"%s","feature":"%s","domain":"%s","resolve":"%s","resolver":"%s","global":%s,"file":%s,"src_mark":%s,"zygote_pid":%s,"zygote_rules":%s,"netd_pid":"%s","netd_rules":%s,"netd_mounts":%s,"inode_match":%s,"hosts_ctx":"%s","apps":[%s],"apps_bad":%s,"private_dns":"%s","private_dns_host":"%s","private_dns_blocked":%s,"ksu":%s,"guard":%s,"guard_active":%s,"proxy_running":%s,"proxy_yield":%s,"sources_ok":%s,"sources_want":%s,"last_ok":%s,"other_hosts_modules":"%s","splash_rules":%s,"splash_locked":%s,"warnings":[%s]}' \
  "$v" "$(date +%s)" "$me" "$(shield_root)" "$(json_esc "$feat")" "$(json_esc "$d")" "$(json_esc "$ip")" "$tool" "${g:-0}" "${file_rules:-0}" "$src_mark" \
  "$zp" "${zy_rules:-0}" "$np" "${netd_rules:-0}" "${netd_mnt:-0}" "$ino_match" "$(json_esc "$hctx")" "$apps" "$bad" \
  "$(json_esc "$pdns")" "$(json_esc "$pspec")" "$pblk" "$([ -e /data/adb/ksud ] && echo true || echo false)" \
  "$(guard_wanted && echo true || echo false)" "$ga" "$hr" "$hy" "${s_ok:-0}" "${s_want:-0}" "${last_ok:-0}" "$(json_esc "${others# }")" \
  "${srules:-0}" "${locked:-0}" "$W")
echo "$out" >"$TEST_JSON"
echo "$out"
shield_write_status >/dev/null 2>&1

if [ $human = 1 ]; then
  printf '\n防护引擎自检：%s\n' "$v"
  printf '  插件      %s\n' "$feat"
  printf '  规则      %s 条（源 %s/%s 成功，上次更新 %s）\n' "${file_rules:-0}" "${s_ok:-0}" "${s_want:-0}" "$(date -d "@${last_ok:-0}" '+%m-%d %H:%M' 2>/dev/null || echo "$last_ok")"
  printf '  挂载方式  %s（root=%s）\n' "$me" "$(shield_root)"
  printf '  netd      pid=%s 读到 %s 条 标记=%s inode一致=%s 挂载项=%s\n' "${np:-无}" "${netd_rules:-0}" "$netd_mark" "$ino_match" "${netd_mnt:-0}"
  printf '  zygote    pid=%s 读到 %s 条 标记=%s\n' "$zp" "${zy_rules:-0}" "$zy_mark"
  printf '  解析测试  %s → %s（%s；0.0.0.0 = 已拦截，空 = 解析失败）\n' "${d:-无}" "${ip:-空}" "${tool:-无}"
  printf '  私人 DNS  %s %s\n' "$pdns" "$pspec"
  printf '  HTTPDNS   开关=%s iptables生效=%s\n' "$(guard_wanted && echo 开 || echo 关)" "$ga"
  printf '  代理服务      运行=%s 让位=%s\n' "$hr" "$hy"
  printf '  开屏锁定  %s 条规则，已锁 %s 个 App\n' "${srules:-0}" "${locked:-0}"
  [ -n "${WL:-}" ] && printf '提示：\n%s' "$WL"
fi
exit 0
