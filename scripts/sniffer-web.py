#!/usr/bin/env python3
# Pannello web per lo sniffer ESP-01 (probesniff). Legge la seriale, aggrega
# i probe/response e serve una pagina live su 0.0.0.0:9909.
import os, re, json, time, threading, subprocess
from collections import deque
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

TV_MAC = "c0:d9:62:2f:08:11"
PORT = 9909
DEV_CANDIDATES = [
    "/dev/serial/by-id/usb-1a86_USB2.0-Serial-if00-port0",
    "/dev/ttyUSB0",
]
KNOWN = {
    "c0:d9:62:2f:08:11": "TV VIERA (Panasonic)",
    "3c:37:12:e6:4a:0b": "FRITZ!Box 7530",
    "3e:37:12:e6:4a:0b": "FRITZ ospiti (OSPITI)",
    "12:42:1b:57:0e:f5": "Orange Pi XR819 (MAC hw)",
    "90:2b:d2:f6:f2:36": "AP BSSID 90:2b:d2:f6:f2:36",
    "e0:b2:f1:c5:81:9b": "Intel5 dongle",
}

lock = threading.Lock()
recent = deque(maxlen=200)
devices = {}
watch_events = deque(maxlen=80)
started = time.time()
serial_dev = None
last_data_t = 0

probe_re = re.compile(r'PROBE ch=(\d+) rssi=(-?\d+) sa=([0-9a-fA-F:]{17}) ssid="(.*)"')
watch_re = re.compile(r'WATCH (\S+) ch=(\d+) rssi=(-?\d+) sa=([0-9a-fA-F:]{17}) da=([0-9a-fA-F:]{17}) ssid="(.*)"')


def touch(mac):
    mac = mac.lower()
    d = devices.get(mac)
    if not d:
        d = {"mac": mac, "label": KNOWN.get(mac, ""), "count": 0,
             "last_rssi": None, "last_ssid": "", "channels": set(),
             "ssids": set(), "last_seen": 0.0}
        devices[mac] = d
    return d


def handle_line(line):
    global last_data_t
    line = line.strip()
    if not line:
        return
    now = time.time()
    with lock:
        last_data_t = now
        recent.append({"t": now, "line": line})
        m = probe_re.search(line)
        if m:
            ch, rssi, sa, ssid = m.group(1), int(m.group(2)), m.group(3), m.group(4)
            d = touch(sa)
            d["count"] += 1
            d["last_rssi"] = rssi
            d["channels"].add(int(ch))
            if ssid:
                d["last_ssid"] = ssid
                d["ssids"].add(ssid)
            d["last_seen"] = now
            return
        w = watch_re.search(line)
        if w:
            kind, ch, rssi, sa, da, ssid = w.groups()
            d = touch(sa)
            d["last_rssi"] = int(rssi)
            d["last_seen"] = now
            if ssid:
                d["last_ssid"] = ssid
            if da.lower() == TV_MAC or sa.lower() == TV_MAC:
                watch_events.append({"t": now, "kind": kind, "ch": int(ch),
                                     "rssi": int(rssi), "sa": sa.lower(),
                                     "da": da.lower(), "ssid": ssid})


def serial_reader():
    global serial_dev
    while True:
        dev = next((p for p in DEV_CANDIDATES if os.path.exists(p)), None)
        serial_dev = dev
        if not dev:
            with lock:
                recent.append({"t": time.time(), "line": "[in attesa dell'ESP sulla seriale...]"})
            time.sleep(2)
            continue
        try:
            subprocess.run(["stty", "-F", dev, "115200", "raw", "-echo"], check=False)
            with open(dev, "rb", buffering=0) as f:
                buf = b""
                while True:
                    chunk = f.read(256)
                    if not chunk:
                        time.sleep(0.05)
                        continue
                    buf += chunk
                    while b"\n" in buf:
                        ln, buf = buf.split(b"\n", 1)
                        handle_line(ln.decode("utf-8", "replace"))
        except Exception as e:
            with lock:
                recent.append({"t": time.time(), "line": f"[errore seriale: {e}]"})
            time.sleep(2)


def snapshot():
    now = time.time()
    with lock:
        devs = []
        for d in devices.values():
            devs.append({
                "mac": d["mac"], "label": d["label"], "count": d["count"],
                "last_rssi": d["last_rssi"], "last_ssid": d["last_ssid"],
                "channels": sorted(d["channels"]),
                "ssids": sorted(x for x in d["ssids"] if x)[:6],
                "age": round(now - d["last_seen"], 1) if d["last_seen"] else None,
                "is_tv": d["mac"] == TV_MAC,
            })
        devs.sort(key=lambda x: (x["age"] is None, x["age"] if x["age"] is not None else 1e9))
        tv = next((x for x in devs if x["is_tv"]), None)
        log = [{"age": round(now - r["t"], 1), "line": r["line"]} for r in list(recent)[-80:]][::-1]
        wev = [{"age": round(now - w["t"], 1), **{k: v for k, v in w.items() if k != "t"}}
               for w in list(watch_events)][-25:][::-1]
        feed_age = round(now - last_data_t, 1) if last_data_t else None
    return {"now": now, "uptime": round(now - started), "tv_mac": TV_MAC,
            "serial": serial_dev, "feed_age": feed_age,
            "tv": tv, "devices": devs, "log": log, "watch": wev}


