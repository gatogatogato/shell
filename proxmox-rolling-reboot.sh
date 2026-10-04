#!/bin/bash
# Rolling Reboot der Proxmox-Nodes n01 und n02, ohne dass ein Gast lange weg ist.
# Doku: proxmox-rolling-reboot.md
#
#   1. alle Gaeste von n01 nach n02 migrieren, n01 neu starten
#   2. alle Gaeste von n02 nach n01 migrieren, n02 neu starten
#   3. alle Gaeste mit Tag node02 zurueck nach n02
#
# Laeuft auf dem Mac (oder auf proxmox-n03) und steuert die Nodes per ssh als root. Auf n01
# oder n02 selbst geht es nicht, weil das Skript den eigenen Node neu starten muesste.
# proxmox-n03 bekommt nie einen Gast und wird nicht neu gestartet.
# Gestoppte Gaeste werden offline migriert und bleiben gestoppt.
#
# Konfig (optional): ~/.config/proxmox-rolling-reboot.conf, jede Variable unten laesst sich dort
# ueberschreiben. Laeuft mit dem bash 3.2 von macOS.
set -euo pipefail

CONFIG="${CONFIG:-$HOME/.config/proxmox-rolling-reboot.conf}"

NODE_A_HOST="proxmox-n01.lan"                    # wird zuerst neu gestartet
NODE_B_HOST="proxmox-n02.lan"
HOME_TAG="node02"                                # Gaeste mit diesem Tag gehoeren auf NODE_B
SSH_USER="root"
CT_TIMEOUT=180                                   # Sekunden, die ein Container zum Herunterfahren hat
BOOT_TIMEOUT=900                                 # so lange darf ein Neustart dauern
SETTLE=30                                        # Pause, wenn ein Node wieder da ist

# shellcheck source=/dev/null
[ -f "$CONFIG" ] && . "$CONFIG"

# Mac nicht einschlafen lassen, solange das Skript laeuft
if [ "$(uname)" = Darwin ] && [ -z "${ROLLING_CAFFEINATED:-}" ] && command -v caffeinate >/dev/null; then
    ROLLING_CAFFEINATED=1 exec caffeinate -i "$0" ${1+"$@"}
fi

usage() {
    cat << EOF
Usage: $(basename "$0") [-n] [-y] [-h]

Rolling Reboot: alle Gaeste von $NODE_A_HOST nach $NODE_B_HOST, $NODE_A_HOST neu starten,
alle nach $NODE_A_HOST, $NODE_B_HOST neu starten, Gaeste mit Tag $HOME_TAG zurueck.

    -n    Probelauf: pruefen und den Plan mit allen Befehlen zeigen, nichts aendern
    -y    ohne Rueckfrage starten
    -h    diese Hilfe
EOF
    exit 1
}

DRY=0
YES=0
while getopts "nyh" opt; do
    case $opt in
        n) DRY=1 ;;
        y) YES=1 ;;
        *) usage ;;
    esac
done

# --- Ausgabe ----------------------------------------------------------------------------
# Gleicher Look wie usb-backup.sh. Farben nur im Terminal, NO_COLOR schaltet ab.
WIDTH=78
if [ -t 1 ] && [ -z "${NO_COLOR+x}" ]; then COLOR=1; else COLOR=0; fi

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
STEPS=8
[ "$DRY" = 1 ] && STEPS=2
section() {
    STEP=$((STEP + 1))
    local label="--[ $STEP/$STEPS ]-- $1 "
    echo
    paint "$label$(line $((WIDTH - ${#label})) -)" 1 36; echo
}
info()  { echo "  $(paint '>' 36) $*"; }
ok()    { echo "  $(paint '[OK]' 1 32) $*"; }
warn()  { echo "  $(paint '[!!]' 1 33) $*"; }
die()   { echo "  $(paint '[XX]' 1 31) $(paint "$*" 31)"; echo; exit 1; }
mmss()  { printf '%d:%02d' $(($1 / 60)) $(($1 % 60)); }

# --- Proxmox ----------------------------------------------------------------------------
pve() {            # <host> <befehl...>: Befehl als root auf dem Node
    local host="$1"; shift
    ssh -n -o BatchMode=yes -o ConnectTimeout=5 -o ServerAliveInterval=5 -o ServerAliveCountMax=3 \
        "$SSH_USER@$host" "$@"
}

