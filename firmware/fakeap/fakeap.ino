// FakeAP — ESP-01 come access point che imita il vecchio router della TV
//
// Stesso SSID, stesso BSSID (MAC) e sicurezza WPA/WPA2 mista (TKIP + AES).
// Sulla seriale (115200) stampa le ricerche della TV e ogni connessione o
// disconnessione di una stazione, con l'IP assegnato dal DHCP dell'ESP.
//
// Scheda: Generic ESP8266 Module, Flash Size 1MB, Flash Mode DOUT.
// La passphrase si passa a compile time: FAKEAP_PASS="..." ./firmware/build.sh

#include <ESP8266WiFi.h>

extern "C" {
#include <user_interface.h>
}

#ifndef FAKEAP_PASS
#error "Definire FAKEAP_PASS (passphrase WPA della rete)"
#endif

constexpr char SSID[] = "RETEDICASA0";
constexpr uint8_t CHANNEL = 6;
uint8_t BSSID[6] = {0x90, 0x2b, 0xd2, 0xf6, 0xf2, 0x36};
const uint8_t TV_MAC[6] = {0xc0, 0xd9, 0x62, 0x2f, 0x08, 0x11};

WiFiEventHandler onConnected, onDisconnected, onProbe;
unsigned long lastProbePrint = 0;
uint16_t tvProbes = 0;

void printMac(const uint8_t *m) {
  for (int i = 0; i < 6; i++) Serial.printf(i ? ":%02x" : "%02x", m[i]);
}

void setup() {
  Serial.begin(115200);
  delay(200);
  Serial.println();
  Serial.println("FakeAP avviato");

  WiFi.persistent(false);
  WiFi.mode(WIFI_AP);
  if (!wifi_set_macaddr(SOFTAP_IF, BSSID)) Serial.println("ERRORE: MAC non impostato");

  softap_config cfg = {};
  memcpy(cfg.ssid, SSID, strlen(SSID));
  cfg.ssid_len = strlen(SSID);
  strncpy(reinterpret_cast<char *>(cfg.password), FAKEAP_PASS, sizeof(cfg.password) - 1);
  cfg.channel = CHANNEL;
  cfg.authmode = AUTH_WPA_WPA2_PSK;
  cfg.ssid_hidden = 0;
  cfg.max_connection = 4;
  cfg.beacon_interval = 100;
  if (!wifi_softap_set_config_current(&cfg)) Serial.println("ERRORE: config AP non applicata");

  uint8_t mac[6];
  wifi_get_macaddr(SOFTAP_IF, mac);
  Serial.printf("AP \"%s\" canale %u bssid=", SSID, CHANNEL);
  printMac(mac);
  Serial.printf(" ip=%s\n", WiFi.softAPIP().toString().c_str());

  onConnected = WiFi.onSoftAPModeStationConnected([](const WiFiEventSoftAPModeStationConnected &e) {
    Serial.print("CONNESSO sta=");
    printMac(e.mac);
    Serial.printf(" aid=%u\n", e.aid);
  });
  onDisconnected = WiFi.onSoftAPModeStationDisconnected([](const WiFiEventSoftAPModeStationDisconnected &e) {
    Serial.print("DISCONNESSO sta=");
    printMac(e.mac);
    Serial.println();
  });
  onProbe = WiFi.onSoftAPModeProbeRequestReceived([](const WiFiEventSoftAPModeProbeRequestReceived &e) {
    if (memcmp(e.mac, TV_MAC, 6) == 0) tvProbes++;
  });
}

void loop() {
  unsigned long now = millis();
  if (now - lastProbePrint < 10000) return;
  lastProbePrint = now;

  Serial.printf("STATO probe_tv_10s=%u stazioni=%u\n", tvProbes, wifi_softap_get_station_num());
  tvProbes = 0;
  for (station_info *s = wifi_softap_get_station_info(); s; s = STAILQ_NEXT(s, next)) {
    Serial.print("  sta=");
    printMac(s->bssid);
    Serial.printf(" ip=%s\n", IPAddress(s->ip.addr).toString().c_str());
  }
  wifi_softap_free_station_info();
}
