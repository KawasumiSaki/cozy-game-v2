# Brand Protocol

Adapted from huashu-design's Core Asset Protocol. The rule: **never design blank-slate for a real brand without grounding in their actual assets.**

## The five steps

### 1. Ask

If the brand is real (a known company, the user's own product, a client):

> "Do you have a brand-spec, logo file, color tokens, or typography choices I should use? If not, where can I find them — Figma file, website, brand book?"

If the brand is hypothetical (a portfolio piece, a test, a learning exercise): skip to step 4 and propose three directions.

### 2. Search official channels

For a real brand, find the canonical materials before designing:

- The company's own website (download SVG logos from the press kit or footer)
- The company's design system docs if public (Stripe, Atlassian, Shopify, etc. publish theirs)
- The company's GitHub for design tokens (`tokens.css`, `brand.json`)
- The user's local files (`Documents/`, `Downloads/`, vault notes)

WebSearch if needed. Do not fabricate official assets. Coca-Cola's red is `oklch(0.55 0.28 27)` — find it; don't guess.

### 3. Download by asset category

For each asset, get the canonical version:

- **Logo:** SVG (or PNG at ≥2× the largest expected use). Light and dark variants.
- **Wordmark/Lockup:** SVG.
- **Color tokens:** OKLCH preferred; HEX as fallback. Primary, secondary, neutrals, semantic.
- **Typography:** Font files or Google Fonts/Adobe Fonts names. Include weights and any variable axes.
- **Imagery direction:** "Photographic / illustrated / 3D / abstract" + 1–2 reference URLs.
- **Voice:** 3 adjectives ("authoritative, plain, optimistic"). 1 example sentence.

### 4. Verify authenticity

Cross-check at least one source. If three places agree on the brand color, it's the brand color. If two say `#FF6B00` and one says `#FF6F00`, ask the user which is canonical.

For real brands, **never fabricate a logo from scratch**. If you can't find the SVG, use a labeled placeholder ("LOGO") until the user provides it.

### 5. Freeze in `brand-spec.md`

Write the result into `brand-spec.md` at the project root. This becomes the single source of truth for the rest of the session:

```markdown
# Brand spec — [project]

## Voice
3 adjectives. 1 sample sentence.

## Color (OKLCH)
- Primary: oklch(0.55 0.18 250) / #4A6CF7
- Secondary: oklch(0.85 0.05 250)
- Neutrals: oklch(0.10–0.99 0.01 250)
- Semantic: success oklch(...) / warn oklch(...) / error oklch(...)

## Typography
- Display: Söhne Breit (700)
- Body: Söhne (400, 500, 600)
- Mono: Söhne Mono (400)
- Scale: 1.25 (Major Third), body 16px

## Spacing
- 4/8 grid; section gap 64–96, component gap 24, element gap 8–16

## Radius
- 8px standard; 4px inner; 16px cards; 9999px pills

## Imagery
- Photographic, muted color grading, never illustrated stock

## Assets
- /assets/logo.svg
- /assets/logo-mono.svg
- /assets/wordmark.svg
```

Keep this updated as decisions are made. Reference it explicitly in step 2 of the design workflow.

## When the user provides a screenshot or Figma

The screenshot/Figma *is* the brand spec implicitly. Extract:

1. Three samples of the dominant color (eyedropper or `get_variable_defs` from Figma MCP) → tokens.
2. The font family and visible weights → typography.
3. Card padding, section gaps → spacing scale.
4. Radius on buttons and cards → radius scale.

Then write `brand-spec.md` from what you extracted. Confirm with the user before generating new screens.

## When there is no brand

For hypothetical or exploratory work, propose three directions in one paragraph each:

> Direction A — Drenched green editorial. Söhne Breit + Söhne. Density 4, motion 2, variance 6. Reference: Things 3 × NYT.
>
> Direction B — Restrained monochrome with one orange accent. Geist + Geist Mono. Density 7, motion 1, variance 3. Reference: Linear × Vercel.
>
> Direction C — Maximalist asymmetric. Pretendard + IBM Plex Mono. Density 5, motion 4, variance 9. Reference: PostHog × Posthog landing.

Pick one with the user. Then write `brand-spec.md` from that direction. Then build.

## Anti-patterns

- **Generating a logo for a real company** without the user's permission and clear "this is a placeholder" framing.
- **Inventing brand colors** that look "close enough" to the real ones.
- **Skipping the brand-spec** because "the task is small." Even a one-page mockup deserves 30 seconds of grounding.
- **Re-extracting the brand every screen.** Freeze it once, refer to the spec.
