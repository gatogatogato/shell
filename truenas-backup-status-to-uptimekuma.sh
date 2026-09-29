#!/usr/bin/env bash
# Meldet den Status der TrueNAS-Backup-Tasks per Push an Uptime Kuma.
# Laeuft auf TrueNAS als root (Cron Job), Doku: truenas-backup-status-to-uptimekuma.md
#
#   truenas-backup-status-to-uptimekuma.sh            alle Checks aus der Konfig pruefen und pushen
#   truenas-backup-status-to-uptimekuma.sh --dry-run  nur anzeigen, nichts pushen
#   truenas-backup-status-to-uptimekuma.sh --list     alle Tasks mit ID anzeigen (fuer die Konfig)
#
# Konfig (Push-URLs, gehoert nicht ins Repo): neben dem Skript mit Endung .conf,
# oder Pfad in CONFIG=... angeben. Format siehe Doku.

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
CONFIG=${CONFIG:-"${SCRIPT_DIR}/$(basename "$0" .sh).conf"}
DRY_RUN=0

# Die Task-Typen und wo midclt ihren letzten Lauf ablegt
# (Replikation und Snapshots in .state, Cloud Sync, TrueCloud Backup und Rsync in .job).
declare -A QUERY=([replication]=replication.query [snapshot]=pool.snapshottask.query
                  [cloudsync]=cloudsync.query [cloudbackup]=cloud_backup.query
                  [rsync]=rsynctask.query)
declare -A FIELD=([replication]=state [snapshot]=state [cloudsync]=job [cloudbackup]=job [rsync]=job)

die() { echo "FEHLER: $*" >&2; exit 2; }

# Wandelt einen midclt-Zeitstempel ({"$date": ms}, ms, s oder ISO-Text) in Epochensekunden.
to_epoch() {
    local v=$1
    [[ -z "$v" || "$v" == null ]] && return 1
    if [[ "$v" =~ ^[0-9]+$ ]]; then
        (( v > 100000000000 )) && v=$(( v / 1000 ))
        echo "$v"
    else
        date -d "$v" +%s 2>/dev/null
    fi
}

