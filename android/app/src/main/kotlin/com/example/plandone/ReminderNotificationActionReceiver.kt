package com.example.plandone

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class ReminderNotificationActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val reminderId = intent.getStringExtra("reminderId") ?: return
        val actionKind = intent.getStringExtra("actionKind") ?: return
        val schedule = ReminderSchedule(
            reminderId = reminderId,
            boardId = intent.getStringExtra("boardId") ?: "",
            boardName = intent.getStringExtra("boardName") ?: "PlanDone",
            itemId = intent.getStringExtra("itemId") ?: "",
            itemTitle = intent.getStringExtra("itemTitle") ?: "Untitled",
            kind = intent.getStringExtra("kind") ?: "due",
            title = intent.getStringExtra("title") ?: "PlanDone reminder",
            body = intent.getStringExtra("body") ?: "Open PlanDone to review.",
            scheduledAtEpochMillis = intent.getLongExtra("scheduledAtEpochMillis", 0L),
            referenceAtEpochMillis = intent.getLongExtra("referenceAtEpochMillis", 0L),
            supportsQuickComplete = intent.getBooleanExtra("supportsQuickComplete", false),
        )
        ReminderNotificationScheduler.handleNotificationAction(context, actionKind, schedule)
    }
}
