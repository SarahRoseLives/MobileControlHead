package com.example.mch25

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.os.Process
import android.util.Log
import kotlinx.coroutines.*
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.ConcurrentLinkedQueue

class AudioStreamPlayer(private val audioManager: AudioManager) {
    private var audioTrack: AudioTrack? = null
    private var downloadJob: Job? = null
    private var playbackJob: Job? = null
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private val audioQueue = ConcurrentLinkedQueue<ByteArray>()
    private var isPlaying = false
    private var playbackStarted = false
    private var actualSampleRate = 8000
    
    companion object {
        private const val TAG = "AudioStreamPlayer"
        private const val SOURCE_SAMPLE_RATE = 8000
        private const val READ_BUFFER_SIZE = 8192
        private const val MAX_QUEUE_SIZE = 30 // Max buffered chunks
    }
    
    fun start(url: String) {
        stop()
        
        Log.d(TAG, "Starting audio stream from: $url")
        
        // Determine best sample rate for device
        val nativeSampleRate = AudioTrack.getNativeOutputSampleRate(AudioManager.STREAM_MUSIC)
        Log.d(TAG, "Device native sample rate: $nativeSampleRate Hz")
        
        // Use native rate or closest supported rate
        actualSampleRate = when {
            nativeSampleRate >= 44100 -> 44100
            nativeSampleRate >= 22050 -> 22050
            nativeSampleRate >= 16000 -> 16000
            else -> SOURCE_SAMPLE_RATE
        }
        
        Log.d(TAG, "Using sample rate: $actualSampleRate Hz (source: $SOURCE_SAMPLE_RATE Hz)")
        
        // Set audio mode and routing
        audioManager.mode = AudioManager.MODE_NORMAL
        audioManager.isSpeakerphoneOn = true
        
        // Request audio focus
        @Suppress("DEPRECATION")
        val result = audioManager.requestAudioFocus(
            null,
            AudioManager.STREAM_MUSIC,
            AudioManager.AUDIOFOCUS_GAIN
        )
        
        if (result != AudioManager.AUDIOFOCUS_REQUEST_GRANTED) {
            Log.w(TAG, "Audio focus not granted!")
        }
        
        // Log current volume
        val maxVolume = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
        val currentVolume = audioManager.getStreamVolume(AudioManager.STREAM_MUSIC)
        Log.d(TAG, "Media volume: $currentVolume/$maxVolume")
        
        isPlaying = true
        
        // Start download job
        downloadJob = scope.launch {
            downloadAudio(url)
        }
        
        // Start playback job
        playbackJob = scope.launch {
            playAudio()
        }
    }
    
    fun stop() {
        Log.d(TAG, "Stopping audio stream")
        isPlaying = false
        playbackStarted = false
        downloadJob?.cancel()
        playbackJob?.cancel()
        downloadJob = null
        playbackJob = null
        audioQueue.clear()
        try {
            audioTrack?.pause()
            audioTrack?.flush()
            audioTrack?.stop()
            audioTrack?.release()
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping audio track: ${e.message}")
        }
        audioTrack = null
    }
    
