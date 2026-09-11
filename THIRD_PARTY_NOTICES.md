# Third-party notices

## Godot skills — `.claude/skills/`

The `godot-*` skills in `.claude/skills/` are taken from
[vl4dt/godot-skills](https://github.com/vl4dt/godot-skills), used under the MIT
Licence. The copyright notice is reproduced below as that licence requires.

Included (13 of the 22 in the upstream set):

    godot-47-migration        godot-animation          godot-architecture
    godot-code-review         godot-debugging          godot-gdscript-patterns
    godot-headless-workflow   godot-performance        godot-physics
    godot-project-setup       godot-save-systems       godot-shaders-vfx
    godot-state-management

Omitted deliberately, so the set stays relevant to this project:

| Skill | Why not |
|---|---|
| `godot-networking` | Frozen by the design doc §82 — no multiplayer before the vertical slice |
| `godot-csharp-patterns` | This project is GDScript only |
| `godot-audio`, `godot-i18n`, `godot-dialog-systems` | No such systems yet, and none planned before the slice |
| `godot-ui`, `godot-input`, `godot-inventory-economy` | Marginal today; revisit when those blocks start |
| `godot-brainstorming` | Not applicable |

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
