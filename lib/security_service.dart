import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart'; 
import 'database_service.dart';
import 'main.dart';

/// VOLATILE SESSION MANAGEMENT
class VaultSession {
  final SecretKey masterKey;
  final DateTime sessionStart;

  VaultSession({required this.masterKey}) : sessionStart = DateTime.now();
}

class SecurityService {
  static const _secureStorage = FlutterSecureStorage();
  static const _saltKey = 'netcodex_crypt_salt';
  static const _verificationKey = 'netcodex_auth_check';
  static final _algorithm = AesGcm.with256bits();

  static VaultSession? _currentSession;

  static SecretKey get activeKey {
    if (_currentSession == null) throw Exception("Vault Session Expired.");
    return _currentSession!.masterKey;
  }

  static void startSession(SecretKey key) {
    _currentSession = VaultSession(masterKey: key);
  }

  static void endSession() {
    _currentSession = null;
    PracticeService().clearCache(); 
    
    debugPrint("SECURITY: Session terminated and memory caches purged.");
  }

  /// STEP 1: Initialization & Metadata Anchor Generation
  static Future<void> initOnboarding(String pin) async {
    final saltBytes = SecretKeyData.random(length: 32).bytes;
    final saltBase64 = base64Encode(saltBytes);

    // Save salt locally
    await _secureStorage.write(key: _saltKey, value: saltBase64);

    final masterKey = await deriveMasterKey(pin);
    final encryptedCheck = await encryptData("NETCODEX_VERIFIED", masterKey);
    
    // Save verification anchor locally
    await _secureStorage.write(key: _verificationKey, value: encryptedCheck);

    // PERSISTENCE: Save both Salt and Auth Check to database for portability
    final db = await DatabaseService().database;
    await db.insert('vault_metadata', {
      'config_key': 'vault_salt',
      'config_value': saltBase64,
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    await db.insert('vault_metadata', {
      'config_key': 'vault_auth_check',
      'config_value': encryptedCheck,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// PIN Verification & Salt/Anchor Synchronization Logic
  static Future<bool> verifyPin(String pin) async {
    try {
      final db = await DatabaseService().database;
      
      // 1. Restore Salt and Auth Check from DB metadata (Fixes fresh-install issues)
      final List<Map<String, dynamic>> maps = await db.query('vault_metadata');
      final metadata = {for (var item in maps) item['config_key']: item['config_value']};

      if (metadata.containsKey('vault_salt')) {
        await _secureStorage.write(key: _saltKey, value: metadata['vault_salt'] as String);
      }
      
      if (metadata.containsKey('vault_auth_check')) {
        await _secureStorage.write(key: _verificationKey, value: metadata['vault_auth_check'] as String);
      }

      // 2. Standard verification using the (potentially restored) anchor
      final storedCheck = await _secureStorage.read(key: _verificationKey);
      if (storedCheck == null) return false;

      final masterKey = await deriveMasterKey(pin);
      final decrypted = await decryptData(storedCheck, masterKey);

      bool isValid = decrypted == "NETCODEX_VERIFIED";
      if (isValid) startSession(masterKey);
      
      return isValid;
    } catch (e) {
      return false;
    }
  }

  /// STEP 2: PBKDF2 Key Derivation 
  static Future<SecretKey> deriveMasterKey(String pin) async {
    final saltString = await _secureStorage.read(key: _saltKey);
    if (saltString == null) throw Exception("System not initialized.");

    final salt = base64Decode(saltString);
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: 100000,
      bits: 256,
    );

    return await pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(pin)),
      nonce: salt,
    );
  }

  /// STEP 3: AES-256 Encryption 
  static Future<String> encryptData(String plaintext, SecretKey masterKey) async {
    final clearText = utf8.encode(plaintext);
    final secretBox = await _algorithm.encrypt(clearText, secretKey: masterKey);
    return base64Encode(secretBox.concatenation());
  }

  /// STEP 4: Just-In-Time Decryption 
  static Future<String> decryptData(String cipherBase64, SecretKey masterKey) async {
    debugPrint("DEBUG: Attempting to decrypt: ${cipherBase64.substring(0, 10)}...");
    final combined = base64Decode(cipherBase64);
    final secretBox = SecretBox.fromConcatenation(
      combined,
      nonceLength: _algorithm.nonceLength,
      macLength: _algorithm.macAlgorithm.macLength,
    );
    final clearText = await _algorithm.decrypt(secretBox, secretKey: masterKey);
    return utf8.decode(clearText);
  }

  /// STEP 5: Secure PIN Rotation with Data Migration
  static Future<bool> updateMasterPin(String oldPin, String newPin) async {
    try {
      debugPrint("MIGRATION: Verifying identity...");
      bool isAuthorized = await _verifyOldPinOnly(oldPin);
      if (!isAuthorized) {
        debugPrint("MIGRATION ERROR: Identity verification failed.");
        return false;
      }

      final db = await DatabaseService().database;
      final oldKey = activeKey;

      // --- 1. EXTRACTION PHASE ---
      debugPrint("MIGRATION: Extracting tables...");
      final kbData = await db.query('knowledge_base');
      final issueData = await db.query('issues');
      final ledgerData = await db.query('network_ledger');
      final passwordData = await db.query('passwords');
      final notesData = await db.query('notes');
      final versionsData = await db.query('note_versions');
      final practiceData = await db.query('practice_bank');

      // Helper for safe decryption to find exactly which record fails
      Future<String?> safeDecrypt(String? cipher, SecretKey key, String tableName, int id) async {
        if (cipher == null) return null;
        try {
          return await decryptData(cipher, key);
        } catch (e) {
          debugPrint("CRITICAL: Decryption failed for $tableName (ID: $id). This record might be corrupted or plaintext.");
          return null; // Skip this record instead of crashing the app
        }
      }

      // --- 2. DECRYPTION PHASE (With Logging) ---
      debugPrint("MIGRATION: Decrypting Knowledge Base...");
      Map<int, String> decryptedKB = {};
      for (var r in kbData) {
        String? dec = await safeDecrypt(r['content'] as String, oldKey, 'KB', r['id'] as int);
        if (dec != null) decryptedKB[r['id'] as int] = dec;
      }

      debugPrint("MIGRATION: Decrypting Issues...");
      List<Map<String, dynamic>> decryptedIssues = [];
      for (var r in issueData) {
        String? d = await safeDecrypt(r['issue_description'] as String, oldKey, 'IssueDesc', r['id'] as int);
        String? f = await safeDecrypt(r['solution_fix'] as String, oldKey, 'IssueFix', r['id'] as int);
        if (d != null && f != null) decryptedIssues.add({'id': r['id'], 'desc': d, 'fix': f});
      }

      debugPrint("MIGRATION: Decrypting Ledger...");
      Map<int, String> decryptedLedger = {};
      for (var r in ledgerData) {
        String? dec = await safeDecrypt(r['data_json'] as String, oldKey, 'Ledger', r['id'] as int);
        if (dec != null) decryptedLedger[r['id'] as int] = dec;
      }

      debugPrint("MIGRATION: Decrypting Passwords...");
      List<Map<String, dynamic>> decryptedPass = [];
      for (var r in passwordData) {
        String? p = await safeDecrypt(r['encrypted_password'] as String, oldKey, 'Password', r['id'] as int);
        if (p != null) decryptedPass.add({'id': r['id'], 'pass': p});
      }

      debugPrint("MIGRATION: Decrypting Notes & Versions...");
      Map<int, String> decryptedNotes = {};
      for (var r in notesData) {
        String? dec = await safeDecrypt(r['content_text'] as String, oldKey, 'Note', r['id'] as int);
        if (dec != null) decryptedNotes[r['id'] as int] = dec;
      }
      Map<int, String> decryptedVersions = {};
      for (var r in versionsData) {
        String? dec = await safeDecrypt(r['content_text'] as String, oldKey, 'Version', r['id'] as int);
        if (dec != null) decryptedVersions[r['id'] as int] = dec;
      }

      debugPrint("MIGRATION: Decrypting Practice Bank...");
      List<Map<String, dynamic>> decryptedPractice = [];
      for (var r in practiceData) {
        String? q = await safeDecrypt(r['question'] as String, oldKey, 'PracticeQ', r['id'] as int);
        String? a = await safeDecrypt(r['answer'] as String, oldKey, 'PracticeA', r['id'] as int);
        if (q != null && a != null) decryptedPractice.add({'id': r['id'], 'q': q, 'a': a});
      }

      // --- 3. KEY ROTATION PHASE ---
      debugPrint("MIGRATION: Rotating keys...");
      await initOnboarding(newPin); 
      final newKey = await deriveMasterKey(newPin);
      startSession(newKey); 

      // --- 4. RE-ENCRYPTION PHASE ---
      debugPrint("MIGRATION: Beginning Database Transaction...");
      await db.transaction((txn) async {
        for (var entry in decryptedKB.entries) {
          String cipher = await encryptData(entry.value, newKey);
          await txn.update('knowledge_base', {'content': cipher}, where: 'id = ?', whereArgs: [entry.key]);
        }
        for (var item in decryptedIssues) {
          String cDesc = await encryptData(item['desc'], newKey);
          String cFix = await encryptData(item['fix'], newKey);
          await txn.update('issues', {'issue_description': cDesc, 'solution_fix': cFix}, where: 'id = ?', whereArgs: [item['id']]);
        }
        for (var entry in decryptedLedger.entries) {
          String cipher = await encryptData(entry.value, newKey);
          await txn.update('network_ledger', {'data_json': cipher}, where: 'id = ?', whereArgs: [entry.key]);
        }
        for (var item in decryptedPass) {
          String cipher = await encryptData(item['pass'], newKey);
          await txn.update('passwords', {'encrypted_password': cipher}, where: 'id = ?', whereArgs: [item['id']]);
        }
        for (var entry in decryptedNotes.entries) {
          String cipher = await encryptData(entry.value, newKey);
          await txn.update('notes', {'content_text': cipher}, where: 'id = ?', whereArgs: [entry.key]);
        }
        for (var entry in decryptedVersions.entries) {
          String cipher = await encryptData(entry.value, newKey);
          await txn.update('note_versions', {'content_text': cipher}, where: 'id = ?', whereArgs: [entry.key]);
        }
        for (var item in decryptedPractice) {
          String cQ = await encryptData(item['q'], newKey);
          String cA = await encryptData(item['a'], newKey);
          await txn.update('practice_bank', {'question': cQ, 'answer': cA}, where: 'id = ?', whereArgs: [item['id']]);
        }
      });

      debugPrint("MIGRATION SUCCESSFUL.");
      return true;
    } catch (e) {
      debugPrint("SECURITY ENGINE CRITICAL: Migration Failure -> $e");
      return false;
    }
  }

  static Future<bool> _verifyOldPinOnly(String pin) async {
    try {
      final db = await DatabaseService().database;
      
      // 1. SYNC: Pull Salt and Auth Check from DB to handle fresh installs/cache clears
      final List<Map<String, dynamic>> maps = await db.query('vault_metadata');
      final metadata = {for (var item in maps) item['config_key']: item['config_value']};

      if (metadata.containsKey('vault_salt')) {
        await _secureStorage.write(key: _saltKey, value: metadata['vault_salt'] as String);
      }
      
      if (metadata.containsKey('vault_auth_check')) {
        await _secureStorage.write(key: _verificationKey, value: metadata['vault_auth_check'] as String);
      }

      // 2. Standard verification using the (now synchronized) anchor
      final storedCheck = await _secureStorage.read(key: _verificationKey);
      if (storedCheck == null) return false;

      // deriveMasterKey will now find the salt it needs in _secureStorage
      final masterKey = await deriveMasterKey(pin);
      final decrypted = await decryptData(storedCheck, masterKey);

      return decrypted == "NETCODEX_VERIFIED";
    } catch (e) {
      debugPrint("Security Engine: _verifyOldPinOnly error: $e");
      return false;
    }
  }

  /// GLOBAL UI HELPER: Deletion Confirmation 
  static Future<bool> confirmDeletion(BuildContext context, String itemName) async {
    final theme = Theme.of(context);
    return await showDialog<bool>(
      context: context, 
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
            SizedBox(width: 10),
            Text("Confirm Deletion"),
          ],
        ),
        content: Text("Permanently delete '$itemName'? This action cannot be undone."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text("CANCEL", style: TextStyle(color: theme.colorScheme.secondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text("DELETE", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    ) ?? false;
  }
}

class SecuritySettingsScreen extends StatefulWidget {
  const SecuritySettingsScreen({super.key});

  @override
  State<SecuritySettingsScreen> createState() => _SecuritySettingsScreenState();
}

class _SecuritySettingsScreenState extends State<SecuritySettingsScreen> {
  final _oldPinController = TextEditingController();
  final _newPinController = TextEditingController();
  final _confirmPinController = TextEditingController();
  bool _isUpdating = false;

  Future<void> _handlePinUpdate() async {
    // 1. Validation
    if (_newPinController.text.length < 6) {
      _showError("Security Policy: 6-digit minimum required.");
      return;
    }

    if (_newPinController.text != _confirmPinController.text) {
      _showError("PINs do not match. Please verify your new entry.");
      return;
    }

    // 2. Lock the UI and show the clean Loading Dialog
    setState(() => _isUpdating = true);
    
    _showLoadingDialog();

    // 3. Run the migration
    bool success = await SecurityService.updateMasterPin(
      _oldPinController.text, 
      _newPinController.text
    );

    if (!mounted) return;

    // 4. Close the dialog and unlock state
    Navigator.pop(context); // Closes the Loading Dialog
    setState(() => _isUpdating = false);

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Vault Re-encrypted. Please login with your new PIN."))
      );

      // 5. REDIRECT: Clear stack and go to Login (Pin Gate)
      // Replace 'VaultPinGateScreen' with your actual login class name
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const PinGateScreen()),
        (route) => false, // This removes all previous screens from memory
      );
    } else {
      _showError("Migration Failed. Check current PIN.");
    }
  }

