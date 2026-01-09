# Audio Output Testing Guide

## Step 1: Test System Audio
First verify the device can play audio at all:

```bash
# Generate a 1-second 440Hz tone (A note)
adb shell "mkdir -p /sdcard/test"
adb shell "tinymix"  # Check if audio mixer is available

# Or use media player to test
adb shell "am start -a android.intent.action.VIEW -d 'https://www.kozco.com/tech/piano2.wav'"
```

## Step 2: Check App Audio Logs

Start the app, enable audio, then:

```bash
adb logcat -c
adb logcat | grep -E "AudioStreamPlayer|volume|Volume|STREAM_MUSIC"
```

### Expected Output:
```
D/AudioStreamPlayer: Starting audio stream from: http://...
D/AudioStreamPlayer: Device native sample rate: 48000 Hz  
D/AudioStreamPlayer: Using sample rate: 44100 Hz (source: 8000 Hz)
D/AudioStreamPlayer: Media volume: 25/30
D/AudioStreamPlayer: Initializing AudioTrack: 44100Hz, buffer: 176400 bytes
D/AudioStreamPlayer: Playback started, playState=3
D/AudioStreamPlayer: AudioTrack volume: 1.0 (max)
D/AudioStreamPlayer: Playing: 128KB, queue: 15, bitrate: 705kbps
```

## Step 3: Manual Volume Check

While app is running:

```bash
# Check current volume
adb shell "dumpsys audio | grep 'STREAM_MUSIC' | head -5"

# Set volume to max
adb shell "media volume --set 30 --stream 3"

# Verify
adb shell "dumpsys audio | grep 'Stream volumes'"
```

## Step 4: Check Audio Routing

```bash
adb shell "dumpsys media.audio_flinger | grep -A5 'Output thread'" | grep -E "Output devices|Standby|Sample rate"
```

Should show:
- Output devices: SPEAKER or EARPIECE (not NONE)
- Standby: no (when playing)
- Sample rate: 48000 Hz (or 44100)

## Step 5: Test Direct AudioTrack

Create a simple test app that plays a sine wave:

```kotlin
val sampleRate = 44100
val frequency = 440 // A note
val duration = 2 // seconds
val numSamples = duration * sampleRate
val samples = ShortArray(numSamples)

for (i in 0 until numSamples) {
    samples[i] = (32767 * sin(2 * PI * frequency * i / sampleRate)).toInt().toShort()
}

val audioTrack = AudioTrack.Builder()
    .setAudioAttributes(AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_MEDIA)
        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
        .build())
    .setAudioFormat(AudioFormat.Builder()
        .setSampleRate(sampleRate)
        .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
        .build())
    .setTransferMode(AudioTrack.MODE_STATIC)
    .setBufferSizeInBytes(numSamples * 2)
    .build()

audioTrack.write(samples, 0, numSamples)
audioTrack.play()
```

## Common Issues

### No Sound - Checklist:
1. ✓ Volume > 0 (check physical buttons)
2. ✓ Not muted (check notification shade)  
3. ✓ Bluetooth not connected (stealing audio)
4. ✓ Do Not Disturb is OFF
5. ✓ App has INTERNET permission
6. ✓ Server is actually streaming audio
7. ✓ AudioTrack playState == 3 (PLAYING)
8. ✓ Output device is SPEAKER or EARPIECE (not NONE)

### Very Quiet Audio:
- Media volume too low
- AudioTrack volume not set to 1.0
- Content type wrong (should be SPEECH for voice)
- Sample rate mismatch causing speed/pitch issues

### Distorted/Garbled Audio:
- Wrong sample rate (needs resampling)
- Buffer underruns (increase buffer size)
- Incorrect audio format (must be PCM 16-bit)
- Endianness issues (should be little-endian)

## Quick Test Command

```bash
# All-in-one test
adb logcat -c && \
adb shell "media volume --set 30 --stream 3" && \
echo "Start audio in app now..." && \
sleep 3 && \
adb logcat -d | grep -E "AudioStreamPlayer" | head -20
```