# Alle Gaeste im Cluster, eine Zeile pro Gast: "vmid typ node status tags ha lock name"
# (tags mit ; getrennt, "-" fuer leer). Geparst mit dem perl des Macs.
guests() {         # <host, ueber den gefragt wird>
    pve "$1" pvesh get /cluster/resources --type vm --output-format json | perl -MJSON::PP -e '
        my $d = decode_json(do { local $/; <STDIN> });
        for my $g (sort { $a->{vmid} <=> $b->{vmid} } @$d) {
            my $t = $g->{tags} // ""; $t =~ s/[\s,;]+/;/g; $t =~ s/^;|;$//g; $t = "-" if $t eq "";
            print join(" ", $g->{vmid}, $g->{type}, $g->{node}, $g->{status}, $t,
                       $g->{hastate} // "-", $g->{lock} // "-", $g->{name} // "-"), "\n";
        }'
}

# Nodes laut Cluster: "name online" pro Zeile
cluster_nodes() {  # <host>
    pve "$1" pvesh get /cluster/status --output-format json | perl -MJSON::PP -e '
        my $d = decode_json(do { local $/; <STDIN> });
        for (@$d) { print "$_->{name} ", ($_->{online} // 0), "\n" if $_->{type} eq "node" }'
}

# "ja", wenn der Cluster auch ohne eine Stimme noch Quorum hat (zaehlt auch ein QDevice mit)
quorum_spare() {   # <host>
    pve "$1" pvecm status | awk -F: '
        /^Quorate:/     { q = ($2 ~ /Yes/) }
        /^Total votes:/ { t = $2 + 0 }
        /^Quorum:/      { n = $2 + 0 }
        END { print (q && t - 1 >= n) ? "ja" : "nein" }'
}

# Laufende Tasks eines Nodes (Backup, Migration ...), leer wenn keine
active_tasks() {   # <host> <node>
    pve "$1" pvesh get "/nodes/$2/tasks" --source active --output-format json | perl -MJSON::PP -e '
        my $d = decode_json(do { local $/; <STDIN> });
        print join(", ", map { $_->{type} . ($_->{id} ? " $_->{id}" : "") } @$d);'
}

has_tag() {        # <tags> <tag>
    case ";$1;" in *";$2;"*) return 0 ;; *) return 1 ;; esac
}

migrate_cmd() {    # <vmid> <typ> <status> <ziel-node>
    case "$2:$3" in
        qemu:running) echo "qm migrate $1 $4 --online --with-local-disks" ;;
        qemu:*)       echo "qm migrate $1 $4" ;;
        lxc:running)  echo "pct migrate $1 $4 --restart --timeout $CT_TIMEOUT" ;;
        lxc:*)        echo "pct migrate $1 $4" ;;
    esac
}

# Migriert die Gaeste aus der Liste nacheinander. Jeder Befehl laeuft auf dem Quell-Node und
# kommt erst zurueck, wenn die Migration fertig ist. Danach wird nachgeprueft.
migrate_list() {   # <quell-host> <ziel-node> <liste aus guests()>
    local src="$1" target="$2" list="$3" id type node status tags ha lock name cmd t0 out now
    [ -n "$list" ] || { info "nichts zu migrieren"; return; }
    while read -r id type node status tags ha lock name; do
        cmd="$(migrate_cmd "$id" "$type" "$status" "$target")"
        info "$id $name ($type, $status) -> $target"
        t0=$(date +%s)
        out="$(mktemp)"
        if ! pve "$src" "$cmd" > "$out" 2>&1; then
            tail -n 15 "$out" | sed 's/^/      /'
            rm -f "$out"
            die "Migration von $id $name fehlgeschlagen. Abbruch, es wird kein Node neu gestartet."
        fi
        rm -f "$out"
        now="$(guests "$src" | awk -v id="$id" '$1 == id { print $3, $4 }')"
        [ "$now" = "$target $status" ] \
            || die "$id $name ist nach der Migration '$now' statt '$target $status'. Abbruch."
        ok "$id $name auf $target, $status ($(mmss $(($(date +%s) - t0))))"
    done << EOF
$list
EOF
}

