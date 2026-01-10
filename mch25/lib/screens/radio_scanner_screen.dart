import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config.dart';
import '../service/mdns_scanner_service.dart';
import '../service/op25_api_service.dart';
import '../audio/audio_metadata_service.dart';
import '../service/talkgroup_service.dart';
import '../service/gps_site_hopping_service.dart';
import '../service/op25_control_service.dart';
import 'log_screen.dart';
import 'scan_grid_screen.dart';
import 'settings_screen.dart';
import 'site_details_screen.dart';

class RadioScannerScreen extends StatefulWidget {
  @override
  State<RadioScannerScreen> createState() => _RadioScannerScreenState();
}

class _RadioScannerScreenState extends State<RadioScannerScreen> {
  int _selectedIndex = 0;
  final PageController _pageController = PageController();

  static final List<Widget> _screens = [
    ScannerScreen(),
    ScanGridScreen(),
    SiteDetailsScreen(),
    LogScreen(),
    SettingsScreen(),
  ];

  static final List<_NavItemData> _navItems = [
    _NavItemData(icon: Icons.radio, label: "Scanner"),
    _NavItemData(icon: Icons.grid_view, label: "ScanGrid"),
    _NavItemData(icon: Icons.cell_tower, label: "Site Details"),
    _NavItemData(icon: Icons.list_alt, label: "Log"),
    _NavItemData(icon: Icons.settings, label: "Settings"),
  ];

  void _onNavTap(int index) {
    setState(() {
      _selectedIndex = index;
    });
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.ease,
    );
  }

  void _onPageChanged(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Use MediaQuery to get bottom padding for devices with gesture navigation
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      body: SafeArea(
        child: PageView(
          controller: _pageController,
          physics: const BouncingScrollPhysics(),
          onPageChanged: _onPageChanged,
          children: _screens,
        ),
      ),
      bottomNavigationBar: Container(
        color: const Color(0xFF202020),
        padding: EdgeInsets.only(
          top: 8,
          bottom: bottomPadding > 0 ? bottomPadding : 8,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: List.generate(_navItems.length, (index) {
            final item = _navItems[index];
            final selected = _selectedIndex == index;
            return GestureDetector(
              onTap: () => _onNavTap(index),
              child: _NavItem(
                icon: item.icon,
                label: item.label,
                selected: selected,
              ),
            );
          }),
        ),
      ),
    );
  }
}

class _NavItemData {
  final IconData icon;
  final String label;
  const _NavItemData({required this.icon, required this.label});
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  const _NavItem(
      {required this.icon, required this.label, this.selected = false});
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: selected ? Colors.white : Colors.white54, size: 28),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.white54,
            fontSize: 12,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            letterSpacing: 1.0,
          ),
        ),
      ],
    );
  }
}

