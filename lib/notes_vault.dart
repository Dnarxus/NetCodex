import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'dart:io';
import 'dart:convert';
import 'database_service.dart';
import 'notes_screen.dart';
import 'security_service.dart';

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
    // NoteService.getAllNotes() now injects 'preview_text' into each map
    final data = await _noteService.getAllNotes();
    if (mounted) {
      setState(() {
        _notes = data;
        _isLoading = false;
      });
    }
  }

  // --- PDF EXPORT LOGIC ---
  Future<void> _exportToPdf(Map<String, dynamic> note) async {
    final pdf = pw.Document();

    List<dynamic> blocks = [];
    try {
      // Logic to decode block-based content
      String rawContent = note['content_text'] ?? '';
      if (rawContent.startsWith('[')) {
        blocks = jsonDecode(rawContent);
      } else {
        // Fallback for legacy plain-text notes
        blocks = [{'type': 'text', 'content': rawContent}];
      }
    } catch (e) {
      blocks = [{'type': 'text', 'content': 'Error decoding note content.'}];
    }

    List<pw.Widget> pdfContent = [];
    
    // Header with Title
    pdfContent.add(
      pw.Header(
        level: 0, 
        child: pw.Text(
          note['title'].toString().toUpperCase(), 
          style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)
        )
      )
    );
    
    // Iterate through blocks to build PDF widgets
    for (var block in blocks) {
      if (block['type'] == 'text') {
        String text = block['content'].toString();
        if (text.isNotEmpty) {
          pdfContent.add(pw.Paragraph(
            text: text,
            textAlign: pw.TextAlign.justify,
            style: const pw.TextStyle(fontSize: 12),
          ));
        }
      } else if (block['type'] == 'image') {
        final imageFile = File(block['content']);
        if (await imageFile.exists()) {
          final image = pw.MemoryImage(imageFile.readAsBytesSync());
          pdfContent.add(pw.Center(
            child: pw.Container(
              margin: const pw.EdgeInsets.symmetric(vertical: 10),
              child: pw.Image(image, height: 350),
            )
          ));
        }
      }
    }

    // Generate Multipage PDF
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => pdfContent,
      ),
    );

    // Launch Save/Print Dialog
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: '${note['title']}.pdf',
    );
  }

  void _showNoteOptions(Map<String, dynamic> note) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 1. PDF Export
            ListTile(
              leading: const Icon(Icons.picture_as_pdf, color: Colors.blueAccent),
              title: const Text("Export as PDF"),
              onTap: () {
                Navigator.pop(context);
                _exportToPdf(note);
              },
            ),
            
            // 2. NEW: Version History/Restore
            ListTile(
              leading: const Icon(Icons.history, color: Colors.orangeAccent),
              title: const Text("Version History"),
              onTap: () {
                Navigator.pop(context);
                _showVersionDialog(note); // We'll build this dialog next
              },
            ),
            
            const Divider(),

            // 3. Purge (Delete)
            ListTile(
              leading: const Icon(Icons.delete_forever, color: Colors.redAccent),
              title: const Text("Purge from Vault"),
              onTap: () {
                Navigator.pop(context);
                _deleteNote(note);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showVersionDialog(Map<String, dynamic> note) async {
    final versions = await _noteService.getNoteVersions(note['id']);
    
    if (!mounted) return;

    if (versions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No previous versions found for this note.")),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Restore Backup"),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: versions.length,
            itemBuilder: (context, index) {
              final v = versions[index];
              final DateTime timestamp = DateTime.parse(v['version_timestamp']);
              
              // --- DIFF LOGIC ---
              int imgCount = 0;
              try {
                List<dynamic> blocks = jsonDecode(v['content_text']);
                imgCount = blocks.where((b) => b['type'] == 'image').length;
              } catch (e) { imgCount = 0; }

              return ListTile(
                leading: Icon(
                  imgCount > 0 ? Icons.image_search : Icons.text_snippet,
                  color: Colors.orangeAccent,
                ),
                title: Text("${timestamp.month}/${timestamp.day} at ${timestamp.hour}:${timestamp.minute.toString().padLeft(2, '0')}"),
                subtitle: Text("Title: ${v['title']}\nContains $imgCount image(s)"),
                isThreeLine: true,
                onTap: () async {
                  bool confirm = await SecurityService.confirmDeletion(
                    context, 
                    "Restore this version? Current changes will be backed up."
                  );
                  
                  if (confirm) {
                    await _noteService.updateNote(note['id'], v['title'], v['content_text']);
                    if (context.mounted) Navigator.pop(context);
                    _refreshNotes();
                  }
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("CLOSE")),
        ],
      ),
    );
  }

  Future<void> _deleteNote(Map<String, dynamic> note) async {
    bool confirmed = await SecurityService.confirmDeletion(context, note['title']);
    if (confirmed) {
      await _noteService.deleteNote(note['id']);
      _refreshNotes();
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
          : _notes.isEmpty
              ? const Center(child: Text("Your vault is empty."))
              : ListView.builder(
                  itemCount: _notes.length,
                  itemBuilder: (context, index) {
                    final note = _notes[index];
                    return Dismissible(
                      key: Key("note_${note['id']}"),
                      direction: DismissDirection.endToStart,
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
                        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        elevation: 2,
                        child: ListTile(
                          title: Text(note['title'], style: const TextStyle(fontWeight: FontWeight.bold)),
                          // UPDATED: Using the virtual preview field from NoteService
                          subtitle: Text(
                            note['preview_text'] ?? "No content",
                            maxLines: 1, 
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.grey),
                          ),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => NotesScreen(note: note)),
                          ).then((_) => _refreshNotes()),
                          onLongPress: () => _showNoteOptions(note),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}