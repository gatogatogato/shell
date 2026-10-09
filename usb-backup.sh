#!/bin/bash
# Laufordner und Bitwarden-Exporte haben feste Namen ohne Sonderzeichen, ls ist hier sicher.
# shellcheck disable=SC2012
# Notfallkopie des Homelabs auf eine verschluesselte USB-Disk (Mac, Variante A von Idee 7)
# Disk anstecken, Skript starten, Disk auswerfen und ausser Haus bringen.
# Doku und Restore: usb-backup.md
#
# Holt jeweils nur den neuesten Stand:
#   - verschluesselter Bitwarden-Export (von Hand erstellt, liegt in ~/Downloads)
#   - TrueNAS-Config inkl. pwenc_secret (wie "Download Configuration" mit Secret Seed)
#   - neuestes Vaultwarden-Backup und neuestes Home-Assistant-Backup von TrueNAS
#   - neuestes vzdump-Archiv jedes Proxmox-Gasts von TrueNAS
#   - Kontakte aus der Kontakte-App als vCard, dazu die Gruppen als Textdatei
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
HA_MAX_DAYS=4                                    # HA sichert Mo/Mi/Fr, nur automatic_backup_* sind Voll-Backups
DUMP_DIR="/mnt/tank01/proxmox-raw-backups/dump"
DUMP_MAX_DAYS=10                                 # aeltere Archive gehoeren zu entfernten Gaesten
NEXTCLOUD_DIR="$HOME/Nextcloud"
FOTOS_DIR="/mnt/tank01/nextcloud/userdata/gato/files/Photos"   # iPhone-Upload, auf dem Mac nicht synchronisiert
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
STAMP="$(date +%Y-%m-%d_%H%M%S)"
RUN="$BASE/$STAMP.partial"
SSH="ssh -o BatchMode=yes -o ControlMaster=auto -o ControlPath=$HOME/.ssh/usb-backup-%C -o ControlPersist=300"
WARN=""
STEPS=10
T0=$(date +%s)

# --- Ausgabe ----------------------------------------------------------------------------
# Gleicher Look wie basetagger und flickr-uploader. Farben nur im Terminal, NO_COLOR schaltet ab.
WIDTH=78
if [ -t 1 ] && [ -z "${NO_COLOR+x}" ]; then COLOR=1; PROGRESS="--progress"; else COLOR=0; PROGRESS=""; fi