# Letzter Lauf eines Tasks als "STATUS<TAB>ZEIT<TAB>FEHLER".
task_state() {
    local type=$1 id=$2 f=${FIELD[$1]}
    midclt call "${QUERY[$type]}" "[[\"id\", \"=\", ${id}]]" \
        | jq -r --arg f "$f" '
            def ts: if type == "object" then .["$date"] else . end;
            .[0] // empty | .[$f] // {} |
            [ (.state // "UNBEKANNT"),
              ((.time_finished // .datetime // .time_started // null) | ts // "" | tostring),
              ((.error // "") | tostring | gsub("[\t\n]"; " ")) ] | @tsv'
}

push() {
    local url=${1%%\?*} status=$2 msg=$3
    echo "  -> ${status}: ${msg}"
    (( DRY_RUN )) && return 0
    local answer
    # Uptime Kuma antwortet {"ok":true}; alles andere (falscher Token, pausierter Monitor) ist ein Fehler.
    answer=$(curl -sS -m 15 --retry 2 --get \
        --data-urlencode "status=${status}" --data-urlencode "msg=${msg}" "$url" 2>&1)
    [[ "$answer" == *'"ok":true'* ]] \
        || { echo "  !! Push an Uptime Kuma fehlgeschlagen: ${answer:-keine Antwort}" >&2; return 1; }
}

check_task() {
    local type=$1 id=$2 max_hours=$3 state when error ts age
    IFS=$'\t' read -r state when error < <(task_state "$type" "$id")
    [[ -z "${state:-}" ]] && { echo "down	${type} ${id} nicht gefunden"; return; }
    ts=$(to_epoch "$when") || ts=0
    age=$(( ( $(date +%s) - ts ) / 3600 ))
    (( age < 0 )) && age=0
    case "$state" in
        RUNNING|PENDING|WAITING)
            echo "up	laeuft (${state})" ;;
        FINISHED|SUCCESS)
            if (( age > max_hours )); then
                echo "down	letzter Erfolg vor ${age} h (erlaubt ${max_hours} h)"
            else
                echo "up	OK vor ${age} h"
            fi ;;
        *)
            echo "down	${state}: ${error:-kein Fehlertext}" ;;
    esac
}

# Neueste Datei unterhalb eines Ordners, z. B. das eingehende Vaultwarden-Backup.
check_file() {
    local dir=$1 max_hours=$2 newest age
    [[ -d "$dir" ]] || { echo "down	Ordner ${dir} fehlt"; return; }
    newest=$(find "$dir" -type f -printf '%T@ %s %p\n' 2>/dev/null | sort -n | tail -1)
    [[ -z "$newest" ]] && { echo "down	keine Datei in ${dir}"; return; }
    read -r mtime size path <<< "$newest"
    age=$(( ( $(date +%s) - ${mtime%.*} ) / 3600 ))
    if (( size == 0 )); then
        echo "down	neueste Datei ist leer: ${path##*/}"
    elif (( age > max_hours )); then
        echo "down	neueste Datei vor ${age} h (erlaubt ${max_hours} h): ${path##*/}"
    else
        echo "up	${path##*/} vor ${age} h, $(( size / 1024 / 1024 )) MB"
    fi
}

# Proxmox-vzdump-Ordner: das neueste Archiv jedes Gasts muss juenger als max_hours sein.
# Gaeste, deren neuestes Archiv aelter als 3 * max_hours ist, gelten als entfernt
# (vzdump raeumt ihre alten Archive nicht weg) und werden nur mitgezaehlt.
check_vzdump() {
    local dir=$1 max_hours=$2 now vmid mtime size age total=0 retired=0 bad=()
    [[ -d "$dir" ]] || { echo "down	Ordner ${dir} fehlt"; return; }
    now=$(date +%s)
    while read -r vmid mtime size; do
        age=$(( ( now - mtime ) / 3600 ))
        if (( age > 3 * max_hours )); then
            retired=$(( retired + 1 ))
        elif (( size == 0 )); then
            bad+=("${vmid} leer")
        elif (( age > max_hours )); then
            bad+=("${vmid} vor ${age} h")
        fi
        total=$(( total + 1 ))
    done < <(find "$dir" -maxdepth 1 -type f -name 'vzdump-*' ! -name '*.log' ! -name '*.notes' \
                 -printf '%f %T@ %s\n' 2>/dev/null \
             | sed -nE 's/^vzdump-(lxc|qemu)-([0-9]+)-[^ ]* ([0-9]+)[.0-9]* ([0-9]+)$/\2 \3 \4/p' \
             | sort -k1,1n -k2,2n | awk '{ last[$1] = $0 } END { for (v in last) print last[v] }')
    (( total == 0 )) && { echo "down	keine vzdump-Archive in ${dir}"; return; }
    local active=$(( total - retired )) note=""
    (( retired )) && note=", ${retired} alte Gaeste ignoriert"
    if (( ${#bad[@]} )); then
        echo "down	${#bad[@]} von ${active} Gaesten ohne frisches Backup (erlaubt ${max_hours} h): ${bad[*]}${note}"
    else
        echo "up	${active} Gaeste gesichert${note}"
    fi
}

list_tasks() {
    echo "Typ          ID  Name                                   letzter Status"
    local type
    for type in replication snapshot cloudsync cloudbackup rsync; do
        midclt call "${QUERY[$type]}" 2>/dev/null | jq -r --arg t "$type" --arg f "${FIELD[$type]}" '
            .[] | [ $t, (.id | tostring),
                    (.name // .description // .dataset // .path // "" | tostring),
                    (.[$f].state // "-") ]
                | "\(.[0] | . + "             " | .[:12]) \(.[1] | "   " + . | .[-3:])  \(.[2] | . + (" " * 38) | .[:38]) \(.[3])"'
    done
}

case "${1:-}" in
    --list)    list_tasks; exit 0 ;;
    --dry-run) DRY_RUN=1 ;;
    "")        ;;
    *)         sed -n '2,10p' "$0"; exit 2 ;;
esac

command -v jq >/dev/null     || die "jq fehlt"
command -v midclt >/dev/null || die "midclt fehlt (laeuft das Skript auf TrueNAS?)"
[[ -r "$CONFIG" ]]           || die "Konfig ${CONFIG} nicht lesbar"

failed=0   # nur Konfig- oder Push-Fehler; ein DOWN meldet Uptime Kuma, nicht TrueNAS
while read -r line; do
    read -r type target max_hours url _ <<< "${line%%#*}"   # Kommentare ab # ignorieren
    [[ -z "${type:-}" ]] && continue
    [[ -n "${url:-}" && "$max_hours" =~ ^[0-9]+$ ]] || die "Zeile unvollstaendig: ${type} ${target} ${max_hours:-}"
    echo "${type} ${target}"
    if [[ "$type" == file ]]; then
        result=$(check_file "$target" "$max_hours")
    elif [[ "$type" == vzdump ]]; then
        result=$(check_vzdump "$target" "$max_hours")
    elif [[ -n "${QUERY[$type]:-}" ]]; then
        result=$(check_task "$type" "$target" "$max_hours")
    else
        die "unbekannter Typ: ${type}"
    fi
    status=${result%%$'\t'*}
    push "$url" "$status" "${result#*$'\t'}" || failed=1
done < "$CONFIG"

exit "$failed"
