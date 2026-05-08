package com.localparty.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioPlaybackCaptureConfiguration
import android.media.AudioRecord
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

/**
 * Foreground service: captures device playback mix via [MediaProjection] + [AudioPlaybackCaptureConfiguration].
 */
class AudioCaptureService : Service() {

    companion object {
        const val ACTION_START = "com.localparty.app.ACTION_START"
        const val ACTION_STOP = "com.localparty.app.ACTION_STOP"
        const val EXTRA_RESULT_CODE = "result_code"
        const val EXTRA_DATA = "data_intent"
        private const val CHANNEL_ID = "local_party_capture"
        private const val NOTIF_ID = 4242

        /** Called from capture thread with capture wall time + PCM bytes. */
        @Volatile
        var onChunk: ((Long, ByteArray) -> Unit)? = null
    }

    private var mediaProjection: MediaProjection? = null
    private var audioRecord: AudioRecord? = null
    private var captureThread: Thread? = null

    @Volatile
    private var running = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val code = intent.getIntExtra(EXTRA_RESULT_CODE, 0)
                val data = getProjectionIntent(intent)
                if (code != 0 && data != null) {
                    startForeground(NOTIF_ID, buildNotification())
                    startCapture(code, data)
                }
            }

            ACTION_STOP -> {
                stopCaptureInternal()
                stopSelf()
            }
        }
        return START_NOT_STICKY
    }

    private fun getProjectionIntent(intent: Intent): Intent? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(EXTRA_DATA, Intent::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(EXTRA_DATA)
        }
    }

    private fun buildNotification(): Notification {
        createChannelIfNeeded()
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Local Party")
            .setContentText("Захват звука для синхронной трансляции")
            .setSmallIcon(android.R.drawable.ic_media_play)
            .build()
    }

    private fun createChannelIfNeeded() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(
                CHANNEL_ID,
                "Захват аудио",
                NotificationManager.IMPORTANCE_LOW,
            )
            getSystemService(NotificationManager::class.java).createNotificationChannel(ch)
        }
    }

    private fun startCapture(resultCode: Int, data: Intent) {
        stopCaptureInternal()
        val mgr = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        val mp = mgr.getMediaProjection(resultCode, data)
        mediaProjection = mp

        val config = AudioPlaybackCaptureConfiguration.Builder(mp)
            .addMatchingUsage(AudioAttributes.USAGE_MEDIA)
            .addMatchingUsage(AudioAttributes.USAGE_GAME)
            .addMatchingUsage(AudioAttributes.USAGE_UNKNOWN)
            .build()

        val format = AudioFormat.Builder()
            .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
            .setSampleRate(44100)
            .setChannelMask(AudioFormat.CHANNEL_IN_STEREO)
            .build()

        val minBuf = AudioRecord.getMinBufferSize(
            44100,
            AudioFormat.CHANNEL_IN_STEREO,
            AudioFormat.ENCODING_PCM_16BIT,
        ).coerceAtLeast(8192)

        val record = AudioRecord.Builder()
            .setAudioFormat(format)
            .setAudioPlaybackCaptureConfig(config)
            .setBufferSizeInBytes(minBuf * 2)
            .build()

        if (record.state != AudioRecord.STATE_INITIALIZED) {
            record.release()
            mp.stop()
            mediaProjection = null
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return
        }

        audioRecord = record
        running = true
        record.startRecording()

        captureThread = Thread({
            val buf = ByteArray(minBuf)
            while (running) {
                val n = record.read(buf, 0, buf.size)
                if (n > 0) {
                    val chunk = buf.copyOf(n)
                    val ts = System.currentTimeMillis()
                    onChunk?.invoke(ts, chunk)
                }
            }
        }, "local-party-capture").also { it.start() }
    }

    private fun stopCaptureInternal() {
        running = false
        captureThread?.interrupt()
        try {
            captureThread?.join(500)
        } catch (_: InterruptedException) {
        }
        captureThread = null

        audioRecord?.apply {
            try {
                stop()
            } catch (_: Throwable) {
            }
            try {
                release()
            } catch (_: Throwable) {
            }
        }
        audioRecord = null

        mediaProjection?.stop()
        mediaProjection = null

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
    }

    override fun onDestroy() {
        stopCaptureInternal()
        super.onDestroy()
    }
}
