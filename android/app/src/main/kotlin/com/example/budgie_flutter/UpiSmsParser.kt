package com.example.budgie_flutter

import java.security.MessageDigest

data class ParsedUpiSms(
    val sourceKey: String,
    val sender: String,
    val body: String,
    val amount: Double,
    val timestampMs: Long,
    val direction: String,
    val reference: String?,
)

class UpiSmsParser {
    private val amountRegex = Regex(
        pattern = "(?:rs\\.?|inr)\\s*([0-9,]+(?:\\.[0-9]{1,2})?)",
        option = RegexOption.IGNORE_CASE,
    )
    private val referenceRegex = Regex(
        pattern = "(?:utr|ref(?:erence)?|txn(?:\\s*id)?|transaction\\s*id)[:\\s-]*([a-zA-Z0-9]{6,})",
        option = RegexOption.IGNORE_CASE,
    )

    fun parse(sender: String?, body: String?, timestampMs: Long): ParsedUpiSms? {
        val safeBody = (body ?: "").trim()
        if (safeBody.isEmpty()) {
            return null
        }

        val normalized = safeBody.lowercase()
        if (!looksLikeUpiMessage(normalized)) {
            return null
        }

        val direction = detectDirection(normalized) ?: return null

        val amount = extractAmount(safeBody) ?: return null
        if (amount <= 0.0) {
            return null
        }

        val reference = extractReference(safeBody)
        val safeSender = (sender ?: "").trim()
        val sourceKey = reference?.lowercase()
            ?: sha256("$safeSender|$timestampMs|$amount|${normalizeForHash(safeBody)}")

        return ParsedUpiSms(
            sourceKey = sourceKey,
            sender = safeSender,
            body = safeBody,
            amount = amount,
            timestampMs = timestampMs,
            direction = direction,
            reference = reference,
        )
    }

    private fun looksLikeUpiMessage(normalizedBody: String): Boolean {
        val tokens = listOf("upi", "vpa", "utr", "txn", "transaction", "credited", "debited")
        return tokens.any { normalizedBody.contains(it) }
    }

    private fun detectDirection(normalizedBody: String): String? {
        val debitTokens = listOf("debited", "debit", "sent", "paid", "dr")
        if (debitTokens.any { normalizedBody.contains(it) }) {
            return "debit"
        }

        val creditTokens = listOf("credited", "credit", "received", "cr")
        if (creditTokens.any { normalizedBody.contains(it) }) {
            return "credit"
        }

        return null
    }

    private fun extractAmount(body: String): Double? {
        val match = amountRegex.find(body) ?: return null
        val rawAmount = match.groupValues.getOrNull(1) ?: return null
        val cleaned = rawAmount.replace(",", "")
        return cleaned.toDoubleOrNull()
    }

    private fun extractReference(body: String): String? {
        val match = referenceRegex.find(body) ?: return null
        val value = match.groupValues.getOrNull(1)?.trim().orEmpty()
        return value.ifEmpty { null }
    }

    private fun normalizeForHash(body: String): String {
        return body.lowercase().replace(Regex("\\s+"), " ").trim()
    }

    private fun sha256(input: String): String {
        val digest = MessageDigest.getInstance("SHA-256")
        val bytes = digest.digest(input.toByteArray())
        return bytes.joinToString("") { byte -> "%02x".format(byte) }
    }
}
