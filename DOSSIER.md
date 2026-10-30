# DOSSIER — VIERA REBORN: riconnessione WiFi della TV

**Progetto:** recupero di una Panasonic VIERA **TX‑L42ET60E** (2013, pannello LCD rotto)
come lettore audio di rete *headless* (vedi `IDEA.md`).
**Stato:** la TV non riesce più a riassociarsi alla rete WiFi che ricorda; indagine in corso.
**Ultimo aggiornamento:** 2026‑10‑30.

---

## 1. Obiettivo immediato

Riportare la TV online via WiFi per poterla raggiungere dalla LAN (telecomando VIERA,
UPnP/DLNA, porte di servizio) e proseguire con la conversione a streamer audio senza schermo.

Il blocco attuale **non** è la TV in sé: è che non esiste più, sull'aria, un access point
che corrisponda **esattamente** al profilo che la TV ha in memoria. Un client WiFi non si può
"forzare" ad associarsi: l'associazione la inizia sempre lui. Si deve quindi ricreare un AP
identico a quello che la TV si aspetta, così è lei a riconnettersi da sola.

## 2. Topologia attuale (30/10)

| Dove | Cosa |
|---|---|
| **Casa** | Router **Huawei** (gateway `192.168.8.1`), e l'operatore (io) collegato alla **VPN dell'ufficio** |
| **Ufficio** | La **TV VIERA**, l'**ESP‑01**, l'**Orange Pi Zero** (`192.168.144.44`, AP), il PC **`Intel5`** (`192.168.144.10`) |
| **Domani** | Il router Huawei verrà portato in ufficio |

Operativamente: tutto il lavoro gira su `Intel5` (raggiunto via SSH sulla VPN, `tun0`).

## 3. Dispositivi e identificativi

| Dispositivo | Identificativo | Note |
|---|---|---|
| TV VIERA (station) | MAC **`c0:d9:62:2f:08:11`** | OUI Panasonic; cerca l'SSID `RETEDICASA0` |
| SSID cercato dalla TV | **`RETEDICASA0`** | con lo zero finale |
| BSSID vecchio router | **`90:2b:d2:f6:f2:36`** | clonato da firmware/script |
| Router Huawei (reale, oggi) | `192.168.8.1`, SSID **`RETEDICASA`** (senza `0`), **canale 2**, WPA2, BSSID `…:36` | a casa |
| Altro AP in ambiente | `3c:37:12:e6:4a:0b` = **FRITZ!Box 7530 JK** | visto rispondere ai probe in ufficio |
| ESP‑01 (FakeAP) | SoftAP `RETEDICASA0`, BSSID `…:36`, **canale 6**, `AUTH_WPA_WPA2_PSK` | `firmware/fakeap/fakeap.ino` |
| Orange Pi Zero | **`192.168.144.44`** (VPN), WiFi XR819, AP via hostapd | `scripts/orangepi-wep-ap.sh` (default **WEP**); faceva da access point. Serve DHCP su `192.168.60.0/24` e inoltra verso `eth0`, così dalla LAN si raggiunge la TV aggiungendo una rotta via l'Orange Pi. SSH aperto (login a password) |
| PC Intel | host `Intel5`, dongle WiFi `wlxe0b2f1c5819b`, NIC `eno1` | banco di lavoro |

## 4. Sintomo osservato (dai dati, non da ipotesi)

Dalle catture in `captures/`:

- `captures/wifi.pcap`: **113 probe‑request** della TV, **0 probe‑response**, **0 auth**,
  **0 assoc‑request/response**, **0 EAPOL**.
- `captures/probesniff-20261030-164740.log`: la TV fa probe diretti per `RETEDICASA0`
  sui **canali 2 e 3**; l'unico probe‑response che riceve è da un **FRITZ!Box** per il
  *suo* SSID, non per `RETEDICASA0`.

**Conclusione:** la TV arriva solo alla fase di *probe*. Nessun AP le risponde con l'SSID
`RETEDICASA0` in modo compatibile, quindi non passa mai ad auth/associazione. Il problema è
**prima** dell'autenticazione (handshake WPA/EAPOL mai raggiunto).

## 5. Diagnosi — perché probe sì, associazione no

Cause probabili, dalla più sospetta:

1. **SSID non combaciante.** La TV cerca `RETEDICASA0`; il Huawei reale trasmette `RETEDICASA`
   (senza `0`). Stringhe diverse ⇒ la TV non si associa al Huawei. Serve un AP esattamente
   `RETEDICASA0`.
