#!/usr/bin/env python3
# Legt Uptime-Kuma-Monitore automatisch aus dem Inventar an (debian-inventar).
# Getestet gegen die Socket.IO-API von Uptime Kuma 2.5.5, Doku: uptimekuma-sync.md
#
#   uptimekuma-sync.py            zeigen, was sich aendern wuerde (aendert nichts)
#   uptimekuma-sync.py --apply    Monitore wirklich anlegen / pausieren
#
# Das Skript fasst nur Monitore mit dem Tag aus der YAML-Datei an (Standard: inventar).
# Von Hand angelegte Monitore bleiben unveraendert; zeigt schon einer auf dasselbe Ziel,
# wird kein zweiter angelegt. Faellt ein Ziel weg, wird sein Monitor pausiert, nie geloescht.
#
# Zugang: KUMA_USER und KUMA_PASSWORD aus der Umgebung, sonst wird gefragt.

import argparse
import copy
import importlib.util
import os
import sys

try:
    import requests
    import yaml
except ImportError:
    sys.exit('FEHLER: Python-Pakete fehlen: pip install "python-socketio[client]" pyyaml')

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DEFAULT_CONFIG = os.path.join(SCRIPT_DIR, "uptimekuma-sync.yaml")

# Anmeldung und Monitorliste wie in uptimekuma-statuspage.py
_spec = importlib.util.spec_from_file_location("statuspage", os.path.join(SCRIPT_DIR, "uptimekuma-statuspage.py"))
statuspage = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(statuspage)
die, TIMEOUT, SLOW = statuspage.die, statuspage.TIMEOUT, statuspage.LOGIN_TIMEOUT

# Felder, die ein neuer Monitor nicht von der Vorlage uebernimmt
NOT_COPIED = {"id", "name", "pathName", "parent", "tags", "hostname", "url", "description",
              "active", "forceInactive", "maintenance", "childrenIDs", "includeSensitiveData",
              "screenshot", "path", "weight", "kafkaProducerSaslOptions"}
# Falls es noch keinen Monitor dieses Typs als Vorlage gibt
DEFAULTS = {
    "interval": 60, "retryInterval": 60, "resendInterval": 0, "maxretries": 1, "timeout": 48,
    "upsideDown": False, "ignoreTls": False, "expiryNotification": False, "maxredirects": 10,
    "accepted_statuscodes": ["200-299"], "method": "GET", "httpBodyEncoding": "json",
    "packetSize": 56, "dns_resolve_type": "A", "dns_resolve_server": "1.1.1.1",
    "kafkaProducerBrokers": [], "kafkaProducerSaslOptions": {"mechanism": "None"},
    "kafkaProducerSsl": False, "kafkaProducerAllowAutoTopicCreation": False,
    "gamedigGivenPortOnly": True, "conditions": [], "rabbitmqNodes": [],
}


def load_config(path):
    if not os.path.exists(path):
        die(f"{path} nicht gefunden")
    with open(path, encoding="utf-8") as f:
        cfg = yaml.safe_load(f) or {}
    for key in ("url", "inventar", "group", "tag"):
        if not cfg.get(key):
            die(f"{key} fehlt in {path}")
    return cfg


def targets(cfg):
    """Was einen Monitor bekommen soll: {schluessel: (typ, name, ziel)} aus /api/devices."""
    try:
        r = requests.get(f"{cfg['inventar'].rstrip('/')}/api/devices", timeout=TIMEOUT)
        r.raise_for_status()
        devices = r.json()["devices"]
    except (requests.RequestException, ValueError, KeyError) as e:
        die(f"Inventar nicht lesbar ({cfg['inventar']}): {e}")
    exclude = {str(x).lower() for x in cfg.get("exclude") or []}
    found = {}
    for d in devices:
        reserved = any(x.get("reserved") for x in d["details"].get("unifi", []))
        if cfg.get("ping", True) and (d.get("range") == "static" or reserved) and d.get("dns"):
            host = d["dns"][0].lower()
            if host not in exclude and d.get("ip") not in exclude:
                found[f"ping:{host}"] = ("ping", f"Ping {host}", host)
        for proxy in d.get("proxy", []) if cfg.get("http", True) else []:
            for domain in proxy["domains"]:
                domain = domain.lower()
                if proxy.get("active") and domain not in exclude:
                    found[f"http:{domain}"] = ("http", f"HTTPS {domain}", f"https://{domain}")
    return found


def key_of(m):
    """Ziel eines vorhandenen Monitors im selben Format wie targets()."""
    if m.get("type") == "ping" and m.get("hostname"):
        return f"ping:{m['hostname'].lower()}"
    if m.get("type") in ("http", "keyword") and m.get("url"):
        url = m["url"].lower().rstrip("/")
        for prefix in ("https://", "http://"):
            if url.startswith(prefix):
                return f"http:{url[len(prefix):]}"
    return None


def has_tag(m, tag):
    return any(t.get("name") == tag for t in m.get("tags") or [])


