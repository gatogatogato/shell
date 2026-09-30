# Uptime-Kuma-Monitore aus dem Inventar

`uptimekuma-sync.py` legt Monitore in Uptime Kuma automatisch an, damit nicht jeder Host von Hand
gepflegt werden muss. Die Liste kommt aus dem Inventar (`http://debian-inventar.lan:8080/api/devices`):

- **Ping** für jeden Host im statischen Bereich oder mit DHCP-Reservierung, der einen DNS-Namen hat
- **HTTPS** für jede aktive Domain im Nginx Proxy Manager (401/403 der Access-Liste zählt als erreichbar)

Die Monitore landen im Gruppen-Monitor „Automatisch (Inventar)“ und bekommen den Tag `inventar`.
Auf der Statusseite `details` erscheinen sie über `- tag: inventar` in `uptimekuma-statuspage.yaml`.

**Was das Skript nie tut:**
- Monitore ohne den Tag `inventar` ändern. Überwacht schon ein Monitor von Hand dasselbe Ziel
  (gleicher Hostname bzw. gleiche URL), wird kein zweiter angelegt.
- Monitore löschen. Verschwindet ein Ziel aus dem Inventar, wird sein Monitor nur pausiert;
  taucht es wieder auf, läuft er weiter. Löschen geht im GUI.

Neue Monitore übernehmen die Einstellungen eines vorhandenen Monitors gleichen Typs und die
Benachrichtigungen, die in Uptime Kuma als „Standard“ markiert sind (Pushover).

## Einrichten

Dieselbe venv wie für die Statusseite (`uptimekuma-statuspage.md`), ausführen auf dem Mac im Heimnetz.

## Ablauf

```sh
cd ~/Documents/Code/shell && git pull
~/.venvs/kuma/bin/python uptimekuma-sync.py            # zeigt nur, was passieren würde
~/.venvs/kuma/bin/python uptimekuma-sync.py --apply    # anlegen / pausieren
~/.venvs/kuma/bin/python uptimekuma-statuspage.py --apply   # neue Monitore auf die Statusseite
```

Der Probelauf nennt, wie viele Ziele es gibt, welche schon von Hand überwacht sind und was neu
angelegt, wieder aktiviert oder pausiert würde. Gehört etwas nicht überwacht (z. B. debian-hercules,
das meist aus ist), in `uptimekuma-sync.yaml` unter `exclude` eintragen.

Zugang wie beim Statuspage-Skript über `KUMA_USER`/`KUMA_PASSWORD` oder Abfrage.
