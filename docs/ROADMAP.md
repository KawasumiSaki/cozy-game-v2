# CozyVale V2 — Roadmap

> **The authoritative block plan lives in Obsidian**, not here:
> `Documents\Obsidian Vault\01-项目\xiansuwd\01-板块\00-目录.md`
>
> This file is the mirror kept next to the code: a status table, the locked
> decisions, and where to find everything else. Block detail, definitions of
> done and the development log are in Obsidian because they are read by a human
> between sessions, not by the engine.

---

## Where things are

| What | Where |
|---|---|
| Block index (start here) | Obsidian `01-板块/00-目录.md` |
| Block detail + DoD + assertions | Obsidian `01-板块/<ID>-<名称>.md` |
| Development log | Obsidian `02-开发日志/游戏开发日志.md` |
| Start / finish protocol | Obsidian `03-流程/更新方案.md` |
| Architecture master (113 KB — only when changing architecture) | Obsidian `00-架构总纲/V2.1-技术架构总纲.md` |
| Art contract (camera, pixel density, import rules) | `docs/ART_PROFILE.md` |

---

## Status

✅ done ｜ 🚧 partial ｜ ⬜ not started

### Phase 0 — Technical spike
| ID | Block | Status |
|---|---|---|
| V2-00 | Skeleton + headless self-check | ✅ |
| V2-01 | Orthographic camera | ✅ (now locked — see ART-09) |
| V2-02 | Segment wall | ✅ |
| V2-03 | Character billboard | ✅ |
| V2-04 | Occlusion fade | ✅ mechanisms complete 2026-09-12 — stale fade list, slabs never registered, and the ray now marches past the nearest blocker. All 8 probe spots report 0 opaque at every yaw. Probe: `--cozy-probe-occlusion` |

### Phase 1 — Spatial core
| ID | Block | Status |
|---|---|---|
| V2-05 | Floor system | ✅ |
| V2-06 | Room detection (planar face traversal) | ✅ |
| V2-07 | Portal | ✅ |
| V2-08 | Room graph | ✅ |
| V2-09 | Local navigation (grid A*) | ✅ |

### Phase 2 — Terrain
| ID | Block | Status |
|---|---|---|
| V2-10 | Terrain data (cell / chunk / materials) | ✅ |
| V2-11 | Terrain editing (intent / rasterization) | ✅ |
| V2-12 | Road system | ⬜ |
| V2-13 | Foundation solver | 🚧 validator done, solver not |

### Phase 3 — Building
| ID | Block | Status |
|---|---|---|
| V2-14 | Building intent (outline → structure) | ✅ |
| V2-15 | Wall connection solver | ✅ |
| V2-16 | Openings (door / window) | ✅ |
| V2-17 | Roof generator | ✅ |

### Phase 4 — Object & interaction
| ID | Block | Status |
|---|---|---|
| V2-18 | WorldObject | ✅ basic |
| V2-19 | Free placement | ✅ basic |
| V2-20 | InteractionPoint | ✅ |
| V2-21 | Containers | 🚧 storage + item vocabulary (§35) + eating done; §45 production chain remains |

### Phase 5 — NPC
| ID | Block | Status |
|---|---|---|
| V2-22 | NPC data model | ✅ |
| V2-23 | Job / Task | ✅ simplified |
| V2-24 | Cross-floor work | ✅ |
| V2-25 | Schedule & needs | ✅ |

### Phase 6 — Persistence
| ID | Block | Status |
|---|---|---|
| V2-26 | Save / load | ✅ JSON facts to `user://`, F5/F9; no save slots yet |

### UI — interface
| ID | Block | Status |
|---|---|---|
| UI-01 | Interface basics (HUD / build palette / right-click select) | ✅ |
| UI-02 | Resident panel (attributes / skills / needs / schedule) | ✅ |

### Phase 7-8 — Frozen
| ID | Block | Status |
|---|---|---|
| V2-27 | Gameplay | ⬜ frozen by doc §82 |
| V2-28 | World | ⬜ frozen |

### ART — Art pipeline (doc Appendix E / K)
| ID | Block | Status |
|---|---|---|
| ART-09 | Fixed camera art profile | ✅ |
| ART-10 | Pixel asset library | ✅ |
| ART-11 | Terrain scatter | ✅ |
| ART-12 | Building material library | 🚧 assembly done, textures await assets |
| ART-13 | Pixel VFX library | ✅ campfire |
| ART-14 | NPC sprite pipeline | 🚧 game-side contract DONE 2026-09-12 — appearance data, animation selection, `AnimatedSprite3D`. Awaiting the Blender factory's sheets (step 2+). |
| ART-15 | NPC Skeleton2D | ⬜ superseded in part: the skeleton now lives in Blender, not Godot. See `ART_PROFILE.md` §9. |
| ART-16 | NPC animation controller | ⬜ |
| ART-17 | Pixel corrective animation | ⬜ |
| ART-18 | Art QA scene | ⬜ |
| ART-19 | AI asset ingest | ⬜ |

