# Nextcloud: Hardening-Check (3. Oktober 2026)

Nextcloud läuft als TrueNAS-App (`ix-nextcloud-*`, intern `http://192.168.1.79:30027`) und ist öffentlich nur über
den Cloudflare Tunnel erreichbar (`nextcloud.mythenstrasse56.net`).

**Stand nach dem 3. Oktober:** Erledigt sind echte Client-IP (`trusted_proxies`), http→https und HSTS bei Cloudflare,
System-Cron, Federation aus, App-Passwort für den Flickr-Server, 2FA (TOTP) für `gato` sowie Passwort und
30 Tage Ablauf für Freigabe-Links. Offen und optional: Wartungsbefehle (Punkt 7 der To-do-Liste) und
TrueNAS-Kleinkram (Punkt 11). `/cron.php` antwortet im Cron-Modus weiter mit „success“, führt aber keinen Job aus (Verhalten von Nextcloud 35).

`occ` aufrufen (als root auf TrueNAS):

```sh
occ() { docker exec -u www-data ix-nextcloud-nextcloud-1 php occ "$@"; }
```

Der erste Check lief nur lesend und ohne Login vom Mac aus, von aussen über `nextcloud.mythenstrasse56.net`
und im LAN gegen `http://192.168.1.79:30027`. Die Vorschläge unten sind der Befund von damals, mit Vermerk, was inzwischen erledigt ist.
Was in Nextcloud selbst eingestellt ist (Konten, 2FA, Freigaben, Apps), lässt sich ohne Login nicht sehen.
Dafür gibt es unten einen Prüfbefehl.

## Was schon gut ist

- Version 35.0.1, kein Wartungsmodus, keine ausstehende DB-Migration.
- Sensible Pfade sind gesperrt: `/data/`, `/config/config.php`, `/.htaccess`, `/3rdparty/`, `/lib/` und `/updater/` liefern 404.
- Die Security-Header sind gesetzt: strikte CSP mit Nonce, `X-Frame-Options`, `nosniff`, `Referrer-Policy: no-referrer`, `X-Robots-Tag: noindex` und eine restriktive Feature-Policy.
- Cookies sind `Secure` und `HttpOnly`, mit `__Host-`-Prefix und SameSite.
- Anonym zeigt die Capabilities-API kaum etwas. `overwrite.cli.url` zeigt korrekt auf die öffentliche Adresse.
- Der Router lässt nichts herein, von aussen geht alles über Cloudflare mit TLS ab 1.2.

## Vorschläge, sortiert nach Nutzen

### 1. Echte Client-IP hinter dem Tunnel (erledigt 3.10.)

Nextcloud sieht als Absender nur cloudflared. Der Brute-Force-Schutz wirft dann alle Anmeldungen in einen Topf:
Ein Angreifer bremst dich mit aus, und im Log steht keine brauchbare IP. Der Check hat `"bruteforce":{"delay":0}` gemeldet.

Vorschlag (die IP vom cloudflared-Container eintragen, nur diese, nicht das ganze LAN):

```php
'trusted_proxies' => ['127.0.0.1', '192.168.1.75'],   // 192.168.1.75 = debian-cloudflared
'forwarded_for_headers' => ['HTTP_CF_CONNECTING_IP', 'HTTP_X_FORWARDED_FOR'],
```

Nur weil `trusted_proxies` so eng ist, kann im LAN niemand den Header fälschen.

### 2. http wird nicht auf https umgeleitet (erledigt 3.10., Always Use HTTPS aktiv)

`/.well-known/caldav` und `/.well-known/carddav` leiten auf `http://nextcloud.mythenstrasse56.net/remote.php/dav/` um.
Das kommt aus der Apache-`.htaccess`, deshalb hilft das schon gesetzte `overwriteprotocol` nicht.
Das eigentliche Problem: `http://nextcloud.mythenstrasse56.net/remote.php/dav/` antwortet direkt mit 401, Cloudflare
leitet also **nicht** auf https um. Folgt ein Kalender- oder Kontakt-Client (iOS, DAVx5) dieser Umleitung, schickt er
Benutzername und App-Passwort unverschlüsselt bis zu Cloudflare.

Vorschlag: In Cloudflare unter *SSL/TLS → Edge Certificates* prüfen, ob „Always Use HTTPS“ wirklich an ist.
Laut Notiz vom 2. Oktober sollte das so sein, gemessen wurde am 3. Oktober aber das Gegenteil.
Sonst unter *Rules* nach einer Regel suchen, die das für diesen Host übersteuert (Configuration Rule oder Page Rule).
Zusammen mit HSTS (Punkt 3) ist die Lücke dann zu.

### 3. HSTS für die öffentliche Adresse (erledigt 3.10.)

