package com.example.ppsi_cashflow

import android.Manifest
import android.app.AlarmManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "dapoer/calendar_notifications"
    private var permissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestPermission" -> requestNotificationPermission(result)
                    "getEnabled" -> result.success(preferences().getBoolean("enabled", false))
                    "setEnabled" -> {
                        preferences().edit().putBoolean("enabled", call.argument<Boolean>("enabled") ?: false).apply()
                        result.success(null)
                    }
                    "schedule" -> {
                        val id = call.argument<Int>("id") ?: 0
                        val at = call.argument<Number>("atMillis")?.toLong() ?: 0L
                        val title = call.argument<String>("title") ?: "Kegiatan Dapoer"
                        val body = call.argument<String>("body") ?: "Buka kalender untuk melihat detail."
                        schedule(id, title, body, at)
                        result.success(null)
                    }
                    "cancel" -> {
                        cancel(call.argument<Int>("id") ?: 0)
                        result.success(null)
                    }
                    "cancelAll" -> {
                        cancelAll()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun preferences() = getSharedPreferences("calendar_notifications", Context.MODE_PRIVATE)

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < 33 || ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) {
            result.success(true)
            return
        }
        permissionResult = result
        ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.POST_NOTIFICATIONS), 7312)
    }

    @Deprecated("Deprecated in Android API")
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 7312) {
            permissionResult?.success(grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED)
            permissionResult = null
        }
    }

    private fun schedule(id: Int, title: String, body: String, atMillis: Long) {
        if (atMillis <= System.currentTimeMillis()) return
        val alarm = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        alarm.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atMillis, CalendarReminderReceiver.pendingIntent(this, id, title, body))
        val ids = preferences().getStringSet("scheduled_ids", emptySet())?.toMutableSet() ?: mutableSetOf()
        ids.add(id.toString())
        preferences().edit().putStringSet("scheduled_ids", ids).apply()
    }

    private fun cancel(id: Int) {
        val alarm = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        alarm.cancel(CalendarReminderReceiver.pendingIntent(this, id, "", ""))
        val ids = preferences().getStringSet("scheduled_ids", emptySet())?.toMutableSet() ?: mutableSetOf()
        ids.remove(id.toString())
        preferences().edit().putStringSet("scheduled_ids", ids).apply()
    }

    private fun cancelAll() {
        val ids = preferences().getStringSet("scheduled_ids", emptySet())?.toList() ?: emptyList()
        ids.forEach { cancel(it.toIntOrNull() ?: return@forEach) }
        preferences().edit().remove("scheduled_ids").apply()
    }
}
