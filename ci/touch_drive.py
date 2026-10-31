# Simulator-only touch driver: real idb HID events into the running sim app.
import re, subprocess, time, math, sys
def sh(c): return subprocess.run(c, shell=True, capture_output=True, text=True)
U = subprocess.check_output("xcrun simctl list devices -j | jq -r '.devices[][] | select(.name==\"cf-touch\") | .udid'", shell=True, text=True).strip()
W = 402
JC = (153, 241)   # landscape joystick centre (fallback, AX dump is empty)
RC = (739, 301)   # landscape repair button centre (fallback)
STATIONS = {'wrench': (5.6, -3.5), 'screwdriver': (-3.5, -4.2), 'welder': (4.6, -4.3), 'diagnostics': (6.8, 2.8)}
RES = {}
LOGF = open('out/driver.log', 'w')
def P(*a):
    s = ' '.join(str(x) for x in a); print(s); LOGF.write(s + '\n'); LOGF.flush()
def f(x, y): return (W - y, x)   # mapping M1 proven in run 104
def snap(n): sh(f"xcrun simctl io cf-touch screenshot out/{n}.png")
def rawlog(last):
    return sh(f"xcrun simctl spawn cf-touch log show --last {last} --predicate 'processImagePath CONTAINS \"CarFlopper\"' --style compact").stdout
RX = re.compile(r'pos=\(([-\d.]+),([-\d.]+)\) yaw=([-\d.]+) .*?repairing=(\d) part=(.*?) tool=(\S+) range=(\d)(?: need=(\S+) aim=\(([-\d.]+),([-\d.]+)\) prog=([-\d.]+))?')
def parse(l):
    m = RX.search(l)
    if not m: return None
    g = m.groups()
    return dict(x=float(g[0]), z=float(g[1]), yaw=float(g[2]), rep=int(g[3]), part=g[4], tool=g[5], rng=int(g[6]),
                need=g[7], ax=float(g[8]) if g[8] else None, az=float(g[9]) if g[9] else None, prog=float(g[10]) if g[10] else None)
def st(last='4s'):
    ls = [l for l in rawlog(last).splitlines() if 'CFTOUCH] state' in l]
    for l in reversed(ls):
        p = parse(l)
        if p: return p
    return None
def swipe(ux, uy, dur=2.0, L=40):
    x0, y0 = f(*JC); x1, y1 = f(JC[0] + ux * L, JC[1] + uy * L)
    sh(f"idb ui swipe {x0:.0f} {y0:.0f} {x1:.0f} {y1:.0f} --duration {dur} --udid {U}")
s0 = st()
P('START', s0)
if not s0:
    open('out/RESULT.txt', 'w').write('HARNESS FAIL: no game state log\n'); sys.exit(1)
if s0['need'] is None:
    P('WARN: state log lacks need/aim/prog fields')
# calibrate joystick -> world displacement
D = {}
for name, (ux, uy) in {'r': (1, 0), 'l': (-1, 0), 'd': (0, 1), 'u': (0, -1)}.items():
    a = st(); swipe(ux, uy, 1.5); time.sleep(0.8); b = st()
    D[name] = (b['x'] - a['x'], b['z'] - a['z']); P('CAL', name, D[name])
axc = ((D['r'][0] - D['l'][0]) / 2, (D['r'][1] - D['l'][1]) / 2)
ayc = ((D['d'][0] - D['u'][0]) / 2, (D['d'][1] - D['u'][1]) / 2)
det = axc[0] * ayc[1] - ayc[0] * axc[1]
RES['joystick_calibrated'] = abs(det) > 1e-3
P('CAL matrix cols', axc, ayc, 'det', det)
if not RES['joystick_calibrated']:
    open('out/RESULT.txt', 'w').write('HARNESS FAIL: joystick calibration degenerate\n'); sys.exit(1)