    private suspend fun downloadAudio(urlString: String) {
        var reconnectAttempts = 0
        val maxReconnectAttempts = 50 // Increased to allow more time for server to be ready
        
        while (isPlaying && reconnectAttempts < maxReconnectAttempts) {
            try {
                Log.d(TAG, "Connecting to audio stream (attempt ${reconnectAttempts + 1})")
                val url = URL(urlString)
                val connection = url.openConnection() as HttpURLConnection
                connection.connectTimeout = 10000
                connection.readTimeout = 30000
                connection.setRequestProperty("Connection", "keep-alive")
                connection.connect()
                
                val responseCode = connection.responseCode
                if (responseCode != HttpURLConnection.HTTP_OK && responseCode != HttpURLConnection.HTTP_PARTIAL) {
                    Log.e(TAG, "HTTP error: $responseCode")
                    throw Exception("HTTP $responseCode")
                }
                
                val inputStream: InputStream = connection.inputStream
                
                // Skip WAV header (44 bytes)
                var headerBytesSkipped = 0
                while (headerBytesSkipped < 44 && isPlaying) {
                    val skipped = inputStream.skip((44 - headerBytesSkipped).toLong())
                    if (skipped <= 0) break
                    headerBytesSkipped += skipped.toInt()
                }
                Log.d(TAG, "WAV header skipped: $headerBytesSkipped bytes")
                
                val buffer = ByteArray(READ_BUFFER_SIZE)
                reconnectAttempts = 0 // Reset on successful connection
                
                Log.d(TAG, "Download started, streaming PCM data")
                
                while (isPlaying) {
                    // Backpressure: Don't buffer too much
                    while (audioQueue.size >= MAX_QUEUE_SIZE && isPlaying) {
                        delay(20)
                    }
                    
                    if (!isPlaying) break
                    
                    val bytesRead = inputStream.read(buffer)
                    if (bytesRead == -1) {
                        Log.d(TAG, "End of stream reached")
                        break
                    }
                    if (bytesRead <= 0) continue
                    
                    // Ensure even number of bytes for 16-bit samples
                    val validBytes = if (bytesRead % 2 != 0) bytesRead - 1 else bytesRead
                    
                    if (validBytes > 0) {
                        // Resample if needed
                        val processedChunk = if (actualSampleRate != SOURCE_SAMPLE_RATE) {
                            val resampled = resampleAudio(buffer, validBytes, SOURCE_SAMPLE_RATE, actualSampleRate)
                            if (audioQueue.size % 50 == 0) {
                                Log.d(TAG, "Resampling: ${validBytes} bytes @ ${SOURCE_SAMPLE_RATE}Hz → ${resampled.size} bytes @ ${actualSampleRate}Hz")
                            }
                            resampled
                        } else {
                            ByteArray(validBytes).also { System.arraycopy(buffer, 0, it, 0, validBytes) }
                        }
                        
                        audioQueue.offer(processedChunk)
                        
                        // If playback hasn't started yet but we now have data, try to start it
                        if (!playbackStarted && audioQueue.size >= 3) {
                            Log.d(TAG, "Data available after initial timeout, restarting playback")
                            playbackJob = scope.launch {
                                playAudio()
                            }
                        }
                    }
                }
                
                inputStream.close()
                connection.disconnect()
                
            } catch (e: Exception) {
                reconnectAttempts++
                val delayMs = minOf(2000L * reconnectAttempts, 10000L)
                Log.e(TAG, "Download error (attempt $reconnectAttempts): ${e.message}")
                
                if (isPlaying && reconnectAttempts < maxReconnectAttempts) {
                    Log.d(TAG, "Reconnecting in ${delayMs}ms...")
                    delay(delayMs)
                } else if (reconnectAttempts >= maxReconnectAttempts) {
                    Log.e(TAG, "Max reconnection attempts reached")
                    isPlaying = false
                }
            }
        }
    }
    
    // Simple linear resampling (could be improved with better interpolation)
    private fun resampleAudio(input: ByteArray, inputSize: Int, fromRate: Int, toRate: Int): ByteArray {
        val inputSamples = inputSize / 2
        val outputSamples = (inputSamples.toDouble() * toRate / fromRate).toInt()
        val output = ByteArray(outputSamples * 2)
        
        for (i in 0 until outputSamples) {
            val srcPos = (i.toDouble() * fromRate / toRate)
            val srcIndex = srcPos.toInt()
            
            if (srcIndex < inputSamples - 1) {
                // Linear interpolation
                val frac = srcPos - srcIndex
                val sample1 = ((input[srcIndex * 2 + 1].toInt() shl 8) or (input[srcIndex * 2].toInt() and 0xFF)).toShort()
                val sample2 = ((input[(srcIndex + 1) * 2 + 1].toInt() shl 8) or (input[(srcIndex + 1) * 2].toInt() and 0xFF)).toShort()
                val interpolated = (sample1 + (sample2 - sample1) * frac).toInt().toShort()
                
                output[i * 2] = (interpolated.toInt() and 0xFF).toByte()
                output[i * 2 + 1] = (interpolated.toInt() shr 8).toByte()
            } else if (srcIndex < inputSamples) {
                // Last sample, no interpolation
                output[i * 2] = input[srcIndex * 2]
                output[i * 2 + 1] = input[srcIndex * 2 + 1]
            }
        }
        
        return output
    }
    