INDEX = r"""<!doctype html>
<html lang="it">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>VIERA Sniffer</title>
<style>
  :root{
    --bg:#0e1116; --panel:#171c24; --panel2:#1e2530; --line:#2a323d;
    --txt:#e6edf3; --dim:#8b97a6; --accent:#4cc2ff; --tv:#56d364;
    --warn:#e3b341; --bad:#f85149;
  }
  *{box-sizing:border-box}
  body{margin:0;background:var(--bg);color:var(--txt);
    font:14px/1.45 system-ui,-apple-system,Segoe UI,Roboto,sans-serif}
  header{display:flex;align-items:center;gap:12px;flex-wrap:wrap;
    padding:14px 18px;border-bottom:1px solid var(--line);background:var(--panel)}
  header h1{font-size:16px;margin:0;font-weight:650;letter-spacing:.3px}
  .pill{font-size:12px;color:var(--dim);background:var(--panel2);
    border:1px solid var(--line);border-radius:999px;padding:3px 10px}
  .dot{width:8px;height:8px;border-radius:50%;display:inline-block;margin-right:6px}
  .live{background:var(--tv);box-shadow:0 0 8px var(--tv)}
  .stale{background:var(--bad)}
  main{max-width:1060px;margin:0 auto;padding:18px;display:grid;gap:18px}
  .grid{display:grid;grid-template-columns:1fr 1fr;gap:18px}
  @media(max-width:760px){.grid{grid-template-columns:1fr}}
  .card{background:var(--panel);border:1px solid var(--line);border-radius:12px;padding:16px}
  .card h2{font-size:12px;text-transform:uppercase;letter-spacing:.8px;
    color:var(--dim);margin:0 0 12px}
  .tvcard{border-color:#2f5134;background:linear-gradient(180deg,#14201a,#171c24)}
  .tvtop{display:flex;align-items:baseline;gap:10px;flex-wrap:wrap}
  .tvtop .name{font-size:18px;font-weight:700;color:var(--tv)}
  .tvtop .mac{font-family:ui-monospace,Menlo,Consolas,monospace;color:var(--dim);font-size:12px}
  .rssi{font-size:40px;font-weight:800;margin:6px 0 2px}
  .bar{height:10px;border-radius:6px;background:var(--panel2);overflow:hidden;margin:8px 0}
  .bar>span{display:block;height:100%;background:linear-gradient(90deg,#f85149,#e3b341,#56d364)}
  .kv{display:flex;gap:18px;flex-wrap:wrap;color:var(--dim);font-size:13px;margin-top:8px}
  .kv b{color:var(--txt);font-weight:600}
  table{width:100%;border-collapse:collapse;font-size:13px}
  th,td{text-align:left;padding:7px 8px;border-bottom:1px solid var(--line);white-space:nowrap}
  th{color:var(--dim);font-weight:600;font-size:11px;text-transform:uppercase;letter-spacing:.5px}
  td.mac{font-family:ui-monospace,Menlo,Consolas,monospace}
  tr.tv td{color:var(--tv);font-weight:600}
  .ssid{color:var(--accent)}
  .muted{color:var(--dim)}
  .log{font-family:ui-monospace,Menlo,Consolas,monospace;font-size:12px;
    max-height:360px;overflow:auto;background:#0b0e13;border-radius:8px;padding:10px}
  .log div{padding:1px 0;white-space:pre-wrap;word-break:break-all}
  .log .hl{color:var(--tv)}
  .log .wl{color:var(--warn)}
  .age{color:var(--dim)}
  .full{grid-column:1/-1}
</style>
</head>
<body>
<header>
  <h1>📡 VIERA Sniffer</h1>
  <span class="pill" id="conn"><span class="dot stale"></span>—</span>
  <span class="pill" id="serial">seriale: —</span>
  <span class="pill" id="uptime">uptime: —</span>
  <span class="pill muted" style="margin-left:auto">auto-refresh 1.5s</span>
</header>
<main>
  <div class="card tvcard" id="tvcard">
    <h2>Televisore (target)</h2>
    <div id="tvbody"><span class="muted">in attesa di probe dalla TV…</span></div>
  </div>

  <div class="grid">
    <div class="card">
      <h2>Dispositivi visti</h2>
      <div style="overflow:auto"><table id="devtbl">
        <thead><tr><th>Dispositivo / MAC</th><th>Probe</th><th>RSSI</th><th>Ultimo SSID</th><th>Canali</th><th>Visto</th></tr></thead>
        <tbody></tbody>
      </table></div>
    </div>
    <div class="card">
      <h2>Risposte verso/da la TV</h2>
      <div style="overflow:auto"><table id="watchtbl">
        <thead><tr><th>Età</th><th>Tipo</th><th>Da (AP)</th><th>SSID</th><th>ch</th><th>RSSI</th></tr></thead>
        <tbody></tbody>
      </table></div>
    </div>
  </div>

  <div class="card full">
    <h2>Log seriale (live)</h2>
    <div class="log" id="log"></div>
  </div>
</main>
<script>
const TV = "%%TVMAC%%";
function rssiPct(r){ if(r==null) return 0; return Math.max(0,Math.min(100,Math.round((r+90)/60*100))); }
function ageStr(a){ if(a==null) return "mai"; if(a<2) return "ora"; if(a<60) return a.toFixed(0)+"s fa"; return (a/60).toFixed(1)+"m fa"; }
function esc(s){ return (s||"").replace(/[&<>]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;'}[c])); }

async function tick(){
  let d;
  try { d = await (await fetch('/data',{cache:'no-store'})).json(); }
  catch(e){ document.getElementById('conn').innerHTML='<span class="dot stale"></span>offline'; return; }

  const fresh = d.feed_age!=null && d.feed_age < 5;
  document.getElementById('conn').innerHTML =
    '<span class="dot '+(fresh?'live':'stale')+'"></span>'+(fresh?'dati live':'nessun dato ('+ageStr(d.feed_age)+')');
  document.getElementById('serial').textContent = 'seriale: ' + (d.serial ? d.serial.split('/').pop() : 'assente');
  document.getElementById('uptime').textContent = 'uptime: ' + d.uptime + 's';

  // TV hero
  const tb = document.getElementById('tvbody');
  if(d.tv){
    const t=d.tv, pct=rssiPct(t.last_rssi), live=(t.age!=null&&t.age<5);
    tb.innerHTML =
      '<div class="tvtop"><span class="name">'+(live?'● ':'○ ')+'VIERA</span>'+
      '<span class="mac">'+t.mac+'</span></div>'+
      '<div class="rssi">'+(t.last_rssi!=null?t.last_rssi+' dBm':'—')+'</div>'+
      '<div class="bar"><span style="width:'+pct+'%"></span></div>'+
      '<div class="kv"><span>SSID cercato: <b class="ssid">'+(esc(t.last_ssid)||'—')+'</b></span>'+
      '<span>probe: <b>'+t.count+'</b></span>'+
      '<span>canali: <b>'+(t.channels.join(', ')||'—')+'</b></span>'+
      '<span>ultimo: <b>'+ageStr(t.age)+'</b></span></div>';
  }

  // devices
  const tb2 = document.querySelector('#devtbl tbody');
  tb2.innerHTML = d.devices.map(x=>
    '<tr class="'+(x.is_tv?'tv':'')+'">'+
    '<td class="mac">'+(x.label?esc(x.label)+'<br>':'')+'<span class="muted">'+x.mac+'</span></td>'+
    '<td>'+x.count+'</td>'+
    '<td>'+(x.last_rssi!=null?x.last_rssi:'—')+'</td>'+
    '<td class="ssid">'+(esc(x.last_ssid)||'<span class="muted">—</span>')+'</td>'+
    '<td class="muted">'+(x.channels.join(',')||'—')+'</td>'+
    '<td class="age">'+ageStr(x.age)+'</td></tr>').join('');

  // watch
  const tb3 = document.querySelector('#watchtbl tbody');
  tb3.innerHTML = d.watch.map(w=>
    '<tr><td class="age">'+ageStr(w.age)+'</td><td>'+esc(w.kind)+'</td>'+
    '<td class="mac">'+w.sa+'</td><td class="ssid">'+esc(w.ssid)+'</td>'+
    '<td>'+w.ch+'</td><td>'+w.rssi+'</td></tr>').join('')
    || '<tr><td colspan="6" class="muted">nessuna ancora</td></tr>';

  // log
  const lg = document.getElementById('log');
  lg.innerHTML = d.log.map(r=>{
    let cls = r.line.indexOf(TV)>=0 ? 'hl' : (r.line.startsWith('WATCH')?'wl':'');
    return '<div class="'+cls+'"><span class="age">'+ageStr(r.age)+'  </span>'+esc(r.line)+'</div>';
  }).join('');
}
tick(); setInterval(tick, 1500);
</script>
</body>
</html>
"""


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_GET(self):
        if self.path.startswith("/data"):
            body = json.dumps(snapshot()).encode()
            ctype = "application/json"
        else:
            body = INDEX.replace("%%TVMAC%%", TV_MAC).encode()
            ctype = "text/html; charset=utf-8"
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)


if __name__ == "__main__":
    threading.Thread(target=serial_reader, daemon=True).start()
    srv = ThreadingHTTPServer(("0.0.0.0", PORT), H)
    print("VIERA sniffer web su :%d" % PORT, flush=True)
    srv.serve_forever()
