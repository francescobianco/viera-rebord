#!/usr/bin/env bash
# Finto router sulla LAN diretta PC <-> TV VIERA.
# DHCP + DNS (dnsmasq) su eno1, cattura pacchetti (tcpdump) e, opzionale, NAT verso internet via WiFi.
#
#   sudo scripts/router.sh start [--nat]   avvia (senza --nat ogni nome DNS risolve verso il PC)
#   sudo scripts/router.sh stop
#   scripts/router.sh status
set -euo pipefail

LAN_IF=${LAN_IF:-eno1}
WAN_IF=${WAN_IF:-wlxe0b2f1c5819b}
LAN_IP=192.168.50.1
DHCP_RANGE=192.168.50.100,192.168.50.150,12h

ROOT=$(cd "$(dirname "$0")/.." && pwd)
RUN=$ROOT/captures/run
mkdir -p "$RUN"
# dnsmasq e' confinato da AppArmor: puo' scrivere solo in questi percorsi
LEASES=/var/lib/misc/dnsmasq.viera.leases
DNSMASQ_PID=/run/viera-dnsmasq.pid
DNSMASQ_LOG=/var/log/dnsmasq-viera.log

start() {
    local nat=no
    [[ ${1:-} == --nat ]] && nat=yes

    ip addr show "$LAN_IF" | grep -q "inet $LAN_IP/" || ip addr add "$LAN_IP/24" dev "$LAN_IF"

    local dns_opts=(--server=1.1.1.1 --server=8.8.8.8)
    # Senza NAT la TV non ha internet: rispondiamo noi a ogni nome per vedere chi cerca di contattare.
    [[ $nat == no ]] && dns_opts=(--no-resolv --address=/#/$LAN_IP)

    dnsmasq \
        --interface="$LAN_IF" --bind-interfaces --except-interface=lo \
        --dhcp-range="$DHCP_RANGE" \
        --dhcp-option=option:router,$LAN_IP \
        --dhcp-option=option:dns-server,$LAN_IP \
        --dhcp-authoritative \
        --dhcp-leasefile="$LEASES" \
        --log-dhcp --log-queries --log-facility="$DNSMASQ_LOG" \
        --pid-file="$DNSMASQ_PID" \
        "${dns_opts[@]}"

    local pcap=$ROOT/captures/eno1-$(date +%Y%m%d-%H%M%S).pcap
    tcpdump -i "$LAN_IF" -n -U -w "$pcap" >/dev/null 2>&1 &
    echo $! >"$RUN/tcpdump.pid"

    if [[ $nat == yes ]]; then
        sysctl -qw net.ipv4.ip_forward=1
        iptables -t nat -A POSTROUTING -s 192.168.50.0/24 -o "$WAN_IF" -j MASQUERADE
        iptables -I FORWARD -i "$LAN_IF" -o "$WAN_IF" -j ACCEPT
        iptables -I FORWARD -i "$WAN_IF" -o "$LAN_IF" -m state --state RELATED,ESTABLISHED -j ACCEPT
        echo yes >"$RUN/nat"
    fi

    sleep 1
    chown -R "${SUDO_UID:-0}:${SUDO_GID:-0}" "$ROOT/captures"
    chmod a+r "$LEASES" "$DNSMASQ_LOG" "$pcap" 2>/dev/null || true
    echo "router attivo su $LAN_IF ($LAN_IP), NAT=$nat, cattura: $pcap"
}

stop() {
    for f in "$DNSMASQ_PID" "$RUN/tcpdump.pid"; do
        [[ -f $f ]] && kill "$(cat "$f")" 2>/dev/null || true
        rm -f "$f"
    done
    if [[ -f $RUN/nat ]]; then
        iptables -t nat -D POSTROUTING -s 192.168.50.0/24 -o "$WAN_IF" -j MASQUERADE || true
        iptables -D FORWARD -i "$LAN_IF" -o "$WAN_IF" -j ACCEPT || true
        iptables -D FORWARD -i "$WAN_IF" -o "$LAN_IF" -m state --state RELATED,ESTABLISHED -j ACCEPT || true
        rm -f "$RUN/nat"
    fi
    echo "router fermato"
}

status() {
    for f in "$DNSMASQ_PID" "$RUN/tcpdump.pid"; do
        if [[ -f $f ]] && ps -p "$(cat "$f")" >/dev/null; then echo "$(basename "$f"): attivo"; else echo "$(basename "$f"): fermo"; fi
    done
    echo "--- lease"; [[ -s $LEASES ]] && cat "$LEASES" || echo "(nessuno)"
    echo "--- ultime righe log"; tail -n 15 "$DNSMASQ_LOG" 2>/dev/null || true
}

case ${1:-} in
    start) shift; start "$@" ;;
    stop) stop ;;
    status) status ;;
    *) echo "uso: $0 start [--nat] | stop | status" >&2; exit 1 ;;
esac
