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
| V2-04 | Occlusion fade | ✅ |

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
| V2-14 | Building intent (outline → structure) | 🚧 prototype only |
| V2-15 | Wall connection solver | ✅ |
| V2-16 | Openings (door / window) | ✅ |
| V2-17 | Roof generator | ⬜ |

### Phase 4 — Object & interaction
| ID | Block | Status |
|---|---|---|
| V2-18 | WorldObject | ✅ basic |
| V2-19 | Free placement | ✅ basic |
| V2-20 | InteractionPoint | ✅ |
| V2-21 | Containers | 🚧 inventory store done |

### Phase 5 — NPC
| ID | Block | Status |
|---|---|---|
| V2-22 | NPC data model | ⬜ |
| V2-23 | Job / Task | ✅ simplified |
| V2-24 | Cross-floor work | ✅ |
| V2-25 | Schedule & needs | ⬜ |

### Phase 6 — Persistence
| ID | Block | Status |
|---|---|---|
| V2-26 | Save / load | ⬜ |

### Phase 7-8 — Frozen
| ID | Block | Status |
|---|---|---|
| V2-27 | Gameplay | ⬜ frozen by doc §82 |
| V2-28 | World | ⬜ frozen |

### ART — Art pipeline (doc Appendix E / K)
| ID | Block | Status |
|---|---|---|
| ART-09 | Fixed camera art profile | ✅ |
| ART-10 | Pixel asset library | ⬜ |
| ART-11 | Terrain scatter | ⬜ |
| ART-12 | Building material library | ⬜ |
| ART-13 | Pixel VFX library | ⬜ |
| ART-14 | NPC sprite pipeline | ⬜ |
| ART-15 | NPC Skeleton2D | ⬜ |
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
| Camera | **Locked** yaw 45 / pitch 52, 5 zoom steps. `L` = debug unlock only. | doc E.1.1 |
| Resolution | **Native 1280×720**, `canvas_items` stretch. Pixel size comes from asset texel density, not a global downscale. | doc E.2 |
| Buildings | Remain real 3D geometry | doc E.1.3 |
| Everything else | Pixel sprite / billboard by default | doc E.1.4 |
| Art | Placeholder only; nothing real committed | doc §58.1 |
| Language | Code and comments in English | Willow 2026-09-11 |

---

## Known debt

Stated plainly so it is not rediscovered later.

1. **Slabs and stairs are not in BuildingState.** Doc §18 lists Floor and Stair
   alongside Wall. They are still emitted directly by the scene. This blocks
   V2-17, because a roof generator needs to know where the floors are.
2. **Terrain height is not displaced into the mesh.** The field carries it and
   DIG/FILL change it, but rendering is still flat. Needs a subdivided grid per
   chunk.
3. **Openings do not create Portals.** Door and stair portals are still
   registered as fixtures, so walling up a doorway would not remove its portal.

---

## Running

```bash
GODOT="D:/privacy/Openclaw/Godot-4.7.2/Godot_v4.7.2-stable_win64.exe"
"$GODOT" --path C:/Users/15598/cozy-game-v2                                  # play
"$GODOT" --headless --path C:/Users/15598/cozy-game-v2 --quit-after 4500     # self-check
```

Every block must end with the self-check green and the demo still runnable.
