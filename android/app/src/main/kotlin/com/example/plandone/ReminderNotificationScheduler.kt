package com.example.plandone

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import org.json.JSONArray
import org.json.JSONObject

data class ReminderSchedule(
    val reminderId: String,
    val boardId: String,
    val boardName: String,
    val itemId: String,
    val itemTitle: String,
    val kind: String,
    val title: String,
    val body: String,
    val scheduledAtEpochMillis: Long,
    val referenceAtEpochMillis: Long,
    val supportsQuickComplete: Boolean,
) {
    fun toJson(): JSONObject {
        return JSONObject()
            .put("reminderId", reminderId)
            .put("boardId", boardId)
            .put("boardName", boardName)
            .put("itemId", itemId)
            .put("itemTitle", itemTitle)
            .put("kind", kind)
            .put("title", title)
            .put("body", body)
            .put("scheduledAtEpochMillis", scheduledAtEpochMillis)
            .put("referenceAtEpochMillis", referenceAtEpochMillis)
            .put("supportsQuickComplete", supportsQuickComplete)
    }

    companion object {
        fun fromJson(json: JSONObject): ReminderSchedule {
            return ReminderSchedule(
                reminderId = json.optString("reminderId"),
                boardId = json.optString("boardId"),
                boardName = json.optString("boardName"),
                itemId = json.optString("itemId"),
                itemTitle = json.optString("itemTitle"),
                kind = json.optString("kind"),
                title = json.optString("title"),
                body = json.optString("body"),
                scheduledAtEpochMillis = json.optLong("scheduledAtEpochMillis"),
                referenceAtEpochMillis = json.optLong("referenceAtEpochMillis"),
                supportsQuickComplete = json.optBoolean("supportsQuickComplete"),
            )
        }
    }
}

data class PendingReminderAction(
    val kind: String,
    val reminderId: String,
    val boardId: String,
    val itemId: String,
) {
    fun toJson(): JSONObject {
        return JSONObject()
            .put("kind", kind)
            .put("reminderId", reminderId)
            .put("boardId", boardId)
            .put("itemId", itemId)
    }

    fun toMap(): Map<String, Any> {
        return mapOf(
            "kind" to kind,
            "reminderId" to reminderId,
            "boardId" to boardId,
            "itemId" to itemId,
        )
    }

    companion object {
        fun fromJson(json: JSONObject): PendingReminderAction {
            return PendingReminderAction(
                kind = json.optString("kind"),
                reminderId = json.optString("reminderId"),
                boardId = json.optString("boardId"),
                itemId = json.optString("itemId"),
            )
        }
    }
}

object ReminderNotificationScheduler {
    const val channelName: String = "plandone/local_notifications"

    private const val prefsName = "plandone_local_notifications"
    private const val schedulesKey = "scheduled_reminders_v1"
    private const val pendingActionsKey = "pending_reminder_actions_v1"
    private const val notificationChannelId = "plandone_reminders"
    private const val actionDone = "done"
    private const val actionSnooze = "snooze"

    fun parseSchedules(rawSchedules: List<Any?>): List<ReminderSchedule> {
        return rawSchedules.mapNotNull { entry ->
            val map = entry as? Map<*, *> ?: return@mapNotNull null
            val reminderId = map["reminderId"] as? String ?: return@mapNotNull null
            val boardId = map["boardId"] as? String ?: ""
            val boardName = map["boardName"] as? String ?: "PlanDone"
            val itemId = map["itemId"] as? String ?: ""
            val itemTitle = map["itemTitle"] as? String ?: "Untitled"
            val kind = map["kind"] as? String ?: "due"
            val title = map["title"] as? String ?: boardName
            val body = map["body"] as? String ?: itemTitle
            val scheduledAtEpochMillis =
                (map["scheduledAtEpochMillis"] as? Number)?.toLong() ?: return@mapNotNull null
            val referenceAtEpochMillis =
                (map["referenceAtEpochMillis"] as? Number)?.toLong() ?: scheduledAtEpochMillis
            val supportsQuickComplete = map["supportsQuickComplete"] == true

            ReminderSchedule(
                reminderId = reminderId,
                boardId = boardId,
                boardName = boardName,
                itemId = itemId,
                itemTitle = itemTitle,
                kind = kind,
                title = title,
                body = body,
                scheduledAtEpochMillis = scheduledAtEpochMillis,
                referenceAtEpochMillis = referenceAtEpochMillis,
                supportsQuickComplete = supportsQuickComplete,
            )
        }
    }

