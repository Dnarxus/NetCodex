[1.2.0] - 2026-03-01

Added
- Session Cache: Implemented an L1 memory buffer in PracticeService to store decrypted flashcards for smoother UI performance during study sessions.
- App Lifecycle Awareness: Integrated endSession() with the PinGateScreen observer to automatically purge keys and RAM caches when the app is minimized.
- Enhanced PIN Migration: Updated updateMasterPin to support atomic re-keying across all pillars of the vault (Notes, Practice, Passwords, etc.).

Fixed
- Plaintext Data Leak: Fixed a critical vulnerability where NoteService and PracticeService were saving data as raw strings instead of ciphertext.
- Migration Failure: Resolved CRITICAL: Decryption failed errors during PIN rotation by ensuring all database entries are pre-encrypted before storage.
- Note Image Cleanup: Patched the deleteNote method to properly decrypt JSON metadata so associated physical image files can be correctly identified and purged.


[1.1.0] - 2026-02-22

Added
- Secure PIN Rotation: Introduced the updateMasterPin engine capable of re-keying the entire SQLite database.
- Migration Engine: Added support for .codex file imports, allowing for cross-device vault restoration.
- Hardware setup persistence: Implemented _persistNoteImages to copy external assets into the internal app_assets folder.

Changed
- Upgraded Master PIN requirement from 4 digits to 6 digits for better security.