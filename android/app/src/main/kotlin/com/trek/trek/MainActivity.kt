package com.trek.trek

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Forwards text shared into Trek from other apps (ACTION_SEND, text/plain)
 * to Dart over the `trek/share_intake` channel:
 *
 * - `getInitialShare` (Dart → native): the text that launched the activity,
 *   returned once and then cleared.
 * - `onShare` (native → Dart): text shared while the activity is running.
 */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var initialShare: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        initialShare = sharedText(intent)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialShare" -> {
                        result.success(initialShare)
                        initialShare = null
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        sharedText(intent)?.let { channel?.invokeMethod("onShare", it) }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        channel?.setMethodCallHandler(null)
        channel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    companion object {
        private const val CHANNEL = "trek/share_intake"

        /**
         * The shared text, with the subject line in front when it isn't
         * already part of it — some apps put the place name there.
         */
        fun sharedText(intent: Intent?): String? {
            if (intent?.action != Intent.ACTION_SEND || intent.type != "text/plain") return null
            val text = intent.getStringExtra(Intent.EXTRA_TEXT)?.trim()
            if (text.isNullOrEmpty()) return null
            val subject = intent.getStringExtra(Intent.EXTRA_SUBJECT)?.trim()
            return if (subject.isNullOrEmpty() || text.contains(subject)) text else "$subject\n$text"
        }
    }
}
