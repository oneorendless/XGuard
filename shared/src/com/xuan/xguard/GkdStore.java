package com.xuan.xguard;

import android.content.Context;
import android.content.SharedPreferences;
import org.json.JSONArray;
import org.json.JSONObject;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.List;
import android.util.AtomicFile;

public final class GkdStore {
    private static final long MAX_BYTES = 12L * 1024L * 1024L;
    private static final Source[] CATALOG = {
        new Source("xguard-local", "XGuard 本地补充", "学习通、移动云盘、迅雷开屏补充", ""),
        new Source("aisouler", "AIsouler GKD 订阅", "社区订阅（上游已停止维护），仅导入兼容开屏规则", "https://raw.githubusercontent.com/AIsouler/GKD_subscription/main/dist/AIsouler_gkd.json5"),
        new Source("lin-arm", "Lin-arm GKD 订阅", "社区订阅，仅导入兼容开屏规则", "https://raw.githubusercontent.com/Lin-arm/GKD_subscription/main/dist/gkd.json5"),
        new Source("ganlinte", "ganlinte GKD 订阅", "社区订阅，仅导入兼容开屏规则", "https://raw.githubusercontent.com/ganlinte/GKD-subscription/main/dist/ganlin_gkd.json5")
    };
    private static volatile JSONArray cachedRules;
    private static volatile long cachedRevision = -1;
    private static JSONObject localCache;

    private GkdStore() { }

    public static synchronized String handle(Context context, JSONArray args) throws Exception {
        String operation = args.optString(1);
        SharedPreferences prefs = prefs(context);
        if ("license".equals(operation)) { try (InputStream input = context.getAssets().open("GPL-3.0.txt")) { return read(input); } }
        if ("guard".equals(operation)) {
            boolean enabled = "1".equals(args.optString(2));
            prefs.edit().putBoolean("gkd_accessibility_guard", enabled).apply();
            return sources(context).toString();
        }
        if ("sources".equals(operation)) return sources(context).toString();
        if ("toggle".equals(operation)) {
            Source source = source(context, args.getString(2));
            boolean enabled = "1".equals(args.getString(3));
            if (enabled && !source.url.isEmpty() && !file(context, source.id).exists()) download(context, source);
            prefs.edit().putBoolean("ui_source_" + source.id, enabled).apply();
            invalidate(context);
            return sources(context).toString();
        }
        if ("add".equals(operation)) {
            String address = validateUrl(args.getString(2));
            for (Source existing : all(context)) if (address.equals(existing.url)) {
                download(context, existing);
                prefs.edit().putBoolean("ui_source_" + existing.id, true).apply();
                invalidate(context);
                return sources(context).toString();
            }
            String id = "custom-" + digest(address).substring(0, 20);
            Source added = new Source(id, address, "自定义在线订阅", address, true);
            download(context, added);
            prefs.edit().putString("gkd_url_" + id, address).putBoolean("ui_source_" + id, true).apply();
            invalidate(context);
            return sources(context).toString();
        }
        if ("remove".equals(operation)) {
            Source removed = source(context, args.getString(2));
            if (!removed.custom) throw new IllegalArgumentException("内置来源可取消勾选，自定义来源可删除");
            prefs.edit().remove("gkd_url_" + removed.id).remove("ui_source_" + removed.id).apply();
            new AtomicFile(file(context, removed.id)).delete();
            invalidate(context);
            return sources(context).toString();
        }
        if ("update".equals(operation)) {
            String requested = args.optString(2);
            int updated = 0;
            JSONArray failures = new JSONArray();
            for (Source source : all(context)) {
                if (source.url.isEmpty()) continue;
                if (!requested.isEmpty() && !requested.equals(source.id)) continue;
                if (requested.isEmpty() && !prefs.getBoolean("ui_source_" + source.id, source.url.isEmpty())) continue;
                try { download(context, source); updated++; }
                catch (Exception error) { failures.put(source.name + "：" + error.getMessage()); }
            }
            invalidate(context);
            return new JSONObject().put("updated", updated).put("failed", failures.length()).put("errors", failures).toString();
        }
        throw new IllegalArgumentException("未知 GKD 操作");
    }

    public static JSONArray enabledRules(Context context) {
        long revision = prefs(context).getLong("gkd_revision", 0);
        JSONArray current = cachedRules;
        if (current != null && cachedRevision == revision) return current;
        JSONArray rebuilt = new JSONArray();
        for (Source source : all(context)) {
            if (!prefs(context).getBoolean("ui_source_" + source.id, source.url.isEmpty())) continue;
            try {
                JSONArray rules = report(context, source).getJSONArray("rules");
                for (int index = 0; index < rules.length(); index++) rebuilt.put(rules.getJSONObject(index));
            } catch (Exception error) { android.util.Log.w("XGuardGKD", "Cannot load subscription " + source.id, error); }
        }
        cachedRevision = revision;
        cachedRules = rebuilt;
        return rebuilt;
    }

