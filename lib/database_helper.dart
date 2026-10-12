import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'models/folder.dart';
import 'models/card_record.dart';

class DatabaseHelper {
  static const _databaseName = "MyDatabase.db";
  static const _databaseVersion = 2;

  // Part I table and columns
  static const table = 'my_table';
  static const columnId = '_id';
  static const columnName = 'name';
  static const columnAge = 'age';

  // Part II tables
  static const tableFolders = 'folders';
  static const tableCards = 'cards';

  late Database _db;

  Database get database => _db;

  // Opens the database, enforces foreign keys, and handles migrations
  Future<void> init() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final path = join(documentsDirectory.path, _databaseName);
    _db = await openDatabase(
      path,
      version: _databaseVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  // Fresh database creation (Version 2)
  Future<void> _onCreate(Database db, int version) async {
    await _createPartOneTables(db);
    await _createCatalogueTables(db);
  }

  // Version-gated schema upgrade
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _createCatalogueTables(db);
    }
  }

  // Create Part I guest table
  Future<void> _createPartOneTables(Database db) async {
    await db.execute('''
CREATE TABLE $table (
  $columnId INTEGER PRIMARY KEY,
  $columnName TEXT NOT NULL,
  $columnAge INTEGER NOT NULL
)
''');
  }

  // Create Part II folders, cards tables, and index
  Future<void> _createCatalogueTables(Database db) async {
    await db.execute('''
CREATE TABLE $tableFolders (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL UNIQUE,
  created_at TEXT NOT NULL
)
''');

    await db.execute('''
CREATE TABLE $tableCards (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  title TEXT NOT NULL,
  suit TEXT NOT NULL,
  notes TEXT NOT NULL DEFAULT '',
  image_ref TEXT,
  folder_id INTEGER NOT NULL,
  FOREIGN KEY (folder_id) REFERENCES $tableFolders(id) ON DELETE CASCADE
)
''');

    await db.execute(
      'CREATE INDEX idx_cards_folder_id ON $tableCards(folder_id)',
    );
  }

  // ==========================================
  // Part I Helper Methods (Preserved intact)
  // ==========================================

  Future<int> insert(Map<String, dynamic> row) async {
    return await _db.insert(table, row);
  }

  Future<List<Map<String, dynamic>>> queryAllRows() async {
    return await _db.query(table, orderBy: '$columnId ASC');
  }

  Future<int> queryRowCount() async {
    final results = await _db.rawQuery('SELECT COUNT(*) FROM $table');
    return Sqflite.firstIntValue(results) ?? 0;
  }

  Future<int> update(Map<String, dynamic> row) async {
    int id = row[columnId];
    return await _db.update(
      table,
      row,
      where: '$columnId = ?',
      whereArgs: [id],
    );
  }

  Future<int> delete(int id) async {
    return await _db.delete(
      table,
      where: '$columnId = ?',
      whereArgs: [id],
    );
  }

  // ==========================================
  // Part II Catalogue Helper Methods
  // ==========================================

  /// Inserts a new folder. Throws DatabaseException on unique constraint violation.
  Future<int> insertFolder(Folder folder) async {
    return await _db.insert(
      tableFolders,
      folder.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  /// Queries all folders with their child card counts using LEFT JOIN
  Future<List<Folder>> getFoldersWithCounts() async {
    final results = await _db.rawQuery('''
SELECT f.id, f.name, f.created_at, COUNT(c.id) AS card_count
FROM $tableFolders f
LEFT JOIN $tableCards c ON f.id = c.folder_id
GROUP BY f.id
ORDER BY f.id ASC
''');
    return results.map((row) => Folder.fromMap(row)).toList();
  }

  /// Queries a single folder by ID
  Future<Folder?> getFolderById(int id) async {
    final results = await _db.rawQuery('''
SELECT f.id, f.name, f.created_at, COUNT(c.id) AS card_count
FROM $tableFolders f
LEFT JOIN $tableCards c ON f.id = c.folder_id
WHERE f.id = ?
GROUP BY f.id
''', [id]);
    if (results.isEmpty) return null;
    return Folder.fromMap(results.first);
  }

  /// Deletes a folder by ID (cascades to all cards in this folder)
  Future<int> deleteFolder(int id) async {
    return await _db.delete(
      tableFolders,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Inserts a new card into a folder
  Future<int> insertCard(CardRecord card) async {
    return await _db.insert(tableCards, card.toMap());
  }

  /// Queries all cards belonging to a folder, ordered case-insensitively by title
  Future<List<CardRecord>> getCards(int folderId) async {
    final results = await _db.query(
      tableCards,
      where: 'folder_id = ?',
      whereArgs: [folderId],
      orderBy: 'title COLLATE NOCASE ASC',
    );
    return results.map((row) => CardRecord.fromMap(row)).toList();
  }

  /// Queries a card by ID
  Future<CardRecord?> getCardById(int id) async {
    final results = await _db.query(
      tableCards,
      where: 'id = ?',
      whereArgs: [id],
    );
    if (results.isEmpty) return null;
    return CardRecord.fromMap(results.first);
  }

  /// Updates a card by ID. Returns affected rows count.
  Future<int> updateCard(CardRecord card) async {
    return await _db.update(
      tableCards,
      card.toMap(),
      where: 'id = ?',
      whereArgs: [card.id],
    );
  }

  /// Deletes a card by ID. Returns affected rows count.
  Future<int> deleteCard(int id) async {
    return await _db.delete(
      tableCards,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Counts cards belonging to a specific folder ID
  Future<int> queryCardCountForFolder(int folderId) async {
    final results = await _db.rawQuery(
      'SELECT COUNT(*) FROM $tableCards WHERE folder_id = ?',
      [folderId],
    );
    return Sqflite.firstIntValue(results) ?? 0;
  }

  /// Counts total cards across all folders
  Future<int> queryTotalCardsCount() async {
    final results = await _db.rawQuery('SELECT COUNT(*) FROM $tableCards');
    return Sqflite.firstIntValue(results) ?? 0;
  }

  // ==========================================
  // Diagnostics & PRAGMA Verification
  // ==========================================

  Future<int> getPragmaUserVersion() async {
    final res = await _db.rawQuery('PRAGMA user_version');
    return Sqflite.firstIntValue(res) ?? 0;
  }

  Future<int> getPragmaForeignKeys() async {
    final res = await _db.rawQuery('PRAGMA foreign_keys');
    return Sqflite.firstIntValue(res) ?? 0;
  }

  Future<List<Map<String, dynamic>>> getPragmaForeignKeyList() async {
    return await _db.rawQuery('PRAGMA foreign_key_list($tableCards)');
  }

  Future<List<Map<String, dynamic>>> getPragmaIndexList() async {
    return await _db.rawQuery('PRAGMA index_list($tableCards)');
  }
}