---

## Locked decisions

| Decision | Value | Source |
|---|---|---|
| Axis mapping | `doc(x,y,z) -> godot(x,z,y)` — height is real elevation, never a render layer | doc §1.1 |
| Render style | Real 3D + orthographic + 2D pixel billboards. **Characters are NOT 3D.** | doc §1.2, E.1.2 |
| Camera | **Locked**, 5 zoom steps, `L` = debug unlock only. The ANGLE is **yaw 180 / pitch 40 + narrow-FOV perspective as of 2026-09-12**. The yaw is a measurement, not a taste call: the door is cut into the `z = 0` wall, so the front of the house faces `-Z`, and the camera has to be on that side or the game opens on the back of the building. Zoom is remembered across runs; the angle deliberately is not. | doc E.1.1, `_check_opening_shot` |
| Resolution | **Native 1280×720**, `canvas_items` stretch. Pixel size comes from asset texel density, not a global downscale. | doc E.2 |
| Buildings | Remain real 3D geometry | doc E.1.3 |
| Everything else | Pixel sprite / billboard by default | doc E.1.4 |
| Art | Placeholder only; nothing real committed | doc §58.1 |
| **Art pipeline** | **Hybrid Pixel Diorama**: buildings/furniture = 3D, **large trees = 2.5D shells**, grass/small = sprites, **NPC = Blender-rendered sprite sheets**. Blender is a factory, not a runtime dependency — `Characters are NOT 3D` (§1.2) still holds. See `ART_PROFILE.md` §9. | Willow 2026-09-12 |
| Language | Code and comments in English | Willow 2026-09-11 |
| UI tool grouping | By OPERATION, not by resulting object — a Door is a wall opening, not a tool | doc #24 |
| UI selection | Right-click probes what is under the cursor; the menu is built from that | Willow 2026-09-11 |
| HP / stamina | Shown **only in dungeons**, never on the home HUD | Willow 2026-09-11 |
| Passion | Scales EXPERIENCE (x1/x2/x4), never speed; aversion means not assignable | 愿景 §10 |
| Schedule | Resolves to an ACTIVITY, then to an interaction-point TYPE — never to an object | doc #115 |
| Traits | Change how FAST a value moves, not where it lands | this project |

---

## Known debt

Stated plainly so it is not rediscovered later.

1. **Terrain height is not displaced into the mesh.** The field carries it and
   DIG/FILL change it, but rendering is still flat. Needs a subdivided grid per
   chunk.
2. ~~Openings do not create Portals~~ — **fixed in V2-25**: a door portal is
   derived from the wall's DOOR opening, and the hand-written `door_south`
   fixture is gone. `no route` failures dropped from 2017 to 1.
3. **The asset library scans with DirAccess.** Works in the editor and in
   headless runs; an exported build would need the definitions declared as
   resources or bundled into a manifest first.
4. ~~Terrain has no biome concept~~ — solved by ART-11 (`CozyBiome`, derived).
5. ~~Outdoor navigation is a straight line~~ — **fixed**: the outdoors gets its
   own (coarser) grid with building footprints as obstacles. Verified by
   asserting no route point lands inside the house.
6. **UI is PC only.** No touch input exists (0 handlers). Willow: mobile later.
7. **Scatter does not follow terrain edits.** Digging does not re-scatter the
   plants on the patch. A full rebuild costs 138 ms, so hooking it to edits
   needs a chunk-scoped rebuild first; the trade-off is recorded in ART-11.
8. **Roofs go to rooms with nothing above them** (corrected from "top floor",
   which left one-storey outbuildings bare). A non-rectangular room still falls
   back to flat; the plan reports that rather than applying it silently.
9. **Outlines emit walls and one doorway only.** Windows and automatic stairs
   are not built, self-intersecting outlines are not guarded against, and a roof
   does not regenerate when the room polygon under it changes.
10. **Trait effects are partly live.** `mood_aura` and friends are stored but
   nothing consumes them yet — they need V2-25's needs system.
11. **The wall assembler does not tile roofs** — ART-12's idea applied to roofs
   is not built.

---

## Running

```bash
GODOT="D:/privacy/Openclaw/Godot-4.7.2/Godot_v4.7.2-stable_win64.exe"
"$GODOT" --path C:/Users/15598/cozy-game-v2                                  # play
"$GODOT" --headless --path C:/Users/15598/cozy-game-v2 --quit-after 4500     # self-check
```

Every block must end with the self-check green and the demo still runnable.
