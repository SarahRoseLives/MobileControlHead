import 'package:flutter/material.dart';

class Talkgroup {
  final String name;
  final int id;
  bool enabled;

  Talkgroup({
    required this.name,
    required this.id,
    this.enabled = false,
  });
}

class ScanGridScreen extends StatefulWidget {
  @override
  _ScanGridScreenState createState() => _ScanGridScreenState();
}

class _ScanGridScreenState extends State<ScanGridScreen> {
  final List<String> groupLabels = [
    "1-9", "10-18", "19-27", "28-36", "37-45", "46-54"
  ];
  int selectedGroup = 0;
  bool pendingChanges = false;

  List<List<Talkgroup>> allGroups = List.generate(
    6,
    (g) => List.generate(
      9,
      (i) => Talkgroup(
        name: "TG ${g * 9 + i + 1}",
        id: g * 9 + i + 1,
        enabled: false,
      ),
    ),
  );

  void _restartOp25() {
    setState(() {
      pendingChanges = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Restart OP25 requested! (Implement actual logic)"),
      ),
    );
    // TODO: Add the actual restart OP25 logic here
  }

  @override
  Widget build(BuildContext context) {
    final talkgroups = allGroups[selectedGroup];

    return Scaffold(
      backgroundColor: const Color(0xFF232323),
      body: SafeArea(
        child: Column(
          children: [
            // Group selector bar + restart button
            Container(
              color: const Color(0xFF313131),
              height: 48,
              child: Stack(
                children: [
                  // Tabs
                  ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: groupLabels.length,
                    itemBuilder: (context, i) {
                      return InkWell(
                        onTap: () => setState(() => selectedGroup = i),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: selectedGroup == i
                                    ? Colors.orange
                                    : Colors.transparent,
                                width: 3,
                              ),
                            ),
                            color: selectedGroup == i
                                ? const Color(0xFF444444)
                                : const Color(0xFF313131),
                          ),
                          child: Center(
                            child: Text(
                              groupLabels[i],
                              style: TextStyle(
                                color: selectedGroup == i
                                    ? Colors.orange
                                    : Colors.white70,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  // Pending Changes Button (upper right)
                  if (pendingChanges)
                    Positioned(
                      right: 8,
                      top: 6,
                      bottom: 6,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.black,
                          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                          elevation: 2,
                        ),
                        onPressed: _restartOp25,
                        child: Text(
                          "Pending Changes, Restart OP25",
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // 3x3 grid of talkgroups, always fits!
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  double gridSpacing = 8.0;
                  double totalSpacing = gridSpacing * 2; // 3 rows: 2 spaces
                  double cardHeight = (constraints.maxHeight - totalSpacing) / 3;

                  return GridView.builder(
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: talkgroups.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: gridSpacing,
                      mainAxisSpacing: gridSpacing,
                      childAspectRatio: constraints.maxWidth / (3 * cardHeight),
                    ),
                    itemBuilder: (context, i) {
                      final tg = talkgroups[i];
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            tg.enabled = !tg.enabled;
                            pendingChanges = true;
                          });
                        },
                        child: Card(
                          color: tg.enabled
                              ? Colors.green[600]
                              : const Color(0xFF424242),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                          elevation: tg.enabled ? 3 : 1,
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  tg.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  "ID: ${tg.id}",
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}