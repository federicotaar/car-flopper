# Car Flopper

Ripara auto distrutte **insieme ai tuoi amici**, in 3D, direttamente su iPhone.

Un garage, un'auto incidentata, fino a 4 meccanici collegati con un codice stanza: cammini nel garage, ti avvicini al pezzo rotto e lo ripari tenendo premuto. In due sullo stesso pezzo si va piu' veloci. Sistema tutto e sblocchi l'auto successiva.

## Scarica l'ultima versione

[![Download IPA](https://img.shields.io/badge/SCARICA-ultima%20IPA-orange?style=for-the-badge)](https://github.com/federicotaranudev/car-flopper/releases/latest/download/CarFlopper.ipa)

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
- **Sblocca**: sistema l'auto per passare alla successiva. 3 auto: Rusty Coupe, Drift 350, Supra MK.

## Com'e' fatto

- **App**: Swift nativo + SceneKit (grafica low-poly costruita in codice, zero asset a pagamento).
- **Multiplayer**: Cloudflare Worker + Durable Objects (websocket) sul piano gratuito. Il server e' in `server/`.
- **Build**: GitHub Actions compila l'IPA non firmato a ogni push; ogni versione resta pubblicata nelle Releases.

## Stato

In sviluppo attivo. Prima versione giocabile: lobby con codici, 3D con camminata, riparazioni co-op, sblocco auto. Bug e idee: apri una issue.

---

_Car Flopper non e' affiliato con nessuna casa automobilistica. Le auto sono modelli low-poly originali disegnati in codice._
