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

**What we took and what we did not.** The shader SOURCE is MIT, so adapting it
is the grant the licence makes. Their **art** is CC BY 4.0, which also permits
this, credited above. Their project logo (Waterfowl) is **not licensed for reuse
and is not used anywhere in this repository**.

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
