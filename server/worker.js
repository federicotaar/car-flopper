// Car Flopper multiplayer server: room codes + realtime sync.
// Worker routes HTTP/WS; one Durable Object per room holds state and relays.
// Free-tier: Workers Free plan includes Durable Objects (since 2025-04-07).

const CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"; // no I/L/O/0/1
const MAX_PLAYERS = 4;
const TICK_MS = 250;
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

function makeCode() {
  let c = "";
  const bytes = new Uint8Array(4);
  crypto.getRandomValues(bytes);
  for (const b of bytes) c += CODE_ALPHABET[b % CODE_ALPHABET.length];
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
    this.timer = null;
  }

  async fetch(request) {
    const url = new URL(request.url);

    if (url.pathname === "/claim") {
      if (this.claimed) return new Response("taken", { status: 409 });
      this.claimed = true;
      this.code = url.searchParams.get("code") || "";
      return new Response("ok");
    }

    if (url.pathname === "/status") {
      if (!this.claimed) return new Response("not found", { status: 404 });
      if (this.players.size >= MAX_PLAYERS) return new Response("full", { status: 409 });
      return Response.json({ code: true, players: this.players.size, phase: this.phase });
    }

    if (url.pathname === "/ws") {
      if (!this.claimed) return new Response("not found", { status: 404 });
      if (this.players.size >= MAX_PLAYERS) return new Response("full", { status: 409 });
      const name = (url.searchParams.get("name") || "mechanic").slice(0, 16);

      const pair = new WebSocketPair();
      const [client, server] = Object.values(pair);
      server.accept();

      const id = crypto.randomUUID().slice(0, 8);
      const color = this.colorPool.length ? this.colorPool.shift() : this.players.size % 4;
      const player = { id, name, color, x: 0, z: 3.5, ry: 3.14, moving: false, repairing: null, lastSeen: Date.now(), lastPosAt: 0 };
      this.players.set(server, player);
      if (!this.hostId) this.hostId = id;

      server.send(JSON.stringify({ t: "welcome", id }));
      this.broadcastState();
      this.ensureTimer();

      server.addEventListener("message", (ev) => {
        if (typeof ev.data !== "string" || ev.data.length > MAX_MSG_BYTES) {
          try { server.close(1009, "message too big"); } catch {}
          return;
        }
        let msg;
        try { msg = JSON.parse(ev.data); } catch { return; }
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
    if (msg.t === "pos") {
      player.x = clampNum(msg.x, -7.4, 7.4);
      player.z = clampNum(msg.z, -5.4, 5.4);
      player.ry = clampNum(msg.ry, -7, 7);
      player.moving = !!msg.moving;
    } else if (msg.t === "repair") {
      const partId = typeof msg.part === "string" ? msg.part : null;
      player.repairing = msg.on && partId && this.parts[partId] && this.parts[partId].progress < 1 ? partId : null;
    } else if (msg.t === "start" && player.id === this.hostId && this.phase === "lobby") {
      this.initCar(this.carIndex);
      this.phase = "play";
      this.broadcastState();
    } else if (msg.t === "pick" && player.id === this.hostId && this.phase === "lobby") {
      const i = Math.trunc(Number(msg.car));
      if (i >= 0 && i < CAR_COUNT) { this.carIndex = i; this.broadcastState(); }
    } else if (msg.t === "next" && player.id === this.hostId && this.phase === "complete") {
      if (this.carIndex + 1 < CAR_COUNT) {
        this.carIndex += 1;
        this.initCar(this.carIndex);
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
  }

  ensureTimer() {
    if (this.timer) return;
    this.timer = setInterval(() => this.tick(), TICK_MS);
  }

  tick() {
    // ghost-socket cleanup so a dead client cannot pin a room forever
    const now = Date.now();
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
      const dt = TICK_MS / 1000;
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
            for (const pl of this.players.values()) if (pl.repairing === def.id) pl.repairing = null;
          }
        }
        if (st.progress < 1) allFixed = false;
      }
      if (allFixed && this.phase === "play") {
        this.phase = "complete";
        this.broadcast({ t: "event", kind: "carComplete", car: String(this.carIndex) });
      }
    }
    this.tickCount += 1;
    if (this.tickCount % BROADCAST_EVERY === 0) this.broadcastState();
  }

  roomSnapshot() {
    return {
      code: this.code || "",
      phase: this.phase,
      carIndex: this.carIndex,
      hostId: this.hostId || "",
      players: [...this.players.values()],
      parts: this.parts,
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
