package com.financecompass.app

import android.app.Notification
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.security.MessageDigest

/** One engine and one Dart database connection for both Activity and listener. */
object FinanceEngine {
    private var engine: FlutterEngine? = null
    private var channel: MethodChannel? = null
    private var ready = false

    fun get(context: Context): FlutterEngine {
        engine?.let { return it }
        val app = context.applicationContext
        val created = FlutterEngine(app)
        engine = created
        val bridge = MethodChannel(created.dartExecutor.binaryMessenger, "finance_compass/notification_bookkeeping")
        channel = bridge
        bridge.setMethodCallHandler { call, result ->
            try {
                val prefs = app.getSharedPreferences("notification_capture", Context.MODE_PRIVATE)
                when (call.method) {
                    "ready" -> { ready = true; result.success(null); wake(app) }
                    "config" -> result.success(prefs.getString("config", "{\"enabled\":false,\"bindings\":[]}"))
                    "captureFailed" -> result.success(prefs.getBoolean("captureFailed", false))
                    "configure" -> {
                        val config = JSONObject(call.arguments as String)
                        require(config.optJSONArray("bindings") != null)
                        val previous = JSONObject(prefs.getString("config", "{}") ?: "{}")
                        config.put("version", previous.optLong("version", 0) + 1)
                        check(prefs.edit().putString("config", config.toString()).commit())
                        result.success(null)
                        wake(app)
                    }
                    "permission" -> {
                        val enabled = Settings.Secure.getString(app.contentResolver, "enabled_notification_listeners") ?: ""
                        val component = android.content.ComponentName(app, PaymentNotificationListener::class.java)
                        result.success(enabled.split(':').any { android.content.ComponentName.unflattenFromString(it) == component })
                    }
                    "openPermission" -> {
                        app.startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                        result.success(null)
                    }
                    "apps" -> {
                        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
                        val apps = app.packageManager.queryIntentActivities(intent, 0)
                            .filter { it.activityInfo.packageName != app.packageName }
                            .distinctBy { it.activityInfo.packageName }
                            .map { mapOf("package" to it.activityInfo.packageName, "label" to it.loadLabel(app.packageManager).toString()) }
                            .sortedBy { it["label"] }
                        result.success(apps)
                    }
                    "pending" -> NotificationQueue(app).use { result.success(it.pending()) }
                    "ack" -> NotificationQueue(app).use { it.ack(call.arguments as String); result.success(null) }
                    else -> result.notImplemented()
                }
            } catch (error: Exception) {
                result.error("notification_capture", "通知服务操作失败，请重试", null)
            }
        }
        created.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
        return created
    }

    fun wake(context: Context) {
        get(context)
        if (ready) channel?.invokeMethod("available", null)
    }
}

class NotificationQueue(context: Context) : SQLiteOpenHelper(context, "notification_capture.sqlite", null, 1) {
    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL("CREATE TABLE events (id TEXT PRIMARY KEY, payload TEXT NOT NULL)")
    }
    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) = Unit
    fun put(id: String, payload: String) {
        val values = ContentValues().apply { put("id", id); put("payload", payload) }
        writableDatabase.insertWithOnConflict("events", null, values, SQLiteDatabase.CONFLICT_IGNORE)
    }
    fun pending(): List<String> {
        val items = mutableListOf<String>()
        readableDatabase.rawQuery("SELECT payload FROM events ORDER BY rowid LIMIT 50", null).use {
            while (it.moveToNext()) items.add(it.getString(0))
        }
        return items
    }
    fun ack(id: String) { writableDatabase.delete("events", "id = ?", arrayOf(id)) }
}

class PaymentNotificationListener : NotificationListenerService() {
    override fun onListenerConnected() {
        // Replay only our durable queue, never historical tray notifications.
        Handler(Looper.getMainLooper()).post { FinanceEngine.wake(this) }
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        val config = JSONObject(getSharedPreferences("notification_capture", Context.MODE_PRIVATE)
            .getString("config", "{}") ?: "{}")
        if (!config.optBoolean("enabled", false)) return
        val bindings = config.optJSONArray("bindings") ?: JSONArray()
        if (!(0 until bindings.length()).any { bindings.getJSONObject(it).optString("package") == sbn.packageName }) return
        if ((sbn.notification.flags and Notification.FLAG_GROUP_SUMMARY) != 0) return
        val extras = sbn.notification.extras
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""
        val body = (extras.getCharSequence(Notification.EXTRA_BIG_TEXT)
            ?: extras.getCharSequence(Notification.EXTRA_TEXT))?.toString() ?: ""
        // Do not persist verification codes or unlock actions.
        if (Regex("(?i)\\b(otp|tac|verification code|one.time password)\\b|验证码").containsMatchIn("$title $body")) return
        if (body.isBlank()) return
        val identity = "${sbn.key}|${sbn.postTime}|$title|$body"
        val id = MessageDigest.getInstance("SHA-256").digest(identity.toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it.toInt() and 0xff) }
        val payload = JSONObject().put("id", id).put("key", sbn.key)
            .put("package", sbn.packageName).put("postedAt", sbn.postTime)
            .put("configVersion", config.optLong("version", 0))
            .put("title", title.take(256)).put("text", body.take(4096))
        // Never auto-post truncated content.
        if (body.length > 4096) payload.put("text", "[通知内容被截断] " + body.take(4096))
        try {
            NotificationQueue(this).use { it.put(id, payload.toString()) }
            Handler(Looper.getMainLooper()).post { FinanceEngine.wake(this) }
        } catch (error: Exception) {
            // No notification contents in logs. Persist a visible failure flag.
            getSharedPreferences("notification_capture", Context.MODE_PRIVATE).edit()
                .putBoolean("captureFailed", true).apply()
        }
    }
}
