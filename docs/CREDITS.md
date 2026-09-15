# Third-party credits

> **This file is the licence record for every byte in this repository that we did
> not make.** If an asset is here, it is here with a source, an author and a
> licence that permits redistribution. If any of the three is missing, the asset
> does not go in.

---

## The rule, and why it replaced the old one

Until 2026-09-15 the rule was **"all art is placeholder, no real assets are
committed"** (總綱 §58.1). Willow lifted it, and the replacement is a rule about
PROVENANCE rather than about placeholder-ness:

> **Art assets may be committed, and every one of them must be recorded here
> with its source, its author, and a licence that allows redistribution.**

The old rule was doing two jobs at once. One was "keep the repo replaceable while
the art direction is unsettled" — that one is now spent, because the direction is
settled enough to build against. The other was **"never commit something we
cannot legally ship"**, and that job does not go away when the first one does.
Deleting the rule would have deleted both. Replacing it keeps the one that
matters.

**So the bar is now:** a licence that permits redistribution — **MIT, CC0, or
CC BY** (with the credit below). **No licence, or an unclear one, means no.** A
file whose origin nobody can name is the failure this file exists to prevent.

---

## In use

### Grass and ground shader techniques — Dylearn

| | |
|---|---|
| Source | https://github.com/DylearnDev/Dylearn-3D-Pixel-Art-Grass-Demo |
| Author | **Dylearn** (DylearnDev) |
| Licence | **MIT** (code) / **CC BY 4.0** (art assets) |
| Used for | Wind model, quantised animation rate, accent variation and the character-displacement mask, adapted into `shaders/vegetation.gdshader` |

Required attribution text, as the licence asks for it:

> **Grass assets by Dylearn** — https://github.com/DylearnDev/Dylearn-3D-Pixel-Art-Grass-Demo

**What we took and what we did not.**

| | |
|---|---|
| Code | Adapted for `shaders/vegetation.gdshader` — the wind model, the quantised animation rate and the base pivot. MIT, so adapting it is the grant the licence makes |
| Art | **Two sprites are in this repository**, at `assets/art/pixel/environment/`: `grassleaf.png` and `accentleaf.png`. CC BY 4.0, credited above |

Their project logo (Waterfowl) is **not licensed for reuse and is not used
anywhere in this repository**.

`grassleaf.png.import` and `accentleaf.png.import` are **edited from what Godot
generated**, and the edit is deliberate: `detect_3d/compress_to=0`. The default
is `1`, which silently switches a texture to VRAM compression the first time it
is used in 3D — lossy, and it destroys a 24 x 24 sprite. If these files are ever
regenerated, that line has to be put back by hand.

---

### Roguelike / RPG pack (item and furniture sprites) — Kenney Vleugels

| Source   | https://kenney.nl/assets/roguelike-rpg-pack |
| Author   | Kenney Vleugels (www.kenney.nl), with help by Lynn Evers |
| Licence  | **CC0-1.0** (public domain dedication) |
| Used for | `assets/art/pixel/kenney/roguelikeSheet.png` and the eight tiles cut from it (`icon_*.png`) |

**Why this licence and not a "free" one:** CC0 is a public-domain dedication, so
it permits redistribution with no conditions at all — the pack's own `License.txt`
says "you may use these graphics in personal and commercial projects; credit would
be nice but is not mandatory". The project's rule is that an asset may enter the
repo only if its licence ALLOWS REDISTRIBUTION (MIT / CC0 / CC BY); CC0 is the
strongest of the three. **CC BY-SA was rejected on sight** for the same rule —
share-alike is a condition this project cannot meet.

**CC0 asks for no attribution, and the entry is here anyway.** The rule is that
every external asset is recorded, and "nobody is owed this one" is a reason to
write less, not a reason to write nothing: the next person to see a sprite in
`assets/` should be able to find out where it came from without asking.

**The sheet is committed whole** (94 KB) rather than only the tiles in use, so the
other 1700 sprites are addressable by coordinate without another download — and so
a tile already in the game can be traced back to the sheet it was cut from.

---

## How to add an entry

Copy this block, fill every line, and put it in "In use":

```
### <what it is> — <author>
| Source   | <url> |
| Author   | <name or handle> |
| Licence  | <SPDX id> |
| Used for | <file(s) in this repo> |
```

**Attribution has to reach the player, not only the repository.** That is what
CC BY asks for, and it is the half of the obligation a credits file quietly
drops: a credit that exists only in a file nobody opens is a credit that is not
given.

**There is no credits surface in the game yet.** This line is here so that the
obligation is written down rather than remembered — the moment a build leaves
this machine, it is owed. When a credits screen is added it reads from here.
