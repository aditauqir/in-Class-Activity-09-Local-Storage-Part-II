import 'package:flutter/material.dart';
import 'database_helper.dart';
import 'models/folder.dart';
import 'models/card_record.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final helper = DatabaseHelper();
  try {
    await helper.init();
  } catch (error, stackTrace) {
    debugPrint('Database initialization failed: $error\n$stackTrace');
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Text(
                'Could not open local storage.\nError: $error\nRestart the app and check the logs.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
    return;
  }
  runApp(CatalogueApp(helper: helper));
}

class CatalogueApp extends StatelessWidget {
  final DatabaseHelper helper;

  const CatalogueApp({super.key, required this.helper});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Card Catalogue & Local Storage',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFBA5416),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: MainShellScreen(helper: helper),
    );
  }
}

class MainShellScreen extends StatefulWidget {
  final DatabaseHelper helper;

  const MainShellScreen({super.key, required this.helper});

  @override
  State<MainShellScreen> createState() => _MainShellScreenState();
}

class _MainShellScreenState extends State<MainShellScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final screens = [
      FoldersScreen(helper: widget.helper),
      PartOneRosterScreen(helper: widget.helper),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.folder_outlined),
            selectedIcon: Icon(Icons.folder),
            label: 'Card Folders',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'Part I Roster',
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// PART II: FOLDERS SCREEN
// ============================================================================

class FoldersScreen extends StatefulWidget {
  final DatabaseHelper helper;

  const FoldersScreen({super.key, required this.helper});

  @override
  State<FoldersScreen> createState() => _FoldersScreenState();
}

