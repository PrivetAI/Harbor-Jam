# Quaylock — measured baseline (port dispatcher)

Produced 2026-08-03 by `./tools/HarborForge/build.sh && ./tools/HarborForge/harborforge gate`
against the shipped simulation and the accepted corpus. Replaces the sliding-block
baseline, kept alongside as `BASELINE-2026-07-28-sliding-block.md`.

```
=== HARBOR JAM — ACCEPTANCE GATE ===
PASS  all shifts generate  [84/84]
PASS  S clears every shift  [84/84]
PASS  G misses two stars >= 80 % from port 5  [97.2 %]
PASS  G three-stars <= 25 % from port 3  [0.0 %]
PASS  G fails >= 30 % from port 5  [83.3 %]
PASS  R three-stars nothing from port 3  [0]
PASS  median S >= 1.35x median G  [2.45x]
PASS  groundings live from port 2  [368]
PASS  channel busy >= 25 % from port 3  [45 % median]
PASS  gear mismatch lives from port 4  [290]

--- per-port detail (policy S / policy G) ---
port 1  shifts=12  S3=12  G3=12  Gfail= 0  medS=   904 medG=   904
port 2  shifts=12  S3=12  G3= 8  Gfail= 0  medS=   968 medG=   914
port 3  shifts=12  S3=12  G3= 0  Gfail= 1  medS=  1132 medG=   817
port 4  shifts=12  S3=12  G3= 0  Gfail= 9  medS=  1256 medG=   500
port 5  shifts=12  S3=12  G3= 0  Gfail=10  medS=  1195 medG=   441
port 6  shifts=12  S3=12  G3= 0  Gfail=10  medS=  1362 medG=   449
port 7  shifts=12  S3=12  G3= 0  Gfail=10  medS=  1768 medG=   611

GATE PASSED

```

## How to read this

`S` is a heuristic reference player: best-fit packing, a tide check before mooring a deep
hull, and it holds the channel when a waiting ship is nearly out of patience. `G` is the
zero-thought policy — first waiting ship into the first berth that fits, send the moment
unloading ends. `R` picks a legal move at random.

The line that matters is `median S >= 1.35x median G`, measured at **2.45×**, together with
`G fails >= 30 % from port 5` at **83.3 %**. Against the same measurements on the previous
sliding-block game, where the zero-thought policy three-starred 96.66 % of the corpus, this
is the whole point of the rebuild.

Ports 1 and 2 deliberately do not discriminate: `G3=12` and `G3=8` there. They teach. The
acceptance filter only demands that greedy lose ground from port 3 on.

Two clauses were rejected during construction for measuring nothing, and are recorded here
so nobody re-adds them:

- **"S three-stars >= 80 %"** is true by construction — `target3` is calibrated at 92 % of
  S's own score, so S clears it on every shift it can finish. Replaced by
  "G misses two stars", which is a threshold S does not define.
- **`channelRefusals`** counts berth commands refused because the channel was busy. A policy
  checks before it acts, so this is always 0 in the harness and can never prove the channel
  matters. Replaced by `channelBusyTicks`, i.e. real occupancy of a serial resource.

`S` is permitted to lose at most one ship on an accepted shift. Requiring it to go flawless
tuned the corpus to "a mediocre bot never slips", which rejected 35 of 84 shifts and would
have shipped a much easier game than a player who plans deserves.
