package com.xuan.xguard;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.net.VpnService;
import android.os.Build;

public final class BootReceiver extends BroadcastReceiver {
    @Override public void onReceive(Context context, Intent intent) {
        if (intent == null || (!Intent.ACTION_BOOT_COMPLETED.equals(intent.getAction()) && !Intent.ACTION_MY_PACKAGE_REPLACED.equals(intent.getAction()))) return;
        if (!context.getSharedPreferences("xguard", Context.MODE_PRIVATE).getBoolean("autostart_enabled", false)) return;
        if (VpnService.prepare(context) != null) return;
        context.getSharedPreferences("xguard", Context.MODE_PRIVATE).edit().putBoolean("enabled", true).apply();
        Intent service = new Intent(context, XGuardVpnService.class);
        if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(service); else context.startService(service);
    }
}
