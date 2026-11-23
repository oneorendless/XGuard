package com.xuan.xguard;

import android.app.Activity;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.widget.Toast;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import javax.net.ssl.HttpsURLConnection;
import org.json.JSONArray;
import org.json.JSONObject;

final class AppUpdates {
    private static final String REPOSITORY = "oneorendless/XGuard";
    private static final String LATEST_RELEASE = "https://api.github.com/repos/" + REPOSITORY + "/releases/latest";
    private static final String DOWNLOAD_BASE = "https://github.com/" + REPOSITORY + "/releases/download/";
    private static final String VERSION_PATTERN = "(0|[1-9][0-9]{0,8})(\\.(0|[1-9][0-9]{0,8})){2}";
    private static final int MAX_RELEASE_BYTES = 512 * 1024;
    private final Activity activity;
    private final boolean vpn;
    private volatile String downloadUrl;

    AppUpdates(Activity activity, boolean vpn) {
        this.activity = activity;
        this.vpn = vpn;
    }

    String installedVersion() throws PackageManager.NameNotFoundException {
        return activity.getPackageManager().getPackageInfo(activity.getPackageName(), 0).versionName;
    }

    String check() throws Exception {
        downloadUrl = null;
        String installed = installedVersion();
        HttpsURLConnection connection = (HttpsURLConnection) new URL(LATEST_RELEASE).openConnection();
        try {
            connection.setInstanceFollowRedirects(false);
            connection.setUseCaches(false);
            connection.setConnectTimeout(8000);
            connection.setReadTimeout(8000);
            connection.setRequestProperty("Accept", "application/vnd.github+json");
            connection.setRequestProperty("User-Agent", "XGuard/" + installed);
            if (connection.getResponseCode() != 200) throw new IOException("GitHub 未返回发布信息");
            try (InputStream stream = connection.getInputStream()) {
                ByteArrayOutputStream bytes = new ByteArrayOutputStream();
                byte[] buffer = new byte[8192];
                int count;
                while ((count = stream.read(buffer)) != -1) {
                    if (bytes.size() + count > MAX_RELEASE_BYTES) throw new IOException("发布信息过长");
                    bytes.write(buffer, 0, count);
                }
                JSONObject result = selectRelease(new JSONObject(new String(bytes.toByteArray(), StandardCharsets.UTF_8)), installed, vpn);
                downloadUrl = result.optString("url", null);
                result.remove("url");
                return result.toString();
            }
        } finally {
            connection.disconnect();
        }
    }

    static JSONObject selectRelease(JSONObject release, String installed, boolean vpn) throws Exception {
        String current = vpn && installed.endsWith("-noroot") ? installed.substring(0, installed.length() - "-noroot".length()) : installed;
        String tag = release.optString("tag_name");
        JSONObject result = new JSONObject().put("current", current).put("state", "current");
        if (release.optBoolean("draft", true) || release.optBoolean("prerelease", true)) return result;
        if (!tag.matches("v" + VERSION_PATTERN)) throw new IOException("无法识别发布版本");
        if (compareVersions(tag.substring(1), current) <= 0) return result;

        result.put("latest", tag.substring(1)).put("state", "missing");
        String name = "XGuard-" + tag + (vpn ? "-no-root.apk" : "-module.zip");
        String expected = DOWNLOAD_BASE + tag + "/" + name;
        JSONArray assets = release.optJSONArray("assets");
        for (int index = 0; assets != null && index < assets.length(); index++) {
            JSONObject asset = assets.optJSONObject(index);
            if (asset != null && name.equals(asset.optString("name")) && "uploaded".equals(asset.optString("state"))
                    && asset.optLong("size", 0) > 0 && expected.equals(asset.optString("browser_download_url"))) {
                return result.put("state", "available").put("url", expected);
            }
        }
        return result;
    }

    private static int compareVersions(String latest, String current) throws IOException {
        if (!current.matches(VERSION_PATTERN)) throw new IOException("无法识别已安装版本");
        String[] remoteParts = latest.split("\\.");
        String[] localParts = current.split("\\.");
        for (int index = 0; index < remoteParts.length; index++) {
            int comparison = Integer.compare(Integer.parseInt(remoteParts[index]), Integer.parseInt(localParts[index]));
            if (comparison != 0) return comparison;
        }
        return 0;
    }

    void openDownload() {
        activity.runOnUiThread(() -> {
            if (activity.isFinishing() || activity.isDestroyed()) return;
            String url = downloadUrl;
            if (url == null) return;
            try { activity.startActivity(new Intent(Intent.ACTION_VIEW, Uri.parse(url))); }
            catch (RuntimeException error) {
                Toast.makeText(activity, "无法打开下载链接，请在浏览器访问 XGuard 的 GitHub 发布页", Toast.LENGTH_LONG).show();
            }
        });
    }
}
