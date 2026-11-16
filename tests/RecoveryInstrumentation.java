package com.xuan.xguard;

import android.app.Instrumentation;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.net.VpnService;
import android.os.Bundle;
import java.io.File;
import java.lang.reflect.Constructor;
import java.lang.reflect.Method;
import java.net.DatagramPacket;
import java.net.DatagramSocket;
import java.net.InetAddress;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.HashSet;
import java.util.Set;
import org.json.JSONArray;
import org.json.JSONObject;

/** Compile into an isolated validation package, never into release APKs. */
public final class RecoveryInstrumentation extends Instrumentation {
    private Context context;
    private MainActivity activity;
    private Object bridge;
    private Method dispatch;
    @Override public void onCreate(Bundle args) { super.onCreate(args); start(); }
    private void check(boolean condition, String message) { if (!condition) throw new AssertionError(message); }
    private String command(String... values) throws Exception { return (String)dispatch.invoke(bridge,new JSONArray(Arrays.asList(values))); }
    private JSONObject recovery(String op) throws Exception { return new JSONObject(command("run","shield","recovery",op)); }
    private void source(String content) throws Exception { RecoveryStore.write(new File(context.getFilesDir(),"source_awavenue.list"),content.getBytes(StandardCharsets.UTF_8)); XGuardVpnService.reloadRules(context); }
    private int dns(String domain) throws Exception {
        java.io.ByteArrayOutputStream q=new java.io.ByteArrayOutputStream(); q.write(new byte[]{0x58,0x47,1,0,0,1,0,0,0,0,0,0});
        for(String label:domain.split("\\.")) { byte[] b=label.getBytes(StandardCharsets.US_ASCII); q.write(b.length); q.write(b); }
        q.write(new byte[]{0,0,1,0,1}); byte[] bytes=q.toByteArray();
        try(DatagramSocket socket=new DatagramSocket()) {
            socket.setSoTimeout(10000); socket.send(new DatagramPacket(bytes,bytes.length,InetAddress.getByName("10.231.0.1"),53));
            byte[] answer=new byte[4096]; DatagramPacket packet=new DatagramPacket(answer,answer.length); socket.receive(packet);
            check(packet.getLength()>=12,"short DNS reply"); return answer[3]&15;
        }
    }
    @Override public void onStart() {
        Bundle result=new Bundle();
        try {
            context=getTargetContext();
            check(context.getPackageName().contains("validation"),"refuse to modify production app data");
            SharedPreferences p=RecoveryStore.prefs(context);
            p.edit().clear().putBoolean("keepalive_prompt",true).commit();
            activity=(MainActivity)startActivitySync(new Intent(context,MainActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
            Class<?> type=Class.forName("com.xuan.xguard.MainActivity$XGuardBridge");
            Constructor<?> constructor=type.getDeclaredConstructor(MainActivity.class); constructor.setAccessible(true); bridge=constructor.newInstance(activity);
            dispatch=type.getDeclaredMethod("dispatch",JSONArray.class); dispatch.setAccessible(true);
            source("old.example.test\nshared.example.test\n");
            Set<String> before=XGuardVpnService.ruleSnapshot(context);
            RecoveryStore.beginUpdate(context);
            // Reading the sources screen persists defaults; it must not invalidate a snapshot.
            command("run","shield","sources");
            source("new.example.test\nshared.example.test\n");
            JSONObject diff=RecoveryStore.finishUpdate(context,before);
            check(diff.getInt("added")==1 && diff.getInt("removed")==1,"domain diff");
            RecoveryStore.domainChange(context,"block","add","user.example.test");
            RecoveryStore.rollback(context);
            check(XGuardVpnService.isBlocked(context,"old.example.test"),"old source restored");
            check(!XGuardVpnService.isBlocked(context,"new.example.test"),"new source removed");
            check(XGuardVpnService.isBlocked(context,"user.example.test"),"current custom block preserved");
            check(p.getLong("update_hold_until",0)>System.currentTimeMillis()/1000L,"rollback hold");
            RecoveryStore.undoDomain(context);
            check(!XGuardVpnService.isBlocked(context,"user.example.test"),"undo block");
            RecoveryStore.domainChange(context,"allow","add","*.example.test");
            check(XGuardVpnService.isAllowed(context,"sub.old.example.test"),"wildcard allow");
            try { RecoveryStore.domainChange(context,"block","add","sub.example.test"); throw new AssertionError("wildcard conflict accepted"); } catch(java.io.IOException expected) { }
            RecoveryStore.undoDomain(context);
            p.edit().putStringSet("enabled_sources",new HashSet<>(Arrays.asList("baseline"))).commit();
            try { RecoveryStore.rollback(context); throw new AssertionError("selection conflict accepted"); } catch(java.io.IOException expected) { }
            check(XGuardVpnService.isBlocked(context,"old.example.test"),"failed rollback retained live rules");
            check(VpnService.prepare(context)==null,"VPN must be authorized for validation package");
            command("enable","shield");
            for(int i=0;i<50&&!XGuardVpnService.isRunning();i++) Thread.sleep(100);
            check(XGuardVpnService.isRunning(),"VPN starts");
            RecoveryStore.domainChange(context,"block","add","example.com");
            check(dns("example.com")==3,"custom block returns NXDOMAIN");
            command("run","shield","recovery","pause");
            check(RecoveryStore.isPaused(context),"pause marker");
            check(dns("example.com")==0,"paused DNS still forwards");
            command("run","shield","recovery","resume");
            check(dns("example.com")==3,"resume blocks again");
            p.edit().putLong("pause_until",System.currentTimeMillis()/1000L-1).commit();
            check(dns("example.com")==3,"expired pause restores blocking without UI");
            XGuardVpnService.requestStop(context);
            for(int i=0;i<30&&XGuardVpnService.isRunning();i++) Thread.sleep(100);
            JSONObject stopped=recovery("check");
            check("vpn_stopped".equals(stopped.getString("state")),"health detects stopped VPN: "+stopped);
            check("ok".equals(recovery("repair").getString("state")),"health repair restarts VPN");
            command("disable","shield"); Thread.sleep(400);
            check("off".equals(recovery("repair").getString("state")),"repair respects manual off");
            check(!XGuardVpnService.isRunning(),"manual off retained");
            result.putString("result","PASS: snapshot diff/rollback and selection guard, preserved custom rules, undo/wildcard conflict, live DNS pause/resume/expiry, VPN health repair/manual off");
            p.edit().putBoolean("enabled",false).commit(); context.stopService(new Intent(context,XGuardVpnService.class));
            finish(0,result);
        } catch(Throwable error) {
            if(context!=null) { RecoveryStore.prefs(context).edit().putBoolean("enabled",false).commit(); context.stopService(new Intent(context,XGuardVpnService.class)); }
            result.putString("error",android.util.Log.getStackTraceString(error)); finish(1,result);
        } finally {
            if(context!=null) { RecoveryStore.prefs(context).edit().putBoolean("enabled",false).commit(); context.stopService(new Intent(context,XGuardVpnService.class)); }
        }
    }
}
