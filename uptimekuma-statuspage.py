#!/usr/bin/env python3
# Setzt die Gruppen einer Uptime-Kuma-Statusseite aus einer YAML-Datei.
# Getestet mit Uptime Kuma 2.5.5, Doku: uptimekuma-statuspage.md
#
#   uptimekuma-statuspage.py            zeigen, was sich aendern wuerde (aendert nichts)
#   uptimekuma-statuspage.py --apply    Gruppen wirklich speichern
#   uptimekuma-statuspage.py --export   aktuelle Statusseite als YAML ausgeben
#
# Zugang: KUMA_USER und KUMA_PASSWORD aus der Umgebung, sonst wird gefragt.
# Passwoerter gehoeren nicht in die YAML-Datei.

import argparse
import difflib
import getpass
import os
import sys
import threading

try:
    import requests
    import socketio
    import yaml
except ImportError:
    sys.exit('FEHLER: Python-Pakete fehlen: pip install "python-socketio[client]" pyyaml')

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DEFAULT_CONFIG = os.path.join(SCRIPT_DIR, "uptimekuma-statuspage.yaml")
TIMEOUT = 30


def die(msg):
    print(f"FEHLER: {msg}", file=sys.stderr)
    sys.exit(2)


def connect(url):
    """Meldet sich per Socket.IO an und liefert (client, {id: monitor})."""
    sio = socketio.Client()
    monitors = {}
    got_list = threading.Event()

    @sio.on("monitorList")
    def on_monitor_list(data):
        monitors.clear()
        monitors.update({int(k): v for k, v in data.items()})
        got_list.set()

    try:
        sio.connect(url, wait_timeout=TIMEOUT)
    except socketio.exceptions.ConnectionError as e:
        die(f"keine Verbindung zu {url}: {e}")

    user = os.environ.get("KUMA_USER") or input("Uptime-Kuma-Benutzer: ")
    password = os.environ.get("KUMA_PASSWORD") or getpass.getpass("Passwort: ")
    login = {"username": user, "password": password, "token": ""}
    res = sio.call("login", login, timeout=TIMEOUT)
    if res.get("tokenRequired"):
        login["token"] = input("2FA-Code: ").strip()
        res = sio.call("login", login, timeout=TIMEOUT)
    if not res.get("ok"):
        die(f"Anmeldung fehlgeschlagen: {res.get('msg')}")

    if not got_list.wait(TIMEOUT):
        die("Monitorliste nicht erhalten")
    return sio, monitors


def current_groups(url, slug):
    """Aktuelle Gruppen der Statusseite, wie sie auch der Browser laedt."""
    try:
        r = requests.get(f"{url}/api/status-page/{slug}", timeout=TIMEOUT)
    except requests.RequestException as e:
        die(f"keine Verbindung zu {url}: {e}")
    if r.status_code != 200:
        die(f"Statusseite '{slug}' nicht lesbar (HTTP {r.status_code})")
    return r.json()["publicGroupList"]


def export(url, slug):
    groups = {g["name"].strip(): [m["name"] for m in g["monitorList"]] for g in current_groups(url, slug)}
    print(yaml.safe_dump({"url": url, "slug": slug, "groups": groups}, allow_unicode=True, sort_keys=False), end="")


def resolve(wanted, monitors):
    """Ordnet Namen (oder Zahlen = Monitor-ID) den IDs zu. Liefert ({gruppe: [id]}, fehler)."""
    by_name = {}
    for mid, m in monitors.items():
        by_name.setdefault(m["name"], []).append(mid)

    result, errors, seen = {}, [], {}
    for group, items in wanted.items():
        ids = []
        for item in items or []:
            if isinstance(item, int):
                if item not in monitors:
                    errors.append(f"[{group}] Monitor-ID {item} gibt es nicht")
                    continue
                mid = item
            else:
                found = by_name.get(item, [])
                if len(found) != 1:
                    if found:
                        hint = f"mehrdeutig, IDs {found}; statt des Namens die ID eintragen"
                    else:
                        close = difflib.get_close_matches(item, by_name, n=3, cutoff=0.5)
                        hint = "nicht gefunden" + (f", meintest du: {', '.join(close)}" if close else "")
                    errors.append(f"[{group}] '{item}': {hint}")
                    continue
                mid = found[0]
            if mid in seen:
                errors.append(f"[{group}] '{monitors[mid]['name']}' steht schon in [{seen[mid]}]")
                continue
            seen[mid] = group
            ids.append(mid)
        result[group] = ids
    return result, errors


