# Rolling Reboot der Proxmox-Nodes

`proxmox-rolling-reboot.sh` startet proxmox-n01 und proxmox-n02 nacheinander neu, ohne dass
ein Gast länger weg ist als für seine Migration:

1. alle Gäste von n01 nach n02 migrieren, n01 neu starten
2. alle Gäste von n02 nach n01 migrieren, n02 neu starten
3. alle Gäste mit Tag `node02` zurück nach n02

Gäste ohne Tag `node02` bleiben danach auf n01. Gäste mit Tag `nomigrate` werden nie
migriert (siehe unten). proxmox-n03 wird nie angefasst und bekommt nie einen Gast.

## Gäste, die nicht wandern (Tag `nomigrate`)

Pi-hole und cloudflared gibt es je einmal pro Node (Pi-hole CT 117 auf n02 und CT 105 auf
n01, cloudflared1 auf n01 und cloudflared2 auf n02). Die müssen nicht umziehen: Während ein
Node neu startet, übernimmt der Zwilling auf dem anderen. Solche Gäste bekommen das Tag
`nomigrate`. Das Skript lässt sie stehen, Proxmox fährt sie mit dem Node sauber herunter und
startet sie beim Booten wieder. Das Skript wartet, bis sie wieder laufen, bevor es weitergeht.

Dafür muss beim Gast „Beim Booten starten“ an sein, sonst bricht das Skript schon bei der
Prüfung ab. Einrichten in der Proxmox-Oberfläche, pro Gast:

1. Gast anklicken, oben neben dem Namen auf den Stift bei den Tags, `nomigrate` hinzufügen
   (bestehende Tags wie `node02` bleiben), Haken.
2. „Optionen“ → „Beim Booten starten“ → Ja.

Nachprüfen auf proxmox-n02 als root (für 117, auf n01 entsprechend für 105 usw.):

```
pct config 117 | grep -E '^(tags|onboot)'
```

Erwartet: `onboot: 1` und `tags:` mit `nomigrate`.

## Wo es läuft

Auf dem Mac, im Checkout des shell-Repos. Das Skript steuert die Nodes per `ssh root@…`.
Auf n01 oder n02 selbst geht es nicht, weil es den eigenen Node neu starten müsste (es
bricht dort ab). proxmox-n03 geht auch, solange es ihn gibt.

Einmalig auf dem Mac testen, ob ssh als root ohne Passwort geht:

```
ssh -o BatchMode=yes root@proxmox-n01.lan hostname
ssh -o BatchMode=yes root@proxmox-n02.lan hostname
```

Kommt statt des Namens „Permission denied“, den Mac-Schlüssel einmal eintragen:

```
ssh-copy-id root@proxmox-n01.lan
ssh-copy-id root@proxmox-n02.lan
```

## Ablauf

Auf dem Mac im Terminal, erst der Probelauf (prüft alles und zeigt jeden Befehl, ändert nichts):

```
cd ~/Documents/Code/shell && git pull && ./proxmox-rolling-reboot.sh -n
```

Passt der Plan, ohne `-n` starten. Das Skript zeigt den Plan nochmal und fragt; mit `ja` geht
es los:

```
cd ~/Documents/Code/shell && ./proxmox-rolling-reboot.sh
```

Der Mac schläft währenddessen nicht ein (`caffeinate`). Den Deckel nicht zuklappen.

## Was es prüft

Vor dem Start bricht es ab, wenn

- ssh als root auf einen der Nodes nicht geht,
- ein Node offline ist oder der Cluster ohne einen Node kein Quorum mehr hätte
  (n03 bzw. später das QDevice muss laufen),
- auf n01 oder n02 gerade ein Task läuft (z. B. das Backup Sonntag 01:00),
- ein laufender Gast das Tag `nomigrate` hat, aber „Beim Booten starten“ aus ist,
- ein Gast gesperrt (Lock), HA-verwaltet oder weder `running` noch `stopped` ist.

Während des Laufs:

- Migrationen laufen nacheinander. Laufende VMs live (`qm migrate --online
  --with-local-disks`), laufende Container mit Neustart (`pct migrate --restart`, 180 s zum
  Herunterfahren), gestoppte Gäste offline. Gestoppte bleiben gestoppt (z. B. hercules).
- Nach jeder Migration prüft es, ob der Gast auf dem Ziel ist und im gleichen Zustand.
  Schlägt eine fehl, bricht es ab und startet keinen Node neu.
- Ein Node wird nur neu gestartet, wenn kein Gast mehr auf ihm ist (ausser mit Tag
  `nomigrate`).
- Nach dem Neustart wartet es, bis der Node neu gebootet hat, im Cluster online ist, der
  Cluster Quorum hat, die PVE-Dienste laufen und die `nomigrate`-Gäste wieder laufen, dann
  noch 30 s. Nach 15 min ohne Rückkehr bricht es ab; alle anderen Gäste laufen dann auf dem
  anderen Node.

Am Ende zeigt es, welcher Gast wo läuft, und warnt, falls ein Gast nicht mehr im gleichen
Zustand ist wie vorher.

## Einstellungen

Alles oben im Skript lässt sich in `~/.config/proxmox-rolling-reboot.conf` überschreiben,
z. B. `CT_TIMEOUT=300` oder `HOME_TAG="node02"`.

## Wenn es abbricht

Das Skript lässt alles so, wie es beim Abbruch war. Nachsehen auf proxmox-n01 als root:

```
pvecm status
pvesh get /cluster/resources --type vm
```

Ist alles wieder in Ordnung, kann man es nochmal starten. Es liest den aktuellen Stand, fängt
aber wieder bei Schritt 1 an, startet also beide Nodes nochmal neu.
