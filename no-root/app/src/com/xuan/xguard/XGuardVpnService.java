package com.xuan.xguard;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.content.SharedPreferences;
import android.net.VpnService;
import android.os.Build;
import android.os.ParcelFileDescriptor;
import java.io.BufferedReader;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.InputStreamReader;
import java.net.DatagramPacket;
import java.net.DatagramSocket;
import java.net.InetAddress;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import org.json.JSONArray;
import org.json.JSONObject;

public final class XGuardVpnService extends VpnService {
    private static final String CHANNEL = "xguard-protection";
    private static final int NOTIFICATION_ID = 8303;
    private static final String DNS_IP = "10.231.0.1";
    private static final Set<String> RULES = new HashSet<>();
    private static final List<ActivityItem> ACTIVITY = new ArrayList<>();
    private static boolean rulesLoaded;
    private static volatile boolean running;
    private ParcelFileDescriptor tunnel;
    private Thread worker;

    @Override public void onCreate() {
        super.onCreate();
        loadRules(this);
        createChannel();
        if (Build.VERSION.SDK_INT >= 34) startForeground(NOTIFICATION_ID, notification(), ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE);
        else if (Build.VERSION.SDK_INT >= 29) startForeground(NOTIFICATION_ID, notification(), 0);
        else startForeground(NOTIFICATION_ID, notification());
    }

    @Override public int onStartCommand(Intent intent, int flags, int startId) {
        if (worker == null || !worker.isAlive()) {
            try {
                tunnel = new Builder().setSession("XGuard").setMtu(1500).addAddress("10.231.0.2", 32).addDnsServer(DNS_IP).addRoute(DNS_IP, 32).establish();
                if (tunnel != null) {
                    running = true;
                    worker = new Thread(this::readPackets, "xguard-dns-vpn");
                    worker.start();
                }
            } catch (Exception error) {
                running = false;
            }
        }
        return START_STICKY;
    }

    @Override public void onTaskRemoved(Intent rootIntent) {
        Intent restart = new Intent(getApplicationContext(), XGuardVpnService.class);
        if (Build.VERSION.SDK_INT >= 26) startForegroundService(restart); else startService(restart);
        super.onTaskRemoved(rootIntent);
    }

    @Override public void onDestroy() {
        running = false;
        if (worker != null) worker.interrupt();
        closeTunnel();
        super.onDestroy();
    }

    @Override public void onRevoke() {
        running = false;
        closeTunnel();
        stopSelf();
        super.onRevoke();
    }

    public static boolean isRunning() { return running; }

    public static int ruleCount(Context context) {
        loadRules(context);
        return RULES.size();
    }

    public static synchronized void reloadRules(Context context) {
        RULES.clear();
        SharedPreferences prefs = context.getSharedPreferences("xguard", MODE_PRIVATE);
        Set<String> enabled = new HashSet<>(prefs.getStringSet("enabled_sources", Collections.emptySet()));
        if (enabled.isEmpty()) { enabled.add("baseline"); enabled.add("awavenue"); enabled.add("antiad"); enabled.add("goodbyeads"); enabled.add("adaway"); }
        if (enabled.contains("baseline")) loadAsset(context, "blocklist.txt");
        if (enabled.contains("httpdns")) loadAsset(context, "httpdns.list");
        for (String id : enabled) if (!"baseline".equals(id) && !"httpdns".equals(id)) loadFile(context, new File(context.getFilesDir(), "source_" + id + ".list"));
        rulesLoaded = true;
    }

    public static int countSourceFile(Context context, String id) { return countSourceFile(new File(context.getFilesDir(), "source_" + id + ".list")); }
    public static int countSourceFile(File file) { Set<String> values = new HashSet<>(); loadFile(file, values); return values.size(); }
    public static int countAsset(Context context, String name) { Set<String> values = new HashSet<>(); try (BufferedReader reader = new BufferedReader(new InputStreamReader(context.getAssets().open(name), StandardCharsets.UTF_8))) { String line; while ((line = reader.readLine()) != null) addRuleLine(line, values); } catch (Exception ignored) { } return values.size(); }

