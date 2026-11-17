package com.xuan.xguard;

import android.app.Activity;
import android.app.ActivityManager;
import android.app.Instrumentation;
import android.content.ComponentName;
import android.content.Intent;
import android.os.Bundle;
import java.lang.reflect.Constructor;
import java.lang.reflect.Method;

public final class RecentTasksInstrumentation extends Instrumentation {
    @Override public void onCreate(Bundle arguments) { super.onCreate(arguments); start(); }
    private void check(boolean value, String name) { if (!value) throw new AssertionError(name); }
    private Activity launch() {
        Intent intent = new Intent(Intent.ACTION_MAIN);
        intent.setComponent(new ComponentName(getTargetContext().getPackageName(), MainActivity.class.getName()));
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        Activity activity = startActivitySync(intent);
        waitForIdleSync();
        return activity;
    }
    private Object bridge(Activity activity) throws Exception {
        for (Class<?> nested : MainActivity.class.getDeclaredClasses()) {
            if (!nested.getSimpleName().endsWith("Bridge")) continue;
            Constructor<?> constructor = nested.getDeclaredConstructor(MainActivity.class);
            constructor.setAccessible(true);
            return constructor.newInstance(activity);
        }
        throw new AssertionError("native bridge missing");
    }
    private void setHidden(Activity activity, boolean hidden) throws Exception {
        Object target = bridge(activity);
        Method setter = target.getClass().getDeclaredMethod("setHideFromRecents", boolean.class);
        setter.setAccessible(true);
        setter.invoke(target, hidden);
        waitForIdleSync();
        Method getter = target.getClass().getDeclaredMethod("getHideFromRecents");
        getter.setAccessible(true);
        check(Boolean.valueOf(hidden).equals(getter.invoke(target)), "bridge saved preference");
        checkTask(activity, hidden);
    }
    private void checkTask(Activity activity, boolean hidden) {
        ActivityManager manager = (ActivityManager) activity.getSystemService(Activity.ACTIVITY_SERVICE);
        for (ActivityManager.AppTask task : manager.getAppTasks()) {
            ActivityManager.RecentTaskInfo info = task.getTaskInfo();
            if (info.id != activity.getTaskId()) continue;
            check(((info.baseIntent.getFlags() & Intent.FLAG_ACTIVITY_EXCLUDE_FROM_RECENTS) != 0) == hidden, "actual recent-task flag");
            return;
        }
        throw new AssertionError("current task missing");
    }
    @Override public void onStart() {
        Bundle result = new Bundle();
        Activity activity = null;
        try {
            check(getTargetContext().getPackageName().contains("validation092"), "isolated validation package");
            activity = launch();
            setHidden(activity, false);
            setHidden(activity, true);
            Activity previous = activity;
            runOnMainSync(previous::finishAndRemoveTask);
            waitForIdleSync();
            activity = launch();
            checkTask(activity, true);
            setHidden(activity, false);
            previous = activity;
            runOnMainSync(previous::finishAndRemoveTask);
            waitForIdleSync();
            activity = launch();
            checkTask(activity, false);
            result.putString("result", "PASS: native bridge on/off, actual task exclusion flag, preference restored across Activity relaunches");
            finish(0, result);
        } catch (Throwable error) {
            result.putString("result", "FAIL: " + error);
            android.util.Log.e("XGuardRecentsTest", "test failed", error);
            finish(1, result);
        } finally {
            if (activity != null) {
                Activity remaining = activity;
                runOnMainSync(remaining::finishAndRemoveTask);
            }
        }
    }
}
