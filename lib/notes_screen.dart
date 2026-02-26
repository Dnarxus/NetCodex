import 'package:flutter/material.dart';
import 'database_service.dart';

class NotesScreen extends StatefulWidget {
  final Map<String, dynamic>? note;

  const NotesScreen({super.key, this.note});

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  // Standard controllers for plain text
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _contentController = TextEditingController();
  final NoteService _noteService = NoteService();

  @override
  void initState() {
    super.initState();
    if (widget.note != null) {
      _titleController.text = widget.note!['title'] ?? '';
      // Make sure this matches the new 'content_text' column name
      _contentController.text = widget.note!['content_text'] ?? ''; 
    }
  }

  Future<void> _handleSave() async {
    final String title = _titleController.text.trim();
    final String content = _contentController.text;

    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter a title")),
      );
      return;
    }

    if (widget.note == null) {
      await _noteService.saveNote(title, content);
    } else {
      await _noteService.updateNote(widget.note!['id'], title, content);
    }

    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("LECTURE NOTES"),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: _handleSave,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20.0),
        child: Column(
          children: [
            // Title Field
            TextField(
              controller: _titleController,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              decoration: const InputDecoration(
                hintText: "Title",
                border: InputBorder.none,
              ),
            ),
            const Divider(),
            // Justified Content Field
            Expanded(
              child: TextField(
                controller: _contentController,
                maxLines: null, // Makes it behave like a document editor
                expands: true,  // Fills the remaining screen space
                textAlign: TextAlign.justify, // <--- This fulfills your requirement
                style: const TextStyle(fontSize: 16, height: 1.5),
                decoration: const InputDecoration(
                  hintText: "Start typing network concepts...",
                  border: InputBorder.none,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}