class _FoldersScreenState extends State<FoldersScreen> {
  List<Folder> _folders = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadFolders();
  }

  Future<void> _loadFolders() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final folders = await widget.helper.getFoldersWithCounts();
      if (!mounted) return;
      setState(() {
        _folders = folders;
        _isLoading = false;
      });
    } catch (e, stack) {
      debugPrint('Error loading folders: $e\n$stack');
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Failed to load folders: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _showAddFolderDialog() async {
    final messenger = ScaffoldMessenger.of(context);
    final nameController = TextEditingController();
    String? localError;
    bool isSaving = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Create New Folder'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameController,
                    autofocus: true,
                    enabled: !isSaving,
                    decoration: InputDecoration(
                      labelText: 'Folder Name',
                      hintText: 'e.g. Atlas, Harbor',
                      errorText: localError,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  if (isSaving)
                    const Padding(
                      padding: EdgeInsets.only(top: 12.0),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.pop(dialogCtx),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          final trimmed = nameController.text.trim();
                          if (trimmed.isEmpty) {
                            setDialogState(() {
                              localError = 'Folder name cannot be blank';
                            });
                            return;
                          }

                          setDialogState(() {
                            isSaving = true;
                            localError = null;
                          });

                          try {
                            final folder = Folder(
                              name: trimmed,
                              createdAt: DateTime.now(),
                            );
                            final insertedId =
                                await widget.helper.insertFolder(folder);
                            if (!dialogCtx.mounted) return;
                            Navigator.pop(dialogCtx);
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(
                                    'Created folder "$trimmed" (ID: $insertedId)'),
                                backgroundColor: Colors.green.shade800,
                              ),
                            );
                            _loadFolders();
                          } catch (e) {
                            debugPrint('Folder create error: $e');
                            setDialogState(() {
                              isSaving = false;
                              if (e.toString().contains('UNIQUE') ||
                                  e.toString().contains('unique')) {
                                localError =
                                    'A folder named "$trimmed" already exists.';
                              } else {
                                localError = 'Save error: $e';
                              }
                            });
                          }
                        },
                  child: const Text('Create'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _confirmDeleteFolder(Folder folder) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          title: Text('Delete "${folder.name}"?'),
          content: Text(
            'Deleting this folder will permanently delete all ${folder.cardCount} associated card(s) via ON DELETE CASCADE.\n\nThis action cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
              onPressed: () => Navigator.pop(dialogCtx, true),
              child: const Text('Confirm Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed == true && mounted) {
      try {
        final affected = await widget.helper.deleteFolder(folder.id!);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Deleted folder "${folder.name}" (Affected parent rows: $affected)'),
            backgroundColor: Colors.brown.shade800,
          ),
        );
        _loadFolders();
      } catch (e) {
        debugPrint('Delete folder error: $e');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete folder: $e'),
            backgroundColor: Colors.red.shade900,
          ),
        );
      }
    }
  }

  void _showDiagnostics() async {
    final userVer = await widget.helper.getPragmaUserVersion();
    final fk = await widget.helper.getPragmaForeignKeys();
    final fkList = await widget.helper.getPragmaForeignKeyList();
    final idxList = await widget.helper.getPragmaIndexList();
    final guestCount = await widget.helper.queryRowCount();
    final totalCards = await widget.helper.queryTotalCardsCount();

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('SQLite Diagnostics (PRAGMA)'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('PRAGMA user_version: $userVer (Target: 2)'),
              const SizedBox(height: 6),
              Text('PRAGMA foreign_keys: $fk (1 = Enabled)'),
              const SizedBox(height: 6),
              Text('Part I guest rows in my_table: $guestCount'),
              const SizedBox(height: 6),
              Text('Total card rows in cards: $totalCards'),
              const Divider(height: 18),
              const Text('Foreign key configuration (cards):',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              Text(fkList.isEmpty
                  ? 'No FK defined'
                  : fkList.map((e) => e.toString()).join('\n')),
              const Divider(height: 18),
              const Text('Index list (cards):',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              Text(idxList.isEmpty
                  ? 'No indexes'
                  : idxList.map((e) => e.toString()).join('\n')),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Card Catalogue'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.analytics_outlined),
            tooltip: 'Inspect PRAGMA diagnostics',
            onPressed: _showDiagnostics,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh folders',
            onPressed: _loadFolders,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline,
                            size: 48, color: Colors.red),
                        const SizedBox(height: 12),
                        Text(_errorMessage!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _loadFolders,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : _folders.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.folder_open,
                                size: 64, color: Colors.grey.shade400),
                            const SizedBox(height: 16),
                            const Text(
                              'No folders yet',
                              style: TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Create a folder like "Atlas" or "Harbor" to organize your cards.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey),
                            ),
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: _showAddFolderDialog,
                              icon: const Icon(Icons.create_new_folder),
                              label: const Text('Create First Folder'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadFolders,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _folders.length,
                        itemBuilder: (context, index) {
                          final folder = _folders[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 6),
                            elevation: 1.5,
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: Theme.of(context)
                                    .colorScheme
                                    .primaryContainer,
                                child: Text(
                                  '#${folder.id}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onPrimaryContainer,
                                  ),
                                ),
                              ),
                              title: Text(
                                folder.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 17),
                              ),
                              subtitle: Text(
                                '${folder.cardCount} card${folder.cardCount == 1 ? '' : 's'} • Created ${folder.createdAt.toLocal().toString().split('.').first}',
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline,
                                        color: Colors.red),
                                    tooltip: 'Delete folder',
                                    onPressed: () =>
                                        _confirmDeleteFolder(folder),
                                  ),
                                  const Icon(Icons.chevron_right),
                                ],
                              ),
                              onTap: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => FolderCardsScreen(
                                      helper: widget.helper,
                                      folder: folder,
                                    ),
                                  ),
                                );
                                _loadFolders();
                              },
                            ),
                          );
                        },
                      ),
                    ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddFolderDialog,
        icon: const Icon(Icons.create_new_folder),
        label: const Text('New Folder'),
      ),
    );
  }
}

// ============================================================================
// PART II: CARDS IN FOLDER SCREEN
// ============================================================================

class FolderCardsScreen extends StatefulWidget {
  final DatabaseHelper helper;
  final Folder folder;

  const FolderCardsScreen({
    super.key,
    required this.helper,
    required this.folder,
  });

