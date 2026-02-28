import 'package:flutter/material.dart';
import 'dart:async';
import 'database_service.dart';
import 'security_service.dart';

class PracticeScreen extends StatefulWidget {
  const PracticeScreen({super.key});

  @override
  State<PracticeScreen> createState() => _PracticeScreenState();
}

class _PracticeScreenState extends State<PracticeScreen> {
  final PracticeService _practiceService = PracticeService();
  List<String> _subjects = [];
  final List<String> _placeholderSubjects = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSubjects();
  }

  Future<void> _loadSubjects() async {
    setState(() => _isLoading = true);
    final data = await _practiceService.getUniqueSubjects();
    if (mounted) {
      setState(() {
        _subjects = {...data, ..._placeholderSubjects}.toList();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Knowledge Practice"),
        actions: [
          // Moved the New Subject button here
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: IconButton(
              icon: const Icon(Icons.create_new_folder, color: Colors.greenAccent),
              onPressed: () => _showCreateFolderDialog(),
              tooltip: "New Subject",
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _subjects.isEmpty
              ? const Center(
                  child: Text("No subjects yet. Create a folder to begin."),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: _subjects.length,
                  itemBuilder: (context, index) => _buildFolderCard(_subjects[index]),
                ),
    );
  }

  Widget _buildFolderCard(String subject) {
    return Card(
      elevation: 3,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onLongPress: () => _showFolderOptions(subject),
        onTap: () async {
          final cards = await _practiceService.getFlashcards(subject: subject);
          
          if (cards.isEmpty) {
            _showModeSelectionDialog(subject);
          } else {
            String autoMode = (cards.first['type'] == 'Flashcard') ? 'Flashcard' : 'Exam';
            _navigateToStudy(subject, autoMode);
          }
        },
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.folder_copy, size: 48, color: Colors.orangeAccent),
            const SizedBox(height: 12),
            Text(
              subject.split(' [').first, // Shows "OS" instead of "OS [FLASHCARD]"
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  // Helper to choose mode when opening an existing folder
  void _showModeSelectionDialog(String subject) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("OPEN $subject"),
        content: const Text("Choose your study mode:"),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _navigateToStudy(subject, "Flashcard");
            },
            child: const Text("FLASHCARD"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _navigateToStudy(subject, "Exam");
            },
            child: const Text("EXAM MODE"),
          ),
        ],
      ),
    );
  }

  void _showCreateFolderDialog() {
    final TextEditingController folderController = TextEditingController();
    String selectedMode = 'Flashcard';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text("New Subject Folder"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: folderController,
                decoration: const InputDecoration(hintText: "e.g. CCNA, OS"),
                textCapitalization: TextCapitalization.characters,
              ),
              const SizedBox(height: 16),
              DropdownButton<String>(
                value: selectedMode,
                isExpanded: true,
                items: ['Flashcard', 'Exam'].map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                onChanged: (val) => setDialogState(() => selectedMode = val!),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCEL")),
            ElevatedButton(
              onPressed: () {
                if (folderController.text.isNotEmpty) {
                  String subjectName = folderController.text.trim().toUpperCase();
                  String uniqueCategory = "$subjectName [${selectedMode.toUpperCase()}]";
                  
                  Navigator.pop(context);
                  _navigateToStudy(uniqueCategory, selectedMode);
                }
              },
              child: const Text("CREATE"),
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToStudy(String subject, String mode) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => StudySessionScreen(subject: subject, mode: mode),
      ),
    ).then((_) => _loadSubjects());
  }

  void _showFolderOptions(String subject) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text("Rename Folder"),
              onTap: () {
                Navigator.pop(context);
                _showRenameFolderDialog(subject);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_forever, color: Colors.redAccent),
              title: const Text("Delete Folder & All Contents"),
              onTap: () async {
                Navigator.pop(context);
                bool confirm = await SecurityService.confirmDeletion(context, "entire '$subject' folder");
                if (confirm) {
                  await _practiceService.deleteSubject(subject);
                  _loadSubjects();
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showRenameFolderDialog(String oldName) {
    final TextEditingController folderController = TextEditingController(text: oldName);
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Rename Subject"),
        content: TextField(controller: folderController),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text("CANCEL")),
          ElevatedButton(
            onPressed: () async {
              if (folderController.text.isNotEmpty) {
                String newName = folderController.text.trim();
                
                // Perform the database update
                await _practiceService.renameSubject(oldName, newName);
                
                // Check if the dialog is still visible before trying to close it
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                }
                
                _loadSubjects();
              }
            },
            child: const Text("RENAME"),
          ),
        ],
      ),
    );
  }
}

