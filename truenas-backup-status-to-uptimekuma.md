# TrueNAS-Backups in Uptime Kuma

`truenas-backup-status-to-uptimekuma.sh` läuft stündlich auf TrueNAS. Es prüft die Backup-Tasks und meldet jeden per Push an einen eigenen Monitor in Uptime Kuma. So sieht man die TrueNAS-Backups dort neben den anderen Cronjobs (Ansible-Updates, Vaultwarden-Backup) und bekommt bei Fehlern eine Pushover-Meldung.

## Überblick

### Ablauf

```
Proxmox-Cluster (n01, n02)          Vaultwarden-Container          TrueNAS-eigene Tasks
vzdump So 01:00, alle Gäste         Backup täglich 00:30           Snapshots, TrueCloud, Storj
        │ SMB (Storage NAS-SMB)             │ scp                          │
        ▼                                   ▼                              │
/mnt/tank01/proxmox-raw-backups/dump   /mnt/tank01/vaultwarden-backups    │
        └──────────────┬────────────────────┴──────────────────────────────┘
                       ▼
   truenas-backup-status-to-uptimekuma.sh  (TrueNAS Cron, stündlich Minute 15)
                       │ ein HTTPS-Push pro Konfig-Zeile: status=up|down, msg=...
                       ▼
   Uptime Kuma (debian-uptimekuma.lan), ein Push-Monitor pro Zeile
                       │ bei Statuswechsel UP↔DOWN
                       ▼
                    Pushover
```

1. Die Backups selbst laufen unabhängig vom Skript: Proxmox schreibt seine vzdump-Archive über den SMB-Share in das Dataset `proxmox-raw-backups`, Vaultwarden kopiert sein Archiv per `scp` nach `vaultwarden-backups`, TrueNAS macht Snapshots und Cloud-Uploads.
2. Stündlich um Minute 15 liest das Skript seine Konfig. Pro Zeile prüft es einen Task (über `midclt`) oder einen Ordner (Dateialter).
3. Pro Zeile schickt es genau einen Push an Uptime Kuma: `up` oder `down` mit einer kurzen Nachricht, z. B. `13 Gaeste gesichert` oder `117 vor 192 h`.
4. Uptime Kuma zeigt den Status und schickt bei einem Wechsel (UP→DOWN oder zurück) eine Pushover-Meldung mit dieser Nachricht. Ein normaler UP-Push erzeugt keine Meldung.
5. Kommt länger als das Heartbeat-Intervall (2 h) gar kein Push, geht der Monitor ebenfalls auf DOWN. Das fängt den Fall ab, dass das Skript oder der Cron nicht mehr läuft.

### Wo was liegt

| Was | Wo |
|---|---|
| Skript | TrueNAS: `/mnt/tank01/scripts/truenas-backup-status-to-uptimekuma.sh` |
| Konfig mit den Push-URLs | TrueNAS: `/mnt/tank01/scripts/truenas-backup-status-to-uptimekuma.conf` (nur root, nicht im Repo) |
| Vorlage der Konfig | dieses Repo: `truenas-backup-status-to-uptimekuma.conf.example` |
| Cron Job | TrueNAS: System > Advanced Settings > Cron Jobs, „Backup-Status an Uptime Kuma“, root, stündlich Minute 15 |
| Proxmox-Backups | TrueNAS: `/mnt/tank01/proxmox-raw-backups/dump`, in Proxmox als Storage `NAS-SMB` (Job in `/etc/pve/jobs.cfg`, So 01:00, keep-last 4) |
| Vaultwarden-Backups | TrueNAS: `/mnt/tank01/vaultwarden-backups` |
| Monitore und Benachrichtigung | Uptime Kuma auf debian-uptimekuma.lan, Benachrichtigung Pushover |

### Wohin gemeldet wird

