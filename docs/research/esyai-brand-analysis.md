# ESYAI brand analysis

**Subject:** https://esyai.co.uk (public site, all top-level routes)
**Captured:** 15 November 2026, desktop 1427×807 CSS px at 2× and a 500 px-wide window
**Purpose:** establish the real ESYAI visual identity so EsyType is recognisably an ESYAI product

> **Headline finding.** ESYAI's site is already a glass-on-black design. Its stylesheet ships two component classes named `.liquid-glass` and `.liquid-glass-strong`, plus `--glass-*` tokens. EsyType's frosted-glass interface does not need to be invented and then reconciled with the brand: it should be a desktop-grade extension of a language the brand already uses.

---

## 1. Method and evidence

| Step | Tool | What it produced |
|---|---|---|
| Target discovery | REA `list-browser-targets` | Page target "EsyAI \| AI-Powered Digital Agency" (`ev_7c317e92…`) |
| Page inspection | REA `inspect-web-page` | 1,098 DOM nodes, 1,441 accessibility nodes, 3 scripts, 4 same-origin resources, 130 DOM URLs (`ev_009bc96d…`) |
| Screenshots | REA `capture-web-screenshot` | 21 PNG captures, each hash-verified against its Evidence record |
| Bundle analysis | REA `analyze-web-bundle` | 3 scripts analysed, no route table recoverable statically (`ev_e8d7178d…`) |
| Stylesheet | Direct fetch of the public `main.43bb071d.css` (84,362 bytes) that REA listed | All colour, type, radius, shadow, blur and motion tokens below |
| Computed styles | Chrome DevTools Protocol on the same dedicated browser profile | Final rendered values for nav, headings, buttons, inputs, cards |
| Motion settings | Pattern search of the public `main.e3520447.js` (1.34 MB) | Animation distances, durations, easings |

Raw REA Evidence JSON and the fetched files are kept outside the app source at `D:\AI Projects\Tools\rea-evidence\esyai\`.

**Limits of this analysis**

- REA's page inspection is passive and origin-scoped. Resources on other origins (Google Fonts, the analytics host, remote images) were policy-filtered; font facts come from the public HTML head and from the browser's loaded-font list instead.
- Hover and focus states were read from class names and CSS, not triggered.
- The site was observed in its only theme (dark). No light theme exists in the stylesheet.
- Everything marked **Observed** was read from shipped files or the rendered page. Everything marked **Inferred** is my interpretation.

---

## 2. Brand overview

**Observed**

- Name as written on the site: **EsyAI** (title, nav wordmark, footer, social card). The wordmark is always followed by a full stop: "EsyAI."
- Positioning line: "AI-Powered Digital Agency". Offer: websites, tools, software, apps and AI automations, "delivered in days, not months".
- Markets named in copy: UK, India, US, Europe. Contact page gives London, United Kingdom.
- Site structure: Home, Services, Projects, Blogs, Contact, plus Privacy and Terms. Home sections in order: hero, process ("How It Works"), services ("Capabilities"), features ("Why Us"), a logo marquee, testimonials ("What They Say"), team, contact, footer.
- Build: single-page React app (Create React App output), Tailwind CSS with shadcn-style HSL tokens, React Router, Lucide icons, a Framer-Motion-style animation API, and a WebGL fragment shader.

**Inferred personality**

Editorial and confident rather than techy. The page is almost entirely black and white; colour is rationed. Large italic serif headlines give it a magazine feel, while the body copy is a clean, slightly condensed sans. Glass is used as jewellery (thin luminous edges on pills and cards), not as large blurred panels. The tone of the copy is short declarative sentences: "The difference is everything." "Days, Not Months."

---

## 3. Logo and logo usage

**Observed**

| Asset | Description |
|---|---|
| Nav and footer wordmark | Live text "EsyAI." set in Instrument Serif italic, white, 24 px in the footer with −0.6 px tracking. It is not an image. |
| `favicon.png` (1024×1024, transparent) | The white "EsyAI." wordmark over a field of thin vertical bars. The bars fade in and out like light through fluted glass and carry a blue-to-amber gradient. Saved as `assets/esyai-favicon.png`. |
| `og-image.png` (1200×630) | "EsyAI" in a plain sans on near-black, with the tagline and service list in grey. This one does not use the serif wordmark. Saved as `assets/esyai-og-image.png`. |

- The wordmark sits at the left of a floating pill navigation bar, never on a coloured background.
- The vertical-bar motif appears twice: in the favicon, and animated as a WebGL intro overlay that plays on every page load (`assets/esyai-21-intro-loader.png`).

**Inferred**

- The **fluted vertical bars** are the closest thing ESYAI has to a brand graphic. This matters for EsyType: a field of vertical bars is also exactly what an audio waveform looks like. See section 12.
- The social card is inconsistent with the site (sans instead of the italic serif). Worth aligning at some point; not an EsyType concern.

---

## 4. Colour palette

### 4.1 Core tokens (observed in `:root`)

The site defines shadcn-style tokens as HSL triples. HEX equivalents are computed from them.

| Token | HSL | HEX | Role |
|---|---|---|---|
| `--background` | 0 0% 2% | `#050505` | Page token (the body itself renders pure black, see below) |
| body background | n/a | `#000000` | Actual rendered page background |
| `--foreground` | 0 0% 100% | `#FFFFFF` | Text |
| `--card`, `--popover` | 0 0% 5% | `#0D0D0D` | Raised surfaces |
| `--secondary`, `--muted`, `--accent` | 0 0% 9% | `#171717` | Secondary fills |
| `--muted-foreground` | 0 0% 60% | `#999999` | Secondary text |
| `--border`, `--input` | 0 0% 15% | `#262626` | Default borders |
| `--primary` | 0 0% 100% | `#FFFFFF` | Primary button fill |
| `--primary-foreground` | 0 0% 0% | `#000000` | Text on primary |
| `--ring` | 0 0% 100% / 0.3 | white at 30% | Focus ring |
| `--destructive` | 0 84.2% 60.2% | `#EF4444` | Errors |
| `--radius` | n/a | `9999px` | Default radius is a full pill |