paint() {          # <text> <ansi-codes...>
    local text="$1"; shift
    if [ "$COLOR" = 1 ]; then local IFS=';'; printf '\033[%sm%s\033[0m' "$*" "$text"; else printf '%s' "$text"; fi
}
line()  { local n=$1 c=$2 out=""; while [ "$n" -gt 0 ]; do out="$out$c"; n=$((n - 1)); done; printf '%s' "$out"; }
box() {            # <text> <ansi-codes...>
    local text=" $1" w=$((WIDTH - 2)); shift
    [ ${#text} -lt "$w" ] || w=$((${#text} + 2))
    echo
    paint "+$(line "$w" =)+" 36; echo
    paint "|" 36; paint "$(printf "%-${w}s" "$text")" 1 "$@"; paint "|" 36; echo
    paint "+$(line "$w" =)+" 36; echo
}
STEP=0
section() {
    STEP=$((STEP + 1))
    local label="--[ $STEP/$STEPS ]-- $1 "
    echo
    paint "$label$(line $((WIDTH - ${#label})) -)" 1 36; echo
}
info()  { echo "  $(paint '>' 36) $*"; }
ok()    { echo "  $(paint '[OK]' 1 32) $*"; }
warn()  { echo "  $(paint '[!!]' 1 33) $*"; WARN="${WARN}- $*"$'\n'; }
die()   { echo "  $(paint '[XX]' 1 31) $(paint "$*" 31)"; echo; exit 1; }
field() { echo "  $(paint "$(printf '%s' "$1" | sed -e :a -e 's/^.\{1,11\}$/&./;ta')" 2) $2"; }
size()  { du -sh "$1" 2>/dev/null | cut -f1 | tr -d ' '; }
ts()    { $SSH "$TRUENAS" "$@"; }

# Kontakte-App per AppleScript (alle Accounts). Beim ersten Lauf fragt macOS, ob das Terminal
# die Kontakte-App steuern darf. Die Skripte stehen in Funktionen, weil bash 3.2 Heredocs
# innerhalb von $(...) falsch liest.
contacts_vcards() {     # alle Kontakte als eine vCard-Datei
    osascript <<'EOF'
tell application "Contacts" to set cards to vcard of every person
set text item delimiters to linefeed
return cards as text
EOF
}
contacts_stats() {      # "<anzahl kontakte> <anzahl mit notiz>"
    osascript <<'EOF'
tell application "Contacts"
    set n to count every person
    set allNotes to note of every person
end tell
set k to 0
repeat with t in allNotes
    set t to contents of t
    if t is not missing value and t is not "" then set k to k + 1
end repeat
return (n as text) & " " & (k as text)
EOF
}
contacts_groups() {     # je Gruppe "## Name" und darunter die Mitglieder
    osascript <<'EOF'
set out to ""
tell application "Contacts"
    repeat with g in every group
        set out to out & "## " & (name of g) & linefeed
        repeat with m in (name of every person of g)
            set out to out & (contents of m) & linefeed
        end repeat
        set out to out & linefeed
    end repeat
end tell
return out
EOF
}

# Neueste Datei zu einem Muster auf TrueNAS: "<alter in tagen> <pfad>", leer wenn keine
newest_remote() {
    ts "f=\$(ls -1t $1/$2 2>/dev/null | head -1); [ -n \"\$f\" ] && echo \$(( (\$(date +%s) - \$(stat -c %Y \"\$f\")) / 86400 )) \"\$f\"" 2>/dev/null || true
}

fetch_newest() {    # <name> <ordner> <muster> <max tage> <ziel>
    local line age file
    line="$(newest_remote "$2" "$3")"
    [ -n "$line" ] || { warn "$1: keine Datei $2/$3 auf TrueNAS"; return; }
    age="${line%% *}"; file="${line#* }"
    info "$1: $(basename "$file")"
    mkdir -p "$5"
    rsync -a $PROGRESS -e "$SSH" "$TRUENAS:$file" "$5/"
    if [ "$age" -le "$4" ]; then ok "$1: $(size "$5/$(basename "$file")"), $age Tage alt"
    else warn "$1: neueste Datei ist $age Tage alt ($(basename "$file"))"; fi
}

finish() {
    rc=$?
    $SSH -O exit "$TRUENAS" 2>/dev/null || true
    if [ $rc -ne 0 ] && [ -d "$RUN" ]; then
        box "Abgebrochen. Unvollständiger Lauf bleibt in $(basename "$RUN")" 31
        info "Er wird beim nächsten Lauf gelöscht."
        [ -n "$KUMA_URL" ] && curl -fsS -m 10 -o /dev/null "${KUMA_URL%%\?*}?status=down&msg=Abbruch" || true
        echo
    fi
    exit $rc
}
trap finish EXIT

box "USB-Notfallkopie $(date '+%d.%m.%Y %H:%M')" 37

# --- 0. Disk pruefen --------------------------------------------------------------------
section "Disk"
[ -d "$DISK" ] || die "$DISK nicht gefunden. Disk angesteckt und entsperrt?"
diskutil info "$DISK" | grep -Eq 'FileVault: +Yes' \
    || die "$DISK ist nicht verschlüsselt (diskutil info: FileVault nicht Yes). Siehe usb-backup.md."
free_gb=$(( $(df -k "$DISK" | awk 'NR==2 {print $4}') / 1024 / 1024 ))
[ "$free_gb" -ge "$MIN_FREE_GB" ] || die "Nur $free_gb GB frei auf $DISK, mindestens $MIN_FREE_GB GB nötig."

mkdir -p "$BASE"
rm -rf "$BASE"/*.partial                         # Reste abgebrochener Laeufe
PREV="$(ls -1d "$BASE"/20*/ 2>/dev/null | sort | tail -1 || true)"
umask 077
mkdir -p "$RUN"
ts true || die "Kein SSH-Login als $TRUENAS (Schlüssel hinterlegt? Siehe usb-backup.md)."
field "Disk" "$DISK, verschlüsselt, $free_gb GB frei"
field "TrueNAS" "$TRUENAS"
field "Ziel" "homelab-backup/$STAMP"
[ -n "$PREV" ] && field "Letzter Lauf" "$(basename "$PREV")"
ok "Disk bereit"

# --- 1. Bitwarden-Export ----------------------------------------------------------------
section "Bitwarden-Export"
for f in "$EXPORT_DIR"/bitwarden_export_*.json "$EXPORT_DIR"/bitwarden_export_*.csv; do
    [ -e "$f" ] && warn "unverschlüsselter Export $(basename "$f") in $EXPORT_DIR, bitte löschen (wird nicht kopiert)"
done
export_file="$(ls -1t "$EXPORT_DIR"/bitwarden_encrypted_export_*.json 2>/dev/null | head -1 || true)"
if [ -z "$export_file" ]; then
    warn "kein verschlüsselter Export in $EXPORT_DIR (Web-Tresor: Werkzeuge > Tresor exportieren, .json (Encrypted), Passwortgeschützt)"
elif ! grep -q '"passwordProtected": *true' "$export_file"; then
    warn "$(basename "$export_file") ist nur mit dem Konto verschlüsselt (Exporttyp \"Kontobeschränkt\"), ohne Vaultwarden nicht lesbar. Neu exportieren mit Exporttyp \"Passwortgeschützt\". Nicht kopiert."
else
    age=$(( ( $(date +%s) - $(stat -f %m "$export_file") ) / 86400 ))
    mkdir -p "$RUN/vaultwarden"
    cp -p "$export_file" "$RUN/vaultwarden/"
    if [ "$age" -le "$EXPORT_MAX_DAYS" ]; then ok "$(basename "$export_file"), $age Tage alt"
    else warn "Bitwarden-Export ist $age Tage alt, bitte neu exportieren"; fi
fi

# --- 2. Kontakte ------------------------------------------------------------------------
# vCards enthalten keine Gruppen, darum liegen die Gruppen zusaetzlich als Text daneben.
section "Kontakte"
mkdir -p "$RUN/kontakte"
vcf="$RUN/kontakte/kontakte-$STAMP.vcf"
contacts_was_running=0
pgrep -x Contacts >/dev/null && contacts_was_running=1
if ! err="$(contacts_vcards 2>&1 >"$vcf")"; then
    rm -f "$vcf"
    warn "Kontakte nicht exportiert: $(printf '%s' "$err" | tail -1). Zugriff erlauben unter Systemeinstellungen > Datenschutz & Sicherheit > Automation > Terminal > Kontakte."
else
    read -r people with_note <<< "$(contacts_stats || true)"
    with_note=${with_note:-0}
    vcount() { tr '\r' '\n' < "$vcf" | grep -c "$1" || true; }    # vCards koennen CR-Zeilenenden haben
    cards=$(vcount '^BEGIN:VCARD')
    notes=$(vcount '^NOTE[;:]')
    photos=$(vcount '^PHOTO[;:]')
    contacts_groups > "$RUN/kontakte/gruppen-$STAMP.txt" || warn "Kontaktgruppen nicht exportiert"
    groups=$(grep -c '^## ' "$RUN/kontakte/gruppen-$STAMP.txt" || true)
    [ "$cards" = "$people" ] || warn "Kontakte: $cards vCards, aber $people Kontakte in der Kontakte-App"
    [ "$notes" -ge "$with_note" ] \
        || warn "Kontakte: $with_note Kontakte haben eine Notiz, in der vCard sind nur $notes. Kontakte > Einstellungen > vCard > \"Notizen in vCards exportieren\" einschalten."
    [ "$photos" -gt 0 ] || [ "$cards" -eq 0 ] \
        || warn "Kontakte: keine Fotos in der vCard. Kontakte > Einstellungen > vCard > \"Fotos in vCards exportieren\" einschalten."
    ok "$cards Kontakte ($notes mit Notiz, $photos mit Foto), $groups Gruppen, $(size "$vcf")"
fi
[ "$contacts_was_running" = 1 ] || osascript -e 'tell application "Contacts" to quit' >/dev/null 2>&1 || true

# --- 3. TrueNAS-Config ------------------------------------------------------------------
section "TrueNAS-Config"
mkdir -p "$RUN/truenas"
# shellcheck disable=SC2016  # laeuft auf TrueNAS, $t soll dort expandieren
ts 'set -e; t=$(mktemp -d); trap "rm -rf $t" EXIT
    if command -v sqlite3 >/dev/null; then sqlite3 /data/freenas-v1.db ".backup $t/freenas-v1.db"
    else cp /data/freenas-v1.db "$t/"; fi
    cp /data/pwenc_secret "$t/"
    tar -C "$t" -cf - freenas-v1.db pwenc_secret' > "$RUN/truenas/truenas-config-$STAMP.tar"
tar -tf "$RUN/truenas/truenas-config-$STAMP.tar" | grep -q pwenc_secret || die "TrueNAS-Config unvollständig."
ok "truenas-config-$STAMP.tar mit pwenc_secret"

# --- 4. Vaultwarden- und Home-Assistant-Backup ------------------------------------------
section "Vaultwarden und Home Assistant"
fetch_newest "Vaultwarden" "$VW_DIR" 'vaultwarden-backup-*.tar.gz' "$VW_MAX_DAYS" "$RUN/vaultwarden"
fetch_newest "Home Assistant" "$HA_DIR" 'automatic_backup_*.tar' "$HA_MAX_DAYS" "$RUN/homeassistant"

# --- 5. vzdump: neuestes Archiv je Gast (mit .log und .notes) ----------------------------
section "Proxmox vzdump"
mkdir -p "$RUN/proxmox-vzdump"
dump_files="$(ts "cd '$DUMP_DIR' && find . -maxdepth 1 -type f -name 'vzdump-*' ! -name '*.log' ! -name '*.notes' -mtime -$DUMP_MAX_DAYS -printf '%T@ %f\n' \
    | sort -rn | awk '{ split(\$2, a, \"-\"); if (!(a[3] in seen)) { seen[a[3]] = 1; p = \$2; sub(/\\.(tar|vma)(\\.(zst|gz|lzo))?\$/, \"\", p); print p } }' \
    | while read -r p; do ls -1 \"\$p\".*; done")"
