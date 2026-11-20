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

// Valid numeric positions clamp at the bounds. Invalid packets are tested below.
room.onMessage(a.server, a.player, { t: "pos", x: 999, z: -999, ry: 0, moving: true });
if (a.player.x !== 7.4 || a.player.z !== -5.4 || a.player.ry !== 0) throw new Error("pos not clamped");
if (a.player.moving !== true) throw new Error("valid moving flag not applied");
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

// tick measures real elapsed time: a lagging interval does not slow repairs,
// and a stalled room jumps by at most 1s per tick
{
  const d = joinDirect("dario");
  room.phase = "play";
  room.initCar();
  room.onMessage(d.server, d.player, { t: "repair", part: "engine", on: true });
  const approx = (x, y) => Math.abs(x - y) < 1e-9;
  let t = Date.now();
  room.tick(t); // first tick after initCar: one nominal TICK_MS step
  const p0 = room.parts.engine.progress;
  if (!approx(p0, (TICK_MS / 1000) / 12)) throw new Error("first tick not nominal: " + p0);
  t += 500; room.tick(t); // interval lagged to 2x: progress still follows the clock
  const p1 = room.parts.engine.progress;
  if (!approx(p1 - p0, 0.5 / 12)) throw new Error("lag not compensated: " + (p1 - p0));
  t += 10000; room.tick(t); // a 10s stall is capped at 1s of progress
  const p2 = room.parts.engine.progress;
  if (!approx(p2 - p1, 1 / 12)) throw new Error("stall not capped at 1s: " + (p2 - p1));
  console.log("real-dt tick OK");
}

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
// idle kick: a socket silent for more than IDLE_KICK_MS is closed and removed
{
  const e = joinDirect("elena");
  e.player.lastSeen = Date.now() - 11 * 60 * 1000; // 11 min of silence
  room.tick(Date.now());
  if (room.players.has(e.server)) throw new Error("idle player not kicked");
  console.log("idle kick OK");
}

// claim conflict: the room reclaimed earlier is still claimed, so a second
// claim must be refused with 409
{
  if (!room.claimed) throw new Error("test setup: room should still be claimed here");
  const again = await room.fetch(new Request("https://do/claim?code=DUP1", { method: "POST" }));
  if (again.status !== 409) throw new Error("second claim not refused: " + again.status);
  if (room.code !== "NEW2") throw new Error("conflicting claim overwrote the room code");
  console.log("claim conflict OK");
}

// room codes: 4 chars, alphabet only (no ambiguous I/L/O/0/1), and the
// rejection sampling actually draws from the whole alphabet over many codes
{
  const seen = new Set();
  for (let i = 0; i < 4000; i++) {
    const c = makeCode();
    if (!/^[A-Z2-9]{4}$/.test(c)) throw new Error("bad code shape: " + c);
    if (/[ILO01]/.test(c)) throw new Error("ambiguous char in code: " + c);
    for (const ch of c) seen.add(ch);
  }
  if (seen.size !== 31) throw new Error("alphabet not fully used: " + seen.size + "/31");
  console.log("room code shape OK");
}

// car pick: only the host picks, only in the lobby, only a real car index
room.phase = "lobby";
room.carIndex = 0;
const host = [...room.players.entries()].find(([, p]) => p.id === room.hostId);
if (!host) throw new Error("no host for pick tests");
const late = joinDirect("laura");
room.onMessage(late.server, late.player, { t: "pick", car: 2 });
if (room.carIndex !== 0) throw new Error("non-host picked a car!");
room.onMessage(host[0], host[1], { t: "pick", car: 9 });
if (room.carIndex !== 0) throw new Error("out-of-range pick accepted!");
room.onMessage(host[0], host[1], { t: "pick", car: "junk" });
if (room.carIndex !== 0) throw new Error("non-numeric pick accepted!");
room.onMessage(host[0], host[1], { t: "pick", car: 2 });
if (room.carIndex !== 2) throw new Error("host pick ignored");
console.log("car pick guards OK");

// the worker answers /health without touching any room
{
  const r = await mod.default.fetch(new Request("https://api/health"), {});
  if (r.status !== 200) throw new Error("health status " + r.status);
  const body = await r.json();
  if (body.ok !== true || body.service !== "car-flopper-api") throw new Error("bad health body");
  if (r.headers.get("access-control-allow-origin") !== "*") throw new Error("health missing CORS");
}
console.log("HEALTH ROUTE TESTS PASS");

