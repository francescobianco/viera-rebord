# DOSSIER — VIERA REBORN: riconnessione WiFi della TV

**Progetto:** recupero di una Panasonic VIERA **TX‑L42ET60E** (2013, pannello LCD rotto)
come lettore audio di rete *headless* (vedi `IDEA.md`).
**Stato:** causa del blocco **individuata** (vedi §5). In attesa di avere il router Huawei
in ufficio per la soluzione definitiva (§6).
**Ultimo aggiornamento:** 2026‑10‑30 (sera, sessione di diagnosi via VPN).

---

## 1. Obiettivo immediato

Riportare la TV online via WiFi per raggiungerla dalla LAN (telecomando VIERA, UPnP/DLNA,
porte di servizio) e proseguire con la conversione a streamer audio senza schermo.

Un client WiFi **non si può forzare** ad associarsi: l'associazione la inizia sempre lui, e solo
se trova un AP che corrisponde **esattamente** al profilo salvato (SSID **+ BSSID + sicurezza**).
Va quindi ricreato l'AP identico a quello che la TV ricorda.

## 2. Topologia (30/10)

| Dove | Cosa |
|---|---|
| **Casa** | Router **Huawei** (gateway `192.168.8.1`, SSID `RETEDICASA`, BSSID `90:2b:d2:f6:f2:36`); l'operatore è a casa, connesso alla **VPN dell'ufficio** |
| **Ufficio** | **TV VIERA**, **ESP‑01**, **Orange Pi Zero** (`192.168.144.44`), PC **`Intel5`** (`192.168.144.10`), un **telefono Android** via USB su Intel5, il **FRITZ!Box 7530** |
| **Domani** | Il router **Huawei** viene portato in ufficio → sblocca la soluzione (§6) |

Operativamente tutto è stato pilotato via SSH sulla VPN (`tun0`): `Intel5` con chiave, Orange Pi
e telefono tramite `Intel5`.

## 3. Dispositivi e identificativi

| Dispositivo | Identificativo | Note |
|---|---|---|
| **TV VIERA** (station) | MAC **`c0:d9:62:2f:08:11`** | OUI Panasonic; cerca `RETEDICASA0`; **ancorata al BSSID `90:2b:d2:f6:f2:36`** |
| SSID cercato dalla TV | **`RETEDICASA0`** (con lo zero) | |
| BSSID richiesto dalla TV | **`90:2b:d2:f6:f2:36`** | = **MAC reale del router Huawei** (vedi §5) |
| Router **Huawei** | `192.168.8.1`, SSID `RETEDICASA`, ch2, WPA2, BSSID **`90:2b:d2:f6:f2:36`** | a casa; **è il "vecchio router" della TV** |
| **Orange Pi Zero** | `192.168.144.44`, WiFi **XR819**, `wlan0` | **NON spoofa il MAC**: annuncia `…:36` ma trasmette i frame reali col MAC hardware `12:42:1b:57:0e:f5` |
| **ESP‑01** | ESP8266, su seriale `ttyUSB0` di Intel5 | `wifi_set_macaddr` imposta **davvero** il BSSID, ma l'ESP8266 **non fa WEP** come AP |
| **FRITZ!Box 7530** | `3c:37:12:e6:4a:0b`; guest = `3e:37:12:e6:4a:0b` | la **rete ospiti** era configurata come `RETEDICASA0` (confondente) → **rinominata `OSPITI`** |
| Telefono Android | adb `2aac646c8c3f7ece` (Android 10, no root), USB su Intel5 | hotspot **spento** (verificato); non c'entrava |
| PC **Intel5** | dongle WiFi `wlxe0b2f1c5819b` (**rtl8xxxu**, solo managed/monitor, no AP), NIC `eno1` | banco di lavoro; monitor rtl8xxxu inaffidabile |

## 4. Cosa è stato fatto (metodologia)

- **Sniffer ESP‑01 su seriale** (`probesniff`) come osservatore affidabile accanto alla TV.
- **Testati diversi AP** (Orange Pi in open / WPA2 / WEP; vari router in ambiente).
- **Pulizia dei confondenti**: spento l'hotspot del telefono via adb; rinominata la rete ospiti
  del FRITZ!Box da `RETEDICASA0` a `OSPITI`.
- Scansioni di verifica da `Intel5` (`nmcli dev wifi list`) e cattura in monitor mode.

## 5. Diagnosi — causa individuata

Dai dati raccolti stasera:

1. **L'antenna/ricezione della TV funziona.** La TV trasmette probe a **RSSI −52/−67 dBm**
   (fortissima, vicina) e **riceve** probe‑response indirizzate a lei. Il timore "antenna
   silenziata" (pannello smontato) è **escluso**: un'antenna staccata non darebbe −52.
2. **La TV è sveglia e cerca `RETEDICASA0` di continuo** (probe sui canali 2–7).
3. **La TV scarta i nostri AP PRIMA dell'autenticazione** (non invia mai l'Auth, né in WPA2 né
   in WEP). Con WEP *open‑system* l'Auth partirebbe anche a chiave sbagliata: se non parte,
   significa che la TV rifiuta **in fase di selezione**, in base a **BSSID/beacon**, non alla
   password.
