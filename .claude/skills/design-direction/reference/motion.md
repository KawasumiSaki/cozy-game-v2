# Motion

## Easing — never use `ease` or `ease-in-out` as default

Browser-default `ease` is rounded and lifeless. `ease-in-out` is symmetric and feels mechanical. Better defaults:

```css
/* Out-quad — for UI entrances and most things */
--ease-out: cubic-bezier(0.22, 1, 0.36, 1);

/* Out-expo — for emphatic reveals */
--ease-out-emphatic: cubic-bezier(0.16, 1, 0.3, 1);

/* In-out for things that have to come back where they started */
--ease-in-out: cubic-bezier(0.65, 0, 0.35, 1);

/* In-quad — for exits (rare; usually fade) */
--ease-in: cubic-bezier(0.64, 0, 0.78, 0);
```

Avoid `cubic-bezier` with overshoot (bounce, elastic) for anything productivity-oriented. Reserve those for playful brands (Duolingo, kid-facing apps).

## Duration

- **Micro-interactions** (hover, focus): 100–150ms
- **Transitions** (tab change, accordion): 200–250ms
- **Reveals** (modal entry, page transition): 300–450ms
- **Orchestrated** (multi-step intro, marketing): 500–800ms

Anything over 800ms is a movie, not a UI. The user is waiting.

## Springs for tactile

Springs feel physical. Use them for drag handles, sheets that come up from the bottom, anything the user feels they're touching. Framer Motion's defaults are good (`spring`, no overshoot).

Don't spring everything. A modal entering on a spring with overshoot looks like a toy.

## prefers-reduced-motion is non-negotiable

Wrap any non-essential motion:

```css
@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after {
    animation-duration: 0.01ms !important;
    transition-duration: 0.01ms !important;
  }
}
```

Or in JS frameworks, check `useReducedMotion()` and bail to opacity-only transitions.

## Things that should always animate

- **Color changes** on hover/focus — 150ms ease-out
- **Layout shifts** when an item is added/removed to a list — FLIP or `view-transition`
- **Loading state changes** — fade in 200ms, never pop
- **Disabled → enabled** — fade, don't pop

## Things that should never animate

- **Page-load skeleton replacement.** Snap-replace, don't crossfade — crossfade reads as flicker.
- **Tab content swap** that takes >100ms (just snap; the user is waiting).
- **Toast notifications dismissing** with bounce. Slide-down + fade.

## Scroll-linked animation

`scroll-driven animations` are now CSS-native (Chrome, Safari TP). Use them for parallax, progress bars, scroll-snap accents. Don't gate on JS.

```css
@keyframes fade-in { from { opacity: 0 } to { opacity: 1 } }
.hero { animation: fade-in linear; animation-timeline: scroll(); animation-range: entry 0% cover 30%; }
```

## Anti-patterns

- **Page-load bounce** (welcome to whimsy hell).
- **Sequential text reveal** (typewriter effect on body copy — user can't read).
- **Hover scale-up of every card.** A whole grid lifting on mouseover is busy.
- **`ease-in-out` on micro-interactions.** Symmetric easing feels slow.
- **Long parallax** that delays scroll past the hero. Users scroll to leave the hero.
- **Confetti** on save. Unless you're a wedding app.
