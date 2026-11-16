package com.xuan.xguard;

import android.content.Context;
import android.content.SharedPreferences;
import android.util.AtomicFile;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.Collections;
import java.util.HashSet;
import java.util.Set;
import java.util.TreeSet;
import org.json.JSONArray;
import org.json.JSONObject;

final class RecoveryStore {
    private RecoveryStore() { }
    static SharedPreferences prefs(Context context) { return context.getSharedPreferences("xguard", Context.MODE_PRIVATE); }
    static long pausedUntil(Context context) { return prefs(context).getLong("pause_until", 0); }
    static boolean isPaused(Context context) { return pausedUntil(context) > System.currentTimeMillis() / 1000L; }
    private static File directory(Context context, String name) { return new File(context.getFilesDir(), "recovery_" + name); }
    private static String selection(Context context) { return new TreeSet<>(enabledSources(context)).toString(); }
    static Set<String> enabledSources(Context context) {
        Set<String> result = new HashSet<>(prefs(context).getStringSet("enabled_sources", Collections.emptySet()));
        if (result.isEmpty()) Collections.addAll(result,"baseline","awavenue","antiad","goodbyeads","adaway");
        return result;
    }
    private static Set<String> domains(SharedPreferences prefs, String key) { return new HashSet<>(prefs.getStringSet(key, Collections.emptySet())); }
    private static String fingerprint(SharedPreferences prefs) { return new TreeSet<>(domains(prefs, "custom_allow")).toString() + "\n" + new TreeSet<>(domains(prefs, "custom_block")).toString(); }

