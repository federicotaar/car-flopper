# Architettura multiplayer

Il multiplayer di Car Flopper è interamente dentro `server/` (Cloudflare Worker) e `Sources/CarFlopper/Net.swift` (client iOS). Piano gratuito Cloudflare, nessun account richiesto ai giocatori.

## Server additions (2026-11-19)

- `GET /health`: liveness probe, answers `{ ok: true, service: "car-flopper-api" }` without touching any room.
- Lobby status (`GET /rooms/:code`) now also reports `carIndex`, `carsTotal` and `partsTotal` for preview UIs.
- Players get a `partsFixed` counter in state snapshots: everyone holding a part when it finishes is credited.
- State snapshots include `serverTime` so clients can estimate clock skew without a separate ping.

## Flusso

1. **Crea garage**: il client chiama `POST /rooms`, il Worker genera un codice da 4 lettere (alfabeto senza I/L/O/0/1 per evitare confusione) e riserva la stanza.
2. **Entra**: `GET /rooms/:code/ws` con il nickname come query param. Massimo 4 giocatori; il server rifiuta con `room full` oltre.
3. **Gioca**: ogni client manda la propria posizione (~12 Hz, il server accetta al massimo 25 Hz) e gli eventi di riparazione. Il Durable Object della stanza trasmette uno snapshot completo ogni 500 ms. Un client che non manda nulla per 10 minuti viene espulso (kick per inattivita'), cosi' un socket morto non puo' tenere una stanza occupata per sempre.
4. **Fine**: l'host avanza all'auto successiva; dopo la terza la stanza è `finished`.

### Messaggio `kick`

Solo l'host, solo in lobby: `{ "t": "kick", "id": "<id giocatore>" }` rimuove quel giocatore (riceve prima `error` con `reason: "kicked"`). L'host non può espellere se stesso e durante la partita il messaggio viene ignorato.

### Messaggio `emote`

`{ "t": "emote", "emote": "wave" }` con uno tra `wave`, `thumbs`, `wow`, `laugh`, `help`, `gg`. Il server inoltra a tutti `{ t: "event", kind: "emote", player, emote }`, al massimo uno al secondo per giocatore; testo libero non viene mai inoltrato.

### Messaggio `ready`

In lobby ogni giocatore può mandare `{ "t": "ready", "on": true }`. Lo snapshot riporta `ready` per giocatore e `allReady` per la stanza. Il server non blocca `start`: decide l'host.

### Tempi

Lo snapshot include `elapsedMs` (millisecondi dall'inizio dell'auto in corso, 0 fuori dalla fase `play`) e `carTimes` (millisecondi impiegati per ogni auto finita, per indice).

## Perché un Durable Object per stanza

Lo stato della stanza (giocatori, progresso dei pezzi, fase) vive in un unico oggetto: il server è autoritativo sul progresso, quindi il bonus co-op è identico per tutti e due client non possono completare lo stesso pezzo due volte.

## Test

- `node server/test-room.js` — logica della stanza senza runtime Cloudflare (WebSocket stubbati).
- `node server/test-live.js` — due client reali contro il server in produzione; da eseguire con parsimonia, dopo i deploy.

## Modelli condivisi

`Net.swift` (RoomPlayer, PartState, RoomSnapshot) e `server/worker.js` (PARTS, tempi di riparazione) devono restare allineati: i commenti in testa a entrambi i file lo ricordano.
