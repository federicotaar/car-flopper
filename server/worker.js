// Car Flopper multiplayer server: room codes + realtime sync.
// Worker routes HTTP/WS; one Durable Object per room holds state and relays.
// Free-tier: Workers Free plan includes Durable Objects (since 2025-04-07).

// HTTP surface (CORS open, the iOS app talks to it directly):
//   POST /rooms            -> { code }   allocate a 4-letter room code
//   GET  /rooms/:code      -> room snapshot (lobby state)
//   GET  /rooms/:code/ws   -> WebSocket upgrade, joins the room
//
// WebSocket protocol (JSON both ways):
//   client -> server: "pos" (x/z/ry/moving, capped at 25 Hz), "repair"
//                     (part id while holding), and host-only "start",
//                     "pick" (car index) and "next" (advance/finish)
//   server -> client: "welcome" (your player id), "state" (full room
//                     snapshot every 500 ms), "event" (join/leave/part done/
//                     car unlocked), "error" (room full, bad code, idle kick)
//
// Part ids and solo repair seconds must stay in sync with the iOS client's
// GameContent.swift; the server is authoritative on progress so co-op
// repair speed (COOP_BONUS per extra fixer) is identical for everyone.

const CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"; // no I/L/O/0/1
const MAX_PLAYERS = 4;
export const TICK_MS = 250;
const BROADCAST_EVERY = 2; // every 2 ticks = 500ms
const COOP_BONUS = 0.7;
const MAX_MSG_BYTES = 4096; // fail closed on junk
const IDLE_KICK_MS = 10 * 60 * 1000; // ghost-socket cleanup: no message for 10 min -> kick
const MIN_POS_GAP_MS = 40; // cap incoming pos at 25 Hz (client sends ~12 Hz)

// Part ids + solo repair seconds. Must match the iOS client's GameContent.
const PARTS = [
  { id: "wheelFL", seconds: 7 },
  { id: "wheelFR", seconds: 7 },
  { id: "wheelRL", seconds: 7 },
  { id: "wheelRR", seconds: 7 },
  { id: "engine", seconds: 12 },
  { id: "door", seconds: 9 },
  { id: "windshield", seconds: 9 },
  { id: "exhaust", seconds: 8 },
];
const CAR_COUNT = 3;
export const EMOTES = ["wave", "thumbs", "wow", "laugh", "help", "gg"];
const EMOTE_GAP_MS = 1000; // one emote per second per player

// Count UTF-8 bytes, not UTF-16 code units, before parsing untrusted packets.
export function parsePacket(data) {
  if (typeof data !== 'string' || data.length > MAX_MSG_BYTES || new TextEncoder().encode(data).length > MAX_MSG_BYTES)
    return null;
  try {
    const msg=JSON.parse(data);
    return msg && typeof msg==='object' && !Array.isArray(msg) ? msg : null;
  } catch { return null; }
}

export function cleanPlayerName(value) {
  if(typeof value !== 'string')return 'mechanic';
  const cleaned=value.normalize('NFC').replace(/[\u0000-\u001f\u007f-\u009f\u202a-\u202e\u2066-\u2069]/g,'').trim();
  return Array.from(cleaned).slice(0,16).join('') || 'mechanic';
}

