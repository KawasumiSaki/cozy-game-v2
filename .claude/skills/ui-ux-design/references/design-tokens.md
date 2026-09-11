# Design Tokens — Complete Specification

All values are precise. Never approximate, never improvise. If a value isn't in this system, it shouldn't exist in the UI.

## Grid System

Base unit: **8pt**. All spacing is a multiple of this unit.

```
Spacing Scale:
  0.5 unit   4pt    Tight: divider padding, icon-to-text micro gaps
  0.75 unit  6pt    Compact: button vertical padding, tag padding
  1 unit     8pt    Standard: inline element spacing, icon gaps
  1.25 unit  10pt   Default: input vertical padding
  1.5 unit   12pt   Comfortable: row icon-to-text, element groups
  1.75 unit  14pt   Breathing: row vertical padding
  2 unit     16pt   Spacious: row horizontal padding, content margins
  2.5 unit   20pt   Generous: sidebar header padding
  3 unit     24pt   Section: page padding, section bottom spacing
  4 unit     32pt   Major: between content sections
  5 unit     40pt   Dramatic: between section groups
```

### Usage Rules

- Row horizontal padding: `unit * 2` (16pt)
- Row vertical padding: `unit * 1.75` (14pt)
- Page padding: `unit * 3` (24pt)
- Between section groups: `unit * 5` (40pt)
- Section label to content: `unit * 1.5` (12pt)
- Icon to text: `unit * 1.5` (12pt)
- Divider indent (past icon): `unit * 5.5` (44pt)

---

## Color Palette

Achromatic with one functional accent. Every color has a semantic name.

### Surfaces

```
surface            #FFFFFF              Primary content background
surfaceElevated    rgb(250,250,250)     Cards, grouped panels, input backgrounds
surfaceRecessed    rgb(243,243,243)     Sidebar, secondary panels, device chassis
```

### Borders

```
border             rgba(0,0,0,0.08)    Structural edges, container outlines
borderSubtle       rgba(0,0,0,0.04)    Dividers within groups, separator lines
```

### Text — 3-Tier Hierarchy

```
textPrimary        rgba(0,0,0,0.85)    Headlines, body text, primary labels
textSecondary      rgb(102,102,102)     Icons, secondary labels, descriptions
textTertiary       rgb(153,153,153)     Timestamps, counts, hints, section headers, disabled
```

**Rule**: Never introduce a 4th tier. If you need more distinction, use size or weight.

### Accent — One Only

```
accent             rgb(209,3,28)        Recording, destructive hover, critical alerts
accentSubtle       rgba(209,3,28,0.08)  Destructive action hover background
```

**Rule**: Accent is functional, never decorative. Reserved for:
- Active recording state
- Destructive action hover
- Critical system alerts
- Nothing else

### Hover States

```
hoverSubtle        rgba(0,0,0,0.02)    Sidebar buttons, navigation rows (unselected)
hoverMedium        rgba(0,0,0,0.03)    Navigation rows, interactive elements
selectedSubtle     rgba(0,0,0,0.04)    Selected sidebar item, active states
```

---

## Typography Scale

System font only. No custom typefaces.

```
Size    Weight    Design      Usage
15pt    medium    default     App name, major identity text
14pt    regular   default     Stat values, icon sizing in rows, prominent numbers
13pt    regular   default     Body text, row titles, primary content
13pt    medium    default     Selected/active row titles, emphasized labels
12pt    regular   default     Secondary text, button labels, control values, descriptions
12pt    medium    default     Primary button text
11pt    medium    default     Section headers (ALWAYS with UPPERCASE + tracking 1.2)
11pt    regular   default     Subtitles, descriptions, detail text, permission status
10pt    regular   default     Timestamps, tertiary labels, action button text
10pt    medium    monospaced  Version numbers, keyboard shortcuts
10pt    regular   monospaced  Counts, technical values
9pt     regular   default     Micro labels ("Original", "Transformed"), chevron sizing
8pt     regular   default     Small chevrons (up/down in dropdowns)
```

### Typography Rules

1. Section headers: ALWAYS `11pt .medium`, `UPPERCASE`, `tracking: 1.2`, `textTertiary`
2. Body text: ALWAYS `13pt .regular`, `textPrimary`
3. Monospaced: ONLY for numbers, versions, counts, code
4. Never use more than 2 weights on the same line
5. Never use italic for UI labels
6. String interpolation with numbers: use the surrounding text style, not monospaced

---

## Corner Radius

Continuous corner style (`.continuous`), never default circular.

```
radiusSmall    6pt     Buttons, tags, inline elements, input fields, hover backgrounds
radiusMedium   8pt     Cards, panels, grouped content, content area inset
radiusLarge    10pt    Modals, sheets, major containers
```

**Rule**: Never use `Capsule()` for buttons. Always `RoundedRectangle` with continuous style.

---

## Border

```
borderWidth    0.5pt   All structural lines — containers, dividers, separators
```

