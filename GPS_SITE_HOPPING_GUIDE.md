# GPS Site Hopping Feature Guide

## Overview
Automatic GPS-based site hopping that switches between radio sites as your location changes to ensure optimal reception.

## How to Use

### Enable GPS Site Hopping

1. **Navigate to Settings → Systems** (Downloaded Systems)
2. **Find the GPS Site Hopping toggle** at the top of each system card
3. **Toggle the switch to ON** to enable automatic site hopping
4. The app will request location permission if not already granted

### Visual Indicators

#### On Scanner Screen
- **Green "GPS" badge** appears in top-right when hopping is enabled
- **Spinning indicator** shows when actively switching sites

#### On Systems Screen
- **Green "GPS Hopping" badge** in the app bar when enabled
- **Toggle switch** on each system card to enable/disable
- **Red location_off button** in app bar to quickly disable
- **Distance indicators** next to each site (sorted closest first)

### How It Works

1. **Location Tracking**: Checks your GPS location every 30 seconds
2. **Distance Calculation**: Calculates distance to all available sites using Haversine formula
3. **Automatic Switching**: Switches to closest site if:
   - Site is different from current
   - Distance is less than 5km threshold
4. **Seamless Transition**: Automatically updates OP25 config and restarts with new site

### Features

- ✅ **Sorted by distance**: Sites always show closest first
- ✅ **Real-time distance**: Shows meters (<1km) or kilometers
- ✅ **Smart hopping**: Only hops when closer site is found
- ✅ **Low battery impact**: Uses medium accuracy GPS with 10s timeout
- ✅ **Persistent**: Runs in background while system is active
- ✅ **Visual feedback**: See when hopping is occurring

### Configuration

Edit `/home/rose/PycharmProjects/OP25MCH/mch25/lib/service/gps_site_hopping_service.dart`:

```dart
// Distance threshold to trigger site change (default: 5km)
static const double hopThresholdKm = 5.0;

// How often to check location (default: 30 seconds)
static const Duration checkInterval = Duration(seconds: 30);
```

### Permissions Required

- `ACCESS_FINE_LOCATION` - For precise GPS coordinates
- `ACCESS_COARSE_LOCATION` - Fallback for approximate location

Already added to `AndroidManifest.xml`

## Technical Details

### Service Architecture
- **GpsSiteHoppingService**: Background service using Provider pattern
- **Location Provider**: Geolocator package for cross-platform GPS
- **Distance Algorithm**: Haversine formula for accurate Earth-surface distances
- **State Management**: ChangeNotifier for reactive UI updates

### Files Modified
- `lib/service/gps_site_hopping_service.dart` - Core hopping logic
- `lib/screens/systems_settings_screen.dart` - UI controls and distance sorting
- `lib/screens/radio_scanner_screen.dart` - GPS indicator on main screen
- `lib/main.dart` - Service initialization
- `android/app/src/main/AndroidManifest.xml` - Location permissions
- `pubspec.yaml` - Geolocator dependency

### API Integration
- Uses existing `/api/systems/list` to load site data
- Uses `/api/op25/config` to update trunk file
- Uses `/api/op25/start` to restart with new site
