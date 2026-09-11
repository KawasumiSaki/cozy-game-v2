# Industry Rules

Category-aware design choices. Compressed from ui-ux-pro-max's 161-rule corpus into the categories that come up most often. Each section: what to lean into, what to refuse, sample tokens.

## Legal / Compliance (default for HAQQ context)

**Lean into:** trust signals, dense data layouts, conservative palette, serif body in long-form, side nav for power users, tabular numbers, audit trails visible.

**Refuse:** glassmorphism (reads as toy), purple gradients, emoji, marketing-bright accents, "click here" CTAs.

**Sample direction:** Restrained palette with one muted accent (`oklch(0.45 0.10 250)` deep blue or `oklch(0.45 0.08 30)` muted rust). Body in IBM Plex Sans or Söhne. Headings in IBM Plex Serif or GT Sectra. Density 6. Motion 2. Variance 3.

## Fintech / Banking

**Lean into:** precision (tabular numbers everywhere), data density, charts that resist clutter, security cues without theatricality.

**Refuse:** navy + gold (the cliché), emoji icons, playful illustrations, animated charts that delay reading, AI purple.

**Sample direction:** Committed palette with one institutional color. Geist + Geist Mono for trade screens; Söhne + Söhne Mono for retail. Density 7 for trading, 5 for retail. Motion 1–2.

## Wellness / Meditation / Healthcare

**Lean into:** soft palettes (low chroma, near-pastel), generous space (density 2–3), slow motion (motion 1–2), rounded sans, optional dark mode for sleep-focused features.

**Refuse:** neon, heavy shadows, dense data on landing, "hustle" copy, hard right-angles everywhere.

**Sample direction:** Drenched soft green or warm sand. Söhne / Pretendard / Inter Display. 16–20px radius. Slow easing (cubic-bezier(0.16, 1, 0.3, 1)).

## Developer tools / DevOps

**Lean into:** monospace for IDs, code, hashes; dark by default; fast micro-motion; keyboard shortcuts visible; dense data.

**Refuse:** illustrated stock people, "Unlock the power of..." copy, three-card feature grids without code samples, light-only themes.

**Sample direction:** Restrained palette with a saturated accent (`oklch(0.65 0.20 140)` lime or `oklch(0.65 0.20 30)` orange). Geist Mono or JetBrains Mono. Dark default. Density 8. Motion 3.

## E-commerce

**Lean into:** imagery first, big touch targets, fast filtering, sticky cart, prominent price, social proof near the buy button.

**Refuse:** carousels for product grids (use grids), modals for product details on desktop (use side panels), three-step checkouts hiding shipping cost.

**Sample direction:** Full palette where the product imagery is the brand. Sans for everything. Density 5 on PLPs, density 3 on PDPs. Motion 3 (hover reveals, smooth add-to-cart).

## SaaS dashboard

**Lean into:** information density, sidebar nav, contextual actions, KPI cards that earn their place (not every screen), data tables with sticky headers.

**Refuse:** marketing-style hero on every dashboard page, big-number-grids that don't add up to a decision, sidebar > 240px wide, glassmorphism cards.

**Sample direction:** Restrained or committed palette. Söhne / Inter / IBM Plex Sans. Density 7. Motion 2. Tabular nums everywhere.

## Marketing / Landing pages

**Lean into:** brand expressiveness (this is where the brand shows up), variance 5–8 (asymmetric flow), one strong hero, type as art, scroll-driven reveals.

**Refuse:** three-card grids, hero metric grid without proof, "Trusted by" before the value prop, AI gradient hero.

**Sample direction:** Drenched or committed palette. Display serif + body sans pair. Density 3. Motion 5. Variance 7.

## Editorial / Long-form

**Lean into:** generous line-height (1.6+), serif body if appropriate, 65–75ch max width, pull quotes, drop caps, sparse imagery in service of text.

**Refuse:** sidebars next to body copy (distraction), social sharing strips that follow scroll, "10 minute read" badges that read as performative.

**Sample direction:** Restrained, near-monochrome. GT Sectra or Söhne or PP Editorial body. Display in a quiet sans. Density 2. Motion 1.

## AI products

**Lean into:** clarity about what the AI is doing, visible processing states, drafts vs. final states, "explain this output" surfaces.

**Refuse:** purple gradient (the AI cliché — even for AI products), generated avatars in testimonials, "powered by AI" copy, sparkle icons everywhere.

**Sample direction:** Restrained or drenched in an unexpected color (green, ochre, rust — not purple). Distinctive type. Density 4–5. Motion 4.

## Kids / Education / Playful

**Lean into:** bold color, spring motion with mild overshoot, illustrated mascots, oversized buttons, friendly voice, sound effects (optional).

**Refuse:** "fun" pastels that look infantilizing, Comic Sans, generic clipart, claustrophobic density.

**Sample direction:** Full palette with bold accents. Hand-drawn or geometric display. Geist or Quicksand body. Density 3. Motion 6 (with reduced-motion fallback). Variance 7.

## Brutalist / Editorial-extreme (when the brief calls for it)

**Lean into:** raw type (Helvetica, Times, Courier), asymmetric grids, bold color blocks, visible borders, "this is a website, not an app" framing.

**Refuse:** softening it back toward generic SaaS as you build.

**Sample direction:** Two-color palette (one bold, one neutral). System fonts or one bold custom. Density varies wildly across sections. Motion 1–2. Variance 9–10.

---

## When in doubt

Look at three real products in the category that you admire. Steal their *thinking*, not their pixels. Articulate what they got right ("Linear uses one accent and lets density do the work") and apply that pattern to the new brand.
