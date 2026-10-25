# VIERA REBORN
## Recupero di una Panasonic TX-L42ET60E come Network Audio Player Headless

**Tipologia:** Hardware hacking, reverse engineering, recupero elettronico, networking  
**Stato:** Analisi hardware e progettazione preliminare  
**Obiettivo:** Trasformare un televisore con LCD rotto in un dispositivo multimediale di rete autonomo, economico, comandabile senza schermo.

---

# 1. Visione del progetto

Il progetto nasce dal recupero di una Panasonic VIERA TX-L42ET60E del 2013, dotata di pannello LCD da 42 pollici fisicamente danneggiato.

Nonostante il guasto, il dispositivo contiene elettronica potenzialmente funzionante:

- Processore multimediale.
- Scheda madre con firmware e sistema operativo embedded.
- Memoria RAM e memoria firmware.
- Interfaccia Ethernet.
- Connettività Wi-Fi.
- Porte USB.
- Decoder audio/video.
- Funzionalità DLNA/UPnP.
- Uscita audio digitale ottica.
- Amplificazione e altoparlanti.
- Ricevitore infrarossi e telecomando.
- Alimentatore.

L'obiettivo non è necessariamente riparare il televisore come TV, ma **riutilizzare la sua piattaforma informatica per una funzione diversa**.

Il risultato desiderato è un dispositivo simile a uno streamer audio Hi-Fi, controllabile dalla rete locale senza display.

Nome provvisorio: **VIERA Reborn — Headless Network Audio Player**.

Il progetto vuole anche dimostrare che un televisore con pannello rotto non deve necessariamente diventare un rifiuto elettronico.

# 2. Hardware disponibile

## Televisore

| Proprietà | Valore |
|---|---|
| Marca | Panasonic |
| Modello | TX-L42ET60E |
| Anno | 2013 |
| Chassis | LA41 |
| Risoluzione originale | 1920 × 1080 |
| Dimensione schermo | 42 pollici |
| Tecnologia 3D | Passiva polarizzata |
| Condizione | LCD fisicamente fratturato |

## Scheda madre

Identificata dalle fotografie:

`TNPH1038 (1) A`

La documentazione della famiglia ET60 indica un processore MediaTek MT5590, identificato negli schemi come `IC8000`. La corrispondenza esatta della versione montata deve ancora essere verificata sulla scheda.

Funzioni di interesse:

- Elaborazione audio/video.
- Elaborazione grafica e OSD.
- Ethernet 10/100.
- USB.
- Interfacce HDMI in ingresso.
- Funzionalità DLNA.
- Controllo tramite rete, dove disponibile.
- Uscite audio.

Le dimensioni fisiche della scheda devono ancora essere misurate. È stata ipotizzata una dimensione nell'ordine di 20 × 20 cm, ma non è un dato verificato.

La scheda ha un formato proprietario, non Mini-ITX o Micro-ATX.

## Alimentatore

P-Board Panasonic originale, identificata visivamente come la grande scheda gialla del televisore.

Si intende conservarla inizialmente per garantire le tensioni e le sequenze di accensione previste dal produttore.

L'integrazione in uno chassis differente richiede verifiche di isolamento, messa a terra, ventilazione, distanze di sicurezza e cablaggio. Non è previsto alimentare la scheda scoperta su un banco improvvisato.

## Pannello LCD

Identificato attraverso l'etichetta fotografata:

- Produttore: LG Display.
- Modello: `LC420EUD (FF)(F1)`.
- Denominazione compatta: `LC420EUD-FFF1`.
- Codice riportato: `6900L-0652A`.

Il pannello è fisicamente danneggiato.

La sostituzione è stata analizzata, ma economicamente non appare conveniente, salvo recuperare a prezzo molto basso un altro televisore donatore con pannello identico e funzionante.

## Scheda T-CON

Identificata attraverso le fotografie:

- Famiglia ricambio: `6871L-3195A`.
- PCB indicativa: `6870C-0450A`.
- Processore T-CON: LG5822.

I codici devono essere confermati sulle serigrafie dell'esemplare.

Sono presenti due collegamenti superiori verso la scheda madre e due piattine inferiori verso il pannello LCD.

I collegamenti superiori sono associati all'interfaccia video LVDS; quelli inferiori trasportano segnali specifici per il pilotaggio del pannello.

La T-CON non dovrebbe essere necessaria per il progetto audio, **ma prima dobbiamo verificare se il firmware consente l'avvio senza di essa**.

## Altre schede da conservare

