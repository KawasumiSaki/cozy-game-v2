---
name: ui-ux-design
description: Design, redesign, review, or improve UI/UX for any screen, component, or flow using Dieter Rams' design philosophy. Use this skill when the user mentions "redesign this screen," "improve the UI," "make this more usable," "UX review," "design system," "Dieter Rams," "clean design," "minimal UI," "layout," "visual hierarchy," "information architecture," "make this more readable," "fix the spacing," "component design," or "screen redesign." Applies functional, honest, long-lasting design principles to digital products. Works with any framework (SwiftUI, React, UIKit, Flutter, etc.) but provides framework-specific component examples.
license: MIT
---

# UI/UX Design — The Dieter Rams Method

Design interfaces that are functional, honest, unobtrusive, and thorough down to the last detail. North star: **"Weniger, aber besser"** — less, but better.

## Before Designing

Read any existing design system, tokens, or style guides in the codebase first. Never introduce a second design language.

Gather context (ask if not provided):

1. **What exists** — current state, design system, platform, framework
2. **Purpose** — screen's single most important job, primary action
3. **Constraints** — features to preserve, platform conventions, accessibility
4. **Context** — how this screen relates to the app, user flow, user mental model

---

## The 10 Principles Applied to Digital Design

### 1. Innovative
Question every convention before adopting it. Solve the actual problem, not the perceived pattern.

### 2. Useful
Every element must earn its place. If removing it doesn't reduce functionality, remove it. If a label exists elsewhere (sidebar, tab bar), don't repeat it as page title.

### 3. Aesthetic
Beauty from proportion, alignment, restraint — not decoration. A mathematical grid is more beautiful than any gradient. Whitespace is a design element.

### 4. Understandable
Information architecture > visual styling. Group related items. Use progressive disclosure. If you need a tooltip, the design has failed.

### 5. Unobtrusive
Content speaks, chrome whispers. Actions on hover (unless high-frequency). Borders over shadows. Controls area (sidebar) is muted; content area is bright.

### 6. Honest
No fake depth, no skeuomorphism unless it serves comprehension. Feedback is factual (checkmark, not confetti). Disabled = clearly muted.

### 7. Long-Lasting
Monochrome + one accent ages well. System fonts at considered sizes outlast custom typefaces. Avoid trends (glassmorphism, neumorphism).

### 8. Thorough
Nothing arbitrary. Spacing from the grid. Color from the palette. Typography from the scale. Transitions from the timing tokens. Every state designed: empty, loading, error, hover, active, disabled.

### 9. Environmentally Friendly
Fewer views, simpler rendering. Solid colors over gradients. System fonts over custom fonts. Fewer choices per screen = less cognitive load.

### 10. As Little Design as Possible
If in doubt, remove. One accent color > five. Thin divider > card wrapper. Content flowing naturally > content in containers.

---

## Design System Foundation

For complete token specifications, see [references/design-tokens.md](references/design-tokens.md).

### Key Principles

**Grid**: All spacing derives from a single base unit (8pt). Never use arbitrary pixel values.

**Color**: Achromatic palette + one functional accent. Three text tiers max (primary, secondary, tertiary). Accent reserved for critical states only.

**Typography**: System font, considered sizes. Section headers: UPPERCASE + tracked. Body: consistent size. Monospaced only for numbers/code.

**Shape**: Continuous corners, never circular for containers. Three radius sizes (small, medium, large).

**Motion**: Always easeInOut. Never spring, bouncy, or linear. Animation communicates state, never entertains.

---

## Layout Patterns

### Two-Tone Layout (The Braun Pattern)

Control panel is quiet, content area is the focus. Like a Braun SK 4 or RT 20.

```
+----------+---------------------------------+
| SIDEBAR  |         CONTENT AREA            |
| (grey)   |         (white)                 |
| recessed |         bright surface          |
| navigate |         focus here              |
+----------+---------------------------------+
```

- Sidebar: recessed/muted surface
- Content: primary surface, full contrast
- Separation: thin border line or inset content (display-in-chassis effect)

### Section Grouping

Label sits outside, content grouped on a subtle panel.

```
SECTION TITLE              <- uppercase, tracked, tertiary text
+------------------------------+
|  icon  Row title      value  |   <- surface panel with border
|  - - - - - - - - - - - - -  |   <- subtle divider (indented past icon)
|  icon  Row title      value  |
+------------------------------+
```

### Content Flow (No Cards)

For lists, don't wrap each item in a card. Content flows with thin dividers.

```
Content text flowing naturally...
Jan 15, 2025

- - - - - - - - - - - - - - - -    <- thin divider (not after last item)

Another content item...
Jan 14, 2025
```

### Action Visibility Hierarchy

| Level | When | Example |
|---|---|---|
| Always visible | High-frequency, primary | Copy button as margin marker |
| On hover | Secondary | Edit, delete, re-process |
| Behind confirmation | Destructive or rare | Delete with dialog |

