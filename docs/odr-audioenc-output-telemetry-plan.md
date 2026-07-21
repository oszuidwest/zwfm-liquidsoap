# Plan: outputtelemetrie voor ODR-AudioEnc en integratie in Liquidsoap

Status: langetermijnplan; TCP ACK-monitoring is als no-forktussenstap uitgewerkt
Datum: 21 juli 2026
Auteursscope: `zwfm-liquidsoap`, ODR-AudioEnc en `zwfm-odrbuilds`

## 1. Besluit in het kort

Breid ODR-AudioEnc uit met backwards-compatible outputtelemetrie in de bestaande
`--stats`-JSON. Maak daarbij een strikt onderscheid tussen:

1. lokale verwerking: AudioEnc encodeert en levert data aan een output;
2. transportstatus: bijvoorbeeld een actieve TCP-sessie;
3. end-to-endontvangst: de ontvangende DabMux bevestigt dat audio wordt verwerkt.

Alleen de eerste twee zijn vanuit AudioEnc vast te stellen. Omdat de DabMux van de
provider niet uitleesbaar is, kan dit project geen echte end-to-endgarantie geven.
UDP kan daarom nooit `connected` of `receiver_confirmed` rapporteren. Voor UDP
rapporteren we uitsluitend lokale verzendpogingen en lokale socketfouten.

De aanbevolen eerste oplevering ondersteunt alle outputs die ODR-AudioEnc op de
`next`-branch werkelijk via zijn CLI kan configureren:

- EDI TCP-client;
- EDI UDP;
- EDI-bestandsoutput;
- ZeroMQ (`tcp`, `pgm`, `epgm` en `ipc`);
- ruwe bestandsoutput en stdout.

De hoogste operationele waarde zit in EDI TCP-client: connectiestatus, pogingen,
disconnects, queuevulling en weggegooide frames worden dan rechtstreeks zichtbaar
in Liquidsoap. De huidige uitgaande pakketmonitor blijft tijdens de invoering actief.

### 1.1 No-forktussenstap in `zwfm-liquidsoap`

De native AudioEnc-uitbreiding is niet nodig om TCP-ACK-progressie te bewaken.
`zwfm-liquidsoap` kan de ongewijzigde AudioEnc-binary starten via een dunne
supervisor die het PID vastlegt. Een aparte monitor leest daarna Linux `TCP_INFO`
via `ss` en vergelijkt per EDI TCP-bestemming de cumulatieve `bytes_sent` en
`bytes_acked`.

Deze tussenstap levert nu al:

- TCP state en ACK-progressie;
- send queue, unacknowledged segments en retransmits;
- status per bestemming via `dab.status`;
- geen AudioEnc-fork en geen packet-capturecapabilities.

Hij levert niet de interne AudioEnc-queue, framedrops of UDP-ontvangststatus. Het
resterende document beschrijft daarom nog steeds de gewenste native upstream-
telemetrie als mogelijke latere verbetering.

## 2. Onderzoeksbasis