- K-Board: ricevitore infrarossi e indicatori.
- GK-Board: pulsanti e comandi locali.
- Modulo Wi-Fi e relativa antenna, se presenti e recuperabili.
- Altoparlanti e cablaggi originali.

I collegamenti effettivamente indispensabili saranno identificati durante le prove.

# 3. Decisioni progettuali

Dopo aver valutato diverse alternative, abbiamo deciso quanto segue.

**Non prioritario:**

- Acquistare un nuovo pannello LCD.
- Costruire un proiettore.
- Convertire il segnale LVDS in HDMI.
- Ricostruire il cablaggio mini-SCART AV1.
- Sviluppare immediatamente un nuovo firmware.
- Utilizzare una FPGA.
- Progettare subito una PCB personalizzata.

Questi argomenti rimangono possibili evoluzioni future, ma non devono bloccare il recupero del dispositivo.

**Obiettivo prioritario:**

1. Recuperare la scheda madre.
2. Verificare che funzioni senza display.
3. Collegarla alla LAN.
4. Controllarla da remoto.
5. Riprodurre audio.
6. Installarla in uno chassis economico e pulito.

La priorità è arrivare a un prototipo funzionante, non massimizzare le modifiche hardware.

# 4. Architettura finale desiderata

Schema concettuale:

```text
                RETE LOCALE
                     |
              Ethernet RJ45
                     |
          +--------------------+
          | Panasonic TNPH1038 |
          |                    |
          | Firmware originale |
          | Decoder multimedia |
          | DLNA / Networking  |
          +--------------------+
                |         |
          Audio digitale  Audio analogico
                |         |
           Uscita SPDIF   Amplificazione
                |         |
              DAC       Altoparlanti
             esterno      originali
```

Il dispositivo dovrebbe avere:

**Pannello frontale:**
- Pulsante di accensione.
- LED di stato originale.
- Eventuale ricevitore IR.

**Pannello posteriore:**
- Ethernet RJ45.
- Uscita ottica digitale.
- Eventuale uscita cuffie.
- Porta USB.
- Alimentazione di rete realizzata e protetta correttamente.

Il tutto inserito in un contenitore chiuso, senza schede o cablaggi esposti.

# 5. Controllo via LAN

Il televisore appartiene alla generazione Panasonic VIERA che dispone di funzionalità di controllo da rete.

Molti modelli utilizzano il protocollo Panasonic VIERA Network Remote Control, basato su richieste HTTP/SOAP e comunemente associato alla porta TCP 55000.

**Non è ancora verificato che il servizio sia attivo sul nostro esemplare.**

## Primo obiettivo: individuare la TV

Su Ubuntu, dopo aver verificato che l'apparecchio possa essere alimentato in sicurezza:

```bash
sudo apt install nmap arp-scan
sudo arp-scan -l
```

Identificare l'indirizzo IP del dispositivo attraverso la tabella DHCP del router oppure tramite scansione della LAN.

Una volta individuato:

```bash
nmap -Pn -sT -p 80,55000 IP_TV
```

Verificare se la porta 55000 è disponibile.

## Libreria Python

Progetto esistente:

https://github.com/florianholzapfel/panasonic-viera

Installazione in ambiente virtuale:

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install panasonic-viera
```

Esempio preliminare:

```python
from panasonic_viera import RemoteControl

tv = RemoteControl("192.168.1.100")