### 4.2 Glass tokens (observed)

| Token | Value | Meaning |
|---|---|---|
| `--glass-bg` | `#FFFFFF05` | White at 2% |
| `--glass-border` | `#FFFFFF14` | White at 8% |
| `--glass-shadow` | `0 8px 32px #0006` | Black at 40%, soft and low |
| `--glass-blur` | `16px` | Default blur radius |

### 4.3 Accent and motif colours

| Colour | HEX | Where (observed) |
|---|---|---|
| Violet | `#8350E8` | `--gradient-color`, `--sparkles-color`, a radial glow `radial-gradient(circle at bottom center, #8350E8, transparent 70%)`, and the floating chat button |
| Motif blue | about `#27669A` (sampled average; bar peaks read brighter) | Favicon bars, WebGL intro |
| Motif amber | about `#DFA164` (sampled average; bar peaks read brighter) | Favicon bars, WebGL intro |
| Online green | `#4ADE80` / `#34D399` | Status dot on the chat button |
| Soft blue | `#60A5FA` | Small icon tints on service cards |
| Silver gradient | `#F3F4F6` → `#D1D5DB` | The nav "Get Started" button (135° gradient) with a blurred `#F3F4F6` halo behind it at 40% opacity |

The motif blue and amber are approximate because the favicon bars are semi-transparent gradients; the values are averages of the most opaque, saturated pixels.

### 4.4 White-opacity text scale (observed class counts on the home page)

| Class | Count | Rendered on black | Use |
|---|---|---|---|
| `text-white` | most headings | `#FFFFFF` | Headings, labels, primary text |
| `text-white/80` | 30 | `#CCCCCC` | Emphasised body |
| `text-white/60` | 16 | `#999999` | Body paragraphs, footer text |
| `text-white/50` | 34 | `#808080` | Captions, meta |
| `text-white/40` | 2 | `#666666` | Placeholders |

### 4.5 Usage rules (inferred from the page)

1. Black and white carry everything. Violet appears as a glow or one small object per screen, never as a text colour or a large fill.
2. Hierarchy comes from white opacity, not from different greys or hues.
3. Blue and amber live only inside the fluted-bar motif. They are not UI colours.

---

## 5. Typography

### 5.1 Families (observed)

| Family | Loaded weights | Role | CSS class |
|---|---|---|---|
| **Instrument Serif** | 400 italic (400 regular is declared but was not loaded on any captured page) | Display: every H1, H2, H3 section heading, the wordmark | `.font-heading` |
| **Barlow** | 300, 400, 500, 600 | Everything else: nav, body, buttons, labels, cards | `.font-body` and the `body` default |
| Inter | 600 requested in the HTML head | Never loaded on the captured pages | none |

