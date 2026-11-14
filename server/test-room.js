// Logic-level test of GarageRoom without the Cloudflare runtime: it stubs
// WebSocketPair and timers, then drives the Durable Object class directly.
// Covers join/leave, repair progress, co-op bonus, host-only car advance and
// snapshot shape. No network, no wrangler needed: `node server/test-room.js`
// (Node 22+ detects the module syntax automatically).

const mod = await import("./worker.js");
const { GarageRoom, makeCode, TICK_MS } = mod;

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
// synthetic clock: tick(now) gets explicit timestamps so the test does not
// depend on how fast the loop happens to run
let simNow = Date.now();
const step = () => { simNow += TICK_MS; room.tick(simNow); };
for (let i = 0; i < 40; i++) step(); // 10s
const eng = room.parts.engine;
console.log("engine after 10s co-op:", eng.progress.toFixed(3), "fixers:", eng.fixers);
if (eng.progress < 0.9) throw new Error("co-op repair too slow: " + eng.progress);

// everyone repairs everything to completion
for (const def of Object.keys(room.parts)) {
  room.onMessage(a.server, a.player, { t: "repair", part: def, on: true });
  room.onMessage(b.server, b.player, { t: "repair", part: def, on: true });
  for (let i = 0; i < 60 && room.parts[def].progress < 1; i++) step();
}
step(); step();
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

// pos clamping: out-of-range coords land on the bounds, junk becomes 0
room.onMessage(a.server, a.player, { t: "pos", x: 999, z: -999, ry: "junk", moving: 1 });
if (a.player.x !== 7.4 || a.player.z !== -5.4 || a.player.ry !== 0) throw new Error("pos not clamped");
if (a.player.moving !== true) throw new Error("moving not coerced");
console.log("pos clamping OK");

// host migration: when the host leaves, the oldest remaining player becomes host
const savedHost = room.hostId;
if (savedHost !== a.player.id) throw new Error("expected a to be host before migration test");
room.onClose(a.server, a.player);
if (room.hostId !== b.player.id) throw new Error("host did not migrate to remaining player");
console.log("host migration OK");

// room dies with the last player: code is released and can be claimed again
room.onClose(b.server, b.player);
if (room.claimed !== false) throw new Error("room still claimed after last player left");
if (room.players.size !== 0) throw new Error("players not empty after last leave");
const reclaim = await room.fetch(new Request("https://do/claim?code=NEW2", { method: "POST" }));
if (reclaim.status !== 200) throw new Error("released room could not be reclaimed");
console.log("room release + reclaim OK");

// repair guards: unknown parts are ignored, "off" clears, fixer counts refresh every tick
const c = joinDirect("cleo");
room.phase = "play";
room.initCar();
room.onMessage(c.server, c.player, { t: "repair", part: "flux-capacitor", on: true });
if (c.player.repairing !== null) throw new Error("unknown part accepted for repair");
room.onMessage(c.server, c.player, { t: "repair", part: "engine", on: true });
if (c.player.repairing !== "engine") throw new Error("repair did not stick");
room.tick();
if (room.parts.engine.fixers !== 1) throw new Error("fixer count wrong: " + room.parts.engine.fixers);
room.onMessage(c.server, c.player, { t: "repair", part: "engine", on: false });
room.tick();
if (room.parts.engine.fixers !== 0) throw new Error("fixer count did not refresh after off");
console.log("repair guards OK");

// room codes: 4 chars, only from the unambiguous alphabet, and varied
{
  const seen = new Set();
  for (let i = 0; i < 200; i++) {
    const code = makeCode();
    if (!/^[A-HJ-NP-Z2-9]{4}$/.test(code)) throw new Error("bad room code: " + code);
    seen.add(code);
  }
  if (seen.size < 150) throw new Error("room codes suspiciously repetitive: " + seen.size + "/200");
  console.log("makeCode charset OK");
}
console.log("ALL ROOM LOGIC TESTS PASSED");
