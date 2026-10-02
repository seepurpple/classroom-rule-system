"use client";
import { useEffect, useRef, useState, type RefObject } from "react";
import type * as T from "three";

export type Prize = { name: string; weight: number };
export type GameConfig = { price: number; prizes: Prize[]; item?: string | null; total?: number | null; remaining?: number | null; seconds?: number | null; precision?: number | null; active: boolean };
export type Play = { id: string; game: string; status: "pending" | "won" | "lost"; result: string | null; elapsed?: number | null; target?: number | null; precision?: number | null; started_at?: string | null };
export type Api = (action: string, data: Record<string, unknown>) => Promise<false | { play?: Play }>;
type Three = typeof T;
type Frame = (dt: number) => void;
type Setup = (THREE: Three, scene: T.Scene, camera: T.PerspectiveCamera, renderer: T.WebGLRenderer) => Frame | void;

const money = (v: number) => v.toLocaleString("ko-KR") + "P";

// One three.js canvas per game: lazy-load three, light the scene, run a frame loop, clean up on close.
function useScene(mount: RefObject<HTMLDivElement | null>, setup: Setup) {
  useEffect(() => {
    let stop = false, dispose = () => {};
    void import("three").then(THREE => {
      const el = mount.current; if (stop || !el) return;
      const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true });
      renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
      renderer.outputColorSpace = THREE.SRGBColorSpace;
      el.appendChild(renderer.domElement);
      const scene = new THREE.Scene();
      const camera = new THREE.PerspectiveCamera(38, 1, .1, 60);
      scene.add(new THREE.HemisphereLight(0xfff8ec, 0x6f7f68, 1.6));
      const sun = new THREE.DirectionalLight(0xffffff, 1.8); sun.position.set(3, 7, 5); scene.add(sun);
      const frame = setup(THREE, scene, camera, renderer);
      const resize = () => { const w = el.clientWidth, h = el.clientHeight; renderer.setSize(w, h, false); camera.aspect = w / h; camera.updateProjectionMatrix(); };
      const ro = new ResizeObserver(resize); ro.observe(el); resize();
      let last = performance.now(), raf = 0;
      const loop = (now: number) => { frame?.(Math.min(.05, (now - last) / 1000)); last = now; renderer.render(scene, camera); raf = requestAnimationFrame(loop); };
      raf = requestAnimationFrame(loop);
      dispose = () => { cancelAnimationFrame(raf); ro.disconnect(); renderer.dispose(); renderer.domElement.remove(); };
    });
    return () => { stop = true; dispose(); };
  // The scene is built once per open popup; game state lives in refs.
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);
}

function label(THREE: Three, lines: { text: string; size: number; color: string; bold?: boolean }[], w: number, h: number, bg: string) {
  const c = document.createElement("canvas"); c.width = w; c.height = h;
  const g = c.getContext("2d")!; g.fillStyle = bg; g.fillRect(0, 0, w, h); g.textAlign = "center"; g.textBaseline = "middle";
  const total = lines.reduce((n, l) => n + l.size * 1.35, 0); let y = (h - total) / 2;
  for (const l of lines) { g.font = `${l.bold ? 800 : 500} ${l.size}px "Apple SD Gothic Neo","Noto Sans KR",sans-serif`; g.fillStyle = l.color; y += l.size * .675; g.fillText(l.text, w / 2, y, w - 40); y += l.size * .675; }
  const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; return t;
}

function Result({ play, onAgain, again }: { play: Play; onAgain: () => void; again: string }) {
  const won = play.status === "won" && play.result !== "꽝";
  return <div className="pc-game-result" role="status"><span>{won ? "🎉" : "🌱"}</span><h3>{won ? `${play.result} 당첨!` : play.result === "꽝" ? "꽝! 다음 기회에" : "아쉽게 놓쳤어요"}</h3><p>{won ? "선생님께 보여 주고 상품을 받아요." : "포인트는 사용되었어요."}</p><button className="pc-primary" onClick={onAgain}>{again}</button></div>;
}

