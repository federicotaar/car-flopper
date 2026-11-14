# Architettura multiplayer

Il multiplayer di Car Flopper è interamente dentro `server/` (Cloudflare Worker) e `Sources/CarFlopper/Net.swift` (client iOS). Piano gratuito Cloudflare, nessun account richiesto ai giocatori.

## Flusso

1. **Crea garage**: il client chiama `POST /rooms`, il Worker genera un codice da 4 lettere (alfabeto senza I/L/O/0/1 per evitare confusione) e riserva la stanza.
2. **Entra**: `GET /rooms/:code/ws` con il nickname come query param. Massimo 4 giocatori; il server rifiuta con `room full` oltre.
3. **Gioca**: ogni client manda la propria posizione (~12 Hz, il server accetta al massimo 25 Hz) e gli eventi di riparazione. Il Durable Object della stanza trasmette uno snapshot completo ogni 500 ms.
4. **Fine**: l'host avanza all'auto successiva; dopo la terza la stanza è `finished`.

## Perché un Durable Object per stanza

Lo stato della stanza (giocatori, progresso dei pezzi, fase) vive in un unico oggetto: il server è autoritativo sul progresso, quindi il bonus co-op è identico per tutti e due client non possono completare lo stesso pezzo due volte.

## Test

- `node server/test-room.js` — logica della stanza senza runtime Cloudflare (WebSocket stubbati).
- `node server/test-live.js` — due client reali contro il server in produzione; da eseguire con parsimonia, dopo i deploy.

## Modelli condivisi

`Net.swift` (RoomPlayer, PartState, RoomSnapshot) e `server/worker.js` (PARTS, tempi di riparazione) devono restare allineati: i commenti in testa a entrambi i file lo ricordano.