export function makeCode() {
  // rejection sampling: 256 % 31 != 0, so plain "byte % 31" would favor
  // the first few alphabet entries; redraw bytes >= limit instead
  const limit = Math.floor(256 / CODE_ALPHABET.length) * CODE_ALPHABET.length;
  let c = "";
  while (c.length < 4) {
    const bytes = new Uint8Array(4);
    crypto.getRandomValues(bytes);
    for (const b of bytes) if (b < limit && c.length < 4) c += CODE_ALPHABET[b % CODE_ALPHABET.length];
  }
  return c;
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const cors = {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type",
    };
    if (request.method === "OPTIONS") return new Response(null, { headers: cors });

    // Only room allocation mutates over HTTP. Unsupported methods must not
    // reach the Durable Object or silently look like successful probes.
    if (request.method !== 'GET' && !(url.pathname === '/rooms' && request.method === 'POST'))
      return new Response('method not allowed', {status:405,headers:{...cors,Allow:'GET,POST,OPTIONS'}});

    if (url.pathname === "/health") {
      // liveness probe for uptime checks; no Durable Object touched, always cheap
      return Response.json({ ok: true, service: "car-flopper-api" }, { headers: cors });
    }

    if (url.pathname === "/rooms" && request.method === "POST") {
      // retry a few times on the (rare) code collision
      for (let i = 0; i < 5; i++) {
        const code = makeCode();
        const id = env.GARAGE_ROOM.idFromName(code);
        const stub = env.GARAGE_ROOM.get(id);
        const r = await stub.fetch(new Request("https://do/claim?code=" + code, { method: "POST" }));
        if (r.ok) {
          return Response.json({ code }, { headers: cors });
        }
      }
      return Response.json({ error: "could not allocate room" }, { status: 500, headers: cors });
    }

    const m = url.pathname.match(/^\/rooms\/([A-Z2-9]{4})(\/ws)?$/);
    if (m) {
      const code = m[1];
      const id = env.GARAGE_ROOM.idFromName(code);
      const stub = env.GARAGE_ROOM.get(id);
      const doUrl = new URL(m[2] ? "https://do/ws" : "https://do/status");
      doUrl.search = url.search;
      const resp = await stub.fetch(new Request(doUrl.toString(), request));
      if (!m[2]) {
        // status: add cors headers
        const h = new Headers(resp.headers);
        for (const [k, v] of Object.entries(cors)) h.set(k, v);
        return new Response(resp.body, { status: resp.status, headers: h });
      }
      return resp; // websocket upgrade
    }

    return new Response("car-flopper-api", { status: 200, headers: cors });
  },
};

export class GarageRoom {
  constructor(state, env) {
    this.state = state;
    this.env = env;
    this.players = new Map(); // ws -> player {id,name,color,x,z,ry,moving,repairing}
    this.claimed = false;
    this.phase = "lobby"; // lobby | play | complete | finished
    this.carIndex = 0;
    this.hostId = null;
    this.parts = {}; // id -> {progress, fixers}
    this.colorPool = [0, 1, 2, 3];
    this.tickCount = 0;
    this.lastTickAt = 0; // wall clock of the previous tick; 0 = no tick yet
    this.timer = null;
  }

  async fetch(request) {
    const url = new URL(request.url);

    const allowed = url.pathname === '/claim' ? 'POST' : 'GET';
    if (request.method !== allowed)
      return new Response('method not allowed',{status:405,headers:{Allow:allowed}});

    if (url.pathname === "/claim") {
      if (this.claimed) return new Response("taken", { status: 409 });
      this.claimed = true;
      this.phase='lobby';this.carIndex=0;this.hostId=null;this.parts={};
      this.colorPool=[0,1,2,3];this.tickCount=0;this.lastTickAt=0;
      this.code = url.searchParams.get("code") || "";
      return new Response("ok");
    }

    if (url.pathname === "/status") {
      if (!this.claimed) return new Response("not found", { status: 404 });
      if (this.players.size >= MAX_PLAYERS) return new Response("full", { status: 409 });
      return Response.json({ code: true, players: this.players.size, phase: this.phase, carIndex: this.carIndex, carsTotal: CAR_COUNT, partsTotal: PARTS.length, maxPlayers: MAX_PLAYERS, availableSlots: Math.max(0,MAX_PLAYERS-this.players.size) });
    }

    if (url.pathname === "/ws") {
      if (!this.claimed) return new Response("not found", { status: 404 });
      if (this.players.size >= MAX_PLAYERS) return new Response("full", { status: 409 });
      const name = cleanPlayerName(url.searchParams.get("name"));

      const pair = new WebSocketPair();
      const [client, server] = Object.values(pair);
      server.accept();

      const id = crypto.randomUUID().slice(0, 8);
      const color = this.colorPool.length ? this.colorPool.shift() : this.players.size % 4;
      const player = { id, name, color, x: 0, z: 3.5, ry: 3.14, moving: false, repairing: null, partsFixed: 0, lastSeen: Date.now(), lastPosAt: 0 };
      this.players.set(server, player);
      if (!this.hostId) this.hostId = id;

      server.send(JSON.stringify({ t: "welcome", id }));
      this.broadcastState();
      this.ensureTimer();

      server.addEventListener("message", (ev) => {
        if (typeof ev.data !== 'string' || ev.data.length > MAX_MSG_BYTES || new TextEncoder().encode(ev.data).length > MAX_MSG_BYTES) {
          try { server.close(1009, "message too big"); } catch {}
          return;
        }
        const msg=parsePacket(ev.data);
        if(!msg)return;
        player.lastSeen = Date.now();
        if (msg.t === "pos") {
          if (player.lastSeen - player.lastPosAt < MIN_POS_GAP_MS) return; // drop excess
          player.lastPosAt = player.lastSeen;
        }
        this.onMessage(server, player, msg);
      });
      server.addEventListener("close", () => this.onClose(server, player));
      server.addEventListener("error", () => this.onClose(server, player));

      return new Response(null, { status: 101, webSocket: client });
    }

    return new Response("not found", { status: 404 });
  }

