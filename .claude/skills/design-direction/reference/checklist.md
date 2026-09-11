# Pre-delivery checklist

Run before shipping. Every item or a documented exemption.

## Accessibility

- [ ] **Contrast** — body 4.5:1, large text 3:1, UI controls 3:1. Test with browser devtools.
- [ ] **Focus-visible** — every interactive element has a visible focus ring (`:focus-visible`, not `:focus`).
- [ ] **Tab order** — logical, follows visual order. Tab through the page; check.
- [ ] **Keyboard operability** — every action reachable without a mouse. Test by unplugging the mouse.
- [ ] **Labels** — every input has a `<label>` or `aria-label`. Placeholders are not labels.
- [ ] **Color is not the only signal** — error states have icons or text, not just red.
- [ ] **Alt text** — all meaningful images. Decorative images: `alt=""`.
- [ ] **ARIA roles** for non-semantic interactive elements (custom dropdowns, tabs, dialogs).
- [ ] **Screen reader** — at least open VoiceOver on Mac and skim the page. Don't ship without ever hearing it.

## Responsive

- [ ] **375 / 768 / 1440 screenshots taken** and reviewed (Playwright or devtools).
- [ ] No horizontal scroll on mobile (`width: 100vw` is usually the culprit — use `100%`).
- [ ] Touch targets ≥ 44 × 44 px on mobile.
- [ ] Safe-area insets respected on iOS (top notch, bottom indicator).
- [ ] Container queries used where components live in multiple widths.

## Motion

- [ ] `prefers-reduced-motion` honored — non-essential motion disabled or shortened.
- [ ] No `ease` or `ease-in-out` as default. Use `cubic-bezier(0.22, 1, 0.36, 1)` or equivalent.
- [ ] No animations longer than 800ms for ordinary UI.
- [ ] No layout shift on hover/focus (test by hovering — does the page jump?).

## States

- [ ] **Hover** designed for every clickable.
- [ ] **Focus-visible** designed.
- [ ] **Active** designed (press feedback).
- [ ] **Disabled** designed — and the user can tell *why* it's disabled.
- [ ] **Loading** designed (skeleton, spinner, or optimistic).
- [ ] **Empty** designed — with next action surfaced.
- [ ] **Error** designed — what went wrong + how to fix.

## Copy

- [ ] No "lorem ipsum" left in production.
- [ ] Button labels are verbs, not "OK" / "Submit."
- [ ] Error messages explain what to do, not just what failed.
- [ ] Loading copy is specific, not "Loading..."
- [ ] Voice is consistent across the page.
- [ ] Dates and currency are formatted explicitly (no `MM/DD/YYYY` ambiguity).

## Brand

- [ ] Brand spec (or extracted brand) was used. No reflex defaults.
- [ ] Color strategy stated and held (restrained / committed / full / drenched).
- [ ] Type stance stated and held.
- [ ] Density / motion / variance dials match the spec.

## Anti-slop final pass

- [ ] No purple-blue gradient (unless brand spec says so).
- [ ] No Inter as default for everything (unless brand spec says so).
- [ ] No identical 3-card feature grid.
- [ ] No card-in-card nesting without reason.
- [ ] No gray-on-color text.
- [ ] No "Trusted by" logo strip before the value prop.
- [ ] No emoji icons (use Heroicons / Lucide / Phosphor).
- [ ] No hover-revealed primary actions.

## Technical

- [ ] No console errors.
- [ ] No console warnings worth fixing.
- [ ] Bundle size hasn't ballooned (check before/after if it matters).
- [ ] Images are sized for delivery (no 4K PNG where 800px WebP would do).
- [ ] Fonts are subset or use `font-display: swap`.
- [ ] No layout shift on initial load (CLS < 0.1).

## Documentation

- [ ] Brand spec updated if any decisions changed.
- [ ] Tokens (`tokens.css`, theme files) updated if applicable.
- [ ] Component README updated if new patterns introduced.

---

If you can't honestly check an item, either fix it or document the exemption with a reason. "Skipped focus-visible because the user said they don't care" is fine; silently shipping without focus-visible is not.