    private static JSONObject sources(Context context) throws Exception {
        JSONArray list = new JSONArray();
        for (Source source : all(context)) {
            JSONObject item = new JSONObject().put("id", source.id).put("name", source.name)
                .put("desc", source.description).put("url", source.url).put("custom", source.custom)
                .put("enabled", prefs(context).getBoolean("ui_source_" + source.id, source.url.isEmpty()));
            try {
                JSONObject report = report(context, source);
                item.put("name", report.optString("name", source.name)).put("version", report.opt("version"))
                    .put("count", report.getJSONArray("rules").length()).put("skipped", report.optInt("skipped"))
                    .put("result", source.url.isEmpty() ? "内置，可离线使用" : "已缓存");
            } catch (Exception ignored) { item.put("count", 0).put("skipped", 0).put("result", "未下载"); }
            list.put(item);
        }
        SharedPreferences prefs = prefs(context);
        return new JSONObject().put("list", list)
            .put("accessibility_guard", prefs.getBoolean("gkd_accessibility_guard", false))
            .put("last_action", prefs.getString("gkd_last_action", "")).put("last_action_at", prefs.getLong("gkd_last_action_at", 0));
    }

    private static void download(Context context, Source source) throws Exception {
        String address = validateUrl(source.url);
        for (int redirect = 0; redirect < 6; redirect++) {
            HttpURLConnection connection = (HttpURLConnection) new URL(address).openConnection();
            connection.setConnectTimeout(12000);
            connection.setReadTimeout(25000);
            connection.setInstanceFollowRedirects(false);
            connection.setRequestProperty("User-Agent", "XGuard/0.9.3");
            try {
                int status = connection.getResponseCode();
                if (status >= 300 && status < 400) {
                    String location = connection.getHeaderField("Location");
                    if (location == null) throw new IllegalArgumentException("订阅重定向缺少地址");
                    address = validateUrl(new URL(new URL(address), location).toString());
                    continue;
                }
                if (status / 100 != 2) throw new IllegalArgumentException("HTTP " + status);
                JSONObject compiled;
                try (InputStream input = connection.getInputStream()) {
                    compiled = GkdRules.compile(read(input), source.id);
                }
                AtomicFile target = new AtomicFile(file(context, source.id));
                java.io.FileOutputStream stream = null;
                try {
                    stream = target.startWrite();
                    stream.write(compiled.toString().getBytes(StandardCharsets.UTF_8));
                    target.finishWrite(stream);
                } catch (Exception error) { target.failWrite(stream); throw error; }
                return;
            } finally { connection.disconnect(); }
        }
        throw new IllegalArgumentException("订阅重定向次数过多");
    }

    private static JSONObject report(Context context, Source source) throws Exception {
        if (source.url.isEmpty()) {
            if (localCache == null) {
                try (InputStream input = context.getAssets().open("ui-rules.json")) {
                    String text = read(input);
                    localCache = GkdRules.compile(text, source.id);
                }
            }
            return localCache;
        }
        try (InputStream input = new AtomicFile(file(context, source.id)).openRead()) { return new JSONObject(read(input)); }
    }

    private static String read(InputStream input) throws Exception {
        ByteArrayOutputStream result = new ByteArrayOutputStream();
        byte[] buffer = new byte[8192];
        int count;
        while ((count = input.read(buffer)) != -1) {
            if (result.size() + count > MAX_BYTES) throw new IllegalArgumentException("订阅超过 12 MiB");
            result.write(buffer, 0, count);
        }
        return new String(result.toByteArray(), StandardCharsets.UTF_8);
    }

    private static String validateUrl(String address) throws Exception {
        URL parsed = new URL(address);
        if (!"https".equals(parsed.getProtocol()) || parsed.getHost().isEmpty() || parsed.getUserInfo() != null)
            throw new IllegalArgumentException("请输入 HTTPS 订阅地址");
        return address;
    }

    private static List<Source> all(Context context) {
        List<Source> sources = new ArrayList<>();
        for (Source source : CATALOG) sources.add(source);
        java.util.TreeSet<String> keys = new java.util.TreeSet<>(prefs(context).getAll().keySet());
        for (String key : keys) if (key.startsWith("gkd_url_custom-")) {
            String address = prefs(context).getString(key, "");
            sources.add(new Source(key.substring(8), address, "自定义在线订阅", address, true));
        }
        return sources;
    }

    private static Source source(Context context, String id) {
        for (Source source : all(context)) if (source.id.equals(id)) return source;
        throw new IllegalArgumentException("订阅不存在");
    }

    private static SharedPreferences prefs(Context context) { return context.getSharedPreferences("xguard", Context.MODE_PRIVATE); }
    private static File file(Context context, String id) { return new File(context.getFilesDir(), "gkd_" + id + ".json"); }
    private static void invalidate(Context context) { prefs(context).edit().putLong("gkd_revision", prefs(context).getLong("gkd_revision", 0) + 1).apply(); cachedRules = null; }
    private static String digest(String text) throws Exception {
        StringBuilder result = new StringBuilder();
        for (byte value : MessageDigest.getInstance("SHA-256").digest(text.getBytes(StandardCharsets.UTF_8))) result.append(String.format("%02x", value & 255));
        return result.toString();
    }

    private static final class Source {
        final String id, name, description, url;
        final boolean custom;
        Source(String id, String name, String description, String url) { this(id, name, description, url, false); }
        Source(String id, String name, String description, String url, boolean custom) {
            this.id = id; this.name = name; this.description = description; this.url = url; this.custom = custom;
        }
    }
}
