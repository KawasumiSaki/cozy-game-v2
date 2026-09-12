# Third-party notices

## Godot skills — `.claude/skills/`

The `godot-*` skills in `.claude/skills/` are taken from
[vl4dt/godot-skills](https://github.com/vl4dt/godot-skills), used under the MIT
Licence. The copyright notice is reproduced below as that licence requires.

Included (16 of the 22 in the upstream set):

    godot-47-migration        godot-animation          godot-architecture
    godot-code-review         godot-debugging          godot-gdscript-patterns
    godot-headless-workflow   godot-performance        godot-physics
    godot-project-setup       godot-save-systems       godot-shaders-vfx
    godot-state-management

    godot-input               godot-inventory-economy  godot-ui
    ^ added 2026-09-12, when the roadmap moved: combat input (V0.2),
      equipment and loot (V0.3) and the UI layers all became real work

Omitted deliberately, so the set stays relevant to this project:

| Skill | Why not |
|---|---|
| `godot-networking` | Still out of scope. The reason CHANGED on 2026-09-12: it is no longer "frozen by §82" — Willow's roadmap now puts multiplayer at V0.4 — but it is still well past the slice, and the architecture constraint that matters (world ownership, save boundary, simulation authority) is recorded in the master doc §82 rather than needing a skill |
| `godot-csharp-patterns` | This project is GDScript only |
| `godot-audio`, `godot-i18n` | No such systems yet. Game text is deliberately ASCII-only for now, which makes i18n premature by definition |
| `godot-dialog-systems` | Dungeon events and quests are V0.2+, and no dialogue system is designed yet |
| `godot-brainstorming` | Not applicable |

**The rule this table encodes:** a skill is taken when the block it describes is
about to start, not when it sounds useful. `godot-input` sat on the omitted list
for a day and then earned its place the moment "combat view = top-down ARPG" was
decided — which is the table working as intended.

### Licence

```
MIT License

Copyright (c) 2026 RoboCat

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