    public static boolean isAllowed(Context context, String domain) {
        String normalized = normalize(domain);
        Set<String> allow = context.getSharedPreferences("xguard", MODE_PRIVATE).getStringSet("custom_allow", Collections.emptySet());
        return matches(allow, normalized);
    }

    public static boolean isBlocked(Context context, String domain) {
        String normalized = normalize(domain);
        if (isAllowed(context, normalized)) return false;
        Set<String> custom = context.getSharedPreferences("xguard", MODE_PRIVATE).getStringSet("custom_block", Collections.emptySet());
        if (matches(custom, normalized)) return true;
        loadRules(context);
        return matches(RULES, normalized);
    }

    public static synchronized void clearActivity() { ACTIVITY.clear(); }

    public static synchronized JSONObject activityJson(Context context) throws Exception {
        JSONObject collector = new JSONObject();
        collector.put("running", running);
        collector.put("enabled", context.getSharedPreferences("xguard", MODE_PRIVATE).getBoolean("collector", true));
        collector.put("error", running ? "" : "请开启本地 VPN 防护");
        JSONObject snapshot = new JSONObject();
        snapshot.put("updated", ACTIVITY.isEmpty() ? 0 : ACTIVITY.get(ACTIVITY.size() - 1).time / 1000L);
        JSONArray items = new JSONArray();
        for (ActivityItem item : ACTIVITY) items.put(item.json());
        snapshot.put("items", items);
        JSONObject result = new JSONObject(); result.put("collector", collector); result.put("snapshot", snapshot); return result;
    }

    private void readPackets() {
        byte[] packet = new byte[32767];
        try (FileInputStream input = new FileInputStream(tunnel.getFileDescriptor()); FileOutputStream output = new FileOutputStream(tunnel.getFileDescriptor())) {
            while (running && !Thread.currentThread().isInterrupted()) {
                int length = input.read(packet);
                if (length <= 0) continue;
                DnsQuery query = parseQuery(packet, length);
                if (query == null) continue;
                boolean blocked = isBlocked(this, query.name);
                record(query.name, blocked);
                byte[] dns = blocked ? blockedResponse(query) : forward(query.payload, query.payloadLength);
                if (dns == null) dns = failureResponse(query);
                byte[] response = wrapResponse(packet, length, query, dns);
                if (response != null) output.write(response);
            }
        } catch (Exception ignored) {
            running = false;
        }
    }

    private byte[] forward(byte[] payload, int length) {
        String[] upstreams = {"223.5.5.5", "1.1.1.1", "8.8.8.8"};
        for (String upstream : upstreams) {
            DatagramSocket socket = null;
            try {
                socket = new DatagramSocket();
                protect(socket);
                socket.setSoTimeout(1500);
                DatagramPacket request = new DatagramPacket(payload, length, InetAddress.getByName(upstream), 53);
                socket.send(request);
                byte[] answer = new byte[4096];
                DatagramPacket reply = new DatagramPacket(answer, answer.length);
                socket.receive(reply);
                byte[] result = new byte[reply.getLength()];
                System.arraycopy(answer, 0, result, 0, result.length);
                return result;
            } catch (Exception ignored) {
            } finally {
                if (socket != null) socket.close();
            }
        }
        return null;
    }

    private byte[] blockedResponse(DnsQuery query) {
        byte[] result = new byte[query.questionEnd];
        System.arraycopy(query.payload, 0, result, 0, result.length);
        result[2] = (byte) 0x81; result[3] = (byte) 0x83;
        result[4] = 0; result[5] = 1; result[6] = 0; result[7] = 0; result[8] = 0; result[9] = 0; result[10] = 0; result[11] = 0;
        return result;
    }

    private byte[] failureResponse(DnsQuery query) {
        byte[] result = blockedResponse(query);
        result[3] = (byte) 0x82;
        return result;
    }