  // Helper to show a clean, non-dismissible loading dialog
  void _showLoadingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const PopScope( // Modern replacement for WillPopScope
        canPop: false, // Prevents backing out during the migration
        child: Dialog(
          backgroundColor: Colors.black87,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 30, horizontal: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: Colors.amberAccent),
                SizedBox(height: 25),
                Text(
                  "Re-encrypting Vault...",
                  style: TextStyle(
                    color: Colors.white, 
                    fontWeight: FontWeight.bold, 
                    fontSize: 16,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  "Please do not close the app.",
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.redAccent)
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Security Settings")),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: SingleChildScrollView(
          child: Column(
            children: [
              const Icon(Icons.lock_reset, size: 64, color: Colors.amberAccent),
              const SizedBox(height: 20),
              const Text(
                "MASTER PIN ROTATION",
                style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.5),
              ),
              const Text(
                "This will re-encrypt all vault data with your new key.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 30),
              TextField(
                controller: _oldPinController, 
                decoration: const InputDecoration(labelText: "Current Master PIN", border: OutlineInputBorder()), 
                obscureText: true,
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 15),
              TextField(
                controller: _newPinController, 
                decoration: const InputDecoration(labelText: "New 6-Digit PIN", border: OutlineInputBorder()), 
                obscureText: true,
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 15),
              TextField(
                controller: _confirmPinController, 
                decoration: const InputDecoration(labelText: "Confirm New PIN", border: OutlineInputBorder()), 
                obscureText: true,
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isUpdating ? null : _handlePinUpdate, 
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amberAccent,
                    foregroundColor: Colors.black,
                  ),
                  child: const Text("INITIALIZE RE-ENCRYPTION", style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}