# Startet einen leeren Node neu und wartet, bis er wieder im Cluster ist
reboot_node() {    # <host> <node> <host des anderen nodes>
    local host="$1" node="$2" other="$3" left boot t0 deadline new state
    left="$(guests "$other" | awk -v n="$node" '$3 == n')"
    [ -z "$left" ] || die "Auf $node sind noch Gaeste, kein Neustart: $(echo "$left" | awk '{ print $1 }' | tr '\n' ' ' | sed 's/ $//')"
    [ "$(quorum_spare "$other")" = ja ] || die "Ohne $node haette der Cluster kein Quorum mehr. Abbruch."

    boot="$(pve "$host" cat /proc/sys/kernel/random/boot_id)"
    info "$node startet neu"
    pve "$host" systemctl reboot || true
    t0=$(date +%s)
    deadline=$((t0 + BOOT_TIMEOUT))

    # 1. neu gebootet (andere boot_id), 2. im Cluster online mit Quorum, 3. PVE-Dienste laufen
    state="Neustart"
    while :; do
        [ "$(date +%s)" -lt "$deadline" ] \
            || die "$node ist nach $(mmss "$BOOT_TIMEOUT") nicht zurueck ($state). Bitte selbst nachsehen, alle Gaeste laufen auf dem anderen Node."
        sleep 10
        case "$state" in
            Neustart)
                new="$(pve "$host" cat /proc/sys/kernel/random/boot_id 2>/dev/null || true)"
                [ -n "$new" ] && [ "$new" != "$boot" ] && { state="Cluster"; info "$node ist wieder erreichbar ($(mmss $(($(date +%s) - t0))))"; } ;;
            Cluster)
                cluster_nodes "$other" 2>/dev/null | grep -qx "$node 1" \
                    && [ "$(quorum_spare "$other" 2>/dev/null)" = ja ] \
                    && pve "$host" systemctl is-active --quiet pve-cluster corosync pvedaemon pveproxy pvestatd \
                    && pve "$other" pvesh get "/nodes/$node/status" > /dev/null 2>&1 \
                    && break ;;
        esac
    done
    info "$node ist im Cluster, Quorum ok. $SETTLE s Pause."
    sleep "$SETTLE"
    ok "$node neu gestartet ($(mmss $(($(date +%s) - t0))))"
}

print_plan() {     # <titel> <ziel-node> <liste>
    local id type node status tags ha lock name
    info "$1"
    [ -n "$3" ] || { echo "      (keine)"; return; }
    while read -r id type node status tags ha lock name; do
        printf '      %-5s %-24s %-8s %s\n' "$id" "$name" "$status" "$(migrate_cmd "$id" "$type" "$status" "$2")"
    done << EOF
$3
EOF
}

# --- Los --------------------------------------------------------------------------------
T0=$(date +%s)
if [ "$DRY" = 1 ]; then box "Proxmox Rolling Reboot, Probelauf" 37; else box "Proxmox Rolling Reboot $(date '+%d.%m.%Y %H:%M')" 37; fi

section "Pruefen"
HERE_NAME="$(hostname -s 2>/dev/null || hostname)"
A="$(pve "$NODE_A_HOST" hostname 2>/dev/null)" \
    || die "Kein ssh als $SSH_USER auf $NODE_A_HOST. Test: ssh $SSH_USER@$NODE_A_HOST hostname"
B="$(pve "$NODE_B_HOST" hostname 2>/dev/null)" \
    || die "Kein ssh als $SSH_USER auf $NODE_B_HOST. Test: ssh $SSH_USER@$NODE_B_HOST hostname"
[ "$A" != "$B" ] || die "$NODE_A_HOST und $NODE_B_HOST sind derselbe Node ($A)"
case "$HERE_NAME" in
    "$A"|"$B") die "Laeuft auf $HERE_NAME, der selbst neu gestartet wird. Auf dem Mac oder proxmox-n03 starten." ;;
esac
ok "ssh auf $A und $B"

NODES="$(cluster_nodes "$NODE_A_HOST")"
for n in "$A" "$B"; do
    echo "$NODES" | grep -qx "$n 1" || die "$n ist laut Cluster nicht online"
done
OTHERS="$(echo "$NODES" | awk -v a="$A" -v b="$B" '$1 != a && $1 != b { print $1 }' | tr '\n' ' ' | sed 's/ $//')"
[ "$(quorum_spare "$NODE_A_HOST")" = ja ] || die "Der Cluster haette ohne einen Node kein Quorum. Laeuft n03 bzw. das QDevice?"
ok "Cluster mit Quorum, auch wenn ein Node fehlt${OTHERS:+ (nicht angefasst: $OTHERS)}"

for n in "$A" "$B"; do
    TASKS="$(active_tasks "$NODE_A_HOST" "$n")"
    [ -z "$TASKS" ] || die "Auf $n laeuft gerade: $TASKS. Spaeter nochmal (Backup Sonntag 01:00)."
done

START="$(guests "$NODE_A_HOST")"
BAD="$(echo "$START" | awk '$6 != "-" { print $1 " " $8 " ist HA-verwaltet" }
                            $7 != "-" { print $1 " " $8 " ist gesperrt (" $7 ")" }
                            $4 != "running" && $4 != "stopped" { print $1 " " $8 " ist " $4 }')"
