#!/bin/bash
# Notfallkopie des Homelabs auf eine verschluesselte USB-Disk (Mac, Variante A von Idee 7)
# Disk anstecken, Skript starten, Disk auswerfen und ausser Haus bringen.
# Doku und Restore: usb-backup.md
#
# Holt jeweils nur den neuesten Stand:
#   - verschluesselter Bitwarden-Export (von Hand erstellt, liegt in ~/Downloads)
#   - TrueNAS-Config inkl. pwenc_secret (wie "Download Configuration" mit Secret Seed)
#   - neuestes Vaultwarden-Backup und neuestes Home-Assistant-Backup von TrueNAS
#   - neuestes vzdump-Archiv jedes Proxmox-Gasts von TrueNAS
#   - lokaler Nextcloud-Ordner
#   - Mirror-Klone der GitHub-Repos
# Jeder Lauf landet in einem eigenen Ordner mit Datum und SHA256SUMS; die letzten $KEEP
# bleiben. Alte Laeufe werden erst geloescht, wenn der neue vollstaendig ist.
#
# Konfig (Kuma-Push-URL, gehoert nicht ins Repo): ~/.config/usb-backup.conf (chmod 600),
# Vorlage usb-backup.conf.example. Jede Variable unten laesst sich dort ueberschreiben.
# Laeuft mit dem bash 3.2 von macOS.
set -euo pipefail

CONFIG="${CONFIG:-$HOME/.config/usb-backup.conf}"

DISK="/Volumes/LastResort"                       # APFS (verschluesselt), Samsung T7
TRUENAS="root@truenas.lan"
VW_DIR="/mnt/tank01/vaultwarden-backups/vaultwarden"
VW_MAX_DAYS=2
HA_DIR="/mnt/tank01/ha-backups"
HA_MAX_DAYS=4                                    # HA sichert Mo/Mi/Fr
DUMP_DIR="/mnt/tank01/proxmox-raw-backups/dump"
DUMP_MAX_DAYS=10                                 # aeltere Archive gehoeren zu entfernten Gaesten
NEXTCLOUD_DIR="$HOME/Nextcloud"
EXPORT_DIR="$HOME/Downloads"
EXPORT_MAX_DAYS=100
GIT_URL="git@github.com:gatogatogato"
REPOS="ansible basetagger camsnaps flickr-scripts flickr-uploader gatogatogato.ch-hugo glance inventar shell"
KEEP=3                                           # so viele Laeufe bleiben auf der Disk
MIN_FREE_GB=60
KUMA_URL=""                                      # Uptime-Kuma-Push-URL, leer = aus

# shellcheck source=/dev/null
[ -f "$CONFIG" ] && . "$CONFIG"

HERE="$(cd "$(dirname "$0")" && pwd)"
BASE="$DISK/homelab-backup"
STAMP="$(date +%Y-%m-%d_%H%M)"
RUN="$BASE/$STAMP.partial"
SSH="ssh -o BatchMode=yes -o ControlMaster=auto -o ControlPath=$HOME/.ssh/usb-backup-%C -o ControlPersist=300"
WARN=""

say()  { printf '\n== %s\n' "$*"; }
warn() { echo "WARNUNG: $*" >&2; WARN="${WARN}- $*"$'\n'; }
die()  { echo "FEHLER: $*" >&2; exit 1; }
ts()   { $SSH "$TRUENAS" "$@"; }

# Neueste Datei zu einem Muster auf TrueNAS: "<alter in tagen> <pfad>", leer wenn keine
newest_remote() {
    ts "f=\$(ls -1t $1/$2 2>/dev/null | head -1); [ -n \"\$f\" ] && echo \$(( (\$(date +%s) - \$(stat -c %Y \"\$f\")) / 86400 )) \"\$f\"" || true
}

fetch_newest() {    # <name> <ordner> <muster> <max tage> <ziel>
    local line age file
    line="$(newest_remote "$2" "$3")"
    [ -n "$line" ] || { warn "$1: keine Datei $2/$3 auf TrueNAS"; return; }
    age="${line%% *}"; file="${line#* }"
    [ "$age" -le "$4" ] || warn "$1: neueste Datei ist $age Tage alt ($file)"
    mkdir -p "$5"
    rsync -a -e "$SSH" "$TRUENAS:$file" "$5/"
    echo "$1: $(basename "$file") ($age Tage alt)"
}

