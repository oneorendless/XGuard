#!/system/bin/sh
set -e
# Isolated test package only. Run as root after installing the validation APK.
appops set com.xuan.xguard.validation087 ACTIVATE_VPN allow
pm grant com.xuan.xguard.validation087 android.permission.POST_NOTIFICATIONS
iptables -w -t nat -I OUTPUT 1 -d 10.231.0.1/32 -p udp --dport 53 -m comment --comment XGUARD_RECOVERY_TEST -j ACCEPT
trap 'iptables -w -t nat -D OUTPUT -d 10.231.0.1/32 -p udp --dport 53 -m comment --comment XGUARD_RECOVERY_TEST -j ACCEPT' EXIT
# Some vendor systems reject the instrumentation process's own activity launch.
( sleep 2; am start -n com.xuan.xguard.validation087/com.xuan.xguard.MainActivity >/dev/null 2>&1 ) &
am instrument -w com.xuan.xguard.validation087/com.xuan.xguard.RecoveryInstrumentation