speed = (math.hypot(*axc) + math.hypot(*ayc)) / 2 / 1.5
def nav(tx, tz, tol, maxit=25, stop_in_range=False, need_t=None):
    for i in range(maxit):
        s = st()
        if s is None: continue
        dx, dz = tx - s['x'], tz - s['z']; dist = math.hypot(dx, dz)
        if dist < tol or (stop_in_range and s['rng'] == 1 and s['need'] == need_t): return s
        # solve [axc ayc] u = d
        ux = (dx * ayc[1] - ayc[0] * dz) / det
        uy = (axc[0] * dz - dx * axc[1]) / det
        n = math.hypot(ux, uy) or 1
        dur = max(0.5, min(2.5, dist / max(speed, 0.2) * 0.8))
        P('NAV', i, 'at', (round(s['x'], 2), round(s['z'], 2)), 'to', (round(tx, 2), round(tz, 2)), 'dist', round(dist, 2), 'dur', round(dur, 2))
        swipe(ux / n, uy / n, dur); time.sleep(0.4)
    return st()
done = False
for attempt in range(4):
    s = st(); P('LOOP', attempt, s)
    if not s: continue
    if s['need'] and s['need'] != '-':
        need_t, aim_t = s['need'], (s['ax'], s['az'])
    elif 'need_t' not in globals():
        P('no active part/need'); break
    if s['tool'] != need_t:
        sx, sz = STATIONS[need_t]
        nav(sx, sz, 0.6)
        t0 = time.time()
        while time.time() - t0 < 8:
            s = st()
            if s and s['tool'] == need_t: break
            time.sleep(1)
        P('TOOL', s['tool'] if s else None, 'need_t', need_t)
        RES['tool_equipped'] = bool(s and s['tool'] == need_t)
        if not RES['tool_equipped']: continue
        s = st()
    s = nav(aim_t[0], aim_t[1], 0.35, stop_in_range=True, need_t=need_t)
    P('AT PART', s)
    RES['in_range'] = bool(s and s['rng'] == 1 and s['need'] == need_t)
    if not RES['in_range']: continue
    prog0 = s['prog']; snap('04-inrange-before-hold')
    x, y = f(*RC)
    sh(f"idb ui tap {x:.0f} {y:.0f} --duration 4 --udid {U}")
    snap('05-after-hold')
    ls = [parse(l) for l in rawlog('10s').splitlines() if 'CFTOUCH] state' in l]
    ls = [p for p in ls if p]
    RES['repairing'] = any(p['rep'] == 1 for p in ls)
    pr = [p['prog'] for p in ls if p['prog'] is not None]
    RES['progress_delta'] = (max(pr) - prog0) if pr else None
    P('HOLD result repairing', RES['repairing'], 'prog0', prog0, 'max', max(pr) if pr else None)
    done = True; break
# pan check after the action sequence
a = st(); x0, y0 = f(437, 200); x1, y1 = f(600, 200)
sh(f"idb ui swipe {x0:.0f} {y0:.0f} {x1:.0f} {y1:.0f} --duration 1 --udid {U}"); time.sleep(1)
b = st(); RES['pan_yaw_changed'] = bool(a and b and abs(a['yaw'] - b['yaw']) > 0.01); snap('06-pan')
full = rawlog('600s'); open('out/touch.log', 'w').write(full)
RES['repairFingerDown_events'] = sum(1 for l in full.splitlines() if 'repairFingerDown=1' in l)
ok = RES.get('tool_equipped', True) and RES.get('in_range') and RES.get('repairing') and (RES.get('progress_delta') or 0) > 0 and RES['pan_yaw_changed'] and RES['repairFingerDown_events'] > 0
v = 'RESULT ' + ' '.join(f'{k}={v}' for k, v in RES.items()) + (' PASS' if ok else ' FAIL')
P(v); open('out/RESULT.txt', 'w').write(v + '\n')
sys.exit(0 if ok else 1)