class StudySessionScreen extends StatefulWidget {
  final String subject;
  final String mode;
  const StudySessionScreen({super.key, required this.subject, required this.mode});

  @override
  State<StudySessionScreen> createState() => _StudySessionScreenState();
}

class _StudySessionScreenState extends State<StudySessionScreen> {
  final PracticeService _service = PracticeService();
  List<Map<String, dynamic>> _data = [];
  int _index = 0;
  bool _revealed = false;
  
  Timer? _timer;
  int _secondsElapsed = 0;
  int _correctCount = 0;
  
  String? _tempSelection; 
  String? _confirmedAnswer; 

  @override
  void initState() {
    super.initState();
    _load();
    if (widget.mode == 'Exam') {
      _startTimer();
    }
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) setState(() => _secondsElapsed++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final d = await _service.getFlashcards(subject: widget.subject);
    if (mounted) {
      setState(() {
        _data = List<Map<String, dynamic>>.from(d);
        _data.shuffle(); // Randomize the cards every time you open the folder
      });
    }
  }

  void _confirmAnswer() {
    if (_tempSelection == null) return;

    setState(() {
      _confirmedAnswer = _tempSelection;
      final correct = _data[_index]['answer'].toString().trim().toLowerCase();
      if (_confirmedAnswer!.trim().toLowerCase() == correct) {
        _correctCount++;
      }
    });

    if (_index == _data.length - 1) {
      Future.delayed(const Duration(milliseconds: 1500), () => _showResults());
    }
  }

