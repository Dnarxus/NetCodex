import 'package:flutter/material.dart';
import 'security_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import 'database_service.dart';
import 'dart:async';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'site_explorer.dart';
import 'password_editor.dart';
import 'ip_intel_screen.dart';
import 'go_bag_checklist.dart';
import 'tool_sheets.dart';
import 'migration_service.dart';
import 'notes_screen.dart';
import 'practice_screen.dart';
import 'notes_vault.dart';

final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.dark);

void main() {
  runApp(const NetCodexApp());
}

class NetCodexApp extends StatelessWidget {
  const NetCodexApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (_, mode, __) {
        return MaterialApp(
          themeMode: mode,
          // LIGHT THEME CONFIG
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,
            colorSchemeSeed: Colors.blueAccent,
          ),
          // DARK THEME CONFIG
          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            colorSchemeSeed: Colors.greenAccent,
          ),
          home: const PinGateScreen(),
        );
      },
    );
  }
}

// --- INITIAL PIN GATE ---
class PinGateScreen extends StatefulWidget {
  const PinGateScreen({super.key});

  @override
  State<PinGateScreen> createState() => _PinGateScreenState();
}

class _PinGateScreenState extends State<PinGateScreen> with WidgetsBindingObserver {
  final TextEditingController _pinController = TextEditingController();
  final TextEditingController _confirmPinController = TextEditingController();
  