2. **Sicurezza/cifratura non combaciante.** La vecchia rete era probabilmente **WEP**
   (lo suggerisce `orangepi-wep-ap.sh`, ed è coerente con un setup del 2013). Una TV che ha in
   memoria un profilo **WEP** non si associa a un AP **WPA/WPA2** con lo stesso SSID. Il FakeAP
   su ESP‑01 è configurato `AUTH_WPA_WPA2_PSK` e **l'ESP8266 non sa fare WEP in SoftAP** → via
   sbagliata se il profilo è WEP.
3. **Collisione di BSSID + canale.** Il FakeAP usa il **BSSID `…:36`** del router reale ma sul
   **canale 6**, mentre il router reale è sul **canale 2** con lo stesso BSSID. Due AP con BSSID
   identico su canali diversi mandano in confusione i client.
4. **Modalità/rates 802.11.** Con WEP va forzato `hw_mode=g` e **`ieee80211n=0`** (il WEP non è
   ammesso in 802.11n): già previsto in `orangepi-wep-ap.sh`.

## 6. Asset nel repository

```
firmware/probesniff/probesniff.ino  Sniffer ESP‑01 in modo promiscuo: hop canali 1‑13, logga ogni
                                    probe request (MAC, canale, RSSI, SSID), i beacon e i frame di
                                    management da/verso WATCH_MAC (la TV). Produce captures/probesniff-*.log
firmware/fakeap/fakeap.ino   FakeAP su ESP‑01 (SoftAP WPA/WPA2, BSSID clonato, conta i probe della TV)
firmware/build.sh            build/flash/monitor con arduino-builder; sketch di default `probesniff`
                             (SKETCH_NAME=fakeap + FAKEAP_PASS per il FakeAP). `monitor` salva in captures/
scripts/orangepi-wep-ap.sh   AP WEP su Orange Pi (XR819) — la via giusta se la rete era WEP
scripts/router.sh            finto router su LAN diretta PC<->TV (dnsmasq DHCP/DNS + tcpdump, NAT opz.)
scripts/wifi-sniff.sh        sniffing passivo in monitor mode (channel hopping 2.4 GHz)
scripts/probe-tv.sh          una volta online: porte Panasonic, SSDP/UPnP, telecomando VIERA (:55000)
captures/                    pcap e log di probe (ESCLUSI dal git tramite .gitignore)
rete.txt                     parametri rete di riferimento (SSID/BSSID)
IDEA.md                      visione del progetto VIERA REBORN
```

## 7. Fatto finora

- Sniffing in monitor mode e conferma che la TV fa **solo probe** per `RETEDICASA0` (ch 2/3).
- Scritto il FakeAP ESP‑01 (WPA/WPA2) — **non** ha ancora portato la TV all'associazione.
- Predisposti gli AP alternativi (Orange Pi WEP) e il finto router per la LAN cablata.
- Catalogati gli identificativi di TV, router reale e AP vicini.

## 8. Prossimi passi (piano di test ordinato)

1. **Stabilire la sicurezza della vecchia rete** (WEP o WPA). Se WEP, abbandonare il FakeAP
   ESP‑01 per quel test e usare l'**AP WEP su Orange Pi** (`orangepi-wep-ap.sh`) con
   `SSID=RETEDICASA0`, `MODE=wep`, `CHANNEL=2`, e `BSSID` = `90:2b:d2:f6:f2:36`.
2. **Allineare il canale** a quello che la TV cerca (2) ed evitare la collisione di BSSID:
   tenere spento il router reale durante il test, oppure usare un BSSID diverso se non è il
   BSSID a essere memorizzato ma solo l'SSID.
3. **Catturare auth/assoc** durante il tentativo: se compaiono *auth* o *assoc‑request* con un
   *reason/status code*, quello dice esattamente cosa rifiuta la TV (cifratura, rates, PMF…).
4. **Verificare la PSK/chiave** salvata nella TV (se WPA) o la chiave WEP corretta.
5. Quando la TV prende un lease DHCP, lanciare **`scripts/probe-tv.sh`** per raggiungerla
   (telecomando VIERA su `:55000`, SSDP/UPnP) e proseguire col progetto headless.

## 9. Nota operativa

Tutti i dispositivi coinvolti (TV, router, ESP, Orange Pi, PC) sono di proprietà
dell'operatore; l'unico client da far riconnettere è la **propria** TV sulla **propria** rete
domestica. Attività di recupero/diagnosi su hardware proprio.
