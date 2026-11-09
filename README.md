# WAOV Installer and Updater

The We Are One Voice launcher kit. Every WAOV asset zip carries `Miles Installer and Updater.exe`.
Each time it opens (install or the menu) it reads the newest `latest.json` from this repo's releases,
checks the SHA-256 hash and the RSA signature against the public key in `launcher/waov-update.pub.xml`,
and if a newer signed kit exists it downloads it and hands over. Old zips always install the newest kit.
Offline, it runs the kit it shipped with.

| File | What it does |
|------|--------------|
| `launcher/Miles Installer and Updater.ps1` | the master script (readable source of the .exe), loading screen, install, menu, update check |
| `launcher/*` | art (EGA base image, cat, trail), sound, icon, public key |
| `build-kit.ps1` | compiles the .exe with ps2exe, writes the backup .bat and README-LAUNCHER.txt |
| `release-kit.ps1` | bumps the version (1.0 to 1.1), builds, zips, signs, pushes, publishes a GitHub release |
| `pack-zip.ps1` | builds a store zip `{NAME}.zip` around an asset |
| `helper.py` | local bridge for the waov.art backdoor Installer Control tile (127.0.0.1:8754, pairing token) |
| `make-keys.ps1` | one time key pair; the private key never leaves the owner's PC |

The version shows in three places: the loading screen and the menu (top right), and the backdoor tile.