  bool _isInitialized = false;
  int _failedAttempts = 0;
  bool _isLockedOut = false;
  Timer? _lockoutTimer;
  int _secondsRemaining = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); 
    _checkSystemStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this); 
    _lockoutTimer?.cancel();
    _pinController.dispose();
    _confirmPinController.dispose();
    super.dispose();
  }

  void _startLockoutTimer(int seconds) {
    setState(() {
      _secondsRemaining = seconds;
      _isLockedOut = true;
    });

    _lockoutTimer?.cancel();
    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining > 0) {
        setState(() => _secondsRemaining--);
      } else {
        setState(() {
          _isLockedOut = false;
          _failedAttempts = 0;
        });
        timer.cancel();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      SecurityService.endSession();
    }
  }

  Future<void> _checkSystemStatus() async {
    final salt = await const FlutterSecureStorage().read(key: 'netcodex_crypt_salt');
    
    bool dbInitialized = false;
    try {
      final db = await DatabaseService().database;
      final List<Map<String, dynamic>> maps = await db.query(
        'vault_metadata',
        where: 'config_key = ?',
        whereArgs: ['vault_salt'],
      );
      dbInitialized = maps.isNotEmpty;
    } catch (e) {
      dbInitialized = false;
    }

    if (mounted) {
      setState(() => _isInitialized = (salt != null || dbInitialized));
    }
  }

  Future<void> _processSecurityAction() async {
    if (_isLockedOut) return;

    final pin = _pinController.text;
    if (pin.length < 6) {
      _showError("Security Policy: 6-digit minimum required.");
      return;
    }

    try {
      if (!_isInitialized) {
        if (pin != _confirmPinController.text) {
          _showError("PINs do not match.");
          return;
        }
        await SecurityService.initOnboarding(pin);
        await _checkSystemStatus();
      }

      bool isValid = await SecurityService.verifyPin(pin);

      if (isValid) {
        _failedAttempts = 0;
        if (!mounted) return;
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const Dashboard()));
      } else {
        setState(() {
          _failedAttempts++;
          if (_failedAttempts >= 3) {
            _startLockoutTimer(60);
            _showError("Critical: 3 failed attempts. Locked for 1 min.");
          } else {
            _showError("Denied: ${3 - _failedAttempts} attempts left.");
          }
        });
        _pinController.clear();
      }
    } catch (e) {
      _showError("Security Engine Failure: $e");
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: Colors.redAccent,
      duration: const Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.security, size: 80, color: Colors.greenAccent),
                const SizedBox(height: 20),
                Text(
                  _isInitialized ? "UNLOCK VAULT" : "CREATE MASTER PIN", 
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 2)
                ),
                const Text("Zero-Trust Offline Documentation", style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 40),

                if (_isLockedOut) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.lock_clock, color: Colors.redAccent, size: 20),
                        const SizedBox(width: 10),
                        Text("LOCKED: ${_secondsRemaining}s",
                          style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 16)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                TextField(
                  controller: _pinController,
                  obscureText: true,
                  enabled: !_isLockedOut,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                    hintText: _isLockedOut ? "WAITING..." : "ENTER 6-DIGIT MASTER PIN",
                    border: const OutlineInputBorder(),
                    fillColor: _isLockedOut ? Colors.white10 : Colors.transparent,
                    filled: true,
                  ),
                ),
                if (!_isInitialized) ...[
                  const SizedBox(height: 15),
                  TextField(
                    controller: _confirmPinController,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(hintText: "CONFIRM MASTER PIN", border: OutlineInputBorder()),
                  ),
                ],
                const SizedBox(height: 30),
                
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isLockedOut ? null : _processSecurityAction, 
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.greenAccent,
                      disabledBackgroundColor: Colors.grey.shade800,
                      foregroundColor: Colors.black,
                      disabledForegroundColor: Colors.white38,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: Text(
                      _isLockedOut ? "VAULT SEALED" : (_isInitialized ? "VERIFY & OPEN" : "INITIALIZE VAULT"),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                ),

                if (!_isInitialized) ...[
                  const SizedBox(height: 20),
                  TextButton.icon(
                    onPressed: () {
                      MigrationService.importDatabase(context, () {
                        _checkSystemStatus(); // Refresh screen state after import
                      });
                    },
                    icon: const Icon(Icons.file_download, color: Colors.blueAccent),
                    label: const Text("RESTORE EXISTING VAULT (.CODEX)", 
                      style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// --- DASHBOARD ---
class Dashboard extends StatelessWidget {
  const Dashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("NetCodex"),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: "Search Vaults",
            onPressed: () {
              showSearch(
                context: context,
                delegate: GlobalSearchDelegate(),
              );
            },
          ),
          ValueListenableBuilder<ThemeMode>(
            valueListenable: themeNotifier,
            builder: (context, mode, _) {
              return IconButton(
                icon: Icon(mode == ThemeMode.dark ? Icons.light_mode : Icons.dark_mode),
                tooltip: "Toggle Theme",
                onPressed: () {
                  themeNotifier.value =
                      mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
                },
              );
            },
          ),
        ],
      ),
      drawer: Drawer(
        child: Column(
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(color: Colors.greenAccent),
              child: SizedBox(
                width: double.infinity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("NetCodex v1.0",
                        style: TextStyle(
                            color: Colors.black, fontWeight: FontWeight.bold)),
                    Spacer(),
                    Text("Dionivel A. Alegado",
                        style: TextStyle(
                            color: Colors.black,
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                    Text("BS Computer Engineering 2026",
                        style: TextStyle(color: Colors.black, fontSize: 10)),
                  ],
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.lan),
              title: const Text("Infrastructure Ledger"),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context,
                    MaterialPageRoute(builder: (context) => const SiteExplorerScreen()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.calculate),
              title: const Text("IP Intel"),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context,
                    MaterialPageRoute(builder: (context) => const IpIntelScreen()));
              },
            ),
            const Divider(),
            
            // --- MIGRATION STRATEGY: .CODEX TOOLS ---
            ListTile(
              leading: const Icon(Icons.upload_file, color: Colors.blueAccent),
              title: const Text("Export Vault (.codex)"),
              subtitle: const Text("Backup encrypted field data"),
              onTap: () {
                Navigator.pop(context);
                MigrationService.exportDatabase(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.download_for_offline, color: Colors.orangeAccent),
              title: const Text("Import Vault (.codex)"),
              subtitle: const Text("Restore existing vault file"),
              onTap: () {
                Navigator.pop(context);
                MigrationService.importDatabase(context, () {
                  SecurityService.endSession();
                  Navigator.pushReplacement(context,
                      MaterialPageRoute(builder: (context) => const PinGateScreen()));
                });
              },
            ),
            
            const Divider(),

            ValueListenableBuilder<ThemeMode>(
              valueListenable: themeNotifier,
              builder: (context, mode, _) {
                final isDark = mode == ThemeMode.dark;
                return ListTile(
                  leading: Icon(isDark ? Icons.light_mode : Icons.dark_mode),
                  title: Text(isDark ? "Switch to Light Mode" : "Switch to Dark Mode"),
                  onTap: () {
                    themeNotifier.value = isDark ? ThemeMode.light : ThemeMode.dark;
                  },
                );
              },
            ),

            ListTile(
              leading: const Icon(Icons.lock_open, color: Colors.redAccent),
              title: const Text("Lock Vault"),
              onTap: () {
                SecurityService.endSession();
                Navigator.pushReplacement(context,
                    MaterialPageRoute(builder: (context) => const PinGateScreen()));
              },
            ),
          ],
        ),
      ),
      body: GridView.count(
        padding: const EdgeInsets.all(16),
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        children: [
          _buildMenuCard(context, Icons.edit_note, "Notes", "Lectures & Concepts"),
          _buildMenuCard(context, Icons.quiz, "Practice", "Exams & Flashcards"),
          _buildMenuCard(context, Icons.terminal, "Scripts", "Verified sequences"),
          _buildMenuCard(context, Icons.bug_report, "Issues", "Troubleshooting fixes"),
          _buildMenuCard(context, Icons.assignment, "Processes", "Deployment guidelines"),
          _buildMenuCard(context, Icons.shopping_bag, "Go-Bag", "Inventory & Maintenance"),
          _buildMenuCard(context, Icons.handyman, "Tool Sheets", "Software and Hardware instructions"),
          _buildMenuCard(context, Icons.lan, "Infrastructure", "Site & VLAN Ledger"),
          _buildMenuCard(context, Icons.router, "IP Intel", "CIDR Calculator"),
          _buildMenuCard(context, Icons.lock, "Password Vault", "Credentials"),
        ],
      ),
    );
  }

  Widget _buildMenuCard(BuildContext context, IconData icon, String title, String subtitle) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: isDark ? 0.3 : 0.7),
      elevation: isDark ? 2 : 1,
      child: InkWell(
        onTap: () {
          switch (title) {
            case "Notes":
              Navigator.push(context, MaterialPageRoute(builder: (context) => const NotesVaultScreen()));
              break;
            case "Practice":
              Navigator.push(context, MaterialPageRoute(builder: (context) => const PracticeScreen()));
              break;
            case "IP Intel":
              Navigator.push(context, MaterialPageRoute(builder: (context) => const IpIntelScreen()));
              break;
            case "Infrastructure":
              Navigator.push(context, MaterialPageRoute(builder: (context) => const SiteExplorerScreen()));
              break;
            case "Password Vault":
              _promptVaultPin(context);
              break;
            case "Scripts":
              Navigator.push(context, MaterialPageRoute(builder: (context) => const VaultListScreen(category: "Script")));
              break;
            case "Issues":
              Navigator.push(context, MaterialPageRoute(builder: (context) => const VaultListScreen(category: "Issue")));
              break;
            case "Processes":
              Navigator.push(context, MaterialPageRoute(builder: (context) => const VaultListScreen(category: "Process")));
              break;
            case "Go-Bag":
              Navigator.push(context, MaterialPageRoute(builder: (context) => const GoBagScreen()));
              break;
            case "Tool Sheets":
              Navigator.push(context, MaterialPageRoute(builder: (context) => const ToolLibraryScreen()));
              break;
          }
        },
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 40, color: theme.colorScheme.primary),
            const SizedBox(height: 10),
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _promptVaultPin(BuildContext context) {
    final TextEditingController vaultPinController = TextEditingController();
    final mainNavigator = Navigator.of(context);
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    
    final theme = Theme.of(context);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        final dialogNavigator = Navigator.of(dialogContext);

        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.lock_outline, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              const Text("Vault Access"),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "Identity re-verification required.",
                style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: vaultPinController,
                obscureText: true,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                autofocus: true,
                style: TextStyle(color: theme.colorScheme.onSurface),
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  hintText: "6-DIGIT PIN",
                  hintStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => dialogNavigator.pop(),
              child: Text(
                "CANCEL",
                style: TextStyle(color: theme.colorScheme.secondary),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.primaryContainer,
                foregroundColor: theme.colorScheme.onPrimaryContainer,
              ),
              onPressed: () async {
                bool isValid = await SecurityService.verifyPin(vaultPinController.text);
                
                if (isValid) {
                  dialogNavigator.pop(); 
                  mainNavigator.push(
                    MaterialPageRoute(builder: (context) => const PasswordVaultScreen())
                  );
                } else {
                  vaultPinController.clear();
                  scaffoldMessenger.showSnackBar(
                    const SnackBar(
                      content: Text("Invalid Master PIN"),
                      backgroundColor: Colors.redAccent,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              },
              child: const Text("UNLOCK"),
            ),
          ],
        );
      },
    );
  }
}