print(tv.get_volume())
```

Da verificare le funzionalità realmente supportate dal firmware.

## Comandi che vorremmo ottenere

- Accensione e standby, se consentiti dalla TV.
- Volume e mute.
- Selezione sorgente.
- Riproduzione, pausa e stop, dove supportati.
- Navigazione dei menu.
- Stato del dispositivo.
- Eventuale selezione dei contenuti multimediali.

Non dobbiamo presumere che tutte queste funzioni siano disponibili via API.

L'obiettivo successivo potrebbe essere una piccola dashboard web sviluppata in Python oppure PHP/JavaScript.

# 6. Funzioni audio e DLNA

La Panasonic supporta tecnologie DLNA/UPnP.

Dobbiamo verificare sperimentalmente i ruoli effettivamente esposti e abilitati.

Sono particolarmente interessanti:

- **MediaRenderer:** ricezione e riproduzione di contenuti inviati da dispositivi della LAN.
- **MediaServer:** pubblicazione di contenuti multimediali disponibili sulla TV.
- **AVTransport:** controllo delle sessioni di riproduzione.
- **RenderingControl:** controllo volume e altri parametri.
- **ContentDirectory:** navigazione dei contenuti condivisi.

La disponibilità teorica di DLNA non garantisce che il televisore sia controllabile completamente senza schermo.

## Discovery da Ubuntu

```bash
sudo apt install gupnp-tools
gupnp-universal-cp
```

Usare il programma per cercare i dispositivi UPnP.

Se il televisore compare come MediaRenderer, provare a inviare un file audio compatibile tramite un controller DLNA.

Se non compare, verificare se la funzione debba essere attivata dalle impostazioni del televisore.

Possibile problema: alcuni servizi di rete potrebbero essere disabilitati, oppure richiedere una prima configurazione tramite OSD.

## Audio disponibile

Il televisore dispone di:

- Uscita digitale ottica.
- Uscita cuffie.
- Amplificazione interna.
- Altoparlanti originali, compreso un woofer.

Per il primo prototipo è preferibile conservare il cablaggio audio originale.

L'uscita ottica permetterebbe di utilizzare un DAC esterno o un amplificatore Hi-Fi senza intervenire direttamente sui circuiti audio.

# 7. Funzionamento senza pannello LCD

Questo è il principale rischio tecnico del progetto.

Non è ancora dimostrato che la scheda madre Panasonic completi il boot quando viene scollegata la T-CON.

Il firmware potrebbe verificare:

- Presenza del pannello.
- Comunicazioni con la T-CON.
- Segnali di stato dell'alimentatore.
- Stato della retroilluminazione.
- Eventuali protezioni hardware.

È necessario distinguere tre casi.

**Caso A — Avvio completo senza pannello**

Situazione ideale. Possiamo eliminare la T-CON dal dispositivo finale.

**Caso B — Avvio possibile mantenendo collegata la T-CON**

Potremmo dover conservare anche la T-CON, pur senza utilizzare il vetro LCD, purché tale configurazione risulti elettricamente sicura e stabile.

**Caso C — Avvio bloccato per errore pannello**

Servirebbe studiare il sistema diagnostico Panasonic prima di procedere. Non vanno simulati segnali di protezione senza averne compreso la funzione.

Le prove di accensione dovranno essere effettuate con alimentatore correttamente fissato e protetto, in una configurazione verificata da un tecnico competente. Non effettuare misure o modifiche su schede di alimentazione esposte e sotto tensione.

# 8. Scelta dello chassis

È stato inizialmente valutato un case rack 19" da 2U o 3U.

L'opzione è stata scartata come requisito perché troppo costosa e non necessaria.

**Nuovo vincolo: contenitore economico, pulito, ordinato e sicuro.**

Budget indicativo per il contenitore: **10–30 €**.

Alternative considerate:

### A. Vecchio DVD recorder o decoder guasto

Opzione preferita se recuperabile gratuitamente.

Vantaggi:
- Chassis già predisposto per elettronica.
- Aspetto da apparecchio multimediale.
- Spesso contenitore metallico.
- Possibilità di riutilizzare pulsanti e parti meccaniche.

Svantaggi:
- Ingombri da verificare.
- Fori di fissaggio non coincidenti.
- Modifiche necessarie per i connettori.

### B. Contenitore universale per elettronica

Ricercare:

- `electronics project enclosure metal`
- `DIY amplifier case`
- `desktop electronics chassis`
- `250x250 metal enclosure`
- `300x250x100 electronics enclosure`

Dimensioni da determinare dopo aver misurato la scheda madre e l'alimentatore.

### C. Case PC desktop usato

Soluzione semplice, ventilata e spesso economica.

Un contenitore Mini-ITX standard potrebbe però essere troppo piccolo per la scheda Panasonic.

### D. Chassis Hi-Fi economico

Come riferimento è stato trovato un contenitore PCS Electronics da circa 440 × 310 × 90 mm, proposto a circa 29 € + IVA.

Prezzo e disponibilità da ricontrollare al momento dell'acquisto.

## Requisiti meccanici

- Fissaggi che utilizzino correttamente i punti originali.
- Nessuna possibilità di contatto accidentale con circuiti di rete.
- Ventilazione adeguata.
- Distanze fra alimentatore e circuiti logici.
- Collegamenti di terra corretti, se richiesti.
- Protezione meccanica dei cablaggi.
- Adeguato accesso ai connettori di rete e audio.
- Nessuna superficie tagliente a contatto con i cavi.

Non è sufficiente che le schede entrino fisicamente nella scatola: il nuovo assemblaggio deve essere elettricamente sicuro.

# 9. Ricerca hardware già effettuata

Durante lo studio del televisore abbiamo esplorato diverse possibilità alternative, ora considerate secondarie.

## Sostituzione del pannello

Pannello originale:

`LG Display LC420EUD-FFF1`

Prezzi di catalogo individuati per ricambi completi: indicativamente 190–210 €, spesso esauriti.

Sono stati individuati anche pannelli della famiglia LC420EUD, ma non è garantita la compatibilità fra differenti revisioni.

Una TV usata funzionante da 42 pollici può costare meno del solo pannello.

La sostituzione rimane interessante soltanto trovando un donatore a costo molto basso.

## Porta AV1

Il televisore possiede una mini-SCART proprietaria Panasonic.

Codice adattatore originale:

`K1HY20YY0013`

Possibile codice alternativo:

`K1HY20YY0016`

L'adattatore era originariamente fornito in dotazione al televisore.

La porta supporta connessioni analogiche audio/video e funzioni di uscita, ma non è dimostrato che esporti OSD, applicazioni o tutte le sorgenti HDMI.

Abbiamo valutato di realizzare un adattatore artigianale.

La spina somiglia a una DisplayPort, ma la disposizione sfalsata dei contatti è differente. **Non è meccanicamente/elettricamente intercambiabile con una normale DisplayPort.**

È stata valutata anche la possibilità di prelevare i segnali analogici direttamente dalla scheda madre, identificando il circuito `CVBS OUT`.

Questa strada è attualmente sospesa.

## Conversione LVDS → HDMI

Abbiamo studiato il percorso:

```text
Processore video Panasonic
          |
       LVDS
          |
      T-CON LG
          |
    Driver del pannello
          |
     Matrice LCD
