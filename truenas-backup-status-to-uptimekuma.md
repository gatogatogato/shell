# TrueNAS-Backups in Uptime Kuma

`truenas-backup-status-to-uptimekuma.sh` läuft stündlich auf TrueNAS. Es prüft die Backup-Tasks und meldet jeden per Push an einen eigenen Monitor in Uptime Kuma. So sieht man die TrueNAS-Backups dort neben den anderen Cronjobs (Ansible-Updates, Vaultwarden-Backup) und bekommt bei Fehlern eine Pushover-Meldung.

## Was geprüft wird

| Typ in der Konfig | Quelle | DOWN, wenn |
|---|---|---|
| `snapshot` | Periodic Snapshot Task (`pool.snapshottask.query`) | letzter Lauf mit Fehler, oder letzter Erfolg älter als `max_h` |
| `cloudsync` | Cloud Sync Task, z. B. Storj (`cloudsync.query`) | Job `FAILED`/`ABORTED`, oder letzter Erfolg älter als `max_h` |
| `cloudbackup` | TrueCloud Backup Task (`cloud_backup.query`) | wie oben |
| `replication` | Replication Task (`replication.query`) | wie oben |
| `rsync` | Rsync Task (`rsynctask.query`) | wie oben |
| `file` | ein Ordner, z. B. `/mnt/tank01/vaultwarden-backups` | keine Datei, neueste Datei leer oder älter als `max_h` |

Ein Task, der gerade läuft, gilt als UP. Den Fehlertext von TrueNAS schickt das Skript als Nachricht mit, er steht dann in Uptime Kuma und in der Pushover-Meldung.

Das Skript bewertet selbst, ob ein Backup zu alt ist, und schickt dann sofort DOWN. Uptime Kuma merkt über das Heartbeat-Intervall nur noch, wenn das Skript gar nicht mehr läuft.

**Vaultwarden hat damit zwei Monitore, und beide sind sinnvoll.** Der Push aus dem Backup-Skript auf dem Vaultwarden-Container (`HC_URL`) meldet, dass das Backup dort gelaufen ist. Der `file`-Check hier meldet, dass die Datei wirklich auf TrueNAS angekommen ist.

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
- **Alle Monitore rot ohne Nachricht:** Das Skript läuft nicht (Cron Job prüfen), oder TrueNAS erreicht Uptime Kuma nicht (`curl -I <Push-URL>` auf TrueNAS).