class EntryEditor extends StatefulWidget {
  final String category;
  final Map<String, dynamic>? existingEntry;

  const EntryEditor({super.key, required this.category, this.existingEntry});

  @override
  State<EntryEditor> createState() => _EntryEditorState();
}

class _EntryEditorState extends State<EntryEditor> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _contentController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _issueDescriptionController = TextEditingController();
  final List<TextEditingController> _stepControllers = [];
  final TextEditingController _remindersController = TextEditingController();

  String _rarity = 'Common';
  String _issueCategory = 'Network';
  bool _isDecrypting = false;

  @override
  void initState() {
    super.initState();
    if (widget.existingEntry != null) {
      _titleController.text = widget.category == "Issue"
          ? (widget.existingEntry!['problem_summary'] ?? "")
          : (widget.existingEntry!['title'] ?? "");
      
      if (widget.category == "Issue") {
        _rarity = widget.existingEntry!['complexity_rank'] == 3 
            ? 'Critical' : (widget.existingEntry!['complexity_rank'] == 2 ? 'Rare' : 'Common');
      }

      _preLoadEncryptedData();
    } else {
      _stepControllers.add(TextEditingController());
    }
  }

  Future<void> _preLoadEncryptedData() async {
    setState(() => _isDecrypting = true);
    try {
      final masterKey = SecurityService.activeKey;

      if (widget.category == "Issue") {
        final desc = await SecurityService.decryptData(widget.existingEntry!['issue_description'], masterKey);
        final fix = await SecurityService.decryptData(widget.existingEntry!['solution_fix'], masterKey);
        setState(() {
          _issueDescriptionController.text = desc;
          _contentController.text = fix;
        });
      } else if (widget.category == "Process") {
        final rawJson = await SecurityService.decryptData(widget.existingEntry!['content'], masterKey);
        final data = jsonDecode(rawJson);
        setState(() {
          _descriptionController.text = data['description'] ?? "";
          _remindersController.text = data['notes'] ?? "";
          _stepControllers.clear();
          for (var step in (data['steps'] as List)) {
            _stepControllers.add(TextEditingController(text: step.toString()));
          }
        });
      } else {
        final content = await SecurityService.decryptData(widget.existingEntry!['content'], masterKey);
        setState(() => _contentController.text = content);
      }
    } catch (e) {
      debugPrint("Decryption error during pre-load: $e");
    } finally {
      if (mounted) setState(() => _isDecrypting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existingEntry == null ? "New ${widget.category}" : "Edit ${widget.category}"),
      ),
      body: _isDecrypting 
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: "Entry Title", border: OutlineInputBorder()),
              ),
              const SizedBox(height: 20),
              if (widget.category == "Cheat Sheet") _buildShortForm(),
              if (widget.category == "Script") _buildLongForm(),
              if (widget.category == "Process") _buildProcessForm(),
              if (widget.category == "Issue") _buildIssueForm(),
              const SizedBox(height: 30),
              ElevatedButton(
                onPressed: _saveToVault,
                child: Text(widget.existingEntry == null ? "ENCRYPT & SAVE" : "UPDATE ENTRY"),
              ),
            ],
          ),
    );
  }

  Widget _buildShortForm() => TextField(
    controller: _contentController,
    maxLines: 3,
    decoration: const InputDecoration(labelText: "Quick Reference Info", hintText: "e.g. Pinout standards"),
  );

  Widget _buildLongForm() => TextField(
    controller: _contentController,
    maxLines: 10,
    decoration: const InputDecoration(labelText: "Script / CLI Syntax", hintText: "```cisco\nconf t\n...```"),
  );

  Widget _buildProcessForm() => Column(
    children: [
      TextField(controller: _descriptionController, decoration: const InputDecoration(labelText: "Brief Description")),
      const Divider(),
      const Text("Steps:"),
      ..._stepControllers.map((c) => TextField(controller: c, decoration: const InputDecoration(hintText: "Enter step..."))),
      TextButton(onPressed: () => setState(() => _stepControllers.add(TextEditingController())), child: const Text("+ Add Step")),
      TextField(controller: _remindersController, decoration: const InputDecoration(labelText: "Notes & Reminders")),
    ],
  );

  Widget _buildIssueForm() => Column(
    children: [
      DropdownButtonFormField<String>(
        initialValue: _issueCategory,
        items: ['Network', 'Hardware', 'Software', 'Server']
            .map((c) => DropdownMenuItem(value: c, child: Text(c)))
            .toList(),
        onChanged: (val) => setState(() => _issueCategory = val!),
        decoration: const InputDecoration(labelText: "Issue Category"),
      ),
      const SizedBox(height: 15),
      DropdownButtonFormField<String>(
        initialValue: _rarity,
        items: ['Common', 'Rare', 'Critical']
            .map((r) => DropdownMenuItem(value: r, child: Text(r)))
            .toList(),
        onChanged: (val) => setState(() => _rarity = val!),
        decoration: const InputDecoration(labelText: "Rarity"),
      ),
      const SizedBox(height: 15),
      TextField(
        controller: _issueDescriptionController,
        maxLines: 3,
        decoration: const InputDecoration(
          labelText: "Issue Description (Symptoms)",
          hintText: "What are the specific errors or symptoms?",
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 15),
      TextField(
        controller: _contentController, 
        maxLines: 5, 
        decoration: const InputDecoration(
          labelText: "Solution/Fix",
          border: OutlineInputBorder(),
        ),
      ),
    ],
  );

  Future<void> _saveToVault() async {
    try {
      final navigator = Navigator.of(context);
      final messenger = ScaffoldMessenger.of(context);
      final masterKey = SecurityService.activeKey;
      final db = await DatabaseService().database;

      bool isUpdate = widget.existingEntry != null;

      if (widget.category == "Issue") {
        String encryptedDescription = await SecurityService.encryptData(_issueDescriptionController.text, masterKey);
        String encryptedFix = await SecurityService.encryptData(_contentController.text, masterKey);

        final data = {
          'problem_summary': _titleController.text,
          'issue_description': encryptedDescription,
          'solution_fix': encryptedFix,
          'complexity_rank': _rarity == 'Critical' ? 3 : (_rarity == 'Rare' ? 2 : 1),
        };

        if (isUpdate) {
          await db.update('issues', data, where: 'id = ?', whereArgs: [widget.existingEntry!['id']]);
        } else {
          await db.insert('issues', data);
        }

      } else if (widget.category == "Process") {
        String processPayload = jsonEncode({
          'description': _descriptionController.text,
          'steps': _stepControllers.map((c) => c.text).toList(),
          'notes': _remindersController.text,
        });

        String encryptedProcess = await SecurityService.encryptData(processPayload, masterKey);
        final data = {'title': _titleController.text, 'content': encryptedProcess, 'type': 'process'};

        if (isUpdate) {
          await db.update('knowledge_base', data, where: 'id = ?', whereArgs: [widget.existingEntry!['id']]);
        } else {
          await db.insert('knowledge_base', data);
        }

      } else {
        String encryptedContent = await SecurityService.encryptData(_contentController.text, masterKey);
        final data = {'title': _titleController.text, 'content': encryptedContent, 'type': widget.category.toLowerCase()};

        if (isUpdate) {
          await db.update('knowledge_base', data, where: 'id = ?', whereArgs: [widget.existingEntry!['id']]);
        } else {
          await db.insert('knowledge_base', data);
        }
      }

      navigator.pop();
      messenger.showSnackBar(const SnackBar(content: Text("Vault Updated Successfully")));
      
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.redAccent));
    }
  }
}

