import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:archive/archive_io.dart'; // REQUIRED for bundling assets
import 'security_service.dart';

class MigrationService {
  /// BUNDLED EXPORT: Archives Database + app_assets folder into a .codex file
  static Future<void> exportDatabase(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final dbPath = join(await getDatabasesPath(), 'netcodex_vault.db');
      final appDocDir = await getApplicationDocumentsDirectory();
      final assetPath = join(appDocDir.path, 'app_assets');
      
      final directory = await getTemporaryDirectory();
      final String backupPath = join(directory.path, "NetCodex_Full_Backup_${DateTime.now().millisecondsSinceEpoch}.codex");

      // Initialize Encoder
      var encoder = ZipFileEncoder();
      encoder.create(backupPath);
      
      // 1. Add the Database file
      encoder.addFile(File(dbPath));
      
      // 2. Add the Photos directory (app_assets)
      final assetDir = Directory(assetPath);
      if (await assetDir.exists()) {
        // addDirectory includes all files within and the directory structure itself
        encoder.addDirectory(assetDir);
      }
      
      encoder.close();

      await Share.shareXFiles([XFile(backupPath)], text: 'NetCodex Full Vault Export (.codex)');
    } catch (e) {
      _showSafeSnackBar(messenger, "Export Failed: $e", isError: true);
    }
  }

  /// BUNDLED IMPORT: Extracts Database and restores hardware photos to app_assets
  static Future<void> importDatabase(BuildContext context, VoidCallback onComplete) async {
    final messenger = ScaffoldMessenger.of(context);
    bool confirmed = await _showConfirmationDialog(context);
    if (!confirmed) return;

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.any);

      if (result != null && result.files.single.path != null) {
        final String filePath = result.files.single.path!;
        
        // Decode the Zip Archive
        final archiveBytes = await File(filePath).readAsBytes();
        final archive = ZipDecoder().decodeBytes(archiveBytes);

        final dbPath = join(await getDatabasesPath(), 'netcodex_vault.db');
        final appDocDir = await getApplicationDocumentsDirectory();

        // Temporary path for integrity check
        String tempDbPath = join((await getTemporaryDirectory()).path, "temp_check.db");

        for (final file in archive) {
          final filename = file.name;
          if (file.isFile) {
            final data = file.content as List<int>;
            
            if (filename.endsWith('netcodex_vault.db')) {
              // Extract to temp for integrity check
              final tempFile = File(tempDbPath);
              await tempFile.writeAsBytes(data);
              
              bool isValid = await _verifyVaultIntegrity(tempDbPath);
              if (!isValid) {
                _showSafeSnackBar(messenger, "Integrity Check Failed: Invalid Database Schema.", isError: true);
                return;
              }
              // Move verified database to actual location
              await tempFile.copy(dbPath);
            } else if (filename.contains('app_assets/')) {
              // Restore Asset Files (Photos) to app_assets maintaining relative paths
              final outFile = File(join(appDocDir.path, filename));
              await outFile.create(recursive: true);
              await outFile.writeAsBytes(data);
            }
          }
        }

        _showSafeSnackBar(messenger, "Vault & Assets Restored. Re-authentication required.");
        
        Future.delayed(const Duration(seconds: 2), () {
          // Clear active session to ensure new database keys are derived
          SecurityService.endSession(); 
          onComplete(); 
        });
      }
    } catch (e) {
      _showSafeSnackBar(messenger, "Import Failed: $e", isError: true);
    }
  }

  /// Verifies the SQLite schema contains essential network and hardware tables
  static Future<bool> _verifyVaultIntegrity(String path) async {
    Database? tempDb;
    try {
      tempDb = await openDatabase(path, readOnly: true);
      var tables = await tempDb.rawQuery("SELECT name FROM sqlite_master WHERE type='table'");
      List<String> tableNames = tables.map((row) => row['name'] as String).toList();

      // Check for core tables and the metadata table added for cross-device salt sync
      bool hasCore = tableNames.contains('site_folders') && 
                     tableNames.contains('go_bag_tools') &&
                     tableNames.contains('passwords') &&
                     tableNames.contains('vault_metadata');

      await tempDb.close();
      return hasCore;
    } catch (e) {
      if (tempDb != null) await tempDb.close();
      return false;
    }
  }

  static Future<bool> _showConfirmationDialog(BuildContext context) async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Overwrite Current Vault?"),
        content: const Text("Importing will replace all documented data and hardware photos. Proceed?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("CANCEL")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(context, true),
            child: const Text("IMPORT", style: TextStyle(color: Colors.white)),
          ),
        ],
      )
    ) ?? false;
  }

  static void _showSafeSnackBar(ScaffoldMessengerState messenger, String msg, {bool isError = false}) {
    messenger.showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.redAccent : Colors.greenAccent,
      behavior: SnackBarBehavior.floating,
    ));
  }
}