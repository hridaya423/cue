"use client";

import { useEffect } from "react";
import { gsap } from "gsap";
import { ScrollTrigger } from "gsap/ScrollTrigger";
import Lenis from "lenis";

const $ = <T extends Element = HTMLElement>(s: string, r: ParentNode = document) => r.querySelector(s) as T;
const $$ = <T extends Element = HTMLElement>(s: string, r: ParentNode = document) => [...r.querySelectorAll(s)] as T[];
const clamp01 = (x: number) => Math.min(1, Math.max(0, x));
const wait = (s: number) => new Promise<void>((r) => gsap.delayedCall(s, r));

const MARK_W = 254.7;
const runs = (rects: Element[]) =>
  rects.map((el) => {
    const x = Number(el.getAttribute("x"));
    return { el, row: Math.round((Number(el.getAttribute("y")) - 1.9) / 10), from: x / MARK_W, to: (x + Number(el.getAttribute("width"))) / MARK_W };
  });
const drawAt = (row: number, from: number) => row * 0.035 + from * 0.22;
const drawMark = (rects: Element[]) => {
  const rs = runs(rects);
  return gsap.to(rects, { scaleX: 1, duration: 0.7, ease: "power3.out", stagger: (i) => drawAt(rs[i].row, rs[i].from) });
};

function intro(root: HTMLElement) {
  const ASPECT = 2.8295, ROWS = 9, MID = 4, DRAW = 0.7, LEAD_IN = 0.15, HOLD = 0.05, CAP = 1.3, PEEL = 0.05, FLIGHT = 0.95;
  const overlay = $(".intro");
  if (!root.classList.contains("is-intro")) {
    overlay.remove();
    return Promise.resolve();
  }
  let announce: () => void = () => {};
  const done = new Promise<void>((r) => (announce = r));
  try { sessionStorage.setItem("cue-intro", "1"); } catch {}
  history.scrollRestoration = "manual";
  scrollTo(0, 0);

  const ground = $(".intro__ground", overlay);
  const mark = $(".intro__mark", overlay);
  const track = $(".intro__track", overlay);
  const fill = $(".intro__fill", overlay);
  const rise = $$(".lead__copy, .desk");

  const vw = innerWidth, vh = innerHeight;
  const W = Math.min(560, Math.max(200, vw < 700 ? vw * 0.6 : vw * 0.34));
  const H = W / ASPECT, pitch = H / ROWS;
  const ox = (vw - W) / 2, oy = (vh - H) / 2 - pitch;
  gsap.set(track, { top: oy + H + Math.max(32, pitch * 2.4) });

  const caps = runs($$(".site-header .logo__svg rect")).map(({ el: target, row, from, to }) => {
    const el = document.createElement("div");
    el.className = "intro__cap";
    const w = (to - from) * W;
    el.style.width = w + "px";
    el.style.height = pitch * 0.62 + "px";
    mark.appendChild(el);
    gsap.set(el, { x: ox + from * W, y: oy + row * pitch + pitch * 0.19, clipPath: "inset(0% 100% 0% 0% round 999px)" });
    return { el, row, from, w, target };
  });

  const tl = gsap.timeline();
  caps.forEach((c) => tl.to(c.el, { clipPath: "inset(0% 0% 0% 0% round 999px)", duration: DRAW, ease: "power3.out" }, LEAD_IN + drawAt(c.row, c.from)));
  const drawEnd = tl.duration();

  let loaded = false;
  const fonts = document.fonts.ready.catch(() => {}).then(() => { loaded = true; });
  const progress = { v: 0 };
  const meter = () => {
    const target = Math.min(loaded ? 1 : 0, tl.time() / drawEnd);
    progress.v += (target - progress.v) * 0.2;
    gsap.set(fill, { scaleX: progress.v });
  };
  gsap.ticker.add(meter);

  let ended = false;
  let flight: gsap.core.Timeline | null = null;
  const inputs = ["keydown", "pointerdown", "wheel", "touchstart"];
  const finish = () => {
    if (ended) return;
    ended = true;
    gsap.ticker.remove(meter);
    tl.kill();
    flight?.kill();
    gsap.set(rise, { clearProps: "transform" });
    root.classList.remove("is-intro");
    overlay.remove();
    inputs.forEach((t) => removeEventListener(t, finish));
    announce();
  };
  inputs.forEach((t) => addEventListener(t, finish, { passive: true }));

  const handoff = () => {
    if (ended) return;
    gsap.ticker.remove(meter);
    flight = gsap.timeline({ onComplete: finish });
    flight.to(track, { opacity: 0, duration: 0.2, ease: "power1.out" }, 0);
    flight.to(ground, { opacity: 0, duration: 0.45, ease: "power1.out" }, FLIGHT * 0.7);
    caps.forEach((c) => {
      const r = c.target.getBoundingClientRect();
      const at = c.row * PEEL + c.from * 0.1;
      const tilt = (c.row - MID) * -0.7 - 2.5;
      flight!
        .to(c.el, { x: r.left, y: r.top, scale: r.width / c.w, duration: FLIGHT, ease: "expo.inOut" }, at)
        .to(c.el, { rotation: tilt, duration: FLIGHT * 0.45, ease: "power2.out" }, at)
        .to(c.el, { rotation: 0, duration: FLIGHT * 0.55, ease: "power3.inOut" }, at + FLIGHT * 0.45);
    });
    flight.fromTo(rise, { y: 24 }, { y: 0, duration: 0.9, ease: "expo.out", stagger: 0.07 }, FLIGHT * 0.7);
  };

  Promise.all([wait(drawEnd + HOLD), Promise.race([fonts, wait(CAP)])]).then(handoff);
  return done;
}

