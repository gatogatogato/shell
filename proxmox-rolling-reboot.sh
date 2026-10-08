#!/bin/bash
# Rolling Reboot der Proxmox-Nodes n01 und n02, ohne dass ein Gast lange weg ist.
# Doku: proxmox-rolling-reboot.md
#
#   1. alle Gaeste von n01 nach n02 migrieren, n01 neu starten
#   2. alle Gaeste von n02 nach n01 migrieren, n02 neu starten
#   3. alle Gaeste mit Tag node02 zurueck nach n02
#
# Gaeste mit Tag nomigrate (doppelt vorhandene wie Pi-hole und cloudflared) werden nie migriert,
# sondern mit ihrem Node heruntergefahren und per "Beim Booten starten" wieder gestartet.
# Gaeste mit Tag stopfirst (Uptime Kuma, damit es keine Fehlalarme gibt) stoppt das Skript
# am Anfang und startet sie ganz am Schluss wieder.
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
PIN_TAG="nomigrate"                              # bleiben auf ihrem Node und starten mit ihm neu
STOP_TAG="stopfirst"                             # am Anfang stoppen, ganz am Schluss wieder starten
SSH_USER="root"
CT_TIMEOUT=180                                   # Sekunden, die ein Container zum Herunterfahren hat
PARALLEL=4                                       # so viele Migrationen gleichzeitig (wie im GUI)
STATE_TIMEOUT=120                                # so lange darf ein Gast nach der Migration zum Starten brauchen
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
Usage: $(basename "$0") [--dry-run] [--yes] [--help]

Rolling Reboot: alle Gaeste von $NODE_A_HOST nach $NODE_B_HOST, $NODE_A_HOST neu starten,
alle nach $NODE_A_HOST, $NODE_B_HOST neu starten, Gaeste mit Tag $HOME_TAG zurueck.

    --dry-run    Probelauf: pruefen und den Plan mit allen Befehlen zeigen, nichts aendern
    --yes        ohne Rueckfrage starten
    --help       diese Hilfe
EOF
    exit 1
}

DRY=0
YES=0
for arg in ${1+"$@"}; do
    case $arg in
        --dry-run) DRY=1 ;;
        --yes)     YES=1 ;;
        *)         usage ;;
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
STEPS=10
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
STOPPED=""         # vom Skript gestoppte Gaeste, am Schluss wieder starten
die()   {
    echo "  $(paint '[XX]' 1 31) $(paint "$*" 31)"
    [ -z "$STOPPED" ] || echo "  $(paint '[!!]' 1 33) Vom Skript gestoppt und noch nicht wieder gestartet:$STOPPED"
    echo; exit 1
}
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

# Ob ein Gast beim Booten des Nodes startet: 1 oder 0
onboot() {         # <host> <node> <typ> <vmid>
    pve "$1" pvesh get "/nodes/$2/$3/$4/config" --output-format json | perl -MJSON::PP -e '
        print decode_json(do { local $/; <STDIN> })->{onboot} ? 1 : 0;'
}

# Filter fuer Zeilen aus guests(): ohne bzw. nur die Gaeste mit Tag $PIN_TAG
unpinned() { awk -v t="$PIN_TAG" 'index(";" $5 ";", ";" t ";") == 0'; }
pinned()   { awk -v t="$PIN_TAG" 'index(";" $5 ";", ";" t ";") > 0'; }

# Faehrt einen Gast herunter bzw. startet ihn (auf dem Node, auf dem er gerade ist) und wartet,
# bis der Cluster den neuen Status meldet
power() {          # <shutdown|start> <vmid>
    local id type node status rest host cmd want now
    read -r id type node status rest << EOF
$(guests "$NODE_A_HOST" | awk -v id="$2" '$1 == id')
EOF
    case "$node" in "$A") host="$NODE_A_HOST" ;; "$B") host="$NODE_B_HOST" ;; *) die "$2 ist auf $node" ;; esac
    case "$type:$1" in
        qemu:shutdown) cmd="qm shutdown $2 --timeout $CT_TIMEOUT"; want=stopped ;;
        lxc:shutdown)  cmd="pct shutdown $2 --timeout $CT_TIMEOUT"; want=stopped ;;
        qemu:start)    cmd="qm start $2"; want=running ;;
        lxc:start)     cmd="pct start $2"; want=running ;;
    esac
    info "$2 ${rest##* } auf $node: $cmd"
    pve "$host" "$cmd" > /dev/null 2>&1 || die "$cmd fehlgeschlagen"
    now="$(wait_state "$NODE_A_HOST" "$2" "$node" "$want")" || die "$2 ist '$now' statt '$node $want'"
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

