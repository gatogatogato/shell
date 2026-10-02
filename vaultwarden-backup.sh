#!/bin/sh
# Vaultwarden-Backup fuer Alpine (BusyBox ash + OpenRC)
# packen -> pruefen -> uebertragen -> verifizieren -> aufraeumen
# Es wird NICHTS geloescht, bevor die Kopie auf dem NAS verifiziert ist.
#
# Liegt im Container als /etc/periodic/daily/create-vaultwarden-backup (ohne Punkt
# im Namen, sonst ueberspringt run-parts die Datei), Doku: vaultwarden-backup.md
# Voraussetzungen: apk add openssh-client tar gzip
#
# Konfig (Push-URL, gehoert nicht ins Repo): /etc/vaultwarden-backup.conf (chmod 600),
# Vorlage vaultwarden-backup.conf.example. Jede Variable unten laesst sich dort ueberschreiben.
set -eu

CONFIG="${CONFIG:-/etc/vaultwarden-backup.conf}"

DPATH="/var/lib/vaultwarden"
STAGE="/var/backups/vaultwarden"                 # nicht /tmp (1777)
REMOTE="vaultwarden@truenas.lan"
REMOTE_DIR="/mnt/tank01/vaultwarden-backups/vaultwarden"
KEY="/root/.ssh/id_ed25519"
SVC="vaultwarden"
KEEP_LOCAL=3                                     # Tage
KEEP_REMOTE=90                                   # Tage
MIN_SIZE=100000                                  # Byte, Plausibilitaetsgrenze
HC_URL=""                                        # Uptime-Kuma-Push-URL, leer = aus

# shellcheck source=/dev/null
[ -f "$CONFIG" ] && . "$CONFIG"

STAMP="$(date +%Y-%m-%d_%H.%M)"
BASENAME="vaultwarden-backup-${STAMP}.tar.gz"
ARCHIVE="${STAGE}/${BASENAME}"

# BusyBox-freundliche Groessenermittlung (kein stat, keine Coreutils noetig)
fsize() { wc -c < "$1" | tr -d ' '; }
die()   { echo "FEHLER: $*" >&2; exit 1; }

umask 077
mkdir -p "$STAGE"
chmod 700 "$STAGE"

# Parallel-Laeufe verhindern (BusyBox flock kann FD-Form)
exec 9>/run/vaultwarden-backup.lock
flock -n 9 || { echo "Backup laeuft bereits, breche ab." >&2; exit 1; }

# Dienst in jedem Fall wieder starten, auch bei Abbruch
cleanup() {
    rc=$?
    rc-service "$SVC" status >/dev/null 2>&1 || rc-service "$SVC" start 9>&- >/dev/null 2>&1 || true
    exit $rc
}
trap cleanup EXIT INT TERM

# --- 1. Konsistent packen -------------------------------------------------
[ -f "${DPATH}/db.sqlite3" ] || die "${DPATH}/db.sqlite3 nicht gefunden."

rc-service "$SVC" stop >/dev/null
sleep 2
tar -C "$(dirname "$DPATH")" -czf "$ARCHIVE" "$(basename "$DPATH")"
rc-service "$SVC" start 9>&- >/dev/null

# --- 2. Archiv pruefen, bevor irgendetwas geloescht wird -------------------
tar -tzf "$ARCHIVE" >/dev/null || die "Archiv nicht lesbar."
tar -tzf "$ARCHIVE" 2>/dev/null | grep -q 'db\.sqlite3$' \
    || die "db.sqlite3 nicht im Archiv enthalten."

LOCAL_SIZE="$(fsize "$ARCHIVE")"
[ "$LOCAL_SIZE" -gt "$MIN_SIZE" ] || die "Archiv nur ${LOCAL_SIZE} Byte."

# --- 3. Uebertragen und Groesse gegenpruefen ------------------------------
scp -q -o ConnectTimeout=30 -o BatchMode=yes -i "$KEY" \
    "$ARCHIVE" "${REMOTE}:${REMOTE_DIR}/" || die "scp fehlgeschlagen."

REMOTE_SIZE="$(ssh -o ConnectTimeout=30 -o BatchMode=yes -i "$KEY" "$REMOTE" \
    "wc -c < '${REMOTE_DIR}/${BASENAME}'" | tr -d ' ')"
[ "$LOCAL_SIZE" = "$REMOTE_SIZE" ] \
    || die "Uebertragung unvollstaendig (${LOCAL_SIZE} vs ${REMOTE_SIZE})."

# --- 4. Erst jetzt aufraeumen: absolute Pfade, maxdepth, enger Namensfilter -
find "$STAGE" -maxdepth 1 -type f -name 'vaultwarden-backup-*.tar.gz' \
     -mtime "+${KEEP_LOCAL}" -exec rm -f {} \;

ssh -o ConnectTimeout=30 -o BatchMode=yes -i "$KEY" "$REMOTE" \
    "find '${REMOTE_DIR}' -maxdepth 1 -type f -name 'vaultwarden-backup-*.tar.gz' -mtime +${KEEP_REMOTE} -exec rm -f {} \;"

# --- 5. Dead-Man-Switch (BusyBox wget, kein curl noetig) -------------------
if [ -n "$HC_URL" ]; then
    wget -q -T 10 -O /dev/null "$HC_URL" || true
fi

echo "OK: ${BASENAME} (${LOCAL_SIZE} Byte)"
