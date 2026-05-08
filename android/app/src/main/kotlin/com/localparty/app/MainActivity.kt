package com.localparty.app

import android.app.Activity
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val audioChannel = "local_party/audio"
    private val pcmStreamChannel = "local_party/audio_pcm"

    private var projectionResultCode: Int = Activity.RESULT_CANCELED
    private var projectionData: Intent? = null

    private var pendingProjection: MethodChannel.Result? = null
    private var pcmSink: EventChannel.EventSink? = null

    companion object {
        private const val REQ_PROJECTION = 1001
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, audioChannel).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestMediaProjection" -> {
                    pendingProjection = result
                    val mgr = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
                    val intent = mgr.createScreenCaptureIntent()
                    startActivityForResult(intent, REQ_PROJECTION)
                }

                "startCaptureService" -> {
                    val code = projectionResultCode
                    val data = projectionData
                    if (code != Activity.RESULT_OK || data == null) {
                        result.error(
                            "NO_PROJECTION",
                            "Сначала разрешите захват экрана/звука в системном диалоге.",
                            null,
                        )
                        return@setMethodCallHandler
                    }
                    AudioCaptureService.onChunk = { ts, bytes ->
                        runOnUiThread {
                            pcmSink?.success(
                                mapOf(
                                    "captureUtcMs" to ts,
                                    "pcm" to bytes,
                                ),
                            )
                        }
                    }
                    val i = Intent(this, AudioCaptureService::class.java).apply {
                        action = AudioCaptureService.ACTION_START
                        putExtra(AudioCaptureService.EXTRA_RESULT_CODE, code)
                        putExtra(AudioCaptureService.EXTRA_DATA, data)
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(i)
                    } else {
                        startService(i)
                    }
                    result.success(true)
                }

                "stopCaptureService" -> {
                    AudioCaptureService.onChunk = null
                    val stop = Intent(this, AudioCaptureService::class.java).apply {
                        action = AudioCaptureService.ACTION_STOP
                    }
                    startService(stop)
                    result.success(true)
                }

                "startPlayback" -> {
                    result.success(AudioPlaybackEngine.start())
                }

                "stopPlayback" -> {
                    AudioPlaybackEngine.stop()
                    result.success(true)
                }

                "feedPcm" -> {
                    val playAt = call.argument<Number>("playAtUtcMs")?.toLong() ?: 0L
                    @Suppress("UNCHECKED_CAST")
                    val pcm = call.argument<ByteArray>("pcm")
                    if (pcm != null && pcm.isNotEmpty()) {
                        AudioPlaybackEngine.schedulePlay(playAt, pcm)
                    }
                    result.success(null)
                }

                "pcmLevel" -> {
                    val bytes = call.argument<ByteArray>("pcm")
                    val level = if (bytes != null) AudioPlaybackEngine.pcmLevel(bytes) else 0.0
                    result.success(level)
                }

                else -> result.notImplemented()
            }
        }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, pcmStreamChannel).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    pcmSink = events
                }

                override fun onCancel(arguments: Any?) {
                    pcmSink = null
                }
            },
        )
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQ_PROJECTION) {
            projectionResultCode = resultCode
            projectionData = data
            pendingProjection?.success(resultCode == Activity.RESULT_OK)
            pendingProjection = null
        }
    }
}