def main():
    ap = argparse.ArgumentParser(description="Gruppen einer Uptime-Kuma-Statusseite aus YAML setzen")
    ap.add_argument("config", nargs="?", default=DEFAULT_CONFIG, help="YAML-Datei (Standard: neben dem Skript)")
    ap.add_argument("--apply", action="store_true", help="Aenderungen speichern")
    ap.add_argument("--export", action="store_true", help="aktuelle Statusseite als YAML ausgeben")
    ap.add_argument("--url", help="Uptime-Kuma-URL (statt url aus der YAML-Datei)")
    ap.add_argument("--slug", help="Statusseite (statt slug aus der YAML-Datei)")
    args = ap.parse_args()

    cfg = {}
    if os.path.exists(args.config):
        with open(args.config, encoding="utf-8") as f:
            cfg = yaml.safe_load(f) or {}
    elif not args.export:
        die(f"{args.config} nicht gefunden")
    url = (args.url or cfg.get("url") or "").rstrip("/")
    slug = args.slug or cfg.get("slug")
    if not url or not slug:
        die("url und slug fehlen (in der YAML-Datei oder per --url/--slug)")

    if args.export:
        export(url, slug)
        return

    wanted = cfg.get("groups") or {}
    if not wanted:
        die("keine Gruppen in der YAML-Datei")

    before = current_groups(url, slug)
    sio, monitors = connect(url)
    try:
        groups, errors = resolve(wanted, monitors)
        if errors:
            print("Die YAML-Datei passt nicht zu den Monitoren in Uptime Kuma:", file=sys.stderr)
            for e in errors:
                print(f"  - {e}", file=sys.stderr)
            sys.exit(1)

        # Bisherige Gruppe und Einstellungen (Link anzeigen) je Monitor merken
        old_group, old_entry, old_group_id = {}, {}, {}
        for g in before:
            old_group_id[g["name"].strip()] = g["id"]
            for m in g["monitorList"]:
                old_group[m["id"]] = g["name"].strip()
                old_entry[m["id"]] = m

        for group, ids in groups.items():
            print(f"{group}:")
            for mid in ids:
                prev = old_group.get(mid)
                note = "" if prev == group else ("  (neu)" if prev is None else f"  (vorher {prev})")
                print(f"  - {monitors[mid]['name']}{note}")
        placed = {mid for ids in groups.values() for mid in ids}
        dropped = sorted(old_group.keys() - placed)
        for mid in dropped:
            print(f"Nicht mehr auf der Statusseite: {old_entry[mid]['name']}")
        missing = sorted(monitors.keys() - placed - set(dropped), key=lambda i: monitors[i]["name"].lower())
        if missing:
            print("Monitore ohne Gruppe (erscheinen nicht): " + ", ".join(monitors[i]["name"] for i in missing))

        if not args.apply:
            print("\nNichts geaendert. Mit --apply speichern.")
            return

        res = sio.call("getStatusPage", slug, timeout=TIMEOUT)
        if not res.get("ok"):
            die(f"Statusseite '{slug}' nicht gefunden: {res.get('msg')}")
        config = res["config"]

        public_groups = []
        for group, ids in groups.items():
            entries = []
            for mid in ids:
                entry = {"id": mid}
                old = old_entry.get(mid, {})
                if "sendUrl" in old:
                    entry["sendUrl"] = old["sendUrl"]
                if old.get("url") is not None:
                    entry["url"] = old["url"]
                entries.append(entry)
            item = {"name": group, "monitorList": entries}
            if group in old_group_id:
                item["id"] = old_group_id[group]
            public_groups.append(item)

        # Das Logo geht unveraendert als URL zurueck, wie im Browser beim Speichern
        res = sio.call("saveStatusPage", (slug, config, config.get("icon") or "", public_groups), timeout=TIMEOUT)
        if not res.get("ok"):
            die(f"Speichern fehlgeschlagen: {res.get('msg')}")
        print(f"\nGespeichert: {url}/status/{slug}")
    finally:
        sio.disconnect()


if __name__ == "__main__":
    main()
