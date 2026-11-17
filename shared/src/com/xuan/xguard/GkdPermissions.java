package com.xuan.xguard;

import android.accessibilityservice.AccessibilityServiceInfo;
import android.content.ComponentName;
import android.content.Context;
import android.view.accessibility.AccessibilityManager;

public final class GkdPermissions {
    private GkdPermissions() { }

    public static boolean enabled(Context context) {
        AccessibilityManager manager = (AccessibilityManager) context.getSystemService(Context.ACCESSIBILITY_SERVICE);
        if (manager == null) return false;
        String packageName = context.getPackageName();
        String serviceName = XGuardAccessibilityService.class.getName();
        for (AccessibilityServiceInfo info : manager.getEnabledAccessibilityServiceList(AccessibilityServiceInfo.FEEDBACK_ALL_MASK)) {
            if (info.getResolveInfo() == null || info.getResolveInfo().serviceInfo == null) continue;
            ComponentName component = new ComponentName(info.getResolveInfo().serviceInfo.packageName, info.getResolveInfo().serviceInfo.name);
            if (packageName.equals(component.getPackageName()) && serviceName.equals(component.getClassName())) return true;
        }
        return false;
    }
}
