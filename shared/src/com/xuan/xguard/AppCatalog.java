package com.xuan.xguard;

import android.content.Context;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.drawable.Drawable;
import android.util.Base64;
import java.io.ByteArrayOutputStream;
import java.util.LinkedHashMap;
import java.util.Map;
import org.json.JSONArray;
import org.json.JSONObject;

public final class AppCatalog {
    private static final Map<String, JSONObject> CACHE = new LinkedHashMap<String, JSONObject>(64, 0.75f, true) {
        @Override protected boolean removeEldestEntry(Map.Entry<String, JSONObject> entry) { return size() > 128; }
    };

    public static synchronized String describe(Context context, JSONArray packages) throws Exception {
        JSONArray result = new JSONArray();
        PackageManager manager = context.getPackageManager();
        for (int index = 1; index < Math.min(packages.length(), 257); index++) {
            String name = packages.getString(index);
            if (!name.matches("[A-Za-z][A-Za-z0-9_]*(\\.[A-Za-z0-9_]+)+")) continue;
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
