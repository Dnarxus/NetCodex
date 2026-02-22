import 'dart:convert';
import 'package:flutter/material.dart';
import 'database_service.dart';
import 'security_service.dart';
import 'network_utils.dart';

class SiteExplorerScreen extends StatefulWidget {
  final int? initialSiteId;
  const SiteExplorerScreen({super.key, this.initialSiteId});

  @override
  State<SiteExplorerScreen> createState() => _SiteExplorerScreenState();
}

class _SiteExplorerScreenState extends State<SiteExplorerScreen> {
  int? _selectedSiteId;
  String? _selectedSiteName;

  List<Map<String, dynamic>> _sites = [];
  List<Map<String, dynamic>> _vlanRecords = [];
  
  final TextEditingController _localSearchController = TextEditingController();
  String _localQuery = "";

  @override
  void initState() {
    super.initState();
    if (widget.initialSiteId != null) {
      _loadInitialSite(widget.initialSiteId!);
    } else {
      _refreshSites();
    }
  }

  Future<void> _loadInitialSite(int id) async {
    final db = await DatabaseService().database;
    final site = await db.query('site_folders', where: 'id = ?', whereArgs: [id]);
    final allSites = await db.query('site_folders');
    setState(() => _sites = allSites); 
    
    if (site.isNotEmpty) {
      _loadVlans(id, site.first['name'] as String);
    }
  }

  // --- VALIDATION & INTELLIGENCE ---

  bool _isValidSubnet(String subnet) {
    final regex = RegExp(
        r'^([0-9]{1,3}\.){3}[0-9]{1,3}(\/([0-9]|[1-2][0-9]|3[0-2]))$');
    return regex.hasMatch(subnet);
  }

