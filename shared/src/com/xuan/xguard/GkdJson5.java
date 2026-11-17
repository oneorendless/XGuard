package com.xuan.xguard;

import org.json.JSONArray;
import org.json.JSONObject;

public final class GkdJson5 {
    private final String input;
    private int cursor;
    private int values;

    private GkdJson5(String input) { this.input = input; }

    public static Object parse(String text) throws Exception {
        GkdJson5 parser = new GkdJson5(text);
        Object value = parser.value(0);
        parser.space();
        if (parser.cursor != text.length()) throw parser.error();
        return value;
    }

    private IllegalArgumentException error() { return new IllegalArgumentException("JSON5 格式错误，位置 " + cursor); }

    private void space() {
        while (cursor < input.length()) {
            char current = input.charAt(cursor);
            if (Character.isWhitespace(current) || current == '\ufeff') { cursor++; continue; }
            if (input.startsWith("//", cursor)) {
                while (cursor < input.length() && input.charAt(cursor) != '\n') cursor++;
                continue;
            }
            if (input.startsWith("/*", cursor)) {
                int end = input.indexOf("*/", cursor + 2);
                if (end < 0) throw error();
                cursor = end + 2;
                continue;
            }
            break;
        }
    }

    private boolean take(char token) {
        space();
        if (cursor < input.length() && input.charAt(cursor) == token) { cursor++; return true; }
        return false;
    }

    private void require(char token) { if (!take(token)) throw error(); }

    private Object value(int depth) throws Exception {
        if (depth > 64 || ++values > 500000) throw new IllegalArgumentException("订阅结构过大");
        space();
        if (cursor >= input.length()) throw error();
        char current = input.charAt(cursor);
        if (current == '{') {
            cursor++;
            JSONObject object = new JSONObject();
            if (take('}')) return object;
            do {
                space();
                String key;
                if (cursor < input.length() && (input.charAt(cursor) == '"' || input.charAt(cursor) == '\'')) key = string();
                else {
                    int start = cursor;
                    while (cursor < input.length() && (Character.isLetterOrDigit(input.charAt(cursor)) || "_$".indexOf(input.charAt(cursor)) >= 0)) cursor++;
                    if (start == cursor) throw error();
                    key = input.substring(start, cursor);
                }
                require(':');
                if (object.has(key)) throw new IllegalArgumentException("订阅含重复字段：" + key);
                object.put(key, value(depth + 1));
                if (take('}')) return object;
                require(',');
                if (take('}')) return object;
            } while (true);
        }
        if (current == '[') {
            cursor++;
            JSONArray array = new JSONArray();
            if (take(']')) return array;
            do {
                array.put(value(depth + 1));
                if (take(']')) return array;
                require(',');
                if (take(']')) return array;
            } while (true);
        }
        if (current == '"' || current == '\'') return string();
        int start = cursor;
        while (cursor < input.length() && !Character.isWhitespace(input.charAt(cursor)) && ",]}".indexOf(input.charAt(cursor)) < 0 && input.charAt(cursor) != '/') cursor++;
        String token = input.substring(start, cursor);
        if ("true".equals(token)) return true;
        if ("false".equals(token)) return false;
        if ("null".equals(token)) return JSONObject.NULL;
        try {
            if (token.matches("[+-]?0[xX][0-9a-fA-F]+")) return Long.decode(token);
            if (token.matches("[+-]?[0-9]+")) return Long.parseLong(token);
            if (token.matches("[+-]?(?:[0-9]+\\.?[0-9]*|\\.[0-9]+)(?:[eE][+-]?[0-9]+)?")) {
                double number = Double.parseDouble(token);
                if (Double.isInfinite(number) || Double.isNaN(number)) throw error();
                return number;
            }
        } catch (NumberFormatException ignored) { throw error(); }
        throw error();
    }

    private String string() {
        char quote = input.charAt(cursor++);
        StringBuilder result = new StringBuilder();
        while (cursor < input.length()) {
            char current = input.charAt(cursor++);
            if (current == quote) return result.toString();
            if (current == '\n' || current == '\r') throw error();
            if (current != '\\') { result.append(current); continue; }
            if (cursor >= input.length()) throw error();
            char escaped = input.charAt(cursor++);
            switch (escaped) {
                case 'n': result.append('\n'); break;
                case 'r': result.append('\r'); break;
                case 't': result.append('\t'); break;
                case 'b': result.append('\b'); break;
                case 'f': result.append('\f'); break;
                case 'v': result.append('\u000b'); break;
                case '0': result.append('\0'); break;
                case '\r': if (cursor < input.length() && input.charAt(cursor) == '\n') cursor++; break;
                case '\n': break;
                case 'u': result.append(hex(4)); break;
                case 'x': result.append(hex(2)); break;
                default: result.append(escaped);
            }
        }
        throw error();
    }

    private char hex(int digits) {
        if (cursor + digits > input.length()) throw error();
        try {
            char result = (char) Integer.parseInt(input.substring(cursor, cursor + digits), 16);
            cursor += digits;
            return result;
        } catch (NumberFormatException ignored) { throw error(); }
    }
}