```

La T-CON possiede due connessioni superiori associate al video proveniente dalla scheda madre.

Sono stati individuati connettori della famiglia JAE FI-R, indicativamente da 51 e 41 pin. Prima di fabbricare adattatori bisogna verificare codici, orientamento e piedinatura sul nostro esemplare.

È stata valutata una scheda Geekworm LVDS2HD, che converte LVDS in HDMI.

Rimangono sconosciuti:
- Numero effettivo delle porte LVDS indipendenti.
- Mappatura delle coppie differenziali.
- Formato pixel.
- Temporizzazioni effettive.
- Eventuale compatibilità con ricevitori dual-link.
- Comportamento del firmware senza T-CON.

La conversione LVDS non è stata giudicata conveniente per la prima versione dello streamer.

## Possibile breakout hardware

È stata concepita una PCB con connettori JAE, punti diagnostici e interfaccia verso un ricevitore LVDS.

Non è stata ancora progettata né prodotta.

Le linee LVDS richiedono routing adatto a segnali differenziali veloci; non sono compatibili con l'uso indiscriminato di una breadboard a cavetti Dupont.

Anche questa strada viene conservata come possibile progetto indipendente futuro.

# 10. Possibilità di reverse engineering del firmware

Nel lungo periodo potremmo esplorare le capacità software della scheda madre.

Possibili argomenti:

- Architettura e sistema operativo embedded.
- Bootloader.
- Partizioni firmware.
- Servizi TCP/UDP disponibili.
- Protocollo VIERA.
- Endpoint HTTP/SOAP.
- Interfacce UART di diagnostica.
- Eventuali console di servizio.
- Possibilità di accesso ai framebuffer.
- Disponibilità di API interne del processore MediaTek.

Nessuna console o shell è stata ancora identificata e non è confermata la possibilità di eseguire codice personalizzato.

La priorità rimane sfruttare il firmware originale senza modificarlo.

# 11. Piano operativo

## Fase 0 — Inventario

- Fotografare tutte le schede.
- Registrare codici e revisioni.
- Misurare dimensioni, altezze e distanze fra i fori.
- Identificare connettori, cablaggi e schermature.
- Documentare i moduli di controllo.
- Conservare i cablaggi originali.

**Output:** inventario hardware completo.

## Fase 1 — Validazione del funzionamento

Prima di investire nel nuovo chassis:

- Verificare la sicurezza dell'assemblaggio.
- Accertare che la scheda madre possa completare il boot.
- Collegare la scheda alla LAN.
- Individuare il dispositivo attraverso il router.
- Verificare la presenza di servizi di rete.
- Verificare almeno una modalità funzionante di riproduzione audio.

**Output:** dimostrazione che il dispositivo può funzionare come nodo audio senza schermo.

## Fase 2 — Controllo remoto

Sviluppare un piccolo programma che:

- Identifichi la Panasonic.
- Interroghi le funzioni disponibili.
- Regoli volume e mute.
- Inoltri i comandi del telecomando supportati.
- Gestisca la riproduzione dove possibile.

**Output:** primo client software funzionante.

## Fase 3 — Streaming audio

Provare:
- Invio di file tramite DLNA.
- Controllo MediaRenderer.
- Riproduzione da server multimediale locale.
- Uscita audio ottica.
- Eventuale riproduzione di radio Internet tramite un meccanismo compatibile.

**Output:** riproduzione audio comandata da un altro dispositivo della LAN.

## Fase 4 — Mini dashboard

Sviluppare una semplice interfaccia web.

Funzioni possibili:
- Accensione/standby.
- Volume.
- Mute.
- Sorgente.
- Riproduzione.
- Stato di connessione.

Una dashboard può sostituire le funzioni di controllo del vecchio telecomando, ma non necessariamente il sistema grafico Panasonic.

**Output:** interfaccia web locale.

## Fase 5 — Nuovo chassis

Dopo i test funzionali:

- Scegliere il contenitore più economico e adatto.
- Preparare i supporti delle schede.
- Organizzare l'alimentazione in sicurezza.
- Posizionare LAN e connessioni audio.
- Portare all'esterno IR e pulsante di accensione.
- Gestire ventilazione e cablaggi.
- Effettuare le verifiche elettriche finali.

**Output:** dispositivo chiuso e utilizzabile.

# 12. Criteri di successo

Il progetto minimo è completato quando:

1. La scheda madre si avvia stabilmente senza LCD.
2. Il dispositivo è raggiungibile via Ethernet.
3. È possibile gestire almeno le principali funzioni da remoto.
4. Riproduce un file o un flusso audio dalla LAN.
5. L'audio è disponibile tramite una delle uscite originali.
6. Tutta l'elettronica necessaria è installata in un contenitore sicuro, pulito ed economico.

Non è indispensabile che funzioni come una moderna smart TV. È sufficiente recuperare una funzione multimediale realmente utile.

# 13. Questioni ancora aperte

Le principali incognite da risolvere sono:

- La TNPH1038 completa il boot senza LCD e T-CON?
- Quali schede secondarie sono indispensabili?
- Il servizio Panasonic VIERA sulla porta 55000 è disponibile?
- Il DLNA Renderer è attivo e utilizzabile senza interfaccia grafica?
- Come si può impostare inizialmente la rete senza schermo?
- Quali funzioni sono utilizzabili tramite comandi IR?
- L'uscita ottica funziona anche durante la riproduzione DLNA?
- È possibile disabilitare completamente la retroilluminazione?
- Qual è il consumo energetico del televisore senza pannello?
- Quanto calore produce la scheda madre?
- Quanto misura effettivamente l'elettronica da conservare?
- Conviene mantenere l'alimentatore originale o, dopo un'analisi elettrica completa, valutarne uno alternativo certificato?

# 14. Filosofia del progetto

VIERA Reborn nasce da un principio:

**Il guasto di un componente non deve automaticamente determinare la fine dell'intero dispositivo.**

Un televisore moderno contiene un computer embedded, una piattaforma di networking, decoder multimediali e molte interfacce.

Se il display viene distrutto, tutto questo hardware conserva potenzialmente un valore funzionale.

Il progetto intende dimostrare la possibilità di recuperare questa elettronica senza dover riprogettare o acquistare un computer sostitutivo.

In prospettiva, potrebbe diventare una metodologia replicabile per altri dispositivi elettronici con display guasto.

Possibile futura pubblicazione open source:

`viera-reborn`

Contenuti del repository:
- Inventario hardware.
- Fotografie e identificazione dei moduli.
- Analisi dei servizi di rete.
- Software di controllo.
- Documentazione sul funzionamento headless.
- Layout meccanico dello chassis.
- Eventuali adattatori hardware sviluppati.
- Guida al recupero di altri modelli.

---

# 15. Prossima azione immediata

**Non acquistare ancora lo chassis.**

Il prossimo lavoro è verificare il comportamento della Panasonic senza il pannello LCD, in una configurazione elettricamente sicura, e analizzarne i servizi sulla rete Ethernet.

In parallelo, raccogliere le misure delle schede per scegliere un contenitore da 10–30 €.

L'obiettivo del primo milestone non è costruire un prodotto finito.

**È dimostrare che una TV Panasonic del 2013 con LCD distrutto può diventare un lettore multimediale di rete controllabile senza schermo.**
