package com.xuan.xguard;

import android.accessibilityservice.AccessibilityService;
import android.accessibilityservice.GestureDescription;
import android.app.KeyguardManager;
import android.content.ComponentName;
import android.content.pm.ActivityInfo;
import android.content.pm.PackageManager;
import android.graphics.Path;
import android.graphics.Rect;
import android.os.Build;
import android.os.Handler;
import android.os.PowerManager;
import android.view.accessibility.AccessibilityEvent;
import android.view.accessibility.AccessibilityNodeInfo;
import org.json.JSONArray;
import org.json.JSONObject;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

public final class XGuardAccessibilityService extends AccessibilityService {
    private final Handler handler = new Handler();
    private final Map<String, GkdRules.Predicate> predicates = new HashMap<>();
    private final Map<String, Integer> counts = new HashMap<>();
    private final Map<String, Long> actions = new HashMap<>();
    private final Map<String, Long> firstMatches = new HashMap<>();
    private final Runnable scanTask = this::scan;
    private String foreground = "";
    private String activity = "";
    private long started;
    private long lastScan;
    private long lastAction;
    private long scheduledAt;
    private JSONArray loadedRules;
    private final Map<String, List<JSONObject>> packageRules = new HashMap<>();

    @Override protected void onServiceConnected() {
        super.onServiceConnected();
        getSharedPreferences("xguard", MODE_PRIVATE).edit().putBoolean("gkd_accessibility_ever_connected", true).apply();
    }

    @Override public void onAccessibilityEvent(AccessibilityEvent event) {
        if (event == null || event.getPackageName() == null) return;
        String pkg = event.getPackageName().toString();
        refreshRules();
        if (event.getEventType() == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED && isActivity(pkg, event.getClassName())) {
            if (!foreground.equals(pkg)) {
                foreground = pkg;
                started = android.os.SystemClock.uptimeMillis();
                counts.clear();
                actions.clear();
                firstMatches.clear();
            }
            activity = event.getClassName().toString();
        }
        if (!pkg.equals(foreground) || pkg.equals(getPackageName()) || GkdStore.isAllowlisted(this, pkg) || !packageRules.containsKey(pkg)
            || android.os.SystemClock.uptimeMillis() - started > 20000) return;
        schedule(Math.max(80, 250 - (android.os.SystemClock.uptimeMillis() - lastScan)));
    }

    private boolean isActivity(String pkg, CharSequence name) {
        if (name == null) return false;
        try {
            getPackageManager().getActivityInfo(new ComponentName(pkg, name.toString()), 0);
            return true;
        } catch (PackageManager.NameNotFoundException ignored) { return false; }
    }

    private void schedule(long delay) {
        long when = android.os.SystemClock.uptimeMillis() + delay;
        if (scheduledAt != 0 && scheduledAt <= when) return;
        handler.removeCallbacks(scanTask);
        scheduledAt = when;
        handler.postDelayed(scanTask, delay);
    }

    private void refreshRules() {
        JSONArray rules = GkdStore.enabledRules(this);
        if (rules == loadedRules) return;
        predicates.clear();
        packageRules.clear();
        loadedRules = rules;
        for (int index = 0; index < rules.length(); index++) {
            JSONObject rule = rules.optJSONObject(index);
            if (rule == null) continue;
            String pkg = rule.optString("package");
            if (!packageRules.containsKey(pkg)) packageRules.put(pkg, new ArrayList<>());
            packageRules.get(pkg).add(rule);
        }
    }

