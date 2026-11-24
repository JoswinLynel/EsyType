// The page hero and the voice wave (Mac design system: PageHero, SpeakingWave). The wave keeps EsyType's own colours,
// amber, white and blue as in the logo (owner, 24 Nov), not the Mac's purple middle.
import { useEffect, useRef, useState, type ReactNode } from "react";

const reduced = () => matchMedia("(prefers-reduced-motion: reduce)").matches;

/** Bar heights for the wave at time t (seconds): the Mac app's formula, x = bar index / bar count. */
export function waveHeights(n: number, t: number): number[] {
  return Array.from({ length: n }, (_, i) => {
    const x = n === 1 ? 0.5 : (i + 0.5) / n;
    const phrase = 0.55 + 0.45 * Math.sin(1.1 * t + 5 * x);
    const syllable = 0.5 + 0.5 * Math.sin(6.3 * t + 19 * x);
    return Math.max(0.08, Math.sin(Math.PI * x) * (0.25 + 0.75 * phrase * syllable));
  });
}

/** The animated wave on its own canvas (never one element per bar: that re-renders the page every frame). 30 frames a
 * second; paused while the window is hidden or not in front; one still frame with reduced motion. Decorative. */
export function Wave({ bar = 4, gap = 5, hint = 24, fade = false, className = "" }: { bar?: number; gap?: number; hint?: number; fade?: boolean; className?: string }) {
  const canvas = useRef<HTMLCanvasElement>(null);
  useEffect(() => {
    const c = canvas.current!;
    const g = c.getContext("2d");
    if (!g) return;
    let raf = 0, last = 0, w = 0, h = 0, grad: CanvasGradient | null = null;
    const draw = (t: number) => {
      const dpr = window.devicePixelRatio || 1;
      if (!grad || c.width !== Math.round(w * dpr) || c.height !== Math.round(h * dpr)) {
        c.width = Math.round(w * dpr); c.height = Math.round(h * dpr);
        // the logo's colours, built once per size rather than every frame
        const css = getComputedStyle(document.documentElement);
        const col = (v: string, d: string) => css.getPropertyValue(v).trim() || d;
        grad = g.createLinearGradient(0, 0, 0, h);
        grad.addColorStop(0, col("--et-mark-amber", "#dfa164"));
        grad.addColorStop(0.5, col("--et-mark-mid", "#ffffff"));
        grad.addColorStop(1, col("--et-mark-blue", "#27669a"));
      }
      g.setTransform(dpr, 0, 0, dpr, 0, 0);
      g.clearRect(0, 0, w, h);
      const n = Math.min(Math.max(8, Math.floor((w + gap) / (bar + gap))), hint * 3);
      const left = (w - (n * bar + (n - 1) * gap)) / 2;
      g.fillStyle = grad;
      // The ends fade here rather than with a CSS mask, which made the browser composite a mask layer every frame.
      waveHeights(n, t).forEach((v, i) => {
        const x = (i + 0.5) / n;
        g.globalAlpha = fade ? Math.min(1, x / 0.18, (1 - x) / 0.18) : 1;
        const bh = Math.max(bar, v * h);
        g.beginPath();
        g.roundRect(left + i * (bar + gap), (h - bh) / 2, bar, bh, bar / 2);
        g.fill();
      });
      g.globalAlpha = 1;
    };
    const running = () => !document.hidden && document.hasFocus() && !reduced();
    const frame = (now: number) => {
      raf = 0;
      if (now - last >= 1000 / 30) { last = now; draw(now / 1000); }
      if (running()) raf = requestAnimationFrame(frame);
    };
    const wake = () => { if (running() && !raf) raf = requestAnimationFrame(frame); else if (!running()) draw(reduced() ? 1.3 : last / 1000 || 1.3); };
    const ro = new ResizeObserver(([e]) => { w = e.contentRect.width; h = e.contentRect.height; draw(running() ? last / 1000 : 1.3); wake(); });
    ro.observe(c);
    window.addEventListener("focus", wake); window.addEventListener("blur", wake); document.addEventListener("visibilitychange", wake);
    return () => { cancelAnimationFrame(raf); ro.disconnect(); window.removeEventListener("focus", wake); window.removeEventListener("blur", wake); document.removeEventListener("visibilitychange", wake); };
  }, [bar, gap, hint, fade]);
  return <canvas ref={canvas} className={"wave " + className} aria-hidden="true" />;
}

export type HeroSpec = {
  /** The headline in three parts; the middle one is the single italic word. */
  headline: [string, string, string];
  message: ReactNode;
  glow: string;
  actions?: ReactNode;
};

const foldKey = (id: string) => "et-hero-" + id;
function useFold(id: string) {
  const [folded, set] = useState(() => { try { return localStorage.getItem(foldKey(id)) === "folded"; } catch { return false; } });
  useEffect(() => { try { set(localStorage.getItem(foldKey(id)) === "folded"); } catch { /* not kept */ } }, [id]);
  const setFolded = (f: boolean) => { set(f); try { localStorage.setItem(foldKey(id), f ? "folded" : "open"); } catch { /* not kept */ } };
  return [folded, setFolded] as const;
}

function FoldSwitch({ on, set }: { on: boolean; set: (on: boolean) => void }) {
  return <button className={"switch hero-switch" + (on ? " on" : "")} role="switch" aria-checked={on} aria-label="Show the banner" title={on ? "Fold the banner away" : "Show the banner"} onClick={() => set(!on)}><i /></button>;
}

/** A page's title row and its hero. `id` remembers the fold; `foldable` is false on Dictation. */
export function PageTop({ id, title, hero, foldable = true }: { id: string; title?: string; hero: HeroSpec; foldable?: boolean }) {
  const [folded, setFolded] = useFold(id);
  const open = !foldable || !folded;
  return (
    <>
      {title && (
        <header className="page-head title-row">
          <h1 className="display">{title}</h1>
          {foldable && !open && <span className="hero-pill"><Wave bar={3} gap={3} hint={10} /><FoldSwitch on={false} set={(on) => setFolded(!on)} /></span>}
        </header>
      )}
      {open && (
        <section className="hero" style={{ "--glow": hero.glow } as React.CSSProperties} aria-label="About this page">
          <div className="hero-text">
            <h2 className="hero-headline">{hero.headline[0]}<em>{hero.headline[1]}</em>{hero.headline[2]}</h2>
            <p className="hero-message">{hero.message}</p>
            {hero.actions && <div className="hero-actions">{hero.actions}</div>}
          </div>
          <Wave fade hint={40} className="hero-wave" />
          {foldable && <FoldSwitch on={true} set={(on) => setFolded(!on)} />}
        </section>
      )}
    </>
  );
}
