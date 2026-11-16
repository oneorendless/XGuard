package com.xuan.xguard;

import android.app.Activity;
import android.app.AlertDialog;
import android.Manifest;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.content.res.Configuration;
import android.graphics.Color;
import android.graphics.Insets;
import android.net.Uri;
import android.net.VpnService;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.provider.Settings;
import android.view.HapticFeedbackConstants;
import android.view.WindowInsets;
import android.webkit.JavascriptInterface;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.webkit.WebResourceRequest;
import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.OutputStreamWriter;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.HashSet;
import java.util.LinkedHashSet;
import java.util.Locale;
import java.util.Set;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import org.json.JSONArray;
import org.json.JSONObject;

public final class MainActivity extends Activity {
    private static final int VPN_REQUEST = 1408;
    private static final SourceSpec[] SOURCE_CATALOG = {
        new SourceSpec("baseline", true, "内置基线规则", "随 APK 分发，离线可用", 0, new String[0]),
        new SourceSpec("httpdns", false, "HTTPDNS 拦截", "广告 SDK 和国内 App 的 HTTPDNS 域名", 0, new String[0]),
        new SourceSpec("awavenue", true, "秋风广告规则 AWAvenue", "Android 广告 SDK，小而准", 300, new String[]{"https://gcore.jsdelivr.net/gh/TG-Twilight/AWAvenue-Ads-Rule@main/Filters/AWAvenue-Ads-Rule-hosts.txt", "https://fastly.jsdelivr.net/gh/TG-Twilight/AWAvenue-Ads-Rule@main/Filters/AWAvenue-Ads-Rule-hosts.txt", "https://ghfast.top/https://raw.githubusercontent.com/TG-Twilight/AWAvenue-Ads-Rule/main/Filters/AWAvenue-Ads-Rule-hosts.txt"}),
        new SourceSpec("antiad", true, "anti-AD", "国内综合去广告列表，约 11 万条", 30000, new String[]{"https://anti-ad.net/domains.txt", "https://gcore.jsdelivr.net/gh/privacy-protection-tools/anti-AD@master/anti-ad-domains.txt", "https://fastly.jsdelivr.net/gh/privacy-protection-tools/anti-AD@master/anti-ad-domains.txt"}),
        new SourceSpec("goodbyeads", true, "GOODBYEADS", "国内 App 去广告合集，含自带白名单", 30000, new String[]{"https://gcore.jsdelivr.net/gh/8680/GOODBYEADS@master/data/rules/ad-domain.txt", "https://fastly.jsdelivr.net/gh/8680/GOODBYEADS@master/data/rules/ad-domain.txt", "https://ghfast.top/https://raw.githubusercontent.com/8680/GOODBYEADS/master/data/rules/ad-domain.txt"}),
        new SourceSpec("adaway", true, "AdAway 官方", "移动端广告规则，约 6500 条", 2000, new String[]{"https://gcore.jsdelivr.net/gh/AdAway/adaway.github.io@master/hosts.txt", "https://adaway.org/hosts.txt", "https://fastly.jsdelivr.net/gh/AdAway/adaway.github.io@master/hosts.txt"}),
        new SourceSpec("adrules", false, "AdRules（Cats-Team）", "国内综合规则，约 20 万条", 50000, new String[]{"https://adrules.top/adrules_domainset.txt", "https://gcore.jsdelivr.net/gh/Cats-Team/AdRules@main/adrules_domainset.txt", "https://gitlab.com/cats-team/AdRules/-/raw/main/adrules_domainset.txt"}),
        new SourceSpec("hagezi_light", false, "Hagezi Light", "国际综合轻量版，误杀较少", 50000, new String[]{"https://hagezi-mirror.dnsbunker.org/hosts/light.txt", "https://gitlab.com/hagezi/mirror/-/raw/main/dns-blocklists/hosts/light.txt"}),
        new SourceSpec("onehosts_lite", false, "1Hosts Lite", "国际综合，偏海外网站", 50000, new String[]{"https://gcore.jsdelivr.net/gh/badmojr/1Hosts@master/Lite/hosts.txt", "https://fastly.jsdelivr.net/gh/badmojr/1Hosts@master/Lite/hosts.txt", "https://raw.githubusercontent.com/badmojr/1Hosts/master/Lite/hosts.txt"}),
        new SourceSpec("adguard_dns", false, "AdGuard DNS 过滤器", "AdGuard 官方过滤器，偏海外", 50000, new String[]{"https://gcore.jsdelivr.net/gh/AdguardTeam/AdGuardSDNSFilter@gh-pages/Filters/filter.txt", "https://adguardteam.github.io/AdGuardSDNSFilter/Filters/filter.txt"}),
        new SourceSpec("stevenblack", false, "StevenBlack", "国际综合 hosts", 30000, new String[]{"https://gcore.jsdelivr.net/gh/StevenBlack/hosts@master/hosts", "https://fastly.jsdelivr.net/gh/StevenBlack/hosts@master/hosts", "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts"}),
        new SourceSpec("adguard_mobile", false, "AdGuard 移动广告", "移动广告 hosts 规则", 300, new String[]{"https://gcore.jsdelivr.net/gh/r-a-y/mobile-hosts@master/AdguardMobileAds.txt", "https://raw.githubusercontent.com/r-a-y/mobile-hosts/master/AdguardMobileAds.txt"}),
        new SourceSpec("doh", false, "加密 DNS 绕过", "拦截常见 DoH/DoT 服务域名", 300, new String[]{"https://hagezi-mirror.dnsbunker.org/domains/doh.txt", "https://gitlab.com/hagezi/mirror/-/raw/main/dns-blocklists/domains/doh.txt"}),
        new SourceSpec("hagezi_pro", false, "Hagezi Pro", "国际综合强力版，规则量较大", 100000, new String[]{"https://hagezi-mirror.dnsbunker.org/hosts/pro.txt", "https://gitlab.com/hagezi/mirror/-/raw/main/dns-blocklists/hosts/pro.txt"})
    };
    private WebView webView;
    private final ExecutorService executor = Executors.newCachedThreadPool();
    private String pendingVpnCallback;

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        setTitle("XGuard");
        boolean dark = (getResources().getConfiguration().uiMode & Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES;
        webView = new WebView(this);
        webView.setBackgroundColor(dark ? Color.BLACK : Color.rgb(245, 245, 245));
        if (Build.VERSION.SDK_INT >= 35) {
            getWindow().getDecorView().setOnApplyWindowInsetsListener((view, insets) -> {
                Insets bars = insets.getInsets(WindowInsets.Type.systemBars() | WindowInsets.Type.displayCutout());
                view.setPadding(bars.left, bars.top, bars.right, bars.bottom);
                return WindowInsets.CONSUMED;
            });
        }
        WebSettings settings = webView.getSettings();
        settings.setJavaScriptEnabled(true);
        if (Build.VERSION.SDK_INT >= 33) settings.setAlgorithmicDarkeningAllowed(false);
        settings.setDomStorageEnabled(true);
        settings.setAllowFileAccess(true);
        settings.setAllowContentAccess(false);
        settings.setBlockNetworkLoads(true);
        settings.setBuiltInZoomControls(false);
        webView.setWebViewClient(new WebViewClient() {
            @Override public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                Uri uri = request.getUrl();
                if ("https".equals(uri.getScheme()) && "github.com".equals(uri.getHost()) && "/oneorendless/XGuard".equals(uri.getPath())) {
                    try { startActivity(new Intent(Intent.ACTION_VIEW, uri)); } catch (Exception ignored) { }
                    return true;
                }
                return !"file".equals(uri.getScheme()) || !uri.getPath().startsWith("/android_asset/");
            }
        });
        webView.addJavascriptInterface(new XGuardBridge(), "XGuard");
        setContentView(webView);
        webView.loadUrl("file:///android_asset/index.html");
        new Handler().postDelayed(this::showKeepAlivePromptIfNeeded, 700);
    }

    @Override protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode != VPN_REQUEST || pendingVpnCallback == null) return;
        String callback = pendingVpnCallback;
        pendingVpnCallback = null;
        if (resultCode == RESULT_OK) {
            startVpnService();
            deliver(callback, 0, "VPN permission granted");
        } else deliver(callback, 1, "本地 VPN 权限未授予");
    }

    private void requestVpn(final String callback) {
        if (callback == null || !callback.matches("xguardCallback[0-9]+")) return;
        Intent intent = VpnService.prepare(this);
        if (intent != null) {
            pendingVpnCallback = callback;
            startActivityForResult(intent, VPN_REQUEST);
        } else {
            startVpnService();
            deliver(callback, 0, "VPN permission granted");
        }
    }

    private void startVpnService() {
        synchronized (RecoveryStore.class) { startVpnServiceLocked(); }
    }
    private void startVpnServiceLocked() {
        if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) requestPermissions(new String[]{Manifest.permission.POST_NOTIFICATIONS}, 8304);
        getSharedPreferences("xguard", MODE_PRIVATE).edit().putBoolean("enabled", true).putBoolean("autostart_enabled", true).apply();
        Intent service = new Intent(this, XGuardVpnService.class);
        if (Build.VERSION.SDK_INT >= 26) startForegroundService(service); else startService(service);
    }

    private void stopVpnService() {
        synchronized (RecoveryStore.class) { stopVpnServiceLocked(); }
    }
    private void stopVpnServiceLocked() {
        getSharedPreferences("xguard", MODE_PRIVATE).edit().putBoolean("enabled", false).remove("pause_until").apply();
        XGuardVpnService.requestStop(this);
    }

    private void deliver(final String callback, final int code, final String output) {
        runOnUiThread(() -> {
            if (webView == null || isFinishing() || (Build.VERSION.SDK_INT >= 17 && isDestroyed())) return;
            String script = "if(window[" + JSONObject.quote(callback) + "])window[" + JSONObject.quote(callback) + "](" + code + "," + JSONObject.quote(output == null ? "" : output) + ",\"\");";
            webView.evaluateJavascript(script, null);
        });
    }

    private void showKeepAlivePromptIfNeeded() {
        SharedPreferences prefs = getSharedPreferences("xguard", MODE_PRIVATE);
        if (prefs.getBoolean("keepalive_prompt", false) || isFinishing()) return;
        prefs.edit().putBoolean("keepalive_prompt", true).apply();
        new AlertDialog.Builder(this)
                .setTitle("保持后台防护")
                .setMessage("XGuard 需要在后台保持 VPN 服务，锁屏后才能继续拦截广告。请将电池策略设为“不受限制”，并在系统设置中允许自启动；通知栏中的常驻通知用于保活和快速停止防护。")
                .setPositiveButton("电量不受限", (dialog, which) -> openBatterySettings())
                .setNeutralButton("自启动设置", (dialog, which) -> openAutoStartSettings())
                .setNegativeButton("稍后", null)
                .show();
    }

    private void openBatterySettings() {
        try {
            Intent intent = new Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS);
            intent.setData(Uri.parse("package:" + getPackageName()));
            startActivity(intent);
        } catch (Exception ignored) {
            Intent intent = new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS);
            intent.setData(Uri.parse("package:" + getPackageName()));
            startActivity(intent);
        }
    }

    private void openAutoStartSettings() {
        String[] actions = {"miui.intent.action.OP_AUTO_START", "huawei.intent.action.HSM_BOOTAPP_MANAGER", "oppo.intent.action.OPPO_STARTUP_MANAGER", "vivo.intent.action.SERVICE_LIST"};
        for (String action : actions) {
            try {
                Intent intent = new Intent(action);
                intent.setData(Uri.parse("package:" + getPackageName()));
                startActivity(intent);
                return;
            } catch (Exception ignored) { }
        }
        Intent intent = new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS);
        intent.setData(Uri.parse("package:" + getPackageName()));
        startActivity(intent);
    }

    @Override public void onBackPressed() {
        if (webView == null) { super.onBackPressed(); return; }
        webView.evaluateJavascript("Boolean(window.xguardBack && window.xguardBack())", handled -> {
            if (!"true".equals(handled)) MainActivity.super.onBackPressed();
        });
    }

    @Override protected void onDestroy() {
        executor.shutdownNow();
        if (webView != null) webView.destroy();
        super.onDestroy();
    }

    private final class XGuardBridge {
        @JavascriptInterface public String getMode() { return "vpn"; }
        @JavascriptInterface public boolean isVpnPrepared() { return VpnService.prepare(MainActivity.this) == null; }
        @JavascriptInterface public void setTheme(final boolean dark) {
            runOnUiThread(() -> {
                if (webView == null || isFinishing()) return;
                webView.setBackgroundColor(dark ? Color.BLACK : Color.rgb(245,245,245));
                getWindow().setStatusBarColor(dark ? Color.BLACK : Color.rgb(245,245,245));
                getWindow().setNavigationBarColor(dark ? Color.BLACK : Color.rgb(245,245,245));
                if (Build.VERSION.SDK_INT >= 30 && getWindow().getInsetsController() != null) {
                    int mask = android.view.WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS | android.view.WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS;
                    getWindow().getInsetsController().setSystemBarsAppearance(dark ? 0 : mask, mask);
                } else {
                    int flags = getWindow().getDecorView().getSystemUiVisibility();
                    int mask = android.view.View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR;
                    if (Build.VERSION.SDK_INT >= 26) mask |= android.view.View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR;
                    getWindow().getDecorView().setSystemUiVisibility(dark ? flags & ~mask : flags | mask);
                }
            });
        }
        @JavascriptInterface public void haptic() {
            runOnUiThread(() -> { if (webView != null && !isFinishing()) webView.performHapticFeedback(HapticFeedbackConstants.CONTEXT_CLICK); });
        }
        @JavascriptInterface public void requestRoot(String callback) { MainActivity.this.requestVpn(callback); }
        @JavascriptInterface public void requestVpn(String callback) { MainActivity.this.requestVpn(callback); }
        @JavascriptInterface public void execute(final String arguments, final String callback) {
            if (callback == null || !callback.matches("xguardCallback[0-9]+")) return;
            executor.execute(() -> {
                int code = 0;
                String output;
                try { output = dispatch(new JSONArray(arguments)); }
                catch (Exception error) { code = 1; output = error.getMessage() == null ? error.toString() : error.getMessage(); }
                deliver(callback, code, output);
            });
        }
        private String dispatch(JSONArray values) throws Exception {
            if (values.length() == 0) throw new IllegalArgumentException("缺少操作");
            String command = values.getString(0);
            if ("apps".equals(command)) return AppCatalog.describe(MainActivity.this, values);
            if ("status".equals(command)) return statusJson();
            if ("log".equals(command)) {
                if (values.length() > 1 && "shield".equals(values.getString(1))) return "最近 DNS 记录（仅保留已开启采集时的记录）\n" + XGuardVpnService.activityJson(MainActivity.this).getJSONObject("snapshot").getJSONArray("items").toString(2);
                return "本地 VPN 运行状态（免 Root 版不读取系统日志）\n" + new JSONObject(statusJson()).toString(2) + "\n累计 DNS 计数\n" + XGuardVpnService.activityJson(MainActivity.this).getJSONObject("snapshot").getJSONObject("totals").toString(2);
            }
            if ("enable".equals(command)) { startVpnService(); return ""; }
            if ("disable".equals(command)) { stopVpnService(); return ""; }
            if ("safe".equals(command)) return "";
            if (!"run".equals(command) || values.length() < 3) throw new IllegalArgumentException("不支持的操作");
            return runCommand(values);
        }
        private String runCommand(JSONArray values) throws Exception {
            String action = values.getString(2);
            SharedPreferences prefs = getSharedPreferences("xguard", MODE_PRIVATE);
            if ("stats".equals(action)) return statsJson(prefs);
            if ("recovery".equals(action)) return recoveryCommand(values, prefs);
            if ("allow".equals(action) || "block".equals(action)) return domainCommand(action, values, prefs);
            if ("query".equals(action)) return queryJson(values.getString(3), prefs);
            if ("activity".equals(action)) return activityCommand(values, prefs);
            if ("sources".equals(action)) return sourcesCommand(values, prefs);
            if ("test".equals(action)) return testJson();
            if ("update".equals(action)) return updateSources(prefs);
            if ("guard".equals(action) || "set".equals(action)) return settingsCommand(action, values, prefs);
            if ("hits".equals(action)) return "{\"supported\":false,\"rules\":[]}";
            if ("rules".equals(action) || "discover".equals(action) || "unlock".equals(action) || "relock".equals(action)) throw new IllegalArgumentException("开屏缓存锁定需要 Root；免 Root 版通过 DNS 拦截广告域名");
            return "{}";
        }
        private String statusJson() throws Exception {
            boolean enabled = getSharedPreferences("xguard", MODE_PRIVATE).getBoolean("enabled", false);
            boolean running = XGuardVpnService.isRunning(), paused = RecoveryStore.isPaused(MainActivity.this);
            JSONObject feature = new JSONObject(); feature.put("enabled", enabled); feature.put("conflict", false); feature.put("health", enabled && !running ? "VPN 服务未运行" : "ok"); feature.put("pause_until", paused ? RecoveryStore.pausedUntil(MainActivity.this) : 0); feature.put("summary", !enabled ? "点击开关开启本地 VPN 防护" : !running ? "防护已开启，但 VPN 服务未运行，请检查并修复" : paused ? "临时暂停 DNS 拦截，VPN 继续转发 DNS" : "本地 VPN 正在拦截广告域名");
            JSONObject result = new JSONObject(); result.put("root", "无 Root · Android VPN"); result.put("daemon", running ? "前台服务运行中" : "未运行"); result.put("safe_mode", false); result.put("version", "0.8.7"); result.put("features", new JSONArray().put(feature));
            return result.toString();
        }
        private String statsJson(SharedPreferences prefs) throws Exception {
            Set<String> enabled = enabledSourceIds(prefs);
            JSONObject result = new JSONObject(); result.put("mode", "dns-vpn"); result.put("hosts_rules", XGuardVpnService.ruleCount(MainActivity.this) + prefs.getStringSet("custom_block", java.util.Collections.emptySet()).size()); result.put("splash_locked_apps", 0); result.put("sources", enabled.size()); result.put("updating", false); result.put("last_ok", prefs.getLong("last_update", 0)); result.put("capped", false); result.put("guard", prefs.getBoolean("guard", false) ? 1 : 0); result.put("proxy_yield", 0); result.put("hide", 0); result.put("mount_mode", "auto"); result.put("hosts_max", 100000); result.put("auto_state", "前台服务"); result.put("auto_next", 0); return result.toString();
        }
        private String domainCommand(String kind, JSONArray values, SharedPreferences prefs) throws Exception {
            java.util.Set<String> set = new java.util.HashSet<>(prefs.getStringSet("custom_" + kind, java.util.Collections.emptySet()));
            if (values.length() >= 5) { RecoveryStore.domainChange(MainActivity.this,kind,values.getString(3),values.getString(4)); return "{}"; }
            JSONObject result = new JSONObject(); result.put(kind, new JSONArray(set)); return result.toString();
        }
        private String queryJson(String domain, SharedPreferences prefs) throws Exception {
            boolean allowed = XGuardVpnService.isAllowed(MainActivity.this, domain);
            boolean blocked = !allowed && XGuardVpnService.isBlocked(MainActivity.this, domain);
            JSONObject result = new JSONObject(); result.put("allowed", allowed); result.put("blocked", blocked); result.put("in_source", blocked && !prefs.getStringSet("custom_block", java.util.Collections.emptySet()).contains(domain)); return result.toString();
        }
        private String activityCommand(JSONArray values, SharedPreferences prefs) throws Exception {
            if (values.length() >= 4) { String op = values.getString(3); if ("clear".equals(op)) XGuardVpnService.clearActivity(); if ("disable".equals(op)) prefs.edit().putBoolean("collector", false).apply(); if ("enable".equals(op)) prefs.edit().putBoolean("collector", true).apply(); }
            JSONObject result = XGuardVpnService.activityJson(MainActivity.this); result.getJSONObject("collector").put("enabled", prefs.getBoolean("collector", true)); return result.toString();
        }
        private String sourcesCommand(JSONArray values, SharedPreferences prefs) throws Exception {
            synchronized (RecoveryStore.class) { return sourcesCommandLocked(values,prefs); }
        }
        private String sourcesCommandLocked(JSONArray values, SharedPreferences prefs) throws Exception {
            Set<String> enabled = enabledSourceIds(prefs);
            Set<String> custom = new HashSet<>(prefs.getStringSet("custom_sources", java.util.Collections.emptySet()));
            if (values.length() >= 5 && "enable".equals(values.getString(3))) enabled.add(values.getString(4));
            if (values.length() >= 5 && "disable".equals(values.getString(3))) enabled.remove(values.getString(4));
            if (values.length() >= 5 && "add".equals(values.getString(3))) custom.add(values.getString(4));
            if (values.length() >= 5 && "remove".equals(values.getString(3))) custom.remove(values.getString(4));
            if (values.length() >= 4 && "reset".equals(values.getString(3))) { enabled = defaultSourceIds(); custom.clear(); }
            if (values.length() >= 4 && "interval".equals(values.getString(3)) && values.length() >= 5) prefs.edit().putInt("interval", Integer.parseInt(values.getString(4))).apply();
            if (enabled.isEmpty()) enabled.add("baseline");
            prefs.edit().putStringSet("enabled_sources", enabled).putStringSet("custom_sources", custom).apply();
            if (values.length() >= 4 && ("enable".equals(values.getString(3)) || "disable".equals(values.getString(3)) || "reset".equals(values.getString(3)))) XGuardVpnService.reloadRules(MainActivity.this);
            JSONArray list = new JSONArray();
            for (SourceSpec spec : SOURCE_CATALOG) {
                JSONObject item = new JSONObject(); item.put("id", spec.id); item.put("name", spec.name); item.put("desc", spec.description); item.put("enabled", enabled.contains(spec.id)); item.put("custom", false); item.put("count", sourceCount(spec)); item.put("result", sourceResult(spec)); list.put(item);
            }
            for (String url : custom) { JSONObject item = new JSONObject(); item.put("id", url); item.put("name", url); item.put("url", url); item.put("enabled", true); item.put("custom", true); item.put("count", 0); item.put("result", "已保存，点击更新规则下载"); list.put(item); }
            JSONObject result = new JSONObject(); result.put("list", list); result.put("interval_h", prefs.getInt("interval", 24)); result.put("sources_ok", enabled.size()); return result.toString();
        }

        private Set<String> defaultSourceIds() { Set<String> result = new LinkedHashSet<>(); for (SourceSpec spec : SOURCE_CATALOG) if (spec.enabledByDefault) result.add(spec.id); return result; }
        private Set<String> enabledSourceIds(SharedPreferences prefs) { Set<String> result = new LinkedHashSet<>(prefs.getStringSet("enabled_sources", java.util.Collections.emptySet())); if (result.isEmpty()) result.addAll(defaultSourceIds()); return result; }
        private SourceSpec sourceSpec(String id) { for (SourceSpec spec : SOURCE_CATALOG) if (spec.id.equals(id)) return spec; return null; }
        private int sourceCount(SourceSpec spec) { if ("baseline".equals(spec.id)) return XGuardVpnService.countAsset(MainActivity.this, "blocklist.txt"); if ("httpdns".equals(spec.id)) return XGuardVpnService.countAsset(MainActivity.this, "httpdns.list"); return XGuardVpnService.countSourceFile(MainActivity.this, spec.id); }
        private String sourceResult(SourceSpec spec) { if (spec.urls.length == 0) return sourceCount(spec) > 0 ? "离线可用" : "未打包"; return sourceCount(spec) > 0 ? "已缓存" : "点击更新规则下载"; }
        private String updateSources(SharedPreferences prefs) throws Exception {
            synchronized (RecoveryStore.class) { return updateSourcesLocked(prefs); }
        }
        private String updateSourcesLocked(SharedPreferences prefs) throws Exception {
            if (RecoveryStore.isPaused(MainActivity.this)) throw new IOException("请先结束临时暂停再更新规则");
            Set<String> before = XGuardVpnService.ruleSnapshot(MainActivity.this);
            RecoveryStore.beginUpdate(MainActivity.this);
            Set<String> enabled = enabledSourceIds(prefs); int updated = 0; int failed = 0;
            for (String id : enabled) { SourceSpec spec = sourceSpec(id); if (spec == null || spec.urls.length == 0) continue; try { if (downloadSource(spec)) updated++; else failed++; } catch (Exception error) { failed++; } }
            XGuardVpnService.reloadRules(MainActivity.this);
            if (updated == 0 && failed > 0) { RecoveryStore.cancelUpdate(MainActivity.this); prefs.edit().putString("last_update_result","fail").apply(); throw new IOException("订阅下载失败，已保留旧规则，请检查网络后重试"); }
            JSONObject diff;
            try { diff=RecoveryStore.finishUpdate(MainActivity.this,before); }
            catch(Exception error) { RecoveryStore.abortUpdate(MainActivity.this); throw error; }
            prefs.edit().putLong("last_update", System.currentTimeMillis() / 1000L).putString("last_update_result",failed>0?"partial":"ok").remove("update_hold_until").apply();
            JSONObject result = new JSONObject(); result.put("updated", updated); result.put("failed", failed); result.put("rules", XGuardVpnService.ruleCount(MainActivity.this)); result.put("diff",diff); return result.toString();
        }
        private boolean downloadSource(SourceSpec spec) throws Exception {
            File target = new File(getFilesDir(), "source_" + spec.id + ".list"); File temp = new File(target.getPath() + ".tmp");
            for (String address : spec.urls) {
                HttpURLConnection connection = null;
                try {
                    connection = (HttpURLConnection) new URL(address).openConnection(); connection.setConnectTimeout(10000); connection.setReadTimeout(30000); connection.setInstanceFollowRedirects(true); connection.setRequestProperty("User-Agent", "XGuard/0.8.7");
                    if (connection.getResponseCode() / 100 != 2) continue;
                    try (BufferedReader reader = new BufferedReader(new InputStreamReader(connection.getInputStream(), StandardCharsets.UTF_8)); BufferedWriter writer = new BufferedWriter(new OutputStreamWriter(new FileOutputStream(temp), StandardCharsets.UTF_8))) {
                        String line; long bytes = 0; while ((line = reader.readLine()) != null) { bytes += line.length() + 1; if (bytes > 20L * 1024L * 1024L) throw new IOException("订阅过大"); writer.write(line); writer.newLine(); }
                    }
                    if (XGuardVpnService.countSourceFile(temp) < spec.minimumRules) { temp.delete(); continue; }
                    if (!temp.renameTo(target)) throw new IOException("无法保存订阅缓存");
                    return true;
                } catch (Exception ignored) {
                    temp.delete();
                } finally { if (connection != null) connection.disconnect(); }
            }
            return false;
        }
        private String testJson() throws Exception { JSONObject result = new JSONObject(); result.put("verdict", XGuardVpnService.isRunning() ? "ok" : "off"); result.put("warnings", new JSONArray()); return result.toString(); }
        private String recoveryCommand(JSONArray values, SharedPreferences prefs) throws Exception {
            synchronized (RecoveryStore.class) { return recoveryCommandLocked(values,prefs); }
        }
        private String recoveryCommandLocked(JSONArray values, SharedPreferences prefs) throws Exception {
            String op = values.optString(3,"status");
            if ("pause".equals(op)) { if (!prefs.getBoolean("enabled",false) || !XGuardVpnService.isRunning()) throw new IOException("请先开启 VPN 防护"); prefs.edit().putLong("pause_until",System.currentTimeMillis()/1000L+300).apply(); }
            else if ("resume".equals(op)) prefs.edit().remove("pause_until").apply();
            else if ("rollback".equals(op)) RecoveryStore.rollback(MainActivity.this);
            else if ("undo".equals(op)) RecoveryStore.undoDomain(MainActivity.this);
            else if ("check".equals(op) || "repair".equals(op)) {
                if ("repair".equals(op) && prefs.getBoolean("enabled",false) && !RecoveryStore.isPaused(MainActivity.this)) {
                    if (VpnService.prepare(MainActivity.this) != null) throw new IOException("VPN 权限已失效，请重新授权");
                    XGuardVpnService.reloadRules(MainActivity.this);
                    if (!XGuardVpnService.isRunning()) { startVpnService(); for(int i=0;i<20 && !XGuardVpnService.isRunning();i++) Thread.sleep(100); }
                }
                boolean desired = prefs.getBoolean("enabled",false), running = XGuardVpnService.isRunning(), authorized = VpnService.prepare(MainActivity.this)==null;
                String state = !desired?"off":RecoveryStore.isPaused(MainActivity.this)?"paused":!authorized?"permission_required":!running?"vpn_stopped":XGuardVpnService.ruleCount(MainActivity.this)==0?"no_rules":"ok";
                JSONObject health=new JSONObject(); health.put("state",state); health.put("checked_at",System.currentTimeMillis()/1000L); health.put("desired",desired); health.put("paused",RecoveryStore.isPaused(MainActivity.this)); health.put("collector_running",running); health.put("collector_enabled",prefs.getBoolean("collector",true)); health.put("action",op); health.put("mode","dns-vpn"); health.put("vpn_authorized",authorized);
                prefs.edit().putString("last_health",health.toString()).apply(); return health.toString();
            } else if (!"status".equals(op)) throw new IOException("未知恢复操作");
            JSONObject result = RecoveryStore.status(MainActivity.this); result.put("health",new JSONObject(prefs.getString("last_health","{}"))); return result.toString();
        }
        private String settingsCommand(String action, JSONArray values, SharedPreferences prefs) throws Exception { if ("guard".equals(action) && values.length() >= 4) prefs.edit().putBoolean("guard", "on".equals(values.getString(3))).apply(); if ("set".equals(action) && values.length() >= 5) prefs.edit().putBoolean(values.getString(3), "1".equals(values.getString(4))).apply(); return "{}"; }
    }

    private static final class SourceSpec {
        final String id;
        final boolean enabledByDefault;
        final String name;
        final String description;
        final int minimumRules;
        final String[] urls;
        SourceSpec(String id, boolean enabledByDefault, String name, String description, int minimumRules, String[] urls) {
            this.id = id; this.enabledByDefault = enabledByDefault; this.name = name; this.description = description; this.minimumRules = minimumRules; this.urls = urls;
        }
    }
}
