# Color

## Color spaces — use OKLCH

OKLCH is perceptually uniform. Two OKLCH colors with the same L look equally bright; HSL doesn't have that property. Use OKLCH for any palette work that goes beyond "pick a vibe from Coolors."

```css
:root {
  --accent: oklch(0.65 0.18 250);     /* L chroma hue */
  --accent-hover: oklch(0.60 0.20 250);
  --accent-bg: oklch(0.97 0.02 250);
}
```

Tailwind v4 supports OKLCH natively. Use it.

## Tint your neutrals

Pure `#000` and `#ffffff` look harsh and disconnected. Neutrals should pull toward the primary hue with low chroma.

- Primary at `oklch(0.55 0.15 250)`
- Neutrals at `oklch(0.10–0.99 0.01–0.02 250)` (same hue, near-zero chroma)

Result: blacks and grays feel related to the brand, not generic.

## The four color strategies

Pick one per design. State it in step 2.

1. **Restrained** — neutrals everywhere, one accent only. Used by Stripe, Linear, most enterprise.
2. **Committed** — one color carries 30–60% of the surface. Used by Apple Music, Notion (when in a workspace color).
3. **Full palette** — 3–5 colors with assignments (success/warn/error/info/brand). Used by most dashboards.
4. **Drenched** — one hue saturates the entire UI; backgrounds, type, accents are all variations of that hue. Used by Things 3, modern marketing pages.

## Contrast minimums

- Body text: **4.5:1** vs background (WCAG AA)
- Large text (≥18px or ≥14px bold): **3:1**
- UI controls (focus rings, button outlines): **3:1** vs adjacent colors
- Disabled state: still ≥3:1 if it carries meaning the user must read

Verify with browser devtools (the contrast checker in inspector) or `pa11y` / `axe`.

## Anti-patterns

- **Gray text on saturated backgrounds.** Use a tinted near-white instead — `oklch(0.95 0.02 [hue])`.
- **Pure `#000` body text.** Use `oklch(0.20 0.01 [hue])` or similar. Easier on the eye.
- **Reflex purple-blue gradient.** Forbidden as a default. Earn the gradient by tying it to something semantic (a fade, a state).
- **AI pink-violet-cyan.** Recognized as AI slop on sight. Avoid.
- **Three accent colors in a non-dashboard UI.** Pick one.

## Dark mode — derive from a scene

Don't invert the light theme. Picture a physical scene and let it dictate:

- "Midnight library" → warm dark `oklch(0.18 0.02 60)`, ivory text, brass accents
- "Late-night IDE" → cool dark `oklch(0.15 0.02 240)`, blue-tinted whites, neon-ish syntax
- "Studio at dusk" → warm gray `oklch(0.22 0.01 40)`, cream text, low-saturation primaries

Then build the scale from the scene's L values, not by flipping the light theme.

## Quick checks

- Squint at the page. Does the hierarchy still read? If not, contrast is wrong.
- Print to grayscale. Does the design still work? If not, you're relying on color for meaning.
- Show a colorblind simulator (Sim Daltonism or browser devtools). Red-green and blue-yellow should both pass.