// ── 뽑기: 집게로 공을 잡아 배출구에 넣으면 서버가 확률표로 상품을 정한다 ──
type ClawLogic = { phase: string; t: number; x: number; z: number; y: number; open: number; held: number; drop: string; keys: Record<string, boolean>; timer: number; shown: number; finish?: (grabbed: boolean) => void };
const HOME = { x: -1.55, z: .95 }, TOP = 3.1, BOTTOM = .66, R = .27;
export function ClawGame({ config, balance, api }: { config: GameConfig; balance: number; api: Api }) {
  const mount = useRef<HTMLDivElement>(null);
  const logic = useRef<ClawLogic>({ phase: "idle", t: 0, x: HOME.x, z: HOME.z, y: TOP, open: .25, held: -1, drop: "", keys: {}, timer: 20, shown: 20 });
  const [phase, setPhase] = useState("idle"), [play, setPlay] = useState<Play | null>(null), [timer, setTimer] = useState(20), [busy, setBusy] = useState(false);
  const finish = async (grabbed: boolean) => {
    if (!play) return; setPhase("resolving");
    const r = await api("gameResult", { playId: play.id, grabbed });
    if (r && r.play) { setPlay(r.play); setPhase("result"); } else setPhase("ready");
  };
  useEffect(() => { logic.current.finish = grabbed => void finish(grabbed); });
  useScene(mount, (THREE, scene, camera) => {
    camera.position.set(0, 3.4, 7.2); camera.lookAt(0, 1.4, 0);
    const mat = (color: number, extra: Partial<T.MeshStandardMaterialParameters> = {}) => new THREE.MeshStandardMaterial({ color, roughness: .45, ...extra });
    const box = (w: number, h: number, d: number, m: T.Material, x: number, y: number, z: number) => { const b = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), m); b.position.set(x, y, z); scene.add(b); return b; };
    const frame = mat(0xd8574f), dark = mat(0x3b3550), glass = new THREE.MeshPhysicalMaterial({ color: 0xffffff, transparent: true, opacity: .12, roughness: .05 });
    box(4.6, .3, 3.4, frame, 0, -.15, 0); box(4.6, .4, 3.4, frame, 0, 3.75, 0);
    for (const [x, z] of [[-2.2, -1.6], [2.2, -1.6], [-2.2, 1.6], [2.2, 1.6]]) box(.18, 3.8, .18, frame, x, 1.8, z);
    box(4.4, 3.6, .04, glass, 0, 1.8, 1.62); box(.04, 3.6, 3.2, glass, -2.22, 1.8, 0); box(.04, 3.6, 3.2, glass, 2.22, 1.8, 0); box(4.4, 3.6, .04, mat(0xf3d9c9), 0, 1.8, -1.62);
    box(4.4, .05, 3.2, mat(0xf6e7d4), 0, 0, 0);
    box(.9, .06, .9, dark, HOME.x, .03, HOME.z);
    box(.95, .5, .05, mat(0xffd36e), HOME.x, .25, HOME.z - .47);
    const rail = box(4.2, .08, .08, dark, 0, 3.45, 0);
    const colors = [0xff6b8b, 0xffa94d, 0xffe066, 0x69db7c, 0x4dabf7, 0x9775fa, 0xf783ac];
    const balls: { m: T.Mesh; v: number; gone: boolean }[] = [];
    for (let i = 0; i < 18; i++) {
      const m = new THREE.Mesh(new THREE.SphereGeometry(R, 24, 16), mat(colors[i % colors.length], { roughness: .3 }));
      m.position.set(-.6 + (i % 6) * .56 + (Math.random() - .5) * .12, R, -1.05 + Math.floor(i / 6) * .7 + (Math.random() - .5) * .12);
      scene.add(m); balls.push({ m, v: 0, gone: false });
    }
    const claw = new THREE.Group(); scene.add(claw);
    const hub = new THREE.Mesh(new THREE.CylinderGeometry(.2, .24, .3, 20), mat(0xc0c4cc, { metalness: .7, roughness: .3 })); claw.add(hub);
    const cable = new THREE.Mesh(new THREE.CylinderGeometry(.025, .025, 1, 8), dark); scene.add(cable);
    const prongs = [0, 1, 2].map(i => { const pivot = new THREE.Group(); pivot.rotation.y = i * Math.PI * 2 / 3; const arm = new THREE.Group(); arm.position.set(0, -.12, .16); pivot.add(arm); const p = new THREE.Mesh(new THREE.BoxGeometry(.06, .55, .06), mat(0xaeb3bd, { metalness: .8, roughness: .3 })); p.position.y = -.27; arm.add(p); claw.add(pivot); return arm; });
    const L = logic.current, speed = 1.7, clamp = (v: number, a: number, b: number) => Math.max(a, Math.min(b, v));
    return dt => {
      L.t += dt;
      if (L.phase === "ready") {
        L.x = clamp(L.x + ((L.keys.right ? 1 : 0) - (L.keys.left ? 1 : 0)) * speed * dt, -1.85, 1.85);
        L.z = clamp(L.z + ((L.keys.down ? 1 : 0) - (L.keys.up ? 1 : 0)) * speed * dt, -1.2, 1.2);
        L.timer -= dt; if (L.timer <= 0) { L.phase = "open"; L.t = 0; setPhase("dropping"); }
      } else if (L.phase === "open") { L.open = .25 + Math.min(1, L.t / .35) * .45; if (L.t > .35) { L.phase = "down"; L.t = 0; } }
      else if (L.phase === "down") { L.y = TOP - (TOP - BOTTOM) * Math.min(1, L.t / 1); if (L.t > 1) { L.phase = "close"; L.t = 0; } }
      else if (L.phase === "close") {
        L.open = .7 - Math.min(1, L.t / .5) * .55;
        if (L.t > .5) {
          let best = -1, dist = .33;
          balls.forEach((b, i) => { const d = Math.hypot(b.m.position.x - L.x, b.m.position.z - L.z); if (!b.gone && d < dist) { dist = d; best = i; } });
          if (best >= 0 && Math.random() < .85) { L.held = best; const o = Math.random(); L.drop = o < 9 / 17 ? "" : o < 13 / 17 ? "lift" : "move"; } else L.held = -1;
          L.phase = "up"; L.t = 0;
        }
      } else if (L.phase === "up") {
        L.y = BOTTOM + (TOP - BOTTOM) * Math.min(1, L.t / 1.1);
        if (L.held >= 0 && L.drop === "lift" && L.t > .55) { balls[L.held].v = 0; L.held = -1; }
        if (L.t > 1.1) { L.phase = "carry"; L.t = 0; }
      } else if (L.phase === "carry") {
        const dx = HOME.x - L.x, dz = HOME.z - L.z, d = Math.hypot(dx, dz), step = speed * 1.2 * dt;
        if (L.held >= 0 && L.drop === "move" && L.t > .45) { balls[L.held].v = 0; L.held = -1; }
        if (d <= step) { L.x = HOME.x; L.z = HOME.z; L.phase = "release"; L.t = 0; } else { L.x += dx / d * step; L.z += dz / d * step; }
      } else if (L.phase === "release") {
        L.open = .15 + Math.min(1, L.t / .3) * .55;
        if (L.t > .3 && L.held >= 0) { balls[L.held].gone = true; balls[L.held].v = 0; L.held = -2; }
        if (L.t > 1.4) { const grabbed = L.held === -2; L.phase = "done"; L.open = .25; L.held = -1; L.finish?.(grabbed); }
      }
      claw.position.set(L.x, L.y, L.z); prongs.forEach(p => { p.rotation.x = L.open; });
      cable.scale.y = TOP + .35 - L.y; cable.position.set(L.x, (TOP + .35 + L.y) / 2 + .1, L.z); rail.position.z = L.z;
      balls.forEach((b, i) => {
        if (i === L.held) { b.m.position.set(L.x, L.y - .62, L.z); return; }
        const floor = b.gone ? -2 : R; if (b.m.position.y > floor) { b.v -= 9.8 * dt; b.m.position.y = Math.max(floor, b.m.position.y + b.v * dt); if (b.m.position.y === floor) b.v = 0; }
      });
      if (L.phase === "ready" && Math.ceil(L.timer) !== L.shown) { L.shown = Math.ceil(L.timer); setTimer(L.shown); }
    };
  });
  useEffect(() => {
    const L = logic.current, map: Record<string, string> = { ArrowLeft: "left", ArrowRight: "right", ArrowUp: "up", ArrowDown: "down" };
    const down = (e: KeyboardEvent) => { if (map[e.key] && L.phase === "ready") { L.keys[map[e.key]] = true; e.preventDefault(); } if ((e.key === " " || e.key === "Enter") && L.phase === "ready") { L.phase = "open"; L.t = 0; setPhase("dropping"); e.preventDefault(); } };
    const up = (e: KeyboardEvent) => { if (map[e.key]) L.keys[map[e.key]] = false; };
    window.addEventListener("keydown", down); window.addEventListener("keyup", up);
    return () => { window.removeEventListener("keydown", down); window.removeEventListener("keyup", up); };
  }, []);
  const start = async () => {
    setBusy(true); const r = await api("gamePlay", { game: "claw", expectedPrice: config.price }); setBusy(false);
    if (!r || !r.play) return;
    setPlay(r.play); Object.assign(logic.current, { phase: "ready", x: HOME.x, z: HOME.z, y: TOP, timer: 20, shown: 20, keys: {} }); setTimer(20); setPhase("ready");
  };
  const hold = (k: string) => ({ onPointerDown: () => { logic.current.keys[k] = true; }, onPointerUp: () => { logic.current.keys[k] = false; }, onPointerLeave: () => { logic.current.keys[k] = false; } });
  return <div className="pc-game">
    <div className="pc-game-stage" ref={mount}>{phase === "ready" && <b className="pc-game-timer">{timer}초</b>}{phase === "result" && play && <Result play={play} again="한 번 더 하기" onAgain={() => { setPlay(null); setPhase("idle"); logic.current.phase = "idle"; }} />}</div>
    {phase === "idle" && <button className="pc-primary pc-game-cta" disabled={busy || balance < config.price} onClick={start}>{balance < config.price ? `${money(config.price - balance)} 더 필요해요` : `${money(config.price)} 내고 시작`}</button>}
    {phase === "ready" && <div className="pc-claw-pad"><div><button aria-label="왼쪽" {...hold("left")}>◀</button><button aria-label="뒤로" {...hold("up")}>▲</button><button aria-label="앞으로" {...hold("down")}>▼</button><button aria-label="오른쪽" {...hold("right")}>▶</button></div><button className="pc-primary" onClick={() => { Object.assign(logic.current, { phase: "open", t: 0 }); setPhase("dropping"); }}>내리기</button></div>}
    {(phase === "dropping" || phase === "resolving") && <p className="pc-subtle pc-game-cta">집게가 움직이는 중…</p>}
  </div>;
}

