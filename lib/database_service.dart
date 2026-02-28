import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:convert';
import 'security_service.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';

class DatabaseService {
  static Database? _database;

  // Singleton pattern ensures the SQLite engine acts as the primary storage 
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  Future<Database> _initDB() async {
    String path = join(await getDatabasesPath(), 'netcodex_vault.db');
    
    return await openDatabase(
      path,
      version: 8, 
      onCreate: _createTables,
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 4) {
          await _createLegacyTables(db);
        }
        if (oldVersion < 5) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS vault_metadata (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              config_key TEXT UNIQUE,
              config_value TEXT
            )
          ''');
        }
        if (oldVersion < 6) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS notes (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              title TEXT NOT NULL,
              content_text TEXT NOT NULL, -- Renamed from content_json for clarity
              last_modified TEXT NOT NULL
            )
          ''');
        }
        if (oldVersion < 7) {
          // 1. Create the table with the FINAL intended schema
          await db.execute('''
            CREATE TABLE IF NOT EXISTS practice_bank (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              question TEXT NOT NULL,
              answer TEXT NOT NULL,
              category TEXT,
              type TEXT DEFAULT 'Flashcard',
              options TEXT,
              last_reviewed TEXT,
              last_modified TEXT
            )
          ''');

          // 2. Safety check: If the table existed but was missing 'type' or 'options'
          // this adds them. Since you're the only user, this covers all bases.
          try {
            await db.execute("ALTER TABLE practice_bank ADD COLUMN type TEXT DEFAULT 'Flashcard'");
          } catch (e) { /* Column already exists */ }
          
          try {
            await db.execute("ALTER TABLE practice_bank ADD COLUMN options TEXT");
          } catch (e) { /* Column already exists */ }
        }

        if (oldVersion < 8) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS note_versions (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              note_id INTEGER,
              title TEXT,
              content_text TEXT,
              version_timestamp TEXT,
              FOREIGN KEY (note_id) REFERENCES notes (id) ON DELETE CASCADE
            )
          ''');
        }
      },
    );
  }

  /// RELATIONAL SCHEMA INITIALIZATION 
  Future<void> _createTables(Database db, int version) async {
    // 1. SITE FOLDERS: Centralized catalog for network data
    await db.execute('''
      CREATE TABLE IF NOT EXISTS site_folders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,       
        description TEXT          
      )
    ''');

    // 2. KNOWLEDGE BASE: Cheat Sheets, Scripts, and Guidelines
    await db.execute('''
      CREATE TABLE IF NOT EXISTS knowledge_base (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        folder_id INTEGER,
        title TEXT NOT NULL,
        content TEXT NOT NULL,
        type TEXT,
        is_favorite INTEGER DEFAULT 0,
        FOREIGN KEY (folder_id) REFERENCES site_folders (id) ON DELETE CASCADE
      )
    ''');

    // 3. ISSUES (Heuristic Troubleshooting Engine)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS issues (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        problem_summary TEXT NOT NULL, 
        issue_description TEXT,         
        solution_fix TEXT NOT NULL,    
        complexity_rank INTEGER,       
        frequency_count INTEGER DEFAULT 0, 
        last_occurrence TEXT
      )
    ''');

    // 4. INFRASTRUCTURE LEDGER: Categorized network data
    await db.execute('''
      CREATE TABLE IF NOT EXISTS network_ledger (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        site_id INTEGER,
        label TEXT NOT NULL,      
        data_json TEXT NOT NULL,
        FOREIGN KEY (site_id) REFERENCES site_folders (id) ON DELETE CASCADE
      )
    ''');

    // 5. GO-BAG LOGISTICS: Tracker for enterprise assets
    await db.execute('''
      CREATE TABLE IF NOT EXISTS go_bag_tools (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        category TEXT,
        description TEXT,
        photo_path TEXT,
        serial_number TEXT,
        warranty_expiry TEXT,
        is_ready INTEGER DEFAULT 0,
        last_maintained TEXT
      )
    ''');

    // 6. PASSWORDS: Secure credential storage
    await db.execute('''
      CREATE TABLE IF NOT EXISTS passwords (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        account_name TEXT,
        username TEXT,
        email TEXT,
        encrypted_password TEXT
      )
    ''');

    // 7. VAULT METADATA: Stores Salt and Auth Check for portable encryption
    await db.execute('''
      CREATE TABLE IF NOT EXISTS vault_metadata (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        config_key TEXT UNIQUE,
        config_value TEXT
      )
    ''');

    // 8. LECTURE NOTES
    await db.execute('''
      CREATE TABLE IF NOT EXISTS notes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        content_text TEXT NOT NULL,
        last_modified TEXT NOT NULL
      )
    ''');
    // 9. PRACTICE ENGINE (Flashcards & Exam Bank)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS practice_bank (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        question TEXT NOT NULL,
        answer TEXT NOT NULL,
        category TEXT, 
        type TEXT DEFAULT 'Flashcard', -- 'Flashcard', 'MultipleChoice', 'TrueFalse'
        options TEXT, -- JSON string for Multiple Choice options
        last_modified TEXT 
      )
    ''');

    // 10. NOTE VERSIONS (Snapshots for rollback)
      await db.execute('''
        CREATE TABLE IF NOT EXISTS note_versions (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          note_id INTEGER,
          title TEXT,
          content_text TEXT,
          version_timestamp TEXT,
          FOREIGN KEY (note_id) REFERENCES notes (id) ON DELETE CASCADE
        )
      ''');
  }

  Future<void> _createLegacyTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS passwords (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        account_name TEXT,
        username TEXT,
        email TEXT,
        encrypted_password TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS go_bag_tools (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        category TEXT,
        description TEXT,
        photo_path TEXT,
        serial_number TEXT,
        warranty_expiry TEXT,
        is_ready INTEGER DEFAULT 0,
        last_maintained TEXT
      )
    ''');
  }
}

