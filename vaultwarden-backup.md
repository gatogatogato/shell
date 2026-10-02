# Vaultwarden-Backup

`vaultwarden-backup.sh` sichert jede Nacht um 00:30 das Datenverzeichnis von Vaultwarden
(Alpine-Container `debian-vaultwarden.lan`) per `scp` auf TrueNAS. Installiert wird es mit
Ansible: `run.sh vaultwarden-backup`, beschrieben in `docs/vaultwarden-backup.md` im
ansible-Repo.

## Ablauf

1. Vaultwarden stoppen, `/var/lib/vaultwarden` komplett packen (Datenbank, `rsa_key*`,
   Anhänge, Sends, `config.json`), Vaultwarden wieder starten. Der Dienst ist dabei ein paar
   Sekunden weg, startet aber auch bei einem Fehler wieder.
2. Archiv prüfen: lesbar, enthält `db.sqlite3`, grösser als 100 kB.
3. Per `scp` nach `vaultwarden@truenas.lan:/mnt/tank01/vaultwarden-backups/vaultwarden`
   kopieren und die Grösse dort gegenprüfen.
4. Erst danach aufräumen: lokal älter als 3 Tage, auf TrueNAS älter als 90 Tage.
5. Push an Uptime Kuma. Bleibt er aus, meldet der Monitor DOWN.

Zusätzlich prüft `truenas-backup-status-to-uptimekuma.sh` auf TrueNAS das Alter der neuesten
Datei, und TrueNAS macht Snapshots des Datasets.

## Konfig

Die Push-URL ist ein Secret und gehört nicht in dieses öffentliche Repo. Sie steht im
Container in `/etc/vaultwarden-backup.conf` (root, `0600`), Vorlage
`vaultwarden-backup.conf.example`. Dort lassen sich auch alle anderen Variablen des
Skripts überschreiben.

## Restore

Im Container (oder einem frischen Alpine-Container mit Vaultwarden) als root:

```
scp vaultwarden@truenas.lan:/mnt/tank01/vaultwarden-backups/vaultwarden/vaultwarden-backup-<DATUM>.tar.gz /root/
rc-service vaultwarden stop
mv /var/lib/vaultwarden /var/lib/vaultwarden.alt
tar -C /var/lib -xzf /root/vaultwarden-backup-<DATUM>.tar.gz
chown -R vaultwarden:vaultwarden /var/lib/vaultwarden
rc-service vaultwarden start
```

Danach im Web-Tresor anmelden und prüfen, ob Einträge und Anhänge da sind. Klappt alles,
`/var/lib/vaultwarden.alt` löschen.
