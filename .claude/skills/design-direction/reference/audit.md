# Audit

When the user says "make it nicer," "polish this," or "what would you change" — this is the workflow.

## The 3-issue rule

You will find 15 things to fix. The user only needs 3. Pick the three with the highest leverage and ignore the rest. A long list of nitpicks is exhausting and signals that nothing is important.

## Workflow

### 1. Open the page

If you can take a screenshot, take one. If you can't, open the file. Look at it for 30 seconds before listing anything.

### 2. List freely (for yourself)

Internally, list every issue you'd touch. Don't filter yet. Examples:

- The hero gradient is the AI purple-blue
- The CTAs aren't differentiated (primary vs. secondary look almost identical)
- Inter is used everywhere
- The "Features" grid is the 3-card pattern with identical cards
- Body text is `#9CA3AF` on a colored card
- Hover on cards scales the whole grid up
- There's a redundant tagline above the H1
- The cookie banner overlaps the hero on mobile
- The pricing tier highlight is a side-stripe border
- Footer has 6 columns of links on mobile (overflows)

### 3. Group by impact

| Tier | What | Action |
|---|---|---|
| **Critical** | Broken — accessibility violation, layout bug, broken interaction | Fix all |
| **High-leverage** | Reads as slop, fights the brand, hurts comprehension | Pick top 3 |
| **Polish** | Minor refinement | Mention briefly or skip |

For the example list above:

- *Critical:* `#9CA3AF` on colored card (contrast fail), footer overflow on mobile, cookie banner overlap.
- *High-leverage:* AI purple-blue gradient, identical 3-card grid, undifferentiated CTAs.
- *Polish:* hover scale, redundant tagline, side-stripe border.

### 4. Fix critical + top 3 high-leverage

Always fix critical (that's not optional — it's broken). Then pick the 3 high-leverage issues that will move the design furthest with the least re-architecting.

Skip the polish list unless the user asks. If you fix everything, the user can't tell which moves mattered.

### 5. Show before/after with reasoning

Don't just ship the diff. Show:

```
1. Replaced AI purple-blue gradient with a single deep green wash.
   Why: The brand spec is "editorial, restrained" — the gradient
   was generic AI-template. The wash uses a tinted brand color
   and gives the hero a sense of place.

2. Differentiated CTAs.
   Why: Primary and secondary both used the same outlined pill.
   New: primary is filled green, secondary is link-style. The eye
   now knows where to go.

3. Restructured the "Features" grid.
   Why: Three identical cards with icon+title+description was
   the canonical slop pattern. New: one large feature with screenshot,
   two smaller cards below with text-only. Hierarchy now matches
   actual importance.
```

The reasoning is the value — not just the diff.

## Common high-leverage moves

When you don't know where to start, these almost always help:

1. **Pick a stronger color direction.** Half of "make it nicer" requests are answered by ditching the generic palette.
2. **Replace a 3-card grid** with a varied layout. Instantly less templatey.
3. **Differentiate primary and secondary actions.** Most pages have both styled identically.
4. **Tighten typography.** Better font + tighter scale + 65ch line length = 30% lift.
5. **Cut chrome.** Borders, shadows, gradients you don't need.
6. **Increase whitespace.** Most "looks cluttered" complaints are solved with 2× margins.
7. **Replace stock illustrations** with something authored (real screenshots, brand photography, custom SVG, or nothing).
8. **Fix the empty / loading / error states.** They almost always exist and are almost always slop.

## When to push back

If the user asks for "polish" and the design is fundamentally broken (wrong color direction, wrong type system, wrong info hierarchy), don't polish — propose a re-direction. Polish on a flawed foundation is wasted work.

Format:

> "Three things would move this furthest, but they're more than polish — they're a small re-direction. (1) Color: the purple is fighting the brand. (2) Type: Inter is leaving energy on the table. (3) Hero: the metric grid doesn't pay off the headline. Want me to propose a new direction (15 minutes) or keep this direction and polish what's there (5 minutes)?"

Give the user the choice.

## Anti-patterns for audits

- **A 20-item bulleted list.** Nobody will read it.
- **"Looks great!"** with no specifics. If it looks great, say *what* is great.
- **Generic suggestions** ("add more whitespace," "increase contrast"). Be specific: which whitespace, which contrast.
- **Touching everything.** Restraint is part of the audit. Leave the parts that work.