    fun replaceSchedule(context: Context, schedules: List<ReminderSchedule>) {
        val existingById = loadSchedules(context).associateBy { it.reminderId }
        val validSchedules = schedules.filter { it.reminderId.isNotBlank() }
        val nextIds = validSchedules.map { it.reminderId }.toSet()

        existingById
            .filterKeys { reminderId -> reminderId !in nextIds }
            .values
            .forEach { schedule -> cancelReminder(context, schedule) }

        saveSchedules(context, validSchedules)
        validSchedules.forEach { schedule -> scheduleReminder(context, schedule) }
    }

    fun rescheduleAll(context: Context) {
        val now = System.currentTimeMillis()
        val retained = mutableListOf<ReminderSchedule>()
        loadSchedules(context).forEach { schedule ->
            if (schedule.scheduledAtEpochMillis > now) {
                scheduleReminder(context, schedule)
                retained += schedule
                return@forEach
            }

            if (isStillRelevant(schedule, now)) {
                showNotification(context, schedule)
            } else {
                cancelReminder(context, schedule)
            }
        }
        saveSchedules(context, retained)
    }

    fun handleAlarm(context: Context, schedule: ReminderSchedule) {
        showNotification(context, schedule)
        val retained = loadSchedules(context)
            .filter { stored -> stored.reminderId != schedule.reminderId }
        saveSchedules(context, retained)
    }

    fun handleNotificationAction(
        context: Context,
        actionKind: String,
        schedule: ReminderSchedule,
    ) {
        enqueuePendingAction(
            context,
            PendingReminderAction(
                kind = actionKind,
                reminderId = schedule.reminderId,
                boardId = schedule.boardId,
                itemId = schedule.itemId,
            ),
        )
        NotificationManagerCompat.from(context).cancel(notificationIdFor(schedule.reminderId))
        launchApp(context)
    }

    fun drainPendingActions(context: Context): List<Map<String, Any>> {
        val actions = loadPendingActions(context)
        context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
            .edit()
            .remove(pendingActionsKey)
            .apply()
        return actions.map { action -> action.toMap() }
    }

    private fun scheduleReminder(context: Context, schedule: ReminderSchedule) {
        val now = System.currentTimeMillis()
        if (schedule.scheduledAtEpochMillis <= now) {
            if (isStillRelevant(schedule, now)) {
                showNotification(context, schedule)
            }
            return
        }

        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        alarmManager.cancel(alarmPendingIntent(context, schedule))
        alarmManager.setAndAllowWhileIdle(
            AlarmManager.RTC_WAKEUP,
            schedule.scheduledAtEpochMillis,
            alarmPendingIntent(context, schedule),
        )
    }

