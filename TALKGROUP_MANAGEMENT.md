# Talkgroup Whitelist/Blacklist Management

## Overview
Manage which talkgroups are enabled or disabled on your system using whitelist and blacklist files. This allows you to filter which channels you want to listen to.

## How It Works

### File Structure
For each system (e.g., system 6643), two files control talkgroup filtering:
- `6643_whitelist.tsv` - List of enabled talkgroup IDs
- `6643_blacklist.tsv` - List of disabled talkgroup IDs

### Filtering Logic
1. **If whitelist has entries**: Only talkgroups in the whitelist are enabled
2. **If whitelist is empty**: All talkgroups are enabled EXCEPT those in the blacklist
3. **Priority**: Whitelist takes precedence over blacklist

## Using the Talkgroup Manager

### Accessing the Manager
1. Navigate to **Settings → Talkgroups**
2. You'll see all talkgroups for the current system

### Managing Talkgroups

#### Enable/Disable Individual Talkgroups
- **Toggle switch** on each talkgroup card to enable/disable
- **Green** = Enabled (in whitelist or not in blacklist)
- **Red** = Disabled (in blacklist)

#### Search and Filter
- **Search bar**: Find talkgroups by ID or name
- **Enabled Only**: Show only enabled talkgroups
- **Disabled Only**: Show only disabled talkgroups

#### Saving Changes
- Click the **Save** button in the app bar
- Changes are written to the whitelist/blacklist files
- Files are saved on the server for OP25 to use

### Visual Indicators
- **Volume up icon** (green) = Talkgroup is enabled
- **Volume off icon** (red) = Talkgroup is disabled
- **System chip** in app bar shows current system ID
- **Counter** shows filtered/total talkgroups

## API Endpoints

### Backend (Go - controller25)

#### GET `/api/talkgroups/list`
Returns all talkgroups for the current system.

**Response:**
```json
{
  "success": true,
  "system_id": "6643",
  "talkgroups": [
    {"id": "27500", "name": "43-WF/WW PD"},
    {"id": "27511", "name": "43 TAC 2"}
  ]
}
```

#### GET `/api/talkgroups/lists`
Returns current whitelist and blacklist.

**Response:**
```json
{
  "success": true,
  "system_id": "6643",
  "whitelist": ["27500", "27511"],
  "blacklist": ["54638", "54702"]
}
```

#### POST `/api/talkgroups/update-lists`
Updates whitelist and blacklist files.

**Request:**
```json
{
  "whitelist": ["27500", "27511"],
  "blacklist": ["54638", "54702"]
}
```

**Response:**
```json
{
  "success": true,
  "message": "Lists updated successfully"
}
```

## File Formats

### Whitelist/Blacklist Format
Simple newline-separated list of talkgroup IDs:
```
27500
27511
27549
```

### Talkgroups File Format
Tab-separated values (TSV):
```
27500	43-WF/WW PD
27511	43 TAC 2
27549	43-FD WB/KI
```

## Example Use Cases

### Scenario 1: Police Only
**Goal**: Listen only to police talkgroups

**Action**: Add all police talkgroup IDs to whitelist
```
6643_whitelist.tsv:
27500
27501
27502
```

Result: Only these talkgroups will be active

### Scenario 2: Exclude Specific Channels
**Goal**: Listen to everything except data channels

**Action**: Add data channel IDs to blacklist, keep whitelist empty
```
6643_blacklist.tsv:
54502
54501
54638
```

Result: All talkgroups except these will be active

### Scenario 3: Emergency Services Only
**Goal**: Listen only to fire, police, and EMS

**Action**: Add emergency service IDs to whitelist
```
6643_whitelist.tsv:
27500
27549
27552
27710
27711
```

Result: Only emergency services are active

## Technical Details

### Flutter Service (TalkgroupService)
- Loads talkgroups from `/api/talkgroups/list`
- Loads whitelist/blacklist from `/api/talkgroups/lists`
- Provides `isEnabled(tgid)` method for filtering
- Auto-refreshes every 60 seconds
- Notifies listeners on changes

### Go Backend
- Reads TSV files from `systems/{systemId}/` directory
- Writes updates atomically
- Validates system ID from current trunk file
- Logs all list updates

### Files Modified
- `controller25/main.go` - Added 3 new API endpoints
- `mch25/lib/service/talkgroup_service.dart` - Added whitelist/blacklist support
- `mch25/lib/screens/talkgroup_management_screen.dart` - New UI for management
- `mch25/lib/screens/settings_screen.dart` - Added menu item

## Benefits
- ✅ **Reduce noise**: Only listen to relevant channels
- ✅ **Save bandwidth**: Don't process unwanted talkgroups
- ✅ **Focus monitoring**: Concentrate on important channels
- ✅ **Easy management**: Toggle channels with a switch
- ✅ **Persistent**: Settings survive restarts
- ✅ **System-specific**: Different lists per system

## Future Enhancements
- Bulk enable/disable by category
- Import/export list files
- Preset configurations (Emergency, Fire, Police, etc.)
- Talkgroup activity statistics
- Quick enable/disable from scanner screen
