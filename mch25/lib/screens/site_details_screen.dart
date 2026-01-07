import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../service/op25_api_service.dart';
import 'package:intl/intl.dart';
import '../service/op25_control_service.dart'; // Import the control service

class SiteDetailsScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // Watch both the API service for data and the Control service for status
    final apiService = context.watch<Op25ApiService>();
    final controlService = context.watch<Op25ControlService>();

    final op25Data = apiService.data;
    final isOp25Running = controlService.isRunning;

    Widget bodyWidget;

    if (!isOp25Running) {
      // Case 1: OP25 is confirmed to be OFF. Show a clear message.
      bodyWidget = const Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.power_off_outlined, color: Colors.white54, size: 48),
              SizedBox(height: 16),
              Text(
                "OP25 Not Running",
                style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text(
                "Go to Settings > Manual OP25 Config to start the process.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 16),
              ),
            ],
          ),
        ),
      );
    } else if (op25Data == null) {
      // Case 2: OP25 is ON, but we don't have data yet.
      // This covers the initial connection phase and any temporary reconnections.
      bodyWidget = const Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 20),
              Text(
                "Connecting to OP25...",
                style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text(
                "Waiting for system data.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 16),
              ),
            ],
          ),
        ),
      );
    } else {
      // Case 3: OP25 is ON and we have data. Display the details.
      bodyWidget = SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (op25Data.trunkInfo != null)
              _buildTrunkInfoCard(op25Data.trunkInfo!),
            const SizedBox(height: 16),
            if (op25Data.rxInfo != null)
              _buildRxInfoCard(op25Data.rxInfo!),
            const SizedBox(height: 16),
            if (op25Data.channelInfo?.channels.isNotEmpty ?? false)
              _buildChannelsCard(context.watch<Op25ApiService>()),
            const SizedBox(height: 16),
            if (op25Data.trunkInfo?.patches.isNotEmpty ?? false)
              _buildPatchesCard(op25Data.trunkInfo!),
            const SizedBox(height: 16),
            if (op25Data.trunkInfo?.adjacentSites.isNotEmpty ?? false)
              _buildAdjacentSitesCard(op25Data.trunkInfo!),
            const SizedBox(height: 16),
            if (op25Data.trunkInfo?.frequencyData.isNotEmpty ?? false)
              _buildFrequenciesCard(op25Data.trunkInfo!),
            const SizedBox(height: 16),
            if (op25Data.trunkInfo?.bandPlan.isNotEmpty ?? false)
              _buildBandPlanCard(op25Data.trunkInfo!),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: bodyWidget,
      ),
    );
  }

  // Updated to include callsign
  Widget _buildTrunkInfoCard(TrunkUpdate info) {
    return _InfoCard(
      title: "System Details: ${info.systemName}",
      icon: Icons.cell_tower,
      children: [
        _buildDetailRow("Type", info.systemType),
        if (info.callsign != null && info.callsign!.isNotEmpty)
          _buildDetailRow("Callsign", info.callsign!),
        _buildDetailRow("NAC", "0x${info.nac}"),
        _buildDetailRow("System ID", info.sysid),
        _buildDetailRow("WACN", info.wacn),
        _buildDetailRow("RFSS", info.rfid),
        _buildDetailRow("Site ID", info.stid),
      ],
    );
  }

  // NEW Card for Receiver Info
  Widget _buildRxInfoCard(RxUpdate info) {
    return _InfoCard(
      title: "Receiver Info",
      icon: Icons.settings_input_hdmi,
      children: [
        if(info.fineTune != null)
          _buildDetailRow("Fine Tune", "${info.fineTune} Hz"),
        if(info.error != null)
          _buildDetailRow("Error", "${info.error} Hz", color: Colors.redAccent),
        _buildDetailRow("Plot Files", info.files.length.toString()),
      ],
    );
  }

  // Updated to show ALL channels, highlighting the active one
  Widget _buildChannelsCard(Op25ApiService apiService) {
    final info = apiService.data!.channelInfo!;
    final activeChannelId = info.channelIds.elementAtOrNull(apiService.channelIndex);

    return _InfoCard(
      title: "Channels",
      icon: Icons.volume_up,
      children: [
        for (var entry in info.channels.entries)
          _ChannelExpansionTile(
            channel: entry.value,
            isActive: entry.key == activeChannelId,
          ),
      ],
    );
  }

  // NEW Card for Patches
  Widget _buildPatchesCard(TrunkUpdate info) {
    return _InfoCard(
      title: "Patches",
      icon: Icons.call_merge,
      children: [
        Table(
            border: TableBorder(horizontalInside: BorderSide(color: Colors.white24, width: 0.5)),
            columnWidths: const {0: FlexColumnWidth(2), 1: FlexColumnWidth(3)},
            children: [
            const TableRow(children: [_HeaderCell('Supergroup'), _HeaderCell('Group')]),
              ...info.patches.entries.expand((entry) {
                final patchData = entry.value as Map<String, dynamic>;
                return patchData.entries.map((subEntry) {
                  final item = subEntry.value;
                  return TableRow(
                    children: [
                      _DataCell(item['sgtag'] ?? item['sg'].toString()),
                      _DataCell(item['gatag'] ?? item['ga'].toString()),
                    ],
                  );
                });
              })
            ],
        )
      ]
    );
  }

  // NEW Card for Adjacent Sites
  Widget _buildAdjacentSitesCard(TrunkUpdate info) {
      return _InfoCard(
        title: "Adjacent Sites",
        icon: Icons.wifi_tethering,
        children: [
            Table(
              border: TableBorder(horizontalInside: BorderSide(color: Colors.white24, width: 0.5)),
              children: [
                  const TableRow(children: [_HeaderCell('Site'), _HeaderCell('Frequency'), _HeaderCell('Uplink')]),
                  ...info.adjacentSites.entries.map((entry) {
                      final freq = (double.tryParse(entry.key) ?? 0.0) / 1000000;
                      final data = entry.value;
                      final uplink = (data['uplink'] ?? 0.0) / 1000000;
                      return TableRow(children: [
                        _DataCell("${data['rfid']}-${data['stid']}"),
                        _DataCell(freq.toStringAsFixed(6), isMono: true),
                        _DataCell(uplink.toStringAsFixed(6), isMono: true),
                      ]);
                  })
              ],
            )
        ],
      );
  }

  // Updated to show more details, similar to JS version
  Widget _buildFrequenciesCard(TrunkUpdate info) {
    return _InfoCard(
      title: "Frequency List",
      icon: Icons.bar_chart,
      children: [
        Table(
          border: TableBorder(horizontalInside: BorderSide(color: Colors.white24, width: 0.5)),
          columnWidths: const {
            0: FlexColumnWidth(2),
            1: FlexColumnWidth(3),
            2: FlexColumnWidth(1.5),
            3: FlexColumnWidth(1.5),
          },
          children: [
            const TableRow(
              children: [
                _HeaderCell('Frequency'),
                _HeaderCell('Active Voice'),
                _HeaderCell('Mode'),
                _HeaderCell('Count'),
              ],
            ),
            ...info.frequencyData.entries.map((entry) {
              final freq = (double.tryParse(entry.key) ?? 0.0) / 1000000;
              final data = entry.value;
              final bool isTdma = data.mode.toLowerCase() == 'tdma' || (data.tags.length > 1 && data.tags[0] != data.tags[1]);

              return TableRow(
                children: [
                  _DataCell(freq.toStringAsFixed(6), isMono: true),
                  _buildVoiceCell(data, isTdma),
                  _DataCell(data.type == 'control' ? 'CC' : data.mode, alignment: TextAlign.center),
                  _DataCell(NumberFormat.compact().format(data.counter), alignment: TextAlign.right),
                ],
              );
            }),
          ],
        )
      ],
    );
  }

  // NEW Card for Band Plan
  Widget _buildBandPlanCard(TrunkUpdate info) {
    return _InfoCard(
      title: "Band Plan",
      icon: Icons.schema,
      children: [
           Table(
            border: TableBorder(horizontalInside: BorderSide(color: Colors.white24, width: 0.5)),
              children: [
                const TableRow(children: [_HeaderCell('ID'), _HeaderCell('Type'), _HeaderCell('Freq'), _HeaderCell('Offset'), _HeaderCell('Spacing')]),
                ...info.bandPlan.map((bp) {
                  return TableRow(children: [
                    _DataCell(bp.id, alignment: TextAlign.center),
                    _DataCell(bp.type, alignment: TextAlign.center),
                    _DataCell(bp.frequency.toStringAsFixed(4), isMono: true),
                    _DataCell(bp.txOffset.toStringAsFixed(3), isMono: true),
                    _DataCell('${bp.spacing.toStringAsFixed(2)}k', isMono: true),
                  ]);
                })
              ],
            )
      ],
    );
  }

  Widget _buildDetailRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 16)),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(color: color ?? Colors.white, fontSize: 16, fontWeight: FontWeight.bold)
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVoiceCell(FrequencyInfo data, bool isTdma) {
    String safeTag(int index) => data.tags.elementAtOrNull(index) ?? 'TG ${data.tgids.elementAtOrNull(index) ?? 0}';
    String safeSrc(int index) => data.srctags.elementAtOrNull(index) ?? 'ID ${data.srcaddrs.elementAtOrNull(index) ?? 0}';

    if (data.tags.isEmpty || data.tags.every((t) => t == null)) {
      return const _DataCell('-');
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Slot 1
            if(data.tags.isNotEmpty && data.tags[0] != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(safeTag(0), style: const TextStyle(color: Colors.white)),
                Text(safeSrc(0), style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          // Slot 2 (if TDMA and different talkgroup)
          if(isTdma && data.tags.length > 1 && data.tags[1] != null)
              Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(safeTag(1), style: const TextStyle(color: Colors.white)),
                    Text(safeSrc(1), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
            ),
              ),
        ],
      ),
    );
  }
}

