import 'package:flutter/material.dart';
import 'database_service.dart';
import 'tool_sheets.dart';

class GoBagScreen extends StatefulWidget {
  const GoBagScreen({super.key});

  @override
  State<GoBagScreen> createState() => _GoBagScreenState();
}

class _GoBagScreenState extends State<GoBagScreen> {
  List<Map<String, dynamic>> _inventory = [];

  @override
  void initState() {
    super.initState();
    _loadInventory();
  }

  Future<void> _loadInventory() async {
    final db = await DatabaseService().database;
    final data = await db.query('go_bag_tools', orderBy: 'category ASC');
    setState(() => _inventory = data);
  }

  // MISSION RESET: Sets all items to 'unpacked' for a new deployment
  Future<void> _resetDeployment() async {
    bool? confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Reset Deployment?"),
        content: const Text("This will mark all items as 'Not Packed'. Ready for a new mission?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("CANCEL")),
          TextButton(
            onPressed: () => Navigator.pop(context, true), 
            child: const Text("RESET", style: TextStyle(color: Colors.redAccent))
          ),
        ],
      ),
    );

    if (confirm == true) {
      final db = await DatabaseService().database;
      await db.update('go_bag_tools', {'is_ready': 0});
      _loadInventory();
    }
  }

  // PROACTIVE MAINTENANCE LOGIC
  Color _getMaintenanceStatus(String? expiryDate) {
    if (expiryDate == null || expiryDate.isEmpty) return Colors.grey;
    try {
      final expiry = DateTime.parse(expiryDate);
      final now = DateTime.now();
      final difference = expiry.difference(now).inDays;

      if (difference < 0) return Colors.redAccent; // EXPIRED
      if (difference < 30) return Colors.orangeAccent; // WARNING (30 Days)
      return Colors.greenAccent; // SERVICEABLE
    } catch (e) {
      return Colors.grey;
    }
  }

  Future<void> _toggleReadiness(int id, bool isReady) async {
    final db = await DatabaseService().database;
    await db.update(
      'go_bag_tools',
      {'is_ready': isReady ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
    _loadInventory();
  }

  @override
  Widget build(BuildContext context) {
    int readyCount = _inventory.where((item) => item['is_ready'] == 1).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text("GO-BAG CHECKLIST"),
        actions: [
          IconButton(
            icon: const Icon(Icons.restart_alt, color: Colors.orangeAccent),
            tooltip: "Reset for new mission",
            onPressed: _resetDeployment,
          )
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(40),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              "READINESS: $readyCount / ${_inventory.length} ITEMS PACKED",
              style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
        ),
      ),
      body: _inventory.isEmpty
          ? const Center(child: Text("Inventory Empty. Add tools via Tool Sheets."))
          : ListView.builder(
              itemCount: _inventory.length,
              itemBuilder: (context, index) {
                final item = _inventory[index];
                final healthColor = _getMaintenanceStatus(item['warranty_expiry']);

                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  color: Colors.white.withValues(alpha: 0.05),
                  child: ListTile(
                    leading: Container(
                      width: 4,
                      height: 30,
                      decoration: BoxDecoration(
                        color: healthColor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    title: Text(item['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(
                      item['category'] ?? "Field Gear",
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    trailing: Switch(
                      activeTrackColor: Colors.greenAccent.withValues(alpha: 0.3),
                      activeThumbColor: Colors.greenAccent,
                      value: item['is_ready'] == 1,
                      onChanged: (val) => _toggleReadiness(item['id'], val),
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => ToolSheetScreen(tool: item)),
                      ).then((_) => _loadInventory());
                    },
                  ),
                );
              },
            ),
    );
  }
}