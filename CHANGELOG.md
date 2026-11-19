# Changelog

Le tappe principali di Car Flopper, dalle più recenti. Le versioni scaricabili sono nella tab Releases.

## 2026-11-19

- Server multiplayer: route `GET /health` per il controllo di vitalità.
- Server multiplayer: lo stato della lobby riporta i totali di auto e pezzi.
- Server multiplayer: i giocatori ricevono credito (`partsFixed`) per i pezzi che aiutano a finire, visibile negli snapshot di stato.
- Server multiplayer: gli snapshot di stato includono `serverTime` per stimare lo sfasamento dell'orologio del client.
- Documentate le novità del server in `docs/MULTIPLAYER.md`.

## 2026-11-15

- Docs: GAMEPLAY.md ora dice il vero sui set di pezzi - le tre auto condividono lo stesso set (cambiano colore, tagline e carrozzeria), verificato contro GameContent.swift.

- Test della stanza: kick dei client inattivi oltre 10 minuti e rifiuto (409) di una seconda prenotazione dello stesso codice.

## 2026-11-14

- Server: codici stanza generati senza bias di modulo (rejection sampling).
- Snapshot della stanza senza i campi interni del server (`lastSeen`, `lastPosAt`).
- Commento del protocollo WebSocket allineato ai messaggi reali (`start`/`pick`/`next`).
- Test della stanza: clamp delle posizioni, migrazione dell'host, rilascio della stanza, guardie sulle riparazioni, alfabeto dei codici.
- README: link aggiornati dopo la rinomina dell'account GitHub in `federicotaar`.
- Documentato il protocollo multiplayer in `server/worker.js` e come eseguire i test del server.

## v2026.10.29.1 (2026-10-30)

- Mano in prima persona: mesh anatomica CC0 posabile (relax/presa) con rig riadattato e strumenti riposizionati.
- Porta con strumentazione valida su iOS (controlli di attacco compatibili, niente API solo macOS).
- Co-op: bonus di riparazione quando più giocatori lavorano sullo stesso pezzo; kick dei giocatori inattivi.
- Server multiplayer su Cloudflare Workers + Durable Objects con codici stanza da 4 lettere.

## 2026-10-29

- Prima versione giocabile: garage 3D in SceneKit, camminata con joystick, riparazioni a pressione, 3 auto sbloccabili (Rusty Coupe, Sideways 500, Garage Legend).