| Ereignis | Meldung |
|---|---|
| Ein Check ist DOWN (Backup fehlt, zu alt, leer, Task mit Fehler) | Uptime Kuma, Monitor rot, Pushover mit Grund |
| Skript läuft nicht mehr (Cron weg, TrueNAS aus) | Uptime Kuma nach 2 h ohne Push, Pushover |
| Fehler in der Konfig oder Uptime Kuma nimmt den Push nicht an | Exit-Code 1, TrueNAS schickt eine Cron-Fehlermail bzw. einen Alert |
| Alles OK | nur grüner Balken in Uptime Kuma |

## Was geprüft wird

| Typ in der Konfig | Quelle | DOWN, wenn |
|---|---|---|
| `snapshot` | Periodic Snapshot Task (`pool.snapshottask.query`) | letzter Lauf mit Fehler, oder letzter Erfolg älter als `max_h` |
| `cloudsync` | Cloud Sync Task, z. B. Storj (`cloudsync.query`) | Job `FAILED`/`ABORTED`, oder letzter Erfolg älter als `max_h` |
| `replication` | Replication Task (`replication.query`) | wie oben |
| `rsync` | Rsync Task (`rsynctask.query`) | wie oben |
| `file` | ein Ordner, z. B. `/mnt/tank01/vaultwarden-backups` | keine Datei, neueste Datei leer oder älter als `max_h` |
| `vzdump` | der `dump`-Ordner des Proxmox-Storage NAS-SMB | ein Gast, dessen neuestes Archiv leer oder älter als `max_h` ist |

Ein Task, der gerade läuft, gilt als UP. Den Fehlertext von TrueNAS schickt das Skript als Nachricht mit, er steht dann in Uptime Kuma und in der Pushover-Meldung.

Das Skript bewertet selbst, ob ein Backup zu alt ist, und schickt dann sofort DOWN. Uptime Kuma merkt über das Heartbeat-Intervall nur noch, wenn das Skript gar nicht mehr läuft.

**Vaultwarden hat damit zwei Monitore, und beide sind sinnvoll.** Der Push aus dem Backup-Skript auf dem Vaultwarden-Container (`HC_URL`) meldet, dass das Backup dort gelaufen ist. Der `file`-Check hier meldet, dass die Datei wirklich auf TrueNAS angekommen ist.

**Proxmox-Backups (`vzdump`).** Der Check schaut im `dump`-Ordner für jeden Gast (VM oder Container) nach dem neuesten Archiv. Ein Gast, der beim letzten Lauf fehlgeschlagen ist, fällt so auf, auch wenn alle anderen gesichert wurden. Die Nachricht nennt die betroffenen IDs, z. B. `117 vor 192 h`. Ein Gast, dessen neuestes Archiv älter als dreimal `max_h` ist, gilt als gelöscht und wird ignoriert, weil Proxmox die Archive entfernter Gäste liegen lässt. Ein Monitor deckt damit alle Nodes ab. Für den wöchentlichen Job (So 01:00) passt `max_h` 174: eine Woche plus 6 h für die Laufzeit.

## Einrichten

### 1. Monitore in Uptime Kuma anlegen

Pro Zeile der Konfig einen Monitor anlegen:

- Monitor-Typ: **Push**
- Name: z. B. `TrueNAS Snapshot nextcloud daily`, `TrueNAS Storj lightroom`
- Heartbeat-Intervall: **7200** Sekunden (2 h; das Skript pusht stündlich)
- Wiederholungen: 0
- Benachrichtigung: Pushover

Die angezeigte Push-URL kopieren. Den Teil ab `?` kann man mitkopieren, das Skript schneidet ihn ab.

### 2. Skript auf TrueNAS ablegen

Als root auf TrueNAS. Die Dateien liegen auf dem Pool, damit sie TrueNAS-Updates sicher überstehen:

