package com.example.budgie_flutter

import android.app.Activity
import android.os.Bundle
import android.view.Gravity
import android.view.WindowManager
import android.widget.Button
import android.widget.EditText
import android.widget.TextView
import java.math.BigDecimal
import java.math.RoundingMode
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.roundToLong

class WidgetQuickAddActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_widget_quick_add)

        window?.setLayout(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
        )
        window?.setGravity(Gravity.BOTTOM)
        setFinishOnTouchOutside(true)

        val amountInput = findViewById<EditText>(R.id.widget_sheet_amount_input)
        val submitButton = findViewById<Button>(R.id.widget_sheet_submit_button)
        val cancelButton = findViewById<Button>(R.id.widget_sheet_cancel_button)
        val errorText = findViewById<TextView>(R.id.widget_sheet_error_text)

        cancelButton.setOnClickListener {
            finish()
        }

        submitButton.setOnClickListener {
            val raw = amountInput.text?.toString()?.trim().orEmpty()
            val parsed = raw.toBigDecimalOrNull()
            if (parsed == null || parsed <= BigDecimal.ZERO) {
                errorText.text = getString(R.string.widget_sheet_error_invalid_amount)
                errorText.visibility = TextView.VISIBLE
                return@setOnClickListener
            }

            val normalized = parsed.setScale(2, RoundingMode.HALF_UP)
            val amountMinor = normalized.multiply(BigDecimal(100)).toDouble().roundToLong()
            if (amountMinor <= 0L) {
                errorText.text = getString(R.string.widget_sheet_error_invalid_amount)
                errorText.visibility = TextView.VISIBLE
                return@setOnClickListener
            }

            val todayIso = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())
            DailySpendWidgetProvider.appendWidgetSpendEvent(this, amountMinor, todayIso)
            DailySpendWidgetProvider.updateWidgetLocalState(this, amountMinor, todayIso)
            DailySpendWidgetProvider.requestWidgetRefresh(this)
            finish()
        }
    }
}