# Wartet, bis ein Gast laut Cluster auf dem Ziel-Node ist und den erwarteten Status hat. Der
# Status kommt mit ein paar Sekunden Verzoegerung (pvestatd), ein Container ist nach der
# Migration zuerst kurz "stopped".
wait_state() {     # <host> <vmid> <ziel-node> <status>: gibt den letzten Stand aus, 1 bei Timeout
    local deadline=$(($(date +%s) + STATE_TIMEOUT)) now
    while :; do
        now="$(guests "$1" | awk -v id="$2" '$1 == id { print $3, $4 }')"
        [ "$now" = "$3 $4" ] && return 0
        [ "$(date +%s)" -lt "$deadline" ] || { echo "$now"; return 1; }
        sleep 3
    done
}

# Migriert die Gaeste aus der Liste, je $PARALLEL gleichzeitig (wie im GUI). Jeder Befehl laeuft
# auf dem Quell-Node und kommt erst zurueck, wenn die Migration fertig ist. Nach jeder Runde wird
# nachgeprueft; geht etwas schief, bricht es ab, ohne einen Node neu zu starten.
migrate_list() {   # <quell-host> <ziel-node> <liste aus guests()>
    local src="$1" target="$2" list="$3" tmp batch="" n=0 id type node status tags ha lock name
    [ -n "$list" ] || { info "nichts zu migrieren"; return; }
    tmp="$(mktemp -d)"
    while read -r id type node status tags ha lock name; do
        info "$id $name ($type, $status) -> $target"
        ( rc=0
          pve "$src" "$(migrate_cmd "$id" "$type" "$status" "$target")" > "$tmp/$id.out" 2>&1 || rc=$?
          echo "$rc" > "$tmp/$id.rc" ) &
        batch="$batch$id $status $name"$'\n'
        n=$((n + 1))
        if [ "$n" -ge "$PARALLEL" ]; then migrate_wait "$src" "$target" "$tmp" "$batch"; batch=""; n=0; fi
    done << EOF
$list
EOF
    [ -z "$batch" ] || migrate_wait "$src" "$target" "$tmp" "$batch"
    rm -rf "$tmp"
}

migrate_wait() {   # <quell-host> <ziel-node> <tmp-dir> <"vmid status name" pro zeile>
    local src="$1" target="$2" tmp="$3" t0 failed="" id status name now
    t0=$(date +%s)
    wait
    while read -r id status name; do
        [ -n "$id" ] || continue
        if [ "$(cat "$tmp/$id.rc")" != 0 ]; then
            warn "Migration von $id $name fehlgeschlagen:"
            tail -n 15 "$tmp/$id.out" | sed 's/^/      /'
            failed="$failed $id"
        elif now="$(wait_state "$src" "$id" "$target" "$status")"; then
            ok "$id $name auf $target, $status"
        else
            warn "$id $name ist nach $STATE_TIMEOUT s '$now' statt '$target $status'"
            failed="$failed $id"
        fi
    done << EOF
$4
EOF
    [ -z "$failed" ] || { rm -rf "$tmp"; die "Problem mit$failed. Abbruch, es wird kein Node neu gestartet."; }
    info "Runde fertig ($(mmss $(($(date +%s) - t0))))"
}

# Startet einen Node neu, auf dem nur noch Gaeste mit Tag $PIN_TAG sind, und wartet, bis er
# wieder im Cluster ist und diese Gaeste wieder laufen
reboot_node() {    # <host> <node> <host des anderen nodes>
    local host="$1" node="$2" other="$3" left stay boot t0 deadline new state down id
    left="$(guests "$other" | awk -v n="$node" '$3 == n' | unpinned)"
    [ -z "$left" ] || die "Auf $node sind noch Gaeste, kein Neustart: $(echo "$left" | awk '{ print $1 }' | tr '\n' ' ' | sed 's/ $//')"
    [ "$(quorum_spare "$other")" = ja ] || die "Ohne $node haette der Cluster kein Quorum mehr. Abbruch."

    stay="$(guests "$other" | awk -v n="$node" '$3 == n && $4 == "running" { print $1 }' | tr '\n' ' ' | sed 's/ $//')"
    [ -z "$stay" ] || info "Bleiben auf $node und starten mit ihm neu: $stay"

    boot="$(pve "$host" cat /proc/sys/kernel/random/boot_id)"
    info "$node startet neu"
    pve "$host" systemctl reboot || true
    t0=$(date +%s)
    deadline=$((t0 + BOOT_TIMEOUT))

    # 1. neu gebootet (andere boot_id), 2. im Cluster online mit Quorum, PVE-Dienste laufen,
    # 3. die gebliebenen Gaeste laufen wieder
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
                    && { state="Gaeste"; info "$node ist im Cluster, Quorum ok ($(mmss $(($(date +%s) - t0))))"; } ;;
            Gaeste)
                down=""
                for id in $stay; do
                    guests "$other" 2>/dev/null | awk -v id="$id" '$1 == id && $4 == "running"' | grep -q . || down="$down $id"
                done
                [ -z "$down" ] && break ;;
        esac
    done
    [ -z "$stay" ] || info "$stay laufen wieder"
    info "$SETTLE s Pause"
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
NOBOOT=""
while read -r id type node status rest; do
    [ -n "$id" ] && [ "$status" = running ] || continue
    [ "$(onboot "$NODE_A_HOST" "$node" "$type" "$id")" = 1 ] || NOBOOT="$NOBOOT $id"