if [ -z "$dump_files" ]; then
    warn "keine vzdump-Archive jünger als $DUMP_MAX_DAYS Tage in $DUMP_DIR"
else
    guests=$(echo "$dump_files" | grep -cE '\.(zst|gz|lzo)$' || true)
    n=0
    for f in $dump_files; do
        case "$f" in
            *.zst|*.gz|*.lzo) n=$((n + 1)); info "[$n/$guests] $f"
                              rsync -a $PROGRESS -e "$SSH" "$TRUENAS:$DUMP_DIR/$f" "$RUN/proxmox-vzdump/" ;;
            *)                rsync -a -e "$SSH" "$TRUENAS:$DUMP_DIR/$f" "$RUN/proxmox-vzdump/" ;;
        esac
    done
    ok "$guests Gäste, $(size "$RUN/proxmox-vzdump")"
fi

# --- 6. Nextcloud -----------------------------------------------------------------------
section "Nextcloud"
if [ -d "$NEXTCLOUD_DIR" ]; then
    link=""
    [ -n "$PREV" ] && [ -d "${PREV}nextcloud" ] && link="--link-dest=${PREV}nextcloud"
    info "$NEXTCLOUD_DIR${link:+ (unveränderte Dateien als Hardlink zum letzten Lauf)}"
    rsync -a ${link:+"$link"} --exclude '.DS_Store' --exclude '.sync_*.db*' --exclude '._sync_*.db*' \
        --exclude '.owncloudsync.log*' --exclude '.nextcloudsync.log*' \
        "$NEXTCLOUD_DIR/" "$RUN/nextcloud/"
    ok "$(find "$RUN/nextcloud" -type f | wc -l | tr -d ' ') Dateien, $(size "$RUN/nextcloud")"
