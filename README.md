# MobileControlHead

A mobile control system for OP25 (boatbod fork) consisting of a Go backend and Flutter mobile app.

## Overview

MobileControlHead provides a user-friendly mobile interface for controlling and monitoring OP25 Software Defined Radio (SDR) systems. It consists of:

- **controller25**: Go backend that manages the OP25 process, streams audio/logs, and provides a REST API
- **mch25**: Flutter mobile app for iOS/Android that provides remote control and real-time monitoring

## Features

### Backend (controller25)
- OP25 process management (start/stop/restart)
- Real-time audio streaming over HTTP (UDP to HTTP bridge)
- Live log streaming with talkgroup parsing
- REST API for configuration and control
- Automatic cleanup of stale OP25 processes
- mDNS service discovery
- Talkgroup metadata injection into audio stream headers

### Mobile App (mch25)
- **Scanner Screen**: Real-time talkgroup and source ID display synchronized with audio
- **Configuration**: Manage SDR device settings (device type, sample rate, LNA gain)
- **Log Viewer**: Live streaming logs from OP25
- **Site Details**: Control channel and system information
- **Audio Streaming**: Built-in audio player with automatic reconnection
- **Network Discovery**: Automatic backend discovery via mDNS

## Architecture

```
┌─────────────────┐
│   Flutter App   │
│    (mch25)      │
└────────┬────────┘
         │ HTTP REST API
         │ Audio Stream (/audio.wav)
         │ Log Stream (/logs)
┌────────▼────────┐
│  Go Backend     │
│ (controller25)  │
└────────┬────────┘
         │ Spawns & Manages
         │ UDP Audio (port 23456)
┌────────▼────────┐
│   OP25 rx.py    │
│  (boatbod fork) │
└─────────────────┘
```

## Requirements

### Backend
- Go 1.21 or later
- OP25 (boatbod fork) installed
- Linux (tested on Raspberry Pi and x86_64)

### Mobile App
- Flutter 3.x
- Dart 3.x
- iOS 12+ or Android 5.0+

## Installation

### Backend Setup

1. Clone the repository:
```bash
git clone https://github.com/SarahRoseLives/MobileControlHead.git
cd MobileControlHead/controller25
```

2. Edit `config.ini` and set the path to your OP25 installation:
```ini
op25rxpath = /path/to/op25/op25/gr-op25_repeater/apps

[op25]
sdr_device = rtl
sample_rate = 1400000
lna_gain = 47
trunk_file = trunk.tsv
```

3. Build the backend:
```bash
go build -o controller25 .
```

4. Run the backend:
```bash
./controller25
```

The backend will listen on port 8000 and advertise itself via mDNS as `_controller25._tcp`.

### Mobile App Setup

1. Navigate to the Flutter app directory:
```bash
cd ../mch25
```

2. Install dependencies:
```bash
flutter pub get
```

3. Build and run:
```bash
# For Android
flutter run

# For iOS
flutter run -d ios
```

## Configuration

### Backend API Endpoints

- `GET /api/op25/status` - Get OP25 process status
- `POST /api/op25/start` - Start OP25 with current configuration
- `POST /api/op25/stop` - Stop OP25 process
- `GET /api/op25/config` - Get current OP25 configuration
- `POST /api/op25/config` - Update OP25 configuration
- `GET /api/talkgroup` - Get active talkgroup data
- `GET /audio.wav` - Audio stream endpoint
- `GET /logs` - Log stream endpoint (Server-Sent Events)

### Mobile App Configuration

The app can be configured through the Settings screen:
- **Manual OP25 Config**: Set SDR device, sample rate, LNA gain, and trunk file
- **Server Connection**: Automatically discovered via mDNS or manually entered

## Features in Detail

### Talkgroup Synchronization

The system extracts talkgroup information from OP25 logs and synchronizes it with the audio stream:

1. Log parser extracts `tgid` (talkgroup ID), `srcid` (source ID), and `freq` (frequency) from OP25 output
2. Talkgroup data is injected into HTTP headers (`X-Talkgroup-ID`, `X-Source-ID`) of the audio stream
3. Mobile app polls both the audio headers (500ms interval) and API endpoint (1s interval)
4. Audio metadata is preferred for display to ensure synchronization with what you're hearing
5. Talkgroup data expires after 5 seconds of inactivity

### Audio Streaming

- OP25 sends audio via UDP to 127.0.0.1:23456
- Backend listens and rebroadcasts as HTTP WAV stream
- Mobile app uses just_audio (iOS/Android) or audioplayers (Linux) for playback
- Automatic reconnection on connection loss
- Configurable buffer size and reconnection delays

### Process Management

- Automatic cleanup of existing rx.py processes on startup
- Prevents "Address already in use" errors on port 8080
- Graceful shutdown with proper resource cleanup
- Audio broadcaster started before OP25 to ensure UDP listener is ready

## Building for Production

### Backend (ARM64 for Raspberry Pi)
```bash
cd controller25
./build_arm.sh
```

### Mobile App (Android Release)
```bash
cd mch25
flutter build apk --release
# APK will be in build/app/outputs/flutter-apk/
```

### Mobile App (iOS Release)
```bash
cd mch25
flutter build ios --release
# Open ios/Runner.xcworkspace in Xcode to archive and distribute
```

## Troubleshooting

### Audio doesn't play after restart
- The backend now starts the audio broadcaster before OP25 to prevent packet loss
- There's a 500ms delay after shutdown to ensure the UDP port is fully released
- If issues persist, check that UDP port 23456 is not blocked by a firewall

### OP25 fails to start - "Address already in use"
- The backend automatically kills existing rx.py processes on startup
- If this fails, manually kill processes: `pkill -f rx.py`

### Mobile app can't find backend
- Ensure both devices are on the same network
- Check that mDNS/Bonjour is enabled on your network
- Try manually entering the backend IP address in settings

### No talkgroup data displayed
- Check that OP25 is receiving traffic (view logs)
- Talkgroup data expires after 5 seconds - wait for new transmissions
- Verify the log parser is receiving data from OP25

## Contributing

Pull requests are welcome! For major changes, please open an issue first to discuss what you would like to change.

## License

This project interfaces with OP25, which is licensed under the GPLv3. Please ensure compliance with OP25's licensing terms.

## Credits

- OP25 by boatbod and contributors
- Flutter framework by Google
- Go standard library and community packages

## Author

Sarah Rose ([@SarahRoseLives](https://github.com/SarahRoseLives))
