# EsyType design system

**Status:** specification, before implementation
**Date:** 15 November 2026
**Source of every brand value:** `docs/research/esyai-brand-analysis.md`

> The project brief names this file `esytalk-design-system.md`. The product name was confirmed as EsyType, so the file is named accordingly.

Each token is marked **site** (taken directly from esyai.co.uk), **adapted** (a site value adjusted for a desktop app, with the reason), or **new** (not present on the site, added because an application needs it).

---

## 1. Principles

1. **ESYAI first.** Black, white, italic serif display type, Barlow, pills, and the luminous hairline edge. A person who knows the website should recognise the app in one glance.
2. **Glass is an edge, not a fog.** The brand's glass is a nearly invisible fill with a bright, fading rim. Heavy blur is used rarely and never over text.
3. **Readable on any background.** Every text and control colour is specified against the worst case, not the best.
4. **Calm while dictating.** Nothing moves unless it tells the user something: the waveform, a state change, progress.
5. **Cheap to draw.** The design must look the same on an integrated GPU, on battery, and with Windows transparency turned off.

**Reference hierarchy:** ESYAI for identity; Wispr Flow for workflow only; the interface itself is original.

---

## 2. Materials and fallbacks

### 2.1 What Windows provides and what EsyType uses

| Surface | Windows 11 | Windows 10 | Why |
|---|---|---|---|
| Main window background | **Mica** behind a black tint | Solid fallback | Mica is sampled from the wallpaper once, costs almost nothing, and does not stutter while the window moves. Windows 10 has no Mica. |
| Main window, optional "Stronger glass" setting | Acrylic (live blur) | Acrylic (off by default) | Acrylic is the true frosted look but can lag during drag and resize on some builds, so it is opt-in. |
| In-app overlays (dialogs, menus, sticky headers) | CSS backdrop blur over the app's own content | Same | This blur is inside the page, so it works everywhere WebView2 does. |
| Recording pill and review popup | Translucent tint with the hairline edge; **no live blur of the desktop** | Same | See 2.3. |
| Title bar | Native, dark | Native, dark | Keeps snap layouts, system menu and accessibility for free. |

### 2.2 When the solid fallback is used

Automatically, without asking, whenever any of these is true:

- Windows 10, or a Windows 11 build without Mica.
- "Transparency effects" is off in Windows settings.
- A high-contrast theme is active.
- Battery saver is on (Windows disables transparency itself).
- The session is a remote desktop session.
- Hardware acceleration is unavailable.
- The user chose "Solid" in Settings → Appearance.

**Fallback appearance:** opaque `#0A0A0A` window with one fixed, very soft radial highlight at the top. All panels, edges, type and spacing are identical. Nothing in the layout depends on the material.

### 2.3 An honest constraint on the pill

A web-rendered window on Windows cannot blur what is behind it in an arbitrary shape. Native Mica and Acrylic fill the window's rectangle (with the system's small corner radius), and CSS `backdrop-filter` only blurs content inside the page. A fully rounded pill with live desktop blur behind it is therefore not available through standard APIs.

**Chosen approach:** the pill is a transparent window containing a CSS pill with a dark tint of 82% and the brand's strong hairline edge, inner highlight and soft shadow. It reads as glass because of the edge and the slight see-through, and it stays legible over any background because the tint is high.

**Recorded experiment (not committed):** a native composition backdrop clipped to a rounded shape, to be tried after the first milestone. If it works and is cheap, the pill gains real blur; if not, nothing is lost.

### 2.4 Layer model

| Layer | Use | Fill | Edge | Shadow | Blur |
|---|---|---|---|---|---|
| L0 Window | Whole app | Material + black tint 62% (or solid) | none | none | system |
| L1 Sidebar | Navigation | black 20% over L0 | 1 px right hairline, white 8% | none | none |
| L2 Panel | Page sections, cards | white 3% | soft hairline edge | none | none |
| L3 Raised | Hovered card, popover, toast, pill | white 6% (pill: black 82%) | strong hairline edge | shadow-2 | none |
| L4 Overlay | Dialog, command menu | white 8% over a black 50% scrim | strong hairline edge | shadow-3 | 16 px on the scrim |