  void _showResults() {
    _timer?.cancel();
    String timeStr = "${(_secondsElapsed ~/ 60).toString().padLeft(2, '0')}:${(_secondsElapsed % 60).toString().padLeft(2, '0')}";
    double percentage = _data.isEmpty ? 0 : (_correctCount / _data.length) * 100;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text("SESSION COMPLETE"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("Score: $_correctCount / ${_data.length}", 
                 style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text("${percentage.toStringAsFixed(1)}%", 
                 style: TextStyle(fontSize: 20, color: percentage >= 75 ? Colors.green : Colors.orange, fontWeight: FontWeight.bold)),
            if (widget.mode == 'Exam') Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text("Time Spent: $timeStr"),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () { Navigator.pop(context); Navigator.pop(context); },
            child: const Text("EXIT"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _index = 0;
                _correctCount = 0;
                _secondsElapsed = 0;
                _tempSelection = null;
                _confirmedAnswer = null;
                _revealed = false;
                if (widget.mode == 'Exam') _startTimer();
              });
            },
            child: const Text("RETRY"),
          ),
        ],
      ),
    );
  }

  void _showEntryDialog({Map<String, dynamic>? existingEntry}) {
    final TextEditingController qController = TextEditingController(text: existingEntry?['question']);
    final TextEditingController aController = TextEditingController(text: existingEntry?['answer']);
    
    List<TextEditingController> optControllers = [];
    
    if (existingEntry != null && existingEntry['options'] != null && existingEntry['options'].isNotEmpty) {
      List<String> existingOpts = existingEntry['options'].toString().split(',');
      for (var opt in existingOpts) {
        optControllers.add(TextEditingController(text: opt.trim()));
      }
    } else {
      optControllers.addAll([TextEditingController(), TextEditingController()]);
    }

    String type = existingEntry?['type'] ?? (widget.mode == 'Flashcard' ? 'Flashcard' : 'Multiple Choice');
    
    // Track T/F state: defaults to True unless editing a "False" answer
    bool isTrueSelected = existingEntry?['answer'].toString().toLowerCase() == 'false' ? false : true;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existingEntry == null ? "Add ${widget.mode} Entry" : "Edit Entry"),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.mode == 'Exam') 
                    DropdownButton<String>(
                      value: type,
                      isExpanded: true,
                      items: ['Multiple Choice', 'True/False']
                          .map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                      onChanged: (val) => setDialogState(() => type = val!),
                    )
                  else
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8.0),
                      child: Text("Mode: FLASHCARD", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueAccent)),
                    ),
                    
                  const Divider(),
                  TextField(
                    controller: qController, 
                    decoration: const InputDecoration(labelText: "Question"),
                    maxLines: 2,
                  ),
                  
                  if (type == 'Multiple Choice') ...[
                    const SizedBox(height: 10),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text("Options:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                    ...optControllers.asMap().entries.map((entry) {
                      int idx = entry.key;
                      return Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: entry.value,
                                decoration: InputDecoration(
                                  labelText: "Option ${idx + 1}",
                                  border: const OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.remove_circle, color: Colors.redAccent),
                              onPressed: () => setDialogState(() => optControllers.removeAt(idx)),
                            ),
                          ],
                        ),
                      );
                    }),
                    TextButton.icon(
                      onPressed: () => setDialogState(() => optControllers.add(TextEditingController())),
                      icon: const Icon(Icons.add_circle, color: Colors.greenAccent),
                      label: const Text("ADD OPTION"),
                    ),
                  ],

                  const SizedBox(height: 20),
                  
                  // Toggle Buttons for True/False, otherwise a TextField
                  if (type == 'True/False') ...[
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text("Correct Answer:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
                    ),
                    const SizedBox(height: 8),
                    ToggleButtons(
                      isSelected: [isTrueSelected, !isTrueSelected],
                      onPressed: (int index) {
                        setDialogState(() => isTrueSelected = index == 0);
                      },
                      borderRadius: BorderRadius.circular(8),
                      selectedColor: Colors.white,
                      fillColor: isTrueSelected ? Colors.green : Colors.red,
                      constraints: const BoxConstraints(minHeight: 40, minWidth: 100),
                      children: const [
                        Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text("TRUE")),
                        Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text("FALSE")),
                      ],
                    ),
                  ] else ...[
                    TextField(
                      controller: aController, 
                      decoration: InputDecoration(
                        labelText: type == 'Flashcard' ? "Answer" : "Correct Answer",
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text("CANCEL")),
            ElevatedButton(
              onPressed: () async {
                if (qController.text.isEmpty) return;

                // Determine the final answer string based on the current type
                String finalAnswer;
                if (type == 'True/False') {
                  finalAnswer = isTrueSelected ? "True" : "False";
                } else {
                  if (aController.text.isEmpty) return;
                  finalAnswer = aController.text.trim();
                }

                String optionsString = type == 'Multiple Choice' 
                    ? optControllers.map((c) => c.text.trim()).where((t) => t.isNotEmpty).join(',')
                    : "";

                if (existingEntry == null) {
                  await _service.saveCard(qController.text, finalAnswer, widget.subject, type: type, options: optionsString);
                } else {
                  await _service.updateCard(existingEntry['id'], qController.text, finalAnswer, widget.subject, type: type, options: optionsString);
                }

                if (dialogContext.mounted) Navigator.pop(dialogContext);
                _load();
              },
              child: const Text("SAVE"),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("${widget.subject.split(' [').first.toUpperCase()} (${widget.mode})"),
        actions: [
          if (widget.mode == 'Exam')
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 16.0),
                child: Text(
                  "${(_secondsElapsed ~/ 60).toString().padLeft(2, '0')}:${(_secondsElapsed % 60).toString().padLeft(2, '0')}",
                  style: const TextStyle(fontFamily: 'Courier', fontWeight: FontWeight.bold, fontSize: 18),
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // 1. Top Section: Progress and Question (Only if data exists)
          if (_data.isNotEmpty) ...[
            LinearProgressIndicator(
              value: (_index + 1) / _data.length,
              color: Colors.greenAccent,
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                "Card ${_index + 1} of ${_data.length}",
                style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w500),
              ),
            ),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _data[_index]['type'].toString().toUpperCase(),
                        style: const TextStyle(color: Colors.grey, fontSize: 10, letterSpacing: 2),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        _data[_index]['question'],
                        style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w500),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 48),
                      _buildDynamicStudyView(_data[_index]),
                    ],
                  ),
                ),
              ),
            ),
          ] 
          // 2. Center Section: Empty State (If no data)
          else ...[
            Expanded(child: _buildEmptyState()),
          ],
          
          // 3. Bottom Section: Unified Navigation & Management Toolbar
          // Passing a dummy map if empty so the buttons still render
          _buildNavigationRow(_data.isNotEmpty ? _data[_index] : {'id': -1}),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  // Separate widget for the empty state to keep the build method clean
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.library_add_check_outlined, size: 80, color: Colors.grey.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          const Text(
            "This folder is empty",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          const Text(
            "Tap the + button below to add\nyour first card or question.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildDynamicStudyView(Map<String, dynamic> item) {
    final correct = item['answer'].toString();
    
    if (widget.mode == 'Flashcard') {
      return _revealed
          ? Text(correct, style: const TextStyle(fontSize: 24, color: Colors.greenAccent, fontWeight: FontWeight.bold))
          : ElevatedButton(onPressed: () => setState(() => _revealed = true), child: const Text("REVEAL ANSWER"));
    }

    // Exam Mode Options
    List<String> options = item['type'] == 'True/False' 
        ? ['True', 'False'] 
        : (item['options'] ?? "").toString().split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

    return Column(
      children: [
        ...options.map((opt) {
          bool isSelected = _tempSelection == opt;
          bool isConfirmed = _confirmedAnswer != null;
          bool isCorrect = opt.trim().toLowerCase() == correct.trim().toLowerCase();

          Color btnColor = Colors.grey.shade300; 
          if (isConfirmed) {
            if (isCorrect) {
              btnColor = Colors.green;
            } else if (isSelected) {
              btnColor = Colors.red;
            }
          } else if (isSelected) {
            btnColor = Colors.blueAccent.withValues(alpha: 0.3);
          }

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: btnColor,
                  foregroundColor: isConfirmed && (isCorrect || isSelected) ? Colors.white : Colors.black,
                  side: isSelected && !isConfirmed ? const BorderSide(color: Colors.blue, width: 2) : null,
                ),
                onPressed: isConfirmed ? null : () => setState(() => _tempSelection = opt),
                child: Text(opt),
              ),
            ),
          );
        }),
        const SizedBox(height: 20),
        if (_tempSelection != null && _confirmedAnswer == null)
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orangeAccent),
            onPressed: _confirmAnswer,
            icon: const Icon(Icons.check, color: Colors.black),
            label: const Text("CONFIRM ANSWER", style: TextStyle(color: Colors.black)),
          ),
      ],
    );
  }

  Widget _buildNavigationRow(Map<String, dynamic> item) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.05), 
        border: const Border(top: BorderSide(color: Colors.white10)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Left: Back Arrow
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 22),
            onPressed: _index > 0
                ? () => setState(() {
                      _index--;
                      _resetEntryState();
                    })
                : null,
          ),

          // Center Group: Trash and Add
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Delete Specific Card
              IconButton(
                // Added a null check for item['id'] to prevent crashes when empty
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 26),
                onPressed: item['id'] == -1 
                  ? null 
                  : () async {
                      bool confirm = await SecurityService.confirmDeletion(
                          context, "this specific question");
                      if (confirm) {
                        await _service.deleteCard(item['id']);
                        await _load();
                        setState(() {
                          if (_index >= _data.length && _index > 0) _index--;
                          _resetEntryState();
                        });
                      }
                    },
              ),
              const SizedBox(width: 20),
              // The Add Button
              IconButton(
                icon: const Icon(Icons.add_circle, color: Colors.greenAccent, size: 32),
                onPressed: () => _showEntryDialog(),
                tooltip: "Add New Card",
              ),
            ],
          ),

          // Right: Forward Arrow
          IconButton(
            icon: const Icon(Icons.arrow_forward_ios, size: 22),
            onPressed: _index < _data.length - 1
                ? () => setState(() {
                      _index++;
                      _resetEntryState();
                    })
                : null,
          ),
        ],
      ),
    );
  }

  // Helper to clear selections when moving
  void _resetEntryState() {
    _tempSelection = null;
    _confirmedAnswer = null;
    _revealed = false;
  }
}