function header(reduce: boolean) {
  const bar = $(".site-header");
  const edge = (side: string) => () => `${side} ${bar.offsetHeight}px`;
  ScrollTrigger.create({ start: 0, end: "max", onUpdate: (s) => bar.classList.toggle("is-scrolled", s.scroll() > 24) });
  const link = $<HTMLAnchorElement>(".site-header .nav__link");
  ScrollTrigger.create({
    trigger: "#privacy", start: "top 40%", endTrigger: ".close", end: "top 40%", refreshPriority: -1,
    onToggle: ({ isActive }) => (isActive ? link.setAttribute("aria-current", "true") : link.removeAttribute("aria-current")),
  });
  const ground = (cls: string, opts: ScrollTrigger.Vars) => {
    const set = (s: ScrollTrigger) => bar.classList.toggle(cls, s.isActive);
    ScrollTrigger.create({ ...opts, refreshPriority: -1, onToggle: set, onRefresh: set });
  };
  ground("is-flood", { trigger: ".lead", start: "top bottom", end: edge("bottom") });
  ground("is-dark", {
    trigger: ".pv", start: edge("top"),
    endTrigger: reduce ? ".pv__local" : ".pv__seam", end: reduce ? edge("top") : `center ${bar.offsetHeight}px`,
  });
  ScrollTrigger.create({ trigger: ".close", start: "top 20%", refreshPriority: -1, onToggle: ({ isActive }) => bar.classList.toggle("is-end", isActive) });
}