def new_monitor(kind, name, target, parent, monitors, cfg, notifications):
    template = next((m for m in monitors.values() if m.get("type") == kind and not has_tag(m, cfg["tag"])), None)
    monitor = copy.deepcopy(DEFAULTS)
    if template:
        monitor.update({k: copy.deepcopy(v) for k, v in template.items() if k not in NOT_COPIED})
    monitor.update({
        "type": kind, "name": name, "parent": parent,
        "description": "Automatisch aus dem Inventar (uptimekuma-sync.py)",
        "interval": cfg.get("interval", 60), "retryInterval": cfg.get("interval", 60),
        "maxretries": cfg.get("retries", 1),
        # Benachrichtigungen, die in Uptime Kuma "Standard" sind, wie beim Anlegen im GUI
        "notificationIDList": {str(n["id"]): True for n in notifications if n.get("isDefault")},
    })
    if kind == "ping":
        monitor["hostname"] = target
    else:
        monitor["url"] = target
        # 401/403: Access-Liste im NPM, die Seite antwortet also
        monitor["accepted_statuscodes"] = ["200-299", "300-399", "401", "403"]
    return monitor


def call(sio, event, *args):
    data = args if len(args) > 1 else (args[0] if args else None)
    res = sio.call(event, data, timeout=SLOW)
    if not res.get("ok"):
        die(f"{event} fehlgeschlagen: {res.get('msg')}")
    return res


def tag_id(sio, tag, apply):
    tags = call(sio, "getTags").get("tags", [])
    found = next((t["id"] for t in tags if t["name"] == tag), None)
    if found or not apply:
        return found
    return call(sio, "addTag", {"name": tag, "color": "#2563eb", "new": True})["tag"]["id"]


def main():
    ap = argparse.ArgumentParser(description="Uptime-Kuma-Monitore aus dem Inventar anlegen")
    ap.add_argument("config", nargs="?", default=DEFAULT_CONFIG, help="YAML-Datei (Standard: neben dem Skript)")
    ap.add_argument("--apply", action="store_true", help="Monitore wirklich anlegen / pausieren")
    ap.add_argument("--debug", action="store_true", help="Socket.IO-Verkehr ausgeben")
    args = ap.parse_args()
    cfg = load_config(args.config)
    wanted = targets(cfg)

    sio, monitors = statuspage.connect(cfg["url"].rstrip("/"), args.debug)
    try:
        tag = cfg["tag"]
        existing = {}
        for mid, m in monitors.items():
            key = key_of(m)
            if key:
                existing.setdefault(key, []).append(mid)
        ours = {mid for mid, m in monitors.items() if has_tag(m, tag) and m.get("type") != "group"}

        create = sorted((k for k in wanted if k not in existing), key=lambda k: wanted[k][1])
        manual = sorted(k for k in wanted if k in existing and not set(existing[k]) & ours)
        resume = sorted(mid for mid in ours if key_of(monitors[mid]) in wanted and not monitors[mid].get("active"))
        pause = sorted((mid for mid in ours if key_of(monitors[mid]) not in wanted and monitors[mid].get("active")),
                       key=lambda mid: monitors[mid]["name"])

        print(f"Aus dem Inventar: {len(wanted)} Ziele, davon {len(manual)} schon von Hand ueberwacht, "
              f"{len(wanted) - len(manual) - len(create)} schon automatisch.")
        for k in create:
            print(f"  neu: {wanted[k][1]}")
        for mid in resume:
            print(f"  wieder aktiv: {monitors[mid]['name']}")
        for mid in pause:
            print(f"  pausieren (Ziel nicht mehr im Inventar): {monitors[mid]['name']}")
        if not (create or resume or pause):
            print("Nichts zu tun.")
            return
        if not args.apply:
            print("\nNichts geaendert. Mit --apply anlegen.")
            return

        group = next((mid for mid, m in monitors.items() if m.get("type") == "group" and m["name"] == cfg["group"]), None)
        tid = tag_id(sio, tag, True)
        if group is None:
            group = call(sio, "add", {**copy.deepcopy(DEFAULTS), "type": "group", "name": cfg["group"],
                                      "notificationIDList": {}, "description": "uptimekuma-sync.py"})["monitorID"]
            call(sio, "addMonitorTag", tid, group, "")
            print(f"Gruppe angelegt: {cfg['group']}")
        notifications = getattr(sio, "notifications", [])
        for k in create:
            kind, name, target = wanted[k]
            mid = call(sio, "add", new_monitor(kind, name, target, group, monitors, cfg, notifications))["monitorID"]
            call(sio, "addMonitorTag", tid, mid, "")
            print(f"Angelegt: {name}")
        for mid in resume:
            call(sio, "resumeMonitor", mid)
            print(f"Wieder aktiv: {monitors[mid]['name']}")
        for mid in pause:
            call(sio, "pauseMonitor", mid)
            print(f"Pausiert: {monitors[mid]['name']}")
    finally:
        sio.disconnect()


if __name__ == "__main__":
    main()
