# Uptime-Kuma-Statusseite aus einer Datei

Uptime Kuma kann seine Einstellungen nicht aus einer Datei lesen. `uptimekuma-statuspage.py` übernimmt das für die Gruppen einer Statusseite: In `uptimekuma-statuspage.yaml` steht, welcher Monitor in welcher Gruppe erscheint, und das Skript überträgt das per API. Getestet mit Uptime Kuma 2.5.5.

Das Skript ändert nur die Gruppen und ihre Reihenfolge. Titel, Beschreibung, CSS, Logo und die Monitore selbst bleiben unverändert. **Monitore anlegen, ändern oder löschen geht weiter nur im GUI.** Die YAML-Datei legt fest, wo sie auf der Statusseite erscheinen.

## Einmalig einrichten (Mac)

```sh
python3 -m venv ~/.venvs/kuma
~/.venvs/kuma/bin/pip install "python-socketio[client]" pyyaml
```

Das Skript muss Uptime Kuma erreichen, also im Heimnetz laufen. Das Repo liegt auf dem Mac unter `~/Documents/Code/shell`.

## Ablauf: einen Monitor einsortieren

1. **Monitor im GUI anlegen** (oder umbenennen). Den Namen genau so übernehmen, wie er dort steht.
2. **Repo aktualisieren:**
   ```sh
   cd ~/Documents/Code/shell && git pull
   ```
3. **YAML bearbeiten:** den Namen in `uptimekuma-statuspage.yaml` unter der passenden Gruppe eintragen (siehe [Gruppen](#gruppen)).
4. **Testen, ohne etwas zu ändern:**
   ```sh
   ~/.venvs/kuma/bin/python uptimekuma-statuspage.py
   ```
   Prüfen:
   - Kein Abbruch mit „passt nicht zu den Monitoren“. Sonst den Namen korrigieren, das Skript schlägt ähnliche Namen vor.
   - Keine Zeile „Nicht mehr auf der Statusseite“, außer du willst den Monitor wirklich entfernen.
   - Keine Zeile „Monitore ohne Gruppe“. Die dort genannten Monitore fehlen noch in der YAML.
5. **Speichern:**
   ```sh
   ~/.venvs/kuma/bin/python uptimekuma-statuspage.py --apply
   ```
6. **YAML committen und pushen**, damit die Datei zum Stand in Uptime Kuma passt:
   ```sh
   git commit -am "uptimekuma-statuspage.yaml: <Monitor> ergänzt" && git push
   ```

Benutzer und Passwort fragt das Skript ab, bei aktivierter 2FA auch den Code. Alternativ kannst du sie in `KUMA_USER` und `KUMA_PASSWORD` setzen. In die YAML-Datei gehören sie nicht.

Die Anmeldung kann einige Sekunden dauern, weil Uptime Kuma dabei die Historie aller Monitore mitschickt. Das Skript wartet bis zu 5 Minuten.

## Aufruf

| Aufruf | Wirkung |
|---|---|
| `uptimekuma-statuspage.py` | zeigt, was sich ändern würde, ändert nichts |
| `uptimekuma-statuspage.py --apply` | speichert die Gruppen |
| `uptimekuma-statuspage.py --export` | gibt die aktuelle Statusseite als YAML aus |
| `uptimekuma-statuspage.py andere.yaml` | nimmt eine andere YAML-Datei, z. B. für eine zweite Statusseite |
| `--url …`, `--slug …` | überschreibt `url` bzw. `slug` aus der YAML-Datei |

Vor jedem Aufruf steht `~/.venvs/kuma/bin/python`.

In der Vorschau steht neben jedem Monitor, was sich ändert: `(neu)` heißt, er war bisher nicht auf der Statusseite. `(vorher X)` heißt, er war bisher in Gruppe X. Ohne Zusatz bleibt er, wo er ist.

Exit-Code: 0 = in Ordnung, 1 = YAML passt nicht zu den Monitoren, 2 = Verbindung, Anmeldung oder Speichern fehlgeschlagen.

## Die YAML-Datei

```yaml
url: https://uptimekuma.mythenstrasse56.net
slug: details          # der Teil nach /status/ in der URL

groups:
  Netzwerk:
    - Pihole DNS Primary
    - 37               # Monitor-ID statt Name, falls zwei Monitore gleich heißen
  Dienste:
    - Glance
```

- Die Gruppen erscheinen in der Reihenfolge der Datei, die Monitore darin ebenso.
- Die Namen müssen genau wie in Uptime Kuma geschrieben sein, inklusive Groß- und Kleinschreibung.
- Ein Monitor darf nur in einer Gruppe stehen.
- Eine Gruppe, die in der Datei fehlt, wird von der Statusseite gelöscht. Die Monitore darin bleiben in Uptime Kuma erhalten.
- Ordner aus dem Dashboard (Monitor-Typ „Group“, z. B. „Tasks“) gehören nicht in die Datei. Das Skript meldet sie auch nicht als fehlend.

Die Monitor-ID steht in der Adresszeile, wenn man den Monitor im GUI öffnet (`/dashboard/37`).

## Gruppen

Die Regel lautet: **Was andere brauchen, steht weiter oben.** Fällt etwas in einer oberen Gruppe aus, sind rote Monitore weiter unten oft nur Folgefehler.

| Gruppe | Was hinein gehört | Beispiele |
|---|---|---|
| Netzwerk | Router, Switch, WLAN, DNS | Unifi-Geräte, Pihole DNS, Lokale DNS-Namen |
| Plattform | Proxmox-Hosts, NAS und Container, auf denen Dienste laufen | Proxmox Node 0X HTTPS, TrueNas, Pihole Ping |
| Dienste | Weboberflächen, die du selbst benutzt | Glance, Home Assistant, NextCloud, VaultWarden |
| Geräte | Geräte ohne eigenen Dienst im Homelab | HomePods, Velux, Zigbee-Stick, eBUSd, Huawei Emma |
| Jobs | Push-Monitore von Cronjobs und Backups | Ansible Updates, Proxmox vzdump, TrueNAS-Snapshots |

Ein Dienst mit zwei Monitoren wird aufgeteilt: Pi-hole DNS gehört zu Netzwerk, der Ping auf den Pi-hole-Container zu Plattform.

## Aktuellen Stand sichern

```sh
~/.venvs/kuma/bin/python uptimekuma-statuspage.py --export > aktuell.yaml
```

Die Ausgabe hat dasselbe Format wie die YAML-Datei, nur ohne Kommentare. Sie eignet sich als Sicherung vor größeren Umbauten und als Ausgangspunkt für eine neue Statusseite.