// Helper widget for the channels list
class _ChannelExpansionTile extends StatelessWidget {
  final ChannelInfo channel;
  final bool isActive;

  const _ChannelExpansionTile({required this.channel, required this.isActive});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: isActive ? Colors.cyan.withOpacity(0.15) : Colors.white.withOpacity(0.05),
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ExpansionTile(
        title: Text(
          channel.name.isNotEmpty ? channel.name : 'Channel ${channel.system}',
          style: TextStyle(
            color: Colors.white,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal
          ),
        ),
        leading: Icon(isActive ? Icons.volume_up : Icons.volume_mute, color: isActive ? Colors.cyanAccent : Colors.white54),
        childrenPadding: const EdgeInsets.all(16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
            _buildExpansionDetailRow("Frequency", "${(channel.freq / 1000000).toStringAsFixed(6)} MHz"),
            _buildExpansionDetailRow("Talkgroup", "${channel.tag} (${channel.tgid})"),
            _buildExpansionDetailRow("Source", "${channel.srctag} (${channel.srcaddr})"),
            _buildExpansionDetailRow("Mode", channel.tdma),
            if (channel.holdTgid != null && channel.holdTgid! > 0)
               _buildExpansionDetailRow("Held TGID", channel.holdTgid.toString(), color: Colors.redAccent),
             _buildExpansionDetailRow(
              "Status",
              channel.emergency == 1
                  ? "EMERGENCY"
                  : (channel.encrypted == 1 ? "Encrypted" : "Clear"),
              color: channel.emergency == 1
                  ? Colors.redAccent
                  : (channel.encrypted == 1 ? Colors.orangeAccent : Colors.greenAccent),
            ),
        ],
      ),
    );
  }
   Widget _buildExpansionDetailRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 14)),
          Text(value, style: TextStyle(color: color ?? Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

// Common helper widgets
class _InfoCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;
  const _InfoCard({required this.title, required this.icon, required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Colors.cyanAccent, size: 20),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ],
            ),
            const Divider(color: Colors.white24, height: 24),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  final String text;
  const _HeaderCell(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Text(text, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
    );
  }
}

class _DataCell extends StatelessWidget {
  final String text;
  final bool isMono;
  final TextAlign alignment;
  const _DataCell(this.text, {this.isMono = false, this.alignment = TextAlign.left});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Text(
        text,
        textAlign: alignment,
        style: TextStyle(
          color: Colors.white,
          fontFamily: isMono ? 'monospace' : null,
        ),
      ),
    );
  }
}