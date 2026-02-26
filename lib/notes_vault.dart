import 'package:flutter/material.dart';
import 'database_service.dart';
import 'notes_screen.dart';
import 'security_service.dart'; // Import this to access your helper

class NotesVaultScreen extends StatefulWidget {
  const NotesVaultScreen({super.key});

  @override
  State<NotesVaultScreen> createState() => _NotesVaultScreenState();
}

class _NotesVaultScreenState extends State<NotesVaultScreen> {
  final NoteService _noteService = NoteService();
  List<Map<String, dynamic>> _notes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _refreshNotes();
  }

  Future<void> _refreshNotes() async {
    setState(() => _isLoading = true);
    final data = await _noteService.getAllNotes();
    setState(() {
      _notes = data;
      _isLoading = false;
    });
  }

  // Integration of your Global Helper
  Future<void> _deleteNote(Map<String, dynamic> note) async {
    bool confirmed = await SecurityService.confirmDeletion(context, note['title']);
    
    if (confirmed) {
      await _noteService.deleteNote(note['id']);
      _refreshNotes();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("'${note['title']}' purged from vault.")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("LECTURE VAULT")),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.greenAccent,
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const NotesScreen()),
        ).then((_) => _refreshNotes()),
        child: const Icon(Icons.add, color: Colors.black),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _notes.length,
              itemBuilder: (context, index) {
                final note = _notes[index];
                return Dismissible(
                  key: Key("note_${note['id']}"),
                  direction: DismissDirection.endToStart,
                  // Triggering your Global Helper here for swiping
                  confirmDismiss: (direction) => SecurityService.confirmDeletion(context, note['title']),
                  onDismissed: (direction) async {
                    await _noteService.deleteNote(note['id']);
                    _refreshNotes();
                  },
                  background: Container(
                    color: Colors.redAccent,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    child: const Icon(Icons.delete_forever, color: Colors.white),
                  ),
                  child: Card(
                    child: ListTile(
                      title: Text(note['title'], style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(note['content_text'], maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => NotesScreen(note: note)),
                      ).then((_) => _refreshNotes()),
                      onLongPress: () => _deleteNote(note),
                    ),
                  ),
                );
              },
            ),
    );
  }
}