    private void scan() {
        long now = android.os.SystemClock.uptimeMillis();
        scheduledAt = 0;
        lastScan = now;
        if (now - started > 20000 || foreground.isEmpty() || foreground.equals(getPackageName())) return;
        if (now - lastAction < 650) { schedule(650 - (now - lastAction)); return; }
        PowerManager power = (PowerManager) getSystemService(POWER_SERVICE);
        KeyguardManager keyguard = (KeyguardManager) getSystemService(KEYGUARD_SERVICE);
        if (!power.isInteractive() || keyguard.isKeyguardLocked()) return;
        refreshRules();
        if (GkdStore.isAllowlisted(this, foreground)) return;
        List<JSONObject> rules = packageRules.get(foreground);
        if (rules == null) return;
        List<JSONObject> applicable = new ArrayList<>();
        for (JSONObject rule : rules) if (eligible(rule, now)) applicable.add(rule);
        if (applicable.isEmpty()) return;
        AccessibilityNodeInfo root = getRootInActiveWindow();
        if (root == null) return;
        List<AccessibilityNodeInfo> nodes = new ArrayList<>();
        nodes.add(root);
        try {
            if (!foreground.equals(String.valueOf(root.getPackageName()))) return;
            if (!collect(root, nodes, 0)) return;
            for (JSONObject rule : applicable) {
                AccessibilityNodeInfo target = target(rule, nodes);
                String key = rule.optString("key");
                if (target == null) { firstMatches.remove(key); continue; }
                long first = firstMatches.containsKey(key) ? firstMatches.get(key) : now;
                firstMatches.put(key, first);
                long remaining = rule.optLong("delay") - (now - first);
                if (remaining > 0) { schedule(remaining); continue; }
                if (GkdStore.isAllowlisted(this, foreground)) return;
                if (!click(target, rule.optString("action"))) continue;
                lastAction = now;
                String group = rule.optString("group");
                counts.put(key, counts.containsKey(key) ? counts.get(key) + 1 : 1);
                counts.put(group, counts.containsKey(group) ? counts.get(group) + 1 : 1);
                actions.put(key, now);
                firstMatches.remove(key);
                getSharedPreferences("xguard", MODE_PRIVATE).edit()
                    .putString("gkd_last_action", foreground + " · " + rule.optString("source"))
                    .putLong("gkd_last_action_at", System.currentTimeMillis()).apply();
                schedule(Math.max(650, rule.optLong("cooldown")));
                break;
            }
        } catch (Exception error) {
            android.util.Log.w("XGuardGKD", "Rule evaluation failed", error);
        } finally {
            for (AccessibilityNodeInfo node : nodes) node.recycle();
        }
    }

    private boolean eligible(JSONObject rule, long now) {
        String key = rule.optString("key"), group = rule.optString("group");
        if (counts.containsKey(key) && counts.get(key) >= rule.optInt("maximum", 2)) return false;
        if (counts.containsKey(group) && counts.get(group) >= rule.optInt("groupMaximum", 2)) return false;
        if (actions.containsKey(key) && now - actions.get(key) < rule.optLong("cooldown", 800)) return false;
        if (now - started > rule.optLong("time", 12000) || now - started < rule.optLong("matchDelay")) return false;
        return activityMatch(rule.optJSONArray("activityIds"), false)
            && activityMatch(rule.optJSONArray("group_activityIds"), false)
            && activityMatch(rule.optJSONArray("excludeActivityIds"), true)
            && activityMatch(rule.optJSONArray("group_excludeActivityIds"), true);
    }

    private boolean activityMatch(JSONArray names, boolean excluded) {
        if (names == null || names.length() == 0) return true;
        boolean found = false;
        for (int index = 0; index < names.length(); index++) {
            String name = names.optString(index);
            if (name.startsWith(".")) name = foreground + name;
            if (name.equals(activity)) found = true;
        }
        return excluded ? !found : found;
    }

    private boolean collect(AccessibilityNodeInfo node, List<AccessibilityNodeInfo> nodes, int depth) {
        if (node.isEditable() || node.isPassword()) return true;
        if (depth >= 32 || nodes.size() >= 900) return node.getChildCount() == 0;
        for (int index = 0; index < node.getChildCount(); index++) {
            if (nodes.size() >= 900) return false;
            AccessibilityNodeInfo child = node.getChild(index);
            if (child == null) continue;
            nodes.add(child);
            if (!collect(child, nodes, depth + 1)) return false;
        }
        return true;
    }

    private AccessibilityNodeInfo find(String selector, List<AccessibilityNodeInfo> nodes) throws Exception {
        GkdRules.Predicate predicate = predicates.get(selector);
        if (predicate == null) { predicate = GkdRules.selector(selector); predicates.put(selector, predicate); }
        for (AccessibilityNodeInfo node : nodes) {
            if (node.isVisibleToUser() && node.isEnabled() && !node.isEditable() && !node.isPassword() && predicate.test(new Adapter(node))) return node;
        }
        return null;
    }