function hero(reduce: boolean, introDone: Promise<void>) {
  const desk = $(".desk");
  const chat = $(".chat", desk);
  const text = $(".chat__pick", chat);
  const cut = $(".cut", text);
  const field = $(".form__field", desk);
  const value = $(".form__value", field);
  const ptr = $(".ptr", desk);
  const [copyKeys, pasteKeys] = $$(".keys", desk);
  const REST = "0 3px 0 0 #aab6ef, 0 7px 14px -3px rgba(10,21,82,0.5)";
  const DOWN = "0 1px 0 0 #aab6ef, 0 3px 6px -3px rgba(10,21,82,0.5)";
  type Line = { el: HTMLElement; l: number; r: number; cy: number };
  let lines: Line[] = [];

  const box = (r: DOMRect | Element) => {
    const d = desk.getBoundingClientRect(), b = r instanceof Element ? r.getBoundingClientRect() : r;
    return { x: b.left - d.left, y: b.top - d.top, w: b.width, h: b.height, cx: b.left - d.left + b.width / 2, cy: b.top - d.top + b.height / 2 };
  };
  const textBox = (el: Element) => { const r = document.createRange(); r.selectNodeContents(el); return box(r.getBoundingClientRect()); };

  const measure = () => {
    $$(".hl", text).forEach((h) => h.remove());
    const range = document.createRange();
    range.selectNodeContents(text);
    const rows: { top: number; bottom: number; l: number; r: number }[] = [];
    for (const r of range.getClientRects()) {
      if (!r.width) continue;
      const cy = (r.top + r.bottom) / 2;
      const row = rows.find((w) => cy > w.top && cy < w.bottom);
      if (row) { row.l = Math.min(row.l, r.left); row.r = Math.max(row.r, r.right); }
      else rows.push({ top: r.top, bottom: r.bottom, l: r.left, r: r.right });
    }
    rows.sort((p, q) => p.top - q.top);
    const t = text.getBoundingClientRect(), d = desk.getBoundingClientRect();
    const lh = parseFloat(getComputedStyle(text).lineHeight);
    lines = rows.map((w) => {
      const el = document.createElement("span");
      el.className = "hl";
      const cy = (w.top + w.bottom) / 2;
      Object.assign(el.style, { left: `${w.l - t.left - 1}px`, top: `${cy - t.top - lh / 2}px`, width: `${w.r - w.l + 2}px`, height: `${lh}px` });
      text.append(el);
      return { el, l: w.l - d.left, r: w.r - d.left, cy: cy - d.top };
    });
  };
  const paint = (x: number, y: number) => {
    let cur = 0;
    lines.forEach((w, i) => { if (Math.abs(w.cy - y) < Math.abs(lines[cur].cy - y)) cur = i; });
    lines.forEach((w, i) => {
      const right = i < cur ? w.r : i === cur ? Math.min(Math.max(x, w.l), w.r) : w.l;
      w.el.style.clipPath = `inset(0 ${(((w.r - right) / (w.r - w.l)) * 100).toFixed(2)}% 0 0)`;
    });
  };

  const at = { x: 0, y: 0 };
  const place = () => gsap.set(ptr, { x: at.x, y: at.y });
  const move = (to: { x: number; y: number }, dur: number, beam: boolean) =>
    gsap.timeline()
      .call(() => ptr.classList.remove("is-beam"))
      .to(at, { x: to.x, duration: dur, ease: "power3.inOut", onUpdate: place }, 0)
      .to(at, { y: to.y, duration: dur, ease: "power2.inOut", onUpdate: place }, 0)
      .call(() => ptr.classList.toggle("is-beam", beam));
  const click = () => gsap.timeline().to(ptr, { scale: 0.85, duration: 0.07, ease: "power2.in" }).to(ptr, { scale: 1, duration: 0.16, ease: "power2.out" });

  const chord = (keys: HTMLElement, spot: () => { x: number; y: number }) => {
    const caps = $$("kbd", keys);
    return gsap.timeline()
      .call(() => { const p = spot(); gsap.set(keys, { x: p.x, y: p.y, xPercent: -50, yPercent: -100 }); })
      .fromTo(keys, { opacity: 0, scale: 0.92 }, { opacity: 1, scale: 1, duration: 0.26, ease: "power3.out" })
      .to(caps.slice(0, -1), { y: 2, boxShadow: DOWN, duration: 0.07, ease: "power2.in" }, "+=0.1")
      .to(caps.at(-1)!, { y: 2, boxShadow: DOWN, duration: 0.07, ease: "power2.in" }, "+=0.08")
      .to(caps, { y: 0, boxShadow: REST, duration: 0.16, ease: "power2.out" }, "+=0.16")
      .to(keys, { opacity: 0, scale: 0.96, duration: 0.3, ease: "power1.in" }, "+=0.4");
  };

  const fly = (dur: number) => {
    const s = { t: 0, ax: 0, ay: 0, bx: 0, by: 0, arc: 0, el: null as HTMLElement | null };
    const bg = gsap.utils.interpolate("#2040e6", "#e9edfd"), ink = gsap.utils.interpolate("#ffffff", "#1d1c2b");
    return gsap.timeline().to(s, {
      t: 1, duration: dur, ease: "power2.inOut",
      onStart() {
        value.textContent = cut.textContent;
        field.classList.add("is-chip");
        value.style.visibility = "hidden";
        const a = box(cut), b = textBox(value);
        const el = document.createElement("span");
        el.className = "fly";
        el.textContent = cut.textContent;
        desk.append(el);
        s.ax = a.cx - el.offsetWidth / 2; s.ay = a.cy - el.offsetHeight / 2;
        s.bx = b.cx - el.offsetWidth / 2; s.by = b.cy - el.offsetHeight / 2;
        s.arc = Math.max(40, Math.hypot(s.bx - s.ax, s.by - s.ay) * 0.26);
        s.el = el;
        gsap.set(el, { x: s.ax, y: s.ay });
        cut.classList.remove("is-sel");
      },
      onUpdate() {
        if (!s.el) return;
        const t = s.t, up = Math.sin(Math.PI * t), k = clamp01((t - 0.55) / 0.4);
        gsap.set(s.el, { x: s.ax + (s.bx - s.ax) * t, y: s.ay + (s.by - s.ay) * t - s.arc * up, rotation: -4 * up, scale: 1 + 0.1 * up, backgroundColor: bg(k), color: ink(k) });
        s.el.style.setProperty("--l", up.toFixed(3));
      },
      onComplete() {
        value.style.visibility = "";
        field.classList.add("is-done");
        gsap.to(s.el, { opacity: 0, duration: 0.2, ease: "power1.out", onComplete: () => s.el?.remove() });
      },
    });
  };

  const reset = () => {
    chat.classList.remove("is-blur");
    cut.classList.remove("is-sel");
    field.classList.remove("is-chip", "is-done", "is-focus");
    value.textContent = "";
    value.style.cssText = "";
    $$(".fly", desk).forEach((f) => f.remove());
    gsap.set([copyKeys, pasteKeys, ptr], { opacity: 0, scale: 1 });
    gsap.set($$("kbd", desk), { y: 0, boxShadow: REST });
    ptr.classList.remove("is-beam");
    measure();
  };

  let tl: gsap.core.Timeline | null = null;
  let inView = true;
  const cycle = () => {
    tl?.kill();
    reset();
    const c = box(chat), first = lines[0], last = lines.at(-1)!, to = box($(".form__box", field));
    Object.assign(at, { x: c.x + c.w * 0.78, y: c.y + c.h * 0.36 });
    place();
    tl = gsap.timeline({ paused: !inView, onComplete: cycle });
    tl.to(ptr, { opacity: 1, duration: 0.3, ease: "power1.out" }, 0.3)
      .add(move({ x: first.l, y: first.cy }, 0.8, true), 0.5)
      .to(at, {
        keyframes: { x: [first.l, last.r * 0.55 + first.l * 0.45, last.r], y: [first.cy, (first.cy + last.cy) / 2, last.cy] },
        duration: 0.9, ease: "power1.inOut", onUpdate: () => { place(); paint(at.x, at.y); },
      }, "+=0.15")
      .add(chord(copyKeys, () => { const t = box(text); return { x: t.x + t.w - 44, y: t.y - 8 }; }), "+=0.15")
      .add(move({ x: to.x + 14, y: to.cy }, 0.85, true), "-=0.55")
      .add(click())
      .call(() => { chat.classList.add("is-blur"); field.classList.add("is-focus"); }, undefined, "<0.05")
      .add(chord(pasteKeys, () => { const r = box(field); return { x: r.x + r.w * 0.62, y: r.y - 6 }; }), "+=0.35")
      .to(ptr, { opacity: 0, duration: 0.25, ease: "power1.in" }, "<0.1")
      .call(() => cut.classList.add("is-sel"), undefined, "<0.35")
      .add(fly(1.05), "+=0.3")
      .to({}, { duration: 2.8 })
      .to([value, ...lines.map((w) => w.el)], { opacity: 0, duration: 0.4, ease: "power1.in" });
  };

  if (reduce) {
    value.textContent = cut.textContent;
    field.classList.add("is-chip", "is-done");
    return;
  }
  reset();
  introDone.then(() => {
    cycle();
    new IntersectionObserver(([e]) => { inView = e.isIntersecting; if (tl) inView ? tl.resume() : tl.pause(); }).observe(desk);
    let last = `${innerWidth}x${innerHeight}`;
    new ResizeObserver(() => { const now = `${innerWidth}x${innerHeight}`; if (now !== last) { last = now; cycle(); } }).observe(desk);
  });
}

