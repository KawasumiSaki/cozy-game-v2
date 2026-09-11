# UI/UX Review Checklist

Use this checklist after every design or redesign. Check every item — nothing is optional.

## Structure

- [ ] Page title removed if navigation already provides context (sidebar, tab bar, breadcrumb)
- [ ] Information hierarchy is clear: primary -> secondary -> tertiary
- [ ] Related items are grouped visually (proximity, shared surface, or section label)
- [ ] All spacing comes from the grid (multiples of base unit)
- [ ] No orphaned elements — everything belongs to a logical group
- [ ] Content flows naturally — no unnecessary containers or wrappers
- [ ] Empty states are designed (not just missing content)
- [ ] Loading states are designed (skeleton or minimal indicator)

## Color

- [ ] Maximum 3 text colors used across the screen (primary, secondary, tertiary)
- [ ] No ad-hoc colors — every color comes from the token palette
- [ ] Accent color used ONLY for functional purposes (recording, destructive hover, critical alerts)
- [ ] Accent color used at most 1-2 places per screen
- [ ] Works in grayscale — color is never the sole differentiator
- [ ] No colored icon badges — icons are monochrome
- [ ] Hover states use subtle opacity (2-4% black), not color

## Typography

- [ ] Section headers are consistent across ALL screens: 11pt medium, UPPERCASE, tracking 1.2, textTertiary
- [ ] Body text is consistent: 13pt regular, textPrimary
- [ ] No more than 3 font sizes per visual section
- [ ] Monospaced used ONLY for numbers, versions, counts, and code
- [ ] No italic used for UI labels
- [ ] No more than 2 font weights on the same visual line
- [ ] Font sizes come from the defined scale — no arbitrary values
- [ ] Subtitle/description text is 11pt regular, textTertiary

## Spacing

- [ ] Row horizontal padding: unit * 2
- [ ] Row vertical padding: unit * 1.75
- [ ] Page/scroll view padding: unit * 3
- [ ] Between section groups: unit * 5
- [ ] Section label to content: unit * 1.5
- [ ] Icon to text gap: unit * 1.5
- [ ] Divider indent: unit * 5.5 (past icon column)
- [ ] No divider after the last item in a list

## Icons

- [ ] Row icons: 14pt regular, 20px frame
- [ ] Action icons (hover): 11pt regular
- [ ] Chevron right (navigation): 9pt medium
- [ ] Chevron up/down (dropdown): 9pt regular
- [ ] External link indicator: 10pt arrow.up.right
- [ ] All icons use textSecondary or textTertiary — never textPrimary (unless selected state)

## Interaction

- [ ] High-frequency actions always accessible (e.g., copy as margin marker)
- [ ] Secondary actions hidden until hover (edit, delete, re-process)
- [ ] Destructive actions require confirmation dialog
- [ ] Hover states use transitionFast (0.15s) timing
- [ ] Content transitions use transition (0.2s) timing
- [ ] All animations use easeInOut curve — no spring, no bounce
- [ ] Interactive elements have `contentShape(Rectangle())` for full hit area
- [ ] Buttons use `buttonStyle(.plain)` — no system chrome
- [ ] Text fields use `textFieldStyle(.plain)` — no system chrome

## Components

- [ ] Toggles scaled to 0.8 and tinted black
- [ ] No system button chrome visible
- [ ] No system text field chrome visible
- [ ] Dividers use borderSubtle (4% opacity), not border (8%)
- [ ] Container outlines use border (8% opacity)
- [ ] Grouped sections use surfaceElevated or surface background with border overlay
- [ ] No drop shadows anywhere — use border + surface hierarchy
- [ ] Corner radius uses continuous style (`.continuous`)
- [ ] No Capsule() for buttons — always RoundedRectangle

## Consistency Across Screens

- [ ] Same section header style on every screen
- [ ] Same row padding on every screen
- [ ] Same page padding on every screen
- [ ] Same icon sizing on every screen
- [ ] Same animation timing on every screen
- [ ] Same hover behavior for same type of interaction
- [ ] Same empty state pattern (text only, no illustration)
- [ ] Same button styling (primary: white on black, compact)
- [ ] Same divider style (borderSubtle, indented past icons)

## Layout

- [ ] Sidebar uses surfaceRecessed background
- [ ] Content area uses surface (white) background
- [ ] Sidebar width is fixed (248pt)
- [ ] Sidebar has trailing border line
- [ ] Content scrolls independently from sidebar
- [ ] No animated gradient backgrounds — solid surfaces only

## Accessibility

- [ ] Touch targets minimum 44pt on iOS
- [ ] Color is not the sole means of conveying information
- [ ] Text contrast ratios meet WCAG AA (textPrimary on surface = passes)
- [ ] Interactive elements have appropriate labels
- [ ] Focus states are visible (keyboard navigation)

## Performance

- [ ] No unnecessary view redraws
- [ ] LazyVStack for long lists (not VStack)
- [ ] Solid colors preferred over gradients
- [ ] System fonts preferred over custom fonts
- [ ] Animations are lightweight (opacity, position — not complex geometry)

---

## Quick Audit — 6 Questions

If you only have time for a quick review, answer these:

1. **Can I remove anything without losing functionality?** If yes, remove it.
2. **Do all section headers look identical?** If not, fix them.
3. **Are there more than 3 text colors?** If yes, reduce.
4. **Is any spacing not a multiple of 8?** If yes, fix it.
5. **Are there any drop shadows?** If yes, replace with borders.
6. **Does this screen look like the others in the app?** If not, make it consistent.
