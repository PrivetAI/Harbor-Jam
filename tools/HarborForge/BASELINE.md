# Harbor Jam — measured baseline

Produced by `./tools/HarborForge/build.sh && ./tools/HarborForge/harborforge audit` against the
shipped engine and generator, before any redesign work. 500 rollouts of each policy per level.

```
=== HARBOR JAM — CORPUS AUDIT (real engine, real generator) ===
levels generated                : 140/140
total boats in corpus           : 1170
levels where par == boat count  : 140/140

policy A runs                   : 70000
policy A cleared at/under par   : 67665  (96.66 %)
boats exiting on the first tap  : 777/1170  (66.41 %)
opening taps that do nothing    : 247/1170  (21.11 %)
levels reachable into a dead end: 21/140
   2-0  boats=6  dead in 7.60 % of rollouts
   2-7  boats=7  dead in 7.40 % of rollouts
   2-8  boats=8  dead in 4.00 % of rollouts
   2-9  boats=8  dead in 3.80 % of rollouts
   2-10  boats=8  dead in 3.80 % of rollouts
   2-12  boats=9  dead in 6.60 % of rollouts
   2-13  boats=9  dead in 36.80 % of rollouts
   2-16  boats=9  dead in 20.20 % of rollouts
   2-18  boats=10  dead in 2.00 % of rollouts
   5-3  boats=9  dead in 1.60 % of rollouts
   5-6  boats=9  dead in 3.60 % of rollouts
   5-8  boats=10  dead in 1.60 % of rollouts
   5-12  boats=11  dead in 4.00 % of rollouts
   6-5  boats=10  dead in 12.80 % of rollouts
   6-6  boats=11  dead in 4.40 % of rollouts
   6-7  boats=11  dead in 11.60 % of rollouts
   6-10  boats=12  dead in 7.60 % of rollouts
   6-11  boats=12  dead in 1.20 % of rollouts
   6-14  boats=13  dead in 9.40 % of rollouts
   6-15  boats=13  dead in 8.80 % of rollouts
   6-16  boats=13  dead in 1.20 % of rollouts

--- baseline assertions ---
PASS  all 140 levels generate
PASS  par equals boat count on every level
PASS  zero-thought policy three-stars at least 90 % of runs
PASS  at least 20 levels reachable into a dead end

AUDIT OK — the measured baseline is unchanged.
```