Never nest more than two glass layers. A panel inside a panel uses a plain divider instead.

---

## 3. Colour tokens

Prefix `--et-`. Values are sRGB.

### 3.1 Brand and neutrals

| Token | Value | Origin | Use |
|---|---|---|---|
| `--et-black` | `#000000` | site | Tint base, pill, footer areas |
| `--et-ink-900` | `#0A0A0A` | site | Solid fallback window |
| `--et-ink-850` | `#0D0D0D` | site (`--card`) | Opaque raised surfaces in fallback |
| `--et-ink-800` | `#111111` | site | Media and code wells |
| `--et-ink-700` | `#171717` | site (`--secondary`) | Opaque secondary fills |
| `--et-line-500` | `#262626` | site (`--border`) | Opaque dividers |
| `--et-line-400` | `#333333` | site (nav border) | Stronger opaque dividers |
| `--et-white` | `#FFFFFF` | site | Primary text, primary button |

### 3.2 Text

| Token | Value | On black | Contrast | Origin | Use |
|---|---|---|---|---|---|
| `--et-text-1` | white 100% | `#FFFFFF` | 21:1 | site | Headings, values, primary labels |
| `--et-text-2` | white 80% | `#CCCCCC` | 13.1:1 | site | Body text |
| `--et-text-3` | white 64% | `#A3A3A3` | 8.3:1 | adapted (site uses 60% and 50%) | Secondary text, descriptions |
| `--et-text-4` | white 50% | `#808080` | 5.3:1 | site | Captions, placeholders, timestamps |
| `--et-text-disabled` | white 38% | `#616161` | 3.4:1 | new | Disabled labels only |