  @override
  State<FolderCardsScreen> createState() => _FolderCardsScreenState();
}

class _FolderCardsScreenState extends State<FolderCardsScreen> {
  List<CardRecord> _cards = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadCards();
  }

  Future<void> _loadCards() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final cards = await widget.helper.getCards(widget.folder.id!);
      if (!mounted) return;
      setState(() {
        _cards = cards;
        _isLoading = false;
      });
    } catch (e, stack) {
      debugPrint('Error loading cards: $e\n$stack');
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Failed to load cards: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _openCardForm({CardRecord? existingCard}) async {
    final messenger = ScaffoldMessenger.of(context);
    final titleController =
        TextEditingController(text: existingCard?.title ?? '');
    final notesController =
        TextEditingController(text: existingCard?.notes ?? '');
    final imageRefController =
        TextEditingController(text: existingCard?.imageRef ?? '');
    String selectedSuit = existingCard?.suit ?? 'Spades';

    String? localError;
    bool isSaving = false;
    final isEditing = existingCard != null;

    final suits = const ['Spades', 'Hearts', 'Diamonds', 'Clubs'];

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(isEditing
                  ? 'Edit Card #${existingCard.id}'
                  : 'Add Card to ${widget.folder.name}'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: titleController,
                      autofocus: !isEditing,
                      enabled: !isSaving,
                      decoration: InputDecoration(
                        labelText: 'Card Title *',
                        hintText: 'e.g. Compass, Signal',
                        errorText: localError,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      initialValue: selectedSuit,
                      decoration: const InputDecoration(
                        labelText: 'Card Suit *',
                        border: OutlineInputBorder(),
                      ),
                      items: suits.map((suit) {
                        return DropdownMenuItem(
                          value: suit,
                          child: Row(
                            children: [
                              _buildSuitBadge(suit, mini: true),
                              const SizedBox(width: 8),
                              Text(suit),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: isSaving
                          ? null
                          : (value) {
                              if (value != null) {
                                setDialogState(() {
                                  selectedSuit = value;
                                });
                              }
                            },
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: notesController,
                      enabled: !isSaving,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Notes (optional)',
                        hintText: 'e.g. Calibrated magnetic bearing',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: imageRefController,
                      enabled: !isSaving,
                      decoration: const InputDecoration(
                        labelText: 'Image Ref (URL or asset path, optional)',
                        hintText: 'Leave empty for null (suit fallback)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    if (isSaving)
                      const Padding(
                        padding: EdgeInsets.only(top: 14.0),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.pop(dialogCtx),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          final trimmedTitle = titleController.text.trim();
                          if (trimmedTitle.isEmpty) {
                            setDialogState(() {
                              localError = 'Card title cannot be empty';
                            });
                            return;
                          }

                          setDialogState(() {
                            isSaving = true;
                            localError = null;
                          });

                          final trimmedNotes = notesController.text.trim();
                          final trimmedImage =
                              imageRefController.text.trim();
                          final String? finalImageRef =
                              trimmedImage.isEmpty ? null : trimmedImage;

                          try {
                            if (isEditing) {
                              final updatedCard = CardRecord(
                                id: existingCard.id,
                                title: trimmedTitle,
                                suit: selectedSuit,
                                notes: trimmedNotes,
                                imageRef: finalImageRef,
                                folderId: existingCard.folderId,
                              );
                              final affected =
                                  await widget.helper.updateCard(updatedCard);
                              if (!dialogCtx.mounted) return;
                              Navigator.pop(dialogCtx);
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text(
                                      'Updated card #${existingCard.id} (Affected rows: $affected)'),
                                  backgroundColor: Colors.green.shade800,
                                ),
                              );
                            } else {
                              final newCard = CardRecord(
                                title: trimmedTitle,
                                suit: selectedSuit,
                                notes: trimmedNotes,
                                imageRef: finalImageRef,
                                folderId: widget.folder.id!,
                              );
                              final insertedId =
                                  await widget.helper.insertCard(newCard);
                              if (!dialogCtx.mounted) return;
                              Navigator.pop(dialogCtx);
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text(
                                      'Added card "$trimmedTitle" (ID: $insertedId)'),
                                  backgroundColor: Colors.green.shade800,
                                ),
                              );
                            }
                            _loadCards();
                          } catch (e) {
                            debugPrint('Save card error: $e');
                            setDialogState(() {
                              isSaving = false;
                              localError = 'Error saving card: $e';
                            });
                          }
                        },
                  child: Text(isEditing ? 'Save Changes' : 'Add Card'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _confirmDeleteCard(CardRecord card) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          title: Text('Delete "${card.title}"?'),
          content: Text(
            'Are you sure you want to delete card #${card.id} ("${card.title}")?\n\nThis will permanently remove this record from SQLite.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
              onPressed: () => Navigator.pop(dialogCtx, true),
              child: const Text('Confirm Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed == true && mounted) {
      try {
        final affected = await widget.helper.deleteCard(card.id!);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Deleted card "${card.title}" (Affected rows: $affected)'),
            backgroundColor: Colors.brown.shade800,
          ),
        );
        _loadCards();
      } catch (e) {
        debugPrint('Delete card error: $e');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete card: $e'),
            backgroundColor: Colors.red.shade900,
          ),
        );
      }
    }
  }

  static Widget _buildSuitBadge(String suit, {bool mini = false}) {
    IconData icon;
    Color color;

    switch (suit.toLowerCase()) {
      case 'hearts':
        icon = Icons.favorite;
        color = Colors.red.shade700;
        break;
      case 'diamonds':
        icon = Icons.diamond;
        color = Colors.red.shade700;
        break;
      case 'clubs':
        icon = Icons.cruelty_free; // Or clover
        color = Colors.black87;
        break;
      case 'spades':
      default:
        icon = Icons.shield;
        color = Colors.black87;
        break;
    }

    if (mini) {
      return Icon(icon, color: color, size: 20);
    }

    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Center(
        child: Icon(icon, color: color, size: 28),
      ),
    );
  }

  Widget _buildCardArtwork(CardRecord card) {
    if (card.imageRef != null && card.imageRef!.isNotEmpty) {
      if (card.imageRef!.startsWith('http://') ||
          card.imageRef!.startsWith('https://')) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            card.imageRef!,
            width: 48,
            height: 48,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) =>
                _buildSuitBadge(card.suit),
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return const SizedBox(
                width: 48,
                height: 48,
                child: Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              );
            },
          ),
        );
      } else if (card.imageRef!.startsWith('assets/')) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.asset(
            card.imageRef!,
            width: 48,
            height: 48,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) =>
                _buildSuitBadge(card.suit),
          ),
        );
      }
    }
    // Reliable suit-symbol fallback for null/empty/invalid references
    return _buildSuitBadge(card.suit);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.folder.name} (${_cards.length})'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh cards',
            onPressed: _loadCards,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline,
                            size: 48, color: Colors.red),
                        const SizedBox(height: 12),
                        Text(_errorMessage!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _loadCards,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : _cards.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.style_outlined,
                                size: 64, color: Colors.grey.shade400),
                            const SizedBox(height: 16),
                            const Text(
                              'No cards in this folder yet',
                              style: TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Tap the button below to add cards like "Compass" or "Signal".',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey),
                            ),
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: () => _openCardForm(),
                              icon: const Icon(Icons.add),
                              label: const Text('Add First Card'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadCards,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _cards.length,
                        itemBuilder: (context, index) {
                          final card = _cards[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 6),
                            elevation: 1.5,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 8, horizontal: 12),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  _buildCardArtwork(card),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              card.title,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 2),
                                              decoration: BoxDecoration(
                                                color: Colors.grey.shade200,
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                'ID: ${card.id}',
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Suit: ${card.suit}',
                                          style: TextStyle(
                                            color: Colors.grey.shade700,
                                            fontSize: 13,
                                          ),
                                        ),
                                        if (card.notes.isNotEmpty) ...[
                                          const SizedBox(height: 2),
                                          Text(
                                            'Notes: ${card.notes}',
                                            style: const TextStyle(
                                              fontSize: 13,
                                              fontStyle: FontStyle.italic,
                                            ),
                                          ),
                                        ],
                                        if (card.imageRef != null &&
                                            card.imageRef!.isNotEmpty) ...[
                                          const SizedBox(height: 2),
                                          Text(
                                            'Image: ${card.imageRef}',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.blueGrey.shade600,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.edit_outlined),
                                    tooltip: 'Edit card',
                                    onPressed: () =>
                                        _openCardForm(existingCard: card),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline,
                                        color: Colors.red),
                                    tooltip: 'Delete card',
                                    onPressed: () => _confirmDeleteCard(card),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openCardForm(),
        tooltip: 'Add Card',
        child: const Icon(Icons.add),
      ),
    );
  }
}