    private fun cancelReminder(context: Context, schedule: ReminderSchedule) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        alarmManager.cancel(alarmPendingIntent(context, schedule))
        NotificationManagerCompat.from(context).cancel(notificationIdFor(schedule.reminderId))
    }

    private fun saveSchedules(context: Context, schedules: List<ReminderSchedule>) {
        val json = JSONArray()
        schedules.forEach { schedule -> json.put(schedule.toJson()) }
        context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
            .edit()
            .putString(schedulesKey, json.toString())
            .apply()
    }

    private fun enqueuePendingAction(context: Context, action: PendingReminderAction) {
        val next = loadPendingActions(context)
            .filterNot { existing ->
                existing.kind == action.kind &&
                    existing.reminderId == action.reminderId &&
                    existing.boardId == action.boardId &&
                    existing.itemId == action.itemId
            }
            .toMutableList()
        next += action

        val json = JSONArray()
        next.forEach { entry -> json.put(entry.toJson()) }
        context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
            .edit()
            .putString(pendingActionsKey, json.toString())
            .apply()
    }

    private fun loadSchedules(context: Context): List<ReminderSchedule> {
        val raw = context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
            .getString(schedulesKey, null)
            ?: return emptyList()
        return try {
            val array = JSONArray(raw)
            buildList {
                for (index in 0 until array.length()) {
                    val entry = array.optJSONObject(index) ?: continue
                    add(ReminderSchedule.fromJson(entry))
                }
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun loadPendingActions(context: Context): List<PendingReminderAction> {
        val raw = context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
            .getString(pendingActionsKey, null)
            ?: return emptyList()
        return try {
            val array = JSONArray(raw)
            buildList {
                for (index in 0 until array.length()) {
                    val entry = array.optJSONObject(index) ?: continue
                    add(PendingReminderAction.fromJson(entry))
                }
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun alarmPendingIntent(context: Context, schedule: ReminderSchedule): PendingIntent {
        val intent = Intent(context, ReminderAlarmReceiver::class.java)
            .putExtra("reminderId", schedule.reminderId)
            .putExtra("boardId", schedule.boardId)
            .putExtra("boardName", schedule.boardName)
            .putExtra("itemId", schedule.itemId)
            .putExtra("itemTitle", schedule.itemTitle)
            .putExtra("kind", schedule.kind)
            .putExtra("title", schedule.title)
            .putExtra("body", schedule.body)
            .putExtra("scheduledAtEpochMillis", schedule.scheduledAtEpochMillis)
            .putExtra("referenceAtEpochMillis", schedule.referenceAtEpochMillis)
            .putExtra("supportsQuickComplete", schedule.supportsQuickComplete)

        return PendingIntent.getBroadcast(
            context,
            notificationIdFor(schedule.reminderId),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun actionPendingIntent(
        context: Context,
        schedule: ReminderSchedule,
        actionKind: String,
    ): PendingIntent {
        val intent = Intent(context, ReminderNotificationActionReceiver::class.java)
            .putExtra("actionKind", actionKind)
            .putExtra("reminderId", schedule.reminderId)
            .putExtra("boardId", schedule.boardId)
            .putExtra("boardName", schedule.boardName)
            .putExtra("itemId", schedule.itemId)
            .putExtra("itemTitle", schedule.itemTitle)
            .putExtra("kind", schedule.kind)
            .putExtra("title", schedule.title)
            .putExtra("body", schedule.body)
            .putExtra("scheduledAtEpochMillis", schedule.scheduledAtEpochMillis)
            .putExtra("referenceAtEpochMillis", schedule.referenceAtEpochMillis)
            .putExtra("supportsQuickComplete", schedule.supportsQuickComplete)

        return PendingIntent.getBroadcast(
            context,
            notificationIdFor("${schedule.reminderId}#$actionKind"),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun createLaunchPendingIntent(context: Context): PendingIntent {
        val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?: Intent(context, MainActivity::class.java)
        launchIntent.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        return PendingIntent.getActivity(
            context,
            0,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun launchApp(context: Context) {
        val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?: Intent(context, MainActivity::class.java)
        launchIntent.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        context.startActivity(launchIntent)
    }

    private fun ensureNotificationChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            notificationChannelId,
            "PlanDone reminders",
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply {
            description = "PlanDone due-date and start-date reminders."
        }
        manager.createNotificationChannel(channel)
    }

    private fun showNotification(context: Context, schedule: ReminderSchedule) {
        ensureNotificationChannel(context)
        val builder = NotificationCompat.Builder(context, notificationChannelId)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(schedule.title)
            .setContentText(schedule.body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(schedule.body))
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setAutoCancel(true)
            .setContentIntent(createLaunchPendingIntent(context))
            .addAction(
                0,
                "Snooze",
                actionPendingIntent(context, schedule, actionSnooze),
            )
        if (schedule.supportsQuickComplete) {
            builder.addAction(
                0,
                "Done",
                actionPendingIntent(context, schedule, actionDone),
            )
        }
        val notification = builder.build()
        NotificationManagerCompat.from(context)
            .notify(notificationIdFor(schedule.reminderId), notification)
    }

    private fun isStillRelevant(schedule: ReminderSchedule, now: Long): Boolean {
        val staleWindowMillis = when (schedule.kind) {
            "start" -> 24L * 60L * 60L * 1000L
            else -> 2L * 24L * 60L * 60L * 1000L
        }
        return now <= schedule.referenceAtEpochMillis + staleWindowMillis
    }

    private fun notificationIdFor(reminderId: String): Int {
        return reminderId.hashCode()
    }
}