[ -z "$BAD" ] || die "Nicht migrierbar: $(echo "$BAD" | tr '\n' ';' | sed 's/;$//; s/;/; /g')"
ON_OTHER="$(echo "$START" | awk -v a="$A" -v b="$B" '$3 != a && $3 != b { print $1 " " $8 " auf " $3 }')"
[ -z "$ON_OTHER" ] || warn "Bleiben, wo sie sind: $(echo "$ON_OTHER" | tr '\n' ';' | sed 's/;$//; s/;/; /g')"
ok "$(echo "$START" | awk -v n="$A" '$3 == n' | grep -c . || true) Gaeste auf $A, $(echo "$START" | awk -v n="$B" '$3 == n' | grep -c . || true) auf $B, keiner gesperrt oder HA-verwaltet"

section "Plan"
P1="$(echo "$START" | awk -v n="$A" '$3 == n')"
P2="$(echo "$START" | awk -v a="$A" -v b="$B" '$3 == a || $3 == b')"
P3=""
NOTAG=""
while read -r id type node status tags ha lock name; do
    [ -n "$id" ] || continue
    if has_tag "$tags" "$HOME_TAG"; then P3="$P3$id $type $node $status $tags $ha $lock $name"$'\n'
    elif [ "$node" = "$B" ]; then NOTAG="$NOTAG$id $name, "; fi
done << EOF
$P2
EOF
P3="${P3%$'\n'}"
print_plan "1. alle Gaeste von $A nach $B" "$B" "$P1"
info "2. $A neu starten"
print_plan "3. alle Gaeste nach $A" "$A" "$P2"
info "4. $B neu starten"
print_plan "5. Gaeste mit Tag $HOME_TAG zurueck nach $B" "$B" "$P3"
[ -z "$NOTAG" ] || warn "Jetzt auf $B ohne Tag $HOME_TAG, bleiben danach auf $A: ${NOTAG%, }"

if [ "$DRY" = 1 ]; then
    echo
    ok "Probelauf: nichts geaendert. Starten ohne -n."
    echo
    exit 0
fi

if [ "$YES" != 1 ]; then
    echo
    printf '  Starten? Tippe "ja": '
    read -r answer
    [ "$answer" = ja ] || die "Nicht gestartet."
fi

# Jede Phase liest den Stand frisch, falls sich seit dem Plan etwas geaendert hat
section "Alle Gaeste von $A nach $B"
migrate_list "$NODE_A_HOST" "$B" "$(guests "$NODE_A_HOST" | awk -v n="$A" '$3 == n')"

section "$A neu starten"
reboot_node "$NODE_A_HOST" "$A" "$NODE_B_HOST"

section "Alle Gaeste von $B nach $A"
migrate_list "$NODE_B_HOST" "$A" "$(guests "$NODE_B_HOST" | awk -v n="$B" '$3 == n')"

section "$B neu starten"
reboot_node "$NODE_B_HOST" "$B" "$NODE_A_HOST"

section "Gaeste mit Tag $HOME_TAG zurueck nach $B"
BACK=""
while read -r id type node status tags ha lock name; do
    [ -n "$id" ] && [ "$node" = "$A" ] && has_tag "$tags" "$HOME_TAG" \
        && BACK="$BACK$id $type $node $status $tags $ha $lock $name"$'\n'
done << EOF
$(guests "$NODE_A_HOST")
EOF
migrate_list "$NODE_A_HOST" "$B" "${BACK%$'\n'}"

section "Ergebnis"
END="$(guests "$NODE_A_HOST")"
for n in "$A" "$B"; do
    info "$n: $(echo "$END" | awk -v n="$n" '$3 == n { printf "%s %s (%s), ", $1, $8, $4 }' | sed 's/, $//')"
done
# Laeuft alles, was vorher lief, und ist Gestopptes gestoppt geblieben?
CHANGED="$(echo "$START" | while read -r id type node status rest; do
    now="$(echo "$END" | awk -v id="$id" '$1 == id { print $4 }')"
    [ "$now" = "$status" ] || echo "$id vorher $status, jetzt ${now:-weg}"
done)"
if [ -n "$CHANGED" ]; then warn "Status geaendert: $(echo "$CHANGED" | tr '\n' ';' | sed 's/;$//; s/;/; /g')"
else ok "Alle Gaeste im gleichen Zustand wie vorher"; fi
box "Fertig in $(mmss $(($(date +%s) - T0)))" 32
echo
