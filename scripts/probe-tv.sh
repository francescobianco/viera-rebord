#!/usr/bin/env bash
# Sonda la TV una volta che ha preso un indirizzo: porte note Panasonic, SSDP/UPnP, endpoint VIERA remote.
#   scripts/probe-tv.sh [IP]   (senza IP usa il primo lease di dnsmasq)
set -uo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
IP=${1:-$(awk 'NR==1{print $3}' /var/lib/misc/dnsmasq.viera.leases 2>/dev/null)}
[[ -z $IP ]] && { echo "nessun IP: la TV non ha ancora preso un lease" >&2; exit 1; }

echo "=== TV: $IP"
ping -c2 -W1 "$IP" | tail -2

echo "=== porte TCP"
nmap -Pn -sT -p 80,443,7676,8080,8443,9080,55000,56789,49152-49160 --open "$IP"

echo "=== SSDP M-SEARCH (UPnP/DLNA)"
python3 -I - "$IP" <<'EOF'
import socket, sys
ip = sys.argv[1]
msg = ("M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\n"
       "MAN: \"ssdp:discover\"\r\nMX: 2\r\nST: ssdp:all\r\n\r\n").encode()
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.settimeout(3)
s.sendto(msg, (ip, 1900))
seen = set()
try:
    while True:
        data, _ = s.recvfrom(4096)
        for line in data.decode(errors="replace").splitlines():
            if line.upper().startswith(("LOCATION:", "SERVER:", "ST:")) and line not in seen:
                seen.add(line); print(line)
except socket.timeout:
    pass
if not seen:
    print("(nessuna risposta SSDP)")
EOF

echo "=== VIERA Network Remote (55000)"
curl -s -m 5 "http://$IP:55000/nrc/ddd.xml" | head -40 || echo "(nessuna risposta)"
