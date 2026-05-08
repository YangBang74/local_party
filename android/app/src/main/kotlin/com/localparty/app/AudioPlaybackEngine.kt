package com.localparty.app

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.os.Handler
import android.os.Looper
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

/**
 * Plays 44.1 kHz stereo PCM16 chunks scheduled by wall-clock deadline [playAtUtcMs].
 */
object AudioPlaybackEngine {
    private const val SAMPLE_RATE = 44100
    private const val CHANNEL_CONFIG = AudioFormat.CHANNEL_OUT_STEREO
    private const val AUDIO_FORMAT = AudioFormat.ENCODING_PCM_16BIT

    private var audioTrack: AudioTrack? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile
    private var started = false

    fun start(): Boolean {
        if (started) return true
        val minBuf =
            AudioTrack.getMinBufferSize(SAMPLE_RATE, CHANNEL_CONFIG, AUDIO_FORMAT)
        if (minBuf <= 0) return false

        val attrs = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_MEDIA)
            .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
            .build()

        val format = AudioFormat.Builder()
            .setSampleRate(SAMPLE_RATE)
            .setEncoding(AUDIO_FORMAT)
            .setChannelMask(CHANNEL_CONFIG)
            .build()

        val track = AudioTrack(
            attrs,
            format,
            minBuf * 4,
            AudioTrack.MODE_STREAM,
            AudioManager.AUDIO_SESSION_ID_GENERATE,
        )
        if (track.state != AudioTrack.STATE_INITIALIZED) {
            track.release()
            return false
        }
        track.play()
        audioTrack = track
        started = true
        return true
    }

    fun stop() {
        started = false
        audioTrack?.apply {
            try {
                pause()
                flush()
                release()
            } catch (_: Throwable) {
            }
        }
        audioTrack = null
    }

    /**
     * Schedule PCM chunk for playback at approximately [playAtUtcMs] (System.currentTimeMillis()).
     */
    fun schedulePlay(playAtUtcMs: Long, pcm: ByteArray) {
        val track = audioTrack ?: return
        val now = System.currentTimeMillis()
        val delay = max(0L, playAtUtcMs - now)
        mainHandler.postDelayed({
            if (!started || audioTrack == null) return@postDelayed
            try {
                var written = 0
                while (written < pcm.size && started) {
                    val w = track.write(pcm, written, pcm.size - written)
                    if (w < 0) break
                    written += w
                }
            } catch (_: Throwable) {
            }
        }, delay)
    }

    /** RMS level 0..1 for metering UI (stereo interleaved). */
    fun pcmLevel(pcm: ByteArray): Double {
        if (pcm.size < 4) return 0.0
        var sum = 0.0
        var frames = 0
        var i = 0
        while (i + 3 < pcm.size) {
            val sl = ((pcm[i].toInt() and 0xff) or (pcm[i + 1].toInt() shl 8)).toShort().toInt()
            val sr = ((pcm[i + 2].toInt() and 0xff) or (pcm[i + 3].toInt() shl 8)).toShort().toInt()
            sum += (sl * sl + sr * sr).toDouble()
            frames += 2
            i += 4
        }
        if (frames == 0) return 0.0
        val rms = sqrt(sum / frames)
        return min(1.0, rms / 32768.0)
    }
}