done << EOF
$(echo "$START" | pinned)
EOF
[ -z "$NOBOOT" ] || die "Tag $PIN_TAG, aber 'Beim Booten starten' aus:$NOBOOT. Einschalten oder Tag entfernen."
ok "$(echo "$START" | awk -v n="$A" '$3 == n' | grep -c . || true) Gaeste auf $A, $(echo "$START" | awk -v n="$B" '$3 == n' | grep -c . || true) auf $B, keiner gesperrt oder HA-verwaltet"

section "Plan"
# Gaeste mit $STOP_TAG sind beim Migrieren schon gestoppt
PLANNED="$(echo "$START" | awk -v t="$STOP_TAG" 'index(";" $5 ";", ";" t ";") > 0 { $4 = "stopped" } { print }')"
P1="$(echo "$PLANNED" | awk -v n="$A" '$3 == n' | unpinned)"
P2="$(echo "$PLANNED" | awk -v a="$A" -v b="$B" '$3 == a || $3 == b' | unpinned)"
PINNED="$(echo "$START" | awk -v a="$A" -v b="$B" '$3 == a || $3 == b' | pinned | awk '{ printf "%s %s (%s), ", $1, $8, $3 }')"
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
TOSTOP="$(echo "$START" | awk '$4 == "running"' | awk -v t="$STOP_TAG" 'index(";" $5 ";", ";" t ";") > 0' | awk '{ printf "%s %s, ", $1, $8 }')"
[ -z "$TOSTOP" ] || info "Tag $STOP_TAG, werden zuerst gestoppt und am Schluss wieder gestartet: ${TOSTOP%, }"
[ -z "$PINNED" ] || info "Tag $PIN_TAG, bleiben und starten mit ihrem Node neu: ${PINNED%, }"
print_plan "1. alle Gaeste von $A nach $B" "$B" "$P1"
info "2. $A neu starten"
print_plan "3. alle Gaeste nach $A" "$A" "$P2"
info "4. $B neu starten"
print_plan "5. Gaeste mit Tag $HOME_TAG zurueck nach $B" "$B" "$P3"
[ -z "$NOTAG" ] || warn "Jetzt auf $B ohne Tag $HOME_TAG, bleiben danach auf $A: ${NOTAG%, }"

if [ "$DRY" = 1 ]; then
    echo
    ok "Probelauf: nichts geaendert. Starten ohne --dry-run."
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
section "Gaeste mit Tag $STOP_TAG stoppen"
for id in $(guests "$NODE_A_HOST" | awk '$4 == "running"' | awk -v t="$STOP_TAG" 'index(";" $5 ";", ";" t ";") > 0 { print $1 }'); do
    STOPPED="$STOPPED $id"
    power shutdown "$id"
    ok "$id gestoppt"
done
[ -n "$STOPPED" ] || info "keine"

section "Alle Gaeste von $A nach $B"
migrate_list "$NODE_A_HOST" "$B" "$(guests "$NODE_A_HOST" | awk -v n="$A" '$3 == n' | unpinned)"

section "$A neu starten"
reboot_node "$NODE_A_HOST" "$A" "$NODE_B_HOST"

section "Alle Gaeste von $B nach $A"
migrate_list "$NODE_B_HOST" "$A" "$(guests "$NODE_B_HOST" | awk -v n="$B" '$3 == n' | unpinned)"

section "$B neu starten"
reboot_node "$NODE_B_HOST" "$B" "$NODE_A_HOST"

section "Gaeste mit Tag $HOME_TAG zurueck nach $B"
BACK=""
while read -r id type node status tags ha lock name; do
    [ -n "$id" ] && [ "$node" = "$A" ] && has_tag "$tags" "$HOME_TAG" && ! has_tag "$tags" "$PIN_TAG" \
        && BACK="$BACK$id $type $node $status $tags $ha $lock $name"$'\n'
done << EOF
$(guests "$NODE_A_HOST")
EOF
migrate_list "$NODE_A_HOST" "$B" "${BACK%$'\n'}"

section "Gaeste mit Tag $STOP_TAG wieder starten"
[ -n "$STOPPED" ] || info "keine"
while [ -n "$STOPPED" ]; do
    id="${STOPPED# }"; id="${id%% *}"
    power start "$id"
    STOPPED="${STOPPED# "$id"}"
    ok "$id laeuft wieder"
done

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
