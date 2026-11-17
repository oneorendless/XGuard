package com.xuan.xguard;

import android.app.Instrumentation;
import android.os.Bundle;
import org.json.JSONArray;
import org.json.JSONObject;
import java.io.File;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;

public final class GkdInstrumentation extends Instrumentation {
    @Override public void onCreate(Bundle arguments) { super.onCreate(arguments); start(); }
    private void check(boolean value, String name) { if (!value) throw new AssertionError(name); }
    private String command(String... arguments) throws Exception { return GkdStore.handle(getTargetContext(), new JSONArray(Arrays.asList(arguments))); }
    private String subscription(String selector) {
        return "{id:1,name:'Test',version:1,apps:[{id:'com.example.test',groups:[{key:0,name:'开屏广告',rules:[{matches:" + JSONObject.quote(selector) + "}]}]}]}";
    }
    @Override public void onStart() {
        Bundle result = new Bundle();
        try {
            check(getTargetContext().getPackageName().contains("validation"), "isolated package");
            check(new JSONObject(command("gkd", "guard", "1")).getBoolean("accessibility_guard"), "guard enabled persisted");
            check(!new JSONObject(command("gkd", "guard", "0")).getBoolean("accessibility_guard"), "guard disabled persisted");
            JSONObject escaped = (JSONObject) GkdJson5.parse("{url:'https://example.com/a',text:'a\\'b',selector:'[text=\"跳过\"]',/*x*/trailing:[1,],}");
            check("a'b".equals(escaped.getString("text")), "single quote escape");
            check("https://example.com/a".equals(escaped.getString("url")), "URL preserved");
            JSONObject simple = GkdRules.compile(subscription("[text=\"跳过\"][clickable=true]"), "test");
            check(simple.getJSONArray("rules").length() == 1, "simple selector compiled");
            check(GkdRules.selector("[text=\"跳过\" || desc=\"跳过\"][text.length<12]").test(key -> "text".equals(key) ? "跳过" : "text.length".equals(key) ? 2 : null), "OR and numeric predicate");
            check(GkdRules.compile(subscription("[text=\"跳过\"] + [clickable=true]"), "test").getJSONArray("rules").length() == 0, "relationship fails closed");
            check(GkdRules.compile(subscription("[text=\"跳过\"][unknown=true]"), "test").getJSONArray("rules").length() == 0, "unknown attribute fails closed");
            check(GkdRules.compile(subscription("[text~=\".*\"]"), "test").getJSONArray("rules").length() == 0, "unsupported regex fails closed");
            String inherited = subscription("[vid=\"skip\"]").replace("key:0,", "key:0,versionCode:{minimum:1},");
            check(GkdRules.compile(inherited, "test").getJSONArray("rules").length() == 0, "inherited unsupported constraint fails closed");
            String specific = subscription("[vid=\"skip\"]").replace("key:0,", "key:0,activityIds:'.SplashActivity',actionMaximum:1,");
            JSONObject rule = GkdRules.compile(specific, "test").getJSONArray("rules").getJSONObject(0);
            check(rule.getJSONArray("group_activityIds").length() == 1 && rule.getInt("maximum") == 1, "inherited activity and maximum");
            for (String source : new String[]{"xguard-local", "lin-arm", "ganlinte", "aisouler"}) command("gkd", "toggle", source, "0");
            check(GkdStore.enabledRules(getTargetContext()).length() == 0, "all disabled stays empty");
            command("gkd", "toggle", "xguard-local", "1");
            check(GkdStore.enabledRules(getTargetContext()).length() == 3, "local source enabled");
            command("gkd", "toggle", "lin-arm", "1");
            JSONObject sources = new JSONObject(command("gkd", "sources"));
            JSONObject remote = sources.getJSONArray("list").getJSONObject(2);
            check(remote.getBoolean("enabled") && remote.getInt("count") > 0, "real online download compiled");
            File cache = new File(getTargetContext().getFilesDir(), "gkd_lin-arm.json");
            long previousSize = cache.length();
            String address = "https://raw.githubusercontent.com/Lin-arm/GKD_subscription/main/dist/gkd.json5?xguard-validation=091";
            JSONObject custom = new JSONObject(command("gkd", "add", address));
            String customId = "";
            for (int index = 0; index < custom.getJSONArray("list").length(); index++) {
                JSONObject item = custom.getJSONArray("list").getJSONObject(index);
                if (item.optBoolean("custom")) { customId = item.getString("id"); check(item.getInt("count") > 0, "custom source downloaded"); }
            }
            check(!customId.isEmpty(), "custom source persisted");
            command("gkd", "toggle", "lin-arm", "0");
            check(!new JSONObject(command("gkd", "sources")).getJSONArray("list").getJSONObject(2).getBoolean("enabled"), "independent source toggle");
            getTargetContext().getSharedPreferences("xguard", 0).edit().putString("gkd_url_" + customId, "https://raw.githubusercontent.com/oneorendless/XGuard/no-such-branch/gkd.json5").commit();
            JSONObject failed = new JSONObject(command("gkd", "update", customId));
            check(failed.getInt("failed") == 1, "failed update reported");
            check(new File(getTargetContext().getFilesDir(), "gkd_" + customId + ".json").length() > 0, "failed update retains cache");
            check(cache.length() == previousSize, "unrelated cache unchanged");
            command("gkd", "remove", customId);
            check(!new File(getTargetContext().getFilesDir(), "gkd_" + customId + ".json").exists(), "custom delete");
            result.putString("result", "PASS: JSON5 escapes, strict selectors and inherited constraints, all-disabled persistence, real preset/custom HTTPS downloads, independent toggle, failed-update cache retention");
            result.putString("remote", remote.toString());
            finish(0, result);
        } catch (Throwable error) { result.putString("result", "FAIL: " + error); android.util.Log.e("XGuardGKDTest", "test failed", error); finish(1, result); }
    }
}
