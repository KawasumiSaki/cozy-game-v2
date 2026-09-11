# Interaction

## Every clickable has four states

Hover, focus-visible, active, disabled. If you can't draw all four, the element isn't done.

```css
.btn {
  /* default */
}
.btn:hover  { /* lighten 4% or shift accent */ }
.btn:focus-visible { outline: 2px solid var(--accent); outline-offset: 2px; }
.btn:active { transform: translateY(1px); }
.btn:disabled { opacity: 0.5; cursor: not-allowed; }
```

Use `:focus-visible`, not `:focus`. The plain `:focus` rule lights up on mouse clicks too, which most designs don't want.

## Cursor pointer on buttons (and only on buttons)

If it's clickable, `cursor: pointer`. If it's not, plain cursor. Don't put `cursor: pointer` on disabled buttons (use `not-allowed`). Don't put it on links inside text (browsers do that automatically).

If you used a `<div>` with `onClick`, fix that first — use a `<button>`. Then the cursor is automatic.

## Touch targets ≥ 44 × 44 px

Apple HIG and Material both agree. If your icon button is 24×24, give it 10–14px of invisible padding to hit 44px.

```css
.icon-btn {
  width: 44px;
  height: 44px;
  padding: 10px; /* visual is 24x24 */
}
```

Mobile menus, close buttons, table-row actions are the worst offenders.

## Keyboard works or it ships broken

Every interactive element must be reachable with Tab and operable with Enter/Space. Test by unplugging your mouse.

- Tab order should follow visual order. If your CSS reorders things visually (grid placement, flex order), check the tab order didn't get weird.
- Skip-to-content link at the top of the page if there's a heavy nav.
- Modals trap focus when open; close on Escape; return focus to the trigger.
- Menus and dropdowns: arrow keys to navigate, Enter to select, Escape to close.

## Forms

- Label every input. `<label htmlFor>` or `aria-label`. "Placeholder is not a label."
- Validate on blur, not on every keystroke (annoying). Show success state with green.
- Error messages: red text below the input + `aria-describedby` link. Not a tooltip.
- Submit button: `disabled` until form is valid, OR allow submission and show errors. Pick one. Don't disable silently with no explanation.
- Pre-fill what you can. Auto-detect city from zip. Auto-format phone numbers.

## Loading

- **Skeleton** for content that has a known shape (cards, table rows). Match the layout you're replacing.
- **Spinner** for actions with unknown duration but inside a known control (button, modal).
- **Progress bar** when you can compute progress.
- **Optimistic** when the operation will almost always succeed — apply the change immediately, roll back on failure.

Never combine: skeleton + spinner on the same element is redundant.

## Empty states

- Explain what would be here.
- Show the *next action* prominently. ("No projects yet — Create your first project.")
- Optional: link to docs or a sample.
- No "lorem ipsum" placeholders shipped to production.

## Tooltips and hover

- Tooltips for **icon-only** buttons (always) and **truncated text** (when overflow happens).
- Don't put critical information in tooltips. Touch users can't hover.
- Delay 500–700ms before showing on hover. Otherwise they flash as the user passes through.

## Anti-patterns

- **Spinner on save** when the operation is fast and rarely fails. Use optimistic update.
- **Disabled submit with no explanation.** Tell the user why.
- **Click targets you can't see.** Pad the icon, then move on.
- **Hover-only menus** with no keyboard equivalent.
- **Modal as the default container** for anything secondary. Try inline editing, sheets, popovers first.
