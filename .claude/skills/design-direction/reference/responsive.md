# Responsive

## Breakpoints — design for these widths

Don't invent your own. Use the industry-standard set:

| Width | What it is | Notes |
|---|---|---|
| **375** | iPhone SE / mid-range Android | Smallest "modern" phone — test here, not at 320 |
| **640** | Large phone / small tablet portrait | Tailwind `sm:` |
| **768** | iPad portrait | Tailwind `md:` |
| **1024** | iPad landscape / small laptop | Tailwind `lg:` |
| **1280** | Standard laptop | Tailwind `xl:` |
| **1440** | Designer monitor | Where you take your hero screenshot |
| **1920** | Full HD desktop | Make sure the design doesn't fall apart |

For Playwright verification, screenshot at **375 / 768 / 1440** minimum.

## Mobile-first means mobile-first

Write the mobile layout first. Add complexity at larger widths. Tailwind enforces this — no prefix = mobile, `md:` adds desktop.

The opposite (desktop-first with `max-width:` queries) leaves edge cases on mobile because mobile gets the last patches.

## Touch comes before mouse

- Tap targets ≥ 44 × 44 (see interaction.md)
- No hover-only affordances. Anything important must be visible without hovering.
- Long-press menus are not discoverable. Use explicit "..." menus.
- Bottom nav bars beat hamburger menus for primary navigation.

## Safe-area insets

iOS has the notch and home indicator. Wrap your layout's outer padding:

```css
.app {
  padding-top: env(safe-area-inset-top);
  padding-bottom: env(safe-area-inset-bottom);
  padding-left: env(safe-area-inset-left);
  padding-right: env(safe-area-inset-right);
}
```

Without this, the iOS home indicator overlaps your bottom nav.

## Container queries for components

When a component lives in multiple contexts (sidebar, main column, modal), use container queries instead of viewport queries. See [space.md](space.md) for syntax.

## Type fluidity

For headlines, use `clamp()` instead of stepped breakpoints:

```css
h1 { font-size: clamp(2rem, 5vw + 1rem, 4.5rem); }
```

This scales smoothly between mobile and desktop instead of jumping.

Don't fluid-size body text. Body should remain 16–18px regardless of viewport — the user already controls that with browser settings.

## What changes between breakpoints

In order of frequency:

1. **Stacking direction** — columns become rows on mobile.
2. **Visibility** — secondary nav collapses to a menu; sidebars hide.
3. **Font sizes** — only for display/headlines.
4. **Spacing** — section gaps shrink on mobile (64px → 40px).
5. **Image ratio** — 16:9 desktop hero might become 1:1 or 4:5 on mobile.

What should NOT change:

- The information hierarchy. The primary CTA stays primary.
- The brand voice. Mobile isn't "lite" — it's the main use case.
- The color palette. No "mobile theme."

## Anti-patterns

- **Designing only at 1440** and resizing the window to "check mobile." Test on a real phone or with devtools' device emulation.
- **`width: 100vw`** — causes horizontal scroll on iOS Safari due to scrollbar accounting. Use `width: 100%`.
- **Fixed widths on cards** without max-width or container queries — they spill on mobile.
- **Hover-revealed actions** on touch devices. They never appear; users never know they exist.
- **Tables that don't scroll horizontally** on mobile — squished tables are worse than overflow-scroll.
