// Live 2-client co-op test against the deployed car-flopper-api.
const BASE = "https://car-flopper.federicotaranu.site";
const WS = "wss://car-flopper.federicotaranu.site";
const fail = (m) => { console.error("FAIL: " + m); process.exit(1); };
const ok = (m) => console.log("ok: " + m);

// 1. create room
const code = (await (await fetch(BASE + "/rooms", { method: "POST" })).json()).code;
if (!/^[A-Z2-9]{4}$/.test(code)) fail("bad code " + code);
ok("room created " + code);

function client(name) {
  const ws = new WebSocket(`${WS}/rooms/${code}/ws?name=${name}`);
  const c = { ws, name, id: null, last: null, events: [], msgs: [] };
  ws.onmessage = (ev) => {
    const m = JSON.parse(ev.data);
    c.msgs.push(m);
    if (m.t === "welcome") c.id = m.id;
    if (m.t === "state") c.last = m.room;
    if (m.t === "event") c.events.push(m);
  };
  return c;
}
const until = (fn, ms, what) => new Promise((res, rej) => {
  const t0 = Date.now();
  const iv = setInterval(() => {
    if (fn()) { clearInterval(iv); res(); }
    else if (Date.now() - t0 > ms) { clearInterval(iv); rej(new Error("timeout: " + what)); }
  }, 50);
});
const send = (c, o) => c.ws.send(JSON.stringify(o));

const A = client("fred");
await until(() => A.id && A.last, 8000, "A welcome");
const B = client("simone");
await until(() => B.id, 8000, "B welcome");
await until(() => A.last && A.last.players.length === 2, 8000, "both visible");
if (A.last.hostId !== A.id) fail("host should be first joiner");
ok("2 players joined, host=first joiner, ids distinct: " + (A.id !== B.id));

// 2. privacy: bogus room ws must fail
const bad = new WebSocket(`${WS}/rooms/ZZZ9/ws?name=x`);
const badRes = await new Promise((r) => { bad.onopen = () => r("open"); bad.onclose = (e) => r("closed"); bad.onerror = () => r("error"); });
if (badRes === "open") fail("bogus room ws opened");
ok("bogus room ws rejected (" + badRes + ")");

// 3. non-host cannot start
send(B, { t: "start" });
await new Promise((r) => setTimeout(r, 800));
if (A.last.phase !== "lobby") fail("non-host started game");
ok("non-host start ignored");

// 4. host starts
send(A, { t: "start" });
await until(() => B.last && B.last.phase === "play", 8000, "phase play");
if (Object.keys(B.last.parts).length !== 8) fail("parts != 8");
ok("host start -> play, 8 parts");

// 5. co-op speed: both repair engine (12s solo -> ~7.06s with 2)
send(A, { t: "repair", part: "engine", on: true });
send(B, { t: "repair", part: "engine", on: true });
const t0 = Date.now();
await until(() => A.events.some((e) => e.kind === "partFixed" && e.part === "engine"), 12000, "engine fixed");
const dt = (Date.now() - t0) / 1000;
if (dt > 9.5) fail(`co-op not faster: ${dt}s (solo=12s)`);
if (dt < 5.5) fail(`suspiciously fast: ${dt}s`);
ok(`co-op engine fixed in ${dt.toFixed(1)}s (solo would be 12s)`);

// 6. positions sync: B moves, A sees it
send(B, { t: "pos", x: 2.5, z: -1.5, ry: 1.0, moving: true });
await until(() => A.last && Math.abs(A.last.players.find(p => p.id === B.id).x - 2.5) < 0.01, 5000, "pos sync");
ok("position sync A<-B");

// 7. host migration: A disconnects, B becomes host
A.ws.close();
await until(() => B.last && B.last.players.length === 1 && B.last.hostId === B.id, 8000, "host migration");
ok("disconnect -> host migrated to B");

// 8. finish car solo: repair remaining parts one at a time
const order = ["wheelFL","wheelFR","wheelRL","wheelRR","door","windshield","exhaust"];
for (const p of order) {
  send(B, { t: "repair", part: p, on: true });
  await until(() => B.events.some((e) => e.kind === "partFixed" && e.part === p), 25000, p);
  send(B, { t: "repair", part: p, on: false });
}
await until(() => B.last && B.last.phase === "complete", 8000, "car complete");
ok("car 1 complete");

// 9. progression: next car unlocks, parts reset
send(B, { t: "next" });
await until(() => B.last && B.last.carIndex === 1 && B.last.phase === "play", 8000, "next car");
const prog = Object.values(B.last.parts).every((p) => p.progress === 0);
if (!prog) fail("parts not reset on next car");
ok("next car started, parts reset");

B.ws.close();
console.log("ALL LIVE TESTS PASSED");
process.exit(0);
