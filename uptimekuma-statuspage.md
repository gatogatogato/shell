# Uptime-Kuma-Statusseite aus einer Datei

Uptime Kuma kann seine Einstellungen nicht aus einer Datei lesen. `uptimekuma-statuspage.py` übernimmt das für die Gruppen einer Statusseite: In `uptimekuma-statuspage.yaml` steht, welcher Monitor in welcher Gruppe erscheint, und das Skript überträgt das per API. Getestet mit Uptime Kuma 2.5.5.

Das Skript ändert nur die Gruppen und ihre Reihenfolge. Titel, Beschreibung, CSS, Logo und die Monitore selbst bleiben unverändert.

## Einmalig einrichten (Mac)

```sh
python3 -m venv ~/.venvs/kuma
~/.venvs/kuma/bin/pip install "python-socketio[client]" pyyaml
```

Das Skript muss Uptime Kuma erreichen, also im Heimnetz laufen.

## Benutzen

```sh
cd ~/shell
~/.venvs/kuma/bin/python uptimekuma-statuspage.py            # zeigt nur, was sich ändern würde
~/.venvs/kuma/bin/python uptimekuma-statuspage.py --apply    # speichert
```

Benutzer und Passwort fragt das Skript ab, bei aktivierter 2FA auch den Code. Alternativ kannst du sie in `KUMA_USER` und `KUMA_PASSWORD` setzen. In die YAML-Datei gehören sie nicht.

Ohne `--apply` zeigt das Skript jede Gruppe mit ihren Monitoren. Neben jedem verschobenen Monitor steht, wo er vorher war. Außerdem listet es alle Monitore, die auf der Statusseite nicht vorkommen.

## Die YAML-Datei

```yaml
url: https://uptimekuma.mythenstrasse56.net
slug: details          # der Teil nach /status/ in der URL

groups:
  Netzwerk:
    - Pi-hole DNS .99
    - 37               # Monitor-ID statt Name, falls zwei Monitore gleich heißen
  Dienste:
    - Glance
```

- Die Gruppen erscheinen in der Reihenfolge der Datei, die Monitore darin ebenso.
- Die Namen müssen genau wie in Uptime Kuma geschrieben sein. Findet das Skript einen Namen nicht, bricht es ohne Änderung ab und schlägt ähnliche Namen vor.
- Eine Gruppe, die in der Datei fehlt, wird von der Statusseite gelöscht. Die Monitore darin bleiben erhalten.

Die aktuelle Statusseite als YAML-Datei ausgeben, zum Beispiel als Ausgangspunkt:

```sh
~/.venvs/kuma/bin/python uptimekuma-statuspage.py --export > aktuell.yaml
```

Für eine andere Statusseite eine zweite YAML-Datei anlegen und beim Aufruf angeben:

```sh
~/.venvs/kuma/bin/python uptimekuma-statuspage.py status.yaml --apply
```
