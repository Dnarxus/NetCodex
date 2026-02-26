import 'package:flutter/material.dart';
import 'database_service.dart';
import 'security_service.dart';

class PracticeScreen extends StatefulWidget {
  const PracticeScreen({super.key});

  @override
  State<PracticeScreen> createState() => _PracticeScreenState();
}

class _PracticeScreenState extends State<PracticeScreen> {
  final PracticeService _practiceService = PracticeService();
  List<Map<String, dynamic>> _flashcards = [];
  List<String> _subjects = ['All'];
  String _selectedSubject = 'All';
  
  int _currentIndex = 0;
  bool _showAnswer = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadFlashcards();
  }

  /// Loads flashcards based on the selected filter and refreshes the subject list
  Future<void> _loadFlashcards() async {
    setState(() => _isLoading = true);
    
    // 1. Fetch cards for the selected subject
    final data = await _practiceService.getFlashcards(subject: _selectedSubject);
    
    // 2. Fetch all unique subjects for the filter menu
    final subjectsData = await _practiceService.getUniqueSubjects();
    
    if (mounted) {
      setState(() {
        _flashcards = data;
        _subjects = ['All', ...subjectsData];
        _isLoading = false;
        _currentIndex = 0; // Reset to start when filter changes
        _showAnswer = false;
      });
    }
  }

  void _nextCard() {
    if (_currentIndex < _flashcards.length - 1) {
      setState(() {
        _currentIndex++;
        _showAnswer = false;
      });
    }
  }

  void _prevCard() {
    if (_currentIndex > 0) {
      setState(() {
        _currentIndex--;
        _showAnswer = false;
      });
    }
  }

  // Logic to handle deletion using your Global UI Helper
  Future<void> _handleDelete() async {
    final currentCard = _flashcards[_currentIndex];
    final String cardTitle = "this ${currentCard['category']} card";

    // Use your Global UI Helper
    bool confirmed = await SecurityService.confirmDeletion(context, cardTitle);

    if (confirmed) {
      await _practiceService.deleteCard(currentCard['id']);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Card purged from practice bank.")),
        );
        _loadFlashcards(); // Refresh the deck
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text("PRACTICE ENGINE"),
        actions: [
          // Delete Button
          if (!_isLoading && _flashcards.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              tooltip: "Delete Current Card",
              onPressed: _handleDelete,
            ),
          IconButton(
            icon: const Icon(Icons.shuffle),
            onPressed: _flashcards.isEmpty ? null : () {
              setState(() {
                _flashcards.shuffle();
                _currentIndex = 0;
                _showAnswer = false;
              });
            },
          ),
          // Shuffle Button
          IconButton(
            icon: const Icon(Icons.shuffle),
            tooltip: "Shuffle Deck",
            onPressed: _flashcards.isEmpty ? null : () {
              setState(() {
                _flashcards.shuffle();
                _currentIndex = 0;
                _showAnswer = false;
              });
            },
          ),
          // Dynamic Filter Menu
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_list),
            onSelected: (String subject) {
              _selectedSubject = subject;
              _loadFlashcards();
            },
            itemBuilder: (context) => _subjects.map((sub) => PopupMenuItem(
              value: sub,
              child: Row(
                children: [
                  Icon(
                    sub == _selectedSubject ? Icons.check_circle : Icons.circle_outlined,
                    size: 18,
                    color: Colors.greenAccent,
                  ),
                  const SizedBox(width: 10),
                  Text(sub),
                ],
              ),
            )).toList(),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.greenAccent))
          : _flashcards.isEmpty
              ? _buildEmptyState()
              : Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    children: [
                      // Card Progress & Subject Info
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "CARD ${_currentIndex + 1} OF ${_flashcards.length}",
                            style: const TextStyle(letterSpacing: 1.2, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.greenAccent.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.3)),
                            ),
                            child: Text(
                              _flashcards[_currentIndex]['category']?.toUpperCase() ?? "GENERAL",
                              style: const TextStyle(color: Colors.greenAccent, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      
                      // THE FLASHCARD
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _showAnswer = !_showAnswer),
                          child: Card(
                            elevation: 8,
                            color: _showAnswer 
                                ? Colors.greenAccent.withValues(alpha: 0.05) 
                                : (isDark ? Colors.grey[900] : Colors.white),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                              side: BorderSide(
                                color: _showAnswer ? Colors.greenAccent : Colors.transparent,
                                width: 2,
                              ),
                            ),
                            child: Stack(
                              children: [
                                Positioned(
                                  top: 20,
                                  left: 20,
                                  child: Text(
                                    _showAnswer ? "ANSWER" : "QUESTION",
                                    style: TextStyle(
                                      color: _showAnswer ? Colors.greenAccent : Colors.grey,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 2,
                                    ),
                                  ),
                                ),
                                Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(32.0),
                                    child: SingleChildScrollView(
                                      child: Text(
                                        _showAnswer 
                                            ? _flashcards[_currentIndex]['answer'] 
                                            : _flashcards[_currentIndex]['question'],
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(fontSize: 22, height: 1.4),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      
                      const SizedBox(height: 40),

                      // NAVIGATION BUTTONS
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildNavButton(Icons.arrow_back_ios_new, _prevCard),
                          ElevatedButton.icon(
                            onPressed: () => setState(() => _showAnswer = !_showAnswer),
                            icon: Icon(_showAnswer ? Icons.help_outline : Icons.visibility),
                            label: Text(_showAnswer ? "REVEAL QUESTION" : "REVEAL ANSWER"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.greenAccent,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                          _buildNavButton(Icons.arrow_forward_ios, _nextCard),
                        ],
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.greenAccent,
        onPressed: () => _showAddCardDialog(),
        child: const Icon(Icons.add, color: Colors.black),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.inbox_outlined, size: 60, color: Colors.grey),
          const SizedBox(height: 16),
          Text(_selectedSubject == 'All' 
            ? "Practice bank empty." 
            : "No cards for '$_selectedSubject'"),
          if (_selectedSubject != 'All')
            TextButton(
              onPressed: () {
                _selectedSubject = 'All';
                _loadFlashcards();
              },
              child: const Text("Clear Filter", style: TextStyle(color: Colors.greenAccent)),
            )
        ],
      ),
    );
  }

  Widget _buildNavButton(IconData icon, VoidCallback? onPressed) {
    return IconButton(
      icon: Icon(icon),
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: Colors.white10,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _showAddCardDialog() {
    final TextEditingController qController = TextEditingController();
    final TextEditingController aController = TextEditingController();
    final TextEditingController catController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Create Practice Card"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: catController, 
                decoration: const InputDecoration(hintText: "Subject (e.g. CCNA, OS, Calculus)"),
                textCapitalization: TextCapitalization.words,
              ),
              const Divider(height: 30),
              TextField(controller: qController, decoration: const InputDecoration(hintText: "Question")),
              const SizedBox(height: 10),
              TextField(controller: aController, decoration: const InputDecoration(hintText: "Answer")),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text("CANCEL")),
          ElevatedButton(
            onPressed: () async {
              final navigator = Navigator.of(dialogContext);

              if (qController.text.trim().isEmpty || aController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Please provide both a question and an answer.")),
                );
                return;
              }

              final String category = catController.text.trim().isEmpty ? "General" : catController.text.trim();

              await _practiceService.saveCard(qController.text, aController.text, category);
              
              navigator.pop();
              if (mounted) _loadFlashcards();
            },
            child: const Text("SAVE CARD"),
          ),
        ],
      ),
    );
  }
}