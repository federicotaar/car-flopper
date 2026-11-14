# Test

## Logica della stanza (senza rete)

```sh
node server/test-room.js
```

Guida la classe `GarageRoom` del Durable Object con stub di WebSocketPair e
timer: join/leave, avanzamento riparazioni, bonus co-op, avanzamento auto
solo per l'host e forma dello snapshot. Non serve rete né wrangler
(Node 22+). Verificato il 2026-11-14: tutti i controlli passano.

## Co-op live contro il deploy

```sh
node server/test-live.js
```

Crea una stanza vera su `car-flopper.federicotaranu.site`, collega due
client WebSocket e ripara un pezzo insieme verificando che entrambi vedano
lo stesso stato. **Colpisce la produzione**: eseguirlo con parsimonia,
dopo i deploy.