```sh
mkdir -p /mnt/tank01/scripts && cd /mnt/tank01/scripts
base=https://raw.githubusercontent.com/gatogatogato/shell/master
curl -fsSLO "$base/truenas-backup-status-to-uptimekuma.sh"
curl -fsSL "$base/truenas-backup-status-to-uptimekuma.conf.example" -o truenas-backup-status-to-uptimekuma.conf
chmod 700 truenas-backup-status-to-uptimekuma.sh
chmod 600 truenas-backup-status-to-uptimekuma.conf
```

Für ein späteres Update des Skripts nur die erste `curl`-Zeile wiederholen. Die Konfig bleibt dabei unverändert.

### 3. Konfig ausfüllen

```sh
bash truenas-backup-status-to-uptimekuma.sh --list
```

`--list` zeigt alle Tasks mit ihrer ID. In `truenas-backup-status-to-uptimekuma.conf` steht pro Check eine Zeile:

```
# Typ     Ziel                             max_h  Push-URL
snapshot  2                                3      https://.../api/push/TOKEN   # nextcloud hourly
cloudsync 5                                26     https://.../api/push/TOKEN   # Storj
file      /mnt/tank01/vaultwarden-backups  26     https://.../api/push/TOKEN
```

`max_h` ist der Task-Rhythmus plus etwas Luft: stündlich 3, täglich 26, wöchentlich 170. Achtung: Snapshot-ID und Cloud-Sync-ID können gleich sein (beide 5). Der Typ am Zeilenanfang unterscheidet sie.

Die Push-URLs sind Zugangsdaten. Die Konfig gehört deshalb nicht ins Repo (`*.conf` steht in `.gitignore`).

### 4. Testen

```sh
bash truenas-backup-status-to-uptimekuma.sh --dry-run   # zeigt nur an, was gepusht würde
bash truenas-backup-status-to-uptimekuma.sh             # pusht wirklich
```

Danach sollten alle Monitore in Uptime Kuma grün sein. Exit-Code 0 bedeutet: alle Pushes sind angekommen, auch wenn ein Check DOWN ist. Den Alarm dafür schickt Uptime Kuma. Einen Exit-Code ungleich 0, und damit einen TrueNAS-Alert, gibt es nur bei einem Fehler in der Konfig oder wenn Uptime Kuma nicht erreichbar ist.

### 5. Cron Job in TrueNAS

**System > Advanced Settings > Cron Jobs > Add**

- Description: `Backup-Status an Uptime Kuma`
- Command: `bash /mnt/tank01/scripts/truenas-backup-status-to-uptimekuma.sh`
- Run As User: `root`
- Schedule: stündlich, z. B. Minute 15
- Hide Standard Output: an, Hide Standard Error: aus (dann mailt TrueNAS nur bei Fehlern im Skript selbst)

`bash` vor dem Pfad sorgt dafür, dass es auch auf einem Dataset mit `noexec` läuft.

## Fehlersuche

- **Ein Monitor ist rot mit "nicht gefunden":** Die ID in der Konfig passt nicht mehr, z. B. weil der Task neu angelegt wurde. `--list` zeigt die aktuelle ID.
- **"letzter Erfolg vor N h":** Der Task lief nicht mehr oder hat nichts erzeugt. In TrueNAS unter Data Protection nachsehen. Bei Snapshot-Tasks mit ausgeschaltetem "Allow taking empty snapshots" kann der letzte Snapshot älter sein, wenn sich nichts geändert hat. Dann `max_h` erhöhen.
- **vzdump meldet einen Gast, der gar nicht mehr existiert:** Er wurde vor weniger als dreimal `max_h` gelöscht. Nach etwa drei Wochen verschwindet er von selbst, oder man löscht seine alten Archive in Proxmox unter Storage NAS-SMB > Backups.
- **Alle Monitore rot ohne Nachricht:** Das Skript läuft nicht (Cron Job prüfen), oder TrueNAS erreicht Uptime Kuma nicht (`curl -I <Push-URL>` auf TrueNAS).