class LedgerService {
  final dbService = DatabaseService();

  Future<void> createSite(String name, String description) async {
    final db = await dbService.database;
    await db.insert('site_folders', {
      'name': name,
      'description': description,
    });
  }

  Future<void> addNetworkRecord(int siteId, String label, Map<String, dynamic> config) async {
    final db = await dbService.database;
    
    String rawJson = jsonEncode(config);
    final masterKey = SecurityService.activeKey;
    String encryptedJson = await SecurityService.encryptData(rawJson, masterKey);

    await db.insert('network_ledger', {
      'site_id': siteId,
      'label': label,
      'data_json': encryptedJson,
    });
  }

  // --- NEW: UPDATE & DELETE CAPABILITIES ---

  /// Updates an existing VLAN or Network Record
  Future<void> updateNetworkRecord(int id, String label, Map<String, dynamic> config) async {
    final db = await dbService.database;
    
    // Convert new config to JSON and encrypt using the volatile master key
    String rawJson = jsonEncode(config);
    final masterKey = SecurityService.activeKey;
    String encryptedJson = await SecurityService.encryptData(rawJson, masterKey);

    await db.update(
      'network_ledger',
      {
        'label': label,
        'data_json': encryptedJson,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Removes a record permanently from the site ledger
  Future<void> deleteNetworkRecord(int id) async {
    final db = await dbService.database;
    await db.delete(
      'network_ledger',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}

class NoteService {
  final dbService = DatabaseService();

  Future<String> _persistNoteImages(String contentJson) async {
    try {
      if (!contentJson.trim().startsWith('[')) return contentJson;

      List<dynamic> blocks = jsonDecode(contentJson);
      final appDocDir = await getApplicationDocumentsDirectory();
      final assetDir = Directory(join(appDocDir.path, 'app_assets'));
      
      if (!await assetDir.exists()) await assetDir.create(recursive: true);

      for (var block in blocks) {
        if (block['type'] == 'image') {
          String path = block['content'];
          
          // Only copy if the image is NOT already in app_assets
          if (!path.contains('app_assets')) {
            File originalFile = File(path);
            if (await originalFile.exists()) {
              String fileName = "note_${DateTime.now().millisecondsSinceEpoch}_${basename(path)}";
              String newPath = join(assetDir.path, fileName);
              
              await originalFile.copy(newPath);
              // Update block content to the new persistent path
              block['content'] = newPath;
            }
          }
        }
      }
      return jsonEncode(blocks);
    } catch (e) {
      return contentJson; // Fallback to original if something fails
    }
  }

  /// Logic to extract human-readable text from JSON blocks for UI previews
  String getPlainTextPreview(String contentText) {
    try {
      // Check if the content is actually a JSON list (starts with '[')
      if (!contentText.trim().startsWith('[')) return contentText; 
      
      List<dynamic> blocks = jsonDecode(contentText);
      String preview = "";
      for (var block in blocks) {
        if (block['type'] == 'text') {
          preview += "${block['content']} ";
        }
      }
      return preview.trim();
    } catch (e) {
      // If decoding fails, return the original text as a fallback
      return contentText;
    }
  }

  Future<int> saveNote(String title, String contentJson) async {
    final db = await dbService.database;
    String persistentJson = await _persistNoteImages(contentJson);
    
    // ENCRYPT BEFORE SAVING
    final masterKey = SecurityService.activeKey;
    String encryptedData = await SecurityService.encryptData(persistentJson, masterKey);
    
    return await db.insert('notes', {
      'title': title,
      'content_text': encryptedData, // Save the ciphertext
      'last_modified': DateTime.now().toIso8601String(),
    });
  }

  /// Fetches all notes and pre-processes the preview text for the UI
  Future<List<Map<String, dynamic>>> getAllNotes() async {
    final db = await dbService.database;
    final List<Map<String, dynamic>> maps = await db.query('notes', orderBy: 'last_modified DESC');
    final masterKey = SecurityService.activeKey; // Get the session key

    return await Future.wait(List.generate(maps.length, (i) async {
      var note = Map<String, dynamic>.from(maps[i]);
      
      try {
        // DECRYPT HERE: Unlock the content so the preview logic can see the JSON
        String decrypted = await SecurityService.decryptData(note['content_text'] as String, masterKey);
        
        note['preview_text'] = getPlainTextPreview(decrypted);
        note['content_text'] = decrypted; // Replace ciphertext with plaintext for the UI
      } catch (e) {
        note['preview_text'] = "[Locked/Encrypted]";
      }
      
      return note;
    }));
  }

  Future<void> _createVersion(int noteId, String title, String content) async {
    final db = await dbService.database;
    await db.insert('note_versions', {
      'note_id': noteId,
      'title': title,
      'content_text': content,
      'version_timestamp': DateTime.now().toIso8601String(),
    });
    
    // Optional: Keep only the last 10 versions to save space
    await db.execute('''
      DELETE FROM note_versions WHERE id IN (
        SELECT id FROM note_versions WHERE note_id = ? 
        ORDER BY version_timestamp DESC LIMIT -1 OFFSET 10
      )
    ''', [noteId]);
  }

  Future<int> updateNote(int id, String title, String contentText) async {
    final db = await dbService.database;
    final masterKey = SecurityService.activeKey;

    // 1. Snapshot current state (it's already encrypted in DB, so this is fine)
    final currentNote = await db.query('notes', where: 'id = ?', whereArgs: [id]);
    if (currentNote.isNotEmpty) {
      await _createVersion(
        id, 
        currentNote.first['title'] as String, 
        currentNote.first['content_text'] as String // Already encrypted
      );
    }

    // 2. Persist images
    String persistentJson = await _persistNoteImages(contentText);

    // 3. ENCRYPT BEFORE UPDATING
    String encryptedUpdate = await SecurityService.encryptData(persistentJson, masterKey);

    return await db.update(
      'notes',
      {
        'title': title,
        'content_text': encryptedUpdate, // Save ciphertext
        'last_modified': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Map<String, dynamic>>> getNoteVersions(int noteId) async {
    try {
      final db = await dbService.database;
      final maps = await db.query('note_versions', where: 'note_id = ?', whereArgs: [noteId], orderBy: 'version_timestamp DESC');
      final masterKey = SecurityService.activeKey;

      return await Future.wait(maps.map((row) async {
        var version = Map<String, dynamic>.from(row);
        try {
          version['content_text'] = await SecurityService.decryptData(row['content_text'] as String, masterKey);
        } catch (e) {
          version['content_text'] = "[Encryption Error]";
        }
        return version;
      }));
    } catch (e) {
      return [];
    }
  }

  /// NEW: Physical file cleanup to prevent storage bloat
  Future<void> _deletePhysicalNoteImages(String contentJson) async {
    try {
      if (!contentJson.trim().startsWith('[')) return;

      List<dynamic> blocks = jsonDecode(contentJson);
      for (var block in blocks) {
        if (block['type'] == 'image') {
          final file = File(block['content']);
          // Only delete if it exists and is within our managed app_assets folder
          if (await file.exists() && block['content'].contains('app_assets')) {
            await file.delete();
          }
        }
      }
    } catch (e) {
      debugPrint("Cleanup failed: $e");
    }
  }

  /// NEW: Cleans up orphaned versions when a note is purged
  Future<void> _clearAllVersions(int noteId) async {
    final db = await dbService.database;
    // Get all versions to find their images before deleting the records
    final versions = await getNoteVersions(noteId);
    for (var v in versions) {
      await _deletePhysicalNoteImages(v['content_text']);
    }
    // Delete the database records
    await db.delete('note_versions', where: 'note_id = ?', whereArgs: [noteId]);
  }

  Future<int> deleteNote(int id) async {
    final db = await dbService.database;

    // 1. Find the current note
    final currentNote = await db.query('notes', where: 'id = ?', whereArgs: [id]);
    
    if (currentNote.isNotEmpty) {
      // 2. DECRYPT the content so we can find the image paths for deletion
      final masterKey = SecurityService.activeKey;
      try {
        final String encryptedContent = currentNote.first['content_text'] as String;
        final String decryptedContent = await SecurityService.decryptData(encryptedContent, masterKey);
        
        // 3. Delete images associated with the current version
        await _deletePhysicalNoteImages(decryptedContent);
      } catch (e) {
        debugPrint("Cleanup: Could not decrypt note for image deletion: $e");
      }
      
      // 4. Delete all history snapshots (Your _clearAllVersions already handles decryption now)
      await _clearAllVersions(id);
    }

    // 5. Finally, remove the record
    return await db.delete('notes', where: 'id = ?', whereArgs: [id]);
  }
}

class PracticeService {
  final dbService = DatabaseService();

  // THE SESSION CACHE: Keeps decrypted cards in RAM for smooth UI performance
  List<Map<String, dynamic>> _sessionCache = [];
  String? _lastSubject;

  /// Clears the decrypted cache. Call this when exiting the Study screen.
  void clearCache() {
    _sessionCache = [];
    _lastSubject = null;
  }

  Future<int> saveCard(String q, String a, String cat, {String type = 'Flashcard', String options = ''}) async {
    final db = await dbService.database;
    final masterKey = SecurityService.activeKey;

    // Encrypt sensitive fields before storage
    String encryptedQ = await SecurityService.encryptData(q, masterKey);
    String encryptedA = await SecurityService.encryptData(a, masterKey);

    clearCache(); // Invalidate cache since data changed
    return await db.insert('practice_bank', {
      'question': encryptedQ,
      'answer': encryptedA,
      'category': cat, 
      'type': type,
      'options': options,
      'last_modified': DateTime.now().toIso8601String(),
    });
  }

  Future<int> updateCard(int id, String q, String a, String cat, {required String type, String options = ''}) async {
    final db = await dbService.database;
    final masterKey = SecurityService.activeKey;

    // FIX: Encrypt the updated data or migration will fail later
    String encryptedQ = await SecurityService.encryptData(q, masterKey);
    String encryptedA = await SecurityService.encryptData(a, masterKey);

    clearCache(); // Invalidate cache
    return await db.update(
      'practice_bank',
      {
        'question': encryptedQ,
        'answer': encryptedA,
        'category': cat,
        'type': type,
        'options': options,
        'last_modified': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> renameSubject(String oldName, String newName) async {
    final db = await dbService.database;
    clearCache();
    return await db.update(
      'practice_bank',
      {'category': newName},
      where: 'category = ?',
      whereArgs: [oldName],
    );
  }

  Future<int> deleteSubject(String subject) async {
    final db = await dbService.database;
    clearCache();
    return await db.delete(
      'practice_bank',
      where: 'category = ?',
      whereArgs: [subject],
    );
  }

  Future<List<String>> getUniqueSubjects() async {
    final db = await dbService.database;
    final List<Map<String, dynamic>> maps = await db.rawQuery('SELECT DISTINCT category FROM practice_bank');
    return maps.map((row) => row['category'] as String).toList();
  }

  Future<List<Map<String, dynamic>>> getFlashcards({String? subject}) async {
    // 1. Performance Check: Return cache if subject hasn't changed
    if (_sessionCache.isNotEmpty && _lastSubject == subject) {
      return _sessionCache;
    }

    final db = await dbService.database;
    List<Map<String, dynamic>> maps;

    if (subject == null || subject == 'All') {
      maps = await db.query('practice_bank');
    } else {
      maps = await db.query('practice_bank', where: 'category = ?', whereArgs: [subject]);
    }

    final masterKey = SecurityService.activeKey;

    // 2. Heavy Lifting: Decrypt all cards in the category once
    _sessionCache = await Future.wait(maps.map((row) async {
      var card = Map<String, dynamic>.from(row);
      try {
        card['question'] = await SecurityService.decryptData(row['question'] as String, masterKey);
        card['answer'] = await SecurityService.decryptData(row['answer'] as String, masterKey);
      } catch (e) {
        card['question'] = "[Decryption Error]";
        card['answer'] = "Could not unlock this card.";
      }
      return card;
    }));

    _lastSubject = subject;
    return _sessionCache;
  }

  Future<int> deleteCard(int id) async {
    final db = await dbService.database;
    clearCache();
    return await db.delete('practice_bank', where: 'id = ?', whereArgs: [id]);
  }
}