---

## Component Patterns

For complete component library with code examples, see [references/component-library.md](references/component-library.md).

### Row Anatomy

```
+-----------------------------------------------+
| [icon 14pt]  Title 13pt         [accessory]   |
|              Subtitle 11pt                    |
+-----------------------------------------------+
```

- Icon: 14pt, secondary color, 20px frame (landmark for scanning)
- Title: 13pt regular, primary color
- Subtitle: 11pt regular, tertiary color
- Padding: horizontal 2 units, vertical 1.75 units
- Accessory: right-aligned (toggle, chevron, value, button)

### Key Variants

- **Navigation Row**: + chevron.right + optional detail text + hover background
- **Toggle Row**: + scaled toggle (0.8) at trailing edge
- **Selection Row (Radio)**: filled/empty 8px circle + title weight changes on select
- **Action Row**: hover-to-reveal icon buttons (edit, delete)

### Other Components

- **Status Line**: instruction left + compact stats right, in bordered container
- **Buttons**: plain style always, black fill for primary, no system chrome
- **Menu/Dropdown**: inline value + chevron, no border on trigger
- **Search**: icon + plain text field in bordered container
- **Empty State**: just text, no illustrations, no emoji

---

## Information Architecture — 5 Questions

Before styling, answer these:

1. **What is the single most important thing on this screen?** Everything else subordinate.
2. **What can be removed without losing function?** Titles duplicating nav, decorative icons, obvious labels.
3. **What can be hidden until needed?** Edit controls, secondary actions, advanced options.
4. **What is the natural reading order?** Top-left = identity, top-right = status, center = content, bottom = actions.
5. **How do similar screens in this app work?** Consistency is non-negotiable.

---

## Anti-Patterns

| Don't | Do Instead |
|---|---|
| Drop shadows for depth | Border + surface hierarchy |
| Card per list item | Content flow + thin dividers |
| Icon badges (colored circles) | Inline monochrome icons |
| Full-width buttons in lists | Compact right-aligned buttons |
| Spring/bouncy animations | easeInOut, purposeful |
| Multiple accent colors | One functional accent |
| Gradient backgrounds | Solid surfaces |
| System button/field styles | Plain styles + custom styling |
| Decorative illustrations in empty states | Honest text only |
| Color-coded status | Monochrome + one accent for critical |
| Page titles duplicating nav | Remove — nav provides context |
| Thick separators | 0.5pt borders, subtle opacity |
| Heavy font weights for emphasis | Position/surface hierarchy |
| Modals for every action | Inline editing, hover actions |
| Arbitrary pixel values | Grid-derived spacing only |

---

## Redesign Process

### Step 1: Read Everything
Read all files involved. Understand every feature, state, edge case. Never redesign what you don't understand.

### Step 2: Map Information Architecture
List every piece of information and action. Categorize: **Essential** (visible immediately), **Important** (visible but secondary), **Available** (on demand), **Removable** (delete it).

### Step 3: Define Hierarchy
Use: position (top-left = most important), size, weight (medium > regular), color (primary > secondary > tertiary), space (more space = more importance).

### Step 4: Apply Existing Patterns
Don't invent new patterns. Reuse: grouped list → SettingsGroup, content list → flow with dividers, status → StatusLine, selection → radio row, actions → hover-to-reveal.

### Step 5: Verify Consistency
Check every other screen. Section headers identical, spacing values match, components reused, typography respected.

### Step 6: Build and Verify
Build after every change. Design doesn't exist until it compiles and renders.

---

## Review Checklist

For the complete review checklist, see [references/review-checklist.md](references/review-checklist.md).

Quick check:
- [ ] No arbitrary spacing — everything from grid
- [ ] Max 3 text colors (primary, secondary, tertiary)
- [ ] Section headers consistent across ALL screens
- [ ] Actions hidden until hover (except high-frequency)
- [ ] No system button/field chrome
- [ ] Same patterns for same purposes everywhere

---

## Platform Notes

**macOS**: Hover states essential (replace touch feedback). `onHover {}` for interactivity. Minimal window chrome.

**iOS**: No hover — actions visible or behind swipe/tap. Tab bar replaces sidebar. Touch targets min 44pt.

**Web**: Hover + click. CSS custom properties for tokens. `prefers-reduced-motion` for accessibility.

**Cross-platform**: Keep information architecture identical. Adapt interaction model (hover vs. tap), not hierarchy.

---

## Braun Reference

| Product | Design Lesson |
|---|---|
| **SK 4** (player) | Control panel quiet, content area is focus |
| **RT 20** (radio) | Two-tone: each zone has one function |
| **ET 66** (calculator) | Display inset into chassis, perfect grid |
| **T 1000** (radio) | Information density through hierarchy, not decoration |
| **ABW 21** (clock) | Nothing to remove — pure function as form |
