# Contributing to Car Flopper

Bug reports and pull requests are welcome. The game is in active development
and the released IPA is an unverified prerelease (see the README), so reports
from real devices are especially useful.

## Reporting a bug

Open an issue with the bug report template: what you did in the garage, what
you expected, what happened, and whether you were solo or in a multiplayer
room (include the room code if the state looked wrong).

## Before opening a pull request

- Run the server tests and add coverage for room-logic changes:

  ```sh
  node server/test-room.js
  ```

  [TESTING.md](TESTING.md) also covers the live two-client test, which hits
  the deployed server - run it sparingly, after deploys.
- Multiplayer rules live in `server/worker.js`: keep repairs fair (progress
  is shared, the host alone advances the car) and never trust the client.
- Asset changes follow [ASSETS.md](ASSETS.md); gameplay tuning is documented
  in [docs/GAMEPLAY.md](docs/GAMEPLAY.md).