**Rule**: Never use thicker borders. If something needs emphasis, use surface color or typography weight.

---

## Animation Timing

```
transitionFast    0.15s    Hover states, selection changes, icon transitions
transition        0.20s    Content reveals, feedback messages, state changes
```

### Animation Rules

1. Always `easeInOut` curve
2. Never `spring`, `bouncy`, `linear`, or custom curves
3. Animation communicates state change — never entertains
4. Hover feedback: `transitionFast`
5. Content appearing/disappearing: `transition`
6. If removing animation doesn't hurt comprehension, remove it

---

## Icon Sizing

```
Row icons         14pt regular, 20px frame    Landmark for eye scanning
Sidebar icons     14pt (regular/medium)       20px frame, weight varies with selection
Action icons      11pt regular                Hover-revealed actions (edit, delete)
External link     10pt regular                arrow.up.right indicator
Chevron right     9pt medium                  Navigation indicator
Chevron up/down   9pt regular                 Dropdown indicator
Tiny indicators   8pt regular                 Chevron pairs in menus
Status dot        6pt                         Recording indicator (filled circle)
Radio circle      8pt                         Selection indicator (filled/stroked)
```

---

## Shadows

```
None.
```

Use border + surface color hierarchy for depth. Shadows draw unwanted attention.

---

## Implementation — SwiftUI Token Example

```swift
enum RamsDesign {
    static let unit: CGFloat = 8

    static let surface = Color.white
    static let surfaceElevated = Color(white: 0.98)
    static let surfaceRecessed = Color(white: 0.955)

    static let border = Color.black.opacity(0.08)
    static let borderSubtle = Color.black.opacity(0.04)

    static let textPrimary = Color.black.opacity(0.85)
    static let textSecondary = Color(white: 0.4)
    static let textTertiary = Color(white: 0.6)

    static let accent = Color(red: 0.82, green: 0.01, blue: 0.11)
    static let accentSubtle = Color(red: 0.82, green: 0.01, blue: 0.11).opacity(0.08)

    static let radiusSmall: CGFloat = 6
    static let radiusMedium: CGFloat = 8
    static let radiusLarge: CGFloat = 10

    static let borderWidth: CGFloat = 0.5

    static let transitionFast: Double = 0.15
    static let transition: Double = 0.2
}
```

## Implementation — CSS Custom Properties Example

```css
:root {
    --unit: 8px;

    --surface: #ffffff;
    --surface-elevated: #fafafa;
    --surface-recessed: #f3f3f3;

    --border: rgba(0, 0, 0, 0.08);
    --border-subtle: rgba(0, 0, 0, 0.04);

    --text-primary: rgba(0, 0, 0, 0.85);
    --text-secondary: rgb(102, 102, 102);
    --text-tertiary: rgb(153, 153, 153);

    --accent: rgb(209, 3, 28);
    --accent-subtle: rgba(209, 3, 28, 0.08);

    --radius-sm: 6px;
    --radius-md: 8px;
    --radius-lg: 10px;

    --border-width: 0.5px;

    --transition-fast: 0.15s ease-in-out;
    --transition: 0.2s ease-in-out;
}
```

## Implementation — Tailwind Config Example

```js
module.exports = {
    theme: {
        extend: {
            spacing: {
                'unit': '8px',
                'unit-half': '4px',
                'unit-1.5': '12px',
                'unit-2': '16px',
                'unit-3': '24px',
                'unit-4': '32px',
                'unit-5': '40px',
            },
            colors: {
                surface: { DEFAULT: '#ffffff', elevated: '#fafafa', recessed: '#f3f3f3' },
                border: { DEFAULT: 'rgba(0,0,0,0.08)', subtle: 'rgba(0,0,0,0.04)' },
                text: { primary: 'rgba(0,0,0,0.85)', secondary: '#666666', tertiary: '#999999' },
                accent: { DEFAULT: 'rgb(209,3,28)', subtle: 'rgba(209,3,28,0.08)' },
            },
            borderRadius: { sm: '6px', md: '8px', lg: '10px' },
            borderWidth: { DEFAULT: '0.5px' },
            transitionDuration: { fast: '150ms', DEFAULT: '200ms' },
        },
    },
}
```

## Implementation — React Native / Expo Example

```typescript
const RamsDesign = {
    unit: 8,

    surface: '#ffffff',
    surfaceElevated: '#fafafa',
    surfaceRecessed: '#f3f3f3',

    border: 'rgba(0,0,0,0.08)',
    borderSubtle: 'rgba(0,0,0,0.04)',

    textPrimary: 'rgba(0,0,0,0.85)',
    textSecondary: '#666666',
    textTertiary: '#999999',

    accent: 'rgb(209,3,28)',
    accentSubtle: 'rgba(209,3,28,0.08)',

    radiusSmall: 6,
    radiusMedium: 8,
    radiusLarge: 10,

    borderWidth: 0.5,

    transitionFast: 150,
    transition: 200,
} as const;
```