White at 40% (the site's placeholder colour, 3.7:1) is not used for anything that must be read.

Contrast is quoted against pure black, the most favourable case. On the lightest surface in the system (L4, about `#1F1F1F`), `--et-text-4` is about 5.1:1 and `--et-text-3` about 7.4:1, so both still pass.

### 3.3 Accent

| Token | Value | Origin | Use |
|---|---|---|---|
| `--et-accent` | `#8350E8` | site | Fills: toggles on, selected radio, progress, processing state. White text on it is 4.9:1. |
| `--et-accent-hover` | `#9567F0` | new | Hover on accent fills |
| `--et-accent-pressed` | `#6F3FD6` | new | Pressed |
| `--et-accent-text` | `#A78BFA` | site (appears in the stylesheet) | Accent-coloured text, links and focus rings on dark; 7.7:1 on black. `#8350E8` itself is only 4.3:1 as text, so it is not used for small text. |
| `--et-accent-soft` | `rgba(131, 80, 232, 0.16)` | new | Selected-row tint |
| `--et-accent-glow` | `rgba(131, 80, 232, 0.35)` | adapted from the site's radial glow | Glow behind the active recording pill; one per screen at most |

### 3.4 Motif (waveform only)

| Token | Value | Origin |
|---|---|---|
| `--et-motif-blue` | `#27669A` | sampled from the favicon (average) |
| `--et-motif-amber` | `#DFA164` | sampled from the favicon (average) |

These are averages of semi-transparent pixels and read darker than the favicon looks. They will be tuned by eye against the favicon when the waveform is built, and the final values recorded here.

### 3.5 Status

| Token | Value | Origin | Use |
|---|---|---|---|
| `--et-green` | `#4ADE80` | site | Recommended, ready, online |
| `--et-amber` | `#F2B04A` | new | Compatible with limitations, warnings |
| `--et-red` | `#EF4444` | site (`--destructive`) | Not recommended, errors, destructive actions |

Status is never shown by colour alone: every status chip has a dot, a word ("Recommended", "Limited", "Not recommended") and, in the wizard, a reason.

---

## 4. Glass, border and shadow tokens

### 4.1 Fills

| Token | Value | Origin |
|---|---|---|
| `--et-glass-1` | `rgba(255,255,255,0.03)` | adapted (site: 1% to 2%; raised slightly because the app's background is not pure black) |
| `--et-glass-2` | `rgba(255,255,255,0.06)` | new |
| `--et-glass-3` | `rgba(255,255,255,0.08)` | site (`--glass-border` value reused as a fill) |
| `--et-tint-window` | `rgba(0,0,0,0.62)` | new |
| `--et-tint-pill` | `rgba(0,0,0,0.82)` | new |
| `--et-scrim` | `rgba(0,0,0,0.50)` | site (`#00000080`) |

### 4.2 The hairline edge

The brand's signature, rebuilt for the app as two utility classes.

| Class | Gradient (top to bottom) | Inner highlight | Origin |
|---|---|---|---|
| `.et-edge` | white 45% → 15% at 20% → 0 at 40% → 0 at 60% → 15% at 80% → 45% | `inset 0 1px 1px rgba(255,255,255,0.10)` | site (`.liquid-glass`) |
| `.et-edge-strong` | white 50% → 20% → 0 → 0 → 20% → 50% | `inset 0 1px 1px rgba(255,255,255,0.15)` | site (`.liquid-glass-strong`) |

Construction: a pseudo-element with the gradient as background, masked so only a border-width ring shows, `border-radius: inherit`, `pointer-events: none`.

**Adapted:** edge width is 1 px at 100% display scale and 1.4 px (the site's value) at 150% and above. A 1.4 px line on a 100% display renders as a blurry 2 px line.

### 4.3 Borders

| Token | Value | Use |
|---|---|---|
| `--et-border-subtle` | white 8% | Dividers inside panels (site) |
| `--et-border` | white 12% | Card outlines where the gradient edge is not used |
| `--et-border-field` | white 36% | **Inputs, selects, checkboxes.** New: the site's 20% is 1.7:1 against black and fails the 3:1 minimum for control boundaries; 36% gives 3.1:1. |
| `--et-border-focus` | white 50% | Focused field border (site) |
| `--et-ring` | `0 0 0 2px #A78BFA` with a 2 px offset | Keyboard focus on every interactive element |

### 4.4 Shadows

| Token | Value | Origin |
|---|---|---|
| `--et-shadow-1` | `0 1px 2px rgba(0,0,0,0.40)` | new |
| `--et-shadow-2` | `0 8px 32px rgba(0,0,0,0.40)` | site (`--glass-shadow`) |
| `--et-shadow-3` | `0 20px 50px rgba(0,0,0,0.50)` | site |

### 4.5 Blur levels

| Token | Value | Origin | Use |
|---|---|---|---|
| `--et-blur-sm` | 4 px | site (light glass, nav) | Sticky page header over scrolling content |
| `--et-blur-md` | 16 px | site (`--glass-blur`) | Dialog scrim, menus |
| not used | 50 px | site (strong glass) | Too costly on integrated graphics for a control-level effect |

Rule: at most one blurred element on screen at a time, and never an element that animates its size.

---

## 5. Typography

### 5.1 Families

| Token | Stack | Bundled weights | Origin |
|---|---|---|---|
| `--et-font-display` | "Instrument Serif", Georgia, serif | 400 italic | site |
| `--et-font-ui` | Barlow, "Segoe UI", system-ui, sans-serif | 400, 500, 600 | site (300 dropped: too thin at application sizes) |
| `--et-font-mono` | "Cascadia Mono", Consolas, ui-monospace, monospace | system | site uses the system monospace stack |

Fonts are bundled as WOFF2 inside the application under the SIL Open Font License. Nothing is loaded from the internet.

### 5.2 Scale

| Token | Family | Size / line | Weight | Tracking | Use |
|---|---|---|---|---|---|
| `display-xl` | display, italic | 44 / 44 | 400 | −0.03 em | Wizard welcome, Coming Soon |
| `display-lg` | display, italic | 36 / 38 | 400 | −0.025 em | Page titles |
| `display-md` | display, italic | 28 / 30 | 400 | −0.025 em | Section titles, empty states, dashboard greeting |
| `title` | ui | 20 / 26 | 600 | 0 | Card titles, dialog titles |
| `heading` | ui | 16 / 22 | 600 | 0 | Group headings |
| `body` | ui | 14 / 20 | 400 | 0 | Default text |
| `body-strong` | ui | 14 / 20 | 500 | 0 | Labels, buttons, sidebar items |
| `small` | ui | 13 / 18 | 400 | 0 | Descriptions under settings |
| `caption` | ui | 12 / 16 | 500 | 0 | Chips, timestamps |
| `overline` | ui | 11 / 14 | 600, uppercase | 0.12 em | Field labels, stat labels (site pattern) |
| `stat` | ui | 32 / 36 | 600, tabular figures | −0.01 em | Dashboard numbers |
| `key` | mono | 12 / 16 | 500 | 0 | Keyboard shortcut caps |

Rules carried from the brand:

- Display type is always italic, always tightly tracked, and a display sentence ends with a full stop. *"Speak. It types."*
- Display type is never used below 24 px or for more than about eight words.
- Numbers that change (timer, counters) use tabular figures so they do not jitter.
- Sizes are in `rem` so Windows text scaling is respected.

---

## 6. Spacing, radius, sizing

| Scale | Values |
|---|---|
| Spacing (4 px grid) | 2, 4, 6, 8, 12, 16, 20, 24, 32, 40, 48, 64 |
| Radius | `xs` 6 · `sm` 8 · `md` 12 (inputs, rows; site `rounded-xl`) · `lg` 16 (panels) · `xl` 24 (hero cards, wizard; site `rounded-3xl`) · `pill` 9999 (buttons, chips, pill; site `--radius`) |
| Control heights | small 28 · default 36 · large 44 (the site's button height, used for wizard primary actions) |
| Minimum pointer target | 32 × 32 |

Layout:

| Item | Value |
|---|---|
| Default window | 1120 × 720; minimum 960 × 640 |
| Sidebar | 224 wide; items 36 high, radius 10 |
| Page padding | 32; content column up to 880 |
| Panel padding | 20; gap between panels 16 |
| Page header | Eyebrow pill → display title → one sentence in `text-3` (the site's section pattern) |

---

## 7. Motion

| Token | Value | Origin | Use |
|---|---|---|---|
| `--et-dur-instant` | 80 ms | new | Press feedback |
| `--et-dur-fast` | 120 ms | adapted (site default 150 ms) | Hover, focus, toggles |
| `--et-dur-base` | 180 ms | new | Panels, menus, tab changes |
| `--et-dur-slow` | 280 ms | site (300 ms) | Dialogs, pill appear and disappear |
| `--et-dur-entrance` | 500 ms | site | First-run and page-level entrances only |
| `--et-ease-standard` | `cubic-bezier(0.4, 0, 0.2, 1)` | site | Default |
| `--et-ease-out` | `cubic-bezier(0, 0, 0.2, 1)` | site | Things entering |
| `--et-ease-expo` | `cubic-bezier(0.25, 1, 0.5, 1)` | site (its most used scripted easing) | Entrances, pill pop |

Patterns:

- **Entrance:** opacity 0 → 1 and 12 px upward travel (the site uses 20 to 30 px; reduced for a smaller canvas). Plays once per page visit, never on scroll.
- **Press:** scale 0.97 for 80 ms (site: 0.95).
- **Not used:** marquee, orbit, sparkles, blur-in, replaying reveals, the WebGL intro.
- **Reduced motion** (Windows "Animation effects" off): all transforms removed, opacity fades capped at 120 ms, waveform replaced by a simple level bar.

---

## 8. Components

### 8.1 Buttons

| Variant | Appearance | Origin |
|---|---|---|
| Primary | White fill, black text, pill, `body-strong`. Hover white 90%. | site |
| Glass | `--et-glass-2` fill, `.et-edge-strong`, white text, pill. Hover fill white 10%. | site |
| Ghost | No container, `text-2`; hover `text-1` and `--et-glass-1` fill | site (text button) |
| Destructive | Glass with red text and red edge at 40%; confirm dialogs use a red fill | new |
| Icon | 32 px circle, ghost behaviour, tooltip required | new |

One primary button per view. Disabled: 38% opacity, no hover.

### 8.2 Inputs

- Height 36, radius `md`, fill `--et-glass-1`, border `--et-border-field`, text `body`, placeholder `text-4`.
- Focus: border `--et-border-focus` plus `--et-ring`.
- Label above in `overline` (site pattern); help text below in `small`, `text-3`; error text in red with an icon.
- Text area, select and search follow the same recipe. The shortcut recorder is an input that shows key caps.

### 8.3 Selection controls

| Control | Specification |
|---|---|
| Toggle | 36 × 20 pill; off: track white 16%, knob white 80%; on: track `--et-accent`, knob white |
| Checkbox / radio | 18 px; border `--et-border-field`; checked: accent fill, white mark |
| Segmented control | Glass pill container with a white active segment and black text, echoing the white chip inside the site's hero pill. Used for Verbatim / Clean / AI Enhanced. |
| Slider | 4 px track white 16%, white filled part, 16 px white knob |

### 8.4 Sidebar

- L1 surface. Wordmark "EsyType." in display italic, 22 px, at the top.
- Items: icon 18 px (Lucide, 1.75 stroke) and label in `body-strong`. Rest: `text-3`. Hover: `text-1`, fill `--et-glass-1`. Active: `text-1`, fill `--et-glass-2`, `.et-edge`.
- Order: Dictation, Notetaker (with a small "Soon" chip), Insights, Dictionary, Snippets, Style, Transforms, Scratchpad; then a divider; Settings and Help pinned to the bottom.
- Footer: engine status line, a green dot and "Local · model name", so the privacy promise is always visible.

### 8.5 Panels and data display

| Component | Specification |
|---|---|
| Panel | L2, radius `lg`, padding 20, `.et-edge` |
| Stat tile | `overline` label, `stat` number, `caption` context line |
| History row | 56 high; first line of text in `body`, clipped; time and word count in `caption`, `text-4`; actions (copy, edit, delete) always visible (changed 21 Nov 2026, owner-approved: hidden actions are harder to find by keyboard and screen reader) |
| Chip | 22 high pill, `caption`; neutral (glass), status (dot plus word), tag |
| Key cap | `key` type, radius `xs`, border white 20%, fill white 6% |
| Progress | 4 px pill; track white 10%; fill white (downloads) or accent (processing); shows percentage, bytes and time remaining as text |
| Empty state | Ringed icon well, one display-italic line, one grey sentence, one button |
| Toast | L3, radius `md`, bottom centre, up to 6 s, with an action |
| Dialog | L4, radius `xl`, 440 wide, primary action on the right |

### 8.6 Wizard

- One step per screen, centred column 560 wide, radius `xl` panels, large (44) primary button, step dots at the top.
- Hardware step: a row per item (CPU, memory, graphics, storage, Windows) with the detected value and a status chip.
- Model step: selectable cards with name, download size, languages, memory needed, speed note, and a status chip; exactly one carries a "Recommended" badge.
- Install step: one progress row per download with pause, retry and a clear error line.

### 8.7 Recording pill

**Window:** transparent, always on top, never takes focus, not in the taskbar or Alt + Tab. Default position: bottom centre of the monitor that has the caret, 64 px above the taskbar. Draggable by its body; position remembered per monitor; pointer events pass through outside the pill shape.

**Body:** 48 high, 248 to 320 wide depending on state, radius `pill`, fill `--et-tint-pill`, `.et-edge-strong`, `--et-shadow-2`.

**Layout:** `[ Cancel ]  [ waveform ············ ]  [ 0:07 ]  [ Stop ]`
Cancel and Stop are 32 px circles with 16 px icons (X and a rounded square), tooltips "Cancel (Esc)" and "Stop".

| State | Waveform area | Extra | Buttons |
|---|---|---|---|
| **Ready** | Flat bars breathing at low opacity; "Listening…" until audio arrives | Appears with a 280 ms pop | Cancel |
| **Recording** | Live bars | Timer in tabular figures; faint accent glow under the pill | Cancel, Stop |
| **Processing** | Bars settle to a line with a violet shimmer travelling along it; label "Transcribing" then "Enhancing" | Elapsed seconds | Cancel |
| **Inserting** | Line draws into a tick | Holds 400 ms, then fades out over 280 ms | none |
| **Error** | Message in `body` | Edge turns red; stays until dismissed | Retry or Copy, Close |

The pill is hidden when idle unless the user enables "Always show".

### 8.8 Waveform

The ESYAI mark, animated.

- 32 vertical bars, 2 px wide, 3 px apart, rounded ends, centred vertically.
- Bar height follows microphone level per 20 ms frame, with fast rise and slower fall, weighted so the centre bars are tallest.
- The site's horizontal edge-fade mask (transparent → opaque at 15% → opaque at 85% → transparent) dissolves the outer bars.
- Colour: white at 90% for quiet input; as level rises the bars take a vertical gradient from `--et-motif-blue` at the base to `--et-motif-amber` at the tip.
- Drawn on a canvas at display refresh rate while recording, and stopped entirely in every other state.
- Target cost, to be measured: under 2% of one core on the development PC.

---

## 9. Iconography and wordmark

- **Icons:** Lucide, line style, 1.75 px stroke, 18 px in navigation and 16 px in controls, `currentColor`. No filled or multicolour icons, no emoji.
- **Wordmark:** "EsyType." in Instrument Serif italic with the full stop, white, mirroring "EsyAI." Parent brand is written "EsyAI" in the About page: "EsyType. by EsyAI."
- **App icon (made 21 Nov 2026, candidate A):** nine rounded bars shaped as a short waveform, on a black rounded square, in the recording pill's colours (amber tips, white middle, blue base). Drawn by `scripts/make-icons.py` at each Windows size: 16 and 24 px use five thick bars on whole pixels.
- **Tray:** the app icon at rest; while listening, recording or transcribing, the same icon with a red dot and the tooltip "EsyType · Recording". A monochrome tray icon was not made (owner-approved): a white-only icon disappears on a light taskbar.

---

## 10. Accessibility checklist

| Requirement | How it is met |
|---|---|
| Text contrast at least 4.5:1 | Token table in 3.2; `--et-text-disabled` is used only for disabled controls |
| Control boundaries at least 3:1 | `--et-border-field` |
| Keyboard access to everything | Logical tab order; visible `--et-ring`; Esc closes overlays; arrow keys in lists and the sidebar |
| Screen readers | Semantic elements and labels; state changes of dictation announced through a polite live region in the main window |
| High-contrast themes | `forced-colors` styles hand colour control to Windows; glass effects are dropped |
| Reduced motion | Section 7 |
| Text scaling | `rem` sizes; layout tested at 100%, 125%, 150% and 200% |
| Colour independence | Status always has a word and an icon |
| Pointer targets | 32 px minimum |

---

## 11. Implementation notes

- Tokens live in one file, `ui/src/styles/tokens.css`, as CSS custom properties. Tailwind's theme maps to those variables, so utilities such as `bg-glass-1` and `text-3` exist and no component hard-codes a colour.
- `.et-edge` and `.et-edge-strong` live in `ui/src/styles/glass.css`.
- Material selection (Mica, Acrylic or solid) is decided in Rust at start-up from the conditions in 2.2 and exposed to the UI as a `data-material` attribute on the root element, which switches `--et-tint-window` and nothing else.
- Fonts are in `resources/fonts/` with their licence files.
- A component gallery page, available in development builds only, shows every component in every state on both the material and the solid fallback. It is the visual test surface.
- Any change to a token is made here first, then in `tokens.css`.
