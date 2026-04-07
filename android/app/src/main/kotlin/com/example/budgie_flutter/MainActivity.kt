package com.example.budgie_flutter

import android.Manifest
import android.content.pm.PackageManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
	companion object {
		private const val CHANNEL = "com.example.budgie_flutter/sms_import"
		private const val REQUEST_READ_SMS = 9901
	}

	private var permissionResult: MethodChannel.Result? = null

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)

		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
			.setMethodCallHandler { call, result ->
				when (call.method) {
					"hasSmsPermission" -> {
						result.success(hasSmsPermission())
					}

					"requestSmsPermission" -> {
						if (hasSmsPermission()) {
							result.success(true)
						} else {
							permissionResult = result
							ActivityCompat.requestPermissions(
								this,
								arrayOf(Manifest.permission.READ_SMS),
								REQUEST_READ_SMS,
							)
						}
					}

					"fetchUpiSms" -> {
						if (!hasSmsPermission()) {
							result.error(
								"permission_denied",
								"READ_SMS permission is required.",
								null,
							)
							return@setMethodCallHandler
						}

						val startAtMs = call.argument<Number>("startAtMs")?.toLong()
						val includeDebits = call.argument<Boolean>("includeDebits") ?: true
						val includeCredits = call.argument<Boolean>("includeCredits") ?: true
						val excludeKeys = (call.argument<List<String>>("excludeKeys") ?: emptyList()).toSet()

						try {
							val transactions = SmsImportService(this).fetchUpiTransactions(
								startAtMs = startAtMs,
								includeDebits = includeDebits,
								includeCredits = includeCredits,
								excludeKeys = excludeKeys,
							)
							result.success(transactions)
						} catch (e: Exception) {
							result.error("sms_read_failed", e.message, null)
						}
					}

					else -> result.notImplemented()
				}
			}
	}

	override fun onRequestPermissionsResult(
		requestCode: Int,
		permissions: Array<out String>,
		grantResults: IntArray,
	) {
		super.onRequestPermissionsResult(requestCode, permissions, grantResults)
		if (requestCode != REQUEST_READ_SMS) {
			return
		}

		val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
		permissionResult?.success(granted)
		permissionResult = null
	}

	private fun hasSmsPermission(): Boolean {
		return ContextCompat.checkSelfPermission(
			this,
			Manifest.permission.READ_SMS,
		) == PackageManager.PERMISSION_GRANTED
	}
}
