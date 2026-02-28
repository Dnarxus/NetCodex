NetCodex: Zero-Trust Documentation Vault
A high-security, "offline-first" documentation and utility vault designed for network engineers and cybersecurity professionals. It eliminates cloud dependency by using localized AES-256-GCM encryption to protect infrastructure ledgers, credential vaults, and hardware setup guides.

🚀 Key Features
Zero-Trust Security: Industry-standard AES-256 (GCM) encryption combined with PBKDF2 key derivation.
Infrastructure Ledger: Hierarchical site and VLAN management with built-in CIDR validation and subnet intelligence.
Hardware Encyclopedia: Persistent documentation for network tools and hardware with an encrypted relative-path photo gallery.
Practice Engine: Encrypted flashcard system for rapid recall of network protocols and troubleshooting heuristics.
Portable Backups (.codex): A custom migration system that bundles the SQLite database and hardware assets into a single encrypted archive for cross-device portability.

🔒 Security Architecture
NetCodex operates on a strictly local, Zero-Knowledge model:
Volatile Session Management: Master keys are derived upon login and stored exclusively in RAM (Volatile Memory). Keys and decrypted caches are purged immediately when the app is paused or closed.
PBKDF2 Key Derivation: User PINs are never stored. Instead, they are stretched using PBKDF2 with 100,000+ iterations and a unique cryptographic salt.
Authenticated Encryption (AEAD): Uses AES-GCM to provide both confidentiality and authenticity, preventing "bit-flipping" attacks on your stored data.
Session Caching: Implements an L1 Memory Cache for high-frequency data (like Flashcards) to minimize CPU overhead while maintaining a secured state.
Secure PIN Rotation: Features a custom Re-Keying Engine that can decrypt and re-encrypt the entire vault database in a single atomic transaction when changing the Master PIN.
Secure Asset Management: Hardware photos are stored in a protected internal directory and referenced via encrypted relative paths.


This project is licensed under the MIT License - see the LICENSE file for details. Thank you.