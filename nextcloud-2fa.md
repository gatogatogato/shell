# Nextcloud: 2FA mit TOTP und YubiKey

Stand 5. Oktober 2026. Nextcloud läuft als TrueNAS-App, einziger Benutzer `gato`.
Zweiter Faktor: zwei YubiKeys (WebAuthn) und TOTP als Ersatz, 2FA ist für alle erzwungen.
Backup-Codes und TOTP-Schlüssel liegen in Vaultwarden.

Alle Befehle laufen als root auf TrueNAS (`ssh root@truenas.lan`). Abkürzung für diese Shell:

```
occ() { docker exec -u www-data ix-nextcloud-nextcloud-1 php occ "$@"; }
```

## Notfall: nicht mehr reinkommen

Der Reihe nach, das erste, was klappt:

1. Beim Login „Andere Methode“ wählen und TOTP nehmen (Code aus der Authenticator-App).
2. Einen Backup-Code aus Vaultwarden nehmen (jeder gilt nur einmal).
3. 2FA auf TrueNAS abschalten:

```
occ twofactorauth:state gato                  # zeigt, welche Methoden aktiv sind
occ twofactorauth:enforce --off               # Erzwingen aus
occ twofactorauth:disable gato webauthn       # YubiKeys für gato aus
occ twofactorauth:disable gato totp           # TOTP für gato aus
```

Danach geht der Login nur mit Passwort. Sofort wieder einrichten (unten) und erzwingen.

Passwort vergessen (fragt das neue Passwort ab, darum `-it`):

```
docker exec -it -u www-data ix-nextcloud-nextcloud-1 php occ user:resetpassword gato
```

Hinweis: Die YubiKeys funktionieren nur auf `https://nextcloud.mythenstrasse56.net`.
Über die LAN-Adresse (`http://192.168.1.79:30027`) bleibt nur TOTP.

## Wieder einrichten (z. B. nach Neuinstallation der App)

Die Apps und die registrierten Keys stecken im Datenverzeichnis und in der Datenbank.
Nach einem Restore aus Backup ist alles wieder da. Nach einer Neuinstallation:

1. Apps installieren:
   ```
   occ app:install twofactor_totp
   occ app:install twofactor_webauthn
   occ app:install twofactor_backupcodes   # meist schon dabei
   ```
2. Im Browser über `https://nextcloud.mythenstrasse56.net` als `gato` anmelden.
3. *Persönliche Einstellungen → Sicherheit → Zwei-Faktor-Authentifizierung*:
   - TOTP aktivieren, QR-Code scannen, Schlüssel in Vaultwarden ersetzen.
   - *WebAuthn-Geräte → Sicherheitsschlüssel hinzufügen*: YubiKey 1, dann YubiKey 2.
   - Backup-Codes neu erzeugen und in Vaultwarden ablegen.
4. Im privaten Fenster testen: einmal mit jedem Key, einmal mit TOTP.
5. Erzwingen: `occ twofactorauth:enforce --on`

## Clients

- Desktop- und Handy-App melden sich per Login im Browser an (einmal 2FA), danach mit eigenem App-Passwort.
- Flickr-Server (`nextcloudcmd`) nutzt das App-Passwort „flickr-server“ in `~/.netrc`. Es umgeht 2FA.
  Neues App-Passwort: *Sicherheit → Geräte & Sitzungen → App-Passwort erstellen*.
- WebDAV mit dem normalen Passwort geht mit 2FA nicht mehr, dafür ebenfalls ein App-Passwort nehmen.