  onMessage(ws, player, msg) {
    if(!this.players.has(ws)||!msg||typeof msg!=='object'||Array.isArray(msg))return;
    if (msg.t === "ping") {
      // Optional heartbeat: old clients can keep sending positions unchanged.
      // Bound echoed data and never relay arbitrary payloads to other players.
      player.lastSeen = Date.now();
      const response = { t: "pong", serverTime: player.lastSeen };
      if (typeof msg.nonce === "string" && msg.nonce.length <= 64) response.nonce = msg.nonce;
      else if (typeof msg.nonce === "number" && Number.isFinite(msg.nonce)) response.nonce = msg.nonce;
      try { ws.send(JSON.stringify(response)); } catch { /* close handler cleans up */ }
    } else if (msg.t === "pos") {
      // Ignore malformed packets atomically rather than teleporting to zero.
      if (![msg.x, msg.z, msg.ry].every(v => typeof v === "number" && Number.isFinite(v))) return;
      player.x = clampNum(msg.x, -7.4, 7.4);
      player.z = clampNum(msg.z, -5.4, 5.4);
      player.ry = clampNum(msg.ry, -7, 7);
      player.moving = msg.moving === true;
    } else if (msg.t === "repair") {
      const partId = typeof msg.part === "string" ? msg.part : null;
      player.repairing = this.phase==='play' && msg.on===true && partId && Object.hasOwn(this.parts,partId) && this.parts[partId] && this.parts[partId].progress < 1 ? partId : null;
    } else if (msg.t === "start" && player.id === this.hostId && this.phase === "lobby") {
      this.initCar();
      this.phase = "play";
      this.broadcastState();
    } else if (msg.t === "kick" && player.id === this.hostId && this.phase === "lobby" && typeof msg.id === "string" && msg.id !== player.id) {
      // host-only moderation: drop one player from the lobby, never the host itself
      for (const [sock, pl] of this.players) {
        if (pl.id !== msg.id) continue;
        try { sock.send(JSON.stringify({ t: "error", reason: "kicked" })); } catch { /* already gone */ }
        try { sock.close(4000, "kicked"); } catch { /* close handler cleans up */ }
        this.onClose(sock, pl);
        break;
      }
    } else if (msg.t === "pick" && player.id === this.hostId && this.phase === "lobby") {
      const i=msg.car;
      if (Number.isInteger(i) && i >= 0 && i < CAR_COUNT) { this.carIndex = i; this.broadcastState(); }
    } else if (msg.t === "next" && player.id === this.hostId && this.phase === "complete") {
      if (this.carIndex + 1 < CAR_COUNT) {
        this.carIndex += 1;
        this.initCar();
        this.phase = "play";
      } else {
        this.phase = "finished";
      }
      this.broadcastState();
    }
  }

  onClose(ws, player) {
    if (!this.players.has(ws)) return;
    this.players.delete(ws);
    this.colorPool.push(player.color);
    if (this.hostId === player.id) {
      this.hostId = this.players.size ? this.players.values().next().value.id : null;
    }
    if (this.players.size === 0) {
      if (this.timer) { clearInterval(this.timer); this.timer = null; }
      this.claimed = false; // room dies with last player; code becomes reusable
    } else {
      this.broadcastState();
    }
  }

