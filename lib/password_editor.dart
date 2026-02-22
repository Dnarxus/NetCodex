import 'dart:math';
import 'package:flutter/material.dart';
import 'database_service.dart';
import 'security_service.dart';

// --- 1. THE VAULT LIST SCREEN ---
// This is the class your main.dart is looking for.
class PasswordVaultScreen extends StatefulWidget {
  const PasswordVaultScreen({super.key});

  @override
  State<PasswordVaultScreen> createState() => _PasswordVaultScreenState();
}

class _PasswordVaultScreenState extends State<PasswordVaultScreen> {
  List<Map<String, dynamic>> _passwords = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchPasswords();
  }

  Future<void> _fetchPasswords() async {
    final db = await DatabaseService().database;
    final data = await db.query('passwords');
    setState(() {
      _passwords = data;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Password Vault"),
        backgroundColor: Colors.transparent,
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.greenAccent,
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const PasswordEditor()),
        ).then((_) => _fetchPasswords()),
        child: const Icon(Icons.add, color: Colors.black),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _passwords.isEmpty
              ? const Center(child: Text("No credentials saved yet."))
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: _passwords.length,
                  itemBuilder: (context, index) {
                    final item = _passwords[index];
                    return Dismissible(
                      key: Key(item['id'].toString()),
                      direction: DismissDirection.endToStart,
                      // THE GATEKEEPER: Call the global helper here
                      confirmDismiss: (direction) async {
                        return await SecurityService.confirmDeletion(context, item['account_name']);
                      },
                      onDismissed: (direction) async {
                        // 1. Capture the messenger state before the async gap
                        final messenger = ScaffoldMessenger.of(context);
                        final deletedName = item['account_name'];

                        final db = await DatabaseService().database;
                        
                        // 2. Perform the destructive action
                        await db.delete('passwords', where: 'id = ?', whereArgs: [item['id']]);
                        
                        // 3. Use the captured messenger to notify the user safely
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text("$deletedName purged from vault."),
                            backgroundColor: Colors.redAccent,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        color: Colors.redAccent,
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                      child: Card(
                        color: Colors.white10,
                        child: ListTile(
                          leading: const Icon(Icons.vpn_key, color: Colors.greenAccent),
                          title: Text(item['account_name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(item['username'] ?? ""),
                          trailing: const Icon(Icons.edit, size: 18, color: Colors.grey),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => PasswordEditor(existingEntry: item)),
                            ).then((_) => _fetchPasswords());
                          },
                        ),
                      ),
                    );
                  }
                ),
    );
  }
}

// --- 2. THE EDITOR UI ---
class PasswordEditor extends StatefulWidget {
  final Map<String, dynamic>? existingEntry;
  const PasswordEditor({super.key, this.existingEntry});

  @override
  State<PasswordEditor> createState() => _PasswordEditorState();
}

class _PasswordEditorState extends State<PasswordEditor> {
  final _accountController = TextEditingController();
  final _userController = TextEditingController();
  final _emailController = TextEditingController();
  final _passController = TextEditingController();
  bool _isObscured = true;

  @override
  void initState() {
    super.initState();
    if (widget.existingEntry != null) {
      _accountController.text = widget.existingEntry!['account_name'] ?? "";
      _userController.text = widget.existingEntry!['username'] ?? "";
      _emailController.text = widget.existingEntry!['email'] ?? "";
      _decryptExistingPassword();
    }
  }

  Future<void> _decryptExistingPassword() async {
    try {
      final masterKey = SecurityService.activeKey; //
      final encryptedPass = widget.existingEntry!['encrypted_password'];
      
      if (encryptedPass != null) {
        final decrypted = await SecurityService.decryptData(encryptedPass, masterKey);
        setState(() {
          _passController.text = decrypted;
        });
      }
    } catch (e) {
      debugPrint("Decryption failed: $e");
    }
  }

  Future<void> _deleteAccount() async {
    if (widget.existingEntry == null) return;

    bool confirmed = await SecurityService.confirmDeletion(
      context, 
      widget.existingEntry!['account_name']
    );

    if (confirmed && mounted) {
      // Capture services before starting async database work
      final navigator = Navigator.of(context);
      final messenger = ScaffoldMessenger.of(context);

      try {
        final db = await DatabaseService().database;

        await db.delete(
          'passwords', 
          where: 'id = ?', 
          whereArgs: [widget.existingEntry!['id']]
        );

        navigator.pop(); // Uses captured navigator safely
        messenger.showSnackBar(
          const SnackBar(
            content: Text("Account deleted from vault"), 
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          )
        );
      } catch (e) {
        debugPrint("Delete Error: $e");
      }
    }
  }

  void _generateStrongPassword() {
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#\$%^&*()';
    final random = Random.secure();
    final password = List.generate(16, (index) => chars[random.nextInt(chars.length)]).join();
    setState(() {
      _passController.text = password;
      _isObscured = false;
    });
  }

  Future<void> _savePassword() async {
    if (!mounted) return;
    
    // Capture navigator state before async database/encryption work
    final navigator = Navigator.of(context);

    try {
      final masterKey = SecurityService.activeKey;
      final encryptedPass = await SecurityService.encryptData(_passController.text, masterKey);
      final db = await DatabaseService().database;

      final data = {
        'account_name': _accountController.text,
        'username': _userController.text,
        'email': _emailController.text,
        'encrypted_password': encryptedPass,
      };

      if (widget.existingEntry == null) {
        await db.insert('passwords', data);
      } else {
        await db.update(
          'passwords', 
          data, 
          where: 'id = ?', 
          whereArgs: [widget.existingEntry!['id']]
        );
      }

      navigator.pop(); // Navigate back safely
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Encryption Error: $e"), 
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        )
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existingEntry == null ? "Secure Credential" : "Update Account"),
        backgroundColor: Colors.transparent,
        // Added the delete action to the AppBar
        actions: [
          if (widget.existingEntry != null)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              onPressed: _deleteAccount,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildField(_accountController, "Account Name (e.g. Google)", Icons.apps),
          _buildField(_userController, "Username", Icons.person),
          _buildField(_emailController, "Email Address", Icons.email),
          TextField(
            controller: _passController,
            obscureText: _isObscured,
            style: const TextStyle(fontFamily: 'monospace', letterSpacing: 2),
            decoration: InputDecoration(
              labelText: "Password",
              prefixIcon: const Icon(Icons.lock),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.refresh, color: Colors.cyanAccent),
                    onPressed: _generateStrongPassword,
                  ),
                  IconButton(
                    icon: Icon(_isObscured ? Icons.visibility : Icons.visibility_off),
                    onPressed: () => setState(() => _isObscured = !_isObscured),
                  ),
                ],
              ),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 30),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _savePassword,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.greenAccent, 
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text("ENCRYPT & SAVE TO VAULT", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildField(TextEditingController controller, String label, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label, 
          prefixIcon: Icon(icon), 
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}