All three are Google Fonts under the SIL Open Font License, so they can be bundled inside a desktop app.

### 5.2 Scale (observed computed values, desktop)

| Element | Family | Size / line height | Weight and style | Tracking | Colour |
|---|---|---|---|---|---|
| Hero headline | Instrument Serif | 88 / 88 px (`lg:text-[5.5rem]`, `leading-[0.85]`) | 400 italic | −3 px | white |
| Contact H2 | Instrument Serif | 72 / 72 px | 400 italic | −1.8 px | white |
| Section H2 | Instrument Serif | 60 / 60 px (`leading-[0.9]`) | 400 italic | −1.5 px | white |
| Service H3 | Instrument Serif | 36 / 40 px | 400 italic | −0.9 px | white |
| Footer wordmark | Instrument Serif | 24 / 32 px | 400 italic | −0.6 px | white |
| Card title | Barlow | about 20 to 24 px | 500 to 600 | normal | white |
| Body paragraph | Barlow | 16 / 24 px | 300 | normal | white at 60% |
| Card body | Barlow | 16 / 24 px | 400 | normal | `#999999` |
| Nav link | Barlow | 14 / 20 px | 400 | normal | white |
| Button label | Barlow | 14 / 20 px | 500 (nav CTA 600) | normal | white or black |
| Eyebrow pill | Barlow | 12 to 14 px | 500 to 600 | normal | white |
| Form label | Barlow | about 11 px | 500, uppercase | 0.1 to 0.2 em | white at 50% |
| Input text | Barlow | 14 / 20 px | 300 | normal | white |

Responsive type steps are plain Tailwind: for example the hero is `text-5xl` (48 px) → `md:text-7xl` (72 px) → `lg:5.5rem` (88 px).

### 5.3 Typographic character (inferred)

- Headlines are always italic serif, always tightly tracked, always with line height at or below 1.0. This single choice is the most recognisable part of the brand.
- Sentences end with full stops, including headings and the logo.
- Barlow is used light (300) for long text on the web. That is too thin for small text in a desktop app on ordinary 100%-scale Windows displays; see section 12.

---

## 6. Glass: the two component classes

**Observed, verbatim from the stylesheet (formatted):**

```css
.liquid-glass {
  background: #ffffff03;                         /* white at about 1% */
  background-blend-mode: luminosity;
  backdrop-filter: blur(4px);
  border: none;
  box-shadow: inset 0 1px 1px #ffffff1a;         /* top inner highlight, white 10% */
  overflow: hidden;
  position: relative;
}
.liquid-glass::before {                          /* the luminous hairline edge */
  content: "";
  position: absolute; inset: 0;
  padding: 1.4px;
  border-radius: inherit;
  background: linear-gradient(180deg,
    #ffffff73, #ffffff26 20%, #fff0 40%, #fff0 60%, #ffffff26 80%, #ffffff73);
  -webkit-mask: linear-gradient(#fff 0 0) content-box, linear-gradient(#fff 0 0);
  -webkit-mask-composite: xor; mask-composite: exclude;
  pointer-events: none;
}

.liquid-glass-strong {
  background: #ffffff03;
  background-blend-mode: luminosity;
  backdrop-filter: blur(50px);
  border: none;
  box-shadow: 4px 4px 4px #0000000d, inset 0 1px 1px #ffffff26;
  overflow: hidden;
  position: relative;
}
.liquid-glass-strong::before {
  /* same construction, brighter: */
  background: linear-gradient(180deg,
    #ffffff80, #fff3 20%, #fff0 40%, #fff0 60%, #fff3 80%, #ffffff80);
  padding: 1.4px;
}
```

What makes it distinctive:

- **The edge, not the fill, does the work.** The fill is almost invisible (1% white). The identity is the 1.4 px gradient hairline that is bright at the top and bottom (45 to 50% white) and fades to nothing through the middle of each side.
- **Two strengths.** Light glass (4 px blur) for eyebrow pills and cards; strong glass (50 px blur) for primary action buttons.
- `.liquid-glass` appears 47 times on the home page; `.liquid-glass-strong` once (a "Book a Call" button in the closing call to action).

The navigation bar uses a third, simpler recipe: `rgba(31,31,31,0.34)` fill, `blur(4px)`, `1px solid #333333`, full pill, 62 px tall, fixed 24 px from the top and centred.

---

## 7. Components (observed)