// finishing a part credits every fixer holding it
{
  const r = new GarageRoom(null, null);
  const a = new FakeWS(), b = new FakeWS();
  const pa = { id: "a", repairing: null, partsFixed: 0 };
  const pb = { id: "b", repairing: null, partsFixed: 0 };
  r.players.set(a, pa); r.players.set(b, pb);
  r.phase = "play"; r.initCar();
  r.onMessage(a, pa, { t: "repair", part: "engine", on: true });
  r.onMessage(b, pb, { t: "repair", part: "engine", on: true });
  for (let t = 1000; r.parts.engine.progress < 1 && t < 200000; t += 250) r.tick(t);
  if (r.parts.engine.progress < 1) throw new Error("engine never finished with two fixers");
  if (pa.partsFixed !== 1 || pb.partsFixed !== 1) throw new Error("fixers not credited");
  if (pa.repairing !== null || pb.repairing !== null) throw new Error("repairing not cleared");
  // the snapshot carries the public stat
  const snap = r.roomSnapshot();
  const sa = snap.players.find(p => p.id === "a");
  if (sa.partsFixed !== 1) throw new Error("partsFixed missing from snapshot");
}
console.log("REPAIR CREDIT TESTS PASS");

// lobby status reports totals for the preview UI
{
  const r = new GarageRoom(null, null);
  await r.fetch(new Request("https://do/claim?code=STAT", { method: "POST" }));
  const resp = await r.fetch(new Request("https://do/status"));
  if (resp.status !== 200) throw new Error("status " + resp.status);
  const s = await resp.json();
  if (s.carsTotal !== 3 || s.partsTotal !== 8 || s.carIndex !== 0 || s.phase !== "lobby") throw new Error("bad status body " + JSON.stringify(s));
}
console.log("LOBBY STATUS TESTS PASS");

// snapshots carry a fresh serverTime
{
  const r = new GarageRoom(null, null);
  const before = Date.now();
  const s = r.roomSnapshot();
  if (!Number.isFinite(s.serverTime) || s.serverTime < before || s.serverTime > Date.now()) throw new Error("stale serverTime");
}
console.log("SNAPSHOT TIME TESTS PASS");

console.log("ALL ROOM LOGIC TESTS PASSED");

{for(const bad of [null,undefined,42,'x',[],true])room.onMessage(host[0],host[1],bad);if(room.carIndex!==2)throw Error('malformed message changed state');}

{for(const bad of [1.5,null,'1',true,NaN,Infinity,-1]){room.onMessage(host[0],host[1],{t:'pick',car:bad});if(room.carIndex!==2)throw Error('invalid car pick accepted');}}

{const detached=new FakeWS();room.onMessage(detached,host[1],{t:'pick',car:0});if(room.carIndex!==2)throw Error('detached socket mutated room');}

{room.phase='play';room.initCar();room.onMessage(host[0],host[1],{t:'repair',part:'engine',on:true});room.tick(10000);const progress=room.parts.engine.progress;room.tick(9000);if(room.parts.engine.progress!==progress)throw Error('clock rollback undid repairs');}

{room.phase='lobby';room.onMessage(host[0],host[1],{t:'repair',part:'engine',on:true});if(host[1].repairing!==null)throw Error('lobby repair accepted');room.phase='play';room.onMessage(host[0],host[1],{t:'repair',part:'engine',on:'false'});if(host[1].repairing!==null)throw Error('truthy string repair accepted');}

{room.onMessage(host[0],host[1],{t:'repair',part:'__proto__',on:true});if(host[1].repairing!==null)throw Error('prototype part accepted');}

{const snap=room.roomSnapshot();if(snap.players.some(p=>'lastSeen' in p||'lastPosAt' in p))throw Error('bookkeeping leaked');}

{for(const [ws,pl] of [...room.players])room.onClose(ws,pl);room.phase='finished';room.carIndex=2;room.parts={old:{progress:1}};const response=await room.fetch(new Request('https://do/claim?code=FRESH',{method:'POST'}));if(response.status!==200||room.phase!=='lobby'||room.carIndex!==0||Object.keys(room.parts).length||room.colorPool.length!==4)throw Error('reclaim retained stale game');}

