import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:convert';
import 'security_service.dart';

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
      version: 7, 
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
          await db.execute('''
            CREATE TABLE IF NOT EXISTS practice_bank (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              question TEXT NOT NULL,
              answer TEXT NOT NULL,
              category TEXT,
              last_reviewed TEXT,
              last_modified TEXT -- Added to match your saveCard logic
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
        last_reviewed TEXT,
        last_modified TEXT -- Add this line
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

  Future<int> saveNote(String title, String contentText) async {
    final db = await dbService.database;
    return await db.insert('notes', {
      'title': title,
      'content_text': contentText,
      'last_modified': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> getAllNotes() async {
    final db = await dbService.database;
    return await db.query('notes', orderBy: 'last_modified DESC');
  }

  Future<int> updateNote(int id, String title, String contentText) async {
    final db = await dbService.database;
    return await db.update(
      'notes',
      {
        'title': title,
        'content_text': contentText,
        'last_modified': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteNote(int id) async {
    final db = await dbService.database;
    return await db.delete('notes', where: 'id = ?', whereArgs: [id]);
  }
}

class PracticeService {
  final dbService = DatabaseService();

  Future<int> saveCard(String q, String a, String cat) async {
    final db = await dbService.database;
    return await db.insert('practice_bank', {
      'question': q,
      'answer': a,
      'category': cat, // Stores the user-defined subject
      'last_modified': DateTime.now().toIso8601String(),
    });
  }

  Future<List<String>> getUniqueSubjects() async {
    final db = await dbService.database;
    final List<Map<String, dynamic>> maps = await db.rawQuery('SELECT DISTINCT category FROM practice_bank');
    return maps.map((row) => row['category'] as String).toList();
  }

  Future<List<Map<String, dynamic>>> getFlashcards({String? subject}) async {
    final db = await dbService.database;
    if (subject == null || subject == 'All') {
      return await db.query('practice_bank');
    }
    return await db.query('practice_bank', where: 'category = ?', whereArgs: [subject]);
  }

  Future<int> deleteCard(int id) async {
    final db = await dbService.database;
    return await db.delete('practice_bank', where: 'id = ?', whereArgs: [id]);
  }
}