  initCar() {
    this.parts = {};
    for (const p of PARTS) this.parts[p.id] = { progress: 0, fixers: 0 };
    for (const pl of this.players.values()) pl.repairing = null;
    this.lastTickAt = 0; // a fresh car starts with a clean clock
  }

  ensureTimer() {
    if (this.timer) return;
    this.timer = setInterval(() => this.tick(), TICK_MS);
  }

  tick(now = Date.now()) {
    // ghost-socket cleanup so a dead client cannot pin a room forever
    for (const [ws, pl] of [...this.players]) {
      if (now - pl.lastSeen > IDLE_KICK_MS) {
        try { ws.close(1001, "idle"); } catch {}
        this.onClose(ws, pl);
      }
    }
    if (this.phase === "play") {
      // reset fixer counts, then count from players
      for (const p of Object.values(this.parts)) p.fixers = 0;
      for (const pl of this.players.values()) {
        if (pl.repairing && this.parts[pl.repairing]) this.parts[pl.repairing].fixers += 1;
      }
      // Measure the real elapsed time instead of assuming one tick = TICK_MS:
      // setInterval drifts when the isolate is busy and a fixed dt would slow
      // repairs down. Capped at 1s so a stalled room does not jump ahead.
      const dt = this.lastTickAt ? Math.max(0,Math.min((now - this.lastTickAt) / 1000, 1)) : TICK_MS / 1000;
      let allFixed = true;
      for (const def of PARTS) {
        const st = this.parts[def.id];
        if (!st || st.progress >= 1) continue;
        if (st.fixers > 0) {
          const rate = (1 + COOP_BONUS * (st.fixers - 1)) / def.seconds;
          const before = st.progress;
          st.progress = Math.min(1, st.progress + rate * dt * 1); // progress per second
          if (st.progress >= 1 && before < 1) {
            this.broadcast({ t: "event", kind: "partFixed", part: def.id });
            // credit everyone holding this part when it finished: co-op stats
            for (const pl of this.players.values()) if (pl.repairing === def.id) { pl.repairing = null; pl.partsFixed = (pl.partsFixed || 0) + 1; }
          }
        }
        if (st.progress < 1) allFixed = false;
      }
      if (allFixed && this.phase === "play") {
        this.phase = "complete";
        this.broadcast({ t: "event", kind: "carComplete", car: String(this.carIndex) });
      }
    }
    this.lastTickAt = now;
    this.tickCount += 1;
    if (this.tickCount % BROADCAST_EVERY === 0) this.broadcastState();
  }

  roomSnapshot() {
    return {
      code: this.code || "",
      // lets clients estimate clock skew without a separate ping (same value as pong)
      serverTime: Date.now(),
      phase: this.phase,
      carIndex: this.carIndex,
      hostId: this.hostId || "",
      progress: {
        fixed: PARTS.filter(p=>this.parts[p.id]?.progress>=1).length,
        total: PARTS.length,
        fraction: PARTS.reduce((n,p)=>n+Math.max(0,Math.min(1,this.parts[p.id]?.progress || 0)),0)/PARTS.length,
      },
      // strip server-side bookkeeping (lastSeen/lastPosAt); the iOS decoder only reads the public fields
      players: [...this.players.values()].map(p => ({
        id:p.id,name:p.name,color:p.color,x:p.x,z:p.z,ry:p.ry,
        moving:p.moving,repairing:p.repairing,partsFixed:p.partsFixed || 0,
      })),
      parts: Object.fromEntries(Object.entries(this.parts).map(([id,p])=>[id,{progress:p.progress,fixers:p.fixers}])),
    };
  }

  broadcastState() { this.broadcast({ t: "state", room: this.roomSnapshot() }); }

  broadcast(obj) {
    const text = JSON.stringify(obj);
    for (const ws of this.players.keys()) {
      try { ws.send(text); } catch { /* dropped on close handler */ }
    }
  }
}

function clampNum(v, lo, hi) {
  const n = Number(v);
  if (!Number.isFinite(n)) return 0;
  return Math.max(lo, Math.min(hi, n));
}