// The main Scanner screen (stunning redesign)
class ScannerScreen extends StatefulWidget {
  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  
  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }
  
  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final mDNSStatus = context.watch<mDNScannerService>().status;
    final serverIp = context.watch<AppConfig>().serverIp;

    // Watch services for talkgroup data
    final apiService = context.watch<Op25ApiService>();
    final audioMetadata = context.watch<AudioMetadataService>();
    final talkgroupService = context.watch<TalkgroupService>();
    final gpsService = context.watch<GpsSiteHoppingService>();
    final controlService = context.watch<Op25ControlService>();

    // ---- START: DATA LOGIC ----

    // Prefer audio metadata (synchronized with audio) over API polling
    final sourceId = audioMetadata.sourceId ?? apiService.talkgroupData?.srcid ?? 0;
    final talkgroupIdValue = audioMetadata.talkgroupId ?? apiService.talkgroupData?.tgid ?? 0;
    
    // Get talkgroup name from service
    String talkgroup;
    if (talkgroupIdValue > 0) {
      final tgName = talkgroupService.getTalkgroupName(talkgroupIdValue);
      talkgroup = '$tgName';
    } else {
      talkgroup = 'Scanning...';
    }

    // Get trunk info for system details
    final trunkInfo = apiService.data?.trunkInfo;

    // Get Control Channel from backend
    final controlChannelMhz = apiService.controlChannelMhz;
    
    final isActive = sourceId > 0 || talkgroupIdValue > 0;
    final isOp25Running = controlService.isRunning;
    final op25Data = apiService.data;

    // ---- END: DATA LOGIC ----

    return Container(
      decoration: AppTheme.gradientBackground,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Determine if we have enough width for split-screen
            final availableWidth = constraints.maxWidth;
            final availableHeight = constraints.maxHeight;
            final bool useSplitScreen = availableWidth > 600; // Landscape/tablet mode
            
            // Calculate responsive sizing based on available space
            final bool isCompact = availableHeight < 600;
            final bool veryCompact = availableHeight < 500;
            
            // Responsive padding and spacing
            final edgePadding = veryCompact ? 8.0 : (isCompact ? 10.0 : 12.0);
            final cardSpacing = veryCompact ? 4.0 : (isCompact ? 6.0 : 8.0);
            final headerPadding = veryCompact ? 6.0 : (isCompact ? 8.0 : 10.0);
            
            // Responsive font sizes
            final headerFontSize = veryCompact ? 13.0 : (isCompact ? 14.0 : 15.0);
            final idFontSize = veryCompact ? size.width * 0.055 : (isCompact ? size.width * 0.065 : size.width * 0.075);
            final ccFontSize = veryCompact ? size.width * 0.03 : (isCompact ? size.width * 0.035 : size.width * 0.04);
            final tgFontSize = veryCompact ? 16.0 : (isCompact ? 18.0 : 20.0);

            if (useSplitScreen) {
              // Split-screen layout for landscape/tablets
              return Row(
                children: [
                  // Left side - Scanner display
                  Expanded(
                    flex: 3,
                    child: _buildScannerPanel(
                      gpsService, mDNSStatus, serverIp, isActive, sourceId,
                      talkgroupIdValue, controlChannelMhz, talkgroup, trunkInfo,
                      edgePadding, cardSpacing, headerPadding, headerFontSize,
                      idFontSize, ccFontSize, tgFontSize, veryCompact,
                    ),
                  ),
                  // Divider
                  Container(
                    width: 1,
                    color: Colors.cyanAccent.withValues(alpha: 0.2),
                  ),
                  // Right side - Site details summary
                  Expanded(
                    flex: 2,
                    child: _buildSiteDetailsPanel(
                      op25Data, isOp25Running, edgePadding, cardSpacing, veryCompact,
                    ),
                  ),
                ],
              );
            } else {
              // Single column layout for portrait/phones
              return _buildScannerPanel(
                gpsService, mDNSStatus, serverIp, isActive, sourceId,
                talkgroupIdValue, controlChannelMhz, talkgroup, trunkInfo,
                edgePadding, cardSpacing, headerPadding, headerFontSize,
                idFontSize, ccFontSize, tgFontSize, veryCompact,
              );
            }
          },
        ),
      ),
    );
  }

  Widget _buildScannerPanel(
    GpsSiteHoppingService gpsService,
    ServerStatus mDNSStatus,
    String serverIp,
    bool isActive,
    int sourceId,
    int talkgroupIdValue,
    double controlChannelMhz,
    String talkgroup,
    TrunkUpdate? trunkInfo,
    double edgePadding,
    double cardSpacing,
    double headerPadding,
    double headerFontSize,
    double idFontSize,
    double ccFontSize,
    double tgFontSize,
    bool veryCompact,
  ) {
    return Padding(
      padding: EdgeInsets.all(edgePadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top bar: Title, Status + Time
          _buildHeader(gpsService, mDNSStatus, serverIp, headerPadding, headerFontSize, veryCompact),
          SizedBox(height: cardSpacing),
          // Main content - must fit in remaining space
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Main Display Card
                Expanded(
                  flex: 3,
                  child: _buildMainDisplayCard(
                    isActive,
                    sourceId,
                    talkgroupIdValue,
                    controlChannelMhz,
                    idFontSize,
                    ccFontSize,
                    veryCompact,
                  ),
                ),
                SizedBox(height: cardSpacing),
                // Talkgroup Card
                Expanded(
                  flex: 2,
                  child: _buildTalkgroupCard(talkgroup, tgFontSize, isActive, veryCompact),
                ),
                SizedBox(height: cardSpacing),
                // System Info Grid - always visible
                _buildSystemInfoGrid(trunkInfo, veryCompact),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSiteDetailsPanel(
    Op25Data? op25Data,
    bool isOp25Running,
    double edgePadding,
    double cardSpacing,
    bool compact,
  ) {
    return Padding(
      padding: EdgeInsets.all(edgePadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            padding: EdgeInsets.all(compact ? 8 : 10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(compact ? 8 : 10),
              border: Border.all(
                color: Colors.blueAccent.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.cell_tower, size: compact ? 16 : 18, color: Colors.blueAccent),
                SizedBox(width: 8),
                Text(
                  "SITE INFO",
                  style: TextStyle(
                    fontSize: compact ? 12 : 14,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: cardSpacing),
          
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!isOp25Running)
                    _buildSiteDetailCard(
                      "Status",
                      "OP25 Not Running",
                      Icons.power_off,
                      Colors.redAccent,
                      compact,
                    )
                  else if (op25Data == null)
                    _buildSiteDetailCard(
                      "Status",
                      "Connecting...",
                      Icons.sync,
                      Colors.orangeAccent,
                      compact,
                    )
                  else ...[
                    // System Info - only show if not N/A
                    if (op25Data.trunkInfo != null) ...[
                      if (op25Data.trunkInfo!.systemName != 'N/A') ...[
                        _buildSiteDetailCard(
                          "System",
                          op25Data.trunkInfo!.systemName,
                          Icons.router,
                          Colors.cyanAccent,
                          compact,
                        ),
                        SizedBox(height: cardSpacing),
                      ],
                      if (op25Data.trunkInfo!.systemType != 'N/A') ...[
                        _buildSiteDetailCard(
                          "Type",
                          op25Data.trunkInfo!.systemType,
                          Icons.dns,
                          Colors.blueAccent,
                          compact,
                        ),
                        SizedBox(height: cardSpacing),
                      ],
                      if (op25Data.trunkInfo!.callsign != null && 
                          op25Data.trunkInfo!.callsign!.isNotEmpty &&
                          op25Data.trunkInfo!.callsign != 'N/A') ...[
                        _buildSiteDetailCard(
                          "Callsign",
                          op25Data.trunkInfo!.callsign!,
                          Icons.radio,
                          Colors.purpleAccent,
                          compact,
                        ),
                        SizedBox(height: cardSpacing),
                      ],
                      if (op25Data.trunkInfo!.rfid != '-' || op25Data.trunkInfo!.stid != '-') ...[
                        _buildSiteDetailCard(
                          "RFSS/Site",
                          "${op25Data.trunkInfo!.rfid}/${op25Data.trunkInfo!.stid}",
                          Icons.location_on,
                          Colors.greenAccent,
                          compact,
                        ),
                        SizedBox(height: cardSpacing),
                      ],
                    ],
                    
                    // Frequencies count
                    if (op25Data.trunkInfo?.frequencyData.isNotEmpty ?? false) ...[
                      _buildSiteDetailCard(
                        "Frequencies",
                        "${op25Data.trunkInfo!.frequencyData.length}",
                        Icons.bar_chart,
                        Colors.tealAccent,
                        compact,
                      ),
                      SizedBox(height: cardSpacing),
                    ],
                    
                    // Adjacent sites count
                    if (op25Data.trunkInfo?.adjacentSites.isNotEmpty ?? false) ...[
                      _buildSiteDetailCard(
                        "Adjacent Sites",
                        "${op25Data.trunkInfo!.adjacentSites.length}",
                        Icons.wifi_tethering,
                        Colors.amberAccent,
                        compact,
                      ),
                      SizedBox(height: cardSpacing),
                    ],
                    
                    // Receiver info
                    if (op25Data.rxInfo?.fineTune != null) ...[
                      _buildSiteDetailCard(
                        "Fine Tune",
                        "${op25Data.rxInfo!.fineTune!.toStringAsFixed(1)} Hz",
                        Icons.tune,
                        Colors.orangeAccent,
                        compact,
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSiteDetailCard(
    String label,
    String value,
    IconData icon,
    Color accentColor,
    bool compact,
  ) {
    return Container(
      padding: EdgeInsets.all(compact ? 10 : 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(compact ? 8 : 10),
        border: Border.all(
          color: accentColor.withValues(alpha: 0.4),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(compact ? 6 : 8),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(compact ? 6 : 8),
            ),
            child: Icon(icon, size: compact ? 16 : 18, color: accentColor),
          ),
          SizedBox(width: compact ? 10 : 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: compact ? 9 : 10,
                    color: Colors.white54,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: compact ? 13 : 14,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(GpsSiteHoppingService gpsService, ServerStatus mDNSStatus, String serverIp, double padding, double fontSize, bool compact) {
    return Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(compact ? 8 : 12),
        border: Border.all(
          color: Colors.cyanAccent.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: EdgeInsets.all(compact ? 6 : 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.cyan.withValues(alpha: 0.3), Colors.blue.withValues(alpha: 0.3)],
                  ),
                  borderRadius: BorderRadius.circular(compact ? 6 : 8),
                ),
                child: Icon(Icons.radio, color: Colors.cyanAccent, size: compact ? 18 : 24),
              ),
              SizedBox(width: compact ? 8 : 12),
              Expanded(
                child: Text(
                  mDNSStatus == ServerStatus.found && serverIp.isNotEmpty
                      ? "MCH25:$serverIp"
                      : "MCH25",
                  style: TextStyle(
                    fontSize: fontSize,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                    color: Colors.white,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (gpsService.isEnabled)
                Container(
                  padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 8, vertical: compact ? 3 : 5),
                  margin: EdgeInsets.only(right: compact ? 4 : 8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.green.withValues(alpha: 0.3), Colors.greenAccent.withValues(alpha: 0.2)],
                    ),
                    borderRadius: BorderRadius.circular(compact ? 8 : 12),
                    border: Border.all(color: Colors.greenAccent, width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.my_location, size: compact ? 12 : 14, color: Colors.greenAccent),
                      if (!compact) ...[
                        SizedBox(width: 4),
                        Text(
                          'GPS',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.greenAccent,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                      if (gpsService.isHopping) ...[
                        SizedBox(width: 4),
                        SizedBox(
                          width: 10,
                          height: 10,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(Colors.greenAccent),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              TimeDisplayLandscape(fontSize: fontSize - 2),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusIndicator(ServerStatus status) {
    Color indicatorColor;
    switch (status) {
      case ServerStatus.found:
        indicatorColor = Colors.greenAccent;
        break;
      case ServerStatus.searching:
        indicatorColor = Colors.orangeAccent;
        break;
      default:
        indicatorColor = Colors.redAccent;
    }
    
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: indicatorColor,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: indicatorColor.withValues(alpha: 0.6),
            blurRadius: 8,
            spreadRadius: 2,
          ),
        ],
      ),
    );
  }

  Widget _buildMainDisplayCard(
    bool isActive,
    int sourceId,
    int talkgroupIdValue,
    double controlChannelMhz,
    double idFontSize,
    double ccFontSize,
    bool compact,
  ) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: EdgeInsets.all(compact ? 8 : 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isActive
              ? [
                  Colors.cyan.withValues(alpha: 0.15),
                  Colors.blue.withValues(alpha: 0.1),
                ]
              : [
                  Colors.grey.withValues(alpha: 0.1),
                  Colors.grey.withValues(alpha: 0.05),
                ],
        ),
        borderRadius: BorderRadius.circular(compact ? 8 : 12),
        border: Border.all(
          color: isActive ? Colors.cyanAccent.withValues(alpha: 0.5) : Colors.grey.withValues(alpha: 0.3),
          width: compact ? 1.5 : 2,
        ),
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: Colors.cyanAccent.withValues(alpha: 0.2),
                  blurRadius: compact ? 8 : 12,
                  spreadRadius: compact ? 1 : 2,
                ),
              ]
            : [],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Row(
            children: [
              if (isActive)
                AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, child) {
                    return Container(
                      width: compact ? 6 : 8,
                      height: compact ? 6 : 8,
                      margin: EdgeInsets.only(right: compact ? 6 : 8),
                      decoration: BoxDecoration(
                        color: Colors.redAccent,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.redAccent.withValues(alpha: _pulseController.value * 0.8),
                            blurRadius: 8 * _pulseController.value,
                            spreadRadius: 2 * _pulseController.value,
                          ),
                        ],
                      ),
                    );
                  },
                ),
              Flexible(
                child: Text(
                  isActive ? "ACTIVE" : "MONITOR",
                  style: TextStyle(
                    fontSize: compact ? 9 : 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                    color: isActive ? Colors.cyanAccent : Colors.white54,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                (sourceId == 0 && talkgroupIdValue == 0)
                    ? "SCANNING"
                    : "SRC: $sourceId   TG: $talkgroupIdValue",
                maxLines: 1,
                style: TextStyle(
                  fontFamily: 'Segment7',
                  fontSize: idFontSize,
                  fontWeight: FontWeight.bold,
                  color: isActive ? Colors.cyanAccent : Colors.white,
                  letterSpacing: 1.5,
                  shadows: isActive
                      ? [
                          Shadow(
                            color: Colors.cyanAccent.withValues(alpha: 0.5),
                            blurRadius: 8,
                          ),
                        ]
                      : [],
                ),
              ),
            ),
          ),
          Row(
            children: [
              Icon(Icons.settings_input_antenna, size: compact ? 10 : 12, color: Colors.cyanAccent.withValues(alpha: 0.7)),
              SizedBox(width: compact ? 3 : 4),
              Flexible(
                child: Text(
                  "CC: ${controlChannelMhz.toStringAsFixed(6)}",
                  style: TextStyle(
                    fontFamily: 'Segment7',
                    fontSize: ccFontSize,
                    color: Colors.cyanAccent.withValues(alpha: 0.9),
                    letterSpacing: 0.8,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTalkgroupCard(String talkgroup, double fontSize, bool isActive, bool compact) {
    return Container(
      padding: EdgeInsets.all(compact ? 8 : 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(compact ? 8 : 10),
        border: Border.all(
          color: isActive ? Colors.greenAccent.withValues(alpha: 0.4) : Colors.grey.withValues(alpha: 0.2),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Row(
            children: [
              Icon(
                Icons.group,
                size: compact ? 12 : 14,
                color: isActive ? Colors.greenAccent : Colors.white54,
              ),
              SizedBox(width: compact ? 4 : 6),
              Text(
                "TALKGROUP",
                style: TextStyle(
                  fontSize: compact ? 8 : 9,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                  color: Colors.white54,
                ),
              ),
            ],
          ),
          Expanded(
            child: Center(
              child: Text(
                talkgroup,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.left,
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.w600,
                  color: isActive ? Colors.greenAccent : Colors.white,
                  letterSpacing: 0.5,
                  height: 1.1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSystemInfoGrid(TrunkUpdate? trunkInfo, bool compact) {
    return Container(
      padding: EdgeInsets.all(compact ? 10 : 14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(compact ? 8 : 10),
        border: Border.all(
          color: Colors.blue.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, size: compact ? 12 : 14, color: Colors.blueAccent),
              SizedBox(width: compact ? 6 : 8),
              Flexible(
                child: Text(
                  "SYSTEM INFO",
                  style: TextStyle(
                    fontSize: compact ? 9 : 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                    color: Colors.white54,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? 6 : 10),
          Wrap(
            spacing: compact ? 6.0 : 8.0,
            runSpacing: compact ? 6.0 : 8.0,
            children: [
              _buildInfoChip("NAC", trunkInfo?.nac ?? "-", Colors.purple, compact),
              _buildInfoChip("WACN", trunkInfo?.wacn ?? "-", Colors.blue, compact),
              _buildInfoChip("SysID", trunkInfo?.sysid ?? "-", Colors.teal, compact),
              _buildInfoChip("TSBKs", "-", Colors.orange, compact),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoChip(String label, String value, Color accentColor, bool compact) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10, vertical: compact ? 5 : 7),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            accentColor.withValues(alpha: 0.2),
            accentColor.withValues(alpha: 0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(compact ? 14 : 18),
        border: Border.all(
          color: accentColor.withValues(alpha: 0.4),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            "$label: ",
            style: TextStyle(
              color: accentColor.withValues(alpha: 0.8),
              fontSize: compact ? 10 : 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: compact ? 11 : 12,
            ),
          ),
        ],
      ),
    );
  }

  String _getStatusText(ServerStatus status, String ip) {
    switch (status) {
      case ServerStatus.searching:
        return 'Searching for server...';
      case ServerStatus.found:
        return 'Connected to $ip';
      case ServerStatus.notFound:
        return 'Server not found. Retrying...';
      case ServerStatus.stopped:
        return 'Discovery stopped.';
    }
  }
}

class TimeDisplayLandscape extends StatefulWidget {
  final double fontSize;
  const TimeDisplayLandscape({Key? key, required this.fontSize})
      : super(key: key);

  @override
  State<TimeDisplayLandscape> createState() => _TimeDisplayLandscapeState();
}

class _TimeDisplayLandscapeState extends State<TimeDisplayLandscape> {
  late String _time;

  @override
  void initState() {
    super.initState();
    _updateTime();
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      _updateTime();
      return true;
    });
  }

  void _updateTime() {
    final now = DateTime.now();
    setState(() {
      _time =
          "${(now.hour % 12 == 0 ? 12 : now.hour % 12).toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')} ${now.hour < 12 ? "AM" : "PM"}";
    });
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _time,
      style: TextStyle(
        fontSize: widget.fontSize,
        fontWeight: FontWeight.w400,
        color: Colors.white,
        letterSpacing: 1.2,
      ),
    );
  }
}