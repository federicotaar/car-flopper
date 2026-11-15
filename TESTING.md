# Test

## Logica della stanza (senza rete)

```sh
node server/test-room.js
```

Guida la classe `GarageRoom` del Durable Object con stub di WebSocketPair e
timer: join/leave, avanzamento riparazioni, bonus co-op, avanzamento auto
solo per l'host e forma dello snapshot; in più clamp delle posizioni ai
limiti del garage, migrazione dell'host quando esce, rilascio e riutilizzo
del codice stanza all'ultima uscita, guardie sulle riparazioni (pezzo
sconosciuto ignorato, fixer ricalcolati a ogni tick), guardie sulla scelta
dell’auto (solo l’host, solo in lobby, solo un indice valido) e alfabeto
senza ambiguità dei codici stanza. Non serve rete né wrangler (Node 22+).
Verificato il 2026-11-14: tutti i controlli passano.

## Co-op live contro il deploy

```sh
node server/test-live.js
```

Crea una stanza vera su `car-flopper.federicotaranu.site`, collega due
client WebSocket e ripara un pezzo insieme verificando che entrambi vedano
lo stesso stato. **Colpisce la produzione**: eseguirlo con parsimonia,
dopo i deploy.
