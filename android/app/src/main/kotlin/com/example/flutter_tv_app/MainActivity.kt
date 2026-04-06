package com.example.flutter_tv_app

import android.os.Bundle
import android.view.KeyEvent
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.net.NetworkInterface
import java.util.Collections

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.example.flutter_tv_app/device",
        ).setMethodCallHandler { call, result ->
            if (call.method == "getMacAddress") {
                result.success(getMacAddressFromNetworkInterfaces())
            } else {
                result.notImplemented()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Keep screen on so the app is not put to sleep or backgrounded by TV
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        // Treat HOME leave as an app close request on TV.
        finishAffinity()
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        // HOME is usually handled by the system. If it is delivered, close app.
        if (event.keyCode == KeyEvent.KEYCODE_HOME) {
            finishAffinity()
            return true
        }

        // Let Flutter handle DPAD/number keys and text input normally.
        return super.dispatchKeyEvent(event)
    }

    /**
     * Reads hardware MAC via [NetworkInterface]. Often works on TV (e.g. eth0) when
     * reading /sys/class/net/.../address from Dart fails due to SELinux.
     */
    private fun getMacAddressFromNetworkInterfaces(): String? {
        val preferredOrder = listOf("eth0", "wlan0", "eth1", "wlan1", "p2p0")
        for (name in preferredOrder) {
            val mac = macForInterface(name)
            if (mac != null) return mac
        }
        try {
            val interfaces = Collections.list(NetworkInterface.getNetworkInterfaces())
            for (intf in interfaces) {
                if (intf.isLoopback) continue
                val mac = intf.hardwareAddress ?: continue
                val formatted = formatMac(mac)
                if (isUsableMac(formatted)) return formatted
            }
        } catch (_: Exception) {
        }
        return null
    }

    private fun macForInterface(name: String): String? {
        return try {
            val ni = NetworkInterface.getByName(name) ?: return null
            val mac = ni.hardwareAddress ?: return null
            val formatted = formatMac(mac)
            if (isUsableMac(formatted)) formatted else null
        } catch (_: Exception) {
            null
        }
    }

    private fun formatMac(mac: ByteArray): String {
        if (mac.isEmpty()) return ""
        return mac.joinToString(":") { b ->
            String.format("%02X", b.toInt() and 0xFF)
        }
    }

    private fun isUsableMac(mac: String): Boolean {
        if (mac.length != 17 || mac.count { it == ':' } != 5) return false
        if (mac == "00:00:00:00:00:00") return false
        // Android often reports this placeholder when the real Wi-Fi MAC is hidden.
        if (mac == "02:00:00:00:00:00") return false
        return true
    }
}