class VaultListScreen extends StatefulWidget {
  final String category; 

  const VaultListScreen({super.key, required this.category});

  @override
  State<VaultListScreen> createState() => _VaultListScreenState();
}

class _VaultListScreenState extends State<VaultListScreen> {
  List<Map<String, dynamic>> _entries = [];

  @override
  void initState() {
    super.initState();
    _loadEntries();
  }

  Future<void> _loadEntries() async {
    final db = await DatabaseService().database;
    List<Map<String, dynamic>> data;

    if (widget.category == "Issue") {
      data = await db.query('issues', orderBy: 'complexity_rank DESC'); 
    } else {
      data = await db.query(
        'knowledge_base', 
        where: 'type = ?', 
        whereArgs: [widget.category.toLowerCase()]
      );
    }

    if (mounted) {
      setState(() {
        _entries = data;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("${widget.category} Vault"),
        actions: [
          IconButton(onPressed: _loadEntries, icon: const Icon(Icons.refresh))
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.greenAccent,
        onPressed: () => Navigator.push(
          context, 
          MaterialPageRoute(builder: (context) => EntryEditor(category: widget.category))
        ).then((_) => _loadEntries()), 
        child: const Icon(Icons.add, color: Colors.black),
      ),
      body: _entries.isEmpty 
        ? const Center(child: Text("Vault Empty. Access 'Entry Engine' to add data."))
        : ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: _entries.length,
            itemBuilder: (context, index) {
              final item = _entries[index];
              final String title = widget.category == "Issue" 
                  ? item['problem_summary'] 
                  : item['title'];

              return Dismissible(
                key: Key("${widget.category}_${item['id']}"),
                direction: DismissDirection.endToStart,
                confirmDismiss: (direction) async {
                  return await SecurityService.confirmDeletion(context, title);
                },
                onDismissed: (direction) async {
                  final messenger = ScaffoldMessenger.of(context);
                  final db = await DatabaseService().database;
                  
                  final tableName = widget.category == "Issue" ? 'issues' : 'knowledge_base';

                  await db.delete(tableName, where: 'id = ?', whereArgs: [item['id']]);
                  
                  _loadEntries();
                  messenger.showSnackBar(SnackBar(
                    content: Text("$title purged from vault."),
                    backgroundColor: Colors.redAccent,
                    behavior: SnackBarBehavior.floating,
                  ));
                },
                background: Container(
                  color: Colors.redAccent,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  child: const Icon(Icons.delete_sweep, color: Colors.white),
                ),
                child: ListTile(
                  leading: Icon(
                    widget.category == "Issue" ? Icons.bug_report : Icons.description,
                    color: Colors.cyanAccent,
                  ),
                  title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text("Reference ID: ${item['id']}"),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => DecryptionDetailView(
                          entry: item,
                          category: widget.category,
                        ),
                      ),
                    ).then((_) => _loadEntries());
                  },
                ),
              );
            },
          ),
    );
  }
}

