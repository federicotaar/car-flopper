# Come funziona il gioco

Car Flopper è un co-op da garage: fino a 4 giocatori in una stanza riparano la stessa auto. Questa pagina descrive le regole implementate nel codice (`Sources/CarFlopper/GameContent.swift` e `GameViewModel.swift`).

## Le auto

Tre auto da sbloccare in sequenza, ognuna con colore, tagline e set di pezzi propri:

1. **Rusty Coupe**
2. **Sideways 500**
3. **Garage Legend**

L'auto successiva si sblocca quando tutti i pezzi di quella corrente arrivano a progresso 1. Dopo la terza auto la stanza passa alla fase `finished`.

## I pezzi da riparare

Ogni pezzo ha un hotspot sulla carrozzeria, un tempo di riparazione in solitaria e uno strumento richiesto:

| Pezzo | Secondi (da solo) |
| --- | --- |
| 4 ruote | 7 ciascuna |
| Motore | 12 |
| Porta | 9 |
| Parabrezza | 9 |
| Scarico | 8 |

Gli strumenti si raccolgono alle stazioni nel garage: senza quello giusto la riparazione non parte.

## Il co-op

- Il server è l'unico che fa avanzare il progresso: niente disallineamenti tra giocatori.
- Ogni giocatore in più sullo stesso pezzo accelera la riparazione (bonus co-op del 70% per fixer aggiuntivo, definito in `server/worker.js`).
- Chi resta fermo 10 minuti senza mandare messaggi viene rimosso dalla stanza.

## I comandi

- Joystick sinistro: cammina.
- Trascina a destra: guarda intorno.
- Vicino a un pezzo rotto compare il pulsante: tieni premuto per riparare.
