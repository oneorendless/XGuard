package com.xuan.xguard;

import org.json.JSONArray;
import org.json.JSONObject;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public final class GkdRules {
    public interface Node { Object attribute(String key); }
    public interface Predicate { boolean test(Node node); }
    private static final List<String> ATTRIBUTES = Arrays.asList("text", "desc", "id", "vid", "name", "clickable", "enabled", "visibleToUser", "checked", "checkable", "selected", "focusable", "longClickable", "childCount", "width", "height", "text.length", "desc.length");
    private static final Pattern CONDITION = Pattern.compile("\\s*([A-Za-z][A-Za-z0-9.]*)\\s*(!\\*=|!\\^=|!\\$=|!=|\\^=|\\$=|\\*=|<=|>=|=|<|>)\\s*('(?:\\\\.|[^'\\\\])*'|\"(?:\\\\.|[^\"\\\\])*\"|true|false|null|-?\\d+)\\s*");
    private static final String[] UNSUPPORTED = {"preKeys", "position", "swipeArg", "scopeKeys", "actionCdKey", "actionMaximumKey", "versionCode", "versionName", "matchRoot"};

    private GkdRules() { }

    public static JSONObject compile(String input, String sourceId) throws Exception {
        Object parsed = GkdJson5.parse(input);
        if (!(parsed instanceof JSONObject)) throw new IllegalArgumentException("需要完整 GKD 订阅对象");
        JSONObject root = (JSONObject) parsed;
        if (!(root.opt("apps") instanceof JSONArray)) throw new IllegalArgumentException("订阅缺少 apps 数组");
        JSONArray compiled = new JSONArray();
        int skipped = 0;
        JSONArray global = root.optJSONArray("globalGroups");
        if (global != null) for (int groupIndex = 0; groupIndex < global.length(); groupIndex++) {
            JSONObject group = global.optJSONObject(groupIndex);
            if (group != null && group.optJSONArray("rules") != null) skipped += group.getJSONArray("rules").length();
        }
        JSONArray apps = root.getJSONArray("apps");
        for (int appIndex = 0; appIndex < apps.length(); appIndex++) {
            JSONObject app = apps.optJSONObject(appIndex);
            if (app == null || !app.optBoolean("enable", true)) continue;
            String pkg = app.optString("id");
            if (!pkg.matches("[A-Za-z][A-Za-z0-9_]*(\\.[A-Za-z0-9_]+)+")) continue;
            JSONArray groups = app.optJSONArray("groups");
            if (groups == null) continue;
            for (int groupIndex = 0; groupIndex < groups.length(); groupIndex++) {
                JSONObject group = groups.optJSONObject(groupIndex);
                if (group == null) continue;
                JSONArray rules = group.optJSONArray("rules");
                if (rules == null) continue;
                boolean allowed = group.optBoolean("enable", true) && group.optString("name").startsWith("开屏广告") && supported(group) && categoryEnabled(root, group.optString("name"));
                for (int ruleIndex = 0; ruleIndex < rules.length(); ruleIndex++) {
                    try {
                        if (!allowed) throw new IllegalArgumentException();
                        Object raw = rules.get(ruleIndex);
                        JSONObject rule = raw instanceof String ? new JSONObject().put("matches", raw) : (JSONObject) raw;
                        if (!rule.optBoolean("enable", true) || !supported(rule)) throw new IllegalArgumentException();
                        String action = rule.optString("action", "click");
                        if (!Arrays.asList("click", "clickNode", "clickCenter").contains(action)) throw new IllegalArgumentException();
                        JSONObject item = new JSONObject();
                        for (String key : new String[]{"matches", "anyMatches", "excludeMatches", "excludeAllMatches"}) {
                            JSONArray expressions = strings(rule.opt(key));
                            for (int selectorIndex = 0; selectorIndex < expressions.length(); selectorIndex++) selector(expressions.getString(selectorIndex));
                            item.put(key, expressions);
                        }
                        if (item.getJSONArray("matches").length() + item.getJSONArray("anyMatches").length() == 0) throw new IllegalArgumentException();
                        item.put("package", pkg);
                        item.put("action", action);
                        item.put("source", sourceId);
                        item.put("key", sourceId + ":" + pkg + ":" + groupIndex + ":" + ruleIndex);
                        item.put("group", sourceId + ":" + pkg + ":" + groupIndex);
                        item.put("groupMaximum", bounded(group.optInt("actionMaximum", 2), 1, 5));
                        item.put("maximum", bounded(rule.optInt("actionMaximum", group.optInt("actionMaximum", 2)), 1, 5));
                        item.put("cooldown", bounded(rule.optLong("actionCd", group.optLong("actionCd", 800)), 650, 60000));
                        item.put("time", bounded(rule.optLong("matchTime", group.optLong("matchTime", 12000)), 1, 20000));
                        item.put("delay", bounded(rule.optLong("actionDelay", group.optLong("actionDelay", 0)), 0, 10000));
                        item.put("matchDelay", bounded(rule.optLong("matchDelay", group.optLong("matchDelay", 0)), 0, 10000));
                        for (String key : new String[]{"activityIds", "excludeActivityIds"}) {
                            item.put(key, strings(rule.opt(key)));
                            item.put("group_" + key, strings(group.opt(key)));
                        }
                        compiled.put(item);
                    } catch (Exception unsupported) { skipped++; }
                }
            }
        }
        return new JSONObject().put("name", root.optString("name", sourceId)).put("version", root.opt("version")).put("rules", compiled).put("skipped", skipped);
    }

    private static boolean categoryEnabled(JSONObject root, String name) {
        JSONArray categories = root.optJSONArray("categories");
        if (categories != null) for (int index = 0; index < categories.length(); index++) {
            JSONObject category = categories.optJSONObject(index);
            if (category != null && name.startsWith(category.optString("name", "\u0000"))) return category.optBoolean("enable", true);
        }
        return true;
    }

    private static long bounded(long value, long minimum, long maximum) {
        if (value < minimum) throw new IllegalArgumentException();
        return Math.min(value, maximum);
    }

    private static boolean supported(JSONObject rule) {
        for (String key : UNSUPPORTED) if (rule.has(key) && !rule.isNull(key)) return false;
        return !rule.has("resetMatch") || "app".equals(rule.optString("resetMatch"));
    }

    public static JSONArray strings(Object value) throws Exception {
        if (value == null || value == JSONObject.NULL) return new JSONArray();
        if (value instanceof String) return new JSONArray().put(value);
        if (!(value instanceof JSONArray)) throw new IllegalArgumentException();
        JSONArray result = (JSONArray) value;
        for (int index = 0; index < result.length(); index++) if (!(result.get(index) instanceof String)) throw new IllegalArgumentException();
        return result;
    }

    public static Predicate selector(String source) throws Exception {
        if (source.length() > 2048) throw new IllegalArgumentException();
        String text = source.trim();
        if (text.startsWith("@")) text = text.substring(1);
        Matcher classMatcher = Pattern.compile("^(\\*|[A-Za-z][A-Za-z0-9_.$]*)?").matcher(text);
        classMatcher.find();
        String className = classMatcher.group();
        int offset = classMatcher.end();
        List<Predicate> predicates = new ArrayList<>();
        if (!className.isEmpty() && !"*".equals(className)) predicates.add(node -> {
            Object name = node.attribute("name");
            return name != null && (className.equals(name.toString()) || name.toString().endsWith("." + className));
        });
        int brackets = 0;
        while (offset < text.length()) {
            while (offset < text.length() && Character.isWhitespace(text.charAt(offset))) offset++;
            if (offset >= text.length()) break;
            if (text.charAt(offset++) != '[') throw new IllegalArgumentException();
            int start = offset;
            char quote = 0; boolean escaped = false;
            while (offset < text.length()) {
                char current = text.charAt(offset);
                if (quote != 0) {
                    if (escaped) escaped = false;
                    else if (current == '\\') escaped = true;
                    else if (current == quote) quote = 0;
                } else if (current == '\'' || current == '"') quote = current;
                else if (current == ']') break;
                offset++;
            }
            if (offset >= text.length()) throw new IllegalArgumentException();
            predicates.add(new Expression(text.substring(start, offset)).parse());
            brackets++;
            offset++;
        }
        if (brackets == 0) throw new IllegalArgumentException();
        return node -> { for (Predicate predicate : predicates) if (!predicate.test(node)) return false; return true; };
    }

    private static final class Expression {
        final String text;
        int cursor;
        Expression(String text) { this.text = text; }
        Predicate parse() throws Exception {
            Predicate predicate = or();
            space();
            if (cursor != text.length()) throw new IllegalArgumentException();
            return predicate;
        }
        void space() { while (cursor < text.length() && Character.isWhitespace(text.charAt(cursor))) cursor++; }
        boolean take(String token) { space(); if (!text.startsWith(token, cursor)) return false; cursor += token.length(); return true; }
        Predicate or() throws Exception {
            Predicate result = and();
            while (take("||")) { Predicate left = result, right = and(); result = node -> left.test(node) || right.test(node); }
            return result;
        }
        Predicate and() throws Exception {
            Predicate result = atom();
            while (take("&&")) { Predicate left = result, right = atom(); result = node -> left.test(node) && right.test(node); }
            return result;
        }
        Predicate atom() throws Exception {
            if (take("!")) { Predicate child = atom(); return node -> !child.test(node); }
            if (take("(")) { Predicate child = or(); if (!take(")")) throw new IllegalArgumentException(); return child; }
            space();
            Matcher matcher = CONDITION.matcher(text);
            matcher.region(cursor, text.length());
            if (!matcher.lookingAt()) throw new IllegalArgumentException();
            cursor = matcher.end();
            String attribute = matcher.group(1), operator = matcher.group(2), literal = matcher.group(3);
            if (!ATTRIBUTES.contains(attribute)) throw new IllegalArgumentException();
            Object expected = GkdJson5.parse(literal);
            return node -> compare(node.attribute(attribute), operator, expected);
        }
    }

    private static boolean compare(Object actual, String operator, Object expected) {
        if (expected == JSONObject.NULL) expected = null;
        if ("=".equals(operator)) return expected == null ? actual == null : expected.equals(actual) || expected instanceof Number && actual instanceof Number && ((Number) expected).doubleValue() == ((Number) actual).doubleValue();
        if ("!=".equals(operator)) return !compare(actual, "=", expected);
        if (actual instanceof Number && expected instanceof Number) {
            double left = ((Number) actual).doubleValue(), right = ((Number) expected).doubleValue();
            if ("<".equals(operator)) return left < right;
            if (">".equals(operator)) return left > right;
            if ("<=".equals(operator)) return left <= right;
            if (">=".equals(operator)) return left >= right;
        }
        if (!(actual instanceof String) || !(expected instanceof String)) return false;
        String left = (String) actual, right = (String) expected;
        if ("*=".equals(operator)) return left.contains(right);
        if ("^=".equals(operator)) return left.startsWith(right);
        if ("$=".equals(operator)) return left.endsWith(right);
        if ("!*=".equals(operator)) return !left.contains(right);
        if ("!^=".equals(operator)) return !left.startsWith(right);
        if ("!$=".equals(operator)) return !left.endsWith(right);
        return false;
    }
}