| Component | Recipe |
|---|---|
| **Floating nav pill** | Fixed, centred, `top: 24px`. Fill `#1F1F1F` at 34%, 4 px backdrop blur, 1 px `#333` border, radius 9999 px, padding 12×24 px. Wordmark left, five 14 px links, CTA right. On small screens it becomes wordmark plus a hamburger ("Open Menu") that expands the pill downward. |
| **Nav link hover** | Each link holds two stacked copies of its label in a 20 px-tall clipped box; hover slides one out and the other in. |
| **Primary button (light)** | White fill, black text, pill, 44 px tall, padding 12×24, Barlow 14/500. Hover: white at 90%. |
| **Nav CTA** | Silver gradient `#F3F4F6 → #D1D5DB`, black 14/600 text, small arrow icon, 36 px tall, with a blurred light halo behind that grows on hover (300 ms ease-out). |
| **Glass button (dark)** | A glass pill (`.liquid-glass`, or `.liquid-glass-strong` for the closing call to action), white 14/500 text, same 44 px height. Hover: fill rises to white 10%. |
| **Text button** | White 14/500 text with a small icon, no container. Hover: white at 80%. |
| **Eyebrow pill** | `.liquid-glass` pill, 32 px tall, padding 4×14, white text. Sits above every section heading ("How It Works", "Capabilities", "Why Us", "What They Say", "Get in Touch"). The hero variant nests a white chip ("EsyAI", black 12/600 text) inside it. |
| **Cards (bento, testimonial, service)** | `.liquid-glass`, radius `rounded-3xl` (24 px) on 31 elements, some 2 rem to 3 rem; body text `#999`. Inner media wells use `#111` with `1px solid #ffffff15` and a deep shadow `0 20px 50px rgba(0,0,0,.5)`. |
| **Tag chip** | Small pill, low-contrast fill (about white 5 to 10%), 12 to 14 px text: "#UI/UX", "Core", "Popular", "New", "Enterprise". |
| **Icon well** | Circle or rounded square about 40 to 64 px, hairline ring, single Lucide line icon in white. |
| **Input / textarea / select** | Transparent fill, `1px solid` white at 20%, radius 12 px (`rounded-xl`), padding 12×16, 46 px tall, Barlow 14/300, placeholder white at 40%. Focus: border to white at 50%, no outline. Labels are tiny uppercase tracked text above the field. |
| **Footer** | Pure black, `border-top` white at 10%, padding 64 px, serif wordmark, 14 px text at white 60%. |
| **Chat launcher** | 56 px violet circle bottom-right with a green status dot. |

### Radius scale in use

`9999px` (pills: nav, buttons, chips) · `24px` (cards) · `16px` and `12px` (inner wells, inputs) · larger `2rem` to `4rem` on a few feature panels.

### Borders and shadows

- Borders are hairlines only: white at 8%, 10%, 15% or 20%, or `#262626` / `#333333`. No coloured borders.
- Shadows are either a single soft drop (`0 8px 32px` black 40%; `0 20px 50px` black 50%) or inner highlights (`inset 0 1px 1px` white 10 to 15%). An `inset 0 0 60px black` vignette is used inside two media wells.

### Iconography

Lucide line icons, 1.5 to 2 px stroke, white, never filled, usually inside a ringed well. No emoji, no multicolour icons.

### Background treatments

- Flat black, edge to edge.
- Occasional soft radial glow (violet at the bottom of a section; warm amber behind a project image).
- Edge-fade masks on scrolling content: `linear-gradient(to right, transparent, black 5%, black 95%, transparent)` and a vertical equivalent at 15% and 85%, so marquees and testimonial columns dissolve into the black instead of being cut off.
- A very faint dot grid: `radial-gradient(circle at center, #ffffff05 1px, transparent 0)`.

---

## 8. Spacing and layout (observed)

- 4 px base grid (Tailwind). Common paddings: 4×12, 4×14, 12×24 (buttons), 12×16 (inputs), 64 px (footer).
- Content is centred with generous vertical air: sections are 600 to 1,200 px tall on desktop with headings near the top.
- Section pattern is consistent: eyebrow pill → italic serif heading → one short grey paragraph → content grid or a single button.
- Grids: a 6-column bento for features (cards span 2 or 3), two-column alternating text and media for services, four masonry columns for testimonials.

---

## 9. Animation and transitions

### 9.1 CSS (observed)