else
    warn "Nextcloud-Ordner $NEXTCLOUD_DIR nicht gefunden"
fi

# --- 7. Nextcloud-Fotos direkt von TrueNAS ---------------------------------------------
section "Nextcloud-Fotos"
if ts "test -d '$FOTOS_DIR'"; then
    link=""
    [ -n "$PREV" ] && [ -d "${PREV}nextcloud-fotos" ] && link="--link-dest=${PREV}nextcloud-fotos"
    info "$TRUENAS:$FOTOS_DIR${link:+ (unveränderte Dateien als Hardlink zum letzten Lauf)}"
    # Probelauf zaehlt, was neu kopiert werden muss; der echte Lauf zaehlt dann hoch.
    # --out-format listet nur uebertragene Dateien, per Hardlink uebernommene nicht.
    fotos_all=$(ts "find '$FOTOS_DIR' -type f | wc -l" | tr -d ' ')
    fotos_new=$(rsync -an ${link:+"$link"} --out-format='%n' -e "$SSH" "$TRUENAS:$FOTOS_DIR/" "$RUN/nextcloud-fotos/" \
        | grep -vc '/$' || true)
    info "$fotos_all Dateien auf TrueNAS, davon $fotos_new neu zu kopieren"
    n=0 arrow="$(paint '>' 36)"
    rsync -a ${link:+"$link"} --out-format='%n' -e "$SSH" "$TRUENAS:$FOTOS_DIR/" "$RUN/nextcloud-fotos/" \
        | while IFS= read -r f; do
            case "$f" in */) continue ;; esac
            n=$((n + 1))
            if [ "$COLOR" = 1 ]; then printf '\r  %s %d/%d Fotos kopiert' "$arrow" "$n" "$fotos_new"; fi
        done
    if [ "$COLOR" = 1 ] && [ "$fotos_new" -gt 0 ]; then echo; fi
    ok "$(find "$RUN/nextcloud-fotos" -type f | wc -l | tr -d ' ') Dateien, $(size "$RUN/nextcloud-fotos")"
