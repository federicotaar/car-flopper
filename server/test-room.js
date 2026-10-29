// Logic-level test of GarageRoom without Cloudflare runtime: stub WebSocketPair + timers.

const mod = await import("./worker.js");
const { GarageRoom } = mod;

class FakeWS {
  constructor() { this.out = []; this.listeners = {}; this.readyState = 1; }
  accept() {}
  addEventListener(t, f) { this.listeners[t] = f; }
  send(s) { this.out.push(JSON.parse(s)); }
  emit(t, ev) { this.listeners[t] && this.listeners[t](ev || {}); }
  close() { this.emit("close"); }
}
class FakeWSPair { 0; 1; constructor() { this[0] = new FakeWS(); this[1] = new FakeWS(); } }
globalThis.WebSocketPair = FakeWSPair;

const room = new GarageRoom(null, null);
const code = "TEST";
await room.fetch(new Request(`https://do/claim?code=${code}`, { method: "POST" }));

async function join(name) {
  const req = new Request(`https://do/ws?name=${name}`);
  const resp = await room.fetch(req);
  if (resp.status !== 101) throw new Error("join failed " + resp.status);
  const server = resp.webSocket ?? null;
  return server;
}

// Response with webSocket: our stub returns `new Response(null,{status:101,webSocket:client})`.
// Node's Response doesn't keep unknown props, so call fetch-level pieces manually instead.
// Simpler: replicate handler internals.
function joinDirect(name) {
  const server = new FakeWS();
  const id = [...Array(8)].map(() => Math.random().toString(16)[2]).join("");
  const color = room.colorPool.length ? room.colorPool.shift() : 0;
  const player = { id, name, color, x: 0, z: 3.5, ry: 3.14, moving: false, repairing: null };
  room.players.set(server, player);
  if (!room.hostId) room.hostId = id;
  return { server, player };
}

const a = joinDirect("fred");
const b = joinDirect("simone");
if (room.hostId !== a.player.id) throw new Error("host wrong");

room.onMessage(a.server, a.player, { t: "start" });
if (room.phase !== "play") throw new Error("did not start");
if (Object.keys(room.parts).length !== 8) throw new Error("parts not initialized");

// both repair engine (12s solo). With 2 players rate = 1.7/12 per sec.
room.onMessage(a.server, a.player, { t: "repair", part: "engine", on: true });
room.onMessage(b.server, b.player, { t: "repair", part: "engine", on: true });
for (let i = 0; i < 40; i++) room.tick(); // 10s
const eng = room.parts.engine;
console.log("engine after 10s co-op:", eng.progress.toFixed(3), "fixers:", eng.fixers);
if (eng.progress < 0.9) throw new Error("co-op repair too slow: " + eng.progress);

// everyone repairs everything to completion
for (const def of Object.keys(room.parts)) {
  room.onMessage(a.server, a.player, { t: "repair", part: def, on: true });
  room.onMessage(b.server, b.player, { t: "repair", part: def, on: true });
  for (let i = 0; i < 60 && room.parts[def].progress < 1; i++) room.tick();
}
room.tick(); room.tick();
if (room.phase !== "complete") throw new Error("not complete, phase=" + room.phase);
console.log("car complete OK");

// host advances
room.onMessage(a.server, a.player, { t: "next" });
if (room.phase !== "play" || room.carIndex !== 1) throw new Error("next car failed");
console.log("next car OK, index", room.carIndex);

// non-host cannot advance
room.phase = "complete";
room.onMessage(b.server, b.player, { t: "next" });
if (room.carIndex !== 1) throw new Error("non-host advanced car!");
console.log("host-only advance OK");

// last car -> finished
room.carIndex = 2; room.phase = "complete";
room.onMessage(a.server, a.player, { t: "next" });
if (room.phase !== "finished") throw new Error("finished state wrong: " + room.phase);
console.log("finished OK");

// snapshot shape matches iOS decoder
room.code = code;
const snap = room.roomSnapshot();
for (const k of ["code","phase","carIndex","hostId","players","parts"]) if (!(k in snap)) throw new Error("snapshot missing " + k);
console.log("snapshot shape OK:", JSON.stringify({code: snap.code, players: snap.players.length}));
console.log("ALL ROOM LOGIC TESTS PASSED");