| Property | Value |
|---|---|
| Default duration | 150 ms (most common), then 300 ms and 500 ms; 200 ms, 700 ms and 1 s appear once or twice |
| Default easing | `cubic-bezier(0.4, 0, 0.2, 1)`; `cubic-bezier(0, 0, 0.2, 1)` for ease-out |
| Keyframes | `orbit` (icons circling), `pulse` (2 s), `spin`, `accordion-down` / `accordion-up` (200 ms ease-out), `enter` / `exit` |
| Scroll | `html { scroll-behavior: smooth }` |

### 9.2 Scripted motion (observed in the bundle)

| Pattern | Occurrences | Settings |
|---|---|---|
| Fade and rise on scroll | 26 `whileInView` reveals | from `opacity 0, y 20 to 30 px` to `opacity 1, y 0` |
| Scale-in | 9 | from `opacity 0, scale 0.95` |
| Blur-in | 2 | from `blur(10px), opacity 0, y 20` |
| Typical timing | 20 of 31 easings | `duration 0.8 s`, `ease [0.25, 1, 0.5, 1]` (a soft "expo-out"), staggered with 0.2 s and 0.4 s delays |
| Secondary timing | 7 | `duration 0.5 s`, `ease [0.25, 0.1, 0.25, 1]` |
| Micro-interactions | few | `0.15 s` and `0.22 s ease-out`; one spring `stiffness 300, damping 20`; press `scale 0.95`; hover `y −5` or `scale 1.08` |
| Replay | 24 of 29 | `viewport: { once: false }`, so reveals replay when scrolled back into view |
| Marquee | 1 | 40 s linear infinite loop |

### 9.3 The intro overlay (observed)

On every full page load a WebGL shader paints a cluster of vertical light bars in white, blue and amber across the centre of the screen, with wide soft falloff, while page content fades up underneath. It takes several seconds to clear on desktop (`assets/esyai-21-intro-loader.png`, and visible mid-fade in `assets/esyai-17-contact-top.png`).

### 9.4 Motion character (inferred)

Slow, soft and vertical. Things rise 20 to 30 px and settle with a long ease-out; nothing bounces except one spring. The 0.8 s reveal is right for a marketing page and far too slow for an application, which is addressed in section 12.

---

## 10. Responsive behaviour

**Observed**

