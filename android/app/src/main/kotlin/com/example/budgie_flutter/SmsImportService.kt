package com.example.budgie_flutter

import android.content.Context
import android.net.Uri

class SmsImportService(private val context: Context) {
    private val parser = UpiSmsParser()

    fun fetchUpiTransactions(
        startAtMs: Long?,
        includeDebits: Boolean,
        includeCredits: Boolean,
        excludeKeys: Set<String>,
    ): List<Map<String, Any>> {
        val uri = Uri.parse("content://sms/inbox")
        val projection = arrayOf("address", "body", "date")
        val selection = if (startAtMs != null) "date >= ?" else null
        val selectionArgs = if (startAtMs != null) arrayOf(startAtMs.toString()) else null
        val sortOrder = "date DESC"

        val output = mutableListOf<Map<String, Any>>()

        context.contentResolver.query(
            uri,
            projection,
            selection,
            selectionArgs,
            sortOrder,
        )?.use { cursor ->
            val addressIndex = cursor.getColumnIndex("address")
            val bodyIndex = cursor.getColumnIndex("body")
            val dateIndex = cursor.getColumnIndex("date")

            while (cursor.moveToNext()) {
                val sender = if (addressIndex >= 0) cursor.getString(addressIndex) else ""
                val body = if (bodyIndex >= 0) cursor.getString(bodyIndex) else ""
                val timestampMs = if (dateIndex >= 0) cursor.getLong(dateIndex) else 0L

                val parsed = parser.parse(sender, body, timestampMs) ?: continue
                if (parsed.direction == "debit" && !includeDebits) {
                    continue
                }
                if (parsed.direction == "credit" && !includeCredits) {
                    continue
                }
                if (excludeKeys.contains(parsed.sourceKey)) {
                    continue
                }

                output.add(
                    mapOf(
                        "sourceKey" to parsed.sourceKey,
                        "sender" to parsed.sender,
                        "body" to parsed.body,
                        "amount" to parsed.amount,
                        "timestampMs" to parsed.timestampMs,
                        "direction" to parsed.direction,
                        "reference" to (parsed.reference ?: ""),
                    ),
                )
            }
        }

        return output
    }
}
