#!/usr/bin/env python3
# Setzt die Gruppen einer oder mehrerer Uptime-Kuma-Statusseiten aus einer YAML-Datei.
# Getestet mit Uptime Kuma 2.5.5, Doku: uptimekuma-statuspage.md
#
#   uptimekuma-statuspage.py            zeigen, was sich aendern wuerde (aendert nichts)
#   uptimekuma-statuspage.py --apply    Gruppen wirklich speichern
#   uptimekuma-statuspage.py --export --slug details   aktuelle Statusseite als YAML
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
LOGIN_TIMEOUT = 300


def die(msg):
    print(f"FEHLER: {msg}", file=sys.stderr)
    sys.exit(2)


def connect(url, debug=False):
    """Meldet sich per Socket.IO an und liefert (client, {id: monitor})."""
    user = os.environ.get("KUMA_USER") or input("Uptime-Kuma-Benutzer: ")
    password = os.environ.get("KUMA_PASSWORD") or getpass.getpass("Passwort: ")
    login = {"username": user, "password": password, "token": ""}

    # Ohne automatisches Neuverbinden: eine neue Verbindung waere nicht angemeldet
    sio = socketio.Client(reconnection=False, logger=debug, engineio_logger=debug)
    monitors = {}
    ready = threading.Event()   # Server hat seine Handler registriert
    changed = threading.Event() # Antwort auf den Login ist da
    got_list = threading.Event()
    answer = {}
    lost = threading.Event()

    @sio.on("info")
    def on_info(data):
        ready.set()

    @sio.on("monitorList")
    def on_monitor_list(data):
        monitors.clear()
        monitors.update({int(k): v for k, v in data.items()})
        got_list.set()

    @sio.on("disconnect")
    def on_disconnect(*args):
        lost.set()
        changed.set()

    def on_login(res):
        answer.update(res)
        changed.set()

    try:
        sio.connect(url, wait_timeout=TIMEOUT)
    except socketio.exceptions.ConnectionError as e:
        die(f"keine Verbindung zu {url}: {e}")
    # Uptime Kuma schickt "info", bevor es auf "login" hoert; frueher gesendet geht verloren
    if not ready.wait(TIMEOUT):
        die("Server antwortet nicht (kein info)")

    # Die Login-Antwort kommt erst, nachdem der Server die Heartbeats aller Monitore
    # geschickt hat. Solange er damit beschaeftigt ist, beantwortet er andere
    # Anfragen nicht rechtzeitig, deshalb auf die Antwort warten.
    print("Anmelden (kann eine Weile dauern) ...", file=sys.stderr)
    sio.emit("login", login, callback=on_login)
    waited = 0
    while not answer.get("ok"):
        if not changed.wait(30):
            waited += 30
            if waited >= LOGIN_TIMEOUT:
                die(f"keine Antwort auf die Anmeldung nach {waited} s")
            print(f"  warte seit {waited} s (Verbindung: {sio.transport()}) ...", file=sys.stderr)
            continue
        changed.clear()
        if lost.is_set():
            die("Verbindung zum Server wurde getrennt. Laeuft Uptime Kuma hinter einem "
                "Reverse Proxy, direkt verbinden, z. B. --url http://debian-uptimekuma.lan:3001")
        if answer.get("tokenRequired"):
            answer.clear()
            login["token"] = input("2FA-Code: ").strip()
            sio.emit("login", login, callback=on_login)
        elif answer and not answer.get("ok"):
            die(f"Anmeldung fehlgeschlagen: {answer.get('msg')}")
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


def show_changes(slug, groups, before, monitors):
    """Gibt aus, was sich auf einer Statusseite aendert. Liefert (alte Eintraege, alte Gruppen-IDs)."""
    old_group, old_entry, old_group_id = {}, {}, {}
    for g in before:
        old_group_id[g["name"].strip()] = g["id"]
        for m in g["monitorList"]:
            old_group[m["id"]] = g["name"].strip()
            old_entry[m["id"]] = m

    print(f"== Statusseite {slug} ==")
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
    # Gruppen-Monitore aus dem Dashboard gehoeren nicht auf die Statusseite
    missing = sorted(
        (i for i in monitors.keys() - placed - set(dropped) if monitors[i].get("type") != "group"),
        key=lambda i: monitors[i]["name"].lower(),
    )
    if missing:
        print("Monitore ohne Gruppe (erscheinen nicht): " + ", ".join(monitors[i]["name"] for i in missing))
    return old_entry, old_group_id


def save(sio, url, slug, groups, old_entry, old_group_id):
    res = sio.call("getStatusPage", slug, timeout=LOGIN_TIMEOUT)
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
    res = sio.call("saveStatusPage", (slug, config, config.get("icon") or "", public_groups), timeout=LOGIN_TIMEOUT)
    if not res.get("ok"):
        die(f"Speichern fehlgeschlagen ({slug}): {res.get('msg')}")
    print(f"Gespeichert: {url}/status/{slug}")


def main():
    ap = argparse.ArgumentParser(description="Gruppen einer Uptime-Kuma-Statusseite aus YAML setzen")
    ap.add_argument("config", nargs="?", default=DEFAULT_CONFIG, help="YAML-Datei (Standard: neben dem Skript)")
    ap.add_argument("--apply", action="store_true", help="Aenderungen speichern")
    ap.add_argument("--export", action="store_true", help="aktuelle Statusseite als YAML ausgeben")
    ap.add_argument("--url", help="Uptime-Kuma-URL (statt url aus der YAML-Datei)")
    ap.add_argument("--slug", help="Statusseite (statt slug aus der YAML-Datei)")
    ap.add_argument("--debug", action="store_true", help="Socket.IO-Verkehr ausgeben")
    args = ap.parse_args()

    cfg = {}
    if os.path.exists(args.config):
        with open(args.config, encoding="utf-8") as f:
            cfg = yaml.safe_load(f) or {}
    elif not args.export:
        die(f"{args.config} nicht gefunden")
    url = (args.url or cfg.get("url") or "").rstrip("/")
    # slug darf eine Liste sein: dann bekommen alle Seiten dieselben Gruppen
    slugs = [args.slug] if args.slug else cfg.get("slug") or []
    if isinstance(slugs, str):
        slugs = [slugs]
    if not url or not slugs:
        die("url und slug fehlen (in der YAML-Datei oder per --url/--slug)")

    if args.export:
        if len(slugs) > 1:
            die(f"--export braucht eine Statusseite, z. B. --slug {slugs[0]}")
        export(url, slugs[0])
        return

    wanted = cfg.get("groups") or {}
    if not wanted:
        die("keine Gruppen in der YAML-Datei")

    before = {slug: current_groups(url, slug) for slug in slugs}
    sio, monitors = connect(url, args.debug)
    try:
        groups, errors = resolve(wanted, monitors)
        if errors:
            print("Die YAML-Datei passt nicht zu den Monitoren in Uptime Kuma:", file=sys.stderr)
            for e in errors:
                print(f"  - {e}", file=sys.stderr)
            sys.exit(1)

        old = {}
        for i, slug in enumerate(slugs):
            if i:
                print()
            old[slug] = show_changes(slug, groups, before[slug], monitors)

        if not args.apply:
            print("\nNichts geaendert. Mit --apply speichern.")
            return
        print()
        for slug in slugs:
            save(sio, url, slug, groups, *old[slug])
    finally:
        sio.disconnect()


if __name__ == "__main__":
    main()