  void _showSubnetDetails(String cidr) {
    final results = NetworkUtils.calculateSubnet(cidr);
    final theme = Theme.of(context);

    showModalBottomSheet(
      context: context,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        if (results.containsKey('error')) {
          return Padding(
            padding: const EdgeInsets.all(24.0),
            child: Text(results['error']!, style: const TextStyle(color: Colors.redAccent)),
          );
        }

        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Subnet Intel: $cidr", 
                style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 20),
              _buildIntelRow("Network ID", results['network_id']!),
              _buildIntelRow("Subnet Mask", results['netmask']!),
              _buildIntelRow("Broadcast", results['broadcast']!),
              Divider(color: theme.colorScheme.outlineVariant, height: 30),
              _buildIntelRow("First IP", results['first_ip']!),
              _buildIntelRow("Last IP", results['last_ip']!),
              _buildIntelRow("Hosts", "${results['total_hosts']} available"),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  Widget _buildIntelRow(String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
          Text(value, style: TextStyle(fontFamily: 'monospace', color: theme.colorScheme.onSurface, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  // --- DATABASE OPERATIONS ---

  Future<void> _refreshSites() async {
    final db = await DatabaseService().database;
    final data = await db.query('site_folders');
    setState(() {
      _sites = data;
      _selectedSiteId = null;
      _selectedSiteName = null;
      _localSearchController.clear();
      _localQuery = "";
    });
  }

  Future<void> _loadVlans(int siteId, String siteName) async {
    final db = await DatabaseService().database;
    final masterKey = SecurityService.activeKey;

    final data = await db.query(
      'network_ledger',
      where: 'site_id = ?',
      whereArgs: [siteId],
    );

    List<Map<String, dynamic>> decryptedList = [];
    for (var row in data) {
      try {
        String decryptedJson = await SecurityService.decryptData(
            row['data_json'] as String, masterKey);
        Map<String, dynamic> vlanData = jsonDecode(decryptedJson);
        decryptedList.add({
          'id': row['id'],
          'label': row['label'],
          ...vlanData,
        });
      } catch (e) {
        debugPrint("Decryption error: $e");
      }
    }

    setState(() {
      _selectedSiteId = siteId;
      _selectedSiteName = siteName;
      _vlanRecords = decryptedList;
    });
  }

  Future<void> _handleDeleteVlan(int id, String label) async {
    bool confirmed = await SecurityService.confirmDeletion(context, label);
    if (confirmed) {
      final db = await DatabaseService().database;
      await db.delete('network_ledger', where: 'id = ?', whereArgs: [id]);
      _showStatus("$label purged from vault.");
      _loadVlans(_selectedSiteId!, _selectedSiteName!);
    }
  }

  // --- DIALOGS ---

  void _showSiteDialog({Map<String, dynamic>? existingSite}) {
    final nameController = TextEditingController(text: existingSite?['name']);
    final descController = TextEditingController(text: existingSite?['description']);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(existingSite == null ? "Create New Site" : "Update Site Details"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameController, decoration: const InputDecoration(labelText: "Site Name")),
            TextField(controller: descController, decoration: const InputDecoration(labelText: "Description")),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCEL")),
          ElevatedButton(
            onPressed: () async {
              final navigator = Navigator.of(context);
              if (nameController.text.isEmpty) return;
              final db = await DatabaseService().database;
              
              if (existingSite == null) {
                await db.insert('site_folders', {'name': nameController.text, 'description': descController.text});
              } else {
                await db.update('site_folders', 
                  {'name': nameController.text, 'description': descController.text},
                  where: 'id = ?', whereArgs: [existingSite['id']]);
              }
              
              navigator.pop();
              if (mounted) _refreshSites();
            },
            child: Text(existingSite == null ? "SAVE" : "UPDATE"),
          ),
        ],
      ),
    );
  }

  // UPDATED: Strict CIDR validation logic
  void _showVlanDialog({Map<String, dynamic>? existingVlan}) {
    final formKey = GlobalKey<FormState>();
    final vlanIdController = TextEditingController(text: existingVlan?['vlan_id']?.toString());
    final nameController = TextEditingController(text: existingVlan?['label']);
    final subnetController = TextEditingController(text: existingVlan?['subnet']);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(existingVlan == null ? "New VLAN: $_selectedSiteName" : "Edit ${existingVlan['label']}"),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: vlanIdController, 
                decoration: const InputDecoration(labelText: "VLAN ID"), 
                keyboardType: TextInputType.number
              ),
              TextFormField(
                controller: nameController, 
                decoration: const InputDecoration(labelText: "VLAN Name"),
                validator: (val) => (val == null || val.isEmpty) ? "Name required" : null,
              ),
              TextFormField(
                controller: subnetController, 
                decoration: const InputDecoration(
                  labelText: "Subnet CIDR", 
                  hintText: "192.168.1.0/24",
                  helperText: "Format: x.x.x.x/prefix",
                ),
                validator: (val) {
                  if (val == null || val.isEmpty) return "Subnet required";
                  if (!_isValidSubnet(val)) return "Invalid CIDR (Missing /mask)";
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCEL")),
          ElevatedButton(
            onPressed: () async {
              if (formKey.currentState!.validate()) {
                final navigator = Navigator.of(context);
                final masterKey = SecurityService.activeKey;
                Map<String, dynamic> vlanInfo = {
                  'vlan_id': vlanIdController.text, 
                  'subnet': subnetController.text
                };
                
                String encryptedData = await SecurityService.encryptData(jsonEncode(vlanInfo), masterKey);
                final db = await DatabaseService().database;
                
                if (existingVlan == null) {
                  await db.insert('network_ledger', {
                    'site_id': _selectedSiteId,
                    'label': nameController.text,
                    'data_json': encryptedData,
                  });
                } else {
                  await db.update('network_ledger', 
                    {'label': nameController.text, 'data_json': encryptedData},
                    where: 'id = ?', whereArgs: [existingVlan['id']]);
                }

                navigator.pop();
                if (mounted) _loadVlans(_selectedSiteId!, _selectedSiteName!);
              }
            },
            child: Text(existingVlan == null ? "SAVE RECORD" : "UPDATE RECORD"),
          ),
        ],
      ),
    );
  }

  void _showStatus(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.redAccent : Colors.greenAccent,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    bool isViewingVlans = _selectedSiteId != null;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: isViewingVlans 
            ? TextField(
                controller: _localSearchController,
                onChanged: (val) => setState(() => _localQuery = val),
                style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 16),
                decoration: InputDecoration(
                  hintText: "Search in $_selectedSiteName...",
                  hintStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  border: InputBorder.none,
                ),
              )
            : const Text("Infrastructure Ledger"),
        leading: isViewingVlans 
          ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: _refreshSites) 
          : null,
        actions: [
          if (isViewingVlans && _localQuery.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => setState(() {
                _localSearchController.clear();
                _localQuery = "";
              }),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: isViewingVlans ? theme.colorScheme.tertiary : theme.colorScheme.primary,
        onPressed: isViewingVlans ? () => _showVlanDialog() : () => _showSiteDialog(),
        child: Icon(isViewingVlans ? Icons.add_road : Icons.create_new_folder, 
                    color: isViewingVlans ? theme.colorScheme.onTertiary : theme.colorScheme.onPrimary),
      ),
      body: isViewingVlans ? _buildVlanList() : _buildSiteList(),
    );
  }

  Widget _buildSiteList() {
    return _sites.isEmpty
        ? const Center(child: Text("No sites documented yet."))
        : ListView.builder(
            itemCount: _sites.length,
            itemBuilder: (context, index) {
              final site = _sites[index];
              return ListTile(
                leading: Icon(Icons.folder, color: Colors.amber[700]),
                title: Text(site['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(site['description'] ?? "No site description"),
                trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                onTap: () => _loadVlans(site['id'], site['name']),
                onLongPress: () => _showSiteDialog(existingSite: site),
              );
            },
          );
  }

  Widget _buildVlanList() {
    final theme = Theme.of(context);
    
    final filteredVlans = _vlanRecords.where((vlan) {
      final query = _localQuery.toLowerCase();
      return vlan['label'].toString().toLowerCase().contains(query) ||
             vlan['subnet'].toString().contains(query) ||
             vlan['vlan_id'].toString().contains(query);
    }).toList();

    return filteredVlans.isEmpty
        ? Center(child: Text(_localQuery.isEmpty ? "No VLANs recorded." : "No results for '$_localQuery'"))
        : ListView.builder(
            itemCount: filteredVlans.length,
            itemBuilder: (context, index) {
              final vlan = filteredVlans[index];
              final String currentSubnet = vlan['subnet'] ?? "N/A";

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: theme.colorScheme.primary,
                    child: Text(vlan['vlan_id'] ?? "?", 
                      style: TextStyle(color: theme.colorScheme.onPrimary, fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                  title: Text(vlan['label'], style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text("Subnet: $currentSubnet"),
                  trailing: Wrap(
                    children: [
                      IconButton(
                        icon: Icon(Icons.analytics_outlined, color: theme.colorScheme.tertiary, size: 20),
                        onPressed: () => _showSubnetDetails(currentSubnet),
                      ),
                      IconButton(
                        icon: Icon(Icons.edit_outlined, color: theme.colorScheme.secondary, size: 20),
                        onPressed: () => _showVlanDialog(existingVlan: vlan),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_sweep_outlined, color: Colors.redAccent, size: 20),
                        onPressed: () => _handleDeleteVlan(vlan['id'], vlan['label']),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
  }
}