finish() {
    rc=$?
    $SSH -O exit "$TRUENAS" 2>/dev/null || true
    if [ $rc -ne 0 ] && [ -d "$RUN" ]; then
        echo "Abgebrochen. Unvollstaendiger Lauf bleibt in $RUN (wird beim naechsten Lauf geloescht)." >&2
        [ -n "$KUMA_URL" ] && curl -fsS -m 10 -o /dev/null "${KUMA_URL%%\?*}?status=down&msg=Abbruch" || true
    fi
    exit $rc
}
trap finish EXIT

# --- 0. Disk pruefen --------------------------------------------------------------------
[ -d "$DISK" ] || die "$DISK nicht gefunden. Disk angesteckt und entsperrt?"
diskutil info "$DISK" | grep -Eq 'FileVault: +Yes' \
    || die "$DISK ist nicht verschluesselt (diskutil info: FileVault nicht Yes). Siehe usb-backup.md."
free_gb=$(( $(df -k "$DISK" | awk 'NR==2 {print $4}') / 1024 / 1024 ))
[ "$free_gb" -ge "$MIN_FREE_GB" ] || die "Nur $free_gb GB frei auf $DISK, mindestens $MIN_FREE_GB GB noetig."

mkdir -p "$BASE"
rm -rf "$BASE"/*.partial                         # Reste abgebrochener Laeufe
PREV="$(ls -1d "$BASE"/20*/ 2>/dev/null | sort | tail -1 || true)"
umask 077
mkdir -p "$RUN"
ts true || die "Kein SSH-Login als $TRUENAS (Schluessel hinterlegt? Siehe usb-backup.md)."

# --- 1. Bitwarden-Export ----------------------------------------------------------------
say "Bitwarden-Export"
for f in "$EXPORT_DIR"/bitwarden_export_*.json "$EXPORT_DIR"/bitwarden_export_*.csv; do
    [ -e "$f" ] && warn "unverschluesselter Export $f gefunden, bitte loeschen (wird nicht kopiert)"
done
export_file="$(ls -1t "$EXPORT_DIR"/bitwarden_encrypted_export_*.json 2>/dev/null | head -1 || true)"
if [ -z "$export_file" ]; then
    warn "kein verschluesselter Export in $EXPORT_DIR (Web-Tresor: Werkzeuge > Tresor exportieren, .json (Encrypted), Passwortgeschuetzt)"
elif ! grep -q '"passwordProtected": *true' "$export_file"; then
    warn "$export_file ist nicht passwortgeschuetzt, nicht kopiert"
else
    age=$(( ( $(date +%s) - $(stat -f %m "$export_file") ) / 86400 ))
    [ "$age" -le "$EXPORT_MAX_DAYS" ] || warn "Bitwarden-Export ist $age Tage alt, bitte neu exportieren"
    mkdir -p "$RUN/vaultwarden"
    cp -p "$export_file" "$RUN/vaultwarden/"
    echo "$(basename "$export_file") ($age Tage alt)"
fi

# --- 2. TrueNAS-Config ------------------------------------------------------------------
say "TrueNAS-Config"
mkdir -p "$RUN/truenas"
ts 'set -e; t=$(mktemp -d); trap "rm -rf $t" EXIT
    if command -v sqlite3 >/dev/null; then sqlite3 /data/freenas-v1.db ".backup $t/freenas-v1.db"
    else cp /data/freenas-v1.db "$t/"; fi
    cp /data/pwenc_secret "$t/"
    tar -C "$t" -cf - freenas-v1.db pwenc_secret' > "$RUN/truenas/truenas-config-$STAMP.tar"
tar -tf "$RUN/truenas/truenas-config-$STAMP.tar" | grep -q pwenc_secret || die "TrueNAS-Config unvollstaendig."
echo "truenas-config-$STAMP.tar"

