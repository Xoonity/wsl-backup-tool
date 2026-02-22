# WSL2 Backup Tool

A professional-grade PowerShell utility to secure your Windows Subsystem for Linux (WSL2) environments. 
This tool ensures filesystem consistency by properly handling WSL instances before exportation.

## Key Features
- **Consistency:** Automatic `wsl --shutdown` to prevent ext4 corruption.
- **Reliability:** Advanced error handling and logging (fixes common PowerShell .Count issues).
- **Automation:** Built-in backup rotation (Retention policy).
- **Flexibility:** Supports compressed (.tar.gz) or standard (.tar) archives.

## Full Tutorials & Guides
For a deep dive into WSL2 backup architecture (VHDX, VSS snapshots, and recovery), check our expert guides:

- **English:** [Mastering WSL2 Backup & Recovery on Windows 11](https://cosmo-edge.com/expert-windows-11-wsl2-vhdx-backup) (Cosmo-Edge)
- **Français :** [Guide Expert : Sauvegarder WSL2 et ses instances IA](https://cosmo-games.com/sauvegarde-expert-windows-11-wsl2-vhdx) (Cosmo-Games)

## License
Distributed under the MIT License. See `LICENSE` for more information.
