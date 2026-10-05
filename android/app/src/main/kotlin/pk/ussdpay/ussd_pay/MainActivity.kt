package pk.ussdpay.ussd_pay

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var pendingResult: MethodChannel.Result? = null
    private var pendingSteps: List<String>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pk.ussdpay/ussd")
        channel = ch
        UssdService.onEvent = { type, text -> runOnUiThread { ch.invokeMethod(type, text) } }
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "accessibilityEnabled" -> result.success(isServiceEnabled())
                "openAccessibilitySettings" -> {
                    startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                    result.success(true)
                }
                "cancel" -> { UssdService.cancel(); result.success(true) }
                "session" -> {
                    val steps = call.argument<List<String>>("steps")
                    if (steps.isNullOrEmpty()) {
                        result.error("ARG", "steps missing", null)
                    } else if (!isServiceEnabled()) {
                        result.error("ACCESSIBILITY", "Turn on the OfflinePay helper in Accessibility settings", null)
                    } else {
                        pendingResult = result
                        pendingSteps = steps
                        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CALL_PHONE) ==
                            PackageManager.PERMISSION_GRANTED
                        ) begin()
                        else ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.CALL_PHONE), 77)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != 77) return
        if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) begin()
        else {
            pendingResult?.error("PERMISSION", "Phone permission is required", null)
            pendingResult = null
        }
    }

    private fun begin() {
        val steps = pendingSteps ?: return
        val r = pendingResult
        pendingResult = null
        try {
            UssdService.start(steps.drop(1))
            startActivity(Intent(Intent.ACTION_CALL, Uri.parse("tel:" + Uri.encode(steps[0]))))
            r?.success(true)
        } catch (e: Exception) {
            UssdService.cancel()
            r?.error("DIAL", e.message, null)
        }
    }

    private fun isServiceEnabled(): Boolean {
        val enabled = Settings.Secure.getString(contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES) ?: return false
        return enabled.contains("$packageName/.UssdService") || enabled.contains("$packageName/$packageName.UssdService")
    }
}
