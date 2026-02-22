import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p; 
import 'package:path_provider/path_provider.dart'; 
import 'database_service.dart';
import 'security_service.dart';

// --- LIBRARY LIST SCREEN ---
class ToolLibraryScreen extends StatefulWidget {
  const ToolLibraryScreen({super.key});

  @override
  State<ToolLibraryScreen> createState() => _ToolLibraryScreenState();
}

class _ToolLibraryScreenState extends State<ToolLibraryScreen> {
  List<Map<String, dynamic>> _allTools = [];
  List<Map<String, dynamic>> _filteredTools = [];
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadLibrary();
  }

  Future<void> _loadLibrary() async {
    final db = await DatabaseService().database;
    final data = await db.query('go_bag_tools', orderBy: 'name ASC');
    setState(() {
      _allTools = data;
      _filteredTools = data;
    });
  }

  void _filterTools(String query) {
    setState(() {
      _filteredTools = _allTools
          .where((tool) =>
              tool['name'].toLowerCase().contains(query.toLowerCase()) ||
              (tool['category'] ?? "").toLowerCase().contains(query.toLowerCase()))
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text("TOOL SHEETS"),
        actions: [
          IconButton(
            icon: Icon(Icons.add, color: theme.colorScheme.primary),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const ToolEditorScreen()),
            ).then((_) => _loadLibrary()),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              onChanged: _filterTools,
              decoration: InputDecoration(
                hintText: "Search setup guides...",
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              ),
            ),
          ),
          Expanded(
            child: _filteredTools.isEmpty
                ? const Center(child: Text("No documentation found."))
                : ListView.builder(
                    itemCount: _filteredTools.length,
                    itemBuilder: (context, index) {
                      final tool = _filteredTools[index];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: theme.colorScheme.primaryContainer,
                          child: Icon(Icons.auto_stories, color: theme.colorScheme.onPrimaryContainer, size: 20),
                        ),
                        title: Text(tool['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(tool['category'] ?? "General Tool"),
                        trailing: const Icon(Icons.chevron_right, size: 16),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => ToolSheetScreen(tool: tool)),
                        ).then((_) => _loadLibrary()),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// --- VIEWING SCREEN (Detail View) ---
class ToolSheetScreen extends StatefulWidget {
  final Map<String, dynamic> tool;
  const ToolSheetScreen({super.key, required this.tool});

  @override
  State<ToolSheetScreen> createState() => _ToolSheetScreenState();
}

class _ToolSheetScreenState extends State<ToolSheetScreen> {
  late Map<String, dynamic> _currentTool;
  String? _resolvedImagePath;

  @override
  void initState() {
    super.initState();
    _currentTool = widget.tool;
    _resolveImagePath();
  }

  Future<void> _resolveImagePath() async {
    if (_currentTool['photo_path'] == null) return;
    
    final directory = await getApplicationDocumentsDirectory();
    final String fullPath = p.join(directory.path, 'app_assets', _currentTool['photo_path']);
    
    // Check if file physically exists before attempting to display
    if (await File(fullPath).exists()) {
      setState(() => _resolvedImagePath = fullPath);
    } else {
      setState(() => _resolvedImagePath = null);
    }
  }

  Future<void> _refreshToolData() async {
    final db = await DatabaseService().database;
    final results = await db.query('go_bag_tools', where: 'id = ?', whereArgs: [_currentTool['id']]);
    if (results.isNotEmpty) {
      _currentTool = results.first;
      await _resolveImagePath();
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_currentTool['name']),
        actions: [
          IconButton(
            icon: Icon(Icons.edit_note, color: theme.colorScheme.secondary),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => ToolEditorScreen(existingTool: _currentTool)),
              ).then((_) => _refreshToolData());
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            onPressed: () async {
              final navigator = Navigator.of(context);
              bool confirmed = await SecurityService.confirmDeletion(context, _currentTool['name']);

              if (confirmed && mounted) {
                final db = await DatabaseService().database;
                await db.delete('go_bag_tools', where: 'id = ?', whereArgs: [_currentTool['id']]);
                navigator.pop();
              }
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  border: Border(bottom: BorderSide(color: theme.colorScheme.outlineVariant)),
                ),
                child: _resolvedImagePath != null 
                  ? Image.file(File(_resolvedImagePath!), fit: BoxFit.cover)
                  : Icon(Icons.hardware_outlined, size: 64, color: theme.colorScheme.outline),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("CATEGORY: ${_currentTool['category']?.toUpperCase() ?? 'GENERAL'}", 
                    style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.bold, letterSpacing: 1.2, fontSize: 12)),
                  const SizedBox(height: 24),
                  Text("SETUP & OPERATING INSTRUCTIONS", 
                    style: TextStyle(fontSize: 11, letterSpacing: 1.5, color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.bold)),
                  const Divider(height: 24),
                  Text(_currentTool['description'] ?? "No instructions documented.", 
                    style: TextStyle(fontSize: 16, height: 1.6, color: theme.colorScheme.onSurface)),
                  const SizedBox(height: 40),
                  _buildSpecRow(context, "Serial/Version", _currentTool['serial_number'] ?? "N/A"),
                  _buildSpecRow(context, "Warranty/Support", _currentTool['warranty_expiry'] ?? "N/A"),
                  _buildSpecRow(context, "Last Maintained", _currentTool['last_maintained'] ?? "Unknown"),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSpecRow(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
          Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace', color: theme.colorScheme.onSurface)),
        ],
      ),
    );
  }
}