Von aussen fehlt `Strict-Transport-Security`. Am einfachsten setzt du das bei Cloudflare nur für diesen Host:
*Rules → Transform Rules → Modify Response Header*, wenn der Hostname gleich `nextcloud.mythenstrasse56.net` ist,
setzt du `Strict-Transport-Security: max-age=15552000`. Nextcloud prüft genau diesen Wert.
Kein `preload`, keine `includeSubDomains`.
Die zonenweite HSTS-Option bei Cloudflare geht auch. Dann gilt sie aber für alle Subdomains.

### 4. 2FA für alle Konten und eine Passwort-Richtlinie (hoch, muss ich noch sehen)

- Apps *Two-Factor TOTP Provider* (und optional WebAuthn) aktivieren und für alle Konten erzwingen:
  *Verwaltung → Sicherheit → Zwei-Faktor-Authentifizierung erzwingen*.
- Desktop- und Handy-Client melden sich danach über App-Passwörter an (Login-Flow), das läuft automatisch.
- Das Admin-Konto sollte nicht `admin` heissen und nicht dein Alltagskonto sein.
- *Password policy*: Mindestlänge 12 und Prüfung gegen geleakte Passwörter (Standard ist an).

### 5. Öffentliche Freigaben (mittel, muss ich noch sehen)

In *Verwaltung → Teilen*:
- Passwort für Link-Freigaben erzwingen, oder zumindest ein Ablaufdatum von z. B. 30 Tagen vorgeben und erzwingen.
- Federation (Teilen mit anderen Nextcloud-Servern) ausschalten, falls du es nicht nutzt.
- Ungenutzte Apps deaktivieren. Jede App ist Angriffsfläche.

### 6. Hintergrundjobs per System-Cron (mittel)

`/cron.php` antwortet mit `success`. Hintergrundjobs laufen also per AJAX oder Webcron, also nur dann, wenn jemand
die Seite aufruft, und sie sind von aussen auslösbar. In der TrueNAS-App gibt es unter *Edit → Nextcloud Configuration*
eine Cron-Option. Die schaltest du ein und setzt danach *Verwaltung → Grundeinstellungen → Hintergrundjobs* auf **Cron**.

### 7. Cloudflare-Schutz vor dem Login (mittel)

- WAF-Rate-Limit auf `/login` und `/index.php/login` (z. B. 10 pro Minute pro IP). Das ergänzt Punkt 1.
- Optional eine Länderregel (nur CH/EU), wenn du nie aus dem Ausland zugreifst. Aber Vorsicht auf Reisen.
- Cloudflare Access gehört **nicht** vor die ganze Nextcloud, sonst können sich Desktop-, Handy- und WebDAV-Clients nicht mehr anmelden.
  Höchstens für `/settings/admin`, was aber wenig bringt.
- Erinnerung: Cloudflare Free lässt pro Request höchstens 100 MB durch. Die Clients laden in Chunks hoch und sind nicht betroffen, grosse Uploads im Browser schon.

### 8. Direktzugriff im LAN auf Port 30027 (niedrig)

`http://192.168.1.79:30027` ist im ganzen LAN offen, ohne TLS und an Cloudflare vorbei.
Die Cookies sind `Secure`, deshalb klappt dort ein Browser-Login sowieso nicht zuverlässig. Clients sollten immer die
öffentliche Adresse nutzen. Wenn das passt, kann man den Port in TrueNAS später auf den cloudflared-Host
beschränken. Das ist kein Muss.

### 9. Versionen nicht verraten (niedrig)

`X-Powered-By: PHP/8.5.11` geht nach aussen. Das entfernst du mit derselben Cloudflare Transform Rule wie in Punkt 3:
*Remove* `X-Powered-By`.

### 10. Backup (mittel, muss ich noch sehen)

- Liegen die Nextcloud-Daten und die Datenbank auf einem Dataset mit regelmässigen ZFS-Snapshots?
- Gibt es einen Datenbank-Dump (Postgres der App)? Ein Snapshot einer laufenden DB ist meist ok, aber nicht garantiert konsistent.
- `config.php` enthält Secrets und gehört ins Backup, behandelt wie ein Passwort.

### 11. TrueNAS selbst (niedrig, nebenbei gesehen)

- Die Web-Oberfläche leitet http nicht auf https um, und HSTS ist `max-age=0`.
  Unter *System → General → GUI* schaltest du „Web Interface HTTP → HTTPS Redirect“ ein.
- Offen im LAN: SSH, SMB, NFS mit rpcbind und WS-Discovery. Was du nicht nutzt (NFS? SSH?), schaltest du unter *System → Services* aus.
- 2FA für die TrueNAS-Anmeldung (*Credentials → 2FA*).

## Prüfbefehl für dich (nur lesen)

