// ProbeSniff — ESP-01 in modalità promiscua
//
// Salta tra i canali 1-13 e stampa sulla seriale (115200) ogni probe request
// vista nell'aria: MAC del mittente, canale, potenza e SSID cercato.
// Serve per scoprire a quale rete prova a collegarsi il WiFi della TV.
// Ogni 30 s stampa un riepilogo dei mittenti visti.
// Stampa anche il primo beacon di ogni rete (nome e canale) e ogni frame di
// management da o verso WATCH_MAC (risposte, autenticazione, associazione).
//
// Scheda: Generic ESP8266 Module, Flash Size 1MB, Flash Mode DOUT.
//
// Formato righe:
//   PROBE ch=6 rssi=-48 sa=aa:bb:cc:dd:ee:ff ssid="iliadbox-68A94A"
//   (ssid vuoto = ricerca generica di qualsiasi rete)
//   BEACON ch=11 rssi=-40 bssid=aa:bb:cc:dd:ee:ff ssid="RETEDICASA0"
//   WATCH probe-resp ch=11 rssi=-40 sa=... da=... ssid="RETEDICASA0"

#include <ESP8266WiFi.h>

extern "C" {
#include <user_interface.h>
}

constexpr unsigned long HOP_MS = 250;
constexpr unsigned long SUMMARY_MS = 30000;
constexpr uint8_t MAX_SEEN = 32;
constexpr uint8_t MAX_BEACONS = 48;
// WiFi della TV
const uint8_t WATCH_MAC[6] = {0xc0, 0xd9, 0x62, 0x2f, 0x08, 0x11};

// Layout dei buffer passati dall'SDK alla callback promiscua
struct RxControl {
  signed rssi : 8;
  unsigned rate : 4;
  unsigned is_group : 1;
  unsigned : 1;
  unsigned sig_mode : 2;
  unsigned legacy_length : 12;
  unsigned damatch0 : 1;
  unsigned damatch1 : 1;
  unsigned bssidmatch0 : 1;
  unsigned bssidmatch1 : 1;
  unsigned MCS : 7;
  unsigned CWB : 1;
  unsigned HT_length : 16;
  unsigned Smoothing : 1;
  unsigned Not_Sounding : 1;
  unsigned : 1;
  unsigned Aggregation : 1;
  unsigned STBC : 2;
  unsigned FEC_CODING : 1;
  unsigned SGI : 1;
  unsigned rxend_state : 8;
  unsigned ampdu_cnt : 8;
  unsigned channel : 4;
  unsigned : 12;
};

// I frame di management arrivano con len == 128 in questo formato
struct SnifferBuf2 {
  RxControl rx_ctrl;
  uint8_t buf[112];
  uint16_t cnt;
  uint16_t len;
};

struct Seen {
  uint8_t mac[6];
  uint16_t count;
  int8_t rssi;
  char ssid[33];
};

// La callback gira in contesto di sistema: copia il minimo e stampa nel loop
struct Pending {
  uint8_t kind;  // frame control byte 0 (sottotipo di management)
  uint8_t mac[6];
  uint8_t da[6];
  int8_t rssi;
  uint8_t channel;
  char ssid[33];
};

constexpr uint8_t QUEUE_LEN = 16;
volatile uint8_t qHead = 0, qTail = 0;
Pending queue[QUEUE_LEN];

Seen seen[MAX_SEEN];
uint8_t seenCount = 0;
uint8_t beacons[MAX_BEACONS][7];  // bssid + canale gia' stampati
uint8_t beaconCount = 0;
uint8_t channel = 1;
unsigned long lastHop = 0, lastSummary = 0;

void ICACHE_RAM_ATTR onPacket(uint8_t *buf, uint16_t len) {
  if (len != 128) return;
  auto *p = reinterpret_cast<SnifferBuf2 *>(buf);
  const uint8_t *f = p->buf;
  // frame control byte 0: 0x40 probe request, 0x80 beacon, altri management
  // (0x00 assoc req, 0x10 assoc resp, 0x50 probe resp, 0xb0 auth, 0xc0 deauth)
  uint8_t kind = f[0];
  if ((kind & 0x0c) != 0) return;  // solo frame di management
  bool watched = memcmp(f + 4, WATCH_MAC, 6) == 0 || memcmp(f + 10, WATCH_MAC, 6) == 0;
  if (kind != 0x40 && kind != 0x80 && !watched) return;

  uint8_t next = (qHead + 1) % QUEUE_LEN;
  if (next == qTail) return;  // coda piena, scarta
  Pending &e = queue[qHead];
  e.kind = kind;
  memcpy(e.mac, f + 10, 6);
  memcpy(e.da, f + 4, 6);
  e.rssi = p->rx_ctrl.rssi;
  e.channel = channel;
  e.ssid[0] = 0;
  // Information element 0 (SSID): dopo l'header di 24 byte, piu' 12 byte di
  // campi fissi per beacon e probe response
  uint8_t ie = (kind == 0x80 || kind == 0x50) ? 36 : 24;
  if (kind == 0x40 || kind == 0x80 || kind == 0x50) {
    if (f[ie] == 0) {
      uint8_t l = f[ie + 1];
      if (l > 32 || ie + 2 + l > sizeof(p->buf)) l = 0;
      memcpy(e.ssid, f + ie + 2, l);
      e.ssid[l] = 0;
    }
  }
  qHead = next;
}