    private static byte[] wrapResponse(byte[] packet, int packetLength, DnsQuery query, byte[] dns) {
        int ipHeader = query.ipHeaderLength;
        int udpOffset = ipHeader;
        int total = ipHeader + 8 + dns.length;
        if (total > 65535) return null;
        byte[] response = new byte[total];
        System.arraycopy(packet, 0, response, 0, Math.min(packetLength, ipHeader + 8));
        for (int index = 0; index < 4; index++) { response[12 + index] = packet[16 + index]; response[16 + index] = packet[12 + index]; }
        response[udpOffset] = packet[udpOffset + 2]; response[udpOffset + 1] = packet[udpOffset + 3]; response[udpOffset + 2] = packet[udpOffset]; response[udpOffset + 3] = packet[udpOffset + 1];
        response[2] = (byte) (total >>> 8); response[3] = (byte) total;
        response[udpOffset + 4] = (byte) ((8 + dns.length) >>> 8); response[udpOffset + 5] = (byte) (8 + dns.length); response[udpOffset + 6] = 0; response[udpOffset + 7] = 0;
        System.arraycopy(dns, 0, response, ipHeader + 8, dns.length);
        response[10] = 0; response[11] = 0; int ipChecksum = checksum(response, 0, ipHeader); response[10] = (byte) (ipChecksum >>> 8); response[11] = (byte) ipChecksum;
        return response;
    }

    private static DnsQuery parseQuery(byte[] packet, int length) {
        if (length < 29 || (packet[0] & 0xf0) != 0x40 || (packet[9] & 0xff) != 17) return null;
        int ipHeader = (packet[0] & 0x0f) * 4;
        if (ipHeader < 20 || length < ipHeader + 20 || (packet[16] & 0xff) != 10 || (packet[17] & 0xff) != 231 || (packet[18] & 0xff) != 0 || (packet[19] & 0xff) != 1) return null;
        int udp = ipHeader;
        if ((packet[udp + 2] & 0xff) != 0 || (packet[udp + 3] & 0xff) != 53) return null;
        int dnsOffset = udp + 8;
        if (length < dnsOffset + 17 || (packet[dnsOffset + 4] & 0xff) != 0 || (packet[dnsOffset + 5] & 0xff) != 1) return null;
        int cursor = dnsOffset + 12; StringBuilder name = new StringBuilder();
        while (cursor < length) {
            int part = packet[cursor++] & 0xff;
            if (part == 0) break;
            if (part > 63 || cursor + part > length) return null;
            if (name.length() > 0) name.append('.');
            name.append(new String(packet, cursor, part, StandardCharsets.US_ASCII)); cursor += part;
        }
        if (cursor + 4 > length || name.length() == 0) return null;
        DnsQuery query = new DnsQuery(); query.name = normalize(name.toString()); query.ipHeaderLength = ipHeader; query.payload = new byte[length - dnsOffset]; System.arraycopy(packet, dnsOffset, query.payload, 0, query.payload.length); query.payloadLength = query.payload.length; query.questionEnd = cursor - dnsOffset + 4; return query;
    }

    private static synchronized void loadRules(Context context) {
        if (rulesLoaded) return;
        reloadRules(context);
    }