    private AccessibilityNodeInfo target(JSONObject rule, List<AccessibilityNodeInfo> nodes) throws Exception {
        JSONArray excluded = rule.getJSONArray("excludeMatches");
        for (int index = 0; index < excluded.length(); index++) if (find(excluded.getString(index), nodes) != null) return null;
        JSONArray allExcluded = rule.getJSONArray("excludeAllMatches");
        boolean all = allExcluded.length() > 0;
        for (int index = 0; index < allExcluded.length(); index++) if (find(allExcluded.getString(index), nodes) == null) all = false;
        if (all) return null;
        AccessibilityNodeInfo target = null;
        JSONArray matches = rule.getJSONArray("matches");
        for (int index = 0; index < matches.length(); index++) {
            target = find(matches.getString(index), nodes);
            if (target == null) return null;
        }
        JSONArray any = rule.getJSONArray("anyMatches");
        if (any.length() > 0) {
            AccessibilityNodeInfo found = null;
            for (int index = 0; index < any.length() && found == null; index++) found = find(any.getString(index), nodes);
            if (found == null) return null;
            target = found;
        }
        return target;
    }

    private boolean click(AccessibilityNodeInfo node, String action) {
        if (!"clickCenter".equals(action) && node.performAction(AccessibilityNodeInfo.ACTION_CLICK)) return true;
        if ("clickNode".equals(action)) return false;
        if (!"clickCenter".equals(action)) {
            AccessibilityNodeInfo parent = node.getParent();
            for (int depth = 0; parent != null && depth < 3; depth++) {
                AccessibilityNodeInfo next = null;
                try {
                    if (parent.isClickable() && parent.isEnabled() && !parent.isEditable() && !parent.isPassword() && parent.performAction(AccessibilityNodeInfo.ACTION_CLICK)) return true;
                    next = parent.getParent();
                } finally { parent.recycle(); }
                parent = next;
            }
            if (parent != null) parent.recycle();
        }
        if (Build.VERSION.SDK_INT < 24) return false;
        Rect bounds = new Rect(); node.getBoundsInScreen(bounds);
        Rect screen = new Rect(0, 0, getResources().getDisplayMetrics().widthPixels, getResources().getDisplayMetrics().heightPixels);
        if (!bounds.intersect(screen) || bounds.isEmpty()) return false;
        Path path = new Path(); path.moveTo(bounds.exactCenterX(), bounds.exactCenterY());
        return dispatchGesture(new GestureDescription.Builder().addStroke(new GestureDescription.StrokeDescription(path, 0, 60)).build(), null, null);
    }

    private static final class Adapter implements GkdRules.Node {
        final AccessibilityNodeInfo node;
        Adapter(AccessibilityNodeInfo node) { this.node = node; }
        private String string(CharSequence value) { return value == null ? null : value.toString(); }
        public Object attribute(String key) {
            switch (key) {
                case "text": return string(node.getText());
                case "desc": return string(node.getContentDescription());
                case "id": return node.getViewIdResourceName();
                case "vid": String id = node.getViewIdResourceName(); return id == null ? null : id.substring(id.lastIndexOf('/') + 1);
                case "name": return string(node.getClassName());
                case "clickable": return node.isClickable();
                case "enabled": return node.isEnabled();
                case "visibleToUser": return node.isVisibleToUser();
                case "checked": return node.isChecked();
                case "checkable": return node.isCheckable();
                case "selected": return node.isSelected();
                case "focusable": return node.isFocusable();
                case "longClickable": return node.isLongClickable();
                case "childCount": return node.getChildCount();
                case "text.length": return node.getText() == null ? 0 : node.getText().length();
                case "desc.length": return node.getContentDescription() == null ? 0 : node.getContentDescription().length();
                case "width": case "height":
                    Rect bounds = new Rect(); node.getBoundsInScreen(bounds);
                    return "width".equals(key) ? bounds.width() : bounds.height();
                default: return null;
            }
        }
    }

    @Override public void onInterrupt() { handler.removeCallbacks(scanTask); scheduledAt = 0L; }
    @Override public void onDestroy() { handler.removeCallbacks(scanTask); scheduledAt = 0L; super.onDestroy(); }
}
