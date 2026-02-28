import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:convert';
import 'database_service.dart';

/// Represents a single piece of content (Text or Image) within the note.
class NoteBlock {
  String type; // 'text' or 'image'
  String content; 
  TextEditingController? controller;
  FocusNode? focusNode;

  NoteBlock({
    required this.type, 
    required this.content, 
    this.controller, 
    this.focusNode
  });

  Map<String, dynamic> toMap() => {'type': type, 'content': content};
}

class NotesScreen extends StatefulWidget {
  final Map<String, dynamic>? note;
  const NotesScreen({super.key, this.note});

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  final NoteService _noteService = NoteService();
  final TextEditingController _titleController = TextEditingController();
  
  final List<NoteBlock> _blocks = [];

  @override
  void initState() {
    super.initState();
    if (widget.note != null) {
      _titleController.text = widget.note!['title'] ?? '';
      _loadExistingContent(widget.note!['content_text'] ?? '');
    } else {
      _addNewTextBlock();
    }
  }

  void _addNewTextBlock({String initialText = ""}) {
    _blocks.add(NoteBlock(
      type: 'text',
      content: initialText,
      controller: TextEditingController(text: initialText),
      focusNode: FocusNode(),
    ));
  }

  void _loadExistingContent(String rawContent) {
    try {
      if (!rawContent.trim().startsWith('[')) {
        _addNewTextBlock(initialText: rawContent);
        return;
      }

      final List<dynamic> decoded = jsonDecode(rawContent);
      for (var item in decoded) {
        _blocks.add(NoteBlock(
          type: item['type'],
          content: item['content'],
          controller: item['type'] == 'text' ? TextEditingController(text: item['content']) : null,
          focusNode: item['type'] == 'text' ? FocusNode() : null,
        ));
      }
    } catch (e) {
      _addNewTextBlock(initialText: rawContent);
    }
  }

  Future<void> _insertImage() async {
    final XFile? image = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (image == null) return;

    setState(() {
      int currentIndex = _blocks.indexWhere((b) => b.focusNode?.hasFocus ?? false);

      if (currentIndex != -1 && _blocks[currentIndex].type == 'text') {
        final controller = _blocks[currentIndex].controller!;
        final text = controller.text;
        final cursorPosition = controller.selection.baseOffset;

        // Split text based on cursor
        String textBefore = cursorPosition != -1 ? text.substring(0, cursorPosition) : text;
        String textAfter = cursorPosition != -1 ? text.substring(cursorPosition) : "";

        // 1. Update current block to text before image
        _blocks[currentIndex].content = textBefore;
        controller.text = textBefore;

        // 2. Insert Image Block
        _blocks.insert(currentIndex + 1, NoteBlock(type: 'image', content: image.path));

        // 3. Insert new text block for the remaining text
        _blocks.insert(currentIndex + 2, NoteBlock(
          type: 'text',
          content: textAfter,
          controller: TextEditingController(text: textAfter),
          focusNode: FocusNode(),
        ));

        // Auto-focus the new block after the image
        Future.delayed(const Duration(milliseconds: 100), () {
          _blocks[currentIndex + 2].focusNode?.requestFocus();
        });
      } else {
        // Fallback: Add to the end
        _blocks.add(NoteBlock(type: 'image', content: image.path));
        _addNewTextBlock();
      }
    });
  }

  Future<void> _handleSave() async {
    final String title = _titleController.text.trim();
    if (title.isEmpty) return;

    // Sync all controller text into the 'content' field before encoding
    for (var block in _blocks) {
      if (block.type == 'text') {
        block.content = block.controller?.text ?? "";
      }
    }

    final String jsonContent = jsonEncode(_blocks.map((b) => b.toMap()).toList());

    if (widget.note == null) {
      await _noteService.saveNote(title, jsonContent);
    } else {
      await _noteService.updateNote(widget.note!['id'], title, jsonContent);
    }

    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("LECTURES"),
        actions: [
          IconButton(icon: const Icon(Icons.add_a_photo_outlined), onPressed: _insertImage),
          IconButton(icon: const Icon(Icons.check), onPressed: _handleSave),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0),
            child: TextField(
              controller: _titleController,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              decoration: const InputDecoration(hintText: "Title", border: InputBorder.none),
            ),
          ),
          const Divider(),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: _blocks.length,
              itemBuilder: (context, index) {
                final block = _blocks[index];
                
                if (block.type == 'text') {
                  return TextField(
                    controller: block.controller,
                    focusNode: block.focusNode,
                    maxLines: null,
                    textAlign: TextAlign.justify,
                    style: const TextStyle(fontSize: 16, height: 1.5),
                    decoration: const InputDecoration(
                      hintText: "Continue typing...",
                      border: InputBorder.none,
                    ),
                  );
                } else {
                  // Image Block Rendering
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Stack(
                      alignment: Alignment.topRight,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(File(block.content), fit: BoxFit.cover),
                        ),
                        // Individual Delete for the Image
                        CircleAvatar(
                          backgroundColor: Colors.black54,
                          radius: 16,
                          child: IconButton(
                            icon: const Icon(Icons.close, color: Colors.white, size: 16),
                            onPressed: () => setState(() => _blocks.removeAt(index)),
                          ),
                        ),
                      ],
                    ),
                  );
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}