    static void write(File target, byte[] bytes) throws IOException {
        AtomicFile file = new AtomicFile(target); FileOutputStream stream = null;
        try { stream = file.startWrite(); stream.write(bytes); file.finishWrite(stream); }
        catch (IOException error) { if (stream != null) file.failWrite(stream); throw error; }
    }
    static byte[] read(File file) throws IOException {
        try (FileInputStream stream = new FileInputStream(file); java.io.ByteArrayOutputStream result = new java.io.ByteArrayOutputStream()) {
            byte[] buffer = new byte[8192]; int n; while ((n = stream.read(buffer)) != -1) result.write(buffer, 0, n); return result.toByteArray();
        }
    }
    private static File[] sourceFiles(Context context) { File[] files = context.getFilesDir().listFiles(f -> f.isFile() && f.getName().matches("source_[a-z0-9_]+\\.list")); return files == null ? new File[0] : files; }
    private static void erase(File file) throws IOException {
        File[] children = file.listFiles(); if (children != null) for (File child : children) erase(child);
        if (file.exists() && !file.delete()) throw new IOException("无法清理规则快照");
    }
    private static void copy(File source, File target) throws IOException { write(target, read(source)); }
    private static JSONObject metadata(Context context, String name) throws Exception {
        File file = new File(directory(context, name), "meta.json"); return file.isFile() ? new JSONObject(new String(read(file), StandardCharsets.UTF_8)) : new JSONObject();
    }
    static synchronized void beginUpdate(Context context) throws Exception {
        File stage = directory(context, "pending"); erase(stage);
        if (!stage.mkdirs()) throw new IOException("无法创建规则快照");
        for (File source : sourceFiles(context)) copy(source, new File(stage, source.getName()));
        JSONObject meta = new JSONObject(); meta.put("time", System.currentTimeMillis() / 1000L); meta.put("selection", selection(context));
        write(new File(stage, "meta.json"), meta.toString().getBytes(StandardCharsets.UTF_8));
    }
    static synchronized JSONObject finishUpdate(Context context, Set<String> before) throws Exception {
        Set<String> after = XGuardVpnService.ruleSnapshot(context);
        Set<String> added = new HashSet<>(after); added.removeAll(before);
        Set<String> removed = new HashSet<>(before); removed.removeAll(after);
        JSONObject diff = new JSONObject(); diff.put("added", added.size()); diff.put("removed", removed.size()); diff.put("time", System.currentTimeMillis() / 1000L);
        File stage = directory(context, "pending"); boolean changed = false;
        for (File source : sourceFiles(context)) { File old = new File(stage, source.getName()); if (!old.isFile() || !Arrays.equals(read(source), read(old))) { changed = true; break; } }
        if (changed) {
            File old = directory(context, "previous"), retired = directory(context, "retired"); erase(retired);
            if (old.exists() && !old.renameTo(retired)) throw new IOException("无法替换旧规则快照");
            if (!stage.renameTo(old)) { retired.renameTo(old); throw new IOException("无法保存规则快照"); }
            try { erase(retired); } catch(IOException ignored) { /* Current snapshot is already committed. */ }
        } else erase(stage);
        prefs(context).edit().putString("last_rule_diff", diff.toString()).apply();
        return diff;
    }
    static synchronized void cancelUpdate(Context context) throws IOException { erase(directory(context, "pending")); }
    static synchronized void abortUpdate(Context context) throws Exception {
        File pending=directory(context,"pending");
        if(new File(pending,"meta.json").isFile()) { restoreSources(context,pending); XGuardVpnService.reloadRules(context); }
        cancelUpdate(context);
    }
    static synchronized void rollback(Context context) throws Exception {
        File old = directory(context, "previous"); JSONObject meta = metadata(context, "previous");
        if (!meta.has("time")) throw new IOException("尚无可用的更新前快照");
        if (!selection(context).equals(meta.optString("selection"))) throw new IOException("来源选择已改变，请先恢复更新时的来源选择");
        beginUpdate(context);
        try {
            restoreSources(context, old);
            XGuardVpnService.reloadRules(context);
            prefs(context).edit().putLong("update_hold_until", System.currentTimeMillis()/1000L + 86400).putString("last_update_result", "rollback").apply();
        } catch (Exception error) { restoreSources(context, directory(context, "pending")); XGuardVpnService.reloadRules(context); throw error; }
        finally { cancelUpdate(context); }
    }
    private static void restoreSources(Context context, File from) throws IOException {
        // Stage and validate every copy before deleting any currently used source.
        File[] files = from.listFiles(f -> f.getName().matches("source_[a-z0-9_]+\\.list"));
        if (files == null) throw new IOException("规则快照不可读取");
        for (File file : files) copy(file, new File(context.getFilesDir(), file.getName() + ".restore"));
        for (File file : files) { File staged = new File(context.getFilesDir(), file.getName() + ".restore"); if (!staged.renameTo(new File(context.getFilesDir(), file.getName()))) throw new IOException("恢复规则缓存失败"); }
        Set<String> kept = new HashSet<>(); for (File file : files) kept.add(file.getName());
        for (File file : sourceFiles(context)) if (!kept.contains(file.getName()) && !file.delete()) throw new IOException("恢复规则缓存失败");
    }
    static synchronized void domainChange(Context context, String kind, String op, String raw) throws Exception {
        String domain = raw.toLowerCase(java.util.Locale.US).trim();
        if (!domain.matches("(?:\\*\\.)?[a-z0-9_](?:[a-z0-9_.-]*[a-z0-9_])?") || domain.length()>253 || domain.contains("..") || (domain.startsWith("*.") && !"allow".equals(kind))) throw new IllegalArgumentException("无效域名");
        if (!"add".equals(op) && !"remove".equals(op)) throw new IllegalArgumentException("无效操作");
        SharedPreferences prefs = prefs(context);
        Set<String> allow = domains(prefs,"custom_allow"), block = domains(prefs,"custom_block");
        JSONObject undo = new JSONObject(); undo.put("allow",new JSONArray(allow)); undo.put("block",new JSONArray(block));
        Set<String> target = "allow".equals(kind) ? allow : block;
        if ("block".equals(kind) && "add".equals(op)) {
            String suffix=domain;
            while (true) {
                if (allow.contains(suffix) && !suffix.equals(domain) || allow.contains("*."+suffix)) throw new IOException("请先移除覆盖该域名的放行规则，再封禁此域名");
                int dot=suffix.indexOf('.'); if (dot<0) break; suffix=suffix.substring(dot+1);
            }
        }
        if ("add".equals(op)) { target.add(domain); ("allow".equals(kind)?block:allow).remove(domain); } else target.remove(domain);
        String after = new TreeSet<>(allow).toString() + "\n" + new TreeSet<>(block).toString(); undo.put("after",after);
        Set<String> originalAllow=domains(prefs,"custom_allow"), originalBlock=domains(prefs,"custom_block"); String previousUndo=prefs.getString("domain_undo", "");
        if (!prefs.edit().putStringSet("custom_allow",allow).putStringSet("custom_block",block).putString("domain_undo",undo.toString()).commit()) {
            prefs.edit().putStringSet("custom_allow",originalAllow).putStringSet("custom_block",originalBlock).putString("domain_undo",previousUndo).commit();
            throw new IOException("保存名单失败，原名单已保留");
        }
    }
    static synchronized void undoDomain(Context context) throws Exception {
        SharedPreferences prefs = prefs(context); String saved = prefs.getString("domain_undo", "");
        if (saved.isEmpty()) throw new IOException("暂无可撤销的域名操作");
        JSONObject undo = new JSONObject(saved);
        if (!fingerprint(prefs).equals(undo.getString("after"))) throw new IOException("域名名单已变更，请手动调整");
        Set<String> allow = new HashSet<>(), block = new HashSet<>();
        JSONArray a=undo.getJSONArray("allow"), b=undo.getJSONArray("block");
        for (int i=0;i<a.length();i++) allow.add(a.getString(i)); for(int i=0;i<b.length();i++) block.add(b.getString(i));
        if (!prefs.edit().putStringSet("custom_allow",allow).putStringSet("custom_block",block).remove("domain_undo").commit()) throw new IOException("保存名单失败");
    }
    static synchronized JSONObject status(Context context) throws Exception {
        JSONObject result = new JSONObject(); SharedPreferences prefs = prefs(context);
        result.put("pause_until",isPaused(context)?pausedUntil(context):0); result.put("backup_time", metadata(context,"previous").optLong("time"));
        result.put("update_hold_until",prefs.getLong("update_hold_until",0)); result.put("undo_available",!prefs.getString("domain_undo", "").isEmpty());
        JSONObject diff = new JSONObject(prefs.getString("last_rule_diff","{}")); result.put("update_added",diff.optInt("added")); result.put("update_removed",diff.optInt("removed")); result.put("update_time",diff.optLong("time"));
        return result;
    }
}