function privacy() {
  const section = $(".pv");
  const note = $(".pv__note", section);
  const rows = $$(".pv__seam i", section);
  const lap = $(".pv__lap", section);
  const marks = $$(".pv__screen rect", section);
  const ease = gsap.parseEase("power2.inOut");
  const seg = (u: number, a: number, b: number) => clamp01((u - a) / (b - a));

  for (const n of [...note.childNodes]) {
    if (n.nodeType !== 3 || !n.textContent!.trim()) continue;
    const frag = document.createDocumentFragment();
    for (const t of n.textContent!.split(/(\s+)/)) {
      if (!t) continue;
      if (/^\s+$/.test(t)) { frag.append(t); continue; }
      const w = document.createElement("span");
      w.className = "pv__w";
      w.textContent = t;
      frag.append(w);
    }
    n.replaceWith(frag);
  }
  const atoms = $$(".pv__w, .pii", note);
  const tapes = $$(".pii", note).map((el) => ({ el, c: $(".pii__c", el), t: $(".pii__t", el), d: 0, after: [] as HTMLElement[] }));
  const mid = (el: HTMLElement) => el.offsetTop + el.offsetHeight / 2;

  const measure = () => {
    atoms.forEach((el) => { el.style.transform = ""; });
    const lh = parseFloat(getComputedStyle(note).lineHeight);
    for (const tp of tapes) {
      tp.d = tp.t.offsetWidth - tp.c.offsetWidth;
      tp.after = atoms.filter((el) => el !== tp.el && Math.abs(mid(el) - mid(tp.el)) < lh / 2 && el.offsetLeft > tp.el.offsetLeft);
    }
  };
  const tape = (p: number) => {
    const shift = new Map<HTMLElement, number>();
    tapes.forEach((tp, i) => {
      const k = ease(seg(p, i * 0.13, i * 0.13 + 0.3));
      tp.c.style.clipPath = `inset(0 ${((1 - k) * 100).toFixed(1)}% 0 0 round 999px)`;
      tp.t.style.opacity = (1 - seg(k, 0, 0.45)).toFixed(2);
      for (const el of tp.after) shift.set(el, (shift.get(el) ?? 0) + tp.d * (1 - k));
    });
    atoms.forEach((el) => { const d = shift.get(el); el.style.transform = d ? `translateX(${d.toFixed(1)}px)` : ""; });
  };
  ScrollTrigger.create({
    trigger: note, start: "top 85%", end: "bottom 40%", invalidateOnRefresh: true,
    onRefreshInit: measure, onRefresh: (s) => tape(s.progress), onUpdate: (s) => tape(s.progress),
  });

  const seam = (q: number) => rows.forEach((row, r) => {
    const k = seg(q, (rows.length - 1 - r) * 0.06, (rows.length - 1 - r) * 0.06 + 0.52);
    const sweep = gsap.parseEase("power3.out")(seg(k, 0, 0.62));
    row.style.clipPath = `inset(0 0 0 ${((1 - sweep) * 100).toFixed(2)}% round 999px)`;
    row.style.transform = `scaleY(${(0.2 + 0.94 * ease(seg(k, 0.4, 1))).toFixed(3)})`;
  });
  ScrollTrigger.create({
    trigger: $(".pv__seam", section), start: "top bottom", end: "bottom 12%", invalidateOnRefresh: true,
    onUpdate: (s) => seam(s.progress), onRefresh: (s) => seam(s.progress),
  });

  for (const [rects, trigger] of [[marks, lap], [$$(".close__mark rect"), $(".close__mark")]] as const) {
    gsap.set(rects, { scaleX: 0 });
    ScrollTrigger.create({ trigger, start: "top 72%", once: true, onEnter: () => { drawMark(rects); } });
  }
  gsap.fromTo($$("img, .pv__screen", lap), { y: 48 }, { y: -24, ease: "none", scrollTrigger: { trigger: lap, start: "top bottom", end: "bottom top", scrub: true } });
}

async function run() {
  gsap.registerPlugin(ScrollTrigger);
  const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const root = document.documentElement;
  const introDone = intro(root);

  if (document.readyState !== "complete") await new Promise((r) => addEventListener("load", r, { once: true }));
  await document.fonts.ready;
  if (!reduce) root.classList.add("motion");

  if (!reduce) {
    const lenis = new Lenis({ lerp: 0.11, anchors: { offset: 0 } });
    lenis.on("scroll", ScrollTrigger.update);
    gsap.ticker.add((t) => lenis.raf(t * 1000));
    gsap.ticker.lagSmoothing(0);
  }

  header(reduce);
  hero(reduce, introDone);
  if (!reduce) privacy();

  await introDone;
  ScrollTrigger.refresh();
}

let started = false;
export default function Motion() {
  useEffect(() => {
    if (started) return;
    started = true;
    run();
  }, []);
  return null;
}
