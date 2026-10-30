# Car Flopper

Ripara auto distrutte **insieme ai tuoi amici**, in 3D, direttamente su iPhone.

Un garage, un'auto incidentata, fino a 4 meccanici collegati con un codice stanza: cammini nel garage, ti avvicini al pezzo rotto e lo ripari tenendo premuto. In due sullo stesso pezzo si va piu' veloci. Sistema tutto e sblocchi l'auto successiva.

## Scarica l'ultima versione

[![Download IPA](https://img.shields.io/badge/SCARICA-ultima%20IPA-orange?style=for-the-badge)](https://github.com/federicotaranudev/car-flopper/releases/download/v2026.10.29.1/CarFlopper.ipa)

Oppure scegli una versione specifica dalla tab [Releases](https://github.com/federicotaranudev/car-flopper/releases).

## Installazione (iPhone, gratis)

Serve un Apple ID gratuito, niente account developer a pagamento.

1. Installa **AltStore** o **Sideloadly** sul tuo computer.
2. Scarica il file `.ipa` dal link qui sopra.
3. Installa l'IPA sul tuo iPhone con AltStore/Sideloadly.
4. Con l'Apple ID gratuito l'app va rinnovata ogni 7 giorni (AltStore lo fa in automatico sullo stesso Wi-Fi).

## Come si gioca

- **Crea garage**: genera un codice da 4 lettere e mandalo agli amici.
- **Entra**: inserisci il codice e scegli il tuo nickname. Niente account, niente email.
- **Ripara**: joystick a sinistra per camminare, trascina a destra per guardarti intorno. Quando sei vicino a un pezzo rotto compare il pulsante: tieni premuto per ripararlo.
- **Co-op**: piu' persone sullo stesso pezzo = riparazione piu' veloce.
- **Sblocca**: sistema l'auto per passare alla successiva. 3 auto: Rusty Coupe, Sideways 500, Garage Legend.

## Com'e' fatto

- **App**: Swift nativo + SceneKit (grafica low-poly costruita in codice, zero asset a pagamento).
- **Multiplayer**: Cloudflare Worker + Durable Objects (websocket) sul piano gratuito. Il server e' in `server/`.
- **Build**: GitHub Actions compila l'IPA non firmato a ogni push; ogni versione resta pubblicata nelle Releases.

## Stato

In sviluppo attivo. La versione nelle Releases e' una **prerelease non verificata**: compila e il server multiplayer e' online e testato, ma l'app non e' ancora stata provata su un iPhone vero. Diventera' una release stabile dopo il test su dispositivo.

Funziona: lobby con codici stanza, 3D con camminata, riparazioni co-op in tempo reale, sblocco auto. Bug e idee: apri una issue.

---

_Car Flopper non e' affiliato con nessuna casa automobilistica. Le auto sono modelli low-poly originali disegnati in codice._
---

## English

### What is Car Flopper?
Repair wrecked cars **together with your friends**, in 3D, directly on iPhone.

One garage, one wrecked car, up to 4 mechanics connected by a 4-letter room code: walk around the garage, get close to a broken part, and hold to repair it. Two people on the same part repair faster. Fix everything to unlock the next car.

### Download
[![Download IPA](https://img.shields.io/badge/DOWNLOAD-latest%20IPA-orange?style=for-the-badge)](https://github.com/federicotaranudev/car-flopper/releases)

### Install (iPhone, free)
Requires a free Apple ID — no paid developer account.

1. Install **AltStore** or **Sideloadly** on your computer.
2. Download the `.ipa` from the link above.
3. Install the IPA on your iPhone with AltStore/Sideloadly.
4. With a free Apple ID the app must be re-signed every 7 days (AltStore does this automatically on the same Wi-Fi).

### How to play
- **Create garage**: generates a 4-letter code to send to friends.
- **Join**: enter the code and pick a nickname. No account, no email.
- **Repair**: left joystick to walk, drag on the right to look around. When close to a broken part a button appears: hold to repair.
- **Co-op**: more people on the same part = faster repair.
- **Unlock**: fix the car to move to the next. 3 cars: Rusty Coupe, Sideways 500, Garage Legend.

### How it's built
- **App**: native Swift + SceneKit (low-poly graphics built in code, zero paid assets).
- **Multiplayer**: Cloudflare Worker + Durable Objects (WebSocket) on the free tier. Server lives in `server/`.
- **Build**: GitHub Actions compiles an unsigned IPA on every push; every version is published in Releases.

### Status
Active development. The released build is an **unverified prerelease**: it compiles and the multiplayer server is online and tested, but the app has not yet been run on a real iPhone. It becomes a stable release after on-device testing.

Works: room lobbies with codes, 3D walking, real-time co-op repairs, car unlocking. Bugs and ideas: open an issue.

---

_Car Flopper is not affiliated with any automaker. Cars are original low-poly models drawn in code._

