package android.src.main.kotlin.com.hiennv.flutter_callkit_incoming

import android.content.ContentResolver
import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.net.Uri

class AudioPlayer  constructor(
    private val context: Context,
) {
    private var player: MediaPlayer? = null

    private val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager

    fun playDialingSound() {
        audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
        player = MediaPlayer.create(
            context,
            Uri.parse(
                ContentResolver.SCHEME_ANDROID_RESOURCE + "://" +
                        context.applicationContext.packageName + "/raw/sound_outgoing_call"
            ),
            null,
            AudioAttributes.Builder()
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION_SIGNALLING)
                .build(),
            0
        ).apply {
            isLooping = true
        }
        init()
    }

    fun playRingingSound() {
        player = MediaPlayer.create(
            context,
            Uri.parse(
                ContentResolver.SCHEME_ANDROID_RESOURCE + "://" +
                        context.applicationContext.packageName + "/raw/sound_incoming_call"
            ),
            null,
            AudioAttributes.Builder()
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                .build(),
            1
        ).apply {
            isLooping = true
        }
        init()
    }

    fun playPickUpSound() = playSound(
        "sound_pickup",
        AudioManager.MODE_IN_COMMUNICATION,
        AudioAttributes.USAGE_VOICE_COMMUNICATION_SIGNALLING,
    )

    fun playReconnectingSound() = playSound(
        "sound_reconnecting",
        AudioManager.MODE_IN_COMMUNICATION,
        AudioAttributes.USAGE_VOICE_COMMUNICATION_SIGNALLING,
        true
    )

    fun playCallEndSound() = playSound(
        "sound_end",
        AudioManager.MODE_IN_COMMUNICATION,
        AudioAttributes.USAGE_VOICE_COMMUNICATION_SIGNALLING
    )

    private fun playSound(
        rawResName: String,
        audioMode: Int?,
        usage: Int,
        isLooping: Boolean = false
    ) {
        stop()
        audioMode?.let { audioManager.mode = it }
        player = MediaPlayer.create(
            context,
            Uri.parse(
                ContentResolver.SCHEME_ANDROID_RESOURCE + "://" +
                        context.applicationContext.packageName + "/raw/" + rawResName
            ),
            null,
            AudioAttributes.Builder()
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .setUsage(usage)
                .build(),
            0
        )
        player?.isLooping = isLooping
        player?.setOnCompletionListener { stop() }
        player?.start()
    }

    private fun init() {
        player?.setOnCompletionListener {
            seekTo(0)
        }
        player?.start()
    }


    fun pause() {
        player?.pause()
    }

    fun play() {
        player?.start()
    }

    fun seekTo(ms: Int) {
        player?.seekTo(ms)
    }

    fun stop() {
        player?.stop()
        player?.release()
        player = null
    }
}