4. **La TV è ancorata al BSSID `90:2b:d2:f6:f2:36`.** Lo sniffer mostra le nostre probe‑response
   uscire col MAC **`12:42:1b:57:0e:f5`** (hardware dell'XR819), **non** `…:36`: la TV le ignora.
5. **L'Orange Pi (XR819) non può servire questa TV**: non spoofa davvero il MAC, quindi presenta
   sempre `12:42`. **Tutte le prove fatte con l'Orange Pi erano quindi falsate**: la TV non ha
   mai visto il BSSID `…:36` che pretende.
6. **Confondente rimosso**: la rete ospiti del FRITZ!Box trasmetteva anch'essa `RETEDICASA0`
   (BSSID `3e:37:12:…`, derivato dal MAC principale) → rinominata `OSPITI`.

### Collegamento chiave

Il BSSID `90:2b:d2:f6:f2:36` che la TV pretende **è esattamente il MAC del router Huawei**.
Quasi certamente il "vecchio router" ricordato dalla TV **è il Huawei stesso**, da quando era in
ufficio con SSID `RETEDICASA0`; poi è stato portato a casa e rinominato `RETEDICASA`.

### Matrice hardware (chi può fare cosa)

| Apparato | Spoof BSSID `…:36` | WEP come AP | AP mode |
|---|---|---|---|
| Huawei (router reale) | **nativo** (è il suo MAC) | sì (config router) | sì |
| ESP‑01 (ESP8266) | **sì** (`wifi_set_macaddr`) | **no** | sì |
| Orange Pi XR819 | **no** | sì (hostapd) | sì |
| Dongle rtl8xxxu (Intel5) | — | — | **no** (solo managed/monitor) |

→ Se il profilo della TV è **WEP + BSSID `…:36`**, **nessun** apparato "fasullo" qui lo copre;
serve il **router Huawei reale** (o un adattatore USB tipo ath9k_htc che faccia AP+WEP+spoof).

## 6. Soluzione (domani, con il Huawei in ufficio)

Non serve spoofare niente: il Huawei **ha già** il BSSID `…:36`.

1. Riportare l'SSID del Huawei a **`RETEDICASA0`**.
2. Impostare la sicurezza che la TV ricorda:
   - prima **WPA/WPA2** con la chiave nota (10 cifre esadecimali — *valore tenuto fuori dal
     repo*; vedi nota riservata);
   - se non aggancia, **WEP** con la stessa chiave (10 hex = chiave WEP a 64 bit).
3. La TV vedrà **SSID + BSSID + sicurezza** esatti e si riconnetterà da sola.
4. Appena prende un lease DHCP, lanciare **`scripts/probe-tv.sh`** per raggiungerla (telecomando
   VIERA su `:55000`, SSDP/UPnP) e proseguire col progetto headless.

### Alternativa se la soluzione col Huawei non bastasse

- **Isolare la variabile BSSID**: flashare l'**ESP FakeAP** (presenta il vero `…:36`) in **open**
  e vedere se la TV almeno invia l'Auth → conferma che il blocco era il BSSID.
- Nota: flashare l'ESP‑01 richiede **accesso fisico** (ponticello GPIO0‑GND per il bootloader),
  non fattibile da remoto.

## 7. Asset nel repository

```
firmware/probesniff/probesniff.ino  Sniffer ESP‑01 promiscuo: hop canali 1‑13, logga probe
                                    request (MAC, canale, RSSI, SSID), beacon e frame mgmt
                                    da/verso WATCH_MAC (la TV). Produce captures/probesniff-*.log
firmware/fakeap/fakeap.ino   FakeAP ESP‑01 (SoftAP WPA/WPA2, imposta davvero il BSSID, conta i probe della TV)
firmware/build.sh            build/flash/monitor (arduino-builder); sketch default `probesniff`
scripts/orangepi-wep-ap.sh   AP WEP su Orange Pi — NB: XR819 non spoofa il BSSID (vedi §5)
scripts/router.sh            finto router su LAN diretta PC<->TV (dnsmasq DHCP/DNS + tcpdump)
scripts/wifi-sniff.sh        sniffing passivo in monitor mode (channel hopping 2.4 GHz)
scripts/probe-tv.sh          a TV online: porte Panasonic, SSDP/UPnP, telecomando VIERA (:55000)
scripts/sniffer-web.py       pannello web (porta 9909) che legge la seriale dell'ESP e mostra
                             probe/TV in tempo reale (stdlib Python, nessuna dipendenza)
captures/                    pcap e log (ESCLUSI dal git via .gitignore)
rete.txt                     parametri di riferimento (SSID/BSSID)
IDEA.md                      visione del progetto VIERA REBORN
```

## 8. Note

- Tutti i dispositivi (TV, router, ESP, Orange Pi, PC, telefono) sono di proprietà
  dell'operatore; l'unico client da far riconnettere è la **propria** TV. Attività di
  recupero/diagnosi su hardware proprio.
- **Segreti fuori dal repo**: la chiave WiFi (10 hex) **non** è versionata; `rete.txt` contiene
  solo SSID e BSSID.