Dit plan is gebaseerd op de actuele upstream `next`-branch van
[Opendigitalradio/ODR-AudioEnc](https://github.com/Opendigitalradio/ODR-AudioEnc/tree/next):

- commit: [`7c14c4f65b1a670f2397237343c988317e0d2bce`](https://github.com/Opendigitalradio/ODR-AudioEnc/commit/7c14c4f65b1a670f2397237343c988317e0d2bce);
- commitdatum: 25 juni 2026;
- onderwerp: `Add EDI file output`;
- taalstandaard: C++17;
- build: Autoconf/Automake;
- pakketversie in `configure.ac`: nog `3.6.0`.

De remote `refs/heads/next` is voor dit onderzoek expliciet vergeleken met de
lokale bronclone; beide wezen naar bovengenoemde commit.

Daarnaast zijn onderzocht:

- de volledige project-eigen source surface onder `src/` en `contrib/`;
- de CLI, encodeerlus, inputs, outputs, EDI-packetisering en socketlagen;
- threading, queues, foutafhandeling en de bestaande stats-publisher;
- buildconfiguratie, CI en documentatie;
- de huidige DAB-integratie in `zwfm-liquidsoap`;
- de build- en Dockerketen in
  [`oszuidwest/zwfm-odrbuilds`](https://github.com/oszuidwest/zwfm-odrbuilds);
- de beschikbare socket-, JSON-, thread- en serverfuncties in de gebruikte
  Liquidsoap 2.4.5-image;
- upstream issues en pull requests op bestaande output- of statsvoorstellen.

Er staat op dit moment geen open of gesloten upstream issue of pull request die
de hier voorgestelde outputtelemetrie al implementeert. De bestaande stats-code
is in 2016 toegevoegd en is later alleen JSON-compatibel en portabeler gemaakt.

### 2.1 Afbakening van de bronanalyse

De repository bevat naast de eigen code twee grote ingebedde codecs:

- `fdk-aac/`: 427 bestanden;
- `libtoolame-dab/`: 67 bestanden.

Deze codecs bepalen de audiocodering, maar hebben geen verantwoordelijkheid voor
outputtransport of `--stats`. Ze zijn als afhankelijkheid en buildsurface
geïnventariseerd, maar hoeven voor dit ontwerp niet aangepast te worden.

De project-eigen runtimecode bestaat uit 65 gevolgde bestanden onder `src/` en
`contrib/`, ongeveer 12.400 regels exclusief de meegeleverde `zmq.hpp`. Alle
grenzen waar audioframes, outputfouten, queues of statistieken doorheen lopen zijn
in dit onderzoek meegenomen.

## 3. Huidige architectuur

De relevante runtimeflow is:

```text
Liquidsoap audio
      |
      | WAV via stdin
      v
AudioEnc::run()
      |
      | gecodeerd DAB/DAB+-frame
      v
AudioEnc::send_frame()
      |
      +--> Output::File
      |
      +--> Output::ZMQ --------> één PUB-socket, meerdere endpoints
      |
      +--> Output::EDI
              |
              v
          edi::Sender
              |
              +--> UDP sender
              +--> TCP send client
              +--> TCP dispatcher (aanwezig in library, niet in AudioEnc CLI)

AudioEnc::run() ----------------> StatsPublisher ----------------> UNIX DGRAM
     audiolevels/drift                  huidige --stats
```

De stats-publisher staat nu naast de outputs. Hij kent alleen audiolevels en
driftcompensatie; hij heeft geen referentie naar `Output::File`, `Output::ZMQ` of
`Output::EDI`. Outputstatus moet daarom via een expliciete snapshot-API naar de
publisher worden gebracht.

### 3.1 Bronkaart en relevantie

| Onderdeel | Bestanden | Huidige verantwoordelijkheid | Geplande impact |
|---|---|---|---|
| Hoofdprogramma | `src/odr-audioenc.cpp` | CLI, input/outputconstructie, encodeerlus, stats-cadans en exitcodes | Outputsnapshots verzamelen en aan `StatsPublisher` geven |
| Output-API | `src/Outputs.h`, `src/Outputs.cpp` | Raw file, stdout, ZeroMQ en EDI-wrapper | Generieke snapshot-API en tellers per output |
| Stats | `src/StatsPublish.h`, `src/StatsPublish.cpp`, `example_stats_receiver.py` | UNIX-datagram met handmatig gebouwde JSON | Schema v2, escaping, grotere receiverbuffer en outputarray |
| EDI-configuratie | `contrib/edioutput/EDIConfig.h` | UDP-, TCP-client- en TCP-serverconfiguratie | Stabiele outputidentiteit en configuratiemetadata |
| EDI-transport | `contrib/edioutput/Transport.h`, `Transport.cpp` | PFT-spreading en transportdispatch | Snapshot per sender; verzend- en fouttellers |
| Sockets | `contrib/Socket.h`, `Socket.cpp` | UDP, TCP-client, TCP-server en reconnectthread | Thread-safe TCP-status, queue-drops en foutdetails |
| Queue | `contrib/ThreadsafeQueue.h` | Thread-safe buffering en overflowhelpers | Bestaande atomische overflowhelper gebruiken |
| EDI-packetisering | `AFPacket.*`, `PFT.*`, `TagPacket.*`, `TagItems.*` | AF/PFT/TAG-opbouw | Geen protocolwijziging; alleen aantallen na dispatch meten |
| Inputs | `InputInterface.h`, `FileInput.*`, `AlsaInput.*`, `JackInput.*`, `GSTInput.*`, `VLCInput.*`, `SampleQueue.h` | PCM-aanvoer en inputbuffering | Geen outputwijziging; bestaande underrun/overrunstats blijven intact |
| Codec | `AACDecoder.*`, FDK-AAC, TooLAME, Reed-Solomon | DAB/DAB+-codering en testdecoder | Geen wijziging |
| Logging | `contrib/Log.*` | Asynchrone logging via `etiLog` | Alleen overgangslogs; stats mogen niet van verbose logging afhangen |
| Build/CI | `Makefile.am`, `configure.ac`, `.travis.yml` | C++17-buildmatrix, nog zonder tests | Testtargets en reproduceerbare versie toevoegen |

Voor de volledigheid zijn ook de overige project-eigen units beoordeeld:

| Onderdeel | Bestanden | Relatie tot dit plan |
|---|---|---|
| PAD | `src/PadInterface.*` | Eigen UNIX-socket voor DLS/MOT; staat los van outputhealth en wijzigt niet |
| TAI/timestamps | `contrib/ClockTAI.*` | Levert EDI-timestamps; netwerkdownload en cache raken het statscontract niet |
| ICY en hulpmethoden | `src/utils.*` | Metadata- en levelhelpers; bestaande audiolevelbron blijft gebruikt |
| WAV | `src/wavfile.*` | Input/testdecoder-output, niet het DAB-outputtransport |
| ZMQ Curve | `src/encryption.*` | Leest secret key; telemetrie mag deze data nooit publiceren |
| CRC/FEC | `contrib/crc.*`, `contrib/fec/*`, `contrib/ReedSolomon.*` | AF/PFT-bescherming; alleen het resulterende verzendvolume wordt geteld |
| Remote-controlstub | `contrib/RemoteControl.h` | Compile-time uitgeschakeld en geen alternatief statsoppervlak |
| Legacy encodervoorbeeld | `src/aac-enc.c` | Wordt niet in `odr_audioenc_SOURCES` gebouwd en valt buiten de runtimewijziging |
| Meegeleverde C++ ZMQ-binding | `src/zmq.hpp` | Biedt sendreturn en `monitor_t`; niet inhoudelijk forken buiten benodigd API-gebruik |

## 4. Bevindingen in de huidige `next`-code

### 4.1 Bestaande `--stats`

`StatsPublisher` verstuurt na ieder geproduceerd outputframe een niet-blokkerend
UNIX-datagram. Bij DAB+ is dat in de praktijk ongeveer 8,3 berichten per seconde,
één per superframe van 120 ms.

De huidige payload bevat alleen:

```json
{
  "program": "ODR-AudioEnc",
  "version": "",
  "audiolevels": { "left": 410, "right": 410 },
  "driftcompensation": { "underruns": 0, "overruns": 0 }
}
```

Eigenschappen en beperkingen:

- verzending is non-blocking en mag de encoder niet vertragen;
- een ontbrekende stats-ontvanger is niet fataal;
- `audiolevels` worden na verzending gereset;
- driftcounters zijn cumulatief;
- JSON wordt handmatig opgebouwd zonder algemene string-escaping;
- de voorbeeldreceiver leest maximaal 256 bytes, te klein voor meerdere outputs;
- de client bindt `/tmp/odr-audioenc.<pid>`, maar verwijdert dit socketpad niet in
  de destructor;
- in de gebruikte `next`-build is `version` leeg doordat de shallow branchclone
  geen bruikbaar resultaat voor `git describe` oplevert.

### 4.2 EDI TCP-client

De TCP-client draait in een eigen `TCPSendClient`-thread. De encodeer-/EDI-thread
plaatst frames in een queue; de senderthread maakt de verbinding en verstuurt de
frames.

Er is intern al informatie aanwezig over:

- doelhost en -poort;
- aantal connectiepogingen onder de misleidende naam `num_reconnects`;
- laatste connectiefout;
- impliciete status in `m_is_connected`;
- actuele queuegrootte.

Deze informatie verlaat de transportlaag nu alleen als waarschuwing wanneer
`--edi-verbose` actief is.

Belangrijke details:

- `num_reconnects` telt ook de eerste connectiepoging en is dus geen zuivere
  reconnectteller;
- `m_is_connected` is geen atomic omdat hij nu alleen door de senderthread wordt
  gebruikt; voor snapshots moet dit thread-safe worden;
- de queue is begrensd op 512 frames;
- bij overflow wordt het oudste frame verwijderd, maar dit wordt niet geteld;
- de laatste fout wordt na herstel niet gewist;
- een mislukte socket-send verliest de concrete fouttekst;
- het publieke `Output::EDI::write_frame()` retourneert altijd `true` en bevat nog
  de TODO `Handle TCP disconnect`;
- een TCP-sessie kan `connected` blijven terwijl de DabMux-applicatie gepauzeerd
  is, zolang de ontvangende kernel data blijft bevestigen of bufferen.

### 4.3 EDI UDP

UDP gebruikt per bestemming een `UDPSocket` en `sendto()`. De bestemming wordt
bij een send lokaal geresolved. Er bestaat geen sessie en er zijn geen
ontvangstbevestigingen.

Meetbaar vanuit AudioEnc:

- verzendpogingen;
- lokaal succesvol aan de kernel aangeboden pakketten en bytes;
- lokale resolve-, route- en socketfouten;
- tijd sinds de laatste lokale succesvolle send.

Niet meetbaar:

- of het pakket het netwerk verlaat;
- of de provider het pakket ontvangt;
- of DabMux het pakket verwerkt;
- packet loss verderop in het pad.

De socketlaag negeert momenteel `ECONNREFUSED` voor UDP. Dit bestaande gedrag
moet niet stilzwijgend als succes of als receiverbevestiging worden gepresenteerd.

### 4.4 EDI TCP-server

De gedeelde EDI-transportcode kent ook een TCP-server/dispatcher. Daarvoor bestaat
al `get_tcp_server_stats()` met verbonden peers en buffer fullness.

ODR-AudioEnc heeft op `next` echter geen CLI-pad dat een `tcp_server_t` aanmaakt:
`--edi=tcp://...` maakt altijd een uitgaande TCP-client. De serverstatistiek is dus
relevant voor hergebruik van de transportcode, maar geen zichtbare AudioEnc-output.
Dit plan voegt geen nieuwe luisterende EDI-modus toe.

### 4.5 EDI-bestandsoutput

Commit `7c14c4f` heeft `--edi=file://...` opnieuw toegevoegd. Het AF-pakket wordt
naar `FILE*` geschreven.

Huidig gedrag bij een schrijffout:

- een waarschuwing wordt gelogd;
- het bestand wordt gesloten;
- `Output::EDI::write_frame()` blijft `true` retourneren;
- AudioEnc blijft draaien zonder nog naar dat bestand te schrijven.

Telemetrie moet deze output daarom expliciet als `down` kunnen markeren. Een
eventuele wijziging waardoor een permanente schrijffout ook de bestaande
send-error/exitcode 4 activeert, moet als afzonderlijke gedragswijziging worden
gereviewd.

### 4.6 Ruwe bestandsoutput en stdout

`Output::File::write_frame()` retourneert het resultaat van `fwrite()`. Na meer
dan tien mislukte outputframes stopt de hoofdloop met exitcode 4. Er zijn nu geen
bytes-, frames- of fouttellers en geen concrete fout in de stats.

### 4.7 ZeroMQ

Alle `-o`-netwerk-URI's worden aangesloten op één `ZMQ_PUB`-socket. Ondersteund
zijn `tcp://`, `pgm://`, `epgm://` en `ipc://`. Eén ZMQ-object kan dus meerdere
endpoints bevatten.

Huidige beperkingen:

- `send(..., dontwait)` is asynchroon;
- succesvol queueën is geen bewijs van een subscriber;
- de optionele returnwaarde van non-blocking `send()` wordt niet gecontroleerd;
- alleen een gegooide `zmq::error_t` telt als sendfout;
- er zijn geen per-endpoint states;
- de meegeleverde `zmq.hpp` ondersteunt wel `monitor_t` en events zoals
  `CONNECTED` en `DISCONNECTED`.

Daarom bestaat de ZMQ-implementatie uit twee stappen: eerst correcte lokale
sendtellers en daarna optioneel per-endpoint transportevents via een monitor.

### 4.8 Hoofdloop en foutsemantiek

`AudioEnc::send_frame()` combineert de resultaten van ZMQ en EDI. Raw file is
mutually exclusive en retourneert direct. Na meer dan tien false returns stopt
AudioEnc met exitcode 4, waarna Liquidsoap het proces kan herstarten.

EDI TCP-disconnects geven nu geen false return: de client blijft in een
reconnectlus. Daardoor blijft `--stats` tijdens een verbroken bestemming normaal
doorlopen. Dit is gewenst voor beschikbaarheid van de encoder, maar betekent dat
procesliveness geen outputhealth is.

### 4.9 Test- en releaseoppervlak

Upstream heeft momenteel:

- geen `tests/`-directory;
- geen `check_PROGRAMS` of Automake `TESTS`;
- een Travis-matrix die alleen bouwt;
- builds voor macOS en Linux, met optionele ALSA/JACK/VLC/GStreamervarianten.

`zwfm-odrbuilds` bouwt AudioEnc als volgt:

- `ODR_AUDIOENC_BRANCH=next`;
- shallow clone met `--depth 1`;
- geen commitpin in `build.env`;
- minimale en volledige binaries voor meerdere distributies/architecturen;
- Dockerimages worden uit de releasebinary opgebouwd;
- de Docker-tag is `next`, zonder `latest` voor developmentversies.

Een nieuwe upstream commit kan daardoor onder dezelfde naam een andere binary
opleveren. Reproduceerbaarheid en versie-identificatie zijn onderdeel van dit
plan.

## 5. Resultaten van de Docker-proef

De volgende proef is lokaal uitgevoerd met:

- `ghcr.io/oszuidwest/odr-audioenc-minimal:next`;
- `ghcr.io/oszuidwest/odr-dabmux:v5.5.1`;
- synthetische 48 kHz stereo-audio;
- EDI over TCP;
- de bestaande `--stats`-UNIX-datagrams.

| Scenario | AudioEnc | Huidige `--stats` | DabMux |
|---|---|---|---|
| Normaal | Draait | Circa 8,3/s, audiolevels aanwezig | Ontvangt audio |
| DabMux gestopt | Draait en probeert iedere seconde opnieuw | Ongewijzigd | Niet beschikbaar |
| DabMux herstart | Herstelt binnen ongeveer twee seconden | Ongewijzigd | Ontvangt weer |
| DabMux gepauzeerd | Geen fout en TCP blijft lokaal established | Ongewijzigd | Na hervatten veel underruns/overruns |
| AudioEnc gestopt | Proces stopt | Binnen één seconde stale | Gaat naar `NoData` |

Conclusie: `--stats` is nu al bruikbaar als encoderheartbeat en audiocontrole,
maar bevat zonder uitbreiding geen outputstatus. Zelfs met de uitbreiding blijft
een applicatief vastgelopen provider-DabMux onzichtbaar zolang de TCP-stack de
verbinding gezond acht.

## 6. Doelen en niet-doelen

### 6.1 Doelen

- Eén backwards-compatible statsbericht voor encoder-, audio- en outputhealth.
- Een stabiel, gedocumenteerd schema met expliciete semantiek per transport.
- Per EDI TCP-bestemming minimaal connectiestatus, counters, queue en fouten.
- Voor UDP uitsluitend controleerbare lokale feiten rapporteren.
- Geen blokkering van de realtime encodeerlus door monitoring.
- Geen afhankelijkheid van `--edi-verbose` of log parsing.
- Ondersteuning voor meerdere gelijktijdige EDI-bestemmingen.
- Direct uitleesbaar vanuit Liquidsoap 2.4.5 via een UNIX-datagramsocket.
- Een reproduceerbare, identificeerbare binary uit `zwfm-odrbuilds`.
- Een veilige rollout waarbij bestaande monitoring pas na vergelijking wordt
  afgebouwd.

### 6.2 Niet-doelen

- Bewijzen dat de provider-DabMux audio decodeert of uitzendt.
- Een acknowledgeprotocol boven op EDI/UDP ontwerpen.
- Een nieuwe EDI TCP-server-CLI voor AudioEnc toevoegen.
- EDI, AF, PFT of TAG wire formats wijzigen.
- Codec- of audio-inputcode aanpassen.
- Outputstoringen automatisch oplossen buiten de bestaande reconnectlogica.
- In de eerste fase een nieuwe externe metricsdaemon vereisen.

## 7. Voorgesteld statscontract

### 7.1 Backwards compatibility

De bestaande velden blijven ongewijzigd:

- `program`;
- `version`;
- `audiolevels`;
- `driftcompensation`.

Nieuwe consumers gebruiken `schema_version` en `outputs`. Oude consumers die
onbekende JSON-velden negeren blijven functioneren. Het bestaande schema wordt
niet hernoemd of genest.

### 7.2 Voorbeeldpayload

```json
{
  "schema_version": 2,
  "sequence": 18423,
  "program": "ODR-AudioEnc",
  "version": "next-7c14c4f",
  "uptime_seconds": 2211,
  "audiolevels": {
    "left": 410,
    "right": 410
  },
  "driftcompensation": {
    "underruns": 0,
    "overruns": 0
  },
  "outputs": [
    {
      "id": "edi-tcp-0",
      "kind": "edi",
      "transport": "tcp-client",
      "endpoint": {
        "host": "92.70.3.244",
        "port": 9171
      },
      "state": "up",
      "connection_state": "connected",
      "health_scope": "transport",
      "end_to_end_confirmed": false,
      "queue": {
        "frames": 0,
        "capacity": 512
      },
      "counters": {
        "frames_enqueued": 18423,
        "frames_sent": 18423,
        "bytes_sent": 3537216,
        "send_errors": 0,
        "queue_drops": 0,
        "connection_attempts": 1,
        "successful_connections": 1,
        "disconnects": 0
      },
      "seconds_since_last_success": 0.04,
      "seconds_since_state_change": 2210.7,
      "last_error": null
    },
    {
      "id": "edi-udp-1",
      "kind": "edi",
      "transport": "udp",
      "endpoint": {
        "host": "239.10.20.30",
        "port": 9172
      },
      "state": "up",
      "connection_state": null,
      "health_scope": "local-send",
      "end_to_end_confirmed": false,
      "counters": {
        "packets_attempted": 55269,
        "packets_sent": 55269,
        "bytes_sent": 7873261,
        "send_errors": 0
      },
      "seconds_since_last_success": 0.01,
      "seconds_since_state_change": 2210.7,
      "last_error": null
    }
  ]
}
```

### 7.3 Veldsemantiek

#### `state`

Generieke lokale outputhealth:

- `starting`: nog geen geslaagde lokale outputactie;
- `up`: actuele outputactie slaagt en er zijn geen actieve lokale fouten;
- `degraded`: output bestaat, maar reconnects, drops of recente fouten zijn actief;
- `down`: output kan momenteel niet leveren of is permanent gesloten.

`state=up` is uitdrukkelijk geen end-to-endgarantie.

#### `connection_state`

Alleen voor connection-oriented transports:

- `connecting`;
- `connected`;
- `disconnected`;
- `listening` indien de generieke library later een TCP-server rapporteert;
- `null` voor UDP en bestanden.

#### `health_scope`

- `local-write`: bestand/stdout;
- `local-send`: UDP en een lokaal door ZMQ geaccepteerd bericht;
- `transport`: vastgestelde TCP- of IPC-transportsessie;
- `receiver`: alleen toegestaan als een toekomstig protocol een echte
  ontvangerbevestiging levert.

AudioEnc zal in deze implementatie nooit zelf `receiver` claimen.

#### Counters

Alle counters zijn monotone unsigned 64-bitwaarden gedurende één procesrun. Een
procesrestart is herkenbaar aan `sequence`, `uptime_seconds` en eventueel een
toekomstige `instance_id`. Liquidsoap vergelijkt counterdelta's, niet alleen de
absolute waarde.

#### Tijdvelden

Gebruik `std::chrono::steady_clock` en rapporteer een relatieve leeftijd in
seconden. Hiermee worden problemen door NTP-correcties of systeemtijdsprongen
vermeden. De consumer bepaalt zelf de wall-clocktijd waarop hij het bericht kreeg.

### 7.4 Identiteit van outputs

`id` is stabiel gedurende één configuratie en procesrun:

- `edi-tcp-0`;
- `edi-udp-1`;
- `edi-file-2`;
- `zmq-0` of, na monitorondersteuning, `zmq-tcp-0`;
- `file-0`.

De index volgt de CLI-volgorde. Liquidsoap koppelt bij voorkeur op `id` plus het
gestructureerde endpoint, niet op een samengestelde URI-string.

### 7.5 Gegevensveiligheid

- Publiceer geen secret keys of keyfile-inhoud.
- Neem credentials en querystrings niet ongefilterd over uit toekomstige URI's.
- Rapporteer EDI-host en -poort apart.
- Maak voor bestandspaden configureerbaar of het hele pad of alleen een label
  wordt gepubliceerd; de lokale stats-socket is geen reden om secrets te lekken.
- Escape alle JSON-strings correct, inclusief foutmeldingen.

### 7.6 Omvang en cadans

- Handhaaf de huidige cadans voor backwards compatibility.
- Reserveer maximaal 64 KiB per UNIX-datagram; streef bij normale configuraties
  naar minder dan 8 KiB.
- Verhoog de voorbeeldreceiverbuffer van 256 naar 65535 bytes.
- Als een harde limiet nodig blijkt, laat dan optionele details weg en zet
  `outputs_truncated: true`; produceer nooit ongeldige of half afgekapte JSON.

## 8. Intern C++-ontwerp

### 8.1 Nieuw neutraal snapshotmodel

Voeg een dependency-arm model toe, bijvoorbeeld:

- `src/OutputStats.h`;
- eventueel `src/OutputStats.cpp` voor JSON-escaping en serialisatiehelpers.

Conceptueel:

```cpp
enum class OutputState { Starting, Up, Degraded, Down };
enum class ConnectionState { NotApplicable, Connecting, Connected, Disconnected, Listening };
enum class HealthScope { LocalWrite, LocalSend, Transport, Receiver };

struct OutputStats {
    std::string id;
    std::string kind;
    std::string transport;
    OutputState state;
    ConnectionState connection_state;
    HealthScope health_scope;
    bool end_to_end_confirmed = false;
    // endpoint, queue, counters, ages en last_error
};
```

`Output::Base` krijgt:

```cpp
virtual std::vector<OutputStats> get_stats() const = 0;
```

Een vector is nodig omdat één `Output::EDI` meerdere bestemmingen en daarnaast
een EDI-bestand kan bevatten, en één `Output::ZMQ` meerdere endpoints kan hebben.

### 8.2 Snapshot in plaats van callbacks

De stats-thread hoeft geen wijzigingen gepusht te krijgen. De hoofdloop vraagt
op het bestaande stats-moment een read-only snapshot op:

```text
AudioEnc::run()
  -> collect_output_stats()
  -> StatsPublisher::send_stats(output_stats)
```

Voordelen:

- geen monitoringcallback op realtime verzendpaden;
- geen lifetimeproblemen tussen outputs en publisher;
- StatsPublisher blijft eigenaar van het wire schema;
- tests kunnen snapshots zonder actieve UNIX-socket verifiëren.

### 8.3 Thread-safetyregels

- Counters die vanuit senderthreads worden bijgewerkt zijn `std::atomic<uint64_t>`.
- TCP-connectiestatus wordt atomic.
- Foutstrings blijven achter een mutex.
- Queuegrootte wordt via de bestaande thread-safe `size()` gelezen.
- Een snapshot houdt een mutex alleen lang genoeg vast om waarden te kopiëren.
- Tijdens een snapshot vinden geen DNS-, socket- of filesystemoperaties plaats.
- Houd geen outputmutex vast tijdens JSON-serialisatie of `sendto()`.
- Gebruik `memory_order_relaxed` voor onafhankelijke statistiekcounters; status die
  bij een foutstring hoort wordt onder dezelfde mutex gesnapshot.

### 8.4 Geen generieke `connected`-boolean

Een algemene boolean zou UDP en asynchrone outputs verkeerd voorstellen. Gebruik
altijd `connection_state` met `null`/`NotApplicable` voor niet-connection-oriented
outputs en combineer dit met `health_scope`.

## 9. Implementatie per output

### 9.1 EDI TCP-client — fase 1, verplicht

Wijzig `Socket::TCPSendClient`:

1. Maak `m_is_connected` atomic.
2. Splits de huidige reconnectcounter in eenduidige counters:
   - `connection_attempts`;
   - `successful_connections`;
   - `disconnects`;
   - eventueel afgeleid `reconnections = max(successful_connections - 1, 0)`.
3. Registreer `frames_enqueued` en bytes enqueued.
4. Gebruik `ThreadsafeQueue::push_overflow(..., MAX_QUEUE_SIZE)` om een overflow en
   de resulterende queuegrootte atomisch te bepalen.
5. Verhoog `queue_drops` wanneer een oud frame is verwijderd.
6. Registreer alleen na een volledig geslaagde socket-send `frames_sent` en
   `bytes_sent`.
7. Bewaar de concrete sendfout vóór de socket wordt vervangen.
8. Bewaar relatieve tijdstippen voor laatste succes en statuswijziging.
9. Bied een `get_stats() const` aan die geen state reset.
10. Houd verbose logging als aanvullende operatorinformatie, maar bouw monitoring
    niet op `has_seen_new_errors`.

Let op: de huidige queue kan tijdens een storing ongeveer twaalf seconden aan EDI
opslaan, afhankelijk van de framecadans. Dit plan verandert het bestaande
backlogbeleid niet. Het maakt drops en backlog alleen zichtbaar. Een apart besluit
is nodig als na reconnect uitsluitend de nieuwste data verstuurd moet worden.

### 9.2 EDI UDP — fase 1, verplicht

Wijzig `udp_sender_t`:

1. Tel attempted packets/bytes vóór de send.
2. Tel sent packets/bytes uitsluitend wanneer resolve en `sendto()` lokaal slagen.
3. Leg lokale fouten en tijd sinds laatste succes vast.
4. Rapporteer altijd `connection_state=null`.
5. Gebruik `health_scope=local-send`.
6. Zet `end_to_end_confirmed=false` zonder uitzonderingen.

Behoud in de eerste patch het bestaande exceptiongedrag. Als UDP-fouten per
destination geïsoleerd moeten worden in plaats van de senderthread te beëindigen,
maak dat een afzonderlijke commit met eigen tests en changelog, omdat dit runtime-
en exitgedrag verandert.

### 9.3 EDI-bestand — fase 1, verplicht

Voeg in `Output::EDI` per EDI-bestandsoutput toe:

- open/closed/failed state;
- frames en bytes geschreven;
- schrijffouten;
- laatste fout en tijd sinds laatste succesvolle write.

Op `fwrite()`-fout wordt de status `down`, ook als de huidige code het proces laat
doorlopen. Beslis in een afzonderlijke wijziging of `write_frame()` daarna false
moet retourneren en exitcode 4 moet activeren.

### 9.4 Raw file/stdout — fase 2

Voeg aan `Output::File` toe:

- outputlabel (`file` of `stdout`);
- frames/bytes geschreven;
- schrijffouten;
- laatste fout en laatste succes;
- `health_scope=local-write`.

Gebruik bij `fwrite()`-falen `errno` direct, voordat andere librarycalls hem kunnen
wijzigen.

### 9.5 ZeroMQ — fase 2 en 3

Fase 2, lokale sendtelemetrie:

1. Bewaar de geconfigureerde endpoints.
2. Controleer de optionele returnwaarde van non-blocking `send()`.
3. Tel accepted frames/bytes, `EAGAIN`/HWM-drops en exceptions.
4. Rapporteer voorlopig één geaggregeerde ZMQ-output, omdat één PUB-socket alle
   endpoints bedient.
5. Gebruik zonder monitor hoogstens `health_scope=local-send`.

Fase 3, optionele transportevents:

1. Gebruik `zmq::monitor_t` in een aparte lifecycle-veilige monitorthread.
2. Verwerk minimaal `CONNECTED`, `CONNECT_DELAYED`, `CONNECT_RETRIED`,
   `DISCONNECTED`, `CLOSED` en `MONITOR_STOPPED`.
3. Koppel events aan de opgeslagen endpoint-URI.
4. Publiceer per endpoint een snapshot met `health_scope=transport` waar het
   protocol dat werkelijk ondersteunt.
5. Noem een ZMQ-peer niet `receiver_confirmed`: een transportsessie bewijst niet
   dat ODR-DabMux het bericht consumeert.

Monitorondersteuning is geen blokkade voor de EDI TCP-oplevering en hoort daarom
niet in dezelfde eerste pull request.

### 9.6 EDI TCP-server in gedeelde code — niet activeren

Maak de al bestaande `get_tcp_server_stats()` indien praktisch passend in het
generieke snapshotmodel, maar voeg geen AudioEnc CLI-optie toe. Test minimaal dat
de refactor bestaande gebruikers van de gedeelde transportcode niet breekt.

## 10. File-by-file wijzigingsplan in ODR-AudioEnc

### `src/OutputStats.h` (nieuw)

- Neutrale enums en snapshots.
- Geen afhankelijkheid van ZMQ of EDI-klassen.
- Duidelijke comments over lokale versus end-to-endsemantiek.

### `src/OutputStats.cpp` (optioneel nieuw)

- Enum-naar-stringconversies.
- JSON-stringescaping indien dit niet bij `StatsPublisher` blijft.
- Geen nieuwe grote JSON-library alleen voor deze payload, tenzij upstream dat
  expliciet prefereert.

### `src/Outputs.h`

- `get_stats() const` aan `Output::Base` toevoegen.
- Configuratie-identiteit opslaan in File, ZMQ en EDI.
- Thread-safe counters toevoegen waar de output zelf schrijft.

### `src/Outputs.cpp`

- Counters en status voor raw file/stdout.
- Controle van de ZeroMQ non-blocking sendreturn.
- Aggregatie van EDI sender- en EDI-bestandsstats.
- Geen verandering aan EDI wire data.

### `contrib/Socket.h`

- Publieke immutable snapshot voor `TCPSendClient`.
- Atomic status en counters.
- Eenduidige namen voor attempts, connections en disconnects.

### `contrib/Socket.cpp`

- Deterministische queue-overflowmeting.
- Concrete sendfouten bewaren.
- Statusovergangen en succesmomenten registreren.
- Snapshot implementeren zonder counters te resetten.

### `contrib/edioutput/Transport.h`

- Virtuele snapshotfunctie op interne senderinterface.
- Snapshotimplementaties declareren voor UDP, TCP-client en bestaande dispatcher.
- Endpointidentiteit behouden.

### `contrib/edioutput/Transport.cpp`

- Verzendcounters bijwerken op het punt waar het transport werkelijk wordt
  aangeroepen.
- Socketstats naar het neutrale model mappen.
- Huidige verbose reconnectlogs behouden, maar corrigeren naar eenduidige
  counternamen.

### `src/StatsPublish.h`, `src/StatsPublish.cpp`

- `send_stats(const std::vector<OutputStats>&)`.
- Bestaande top-level velden behouden.
- `schema_version`, `sequence`, `uptime_seconds` en `outputs` toevoegen.
- Correcte JSON-escaping.
- Client-socketpad in destructor verwijderen.
- Payloadlengte controleren en nooit gedeeltelijke JSON versturen.

### `src/odr-audioenc.cpp`

- Outputsnapshots verzamelen op het bestaande stats-moment.
- Geen extra stats-thread starten.
- Stats blijven versturen wanneer één netwerkbestemming disconnected is.
- CLI-help uitbreiden met de nieuwe outputtelemetrie.

### `example_stats_receiver.py`

- Buffer verhogen naar 65535.
- Schema version tonen.
- Onbekende velden blijven accepteren.
- Socket cleanup ook bij normale beëindiging uitvoeren.

### `Makefile.am`

- Nieuwe bronbestanden opnemen.
- Unit-testtargets toevoegen via `check_PROGRAMS` en `TESTS`.
- `git describe --always --dirty` of een expliciet geïnjecteerde buildversie
  ondersteunen, zodat branchbuilds nooit een lege versie produceren.

### `README.md`, manpage en changelog

- Volledig schema en transportsemantiek documenteren.
- Expliciet vermelden dat UDP geen receiverstatus biedt.
- Statsvoorbeeld actualiseren.
- Nieuwe JSON-velden als additive/backwards-compatible markeren.

## 11. Gefaseerde implementatiestrategie

### Fase 0 — reproduceerbare basis

1. Maak een werkbranch vanaf exact `7c14c4f65b1a670f2397237343c988317e0d2bce`.
2. Registreer deze upstream SHA in de ontwikkel- en testdocumentatie.
3. Kies vóór publicatie tussen:
   - een tijdelijke `oszuidwest`-forkbranch; of
   - een upstream featurebranch/pull request.
4. Laat `zwfm-odrbuilds` tijdens ontwikkeling een expliciete repo plus commit-SHA
   accepteren, niet alleen een zwevende branchnaam.
5. Zorg dat `odr-audioenc --version` en het statsveld `version` de SHA bevatten.

Acceptatie: dezelfde configuratie produceert aantoonbaar dezelfde source revision
op AMD64 en ARM64.

### Fase 1 — EDI-telemetrie upstream

1. Voeg snapshotmodel en JSON schema v2 toe.
2. Implementeer EDI TCP-clienttelemetrie.
3. Implementeer EDI UDP lokale sendtelemetrie.
4. Implementeer EDI-bestandsstatus.
5. Voeg tests en documentatie toe.
6. Houd de bestaande top-level statsvelden identiek.

Acceptatie: een multi-destinationtest laat onafhankelijk zien dat één TCP-doel
connected is en een ander reconnect, terwijl stats en audio voor de encoder blijven
doorlopen.

### Fase 2 — overige AudioEnc-outputs

1. Raw file/stdout counters en fouten.
2. ZeroMQ non-blocking sendresultaat correct verwerken.
3. Geaggregeerde ZMQ lokale sendtelemetrie publiceren.
4. Bestand- en ZMQ-tests toevoegen.

Acceptatie: `/dev/full` en een geforceerde ZMQ-HWM-situatie worden in stats
zichtbaar en volgen de gedocumenteerde exitsemantiek.

### Fase 3 — optionele ZeroMQ-monitor

Implementeer alleen als ZMQ in productie vergelijkbare operationele eisen krijgt.
Houd dit los van de EDI-pull request om review en risico beheersbaar te houden.

### Fase 4 — `zwfm-odrbuilds`

1. Voeg een expliciete source-SHA/ref toe aan `build.env` en workflow.
2. Laat checkout van een branch gevolgd worden door verificatie van de gewenste
   SHA, of checkout de SHA direct.
3. Voeg de source revision als OCI-label en release metadata toe.
4. Bouw minimal/full op de bestaande OS/architectuurmatrix.
5. Draai unit- en integratietests vóór het publiceren van artifacts.
6. Gebruik een onveranderlijke ontwikkeltag, bijvoorbeeld
   `next-7c14c4f-outputstats1`, naast een eventuele bewegende testalias.
7. Publiceer pas een nieuwe `next`-image nadat de Docker-integratietests slagen.

### Fase 5 — Liquidsoap-integratie

1. Maak en bind vóór AudioEnc-start een UNIX-datagramsocket, bijvoorbeeld
   `/tmp/liquidsoap/odr-audioenc-stats.sock`.
2. Voeg aan het commando toe:

   ```text
   --stats=/tmp/liquidsoap/odr-audioenc-stats.sock
   ```

3. Gebruik in Liquidsoap 2.4.5:
   - `socket.unix(domain=socket.domain.unix, type=socket.type.dgram)`;
   - `socket.address.unix(path)`;
   - `bind` en blocking `read` in een `thread.run`/lage-prioriteitstaak;
   - typed `let json.parse` voor parsing.
4. Bewaar minimaal:
   - ontvangsttijd laatste stats;
   - laatste sequence/uptime;
   - audiolevels en driftcounterdelta's;
   - snapshot per geconfigureerde output;
   - tijd van laatste state transition.
5. Registreer `dab.status` op de bestaande Liquidsoap-serversocket.
6. Log uitsluitend state transitions, niet ieder statsdatagram.
7. Laat een parsefout de receivethread niet permanent stoppen.
8. Laat een herstart van `output.external` dezelfde gebonden receiversocket
   hergebruiken.

De bestaande Compose-mount `/tmp/liquidsoap` is hiervoor geschikt. Omdat AudioEnc
en Liquidsoap in dezelfde container draaien, is geen Docker Desktop bind-mounted
UNIX-datagramsocket nodig.

### Fase 6 — monitoring en rollout

1. Draai nieuwe statsmonitoring en de bestaande packetmonitor minimaal één week
   parallel.
2. Vergelijk per providerpoort:
   - TCP states/reconnects uit AudioEnc;
   - uitgaande packetobservatie;
   - bestaande UptimeRobot-heartbeats.
3. Houd de packetmonitor actief voor het signaal “pakketten verlaten lokaal de
   interface”, omdat AudioEnc alleen socket-/transportstatus ziet.
4. Stuur heartbeats pas na een stabiele overgangsperiode vanuit de nieuwe state
   machine.
5. Verwijder de oude monitor niet zolang niet expliciet is besloten welk lokaal
   assurance-niveau voldoende is.

## 12. Toekomstig Liquidsoap-statusmodel voor native telemetrie

Dit hoofdstuk is uitsluitend een voorstel voor de latere native `--stats`-
integratie en beschrijft niet het huidige no-forkcontract. De nu geïmplementeerde
TCP ACK-monitor gebruikt ook `unmonitored` en standaardgrenzen van 5 seconden
voor `degraded` en 15 seconden voor `down`; de actuele operationele contracttekst
staat in de README.

### 12.1 Globale DAB-status

Voorgestelde waarden voor `dab.status`:

- `disabled`: DAB-configuratie ontbreekt;
- `starting`: AudioEnc is gestart, maar nog geen geldige stats ontvangen;
- `ok`: stats zijn actueel en alle verplichte TCP-bestemmingen zijn connected;
- `degraded`: encoder leeft, maar minstens één bestemming reconnect, heeft drops
  of een recente lokale fout;
- `down`: stats zijn stale of AudioEnc is niet actief.

UDP-only configuraties mogen hoogstens “lokaal sending” melden; de tekstuele status
moet duidelijk maken dat ontvangst onbekend is.

### 12.2 Beginwaarden voor thresholds

| Controle | Beginwaarde | Reden |
|---|---:|---|
| Stats stale | 2 seconden | Ruim zestien gemiste DAB+-statsberichten |
| Startup grace | 10 seconden | Processtart, codecinit en eerste connectie |
| TCP disconnected waarschuwing | 3 seconden | Vermijdt alarm op één tijdelijke reconnectpoging |
| Queue drops | Direct transition naar degraded | Betekent daadwerkelijk verloren oude EDI-frames |
| Herstel naar ok | 60 seconden stabiel | Voorkomt flapping |
| Audiolevel/silence | Bestaande silenceconfiguratie hergebruiken | Geen concurrerende stiltestate machine maken |

Deze waarden worden pas definitief na meting in staging.

### 12.3 Meerdere bestemmingen

- Beoordeel iedere `id` afzonderlijk.
- Eén down bestemming maakt de globale status `degraded`, niet `down`, zolang een
  andere verplichte bestemming gezond is en AudioEnc leeft.
- Alle verplichte bestemmingen down maakt de globale status `down` of
  `degraded-all-destinations` afhankelijk van het gekozen externe contract.
- UptimeRobot-heartbeats blijven per bestemming gescheiden.
- Een bestemming die bewust optioneel is vereist later expliciete configuratie;
  leid optionaliteit niet af uit de transportsoort.

## 13. Testplan

### 13.1 Unit tests upstream

Voeg kleine C++17-tests zonder zwaar testframework toe, tenzij upstream een
framework prefereert.

Minimale tests:

1. JSON-escaping van quotes, backslashes, control characters en foutteksten.
2. Schema v2 bevat alle oude top-level velden.
3. Enumwaarden serialiseren naar exact gedocumenteerde strings.
4. TCP initial state is `connecting`.
5. Eerste connectie telt als attempt en successful connection, niet als reconnect.
6. Disconnect plus herstel verhoogt disconnects en reconnections correct.
7. Queue-overflow verhoogt exact één drop per verwijderd frame.
8. Snapshot reset geen counters.
9. Gelijktijdige snapshots en counterupdates zijn racevrij.
10. UDP heeft nooit een niet-null connection state.
11. File write success en failure leveren correcte counters/states.
12. Een statsbericht met meerdere outputs blijft geldige JSON.

### 13.2 Sanitizers

- Draai AddressSanitizer/UndefinedBehaviorSanitizer op unit tests.
- Draai ThreadSanitizer op TCP state/queue tests waar het platform dat ondersteunt.
- Controleer specifiek snapshots tijdens connect/disconnect en destructor/shutdown.

### 13.3 Docker-integratietests

Gebruik uitsluitend de `oszuidwest`-containers/binaries in de uiteindelijke keten.
ODR-DabMux fungeert als lokale testbestemming.

| Test | Verwachte AudioEnc-telemetrie | Verwachte beperking |
|---|---|---|
| TCP-bestemming normaal | connected, queue rond nul, sent stijgt | Geen bewijs van audio-output na DabMux |
| Verkeerde DNS-naam | disconnected, attempts en last_error stijgen | Stats blijven actueel |
| Connection refused | disconnected met concrete fout | Reconnect per circa één seconde |
| DabMux stop | disconnect zichtbaar zodra socket faalt | Detectietijd hangt van TCP af |
| DabMux restart | nieuwe successful connection, queue loopt leeg | Backlog kan oude frames bevatten |
| DabMux pause 60 s | mogelijk connected en geen fout | Bekende, expliciet gedocumenteerde blinde vlek |
| Twee TCP-doelen, één down | onafhankelijke states | Encoder blijft voor gezonde output werken |
| Queue >512 | queue_drops stijgt | Verlies is lokaal aantoonbaar |
| UDP normaal | local send counters stijgen | Receiverstatus onbekend |
| UDP ontvanger weg | kan nog steeds local send melden | Correct gedrag voor connectionless UDP |
| Ongeldige UDP-route/resolve | send_errors en last_error | Geen receiverclaim |
| EDI file naar `/dev/full` | file down, write error | Exitgedrag volgens apart besluit |
| ZMQ zonder subscriber | alleen lokale/monitorsemantiek | Geen consumerbevestiging |
| Statsreceiver weg/terug | encoder blijft draaien; stats herstelt | Geen outputimpact |
| AudioEnc kill | stats stale binnen twee seconden | Liquidsoap `output.external` herstart |

### 13.4 Liquidsoap-tests

1. Configuratie zonder DAB blijft `disabled` en maakt geen socket/thread.
2. Geldige payload wordt geparsed en per output opgeslagen.
3. Onbekende toekomstige velden breken parsing niet.
4. Malformed JSON logt rate-limited en de thread blijft leven.
5. Stale timer gaat naar `down`.
6. Nieuwe instance na `output.external` restart reset relevante delta-baselines.
7. Eén van twee bestemmingen down geeft `degraded`.
8. `dab.status` is beschikbaar via de bestaande serversocket.
9. Liquidsoap-start en configcheck slagen voor alle stationsbestanden.
10. DAB-storing stopt Icecast, HLS of DME niet.

## 14. Acceptatiecriteria

De eerste productiegeschikte oplevering is gereed wanneer:

- de binary aantoonbaar vanaf een vastgelegde `next`-SHA is gebouwd;
- `--version` en stats een niet-lege revision geven;
- het oude statscontract intact is;
- iedere geconfigureerde EDI TCP-client afzonderlijk zichtbaar is;
- connect, disconnect, reconnect, queuevulling en drops correct gemeten worden;
- UDP nergens als connected of receiver-confirmed wordt aangeduid;
- stats non-blocking blijven en uitval van de receiver AudioEnc niet beïnvloedt;
- de multi-destination Docker-test slaagt op AMD64 en ARM64;
- ThreadSanitizer geen races in de nieuwe statuspaden vindt;
- Liquidsoap `dab.status` transitions zonder logspam rapporteert;
- een defecte DAB-output andere Liquidsoap-outputs niet stopt;
- de bekende DabMux-pauze/blinde vlek zichtbaar in documentatie en runbook staat;
- bestaande packetmonitoring gedurende de afgesproken parallelperiode blijft
  functioneren.

## 15. Risico's en mitigaties

| Risico | Effect | Mitigatie |
|---|---|---|
| TCP connected wordt geïnterpreteerd als end-to-end | Valse zekerheid | `health_scope`, `end_to_end_confirmed=false` en expliciete UI-tekst |
| Data race door snapshots uit senderthread | Crash of inconsistente stats | Atomics, korte mutexsnapshots en ThreadSanitizer |
| Statsdatagram wordt te groot | Truncatie/parsefout | 64 KiB receiver, payloadlimiet en truncation flag |
| Handmatige JSON met foutstrings | Ongeldige JSON | Centrale escaping plus unit tests |
| Floating `next` verandert ongemerkt | Niet-reproduceerbare release | Commit-SHA pin en OCI revision label |
| ZMQ send lijkt succesvol zonder peer | Onjuiste health | Eerst local-send scope, later monitor events |
| TCP backlog verstuurt oude audio na herstel | Ontvanger krijgt vertraagde frames | Drops/backlog meten; beleid afzonderlijk besluiten |
| Te veel overgangslogs | Operationele ruis | Alleen transitions en rate limiting |
| Upstream accepteert generiek model niet | Langdurige fork | Kleine gefaseerde PR's, EDI eerst, fork tijdelijk pinnen |
| Gedeelde `contrib` wijkt af van mmbtools-common | Moeilijke upstreammerge | Wijzigingen klein houden en mogelijke common-origin upstream bespreken |

## 16. Aanbevolen commit- en pull-requestindeling

Houd gedragswijzigingen los van pure telemetrie. Een werkbare reeks is:

1. `test: add output stats test harness`
2. `feat: add versioned output stats schema`
3. `feat: expose EDI TCP client telemetry`
4. `feat: expose EDI UDP send telemetry`
5. `feat: expose EDI file telemetry`
6. `fix: clean up stats publisher socket path`
7. `docs: document output telemetry semantics`
8. `feat: expose file and ZeroMQ send telemetry`
9. optioneel: `feat: monitor ZeroMQ endpoint events`

Een eventuele wijziging van UDP-exceptiongedrag, TCP-backlogbeleid of EDI-file
exitgedrag krijgt een aparte `fix:`-commit en eigen review.

## 17. Concrete repositoryvolgorde

### Repository 1: ODR-AudioEnc of tijdelijke fork

- Implementeer en test het schema en de counters.
- Baseer alles op de vastgelegde `next`-commit.
- Dien bij voorkeur gefaseerde upstream pull requests in.

### Repository 2: `zwfm-odrbuilds`

- Voeg source pinning en revisionmetadata toe.
- Bouw de minimale binary die `zwfm-liquidsoap` gebruikt.
- Publiceer een onveranderlijke testtag en voer Docker-failuretests uit.

### Repository 3: `zwfm-liquidsoap`

- Pin tijdelijk de geteste AudioEnc artifact/tag.
- Voeg stats socket, parser, state machine en `dab.status` toe.
- Documenteer nieuwe settings en monitoringsemantiek.
- Vergelijk met de bestaande packetmonitor voor rollout.

Deze volgorde voorkomt dat Liquidsoap afhankelijk wordt van een schema waarvoor nog
geen reproduceerbare binary bestaat.

## 18. Open ontwerpbesluiten vóór implementatie

De volgende keuzes moeten vóór code review expliciet worden vastgelegd:

1. **Fork of upstream-first:** tijdelijke `oszuidwest`-fork voor snelheid, of wachten
   op upstreammerge?
2. **EDI file failure:** alleen `down` rapporteren of na tien fouten exitcode 4
   behouden/activeren?
3. **TCP backlog:** bestaande 512-frame drop-oldestqueue behouden of op reconnect
   stale frames weggooien?
4. **ZeroMQ-scope:** alleen lokale sendtelemetrie in de eerste release, of direct
   monitor events?
5. **Bestandspaden:** volledig pad in lokale stats of een niet-gevoelig label?
6. **UptimeRobot-eigenaarschap:** Liquidsoap zelf of een dunne monitorconsumer?
7. **Oude packetmonitor:** permanent aanvullend signaal of na een parallelperiode
   beperken tot alleen de gevallen die AudioEnc niet kan zien?

Geen van deze keuzes blokkeert het ontwerpen en testen van EDI TCP snapshots. Wel
beïnvloeden ze runtimegedrag en moeten ze daarom niet impliciet in een telemetry-PR
terechtkomen.

## 19. Aanbevolen eerste uitvoerbare slice

De kleinste slice met directe productiewaarde is:

1. source-SHA pinnen;
2. schema v2 plus outputmodel;
3. uitsluitend EDI TCP-client snapshot met:
   - connection state;
   - attempts/successful connections/disconnects;
   - queue frames/capacity/drops;
   - frames/bytes sent;
   - last error en ages;
4. unit tests en één multi-destination Docker-test;
5. nieuwe minimal AudioEnc testimage;
6. Liquidsoap statsreader en `dab.status`;
7. parallel draaien naast de packetmonitor.

UDP, file en ZMQ zijn al in het schema voorzien, maar hoeven de eerste operationele
validatie van de twee huidige TCP-providerbestemmingen niet te vertragen.

## 20. Eindbeeld

Na uitvoering heeft Liquidsoap drie onafhankelijke lokale signalen:

1. **encoderheartbeat en audio:** actuele `--stats`, levels en drift;
2. **outputtransport:** per EDI TCP-bestemming connectie, queue, drops en fouten;
3. **uitgaand verkeer:** de bestaande pakketobservatie zolang die gewenst blijft.

Wat bewust ontbreekt is een vierde signaal: bevestiging vanuit de provider-DabMux.
Zonder toegang tot diens stats of een apart acknowledgepad kan geen wijziging in
AudioEnc dit betrouwbaar leveren. Het ontwerp maakt die grens zichtbaar in plaats
van haar te verhullen achter een te brede `connected=true`.

## 21. Primaire bronverwijzingen

Alle ODR-AudioEnc-links hieronder zijn vastgezet op de onderzochte commit:

- [`src/odr-audioenc.cpp`](https://github.com/Opendigitalradio/ODR-AudioEnc/blob/7c14c4f65b1a670f2397237343c988317e0d2bce/src/odr-audioenc.cpp)
- [`src/Outputs.h`](https://github.com/Opendigitalradio/ODR-AudioEnc/blob/7c14c4f65b1a670f2397237343c988317e0d2bce/src/Outputs.h)
- [`src/Outputs.cpp`](https://github.com/Opendigitalradio/ODR-AudioEnc/blob/7c14c4f65b1a670f2397237343c988317e0d2bce/src/Outputs.cpp)
- [`src/StatsPublish.h`](https://github.com/Opendigitalradio/ODR-AudioEnc/blob/7c14c4f65b1a670f2397237343c988317e0d2bce/src/StatsPublish.h)
- [`src/StatsPublish.cpp`](https://github.com/Opendigitalradio/ODR-AudioEnc/blob/7c14c4f65b1a670f2397237343c988317e0d2bce/src/StatsPublish.cpp)
- [`contrib/edioutput/EDIConfig.h`](https://github.com/Opendigitalradio/ODR-AudioEnc/blob/7c14c4f65b1a670f2397237343c988317e0d2bce/contrib/edioutput/EDIConfig.h)
- [`contrib/edioutput/Transport.h`](https://github.com/Opendigitalradio/ODR-AudioEnc/blob/7c14c4f65b1a670f2397237343c988317e0d2bce/contrib/edioutput/Transport.h)
- [`contrib/edioutput/Transport.cpp`](https://github.com/Opendigitalradio/ODR-AudioEnc/blob/7c14c4f65b1a670f2397237343c988317e0d2bce/contrib/edioutput/Transport.cpp)
- [`contrib/Socket.h`](https://github.com/Opendigitalradio/ODR-AudioEnc/blob/7c14c4f65b1a670f2397237343c988317e0d2bce/contrib/Socket.h)
- [`contrib/Socket.cpp`](https://github.com/Opendigitalradio/ODR-AudioEnc/blob/7c14c4f65b1a670f2397237343c988317e0d2bce/contrib/Socket.cpp)
- [`contrib/ThreadsafeQueue.h`](https://github.com/Opendigitalradio/ODR-AudioEnc/blob/7c14c4f65b1a670f2397237343c988317e0d2bce/contrib/ThreadsafeQueue.h)
- [`example_stats_receiver.py`](https://github.com/Opendigitalradio/ODR-AudioEnc/blob/7c14c4f65b1a670f2397237343c988317e0d2bce/example_stats_receiver.py)
- [`Makefile.am`](https://github.com/Opendigitalradio/ODR-AudioEnc/blob/7c14c4f65b1a670f2397237343c988317e0d2bce/Makefile.am)
- [`configure.ac`](https://github.com/Opendigitalradio/ODR-AudioEnc/blob/7c14c4f65b1a670f2397237343c988317e0d2bce/configure.ac)

Aanvullende ketenbronnen:

- [`zwfm-odrbuilds/build.env`](https://github.com/oszuidwest/zwfm-odrbuilds/blob/main/build.env)
- [`zwfm-odrbuilds` AudioEnc-buildworkflow](https://github.com/oszuidwest/zwfm-odrbuilds/blob/main/.github/workflows/odr-build.yml)
- [Liquidsoap 2.4.0-referentie](https://www.liquidsoap.info/doc-2.4.0/reference.html)
