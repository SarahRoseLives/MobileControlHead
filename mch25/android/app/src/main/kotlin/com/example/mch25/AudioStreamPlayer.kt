package com.example.mch25

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.util.Log
import kotlinx.coroutines.*
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URL

class AudioStreamPlayer {
    private var audioTrack: AudioTrack? = null
    private var streamJob: Job? = null
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    
    companion object {
        private const val TAG = "AudioStreamPlayer"
        private const val SAMPLE_RATE = 8000
        private const val BUFFER_SIZE = 8192
    }
    
    fun start(url: String) {
        stop() // Stop any existing playback
        
        Log.d(TAG, "Starting audio stream from: $url")
        
        // Create AudioTrack
        val minBufferSize = AudioTrack.getMinBufferSize(
            SAMPLE_RATE,
            AudioFormat.CHANNEL_OUT_MONO,
            AudioFormat.ENCODING_PCM_16BIT
        )
        
        audioTrack = AudioTrack.Builder()
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                    .build()
            )
            .setAudioFormat(
                AudioFormat.Builder()
                    .setSampleRate(SAMPLE_RATE)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .build()
            )
            .setBufferSizeInBytes(minBufferSize * 4)
            .setTransferMode(AudioTrack.MODE_STREAM)
            .build()
        
        audioTrack?.play()
        
        // Start streaming in background
        streamJob = scope.launch {
            streamAudio(url)
        }
    }
    
    fun stop() {
        Log.d(TAG, "Stopping audio stream")
        streamJob?.cancel()
        streamJob = null
        audioTrack?.stop()
        audioTrack?.release()
        audioTrack = null
    }
    
    private suspend fun streamAudio(urlString: String) {
        while (streamJob?.isActive == true) {
            try {
                val url = URL(urlString)
                val connection = url.openConnection() as HttpURLConnection
                connection.connectTimeout = 5000
                connection.readTimeout = 30000
                connection.connect()
                
                val inputStream: InputStream = connection.inputStream
                
                // Skip WAV header (44 bytes)
                inputStream.skip(44)
                
                val buffer = ByteArray(BUFFER_SIZE)
                
                Log.d(TAG, "Connected, streaming audio...")
                
                while (streamJob?.isActive == true) {
                    val bytesRead = inputStream.read(buffer)
                    if (bytesRead == -1) break
                    audioTrack?.write(buffer, 0, bytesRead)
                }
                
                inputStream.close()
                connection.disconnect()
                
            } catch (e: Exception) {
                Log.e(TAG, "Stream error: ${e.message}")
                delay(2000) // Wait before reconnecting
            }
        }
    }
}