// ── 랜덤박스: START를 누르면 서버가 정한 캡슐이 굴러 나온다 ──
export function GachaGame({ config, balance, api }: { config: GameConfig; balance: number; api: Api }) {
  const mount = useRef<HTMLDivElement>(null);
  const anim = useRef({ phase: "idle", t: 0 });
  const [phase, setPhase] = useState("idle"), [play, setPlay] = useState<Play | null>(null), [busy, setBusy] = useState(false);
  useScene(mount, (THREE, scene, camera) => {
    camera.position.set(2.6, 2.7, 8.4); camera.lookAt(0, 1.9, 0);
    const mat = (color: number, extra: Partial<T.MeshStandardMaterialParameters> = {}) => new THREE.MeshStandardMaterial({ color, roughness: .5, ...extra });
    const machine = new THREE.Group(); scene.add(machine);
    const add = (geo: T.BufferGeometry, m: T.Material, x: number, y: number, z: number) => { const o = new THREE.Mesh(geo, m); o.position.set(x, y, z); machine.add(o); return o; };
    add(new THREE.BoxGeometry(2.8, 4.2, 1.6), mat(0xe9b8c8), 0, 2.1, 0);
    const list = config.prizes.slice(0, 7).map(p => ({ text: `${p.name} · ${p.weight}%`, size: 34, color: "#5b3b4a" }));
    add(new THREE.PlaneGeometry(2.3, 2.1), new THREE.MeshBasicMaterial({ map: label(THREE, [{ text: "랜덤 가챠", size: 74, color: "#b5466b", bold: true }, ...list], 640, 584, "#fff4f7") }), 0, 2.85, .81);
    add(new THREE.BoxGeometry(2.4, .08, .1), mat(0x8c5a6c), 0, 1.75, .82);
    add(new THREE.BoxGeometry(.95, .8, .3), mat(0x2c2430), -.6, .85, .7);
    add(new THREE.PlaneGeometry(.75, .32), new THREE.MeshBasicMaterial({ map: label(THREE, [{ text: money(config.price), size: 44, color: "#d8f3ff", bold: true }], 300, 128, "#2b4f9e") }), .55, 1.3, .81);
    const button = add(new THREE.CylinderGeometry(.24, .24, .16, 32), mat(0xe03131, { emissive: 0x500000 }), .55, .78, .84); button.rotation.x = Math.PI / 2;
    const capsule = new THREE.Group(); capsule.visible = false; scene.add(capsule);
    const top = new THREE.Mesh(new THREE.SphereGeometry(.28, 32, 16, 0, Math.PI * 2, 0, Math.PI / 2), mat([0xff8fab, 0x74c0fc, 0xffd43b, 0x8ce99a][Math.floor(Math.random() * 4)], { roughness: .25 }));
    const bottom = new THREE.Mesh(new THREE.SphereGeometry(.28, 32, 16, 0, Math.PI * 2, Math.PI / 2, Math.PI / 2), mat(0xffffff, { roughness: .25 }));
    capsule.add(top, bottom);
    const A = anim.current;
    return dt => {
      A.t += dt;
      button.position.z = A.phase === "press" && A.t < .25 ? .78 : .84;
      machine.position.x = A.phase === "press" ? Math.sin(A.t * 60) * .03 * Math.max(0, 1 - A.t) : 0;
      if (A.phase === "drop") {
        capsule.visible = true; const k = Math.min(1, A.t / 1.2);
        capsule.position.set(-.6 + k * .5, .85 - Math.abs(Math.sin(k * Math.PI * 2.5)) * .35 * (1 - k) - k * .55, .7 + k * 1.6); capsule.rotation.x = k * 8;
        top.position.y = 0; top.rotation.z = 0;
        if (A.t > 1.3) { A.phase = "wait"; setPhase("ready"); }
      } else if (A.phase === "open") {
        const k = Math.min(1, A.t / .6); top.position.y = k * .55; top.rotation.z = k * 1.2; capsule.rotation.x *= .9;
        if (A.t > .8) { A.phase = "shown"; setPhase("result"); }
      } else if (A.phase === "idle") { capsule.visible = false; top.position.y = 0; top.rotation.z = 0; }
    };
  });
  const start = async () => {
    setBusy(true); anim.current.phase = "press"; anim.current.t = 0;
    const r = await api("gamePlay", { game: "gacha", expectedPrice: config.price }); setBusy(false);
    if (!r || !r.play) { anim.current.phase = "idle"; return; }
    setPlay(r.play); setPhase("dropping"); anim.current.phase = "drop"; anim.current.t = 0;
  };
  return <div className="pc-game">
    <div className="pc-game-stage" ref={mount}>{phase === "result" && play && <Result play={play} again="한 번 더 뽑기" onAgain={() => { setPlay(null); setPhase("idle"); anim.current.phase = "idle"; }} />}</div>
    {phase === "idle" && <button className="pc-primary pc-game-cta" disabled={busy || balance < config.price} onClick={start}>{balance < config.price ? `${money(config.price - balance)} 더 필요해요` : `START · ${money(config.price)}`}</button>}
    {phase === "dropping" && <p className="pc-subtle pc-game-cta">캡슐이 나오는 중…</p>}
    {phase === "ready" && <button className="pc-primary pc-game-cta" onClick={() => { anim.current.phase = "open"; anim.current.t = 0; setPhase("opening"); }}>캡슐 열기</button>}
  </div>;
}

