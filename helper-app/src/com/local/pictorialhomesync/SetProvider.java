package com.local.pictorialhomesync;

import android.content.ContentProvider;
import android.content.ContentValues;
import android.database.Cursor;
import android.net.Uri;
import android.os.Bundle;
import android.util.Log;

/**
 * Invoked via {@code content call} from Magisk shell — reliable on ColorOS 17
 * where {@code am start-service} / broadcasts are blocked.
 */
public class SetProvider extends ContentProvider {
    private static final String TAG = "PictorialHomeSync";

    @Override
    public boolean onCreate() {
        return true;
    }

    @Override
    public Bundle call(String method, String arg, Bundle extras) {
        if (!"set".equals(method)) {
            return null;
        }
        String path = extras != null ? extras.getString("path") : arg;
        String md5 = extras != null ? extras.getString("md5") : null;
        String err = WallpaperApply.apply(getContext(), path, md5);
        Bundle out = new Bundle();
        out.putBoolean("ok", err == null);
        if (err != null) {
            out.putString("error", err);
            Log.e(TAG, "SetProvider fail: " + err);
        } else {
            Log.i(TAG, "SetProvider OK md5=" + md5);
        }
        return out;
    }

    @Override public Cursor query(Uri u, String[] p, String s, String[] a, String o) { return null; }
    @Override public String getType(Uri uri) { return null; }
    @Override public Uri insert(Uri uri, ContentValues values) { return null; }
    @Override public int delete(Uri uri, String selection, String[] selectionArgs) { return 0; }
    @Override public int update(Uri uri, ContentValues values, String selection, String[] selectionArgs) { return 0; }
}