void printMac(const uint8_t *m) {
  for (int i = 0; i < 6; i++) Serial.printf(i ? ":%02x" : "%02x", m[i]);
}

const char *kindName(uint8_t k) {
  switch (k) {
    case 0x00: return "assoc-req";
    case 0x10: return "assoc-resp";
    case 0x20: return "reassoc-req";
    case 0x30: return "reassoc-resp";
    case 0x40: return "probe-req";
    case 0x50: return "probe-resp";
    case 0xa0: return "disassoc";
    case 0xb0: return "auth";
    case 0xc0: return "deauth";
    case 0xd0: return "action";
    default: return "mgmt";
  }
}

// true la prima volta che si vede questa rete su questo canale
bool newBeacon(const Pending &e) {
  for (uint8_t i = 0; i < beaconCount; i++)
    if (memcmp(beacons[i], e.mac, 6) == 0 && beacons[i][6] == e.channel) return false;
  if (beaconCount == MAX_BEACONS) return false;
  memcpy(beacons[beaconCount], e.mac, 6);
  beacons[beaconCount++][6] = e.channel;
  return true;
}

void remember(const Pending &e) {
  for (uint8_t i = 0; i < seenCount; i++) {
    if (memcmp(seen[i].mac, e.mac, 6) == 0) {
      seen[i].count++;
      seen[i].rssi = e.rssi;
      if (e.ssid[0]) strcpy(seen[i].ssid, e.ssid);
      return;
    }
  }
  if (seenCount == MAX_SEEN) return;
  Seen &s = seen[seenCount++];
  memcpy(s.mac, e.mac, 6);
  s.count = 1;
  s.rssi = e.rssi;
  strcpy(s.ssid, e.ssid);
}

void setup() {
  Serial.begin(115200);
  delay(200);
  Serial.println();
  Serial.println("ProbeSniff avviato");

  wifi_set_opmode(STATION_MODE);
  wifi_station_disconnect();
  wifi_promiscuous_enable(0);
  wifi_set_promiscuous_rx_cb(onPacket);
  wifi_set_channel(channel);
  wifi_promiscuous_enable(1);
}

void loop() {
  while (qTail != qHead) {
    Pending e = queue[qTail];
    qTail = (qTail + 1) % QUEUE_LEN;
    if (e.kind == 0x40) {
      Serial.printf("PROBE ch=%u rssi=%d sa=", e.channel, e.rssi);
      printMac(e.mac);
      Serial.printf(" ssid=\"%s\"\n", e.ssid);
      remember(e);
    } else if (e.kind == 0x80) {
      if (!newBeacon(e)) continue;
      Serial.printf("BEACON ch=%u rssi=%d bssid=", e.channel, e.rssi);
      printMac(e.mac);
      Serial.printf(" ssid=\"%s\"\n", e.ssid);
    } else {
      Serial.printf("WATCH %s ch=%u rssi=%d sa=", kindName(e.kind), e.channel, e.rssi);
      printMac(e.mac);
      Serial.print(" da=");
      printMac(e.da);
      Serial.printf(" ssid=\"%s\"\n", e.ssid);
    }
  }

  unsigned long now = millis();
  if (now - lastHop >= HOP_MS) {
    lastHop = now;
    channel = channel % 13 + 1;
    wifi_set_channel(channel);
  }

  if (now - lastSummary >= SUMMARY_MS) {
    lastSummary = now;
    Serial.printf("SUMMARY %u mittenti\n", seenCount);
    for (uint8_t i = 0; i < seenCount; i++) {
      Serial.print("  ");
      printMac(seen[i].mac);
      Serial.printf(" n=%u rssi=%d ultimo_ssid=\"%s\"\n", seen[i].count, seen[i].rssi, seen[i].ssid);
    }
  }
}
