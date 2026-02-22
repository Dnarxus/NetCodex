import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart'; 
import 'database_service.dart';

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
    final combined = base64Decode(cipherBase64);
    final secretBox = SecretBox.fromConcatenation(
      combined,
      nonceLength: _algorithm.nonceLength,
      macLength: _algorithm.macAlgorithm.macLength,
    );
    final clearText = await _algorithm.decrypt(secretBox, secretKey: masterKey);
    return utf8.decode(clearText);
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