    private suspend fun playAudio() {
        Process.setThreadPriority(Process.THREAD_PRIORITY_AUDIO)
        
        // Wait for initial buffering - increased timeout for network delays
        var bufferWaitCount = 0
        while (isPlaying && audioQueue.size < 3 && bufferWaitCount < 150) {
            delay(100)
            bufferWaitCount++
        }
        
        if (!isPlaying || audioQueue.isEmpty()) {
            Log.w(TAG, "Playback aborted - no audio data after ${bufferWaitCount * 100}ms")
            playbackStarted = false
            return
        }
        
        playbackStarted = true
        Log.d(TAG, "Initial buffering complete, ${audioQueue.size} chunks ready")
        
        // Initialize AudioTrack with device-appropriate settings
        val minBufferSize = AudioTrack.getMinBufferSize(
            actualSampleRate,
            AudioFormat.CHANNEL_OUT_MONO,
            AudioFormat.ENCODING_PCM_16BIT
        )
        
        if (minBufferSize == AudioTrack.ERROR_BAD_VALUE || minBufferSize == AudioTrack.ERROR) {
            Log.e(TAG, "Invalid buffer size for ${actualSampleRate}Hz")
            return
        }
        
        // Use larger buffer for smoother playback
        val bufferSize = maxOf(minBufferSize * 4, actualSampleRate * 2)
        
        Log.d(TAG, "Initializing AudioTrack: ${actualSampleRate}Hz, buffer: $bufferSize bytes (min: $minBufferSize)")
        
        try {
            audioTrack = AudioTrack.Builder()
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                        .setFlags(AudioAttributes.FLAG_LOW_LATENCY)
                        .build()
                )
                .setAudioFormat(
                    AudioFormat.Builder()
                        .setSampleRate(actualSampleRate)
                        .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .build()
                )
                .setBufferSizeInBytes(bufferSize)
                .setTransferMode(AudioTrack.MODE_STREAM)
                .setPerformanceMode(AudioTrack.PERFORMANCE_MODE_LOW_LATENCY)
                .build()
        } catch (e: Exception) {
            Log.e(TAG, "AudioTrack creation failed: ${e.message}")
            return
        }
        
        if (audioTrack?.state != AudioTrack.STATE_INITIALIZED) {
            Log.e(TAG, "AudioTrack failed to initialize! State: ${audioTrack?.state}")
            audioTrack?.release()
            audioTrack = null
            return
        }
        
        audioTrack?.setVolume(1.0f) // Set to maximum
        audioTrack?.flush() // Clear any stale buffer state
        audioTrack?.play()
        
        val playState = audioTrack?.playState
        Log.d(TAG, "Playback started, playState=$playState")
        Log.d(TAG, "AudioTrack volume: 1.0 (max)")
        
        if (playState != AudioTrack.PLAYSTATE_PLAYING) {
            Log.e(TAG, "AudioTrack not playing! PlayState: $playState")
            return
        }
        
        var bytesWritten = 0L
        var chunksWritten = 0
        val startTime = System.currentTimeMillis()
        
        while (isPlaying) {
            val chunk = audioQueue.poll()
            if (chunk == null) {
                // Queue empty, wait a bit
                delay(10)
                continue
            }
            
            val track = audioTrack ?: break
            
            if (track.state != AudioTrack.STATE_INITIALIZED) {
                Log.e(TAG, "AudioTrack not initialized!")
                break
            }
            
            var offset = 0
            while (offset < chunk.size && isPlaying) {
                val remaining = chunk.size - offset
                val written = track.write(chunk, offset, remaining, AudioTrack.WRITE_NON_BLOCKING)
                
                if (written < 0) {
                    Log.e(TAG, "Write error: $written")
                    break
                }
                
                if (written == 0) {
                    // Buffer full, wait a bit
                    delay(10)
                    continue
                }
                
                offset += written
                bytesWritten += written
            }
            
            chunksWritten++
            
            // Log every 2 seconds worth of data
            if (chunksWritten % 100 == 0) {
                val elapsed = (System.currentTimeMillis() - startTime) / 1000.0
                val kbps = (bytesWritten * 8 / elapsed / 1000).toInt()
                Log.d(TAG, "Playing: ${bytesWritten / 1024}KB, queue: ${audioQueue.size}, bitrate: ${kbps}kbps")
            }
        }
        
        Log.d(TAG, "Playback ended, total written: ${bytesWritten / 1024}KB")
    }
}
