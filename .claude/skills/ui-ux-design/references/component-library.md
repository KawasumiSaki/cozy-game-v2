# Component Library — Code Examples

Complete code examples for every component pattern. Each example uses the design token system from [design-tokens.md](design-tokens.md).

## Table of Contents

1. [Settings Group (Section)](#settings-group)
2. [Settings Row](#settings-row)
3. [Toggle Row](#toggle-row)
4. [Navigation Row](#navigation-row)
5. [Selection Row (Radio)](#selection-row)
6. [Action Button](#action-button)
7. [Status Line](#status-line)
8. [Search Field](#search-field)
9. [Inline Add Row](#inline-add-row)
10. [Inline Edit Row](#inline-edit-row)
11. [Empty State](#empty-state)
12. [Content List Item](#content-list-item)
13. [Sidebar Button](#sidebar-button)
14. [Language/Menu Picker](#menu-picker)
15. [Two-Tone Layout](#two-tone-layout)

---

## Settings Group

Section with uppercase tracked label and grouped content on surface panel.

### SwiftUI

```swift
struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: RamsDesign.unit * 1.5) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .medium))
                .tracking(1.2)
                .foregroundStyle(RamsDesign.textTertiary)

            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .background(
                RoundedRectangle(cornerRadius: RamsDesign.radiusMedium, style: .continuous)
                    .fill(RamsDesign.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: RamsDesign.radiusMedium, style: .continuous)
                    .stroke(RamsDesign.border, lineWidth: RamsDesign.borderWidth)
            )
        }
    }
}
```

### React / HTML+CSS

```tsx
function SettingsGroup({ title, children }: { title: string; children: React.ReactNode }) {
    return (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 'calc(var(--unit) * 1.5)' }}>
            <span style={{
                fontSize: 11,
                fontWeight: 500,
                letterSpacing: '1.2px',
                color: 'var(--text-tertiary)',
                textTransform: 'uppercase',
            }}>
                {title}
            </span>
            <div style={{
                background: 'var(--surface)',
                borderRadius: 'var(--radius-md)',
                border: 'var(--border-width) solid var(--border)',
            }}>
                {children}
            </div>
        </div>
    );
}
```

### Divider (inside groups)

```swift
// SwiftUI
Rectangle()
    .fill(RamsDesign.borderSubtle)
    .frame(height: RamsDesign.borderWidth)
    .padding(.leading, RamsDesign.unit * 5.5)
```

```css
/* CSS */
.settings-divider {
    height: var(--border-width);
    background: var(--border-subtle);
    margin-left: calc(var(--unit) * 5.5);
}
```

---

## Settings Row

Standard row with icon, title, and right-aligned accessory.

### SwiftUI

```swift
struct SettingsRow<Accessory: View>: View {
    let icon: String
    let title: String
    @ViewBuilder let accessory: Accessory

    var body: some View {
        HStack(spacing: RamsDesign.unit * 1.5) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(RamsDesign.textSecondary)
                .frame(width: 20)

            Text(title)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(RamsDesign.textPrimary)

            Spacer()

            accessory
        }
        .padding(.horizontal, RamsDesign.unit * 2)
        .padding(.vertical, RamsDesign.unit * 1.75)
    }
}
```

### React

```tsx
function SettingsRow({ icon, title, children }: {
    icon: React.ReactNode;
    title: string;
    children?: React.ReactNode;
}) {
    return (
        <div style={{
            display: 'flex',
            alignItems: 'center',
            gap: 'calc(var(--unit) * 1.5)',
            padding: 'calc(var(--unit) * 1.75) calc(var(--unit) * 2)',
        }}>
            <span style={{ width: 20, color: 'var(--text-secondary)', fontSize: 14 }}>{icon}</span>
            <span style={{ fontSize: 13, color: 'var(--text-primary)', flex: 1 }}>{title}</span>
            {children}
        </div>
    );
}
```

---

## Toggle Row

Row with title, optional subtitle, and trailing toggle.

### SwiftUI

```swift
struct SettingsToggleRow: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: RamsDesign.unit * 1.5) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(RamsDesign.textSecondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(RamsDesign.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(RamsDesign.textTertiary)
                }
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(.black)
                .scaleEffect(0.8)
        }
        .padding(.horizontal, RamsDesign.unit * 2)
        .padding(.vertical, RamsDesign.unit * 1.75)
    }
}
```

---

## Navigation Row

Interactive row with hover state, optional detail, and chevron.

### SwiftUI

```swift
struct SettingsNavRow: View {
    let icon: String
    let title: String
    var detail: String? = nil
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: RamsDesign.unit * 1.5) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(RamsDesign.textSecondary)
                    .frame(width: 20)

                Text(title)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(RamsDesign.textPrimary)

                Spacer()

                if let detail {
                    Text(detail)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(RamsDesign.textTertiary)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(RamsDesign.textTertiary)
            }
            .padding(.horizontal, RamsDesign.unit * 2)
            .padding(.vertical, RamsDesign.unit * 1.75)
            .background(
                RoundedRectangle(cornerRadius: RamsDesign.radiusSmall, style: .continuous)
                    .fill(isHovered ? Color.black.opacity(0.03) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: RamsDesign.transitionFast), value: isHovered)
    }
}
```

---

## Selection Row

Radio-style selection with filled/empty circle indicator.

### SwiftUI

```swift
struct SelectionRow: View {
    let title: String
    let description: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: RamsDesign.unit * 1.5) {
                Circle()
                    .fill(isSelected ? RamsDesign.textPrimary : Color.clear)
                    .frame(width: 8, height: 8)
                    .overlay(
                        Circle()
                            .stroke(
                                isSelected ? RamsDesign.textPrimary : RamsDesign.textTertiary,
                                lineWidth: isSelected ? 0 : RamsDesign.borderWidth
                            )
                    )

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                        .foregroundStyle(isSelected ? RamsDesign.textPrimary : RamsDesign.textSecondary)
                    Text(description)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(RamsDesign.textTertiary)
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(.horizontal, RamsDesign.unit * 2)
            .padding(.vertical, RamsDesign.unit * 1.5)
            .background(
                isHovered && !isSelected ? Color.black.opacity(0.02) : Color.clear
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: RamsDesign.transitionFast), value: isHovered)
    }
}
```

---

## Action Button

Compact button for secondary actions, revealed on hover.

### SwiftUI

```swift
struct ActionButton: View {
    let icon: String
    let label: String
    var isDestructive: Bool = false
    var isDisabled: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .regular))
                Text(label)
                    .font(.system(size: 10, weight: .regular))
            }
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, RamsDesign.unit)
            .padding(.vertical, RamsDesign.unit * 0.5)
            .background(
                RoundedRectangle(cornerRadius: RamsDesign.radiusSmall, style: .continuous)
                    .fill(backgroundColor)
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: RamsDesign.transitionFast), value: isHovered)
    }

    private var foregroundColor: Color {
        if isDisabled { return RamsDesign.textTertiary }
        if isDestructive { return isHovered ? RamsDesign.accent : RamsDesign.textSecondary }
        return isHovered ? RamsDesign.textPrimary : RamsDesign.textSecondary
    }

    private var backgroundColor: Color {
        if isDestructive && isHovered { return RamsDesign.accentSubtle }
        return RamsDesign.surfaceElevated
    }
}
```

---

## Status Line

Ambient information bar — instruction left, stats right.

### SwiftUI

```swift
struct StatusLine: View {
    let isRecording: Bool
    let totalWords: Int
    let savedMinutes: Int

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Left — state
            if isRecording {
                HStack(spacing: RamsDesign.unit * 0.75) {
                    Circle()
                        .fill(RamsDesign.accent)
                        .frame(width: 6, height: 6)
                    Text("Recording")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(RamsDesign.accent)
                }
            } else {
                Text("Ready")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(RamsDesign.textTertiary)
            }

            Spacer()

            // Right — compact stats
            HStack(spacing: RamsDesign.unit * 2) {
                StatUnit(value: "\(totalWords)", label: "words")
                StatUnit(value: "\(savedMinutes)", label: "min saved")
            }
        }
        .padding(RamsDesign.unit * 2)
        .background(
            RoundedRectangle(cornerRadius: RamsDesign.radiusMedium, style: .continuous)
                .fill(RamsDesign.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: RamsDesign.radiusMedium, style: .continuous)
                .stroke(RamsDesign.border, lineWidth: RamsDesign.borderWidth)
        )
    }
}

struct StatUnit: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(value)
                .font(.system(size: 14, weight: .regular, design: .monospaced))
                .foregroundStyle(RamsDesign.textPrimary)
            Text(label)
                .font(.system(size: 9, weight: .regular))
                .foregroundStyle(RamsDesign.textTertiary)
        }
    }
}
```

---

## Search Field

### SwiftUI

```swift
struct SearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: RamsDesign.unit) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(RamsDesign.textTertiary)

            TextField("Search...", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .regular))
        }
        .padding(.horizontal, RamsDesign.unit * 1.5)
        .padding(.vertical, RamsDesign.unit * 1.25)
        .background(
            RoundedRectangle(cornerRadius: RamsDesign.radiusSmall, style: .continuous)
                .fill(RamsDesign.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: RamsDesign.radiusSmall, style: .continuous)
                .stroke(RamsDesign.border, lineWidth: RamsDesign.borderWidth)
        )
    }
}
```

---

## Inline Add Row

Always-visible add input — no expand/collapse ceremony.

### SwiftUI

```swift
struct InlineAddRow: View {
    let onAdd: (String, String?) -> Void

    @State private var term = ""
    @State private var replacement = ""
    @FocusState private var focusedField: Field?

    enum Field { case term, replacement }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: RamsDesign.unit) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(term.isEmpty ? RamsDesign.textTertiary : RamsDesign.textPrimary)
                    .frame(width: 14)

                TextField("New term", text: $term)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .focused($focusedField, equals: .term)
                    .onSubmit {
                        guard !term.isEmpty else { return }
                        onAdd(term, replacement.isEmpty ? nil : replacement)
                        term = ""
                        replacement = ""
                        focusedField = .term
                    }
            }

            Spacer()

            HStack(spacing: RamsDesign.unit * 0.5) {
                Text("\u{2192}") // →
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(RamsDesign.textTertiary)

                TextField("Replacement", text: $replacement)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(RamsDesign.textSecondary)
                    .focused($focusedField, equals: .replacement)
            }
            .frame(maxWidth: 200)
        }
        .padding(.horizontal, RamsDesign.unit * 2)
        .padding(.vertical, RamsDesign.unit * 1.5)
        .background(focusedField != nil ? RamsDesign.surfaceElevated : Color.clear)
        .animation(.easeInOut(duration: RamsDesign.transitionFast), value: focusedField != nil)
    }
}
```

---

## Inline Edit Row

Click-to-edit with hover-revealed actions. View mode and edit mode in one component.

### SwiftUI (View Mode portion)

```swift
// View mode — clean, actions on hover
HStack(spacing: 0) {
    Text(term.name)
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(RamsDesign.textPrimary)

    Spacer()

    if let replacement = term.replacement {
        HStack(spacing: RamsDesign.unit * 0.5) {
            Text("\u{2192}")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(RamsDesign.textTertiary)
            Text(replacement)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(RamsDesign.textSecondary)
        }
    }

    // Actions — hover only, monochrome
    if isHovered {
        HStack(spacing: RamsDesign.unit * 1.5) {
            Button { startEditing() } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(RamsDesign.textTertiary)
            }
            .buttonStyle(.plain)

            Button { showDeleteConfirmation = true } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(RamsDesign.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, RamsDesign.unit * 2)
        .transition(.opacity)
    }
}
.contentShape(Rectangle())
.onHover { isHovered = $0 }
.onTapGesture { startEditing() }
```

---

## Empty State

No illustrations. No emoji. Just honest text.

### SwiftUI

```swift
struct EmptyStateView: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: RamsDesign.unit) {
            Text(title)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(RamsDesign.textSecondary)
            Text(subtitle)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(RamsDesign.textTertiary)
        }
        .padding(.top, RamsDesign.unit * 4)
    }
}
```

---

## Content List Item

Transcript/message row — no card, copy as margin marker, actions on hover.

### SwiftUI

```swift
HStack(alignment: .top, spacing: RamsDesign.unit * 1.5) {
    // Copy — top-left, always reachable (margin marker)
    Button {
        onCopy()
    } label: {
        Image(systemName: "doc.on.doc")
            .font(.system(size: 11, weight: .regular))
            .foregroundStyle(isHovered ? RamsDesign.textPrimary : RamsDesign.textTertiary)
            .frame(width: 16)
    }
    .buttonStyle(.plain)

    // Content column
    VStack(alignment: .leading, spacing: RamsDesign.unit) {
        Text(item.text)
            .font(.system(size: 13, weight: .regular))
            .foregroundStyle(RamsDesign.textPrimary)
            .lineSpacing(4)
            .lineLimit(3)

        HStack(spacing: 0) {
            Text(item.date.formatted(date: .abbreviated, time: .shortened))
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(RamsDesign.textTertiary)

            Spacer()

            // Secondary actions — hover only
            if isHovered {
                HStack(spacing: RamsDesign.unit * 0.75) {
                    ActionButton(icon: "waveform", label: "Re-process", action: onReprocess)
                    ActionButton(icon: "trash", label: "Delete", isDestructive: true) {
                        showDeleteConfirmation = true
                    }
                }
                .transition(.opacity)
            }
        }
    }
}
.padding(.vertical, RamsDesign.unit * 1.5)
.contentShape(Rectangle())
.onHover { isHovered = $0 }
```

---

## Sidebar Button

### SwiftUI

```swift
struct SidebarButton: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: RamsDesign.unit * 1.5) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: isSelected ? .medium : .regular))
                    .frame(width: 20)
                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                Spacer()
            }
            .foregroundColor(isSelected ? RamsDesign.textPrimary : RamsDesign.textSecondary)
            .padding(.horizontal, RamsDesign.unit * 1.5)
            .padding(.vertical, RamsDesign.unit)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: RamsDesign.radiusSmall, style: .continuous)
                        .fill(Color.black.opacity(0.04))
                } else if isHovered {
                    RoundedRectangle(cornerRadius: RamsDesign.radiusSmall, style: .continuous)
                        .fill(Color.black.opacity(0.02))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: RamsDesign.transitionFast), value: isHovered)
    }
}
```

---

## Menu Picker

Inline dropdown with value display and chevron indicator.

### SwiftUI

```swift
struct InlinePicker: View {
    let currentValue: String
    let options: [(label: String, value: String)]
    let onSelect: (String) -> Void

    var body: some View {
        Menu {
            ForEach(options, id: \.value) { option in
                Button {
                    onSelect(option.value)
                } label: {
                    HStack {
                        Text(option.label)
                        if currentValue == option.value {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(currentValue)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(RamsDesign.textSecondary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .regular))
                    .foregroundStyle(RamsDesign.textTertiary)
            }
        }
        .buttonStyle(.plain)
    }
}
```

---

## Two-Tone Layout

The Braun chassis pattern — grey frame, white content panel.

### SwiftUI

```swift
struct AppLayout<Sidebar: View, Content: View>: View {
    @ViewBuilder let sidebar: Sidebar
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 248)
                .background(RamsDesign.surfaceRecessed)
                .overlay(
                    Rectangle()
                        .fill(RamsDesign.border)
                        .frame(width: RamsDesign.borderWidth),
                    alignment: .trailing
                )

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RamsDesign.surface)
        }
        .background(RamsDesign.surfaceRecessed)
    }
}
```

### CSS

```css
.app-layout {
    display: flex;
    height: 100vh;
    background: var(--surface-recessed);
}

.sidebar {
    width: 248px;
    background: var(--surface-recessed);
    border-right: var(--border-width) solid var(--border);
    display: flex;
    flex-direction: column;
}

.content {
    flex: 1;
    background: var(--surface);
    overflow-y: auto;
}
```
