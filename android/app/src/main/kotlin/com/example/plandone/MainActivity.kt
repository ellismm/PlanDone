package com.example.plandone

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    companion object {
        private const val notificationPermissionRequestCode = 4107
    }

    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            ReminderNotificationScheduler.channelName,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestPermission" -> handleNotificationPermission(result)
                "replaceSchedule" -> {
                    val rawSchedules = call.argument<List<Any?>>("schedules") ?: emptyList()
                    val schedules = ReminderNotificationScheduler.parseSchedules(rawSchedules)
                    ReminderNotificationScheduler.replaceSchedule(this, schedules)
                    result.success(null)
                }

                "drainPendingActions" -> {
                    result.success(ReminderNotificationScheduler.drainPendingActions(this))
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun handleNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.success(true)
            return
        }
        if (ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.POST_NOTIFICATIONS,
            ) == PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }

        pendingPermissionResult?.error(
            "permission_request_replaced",
            "A previous notification permission request was replaced.",
            null,
        )
        pendingPermissionResult = result
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            notificationPermissionRequestCode,
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != notificationPermissionRequestCode) {
            return
        }
        val granted =
            grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
        pendingPermissionResult?.success(granted)
        pendingPermissionResult = null
    }
}
