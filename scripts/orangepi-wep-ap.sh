#!/usr/bin/env bash
# Access point WEP sull'Orange Pi Zero (XR819) per far agganciare la TV alla
# rete che ricorda. DHCP su 192.168.60.0/24 e inoltro verso eth0, cosi' dalla
# LAN si raggiunge la TV aggiungendo una rotta via l'Orange Pi.
#
#   sudo ./orangepi-wep-ap.sh start
#   sudo ./orangepi-wep-ap.sh stop
#   sudo ./orangepi-wep-ap.sh status
set -euo pipefail

IF=wlan0
SSID=${SSID:-RETEDICASA0}
WEP_KEY=${WEP_KEY:?imposta WEP_KEY con la chiave (WEP esadecimale o passphrase WPA)}
# Sicurezza: wep (default), wep-shared, open, wpa-tkip, wpa2-tkip, wpa-mixed
MODE=${MODE:-wep}
CHANNEL=${CHANNEL:-6}
AP_IP=192.168.60.1
RUN=/tmp/viera-ap
mkdir -p "$RUN"

start() {
    nmcli device set "$IF" managed no 2>/dev/null || true
    # BSSID: imita il MAC del vecchio router, se la TV lo ha memorizzato
    if [[ -n ${BSSID:-} ]]; then
        ip link set "$IF" down
        ip link set "$IF" address "$BSSID"
    fi
    ip link set "$IF" up
    ip addr flush dev "$IF"
    ip addr add "$AP_IP/24" dev "$IF"

    cat >"$RUN/hostapd.conf" <<EOF
interface=$IF
driver=nl80211
ssid=$SSID
country_code=IT
hw_mode=g
channel=$CHANNEL
# Il WEP non e' ammesso in 802.11n
ieee80211n=0
wmm_enabled=0
logger_stdout=-1
logger_stdout_level=1
EOF
    # auth_algs: 1 = open system, 2 = shared key, 3 = entrambi
    case $MODE in
        wep) printf 'auth_algs=3\nwep_default_key=0\nwep_key0=%s\n' "$WEP_KEY" ;;
        wep-shared) printf 'auth_algs=2\nwep_default_key=0\nwep_key0=%s\n' "$WEP_KEY" ;;
        open) printf 'auth_algs=1\n' ;;
        wpa-tkip) printf 'auth_algs=1\nwpa=1\nwpa_key_mgmt=WPA-PSK\nwpa_pairwise=TKIP\nwpa_passphrase=%s\n' "$WEP_KEY" ;;
        wpa2-tkip) printf 'auth_algs=1\nwpa=2\nwpa_key_mgmt=WPA-PSK\nrsn_pairwise=TKIP\nwpa_passphrase=%s\n' "$WEP_KEY" ;;
        wpa-mixed) printf 'auth_algs=1\nwpa=3\nwpa_key_mgmt=WPA-PSK\nwpa_pairwise=TKIP CCMP\nrsn_pairwise=TKIP CCMP\nwpa_passphrase=%s\n' "$WEP_KEY" ;;
        *) echo "MODE sconosciuto: $MODE" >&2; exit 1 ;;
    esac >>"$RUN/hostapd.conf"
    [[ -n ${BSSID:-} ]] && echo "bssid=$BSSID" >>"$RUN/hostapd.conf"
    /usr/sbin/hostapd -B -P "$RUN/hostapd.pid" -f "$RUN/hostapd.log" -t "$RUN/hostapd.conf"

    /usr/sbin/dnsmasq --user=root --interface="$IF" --bind-interfaces --except-interface=lo \
        --dhcp-range=192.168.60.100,192.168.60.150,12h \
        --dhcp-option=option:router,$AP_IP --dhcp-option=option:dns-server,$AP_IP \
        --no-resolv --server=1.1.1.1 \
        --dhcp-leasefile="$RUN/leases" --pid-file="$RUN/dnsmasq.pid" \
        --log-dhcp --log-queries --log-facility="$RUN/dnsmasq.log"

    sysctl -qw net.ipv4.ip_forward=1
    echo "AP $MODE '$SSID' attivo su $IF canale $CHANNEL ($AP_IP)"
}

stop() {
    for p in hostapd dnsmasq; do
        [[ -f $RUN/$p.pid ]] && kill "$(cat "$RUN/$p.pid")" 2>/dev/null || true
        rm -f "$RUN/$p.pid"
    done
    ip addr flush dev "$IF" || true
    nmcli device set "$IF" managed yes 2>/dev/null || true
    echo "AP fermato"
}

status() {
    for p in hostapd dnsmasq; do
        if [[ -f $RUN/$p.pid ]] && kill -0 "$(cat "$RUN/$p.pid")" 2>/dev/null; then echo "$p: attivo"; else echo "$p: fermo"; fi
    done
    echo "--- stazioni"; iw dev "$IF" station dump 2>/dev/null | grep -E '^Station|inactive|signal:' || true
    echo "--- lease"; cat "$RUN/leases" 2>/dev/null || true
    echo "--- hostapd"; tail -n 15 "$RUN/hostapd.log" 2>/dev/null || true
    echo "--- dnsmasq"; tail -n 10 "$RUN/dnsmasq.log" 2>/dev/null || true
}

case ${1:-} in
    start) start ;;
    stop) stop ;;
    status) status ;;
    *) echo "uso: $0 start|stop|status" >&2; exit 1 ;;
esac
