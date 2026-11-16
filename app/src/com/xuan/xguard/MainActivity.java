package com.xuan.xguard;

import android.app.Activity;
import android.os.Bundle;
import android.os.Build;
import android.content.res.Configuration;
import android.graphics.Color;
import android.graphics.Insets;
import android.view.WindowInsets;
import android.view.HapticFeedbackConstants;
import android.net.Uri;
import android.webkit.JavascriptInterface;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.webkit.WebResourceRequest;
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
        settings.setDomStorageEnabled(true);
        settings.setAllowFileAccess(true);
        settings.setAllowContentAccess(false);
        settings.setBlockNetworkLoads(true);
        settings.setBuiltInZoomControls(false);
        webView.setWebViewClient(new WebViewClient() {
            @Override public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                Uri uri = request.getUrl();
                return !"file".equals(uri.getScheme()) || !uri.getPath().startsWith("/android_asset/");
            }
        });
        webView.addJavascriptInterface(new RootBridge(), "XGuard");
        setContentView(webView);
        webView.loadUrl("file:///android_asset/index.html");
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

    private final class RootBridge {
        @JavascriptInterface public void haptic() {
            runOnUiThread(() -> { if (!isFinishing()) webView.performHapticFeedback(HapticFeedbackConstants.CONTEXT_CLICK); });
        }

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
                    StringBuilder command = new StringBuilder("sh /data/adb/modules/xguard/system/bin/xguard");
                    for (int index = 0; index < values.length(); index++) {
                        String value = values.getString(index);
                        if (value.indexOf('\u0000') >= 0) throw new IllegalArgumentException("无效参数");
                        command.append(" '").append(value.replace("'", "'\\''")).append("'");
                    }
                    Process process = new ProcessBuilder("su", "-c", command.toString()).redirectErrorStream(true).start();
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
