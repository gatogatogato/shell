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

## Wann ausführen

Das Skript läuft **nicht automatisch**, sondern von Hand auf dem Mac. Es braucht das Kuma-Passwort,
das auf keinem Server liegen soll, und jede Änderung soll man vorher im Probelauf sehen. Starten:

- nach einem neuen Host mit fester IP oder DHCP-Reservierung (neuer Container, neues Gerät),
- nach einer neuen oder abgeschalteten Domain im Nginx Proxy Manager,
- wenn im Inventar ein Gerät verschwunden ist (dann pausiert es dessen Monitor).

Ein Anlass ist auch die Warnung „Neues Gerät“ im Inventar, sobald das Gerät Name und DNS hat.

## Ablauf

```sh
cd ~/Documents/Code/shell && git pull
~/.venvs/kuma/bin/python uptimekuma-sync.py            # zeigt nur, was passieren würde
~/.venvs/kuma/bin/python uptimekuma-sync.py --apply    # anlegen / pausieren
~/.venvs/kuma/bin/python uptimekuma-statuspage.py --apply   # neue Monitore auf die Statusseite
```

Der Probelauf nennt, wie viele Ziele es gibt, welche schon von Hand überwacht sind und was neu
angelegt, wieder aktiviert oder pausiert würde. Gehört etwas nicht überwacht, in `uptimekuma-sync.yaml`
unter `exclude` eintragen (siehe unten).

## Ausnahmen

`exclude` nimmt DNS-Namen, IPs oder NPM-Domains. Ein DNS-Name oder eine IP verhindert den Ping-Monitor
eines Hosts, eine Domain den HTTPS-Monitor. Achtung: Ist der DNS-Name eines Hosts gleichzeitig eine
NPM-Domain, fallen mit dem Namen beide weg; dann die IP eintragen, sie betrifft nur den Ping.
Ist ein Monitor schon angelegt und kommt sein Ziel später in `exclude`, pausiert ihn der nächste Lauf.

Stand 30.09.2026 (erster Probelauf: 72 Ziele, 8 davon schon von Hand überwacht):

| Eintrag | Warum kein Monitor |
|---|---|
| `debian-hercules.lan` | Braucht viel CPU und ist deshalb absichtlich meist aus, wäre dauernd rot. |
| `uptimekuma.mythenstrasse56.net` | Kuma kann sich nicht sinnvoll selbst überwachen: Fällt es aus, meldet es nichts mehr. |
| `192.168.1.78` | NPM-Container. Sein erster DNS-Name ist `npm.mythenstrasse56.net`, der Ping-Monitor wäre doppelt zum HTTPS-Monitor. Per IP ausgeschlossen, damit HTTPS bleibt. |
| `amazon-fire-hd.lan` | Tablet schläft, WLAN geht dann aus. |
| `miele-w1.lan`, `siemens-dishwasher.lan`, `electrolux-ir.lan` | Haushaltsgeräte sind oft nur im WLAN, solange sie laufen. |
| `stehpult-office.lan` | Steuerung ist nicht dauernd im WLAN. |
| `dreame-vacuum-r9542b.lan`, `dreame_vacuum_p2029.lan`, `dreame_vacuum_r2250.lan` | Saugroboter schlafen in der Station. |
| `reolink-terasse.lan` | Akku-Kamera geht oft in den Schlafmodus, die Pings kosten Batterie (Monitor am 05.10.2026 von Hand gelöscht). |

Die Geräte aus den letzten vier Zeilen sind Vermutungen: Ist eines davon doch immer erreichbar,
den Eintrag löschen, dann legt der nächste `--apply` den Monitor an.

Zugang wie beim Statuspage-Skript über `KUMA_USER`/`KUMA_PASSWORD` oder Abfrage.
