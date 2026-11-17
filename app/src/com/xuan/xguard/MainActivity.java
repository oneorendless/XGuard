package com.xuan.xguard;

import android.app.Activity;
import android.app.ActivityManager;
import android.content.Intent;
import android.os.Bundle;
import android.os.Build;
import android.content.res.Configuration;
import android.graphics.Color;
import android.graphics.Insets;
import android.view.WindowInsets;
import android.view.HapticFeedbackConstants;
import android.net.Uri;
import android.provider.Settings;
import android.webkit.JavascriptInterface;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.webkit.WebResourceRequest;
import android.view.accessibility.AccessibilityManager;
import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import org.json.JSONArray;
import org.json.JSONObject;

public final class MainActivity extends Activity {
    private WebView webView;
    private final ExecutorService executor = Executors.newCachedThreadPool();

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        setTitle("XGuard");
        boolean dark = (getResources().getConfiguration().uiMode & Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES;
        webView = new WebView(this);
        webView.setBackgroundColor(dark ? Color.BLACK : Color.rgb(245,245,245));
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
                if ("https".equals(uri.getScheme()) && "github.com".equals(uri.getHost())) {
                    try { startActivity(new Intent(Intent.ACTION_VIEW, uri)); } catch (Exception ignored) { }
                    return true;
                }
                return !"file".equals(uri.getScheme()) || !uri.getPath().startsWith("/android_asset/");
            }
        });
        webView.addJavascriptInterface(new RootBridge(), "XGuard");
        setContentView(webView);
        applyHideFromRecents();
        webView.loadUrl("file:///android_asset/index.html");
    }

    @Override public void onBackPressed() {
        if (webView == null) { super.onBackPressed(); return; }
        webView.evaluateJavascript("Boolean(window.xguardBack && window.xguardBack())", handled -> {
            if (!"true".equals(handled)) MainActivity.super.onBackPressed();
        });
    }

    @Override protected void onResume() {
        super.onResume();
        if (webView != null) webView.post(() -> webView.evaluateJavascript("window.xguardPermissionsChanged && window.xguardPermissionsChanged()", null));
    }

    @Override protected void onDestroy() {
        executor.shutdownNow();
        if (webView != null) webView.destroy();
        super.onDestroy();
    }

    private void applyHideFromRecents() {
        boolean hidden = getSharedPreferences("xguard", MODE_PRIVATE).getBoolean("hide_from_recents", false);
        try {
            ActivityManager manager = (ActivityManager) getSystemService(ACTIVITY_SERVICE);
            if (manager == null) return;
            int currentTaskId = getTaskId();
            for (ActivityManager.AppTask task : manager.getAppTasks()) {
                ActivityManager.RecentTaskInfo info = task.getTaskInfo();
                if (info != null && info.id == currentTaskId) {
                    task.setExcludeFromRecents(hidden);
                    return;
                }
            }
        } catch (Exception ignored) { }
    }

    private final class RootBridge {
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
            runOnUiThread(() -> { if (!isFinishing()) webView.performHapticFeedback(HapticFeedbackConstants.CONTEXT_CLICK); });
        }
        @JavascriptInterface public boolean getHideFromRecents() { return getSharedPreferences("xguard", MODE_PRIVATE).getBoolean("hide_from_recents", false); }
        @JavascriptInterface public void setHideFromRecents(final boolean hidden) {
            getSharedPreferences("xguard", MODE_PRIVATE).edit().putBoolean("hide_from_recents", hidden).apply();
            runOnUiThread(MainActivity.this::applyHideFromRecents);
        }
        @JavascriptInterface public void setUiRulesEnabled(boolean enabled) {
            getSharedPreferences("xguard", MODE_PRIVATE).edit().putBoolean("ui_rules_enabled", enabled).apply();
        }
        @JavascriptInterface public boolean getUiRulesEnabled() { return getSharedPreferences("xguard", MODE_PRIVATE).getBoolean("ui_rules_enabled", false); }
        @JavascriptInterface public boolean getUiRuleSource(String source) { return getSharedPreferences("xguard", MODE_PRIVATE).getBoolean("ui_source_" + source, true); }
        @JavascriptInterface public void setUiRuleSource(String source, boolean enabled) {
            if (source == null || !source.matches("[a-z0-9-]+")) return;
            getSharedPreferences("xguard", MODE_PRIVATE).edit().putBoolean("ui_source_" + source, enabled).apply();
        }
        @JavascriptInterface public void openAccessibilitySettings() {
            try { startActivity(new Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)); } catch (Exception ignored) { }
        }
        @JavascriptInterface public boolean isAccessibilityEnabled() { return GkdPermissions.enabled(MainActivity.this); }

        @JavascriptInterface public void requestRoot(final String callback) {
            if (callback == null || !callback.matches("xguardCallback[0-9]+")) return;
            executor.execute(() -> {
                int code = 1; String output = "Root permission denied";
                try {
                    Process process = new ProcessBuilder("su", "-c", "id -u").redirectErrorStream(true).start();
                    BufferedReader reader = new BufferedReader(new InputStreamReader(process.getInputStream()));
                    StringBuilder result = new StringBuilder(); String line;
                    while ((line = reader.readLine()) != null) result.append(line).append('\n');
                    code = process.waitFor(); output = result.toString();
                } catch (Exception error) { output = error.toString(); }
                deliver(callback, code, output);
            });
        }

        private void deliver(final String callback, final int code, final String output) {
            runOnUiThread(() -> {
                if (isFinishing() || isDestroyed() || !callback.matches("xguardCallback[0-9]+")) return;
                webView.evaluateJavascript("if(window[" + JSONObject.quote(callback) + "])window[" + JSONObject.quote(callback) + "](" + code + "," + JSONObject.quote(output) + ",\"\");", null);
            });
        }

        @JavascriptInterface public void execute(final String arguments, final String callback) {
            if (callback == null || !callback.matches("xguardCallback[0-9]+")) return;
            executor.execute(() -> {
                int errno = 0;
                String output;
                try {
                    JSONArray values = new JSONArray(arguments);
                    if (values.length() > 0 && "gkd".equals(values.getString(0))) {
                        deliver(callback, 0, GkdStore.handle(MainActivity.this, values));
                        return;
                    }
                    if (values.length() > 0 && "apps".equals(values.getString(0))) {
                        deliver(callback, 0, AppCatalog.describe(MainActivity.this, values));
                        return;
                    }
                    StringBuilder command = new StringBuilder("sh /data/adb/modules/xguard/system/bin/xguard");
                    for (int index = 0; index < values.length(); index++) {
                        String value = values.getString(index);
                        if (value.indexOf('\u0000') >= 0) throw new IllegalArgumentException("无效参数");
                        command.append(" '").append(value.replace("'", "'\\''")).append("'");
                    }
                    Process process = new ProcessBuilder("su", "-M", "-c", command.toString()).redirectErrorStream(true).start();
                    StringBuilder text = new StringBuilder();
                    BufferedReader reader = new BufferedReader(new InputStreamReader(process.getInputStream()));
                    String line;
                    while ((line = reader.readLine()) != null) text.append(line).append('\n');
                    errno = process.waitFor();
                    output = text.toString();
                } catch (Exception error) {
                    errno = 1;
                    output = error.toString();
                }
                final int resultCode = errno;
                final String result = output == null ? "" : output;
                runOnUiThread(() -> {
                    if (isFinishing() || isDestroyed() || !callback.matches("xguardCallback[0-9]+")) return;
                    String script = "if(window[" + JSONObject.quote(callback) + "])window[" + JSONObject.quote(callback) + "](" + resultCode + "," + JSONObject.quote(result) + ",\"\");";
                    webView.evaluateJavascript(script, null);
                });
            });
        }

    }
}