// ============================================================================
// PART I: FALL FESTIVAL ROSTER SCREEN (PRESERVED)
// ============================================================================

class PartOneRosterScreen extends StatefulWidget {
  final DatabaseHelper helper;

  const PartOneRosterScreen({super.key, required this.helper});

  @override
  State<PartOneRosterScreen> createState() => _PartOneRosterScreenState();
}

class _PartOneRosterScreenState extends State<PartOneRosterScreen> {
  final _nameController = TextEditingController();
  final _ageController = TextEditingController();

  List<Map<String, dynamic>> _guests = [];
  int _guestCount = 0;
  bool _isLoading = true;
  bool _isBusy = false;
  String? _readError;
  String? _statusMessage;
  bool _statusIsError = false;

  int? _selectedId;
  String? _nameError;
  String? _ageError;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _readError = null;
    });

    try {
      final rows = await widget.helper.queryAllRows();
      final count = await widget.helper.queryRowCount();

      if (!mounted) return;
      setState(() {
        _guests = rows;
        _guestCount = count;
        _isLoading = false;
      });
    } catch (e, stack) {
      debugPrint('Error loading Part I guests: $e\n$stack');
      if (!mounted) return;
      setState(() {
        _readError = 'Could not load guest list: $e';
        _isLoading = false;
      });
    }
  }

  void _startEdit(Map<String, dynamic> guest) {
    setState(() {
      _selectedId = guest[DatabaseHelper.columnId];
      _nameController.text = guest[DatabaseHelper.columnName];
      _ageController.text = guest[DatabaseHelper.columnAge].toString();
      _nameError = null;
      _ageError = null;
      _statusMessage = 'Editing Guest #$_selectedId';
      _statusIsError = false;
    });
  }

  void _cancelEdit() {
    setState(() {
      _selectedId = null;
      _nameController.clear();
      _ageController.clear();
      _nameError = null;
      _ageError = null;
      _statusMessage = 'Edit cancelled';
      _statusIsError = false;
    });
  }

  Future<void> _saveGuest() async {
    final rawName = _nameController.text.trim();
    final rawAge = _ageController.text.trim();

    String? nameErr;
    String? ageErr;

    if (rawName.isEmpty) {
      nameErr = 'Name cannot be blank';
    }

    final parsedAge = int.tryParse(rawAge);
    if (parsedAge == null) {
      ageErr = 'Age must be a valid whole number';
    } else if (parsedAge < 0 || parsedAge > 130) {
      ageErr = 'Age must be between 0 and 130 inclusive';
    }

    if (nameErr != null || ageErr != null) {
      setState(() {
        _nameError = nameErr;
        _ageError = ageErr;
        _statusMessage = 'Please correct the errors in the form';
        _statusIsError = true;
      });
      return;
    }

    setState(() {
      _isBusy = true;
      _nameError = null;
      _ageError = null;
      _statusMessage = null;
    });

    try {
      if (_selectedId != null) {
        final row = {
          DatabaseHelper.columnId: _selectedId,
          DatabaseHelper.columnName: rawName,
          DatabaseHelper.columnAge: parsedAge,
        };
        final affected = await widget.helper.update(row);
        if (!mounted) return;
        setState(() {
          _statusMessage =
              'Updated Guest #$_selectedId (Affected rows: $affected)';
          _statusIsError = false;
          _selectedId = null;
          _nameController.clear();
          _ageController.clear();
        });
      } else {
        final row = {
          DatabaseHelper.columnName: rawName,
          DatabaseHelper.columnAge: parsedAge,
        };
        final id = await widget.helper.insert(row);
        if (!mounted) return;
        setState(() {
          _statusMessage = 'Registered Guest #$id ($rawName, age $parsedAge)';
          _statusIsError = false;
          _nameController.clear();
          _ageController.clear();
        });
      }
      _loadData();
    } catch (e) {
      debugPrint('Save guest error: $e');
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Failed to save guest: $e';
        _statusIsError = true;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Future<void> _confirmDelete(Map<String, dynamic> guest) async {
    final id = guest[DatabaseHelper.columnId];
    final name = guest[DatabaseHelper.columnName];

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('Remove $name?'),
        content: Text('Are you sure you want to delete Guest #$id ($name)?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Confirm Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        final affected = await widget.helper.delete(id);
        if (!mounted) return;
        setState(() {
          _statusMessage = 'Deleted Guest #$id (Affected rows: $affected)';
          _statusIsError = false;
        });
        _loadData();
      } catch (e) {
        debugPrint('Delete guest error: $e');
        if (!mounted) return;
        setState(() {
          _statusMessage = 'Failed to delete guest: $e';
          _statusIsError = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fall Festival Roster (Part I)'),
        backgroundColor: const Color(0xFFFFCCBC),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh roster',
            onPressed: _loadData,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _selectedId != null
                          ? 'Edit Guest #$_selectedId'
                          : 'Register New Guest',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _nameController,
                      enabled: !_isBusy,
                      decoration: InputDecoration(
                        labelText: 'Guest Name',
                        prefixIcon: const Icon(Icons.person),
                        errorText: _nameError,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _ageController,
                      enabled: !_isBusy,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Age (0 - 130)',
                        prefixIcon: const Icon(Icons.cake),
                        errorText: _ageError,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        if (_selectedId != null) ...[
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _isBusy ? null : _cancelEdit,
                              child: const Text('Cancel Edit'),
                            ),
                          ),
                          const SizedBox(width: 12),
                        ],
                        Expanded(
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF8D4B32),
                            ),
                            onPressed: _isBusy ? null : _saveGuest,
                            icon: Icon(_selectedId != null
                                ? Icons.save
                                : Icons.person_add),
                            label: Text(_selectedId != null
                                ? 'Save Changes'
                                : 'Add Guest'),
                          ),
                        ),
                      ],
                    ),
                    if (_statusMessage != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _statusMessage!,
                        style: TextStyle(
                          color:
                              _statusIsError ? Colors.red.shade800 : Colors.green.shade800,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Festival Guests',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFE0B2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Total Guests: $_guestCount',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_readError != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(_readError!,
                      style: const TextStyle(color: Colors.red)),
                ),
              )
            else if (_guests.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No festival guests yet'),
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _guests.length,
                itemBuilder: (context, index) {
                  final guest = _guests[index];
                  final id = guest[DatabaseHelper.columnId];
                  final name = guest[DatabaseHelper.columnName];
                  final age = guest[DatabaseHelper.columnAge];
                  final isEditing = _selectedId == id;

                  return Card(
                    color: isEditing
                        ? const Color(0xFFFFECB3)
                        : const Color(0xFFFFF3E0),
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: const Color(0xFFFFCCBC),
                        child: Text(
                          '#$id',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF8D4B32),
                          ),
                        ),
                      ),
                      title: Text(
                        name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text('Age: $age • Database ID: $id'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            tooltip: 'Edit guest',
                            onPressed: () => _startEdit(guest),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline,
                                color: Colors.red),
                            tooltip: 'Delete guest',
                            onPressed: () => _confirmDelete(guest),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