- Breakpoints are Tailwind defaults: 640, 768, 1024, 1280 and 1536 px.
- At a 500 px window the home page grows from 7,374 px to 9,690 px tall. The features section goes from 942 px to 2,132 px (bento collapses to one column), services from 1,173 px to 1,561 px, team from 810 px to 1,356 px.
- The nav pill collapses to wordmark plus hamburger; the opened menu stacks links vertically inside the same pill (the header's border radius animates when it opens).
- The nav CTA halo and some decorative layers are hidden below 640 px (`hidden sm:block`).
- Viewport meta allows zoom up to 5×.

**Not captured**

- A clean phone-width screenshot. Both narrow captures (`assets/esyai-19-…`, `assets/esyai-20-…`) were taken while the intro overlay was still covering the page, so small-screen layout facts above come from DOM measurements rather than pictures. This does not affect EsyType, which is a desktop app.

---

## 11. Consistency notes

Observed while inspecting; none block EsyType.

1. The social card uses a plain sans "EsyAI" while the site wordmark is italic serif "EsyAI."
2. `<link rel="canonical">`, `og:url` and `twitter:url` all point to `https://esyai.com` although the site was served from `esyai.co.uk`.
3. Inter 600 is requested from Google Fonts but no element on the captured pages uses it.
4. The site loads a third-party analytics script. EsyType must not inherit that: the product promise is no telemetry.
5. `--background` is `#050505` but `body` renders `#000000`. Treat pure black as the canonical base.

---

## 12. Recommendations for applying the ESYAI identity to EsyType

### Carry over unchanged

- **Black base, white type, opacity-based hierarchy.**
- **Instrument Serif italic for display moments**, with tight tracking and a closing full stop: the wizard welcome, page titles, empty states, the Notetaker "Coming Soon" page. Example: *"Speak. It types."*
- **Barlow for all interface text.**
- **The hairline glass edge** (`.liquid-glass::before`). This is the brand's signature and it is cheap to render, because it is a masked gradient, not a blur.
- **Pills** for buttons, chips, the nav-style segmented controls and the recording widget.
- **Violet `#8350E8` as the single accent**: focus, selection, the active recording state, progress.
- **Lucide line icons** in ringed wells.
- **Eyebrow pill → serif heading → grey sentence** as the page header pattern.

### Adapt for a desktop application

| Website behaviour | Problem in an app | EsyType adaptation |
|---|---|---|
| Body text in Barlow 300 at white 60% | Thin and low-contrast at 13 to 14 px on 100%-scale laptop screens | Body in Barlow 400; minimum text colour white 64% (about `#A3A3A3`, 8.3:1 on black); 500 for labels |
| Placeholder at white 40% (`#666`, 3.7:1) | Below WCAG AA for text | Placeholders at white 50% minimum; never use below 50% for anything that must be read |
| 60 to 88 px headings | No room in a 1,000 px window | Display scale of 28, 36 and 44 px, same italic serif and proportional tracking (about −0.025 em) |
| 0.8 s reveals with 0.2 to 0.4 s staggers, replaying on scroll | Feels sluggish on the hundredth use | 120 to 220 ms for UI state changes using the site's own `cubic-bezier(0.4, 0, 0.2, 1)`; keep the 0.5 to 0.8 s `[0.25, 1, 0.5, 1]` rise for first-run and page-level entrances only; never replay |
| `backdrop-filter: blur(50px)` on buttons | Expensive on integrated GPUs; this dev PC has Iris Xe | Let Windows provide the big blur (Mica or Acrylic behind the window) and keep CSS blur to small, static surfaces at 12 to 20 px; the hairline edge carries the look where blur is off |
| Pure black everywhere | With a translucent window, pure black hides the material | Window tint of black at roughly 55 to 70% over the system material, with opaque `#0D0D0D` fallback when the material is unavailable |
| Fully rounded cards up to 4 rem | Wastes space in dense settings lists | 16 px for panels, 12 px for rows and inputs, pills for controls |
| Marquee, orbit, sparkles | Decorative motion distracts while dictating | Not used in the app |

### Turn the brand motif into the product's signature

The ESYAI favicon and intro animation are fields of thin vertical bars with soft falloff in white, blue and amber. A live audio waveform is the same shape. EsyType's floating recording pill should render its waveform in that exact style: thin vertical bars, brightest at the centre, fading at the edges with the site's edge-fade mask, white while listening, with the blue-to-amber tint from the favicon appearing as input level rises and violet reserved for the processing state. That makes the one piece of EsyType the user sees most often an animated version of the ESYAI mark, and it is something no competitor's widget has.

### Name and wordmark

- Write the parent brand as **EsyAI** in product UI, matching the site.
- Set the product wordmark as **"EsyType."** in Instrument Serif italic with the full stop, mirroring "EsyAI."
- App icon direction: the fluted-bar field from the favicon, with the bars shaped as a short waveform. To be designed in the design-system phase.

---

## 13. Screenshot index

All in `docs/research/assets/`. Desktop captures are 2854×1614 px (1427×807 at 2×).

| File | Shows |
|---|---|
| `esyai-01-home-hero.png` | Nav pill, hero eyebrow, 88 px headline, glass and text buttons, chat launcher |
| `esyai-02-home-process.png` | "How It Works" section pattern |
| `esyai-03-home-services-a.png`, `-04-…-b.png` | Alternating text and media rows, media wells with glow |
| `esyai-05-home-features.png` | Bento cards, icon wells, card typography |
| `esyai-06-home-marquee.png` | Logo marquee with edge fade |
| `esyai-07-…-testimonials-a.png`, `-08-…-b.png` | Testimonial cards, masonry columns, vertical fade mask |
| `esyai-09-home-contact.png`, `-10-home-footer.png` | Contact call to action, footer |
| `esyai-11-services-top.png`, `-12-services-scrolled.png` | Services page hero and service cards with tags and chips |
| `esyai-13-projects-top.png`, `-14-projects-scrolled.png` | Projects page |
| `esyai-15-blogs-top.png`, `-16-blogs-scrolled.png` | Blog index cards |
| `esyai-17-contact-top.png`, `-18-contact-scrolled.png` | Contact form: inputs, labels, select, info rows (intro overlay still fading in `-17`) |
| `esyai-19-narrow-home-hero.png`, `-20-narrow-home-features.png` | 500 px window, covered by the intro overlay (kept as a record of the overlay at narrow width) |
| `esyai-21-intro-loader.png` | The WebGL fluted-bar intro overlay |
| `esyai-favicon.png`, `esyai-og-image.png` | Brand mark and social card |

The team section was not captured because it is portrait photography rather than interface design.