// --- EDITOR SCREEN ---
class ToolEditorScreen extends StatefulWidget {
  final Map<String, dynamic>? existingTool;
  const ToolEditorScreen({super.key, this.existingTool});

  @override
  State<ToolEditorScreen> createState() => _ToolEditorScreenState();
}

class _ToolEditorScreenState extends State<ToolEditorScreen> {
  final _nameController = TextEditingController();
  final _categoryController = TextEditingController();
  final _descController = TextEditingController();
  final _serialController = TextEditingController();
  final _warrantyController = TextEditingController();
  String? _displayImagePath; 
  String? _savedFileName;    

  @override
  void initState() {
    super.initState();
    if (widget.existingTool != null) {
      final t = widget.existingTool!;
      _nameController.text = t['name'] ?? "";
      _categoryController.text = t['category'] ?? "";
      _descController.text = t['description'] ?? "";
      _serialController.text = t['serial_number'] ?? "";
      _warrantyController.text = t['warranty_expiry'] ?? "";
      _savedFileName = t['photo_path'];
      _resolveInitialImage();
    }
  }

  Future<void> _resolveInitialImage() async {
    if (_savedFileName == null) return;
    final directory = await getApplicationDocumentsDirectory();
    final String fullPath = p.join(directory.path, 'app_assets', _savedFileName!);
    if (await File(fullPath).exists()) {
      setState(() => _displayImagePath = fullPath);
    }
  }

  Future<void> _pickImage() async {
    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: Icon(Icons.camera_alt, color: theme.colorScheme.primary),
              title: const Text('Capture with Camera'),
              onTap: () => _handlePicker(ImageSource.camera),
            ),
            ListTile(
              leading: Icon(Icons.photo_library, color: theme.colorScheme.primary),
              title: const Text('Select from Gallery'),
              onTap: () => _handlePicker(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handlePicker(ImageSource source) async {
    Navigator.pop(context);
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: source, imageQuality: 80); 
    if (pickedFile != null) {
      setState(() {
        _displayImagePath = pickedFile.path;
      });
    }
  }

  Future<void> _saveTool() async {
    String? finalFileName = _savedFileName;

    if (_displayImagePath != null && !_displayImagePath!.contains('app_assets')) {
      final directory = await getApplicationDocumentsDirectory();
      final String assetPath = p.join(directory.path, 'app_assets');
      await Directory(assetPath).create(recursive: true);

      final String fileName = "tool_${DateTime.now().millisecondsSinceEpoch}${p.extension(_displayImagePath!)}";
      final File localImage = await File(_displayImagePath!).copy(p.join(assetPath, fileName));
      finalFileName = p.basename(localImage.path);
    }

    final db = await DatabaseService().database;
    final toolData = {
      'name': _nameController.text,
      'category': _categoryController.text,
      'description': _descController.text,
      'serial_number': _serialController.text,
      'warranty_expiry': _warrantyController.text,
      'photo_path': finalFileName, 
      'last_maintained': DateTime.now().toString().split(' ')[0],
    };

    if (widget.existingTool == null) {
      await db.insert('go_bag_tools', toolData);
    } else {
      await db.update('go_bag_tools', toolData, where: 'id = ?', whereArgs: [widget.existingTool!['id']]);
    }

    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(widget.existingTool == null ? "NEW TOOL SHEET" : "EDIT TOOL SHEET")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          GestureDetector(
            onTap: _pickImage,
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5), 
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: theme.colorScheme.outlineVariant)
                ),
                child: _displayImagePath == null 
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center, 
                      children: [
                        Icon(Icons.add_a_photo_outlined, size: 48, color: theme.colorScheme.primary),
                        const SizedBox(height: 12),
                        Text("Add Hardware/UI Photo", style: TextStyle(color: theme.colorScheme.onSurfaceVariant))
                      ],
                    )
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(File(_displayImagePath!), fit: BoxFit.cover)
                    ),
              ),
            ),
          ),
          const SizedBox(height: 25),
          _buildField(context, _nameController, "Tool/Software Name", "e.g. Console Cable"),
          _buildField(context, _categoryController, "Category", "e.g. Connectivity"),
          _buildField(context, _descController, "Instructions", "Configuration steps...", maxLines: 6),
          _buildField(context, _serialController, "Serial/Version", "Hardware SN or Software Ver"),
          _buildField(context, _warrantyController, "Warranty/Support Expiry", "YYYY-MM-DD"),
          const SizedBox(height: 30),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.colorScheme.primary, 
              foregroundColor: theme.colorScheme.onPrimary,
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
            ),
            onPressed: _saveTool, 
            child: const Text("SAVE TO ENCYCLOPEDIA", style: TextStyle(fontWeight: FontWeight.bold))
          ),
        ],
      ),
    );
  }

  Widget _buildField(BuildContext context, TextEditingController controller, String label, String hint, {int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20.0),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
          alignLabelWithHint: true,
        ),
      ),
    );
  }
}