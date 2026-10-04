# USB-Notfallkopie (LastResort)

`usb-backup.sh` legt auf dem Mac eine Notfallkopie des Homelabs auf die verschlüsselte
USB-SSD „LastResort“ (Samsung T7, 2 TB). Für den Fall „Homelab komplett weg“ (Brand,
Diebstahl, Ransomware): Mit der Disk allein kommst du wieder an alle Passwörter, an die
Storj-Zugänge für die Offsite-Backups und an die neuesten Stände aller Gäste.

Die Disk ist nur während des Laufs angesteckt und liegt sonst ausser Haus.

## Was drauf landet

Jeder Lauf ist ein eigener Ordner `homelab-backup/<Datum_Zeit>/` mit:

| Ordner | Inhalt | Quelle |
|---|---|---|
| `vaultwarden/` | verschlüsselter Bitwarden-Export und neuestes Vaultwarden-Backup (tar) | `~/Downloads`, TrueNAS |
| `truenas/` | TrueNAS-Config mit `pwenc_secret` (wie „Download Configuration“ mit Secret Seed) | TrueNAS `/data` |
| `homeassistant/` | neuestes automatisches Voll-Backup von Home Assistant (`automatic_backup_*.tar`, ca. 7 GB) | TrueNAS |
| `proxmox-vzdump/` | neuestes vzdump-Archiv jedes Gasts mit `.log` und `.notes` | TrueNAS |
| `nextcloud/` | der lokale Nextcloud-Ordner (inkl. „Config Backups“) | Mac |
| `git/` | Mirror-Klone aller GitHub-Repos | GitHub |
| `SHA256SUMS` | Prüfsummen aller Dateien | |
| `WARNUNGEN.txt` | nur wenn etwas fehlte oder zu alt war | |
| `LIESMICH.md` | diese Anleitung | |

Die letzten 3 Läufe bleiben (`KEEP`). Ein alter Lauf wird erst gelöscht, wenn der neue
vollständig ist. Unveränderte Nextcloud-Dateien sind zwischen den Läufen Hardlinks und
belegen nur einmal Platz. Ein Lauf braucht rund 40 GB.

## Einmalig einrichten

**1. Disk verschlüsseln.** Auf dem Mac im Terminal:

```
diskutil info /Volumes/LastResort | grep -E 'File System Personality|FileVault'
```

Steht dort `APFS` und `FileVault: Yes`, ist alles gut. Sonst:

- `FileVault: No` bei APFS: im Finder Rechtsklick auf „LastResort“ → „LastResort“ verschlüsseln.
  Das läuft im Hintergrund, die Disk bleibt dabei nutzbar.
- Nicht APFS (die T7 kommt ab Werk mit exFAT): Festplattendienstprogramm → Darstellung →
  „Alle Geräte einblenden“ → die Samsung T7 (das Gerät, nicht das Volume) → Löschen →
  Name `LastResort`, Format „APFS (verschlüsselt)“, Schema „GUID-Partitionstabelle“.
  Löscht alles auf der Disk.

Das Passwort kommt in Vaultwarden **und** auf Papier ins Notfallblatt, denn wenn Vaultwarden
weg ist, brauchst du es ohne Vaultwarden. Beim Entsperren „Im Schlüsselbund sichern“
ankreuzen ist in Ordnung, das betrifft nur diesen Mac.

**2. SSH vom Mac auf TrueNAS als root.** Auf dem Mac den öffentlichen Schlüssel anzeigen:

```
cat ~/.ssh/id_ed25519.pub
```

Gibt es keinen, zuerst `ssh-keygen -t ed25519` (Enter für Standardpfad). Den Schlüssel in
TrueNAS unter Credentials → Users → root → Edit → „Authorized Keys“ einfügen und speichern.
Test auf dem Mac:

```
ssh root@truenas.lan 'ls /mnt/tank01/ha-backups | tail -3'
```

Liegen die Home-Assistant-Backups woanders, den Pfad als `HA_DIR` in der Konfig eintragen.

**3. Skript auf dem Mac aktualisieren.** Im Terminal auf dem Mac:

```
cd ~/Documents/Code/shell && git pull
```

Eine Konfig ist nicht nötig. Nur wenn ein Pfad oder eine Einstellung abweichen soll:
`cp usb-backup.conf.example ~/.config/usb-backup.conf`, `chmod 600 ~/.config/usb-backup.conf`
und dort die Variable setzen.

**4. Erinnerung.** In der Erinnerungen-App eine Erinnerung „USB-Notfallkopie erneuern
(Anleitung: shell/usb-backup.md)“ anlegen, Wiederholen „Alle 3 Monate“.

## Ablauf (alle 3 Monate)

1. Im Web-Tresor (vault.mythenstrasse56.net): Werkzeuge → Tresor exportieren → Format
   „.json (Encrypted)“ → Exporttyp „Passwortgeschützt“ → eigenes Export-Passwort (auch aufs
   Notfallblatt). Die Datei landet in `~/Downloads`. Einen unverschlüsselten Export erkennt
   das Skript, kopiert ihn nicht und warnt.
2. Disk anstecken und entsperren.
3. Im Terminal auf dem Mac:

   ```
   ~/Documents/Code/shell/usb-backup.sh
   ```

   Dauert je nach Grösse der vzdump-Archive einige Minuten. Am Ende stehen die Warnungen.
4. Exportdatei in `~/Downloads` löschen (ist auf der Disk), dann
   `diskutil eject /Volumes/LastResort` und die Disk wieder ausser Haus bringen.

## Wiederherstellen

Erst prüfen, ob die Dateien heil sind (Terminal auf einem Mac, Disk entsperrt):

```
cd /Volumes/LastResort/homelab-backup/<Datum_Zeit> && shasum -a 256 -c SHA256SUMS | grep -v ': OK$'
```

Keine Ausgabe heisst: alles in Ordnung.

- **Passwörter:** Bitwarden-App oder bitwarden.com (Konto anlegen genügt) → Importieren →
  „Bitwarden (json)“ → `vaultwarden/bitwarden_encrypted_export_*.json` mit dem Export-Passwort.
  Darin stehen auch die Storj-Zugänge und die Secrets von flickr und inventar.
- **Vaultwarden-Server:** `vaultwarden/vaultwarden-backup-*.tar.gz`, Restore wie in
  `vaultwarden-backup.md` beschrieben.
- **TrueNAS:** neu installieren, dann System → General → Manage Configuration → Upload
  Config → `truenas/truenas-config-*.tar`. Danach sind alle Tasks und gespeicherten
  Zugänge (Storj) wieder da.
- **Proxmox-Gäste:** Die Dateien aus `proxmox-vzdump/` auf einen Proxmox-Storage kopieren
  (z. B. `/var/lib/vz/dump/`), dann in Proxmox den Storage öffnen → Backups → Restore.
- **Home Assistant:** beim Onboarding einer neuen Installation „Aus Backup wiederherstellen“
  → `homeassistant/*.tar`.
- **Nextcloud:** die Dateien liegen offen in `nextcloud/`.
- **Repos:** `git clone /Volumes/LastResort/homelab-backup/<Datum_Zeit>/git/ansible.git`.
