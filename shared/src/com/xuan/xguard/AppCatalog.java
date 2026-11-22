package com.xuan.xguard;

import android.content.Context;
import android.content.Intent;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.content.pm.ResolveInfo;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.drawable.Drawable;
import android.util.Base64;
import java.io.ByteArrayOutputStream;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Set;
import java.util.TreeMap;
import org.json.JSONArray;
import org.json.JSONObject;

public final class AppCatalog {
    static boolean isPackageName(String name) {
        return name.matches("[A-Za-z][A-Za-z0-9_]*(\\.[A-Za-z0-9_]+)+");
    }

    static JSONArray selectable(Context context, Set<String> selected) throws Exception {
        PackageManager manager = context.getPackageManager();
        Intent launcher = new Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER);
        Map<String, String> apps = new TreeMap<>();
        for (ResolveInfo app : manager.queryIntentActivities(launcher, 0)) {
            if (app.activityInfo == null) continue;
            String pkg = app.activityInfo.packageName;
            if (!context.getPackageName().equals(pkg) && isPackageName(pkg))
                apps.put(pkg, app.activityInfo.applicationInfo.loadLabel(manager).toString());
        }
        for (String pkg : selected) if (!apps.containsKey(pkg)) apps.put(pkg, pkg);
        JSONArray result = new JSONArray();
        for (Map.Entry<String, String> app : apps.entrySet()) {
            result.put(new JSONObject().put("pkg", app.getKey()).put("name", app.getValue())
                .put("selected", selected.contains(app.getKey())));
        }
        return result;
    }

    private static final Map<String, JSONObject> CACHE = new LinkedHashMap<String, JSONObject>(64, 0.75f, true) {
        @Override protected boolean removeEldestEntry(Map.Entry<String, JSONObject> entry) { return size() > 128; }
    };

    public static synchronized String describe(Context context, JSONArray packages) throws Exception {
        JSONArray result = new JSONArray();
        PackageManager manager = context.getPackageManager();
        for (int index = 1; index < Math.min(packages.length(), 257); index++) {
            String name = packages.getString(index);
            if (!isPackageName(name)) continue;
            JSONObject item = CACHE.get(name);
            if (item == null) {
                try {
                    ApplicationInfo info = manager.getApplicationInfo(name, 0);
                    item = new JSONObject();
                    item.put("pkg", name); item.put("name", manager.getApplicationLabel(info).toString());
                    Drawable drawable = manager.getApplicationIcon(info);
                    Bitmap bitmap = Bitmap.createBitmap(72, 72, Bitmap.Config.ARGB_8888);
                    drawable.setBounds(0, 0, 72, 72); drawable.draw(new Canvas(bitmap));
                    ByteArrayOutputStream output = new ByteArrayOutputStream();
                    bitmap.compress(Bitmap.CompressFormat.PNG, 100, output); bitmap.recycle();
                    item.put("icon", "data:image/png;base64," + Base64.encodeToString(output.toByteArray(), Base64.NO_WRAP));
                    CACHE.put(name, item);
                } catch (PackageManager.NameNotFoundException ignored) { continue; }
            }
            result.put(item);
        }
        return new JSONObject().put("apps", result).toString();
    }
}
