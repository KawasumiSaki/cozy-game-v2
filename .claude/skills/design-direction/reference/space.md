# Space

## The 4/8 rule

Every spacing value is a multiple of 4px. Use 8px increments for most things, 4px for tight inner padding. Tailwind's default scale already enforces this — if you find yourself writing `px-[13px]`, stop.

```
4 8 12 16 24 32 48 64 96 128 192
```

## Hierarchy via space, not lines

Whitespace separates groups better than borders. Before reaching for a `<hr>` or a card border, try doubling the margin. If 2× space doesn't separate the groups visually, then add a border — but it's usually unnecessary.

Rule of thumb: **section gap ≥ 2× component gap ≥ 2× element gap**.

```
Element gap (inside a component):    8–16px
Component gap (between components):  24–48px
Section gap (between sections):      64–128px
```

## Empty space is content

For marketing/landing: above-the-fold should be ≥30% empty space. Headlines breathe; CTAs sit alone.

For dashboards: density is higher. Section gaps drop to 16–24px. Component gaps drop to 8–12px. But never zero — adjacent components without space read as one component.

## Container queries > media queries (for components)

A media query asks "how big is the window?" A container query asks "how big is my container?" For components that get placed in different contexts (sidebar, main column, modal), use container queries.

```css
.card { container-type: inline-size; }

@container (min-width: 400px) {
  .card { display: flex; gap: 1rem; }
}
```

Tailwind v4 supports `@container` syntax. Use it for cards, navs, and anything that travels.

## Grids — be intentional

Two anti-patterns to refuse:

1. **The 3-card identical grid for "Features."** If every feature is identical visually, the design is saying they're all the same. Vary card heights, give one feature visual priority, or switch to a different pattern (stacked, alternating).
2. **The 12-column grid as religion.** Use a grid when there's actually a grid (data tables, image galleries). For most marketing, asymmetric flow with `max-width` and `margin: auto` reads better than rigid 4-3-5 splits.

## Padding ratios

For buttons, cards, modals — internal padding ratios reveal the hand of a designer.

- Buttons: `py: 8–12, px: 16–24` (px ≥ 2× py).
- Cards: `p: 24` standard, `p: 32–48` for marketing emphasis.
- Modals: `p: 32` at min, `p: 48–64` for editorial weight.

## Anti-patterns

- **Cards inside cards inside cards.** A card is a container. If you're nesting, the inner card should be a different visual element (an inset panel, a divider, or just spacing).
- **`gap: 4px` between major sections.** That's not separation; that's a layout bug.
- **Borders on every container.** Borders are a tax. Use them when a border is the answer (data table rows, segmented controls); use space everywhere else.
- **Flush-to-edge content on mobile.** Always 16–24px gutter min.
