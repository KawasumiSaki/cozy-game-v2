# Typography

## Not Inter. Pick on purpose.

Inter is the default because it's free, modern, and inoffensive. That's also why every AI design looks the same. Inter is fine, but it's never the *answer*; it's the fallback when no other answer fits.

Stronger defaults to reach for first:

- **Geist** (Vercel) — modern, geometric, free. Good when "tech-forward" is the brief.
- **Söhne** / **GT America** — paid, but the gold standard for serious product UI.
- **Space Grotesk** — character without weirdness. Great for product + landing.
- **IBM Plex** — institutional, free, three subfamilies (Sans/Serif/Mono).
- **Pretendard** — Korean-tuned, but excellent Latin support. Cleaner than Inter.
- **Söhne Mono** / **Berkeley Mono** / **JetBrains Mono** — monospace with personality.
- **GT Sectra** / **Söhne Breit** / **PP Editorial Old** — display serifs that don't feel like Times.

## Pair, don't decorate

Two families max in 95% of designs. Pairing patterns that work:

- **Mono-display** — one sans for everything. Modern, restrained. (Linear, Vercel.)
- **Classical pair** — serif display + sans body. Editorial weight. (Apollo, Posthog landing.)
- **Editorial** — serif body + sans display. Rare; works for long-form reading products.
- **Utility** — sans body + mono for code/IDs/numbers. Default for dev tools and fintech.

Never three families. Never two sans-serifs that look almost the same.

## Scale — start at 1.25, go up

Body 16–18px (never below 14px for paragraph text). Modular scale step ≥1.25. Common scales:

| Step | 1.25 (Major Third) | 1.333 (Perfect Fourth) | 1.5 (Perfect Fifth) |
|---|---|---|---|
| body | 16 | 16 | 16 |
| h4 | 20 | 21 | 24 |
| h3 | 25 | 28 | 36 |
| h2 | 31 | 37 | 54 |
| h1 | 39 | 50 | 81 |
| display | 49+ | 67+ | 122+ |

Editorial designs use 1.5+. Dashboards use 1.2 (denser).

## Line length — 65 to 75 characters

For body paragraphs, target `max-width: 65ch` (Tailwind: `max-w-prose`). Longer = readers lose their place. Shorter = jumpy rhythm.

UI labels and table cells are exempt.

## Line height

- Body: **1.5–1.65**
- Headings: **1.1–1.2** (the bigger the heading, the tighter)
- UI labels: **1.0–1.2**

## Optical sizing

If your typeface has a variable `opsz` axis (Söhne, Inter, Recursive), use it. Display sizes get tighter tracking and finer details; body gets opened up.

```css
.display { font-variation-settings: "opsz" 96; letter-spacing: -0.03em; }
.body    { font-variation-settings: "opsz" 16; letter-spacing: 0; }
```

## Tabular numbers

Anywhere numbers align in columns (tables, prices, dashboards), use `font-variant-numeric: tabular-nums`. Without this, "1,234" and "1,567" don't line up.

## Anti-patterns

- **Inter as default for everything.** Already covered. Pick a typeface.
- **All-caps headlines without letter-spacing.** Add 0.05–0.10em or skip the all-caps.
- **Italic-as-emphasis in UI.** Bold or color works better at 14–16px.
- **Underline that isn't a link.** Underlines mean "click this." Don't decorate.
- **Three sizes in one heading area.** "Big — medium — small" stacks read as a billing form, not a hero.
