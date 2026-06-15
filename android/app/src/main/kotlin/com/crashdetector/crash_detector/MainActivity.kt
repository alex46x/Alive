package com.crashdetector.crash_detector

import android.content.Intent
import android.net.Uri
import android.telephony.SmsManager
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.crashdetector/sos"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "sendSms") {
                val number = call.argument<String>("number")
                val message = call.argument<String>("message")
                
                if (number != null && message != null) {
                    try {
                        val smsManager = SmsManager.getDefault()
                        smsManager.sendTextMessage(number, null, message, null, null)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SMS_FAILED", e.message, null)
                    }
                } else {
                    result.error("INVALID_ARGS", "Number or message is null", null)
                }
            } else if (call.method == "makeCall") {
                val number = call.argument<String>("number")
                if (number != null) {
                    try {
                        // ACTION_DIAL opens the dialer pre-filled with the number.
                        // The user still has to press call - safer than ACTION_CALL,
                        // which requires a runtime CALL_PHONE grant and can be abused.
                        val intent = Intent(Intent.ACTION_DIAL)
                        intent.data = Uri.parse("tel:$number")
                        intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("CALL_FAILED", e.message, null)
                    }
                } else {
                    result.error("INVALID_ARGS", "Number is null", null)
                }
            } else {
                result.notImplemented()
            }
        }
    }
}
