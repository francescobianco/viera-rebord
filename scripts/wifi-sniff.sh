#!/usr/bin/env bash
# Ascolto passivo del WiFi in modalita' monitor per catturare le probe request della TV.
# Il dongle perde la connessione per DURATA secondi, poi torna gestito da NetworkManager.
#   sudo scripts/wifi-sniff.sh [DURATA_SECONDI]
set -uo pipefail

WIFI_IF=${WIFI_IF:-wlxe0b2f1c5819b}
DURATA=${1:-120}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
PCAP=$ROOT/captures/wifi-monitor-$(date +%Y%m%d-%H%M%S).pcap

ripristina() {
    kill "${HOP_PID:-}" "${DUMP_PID:-}" 2>/dev/null
    ip link set "$WIFI_IF" down
    iw dev "$WIFI_IF" set type managed
    ip link set "$WIFI_IF" up
    nmcli device set "$WIFI_IF" managed yes
    chown "${SUDO_UID:-0}:${SUDO_GID:-0}" "$PCAP" "$PCAP.log" 2>/dev/null
    echo "WiFi ripristinato, cattura in $PCAP"
    echo "frame catturati: $(tcpdump -r "$PCAP" 2>/dev/null | wc -l), di cui probe request: $(tcpdump -r "$PCAP" 'type mgt subtype probe-req' 2>/dev/null | wc -l)"
}
trap ripristina EXIT

nmcli device set "$WIFI_IF" managed no
ip link set "$WIFI_IF" down
iw dev "$WIFI_IF" set type monitor || exit 1
ip link set "$WIFI_IF" up
iw dev "$WIFI_IF" info | sed -n '/type/,/channel/p'

# Salta tra i canali 2.4 GHz: la TV puo' cercare su uno qualsiasi
( while true; do for c in 1 6 11 2 7 12 3 8 13 4 9 5 10; do iw dev "$WIFI_IF" set channel "$c" 2>/dev/null; sleep 0.4; done; done ) &
HOP_PID=$!

# Nessun filtro BPF: con alcuni driver il filtro sui frame 802.11 scarta tutto
tcpdump -i "$WIFI_IF" -n -e -U -w "$PCAP" >"$PCAP.log" 2>&1 &
DUMP_PID=$!

echo "ascolto per $DURATA secondi su $WIFI_IF..."
sleep "$DURATA"
