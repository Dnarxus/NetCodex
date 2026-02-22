# NetCodex: Zero-Trust Infrastructure Vault

NetCodex is an "offline-first" documentation tool designed for network professionals. It provides a highly secure environment to store infrastructure ledgers, hardware setup guides, and heuristic troubleshooting data without relying on cloud services.

## 🚀 Key Features
- **Zero-Trust Security**: Uses AES-256 (GCM) encryption and PBKDF2 key derivation to ensure data is only accessible with your Master PIN.
- **Infrastructure Ledger**: Hierarchical management of sites and VLANs with built-in CIDR validation and subnet intelligence.
- **Hardware Encyclopedia**: Documentation sheets for tools (Go-Bag) including persistent relative photo storage.
- **Portable Backups (.codex)**: A custom migration system that bundles the SQLite database and hardware assets into a single encrypted archive.
- **Cross-Device Sync**: Includes a portable cryptographic salt and authentication anchor for seamless migration between devices.

## 🔒 Security Architecture
- **Volatile Sessions**: Encryption keys are stored in RAM and purged when the app is closed.
- **Portable Salt**: The cryptographic salt is stored in database metadata, allowing secure re-authentication on fresh installations.
- **Asset Portability**: Hardware photos are managed via relative paths to prevent broken links during vault migration.

## 🛠️ Tech Stack
- **Framework**: Flutter
- **Database**: SQLite (sqflite)
- **Encryption**: Cryptography (AES-GCM, PBKDF2)
- **State**: Singleton Services

## 📄 License
This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.