// ── 시간 맞추기: 3·2·1 뒤 보이지 않는 타이머를 감으로 멈춘다. 시간은 서버가 잰다 ──
export function TimingGame({ config, balance, api }: { config: GameConfig; balance: number; api: Api }) {
  const mount = useRef<HTMLDivElement>(null);
  const [phase, setPhase] = useState("idle"), [count, setCount] = useState(""), [play, setPlay] = useState<Play | null>(null), [busy, setBusy] = useState(false);
  const started = useRef<Promise<unknown> | null>(null);
  const digits = config.precision === .01 ? 2 : 1;
  useScene(mount, (THREE, scene, camera) => {
    camera.position.set(0, 1.7, 6.2); camera.lookAt(0, 1.3, 0);
    const base = new THREE.Mesh(new THREE.CylinderGeometry(1.5, 1.7, .35, 48), new THREE.MeshStandardMaterial({ color: 0x5b7a5f, roughness: .6 })); base.position.y = .17; scene.add(base);
    const cube = new THREE.BoxGeometry(2.3, 2.5, 2.3);
    const glass = new THREE.Mesh(cube, new THREE.MeshPhysicalMaterial({ color: 0xe8f6ff, transparent: true, opacity: .18, roughness: .05, metalness: 0, clearcoat: 1 })); glass.position.y = 1.6; scene.add(glass);
    const edges = new THREE.LineSegments(new THREE.EdgesGeometry(cube), new THREE.LineBasicMaterial({ color: 0xd9eef7 })); edges.position.y = 1.6; scene.add(edges);
    const card = new THREE.Mesh(new THREE.PlaneGeometry(1.35, 1.75), new THREE.MeshStandardMaterial({ side: THREE.DoubleSide, roughness: .7, map: label(THREE, [{ text: "오늘의 상품", size: 40, color: "#7a8b6f" }, { text: config.item ?? "", size: 76, color: "#263d35", bold: true }, { text: `${config.remaining ?? 0}개 남음`, size: 36, color: "#a07a2c" }], 540, 700, "#fffaf0") }));
    card.position.y = 1.55; scene.add(card);
    let t = 0;
    return dt => { t += dt; card.rotation.y = Math.sin(t * .8) * .35; card.position.y = 1.55 + Math.sin(t * 1.6) * .05; };
  });
  const run = async () => {
    setBusy(true); const r = await api("gamePlay", { game: "timing", expectedPrice: config.price }); setBusy(false);
    if (!r || !r.play) return;
    setPlay(r.play);
    if (r.play.started_at) { setPhase("running"); return; }
    setPhase("count");
    for (const c of ["3", "2", "1"]) { setCount(c); await new Promise(res => setTimeout(res, 1000)); }
    setCount("시작!"); started.current = api("timingStart", { playId: r.play.id }); setPhase("running");
    setTimeout(() => setCount(""), 700);
  };
  const stop = async () => {
    if (!play) return; setBusy(true); await started.current;
    const r = await api("timingStop", { playId: play.id }); setBusy(false);
    if (r && r.play) { setPlay(r.play); setPhase("result"); }
  };
  if (!config.active && phase === "idle") return <div className="pc-game"><p className="pc-subtle pc-game-cta">지금은 등록된 상품이 없어요.</p></div>;
  return <div className="pc-game">
    <div className="pc-game-stage" ref={mount}>
      {count && <b className="pc-countdown" key={count}>{count}</b>}
      {phase === "result" && play && <div className="pc-game-result" role="status"><span>{play.status === "won" ? "🎉" : "⏱"}</span><h3>{Number(play.elapsed).toFixed(digits)}초</h3><p>목표 {Number(play.target).toFixed(digits)}초 · {play.status === "won" ? `성공! ${play.result} 획득` : "아쉬워요, 다시 도전해 보세요"}</p><button className="pc-primary" onClick={() => { setPlay(null); setPhase("idle"); }}>확인</button></div>}
    </div>
    <p className="pc-subtle pc-game-goal">{(config.seconds ?? 0).toFixed(digits)}초에 맞춰 정지를 누르세요 · {digits === 2 ? "0.01" : "0.1"}초 단위</p>
    {phase === "idle" && <button className="pc-primary pc-game-cta" disabled={busy || balance < config.price} onClick={run}>{balance < config.price ? `${money(config.price - balance)} 더 필요해요` : `시작 · ${money(config.price)}`}</button>}
    {phase === "count" && <button className="pc-primary pc-game-cta" disabled>준비…</button>}
    {phase === "running" && <button className="pc-primary pc-game-cta pc-stop" disabled={busy} onClick={stop}>정지</button>}
  </div>;
}