// Optional heartbeat replies go only to the sender and do not change game state.
{
  const r = new GarageRoom(null, null);
  const ws = new FakeWS();
  const peer = new FakeWS();
  const player = {id:"heartbeat", x:2,z:3,ry:1,moving:false,lastSeen:1};
  r.players.set(ws, player);
  r.players.set(peer, {id:"peer"});
  for (const nonce of ["probe", 42, "x".repeat(64)]) {
    r.onMessage(ws,player,{t:"ping",nonce});
    const response=ws.out.at(-1);
    if(response.t!=="pong"||response.nonce!==nonce||!Number.isFinite(response.serverTime))throw Error("bad heartbeat");
  }
  for(const nonce of ["x".repeat(65),{},null,Infinity]){
    r.onMessage(ws,player,{t:"ping",nonce});
    if("nonce" in ws.out.at(-1))throw Error("unsafe heartbeat echo");
  }
  if(peer.out.length||r.phase!=="lobby"||player.lastSeen<=1)throw Error("heartbeat leaked or mutated phase");
  r.players.delete(ws);
  const count=ws.out.length;
  r.onMessage(ws,player,{t:"ping"});
  if(ws.out.length!==count)throw Error("departed player heartbeat");
}
console.log("HEARTBEAT TESTS PASS");


// Malformed movement is ignored as one packet, keeping the last good state.
{
  const r=new GarageRoom(null,null), ws=new FakeWS();
  const p={id:"movement",x:2,z:3,ry:1,moving:false};
  r.players.set(ws,p);
  for(const bad of [null,"4",true,Infinity,NaN,{},undefined]){
    r.onMessage(ws,p,{t:"pos",x:4,z:bad,ry:2,moving:true});
    if(p.x!==2||p.z!==3||p.ry!==1||p.moving)throw Error("partial malformed movement applied");
  }
  r.onMessage(ws,p,{t:"pos",x:999,z:-999,ry:999,moving:"false"});
  if(p.x!==7.4||p.z!==-5.4||p.ry!==7||p.moving)throw Error("movement bounds or boolean guard");
}
console.log("MOVEMENT VALIDATION TESTS PASS");

{
 let touched=false;
 const env={GARAGE_ROOM:{idFromName(){touched=true;throw Error('must not touch room');}}};
 for(const [path,method] of [['/health','POST'],['/rooms/TEST','DELETE'],['/rooms/TEST/ws','POST']]){
  const r=await mod.default.fetch(new Request('https://api'+path,{method}),env);
  if(r.status!==405||!r.headers.get('allow')||touched)throw Error('worker method guard failed');
 }
 const preflight=await mod.default.fetch(new Request('https://api/rooms',{method:'OPTIONS'}),env);
 if(preflight.status!==200||touched)throw Error('preflight touched room');
}

{
 const r=new GarageRoom(null,null);
 for(const [path,method] of [['/claim','GET'],['/status','POST'],['/ws','POST']]){
  const resp=await r.fetch(new Request('https://do'+path,{method}));
  if(resp.status!==405||r.claimed||r.players.size)throw Error('internal method guard failed');
 }
}

{
 const {parsePacket}=mod;
 for(const raw of [null,'{','null','[]','42','true',JSON.stringify({text:'🙂'.repeat(1100)})])
  if(parsePacket(raw)!==null)throw Error('invalid or oversized packet accepted');
 const boundary=JSON.stringify({text:'x'.repeat(4085)});
 if(new TextEncoder().encode(boundary).length!==4096||!parsePacket(boundary))throw Error('exact packet byte boundary');
 if(parsePacket(boundary+' ')!==null)throw Error('oversized ASCII packet accepted');
 if(parsePacket('{"t":"ping"}').t!=='ping')throw Error('valid packet rejected');
}

{
 const {cleanPlayerName}=mod;
 if(cleanPlayerName('  fred\n\u202e  ')!=='fred')throw Error('control characters in name');
 if(cleanPlayerName('🙂'.repeat(20))!=='🙂'.repeat(16))throw Error('emoji split in name');
 if(cleanPlayerName('e\u0301')!=='é')throw Error('name NFC normalization');
 for(const value of [null,{},'  ','\n'])if(cleanPlayerName(value)!=='mechanic')throw Error('name fallback');
}
