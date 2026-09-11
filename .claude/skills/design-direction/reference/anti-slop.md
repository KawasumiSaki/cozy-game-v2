# Anti-slop

The catalog of patterns that read as "AI-generated" or "Webflow template." Refuse these by default. If a design contains any without justification, rework it.

## Color and gradient

- **Purple → blue gradient hero.** The signature of every AI startup template.
- **Pink → violet → cyan gradient** (the OpenAI/Anthropic-adjacent "AI gradient"). Recognized on sight.
- **Black-to-color radial behind everything.** "Hero shimmer." Cliché.
- **Pure `#000` background with neon green/cyan text.** Cyberpunk-by-Canva.
- **Gray text (`#9CA3AF`) on a colored background.** Always wrong. Tint the neutral.
- **Three accent colors competing.** Pick one.
- **Gradient text on a body paragraph.** Gradient text is for one word, one time.

## Typography

- **Inter everywhere.** It's free, modern, and inoffensive. It's also the AI default. Pick on purpose.
- **System font stack with no styling.** Looks like you forgot to apply CSS.
- **Three font sizes in a stacked hero** (big — medium — small). Reads as a billing form.
- **All-caps headings without letter-spacing.** Squished.
- **Italic for emphasis in UI** at 14–16px. Use bold or color.
- **Decorative script fonts** for product UI. Almost never the answer.

## Layout

- **Three identical "Features" cards in a row** with an icon, title, two-line description, no visual hierarchy. The unmistakable shape of slop.
- **Hero metric grid** (Big Number, Big Number, Big Number) without context. Means nothing.
- **Card-in-card-in-card nesting.** Containers must have reasons.
- **Side-stripe colored borders** on cards (4px purple left border). Bootstrap-era pattern.
- **Floating action button on every screen.** Mobile pattern misapplied to desktop.
- **"Trusted by" logo strip** with no context, often before the user knows what the product is.
- **Sticky everything.** Sticky header, sticky sidebar, sticky CTA, sticky cookie banner — no room left.
- **Centered everything.** Headlines centered, paragraphs centered, lists centered. Hard to scan.

## Components

- **Default glassmorphism** with `backdrop-blur` and 10% white. Lazy.
- **Skeuomorphic icons** (3D-shaded) mixed with flat icons.
- **Emoji as icons** in product UI. Use Heroicons / Lucide / Phosphor.
- **Neumorphic everything.** Was briefly trendy in 2020. Now slop.
- **Modal-as-first-thought** for anything secondary. Try sheets, popovers, inline editing.
- **Generic stock illustrations** (the "Storyset" / "Undraw" / "Humaaans" tells).
- **AI-generated avatars** in testimonials. People can tell.

## Motion

- **Page-load bounce.** Welcome to whimsy hell.
- **Typewriter reveal on body copy.** User can't read.
- **Hover scale-up on every card.** A whole grid lifting is busy.
- **Confetti on save.** Unless this is genuinely a celebration moment, no.
- **Parallax that delays scroll past the hero.** Users scroll to leave.
- **Bounce / elastic easing** on productivity UI.

## Copy

- **"Powered by AI."** Tell me what it does for me, not which technology you used.
- **"Unlock the power of [X]."** Copywriter-by-template.
- **"Coming soon" with no date.** If you have a date, show it; if you don't, don't tease.
- **"Lorem ipsum" shipped to production.**
- **"Click here" links.**
- **TITLE CASE ON EVERY BUTTON.**

## Category reflexes (per-industry slop)

- **Fintech** = navy + gold + serif. Tired.
- **Wellness** = sage green + cream + script font. Tired.
- **AI** = purple + black + glow. Recognized as AI design about AI.
- **Crypto** = neon + dark + 3D coins. Cliché.
- **Legal** = navy + gold + serif. Same as fintech, same problem.
- **SaaS** = blue + Inter + 3-card grid. The default.

When you find yourself reaching for the category default, ask: what would a brand in this category that refused the cliché look like? That's a stronger starting point.

## How to refuse slop

1. Notice the reflex.
2. Name it ("I was about to use the AI gradient").
3. Replace it with a justified choice ("Drenched in deep green because the brand spec says 'arboretum'").

Document the swap in your direction line (step 2 of the workflow). The user should be able to see why you didn't pick the obvious thing.
