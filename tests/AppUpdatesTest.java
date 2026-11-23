package com.xuan.xguard;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Paths;
import org.json.JSONArray;
import org.json.JSONObject;

public final class AppUpdatesTest {
    private static final String BASE = "https://github.com/oneorendless/XGuard/releases/download/";

    private static void expect(JSONObject release, String installed, boolean vpn, String state, String url) throws Exception {
        JSONObject result = AppUpdates.selectRelease(release, installed, vpn);
        if (!state.equals(result.getString("state")) || !url.equals(result.optString("url"))) throw new AssertionError(result);
    }

    private static JSONObject asset(String tag, String suffix) throws Exception {
        String name = "XGuard-" + tag + suffix;
        return new JSONObject().put("name", name).put("state", "uploaded").put("size", 100)
                .put("browser_download_url", BASE + tag + "/" + name);
    }

    public static void main(String[] args) throws Exception {
        String tag = "v0.9.10";
        JSONObject root = asset(tag, "-module.zip"), vpn = asset(tag, "-no-root.apk"), companion = asset(tag, "-root.apk");
        JSONObject release = new JSONObject().put("tag_name", tag).put("draft", false).put("prerelease", false)
                .put("assets", new JSONArray().put(companion).put(vpn).put(root));
        expect(release, "0.9.9", false, "available", root.getString("browser_download_url"));
        expect(release, "0.9.9-noroot", true, "available", vpn.getString("browser_download_url"));
        expect(release, "0.9.10-noroot", true, "current", "");
        expect(release, "0.10.0", false, "current", "");
        expect(release.put("draft", true), "0.9.9", false, "current", "");
        expect(release.put("draft", false).put("prerelease", true), "0.9.9", false, "current", "");
        release.put("prerelease", false);
        root.put("browser_download_url", "https://example.org/invalid.zip");
        expect(release, "0.9.9", false, "missing", "");
        vpn.put("state", "starter");
        expect(release, "0.9.9-noroot", true, "missing", "");
        expect(release.put("assets", new JSONArray().put(companion)), "0.9.9", false, "missing", "");
        if (args.length == 1) {
            JSONObject live = new JSONObject(new String(Files.readAllBytes(Paths.get(args[0])), StandardCharsets.UTF_8));
            String liveTag = live.getString("tag_name");
            expect(live, "0.8.0", false, "available", asset(liveTag, "-module.zip").getString("browser_download_url"));
            expect(live, "0.8.0-noroot", true, "available", asset(liveTag, "-no-root.apk").getString("browser_download_url"));
        }
        System.out.println("PASS: numeric version ordering, edition matching, release eligibility and official asset validation");
    }
}