    private static void loadAsset(Context context, String name) { try (BufferedReader reader = new BufferedReader(new InputStreamReader(context.getAssets().open(name), StandardCharsets.UTF_8))) { String line; while ((line = reader.readLine()) != null) addRuleLine(line, RULES); } catch (Exception ignored) { } }
    private static void loadFile(Context context, File file) { loadFile(file, RULES); }
    private static void loadFile(File file, Set<String> target) { if (!file.isFile()) return; try (BufferedReader reader = new BufferedReader(new InputStreamReader(new FileInputStream(file), StandardCharsets.UTF_8))) { String line; while ((line = reader.readLine()) != null) addRuleLine(line, target); } catch (Exception ignored) { } }
    private static int addRuleLine(String raw, Set<String> target) {
        if (raw == null) return 0;
        String line = raw.trim().toLowerCase(Locale.US).replace("\ufeff", "");
        if (line.isEmpty() || line.startsWith("#") || line.startsWith("!") || line.startsWith("@@")) return 0;
        int before = target.size();
        String[] fields = line.split("\\s+");
        if (fields.length > 1 && (fields[0].matches("(?:0{1,3}\\.){3}0{1,3}") || fields[0].matches("127(?:\\.\\d{1,3}){3}") || fields[0].equals("::") || fields[0].equals("::1"))) {
            for (int index = 1; index < fields.length; index++) addDomain(fields[index], target);
        } else addDomain(fields[0], target);
        return target.size() - before;
    }
    private static void addDomain(String raw, Set<String> target) {
        String domain = raw.trim().toLowerCase(Locale.US);
        if (domain.startsWith("||")) domain = domain.substring(2);
        if (domain.startsWith("*.")) domain = domain.substring(2);
        if (domain.startsWith("+.")) domain = domain.substring(2);
        while (domain.startsWith(".")) domain = domain.substring(1);
        domain = domain.replaceFirst("^https?://", "");
        int cut = domain.indexOf('^'); if (cut >= 0) domain = domain.substring(0, cut);
        cut = domain.indexOf('/'); if (cut >= 0) domain = domain.substring(0, cut);
        cut = domain.indexOf('$'); if (cut >= 0) domain = domain.substring(0, cut);
        if (domain.length() > 253 || !domain.matches("[a-z0-9_](?:[a-z0-9_.-]*[a-z0-9_])?")) return;
        if (domain.indexOf('.') < 0 || domain.equals("localhost")) return;
        target.add(domain);
    }

    private static boolean matches(Set<String> rules, String domain) {
        String current = normalize(domain);
        while (!current.isEmpty()) {
            if (rules.contains(current)) return true;
            int dot = current.indexOf('.'); if (dot < 0) break; current = current.substring(dot + 1);
        }
        return false;
    }

    private static String normalize(String value) { return value == null ? "" : value.trim().toLowerCase(Locale.US).replaceAll("\\.$", ""); }

    private static synchronized void record(String domain, boolean blocked) {
        if (ACTIVITY.size() >= 240) ACTIVITY.remove(0);
        ACTIVITY.add(new ActivityItem(domain, blocked));
    }

    private void closeTunnel() { if (tunnel != null) { try { tunnel.close(); } catch (Exception ignored) { } tunnel = null; } }

    private void createChannel() { if (Build.VERSION.SDK_INT >= 26) { NotificationManager manager = getSystemService(NotificationManager.class); manager.createNotificationChannel(new NotificationChannel(CHANNEL, "XGuard 防护", NotificationManager.IMPORTANCE_LOW)); } }

    private Notification notification() {
        Intent intent = new Intent(this, MainActivity.class);
        PendingIntent pending = PendingIntent.getActivity(this, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        Notification.Builder builder = Build.VERSION.SDK_INT >= 26 ? new Notification.Builder(this, CHANNEL) : new Notification.Builder(this);
        return builder.setSmallIcon(android.R.drawable.ic_menu_info_details).setContentTitle("XGuard 正在保护网络").setContentText("无 Root DNS 广告拦截 · 点击打开控制面板").setContentIntent(pending).setOngoing(true).setCategory(Notification.CATEGORY_SERVICE).build();
    }

    private static int checksum(byte[] data, int offset, int length) {
        long sum = 0;
        for (int index = offset; index < offset + length; index += 2) { int value = (data[index] & 0xff) << 8; if (index + 1 < offset + length) value |= data[index + 1] & 0xff; sum += value; while ((sum >>> 16) != 0) sum = (sum & 0xffff) + (sum >>> 16); }
        return (int) (~sum & 0xffff);
    }

    private static final class DnsQuery {
        String name; byte[] payload; int payloadLength; int questionEnd; int ipHeaderLength;
    }

    private static final class ActivityItem {
        final String domain; final boolean blocked; final long time = System.currentTimeMillis();
        ActivityItem(String domain, boolean blocked) { this.domain = domain; this.blocked = blocked; }
        JSONObject json() throws Exception { JSONObject result = new JSONObject(); result.put("domain", domain); result.put("source", "dns"); result.put("time", time / 1000L); result.put("rule_blocked", blocked); return result; }
    }
}