class DecryptionDetailView extends StatefulWidget {
  final Map<String, dynamic> entry;
  final String category;

  const DecryptionDetailView({super.key, required this.entry, required this.category});

  @override
  State<DecryptionDetailView> createState() => _DecryptionDetailViewState();
}

class _DecryptionDetailViewState extends State<DecryptionDetailView> {
  String _decryptedContent = "";
  String _decryptedDescription = "";
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _performDecryption();
  }

  /// PHASE 4: Just-In-Time (JIT) Decryption Logic
  Future<void> _performDecryption() async {
    try {
      final masterKey = SecurityService.activeKey;

      if (widget.category == "Issue") {
        final desc = await SecurityService.decryptData(
            widget.entry['issue_description'] ?? "", masterKey);
        final fix = await SecurityService.decryptData(
            widget.entry['solution_fix'] ?? "", masterKey);

        if (!mounted) return;
        setState(() {
          _decryptedDescription = desc;
          _decryptedContent = fix;
          _isLoading = false;
        });
      } else if (widget.category == "Process") {
        final rawJson = await SecurityService.decryptData(
            widget.entry['content'] ?? "", masterKey);

        final Map<String, dynamic> data = jsonDecode(rawJson);

        String markdown =
            "### Description\n${data['description'] ?? 'No description provided.'}\n\n";
        markdown += "### Procedure\n";
        List steps = data['steps'] ?? [];
        if (steps.isEmpty) {
          markdown += "_No steps documented._\n";
        } else {
          for (int i = 0; i < steps.length; i++) {
            markdown += "${i + 1}. ${steps[i]}\n";
          }
        }

        if (data['notes'] != null && data['notes'].toString().trim().isNotEmpty) {
          markdown += "\n---\n> **💡 Notes:** ${data['notes']}";
        }

        if (!mounted) return;
        setState(() {
          _decryptedContent = markdown;
          _isLoading = false;
        });
      } else {
        final content = await SecurityService.decryptData(
            widget.entry['content'] ?? "", masterKey);

        if (!mounted) return;
        setState(() {
          _decryptedContent = content;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _decryptedContent = "### ⚠️ Decryption Error\nFailed to unlock documentation: $e";
        _isLoading = false;
      });
    }
  }

  // --- HELPER METHODS FOR METADATA DISPLAY ---

  String _parseRarity(dynamic rank) {
    if (rank == 3) return "CRITICAL";
    if (rank == 2) return "RARE";
    return "COMMON";
  }

  Color _getRarityColor(dynamic rank) {
    if (rank == 3) return Colors.redAccent;
    if (rank == 2) return Colors.orangeAccent;
    return Colors.blueAccent;
  }

  Widget _buildMetadataChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            label.toUpperCase(),
            style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, Color color) {
    return Text(
      title,
      style: TextStyle(
        color: color,
        fontWeight: FontWeight.bold,
        fontSize: 12,
        letterSpacing: 2.0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryHeaderColor = theme.colorScheme.primary;
    final secondaryHeaderColor = theme.colorScheme.tertiary;

    final commonMarkdownStyle = MarkdownStyleSheet(
      p: TextStyle(
          fontSize: 15, height: 1.6, color: theme.colorScheme.onSurface),
      code: TextStyle(
        backgroundColor: isDark ? Colors.black54 : Colors.grey[200],
        fontFamily: 'monospace',
        color: isDark ? Colors.greenAccent : Colors.green[800],
        fontSize: 14,
      ),
      codeblockDecoration: BoxDecoration(
        color: isDark ? Colors.black : Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      blockquoteDecoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      blockquote: TextStyle(color: theme.colorScheme.secondary),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.entry['problem_summary'] ?? widget.entry['title'] ?? "Detail View"),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_note, color: Colors.cyanAccent),
            tooltip: "Edit Entry",
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => EntryEditor(
                    category: widget.category,
                    existingEntry: widget.entry,
                  ),
                ),
              ).then((_) => _performDecryption());
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined, color: Colors.redAccent),
            tooltip: "Purge Entry",
            onPressed: () async {
              final navigator = Navigator.of(context);
              final messenger = ScaffoldMessenger.of(context);
              final String title = widget.entry['problem_summary'] ?? widget.entry['title'] ?? "this entry";

              bool confirmed = await SecurityService.confirmDeletion(context, title);

              if (confirmed && mounted) {
                try {
                  final db = await DatabaseService().database;
                  final tableName = widget.category == "Issue" ? 'issues' : 'knowledge_base';
                  await db.delete(tableName, where: 'id = ?', whereArgs: [widget.entry['id']]);

                  navigator.pop();
                  messenger.showSnackBar(SnackBar(
                    content: Text("$title purged from vault."),
                    backgroundColor: Colors.redAccent,
                    behavior: SnackBarBehavior.floating,
                  ));
                } catch (e) {
                  debugPrint("Delete error: $e");
                }
              }
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.greenAccent))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.category == "Issue") ...[
                    Row(
                      children: [
                        _buildMetadataChip(
                            Icons.error_outline,
                            _parseRarity(widget.entry['complexity_rank']),
                            _getRarityColor(widget.entry['complexity_rank'])),
                        const SizedBox(width: 10),
                        _buildMetadataChip(
                            Icons.history,
                            "Hits: ${widget.entry['frequency_count'] ?? 0}",
                            Colors.grey),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _buildSectionHeader("SYMPTOM DESCRIPTION", primaryHeaderColor),
                    const SizedBox(height: 12),
                    MarkdownBody(
                      data: _decryptedDescription,
                      styleSheet: commonMarkdownStyle,
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Divider(
                          color: theme.colorScheme.outlineVariant, thickness: 1),
                    ),
                    _buildSectionHeader("VERIFIED SOLUTION", secondaryHeaderColor),
                    const SizedBox(height: 12),
                    MarkdownBody(
                      data: _decryptedContent,
                      selectable: true,
                      styleSheet: commonMarkdownStyle,
                    ),
                  ] else ...[
                    _buildSectionHeader(widget.category.toUpperCase(), primaryHeaderColor),
                    const SizedBox(height: 12),
                    MarkdownBody(
                      data: _decryptedContent,
                      selectable: true,
                      styleSheet: commonMarkdownStyle,
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}

class GlobalSearchDelegate extends SearchDelegate {
  String? _lastQuery;
  Future<List<Map<String, dynamic>>>? _searchFuture;

  @override
  List<Widget>? buildActions(BuildContext context) => [
        IconButton(
          icon: const Icon(Icons.clear),
          onPressed: () {
            query = '';
            showSuggestions(context);
          },
        )
      ];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => close(context, null),
      );

  @override
  Widget buildResults(BuildContext context) => _buildSearchResults(context);

  @override
  Widget buildSuggestions(BuildContext context) => _buildSearchResults(context);

  Widget _buildSearchResults(BuildContext context) {
    final theme = Theme.of(context);
    
    if (query.trim().isEmpty) {
      return Center(
        child: Text("Search across NetCodex...", 
          style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
      );
    }

    if (_lastQuery != query) {
      _lastQuery = query;
      _searchFuture = _searchAllTables(query.trim());
    }

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _searchFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator(color: theme.colorScheme.primary));
        }

        if (snapshot.hasError) {
          return const Center(child: Text("Search error occurred."));
        }

        final results = snapshot.data ?? [];

        if (results.isEmpty) {
          return const Center(child: Text("No matches found in the vault."));
        }

        return ListView.builder(
          itemCount: results.length,
          itemBuilder: (context, index) {
            final item = results[index];
            return ListTile(
              leading: Icon(_getIcon(item['origin']), color: theme.colorScheme.primary),
              title: Text(item['display_title'], 
                style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.w500)),
              subtitle: Text(
                item['origin'].toUpperCase(),
                style: TextStyle(fontSize: 10, color: theme.colorScheme.secondary, fontWeight: FontWeight.bold),
              ),
              onTap: () => _navigateToResult(context, item),
            );
          },
        );
      },
    );
  }

  Future<List<Map<String, dynamic>>> _searchAllTables(String q) async {
    final db = await DatabaseService().database;
    final masterKey = SecurityService.activeKey;
    List<Map<String, dynamic>> combined = [];

    // 1. Search Issues
    final issues = await db.query('issues', 
      where: 'problem_summary LIKE ? COLLATE NOCASE', whereArgs: ['%$q%']);
    combined.addAll(issues.map((e) => {...e, 'origin': 'Issue', 'display_title': e['problem_summary']}));

    // 2. Search Knowledge Base (Scripts/Processes)
    final kb = await db.query('knowledge_base', 
      where: 'title LIKE ? COLLATE NOCASE', whereArgs: ['%$q%']);
    combined.addAll(kb.map((e) => {...e, 'origin': e['type'], 'display_title': e['title']}));

    // 3. Search Infrastructure (Sites)
    final sites = await db.query('site_folders', 
      where: 'name LIKE ? COLLATE NOCASE', whereArgs: ['%$q%']);
    combined.addAll(sites.map((e) => {...e, 'origin': 'Infrastructure', 'display_title': e['name'], 'is_site': true}));

    // 4. Search Network Ledger (VLANs - Requires Decryption for Deep Search)
    final networkRecords = await db.query('network_ledger');
    for (var row in networkRecords) {
      bool match = false;
      // Check unencrypted label
      if (row['label'].toString().toLowerCase().contains(q.toLowerCase())) {
        match = true;
      } else {
        // Check encrypted data
        try {
          String decrypted = await SecurityService.decryptData(row['data_json'] as String, masterKey);
          if (decrypted.toLowerCase().contains(q.toLowerCase())) match = true;
        } catch (_) {}
      }

      if (match) {
        combined.add({
          ...row, 
          'origin': 'Infrastructure', 
          'display_title': "VLAN: ${row['label']}",
          'is_site': false,
          'site_id': row['site_id']
        });
      }
    }

    // 5. Search Go-Bag & Tool Sheets
    final tools = await db.query('go_bag_tools', 
      where: 'name LIKE ? COLLATE NOCASE OR category LIKE ? COLLATE NOCASE', whereArgs: ['%$q%', '%$q%']);
    combined.addAll(tools.map((e) => {...e, 'origin': 'Tool Sheet', 'display_title': e['name']}));

    // 6. Search Lecture Notes
    final notes = await db.query('notes', 
      where: 'title LIKE ? OR content_text LIKE ? COLLATE NOCASE', 
      whereArgs: ['%$q%', '%$q%']);
    combined.addAll(notes.map((e) => {
      ...e, 
      'origin': 'Note', 
      'display_title': e['title']
    }));

    return combined;
  }

  IconData _getIcon(String origin) {
    switch (origin.toLowerCase()) {
      case 'issue': return Icons.bug_report;
      case 'process': return Icons.assignment;
      case 'infrastructure': return Icons.lan;
      case 'tool sheet': return Icons.handyman;
      case 'note': return Icons.edit_note;
      default: return Icons.terminal;
    }
  }

  void _navigateToResult(BuildContext context, Map<String, dynamic> item) {
    final String origin = item['origin'].toString().toLowerCase();

    if (origin == 'infrastructure') {
      // Deep-link into the SiteExplorer with the specific site ID
      Navigator.push(context, MaterialPageRoute(
        builder: (context) => SiteExplorerScreen(
          initialSiteId: item['is_site'] ? item['id'] : item['site_id']
        ),
      ));
    } else if (origin == 'tool sheet') {
      Navigator.push(context, MaterialPageRoute(
        builder: (context) => ToolSheetScreen(tool: item),
      ));
    } else if (origin == 'note') {
        // Navigate to your specific Note Editor
        Navigator.push(context, MaterialPageRoute(
          builder: (context) => NotesScreen(note: item),
        ));
    } else {
      Navigator.push(context, MaterialPageRoute(
        builder: (context) => DecryptionDetailView(
          entry: item,
          category: item['origin'],
        ),
      ));
    }
  }
}