# --- 3. Vaultwarden- und Home-Assistant-Backup ------------------------------------------
say "Vaultwarden- und Home-Assistant-Backup"
fetch_newest "Vaultwarden" "$VW_DIR" 'vaultwarden-backup-*.tar.gz' "$VW_MAX_DAYS" "$RUN/vaultwarden"
fetch_newest "Home Assistant" "$HA_DIR" '*.tar' "$HA_MAX_DAYS" "$RUN/homeassistant"

# --- 4. vzdump: neuestes Archiv je Gast (mit .log und .notes) ----------------------------
say "Proxmox vzdump"
mkdir -p "$RUN/proxmox-vzdump"
dump_files="$(ts "cd '$DUMP_DIR' && find . -maxdepth 1 -type f -name 'vzdump-*' ! -name '*.log' ! -name '*.notes' -mtime -$DUMP_MAX_DAYS -printf '%T@ %f\n' \
    | sort -rn | awk '{ split(\$2, a, \"-\"); if (!(a[3] in seen)) { seen[a[3]] = 1; p = \$2; sub(/\\.(tar|vma)(\\.(zst|gz|lzo))?\$/, \"\", p); print p } }' \
    | while read -r p; do ls -1 \"\$p\".*; done")"
[ -n "$dump_files" ] || warn "keine vzdump-Archive juenger als $DUMP_MAX_DAYS Tage in $DUMP_DIR"
for f in $dump_files; do
    rsync -a -e "$SSH" "$TRUENAS:$DUMP_DIR/$f" "$RUN/proxmox-vzdump/"
done
echo "$(echo "$dump_files" | grep -cE '\.(zst|gz|lzo)$' || true) Gaeste, $(du -sh "$RUN/proxmox-vzdump" | cut -f1)"

# --- 5. Nextcloud -----------------------------------------------------------------------
say "Nextcloud"
if [ -d "$NEXTCLOUD_DIR" ]; then
    link=""
    [ -n "$PREV" ] && [ -d "${PREV}nextcloud" ] && link="--link-dest=${PREV}nextcloud"
    rsync -a $link --exclude '.DS_Store' --exclude '.sync_*.db*' --exclude '._sync_*.db*' \
        --exclude '.owncloudsync.log*' --exclude '.nextcloudsync.log*' \
        "$NEXTCLOUD_DIR/" "$RUN/nextcloud/"
    echo "$(du -sh "$RUN/nextcloud" | cut -f1)"
else
    warn "Nextcloud-Ordner $NEXTCLOUD_DIR nicht gefunden"
fi

# --- 6. GitHub-Repos --------------------------------------------------------------------
say "GitHub-Repos"
mkdir -p "$RUN/git"
for r in $REPOS; do
    git clone -q --mirror "$GIT_URL/$r.git" "$RUN/git/$r.git" 2>/dev/null && echo "$r" \
        || warn "git clone $r fehlgeschlagen"
done

# --- 7. Pruefsummen, Anleitung, abschliessen --------------------------------------------
say "Pruefsummen"
[ -f "$HERE/usb-backup.md" ] && cp "$HERE/usb-backup.md" "$RUN/LIESMICH.md"
(cd "$RUN" && find . -type f ! -name SHA256SUMS -print0 | xargs -0 shasum -a 256 > SHA256SUMS)
[ -n "$WARN" ] && printf '%s' "$WARN" > "$RUN/WARNUNGEN.txt"
mv "$RUN" "$BASE/$STAMP"
RUN="$BASE/$STAMP"
echo "$(wc -l < "$RUN/SHA256SUMS" | tr -d ' ') Dateien, $(du -sh "$RUN" | cut -f1)"

ls -1d "$BASE"/20*/ | sort -r | tail -n +$((KEEP + 1)) | while read -r old; do
    echo "loesche alten Lauf $old"
    rm -rf "$old"
done

if [ -n "$KUMA_URL" ]; then
    n=$(printf '%s' "$WARN" | grep -c . || true)
    curl -fsS -m 10 -o /dev/null "${KUMA_URL%%\?*}?status=up&msg=OK%20${n}%20Warnungen" \
        || warn "Push an Uptime Kuma fehlgeschlagen"
fi

say "Fertig: $RUN"
[ -z "$WARN" ] || printf '\nWarnungen:\n%s' "$WARN"
echo "Disk auswerfen: diskutil eject $DISK"