In der TrueNAS-Shell als root (*System → Shell* oder ssh). Der Container heisst `ix-nextcloud-nextcloud-1`, prüfen mit:

```sh
docker ps --format '{{.Names}}' | grep -i nextcloud
```

Dann `<NAME>` durch den Nextcloud-Container ersetzen, nicht durch die Datenbank oder Redis:

```sh
N=<NAME>; occ() { docker exec -u www-data "$N" php occ "$@"; }
echo "== System-Config (Secrets werden von occ maskiert)"
occ config:list system | grep -E '"(trusted_domains|trusted_proxies|forwarded_for_headers|overwriteprotocol|overwrite.cli.url|overwritehost|loglevel|auth.bruteforce.protection.enabled|maintenance_window_start|default_phone_region)"' -A4
echo "== Hintergrundjobs"; occ config:app:get core backgroundjobs_mode
echo "== Freigaben"; for k in shareapi_allow_links shareapi_enforce_links_password shareapi_default_expire_date shareapi_enforce_expire_date shareapi_expire_after_n_days; do printf "%s: " $k; occ config:app:get core $k || echo "(Standard)"; done
echo "== 2FA erzwungen?"; occ twofactorauth:enforce
echo "== Konten (nur Namen)"; occ user:list
echo "== Aktivierte Apps"; occ app:list --enabled
echo "== Setup-Warnungen"; occ setupchecks
```

Die Ausgabe enthält Kontonamen und die App-Liste, aber keine Passwörter.
Statt `occ setupchecks` geht auch ein Screenshot von *Verwaltung → Übersicht → Sicherheits- & Einrichtungswarnungen*.

## Stand nach dem Prüfbefehl (3. Oktober, 11:12)

- Konten: nur `gato`. Ein Konto `admin` gibt es nicht. Der fehlgeschlagene Login „admin“ war der eigene Test.
- 2FA: `twofactor_totp` ist installiert, aber nicht erzwungen.
- Freigaben: alles auf Standard. Links sind erlaubt, ohne Passwortpflicht und ohne Ablaufdatum.
- Federation ist aktiv (`federation`, `federatedfilesharing`, `lookup_server_connector`).
- Setup-Warnungen: HSTS fehlt (kommt mit Cloudflare-HSTS), kein Wartungsfenster, fehlende DB-Indizes,
  Mimetype-Migration offen, 1 DB-Konfigurationsprüfung schlägt fehl (Details noch offen), 57 Fehler im Log,
  keine Telefonregion, kein Mailserver.
- „Remote address could not be determined“ ist bei occ normal (Aufruf über die Kommandozeile, nicht über das Web).

### To-do in Reihenfolge

1. (erledigt 3.10.) Cron: `occ background:cron`.
2. (erledigt 3.10.) Cloudflare: Always Use HTTPS und HSTS (max-age 15552000 gemessen).
3. (erledigt 3.10., Flickr-Sync auf App-Passwort umgestellt) 2FA für `gato` einrichten (*Persönliche Einstellungen → Sicherheit → TOTP*), Backup-Codes in Vaultwarden und auf dem Papier-Notfallblatt. Nicht global erzwungen (`twofactorauth:enforce`), bei einem Konto unnötig.
4. (erledigt 3.10.) Freigaben: `occ config:app:set core shareapi_enforce_links_password --value=yes` und Ablaufdatum 30 Tage
   (`shareapi_default_expire_date yes`, `shareapi_expire_after_n_days 30`, `shareapi_enforce_expire_date yes`).
5. (erledigt 3.10.) Federation aus, wenn nicht genutzt: `occ app:disable lookup_server_connector federation`, dazu
   `occ config:app:set files_sharing <key> --value=no` für `outgoing_server2server_share_enabled`,
   `incoming_server2server_share_enabled`, `lookupServerEnabled` und `lookupServerUploadEnabled`.
6. Unnötige Apps aus: `survey_client recommendations weather_status nextcloud_announcements support firstrunwizard app_api webhook_listeners`.
7. Pflege: `occ config:system:set maintenance_window_start --type=integer --value=2` (02:00 UTC = 04:00 Sommerzeit,
   nach Proxmox-Backup und Ansible-Updates), `occ config:system:set default_phone_region --value=CH`,
   `occ db:add-missing-indices`, `occ maintenance:repair --include-expensive` (dauert etwas, lieber abends).
8. (geklärt 3.10.) DB-Prüfung: nur ein Hinweis, `oc_preferences` und `oc_appconfig` werden sequenziell gelesen. Das sind kleine Tabellen, Postgres liest sie absichtlich am Stück, kein Handlungsbedarf. Log-Fehler: alle vom 1.10. 06:44 UTC, Postgres war beim Start kurz nicht erreichbar, einmalig.