else
    warn "Fotos-Ordner $FOTOS_DIR auf TrueNAS nicht gefunden"
fi

# --- 8. GitHub-Repos --------------------------------------------------------------------
section "GitHub-Repos"
mkdir -p "$RUN/git"
done_repos=""
for r in $REPOS; do
    if err="$(git clone -q --mirror "$GIT_URL/$r.git" "$RUN/git/$r.git" 2>&1)"; then done_repos="$done_repos $r"
    else warn "git clone $r fehlgeschlagen: $(printf '%s' "$err" | grep -v '^$' | tail -1)"; fi
done
[ -z "$done_repos" ] || ok "$(echo "$done_repos" | wc -w | tr -d ' ') Repos:$done_repos"

# --- 9. Pruefsummen, Anleitung, abschliessen ----------------------------------------------
section "Abschluss"
[ -f "$HERE/usb-backup.md" ] && cp "$HERE/usb-backup.md" "$RUN/LIESMICH.md"
[ -f "$HERE/nextcloud-2fa.md" ] && cp "$HERE/nextcloud-2fa.md" "$RUN/NEXTCLOUD-2FA.md"
info "SHA256SUMS berechnen"
# shellcheck disable=SC2094  # find laesst SHA256SUMS aus
(cd "$RUN" && find . -type f ! -name SHA256SUMS -print0 | xargs -0 shasum -a 256 > SHA256SUMS)
[ -n "$WARN" ] && printf '%s' "$WARN" > "$RUN/WARNUNGEN.txt"
mv "$RUN" "$BASE/$STAMP"
RUN="$BASE/$STAMP"
ok "$(wc -l < "$RUN/SHA256SUMS" | tr -d ' ') Dateien, $(size "$RUN")"

ls -1d "$BASE"/20*/ | sort -r | tail -n +$((KEEP + 1)) | while read -r old; do
    rm -rf "$old"
    ok "alten Lauf $(basename "$old") gelöscht"
done

if [ -n "$KUMA_URL" ]; then
    n=$(printf '%s' "$WARN" | grep -c . || true)
    curl -fsS -m 10 -o /dev/null "${KUMA_URL%%\?*}?status=up&msg=OK%20${n}%20Warnungen" \
        || warn "Push an Uptime Kuma fehlgeschlagen"
fi

secs=$(( $(date +%s) - T0 ))
if [ -z "$WARN" ]; then
    box "Fertig ohne Warnungen" 32
else
    box "Fertig mit $(printf '%s' "$WARN" | grep -c .) Warnungen" 33
    printf '%s' "$WARN" | while IFS= read -r w; do echo "  $(paint '[!!]' 1 33) ${w#- }"; done
fi
field "Ordner" "$RUN"
field "Belegt" "$(size "$RUN"), $(( $(df -k "$DISK" | awk 'NR==2 {print $4}') / 1024 / 1024 )) GB frei"
field "Dauer" "$((secs / 60)) Min. $((secs % 60)) Sek."
field "Kopien" "$(ls -1d "$BASE"/20*/ | wc -l | tr -d ' ') von $KEEP"
echo
info "Disk auswerfen: $(paint "diskutil eject $DISK" 1)"
echo
