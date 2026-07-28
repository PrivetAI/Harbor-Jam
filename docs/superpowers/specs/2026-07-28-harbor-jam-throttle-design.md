# Harbor Jam — Throttle & Turning Basins

**Date:** 2026-07-28
**Status:** approved for implementation
**Scope:** replace the core move rule, the level generator and the scoring instrument so the game
contains an actual puzzle. Art direction, the single-tap verb, the four-tab shell, the store
listing and the target audience are unchanged.

---

## 1. Why

The game as built has no puzzle in it, and this is provable rather than a matter of taste. A headless
harness compiled against the real `HJEngine`, `HJModels` and `HJGenerator` (70 000 rollouts over all
140 campaign levels) measured:

| Property | Measured |
|---|---|
| Levels where `par == boat count` | 140 / 140 |
| Zero-thought policy ("tap anything that exits") clears at 3 stars | **96.63 %** |
| Boats that exit on the very first tap | 777 / 1170 (66.4 %) |
| Opening taps that mutate nothing at all | 247 / 1170 (21.1 %) |
| Levels reachable into a state where no tap does anything | **21 / 140** |

### Root causes

1. **`par` is defined as the boat count and the verifier enforces it.**
   `HJGenerator.swift:170` ships `par: total, solutionOrder: Array(0..<total)`, and
   `HJGenerator.swift:196-200` rejects any candidate where a tap is not a full `.exited` and
   `state.taps != par`. With one tap per boat, a solution is a *permutation*, not a path. The move
   class every sliding-block puzzle draws its depth from — park a piece somewhere temporarily and
   come back for it — is structurally excluded and actively punished, because any partial slide is
   over par and costs a star. Search depth is exactly 1.

2. **Reverse construction guarantees a greedy exit order exists.**
   `HJGenerator.swift:81-105` places boat *i* only after every boat with id > *i*, with
   `guard corridor.isDisjoint(with: occupiedNow)` at `:97`. By induction the lowest remaining id can
   always exit. Because exiting only ever *deletes* occupancy, the exit-ready set never shrinks —
   so there is no state in the game where the correct move is to decline an available exit, and
   greedy is a *complete* solver with zero lookahead.

3. **No action ever tightens the board.** The only mutations are "remove a boat" and "slide a boat
   forward". Any reachable state is at least as easy as the start.

4. **`verify()` is a difficulty-*removal* filter.** Any seed where a mechanic would have mattered
   gets re-rolled. Sandbars are drawn from the complement of every exit corridor
   (`HJGenerator.swift:122-135`) so the tide cannot block anything; buoy chains always name a key
   exiting before its lock (`:113-117`) so ascending order pre-satisfies all of them; currents are
   gated behind `if let id = movedBoatID` (`HJEngine.swift:137-139`) while the exit path passes
   `nil` (`:116`) so they fire on zero taps of any par run; the tug is never needed. Four of the
   five advertised mechanics are provably inert.

5. **Trial is free three ways over, and the same early return is a bug.**
   `HJEngine.swift:72` and `:111` return before the first mutation, so probing costs nothing; `taps`
   is a stored field of the snapshotted `HJBoardState` (`:15`) so `undo()` refunds the score;
   `restart()` zeroes it. And because `if steps == 0 { return .blocked }` at `:111` sits *above*
   `advanceFerry` at `:136`, the ferry only advances when some boat successfully moved — so a board
   whose remaining boats are all blocked by the ferry can never change again. All 21 dead-state
   levels are in the three ferry chapters (2, 5, 6); the four chapters without a ferry produce zero.

This is a mathematics failure, not a presentation or motivation failure. Hints, timers and juice
would produce the same trivial game, faster and prettier.

---

## 2. The design

### 2.1 Throttle — a tap advances a fixed number of cells

Every hull carries a printed **throttle of 1, 2 or 3**. A tap advances the boat exactly that many
cells along its bow, or as far as it can if fewer are clear. It exits only if it sheds all in-bounds
cells during those steps.

- `HJBoat` gains `throttle: Int` (`HJModels.swift:32-54`).
- The unbounded `while true` march at `HJEngine.swift:81-109` becomes `for _ in 0..<boat.throttle`,
  keeping the existing per-step legality checks verbatim (solid-cell test at `:89`, bow-side
  out-of-bounds test at `:92-104`).
- Rendered as that many dots beside the existing bow arrow (`HJBoardView.swift:210-212`).

**Why this is the whole design.** Today an action is set-subtraction on the occupancy set. Under
throttle an advance *translates a footprint*: the boat lands on cells that were free a moment ago,
so a legal, productive-looking tap can plug the only lane another boat needs. `par` becomes roughly
twice the boat count by arithmetic, before any solver runs, and where a boat rests becomes something
the player chose.

**Explicitly excluded:** astern-when-fouled. A single gesture that produces forward or backward
motion depending on a clearance count the UI never shows reads as a bug, not as a second verb. A
boat that cannot advance nudges and stops — the existing 4pt shake already draws this.

### 2.2 Every tap ticks the world

The pre-mutation early returns at `HJEngine.swift:72` (`.anchored`) and `:111` (`.blocked`) are
deleted. `state.taps += 1`, the tide toggle (`:130-135`) and `advanceFerry` (`:136`) are hoisted into
a `tickWorld(_:)` that runs on every outcome except `.invalid`.

One deletion fixes three things: the 21.1 % of taps that let the player read the answer off the
engine for free, all 21 dead-state levels (the ferry can no longer freeze), and the absence of a
wait move — which the player now has on the existing single gesture.

### 2.3 Currents run every tick; sandbars move inside the corridors

- `applyCurrent(_:boatID:)` (`HJEngine.swift:163-178`) becomes `applyCurrents(_ state:)`, iterating
  **every** lane resident, far-side-first so a queue in a lane resolves without overlap. The barge
  exemption at `:166` stays (barges become drift anchors the player positions) and the legality
  guard at `:176` stays.
- `HJCurrentLane` gains `period: Int` drawn from {2, 3, 4}; the effective push flips when
  `(taps / period) % 2 == 1`, so lanes do not saturate against a wall. `HJDirection` gains an
  `opposite` property (same shape as `rotatedCW`, `HJModels.swift:21-23`).
- `HJGenerator.swift:122-140` inverts polarity: sandbars are drawn **from** the union of exit
  corridors instead of its complement, and a board must have sandbars inside at least two distinct
  boats' corridors.

The board now changes without the player's consent, so a reachable state is no longer at least as
easy as the start.

### 2.4 Turning basins replace the tug token

With fixed bows and forward-only movement, every boat's position is a monotone counter along one ray
and the move graph is acyclic — "park it and come back" is impossible in principle. A **basin** is a
board cell; a boat whose bow cell enters a basin stops there and its bow flips **180°**.

This is free and always legal: `width`/`height` derive purely from `bow.isHorizontal`
(`HJModels.swift:42-43`), and east↔west / north↔south both preserve the footprint, so no collision
check is needed. `rotatedCW` does change the footprint, which is why the existing `tugRotate` has to
special-case barges at `HJEngine.swift:188-192`.

Deleted: `tugRotate` (`HJEngine.swift:181-200`), `tugTokens` (`:14`, `HJModels.swift:79`),
`tugArmed` / `tugsUsed` (`HJGameViewModel.swift:21/25/51-64`), `tugChip`
(`HJGameView.swift:129-147`), the `tugs_15` achievement (`HJSave.swift:126`). `HJTugShape`
(`HJTheme.swift:218`) is reused as the basin tile art.

### 2.5 Par becomes a witnessed line, and the gate becomes adversarial

`par: total` and the `state.taps == level.par` assertion are deleted. An **offline harness**,
compiled against `HJEngine` / `HJModels` / `HJGenerator` outside the Xcode project, searches each
seed and bakes a table of `(accepted salt, par, witness line)`. The device never searches — it
replays the witness through the real engine exactly as `verify()` does today
(`HJGenerator.swift:196-199`).

**The search.** Breadth-first over committed board states, with a transposition set keyed on a
canonical hash of `(boats sorted by id: x, y, bow, throttle; tideHigh; ferry.x; taps % lcm(periods))`,
a node cap of 2 000 000 and a depth cap of `4 × boatCount`. The first complete line found is the
witness. If the cap is reached without a line, the **seed is rejected** — never shipped with an
unproven par. The engine is used as-is for successor generation so the witness is valid by
construction; `solidCells` (`HJEngine.swift:40-47`) allocates a fresh `Set` per query, which is
acceptable offline and is the reason the search stays out of the app.

Acceptance is **not** defined against a proven optimum: a capped search silently returns a
non-minimum, and "greedy fails to reach the optimum" then becomes trivially true on every board.
Four clauses instead, enforced from level 0 with no chapter exempt:

- **(a)** witness length > boat count;
- **(b)** over 200 randomised "tap anything that advances, prefer anything that exits" rollouts, the
  median result is ≥ **1.25 ×** the witness or fails to clear — stated as a *ratio* so it does not
  become easier to satisfy as par grows;
- **(c)** at least two boats appear three or more times in the witness;
- **(d)** deleting any single mechanic from the board changes the witness length — this is the test
  that a mechanic is not decorative.

**Checkpoint gate.** The harness is built and run FIRST, before any change lands in the app. It
produces the one number nobody has measured: the acceptance yield on real boards. If the yield is
too low, the parameters are retuned or the direction is reconsidered — at a cost of weeks, not
months.

### 2.6 Scoring and progression

- `taps` **stays** inside `HJBoardState`. It is the world phase that the tide (`:131`) and the lane
  flips read; an undo that did not rewind it would desynchronise the harbor.
- A new `movesCommitted` on `HJGameViewModel` increments on every non-`.invalid` outcome and is
  touched by neither `undo()` (`:88-92`) nor `restart()` (`:94-102`). Both stay free and unlimited —
  free undo is correct; refunding the score is not.
- Star bands scale (`HJSave.swift:190`): 3 at `≤ par`, 2 at `≤ par + max(2, par/6)`, 1 otherwise. A
  flat +2 window on a 28-move board is 7 % tolerance and collapses expert and careless play into one
  bucket.
- Chapter unlock (`HJSave.swift:176-179`) moves from stars to **levels cleared**. The current gate —
  166 of 420 stars — opens the final chapter after 56 of 140 levels, and was tuned when 3 stars were
  unloseable.
- A per-level **Clean Line** pennant: cleared at par with zero undos and zero restarts. This is the
  unfakeable mastery signal.
- Achievements are rewritten around first clears and Clean Lines. `applyCommonWinStats`
  (`HJSave.swift:223-229`) and `levelsCleared += 1` (`:198`) currently increment on every clear
  including repeats, so 18 of 20 are farmable by replaying the 3-boat first level; `boats_1500`
  (`:108`) and `taps_2000` (`:127`) are unreachable by a perfect playthrough, because the corpus
  contains exactly 1170 boats and 1170 par moves.

### 2.7 Feedback ships with the rules, not after

- Press-and-hold shows a ghost hull at the landing cell and names why the boat will stop there.
- Departures get a `.transition`.
- "Blocked by hull", "blocked by sandbar" and "anchored" stop collapsing into one 4pt shake
  (`HJGameViewModel.swift:80-81`).

Cheaper than it sounds: `HJBoardView.swift:168-169` already carries
`.animation(.easeOut(duration: 0.22), value: boat.x)` and `value: boat.y`, and `:153` animates the
ferry, so multi-cell motion and drift animate for free.

### 2.8 Win sound

The win currently plays `AudioServicesPlaySystemSound(1025)` (`HJGameViewModel.swift:107`) — a
generic system alert, identical whether the player earned one star or three.

Replace it with a bundled **harbour bell**, synthesised offline as a mono 44.1 kHz 16-bit PCM WAV and
registered once via `AudioServicesCreateSystemSoundID` with the bundle URL (PCM WAV under 30 s is a
supported format; no `AVAudioPlayer` and no new framework link).

- `win_bell.wav` — a struck bronze bell: fundamental ≈ 587 Hz with inharmonic partials at ×2.0, ×3.0
  and ×4.2, exponential decay ≈ 1.4 s, 5 ms attack ramp to avoid a click.
- Three stars additionally plays `win_bell_double.wav`, the same strike answered a fifth higher
  ≈ 200 ms later — the traditional two-bell answer, so mastery is audible and not just visual.
- Both respect the existing `soundOn` gate in `playSound` (`:136-138`).
- Sounds are created once and cached in the view model; `AudioServicesDisposeSystemSoundID` on
  deinit.

The move sounds also separate: an exit keeps a distinct tone from a partial advance, so the player
hears the difference between the two outcomes that now matter.

### 2.9 Content scale

Grids cap at **8×8** and boats at **10** (chapter 6 is currently 9×9 and ramps to 14,
`HJModels.swift:132`). On a 393 pt iPhone a 9×9 board gives a 38 pt cell and a 35 pt hull
(`HJBoardView.swift:196-197`), below the 44 pt touch target. And more boats means more
simultaneously-correct moves — object count made the game *easier*, not harder. Difficulty now comes
from throttle, basins and the acceptance gate.

### 2.10 Daily

Baking breaks the current promise of "A fresh harbor every day" (`HJDailyView`). Resolution: bake a
pool of ~400 accepted boards and select by date. That is years without repetition for a player, at
the same quality guarantee as the campaign.

---

## 3. What survives

The verb and the fantasy — one gesture, a bow arrow on every hull, tap and the boat sails. The
entire art direction and the `HJTheme` shape vocabulary. Free unlimited undo and restart. The
value-typed deterministic engine and the snapshot undo stack. `HJRandom` (`HJGenerator.swift:4-23`),
the salt retry loop (`:35-44`), the in-memory cache (`:46-55`), `exitCorridor` (`:173-185`), the
real-engine witness replay, the daily fallback pool. The colorblind pattern overlay
(`HJBoardView.swift:205-208`). The save layer's `decodeIfPresent` robustness. The ferry, unchanged
and finally not frozen. The name, icon, four-tab shell, store listing and casual audience.

## 4. What dies

Reverse construction and `guard corridor.isDisjoint(with: occupiedNow)` (`HJGenerator.swift:97`).
`par: total, solutionOrder: Array(0..<total)` (`:170`) and the canonical-order replay (`:196-200`).
The `max(1, n/4)` triviality gate (`:204-212`), which does not run at all below 5 boats. The
`protected` sandbar exclusion (`:122-135`). The `keyIdx < lockIdx` chain rule (`:113-117`). The
unbounded march (`HJEngine.swift:81-109`). The free `.blocked` / `.anchored` returns (`:72`, `:111`).
The tug token economy. The flat +2 star band and the star-gated chapter unlock. The 9×9 / 14-boat
chapter 6. All three onboarding cards (`HJGameView.swift:258-262`) — both "sails straight ahead" and
"Undo and restart are always free" become misleading. 18 of the 20 achievements. The system win
sound.

Save compatibility is deliberately broken: `par` changes meaning, so every star already earned is
meaningless. The save key at `HJSave.swift:132` is bumped, which wipes local progress. Acceptable —
the app has not been released.

---

## 5. Risks

1. **Acceptance yield is unmeasured.** The four-clause gate may reject nearly every seed. Mitigated
   by the checkpoint in §2.5: the harness runs before any app change.
2. **Depth ceiling is real but bounded.** Bows stay fixed, boats only advance along one ray, and
   basins are the only cycle in the move graph, so required lookahead goes from 1 ply to roughly
   3–4. This is Cosmic Express, not Baba Is You. A puzzle-forum player will finish and shrug. The
   trade is deliberate: it is the only direction that does not pay for depth in audience.
3. **The pbxproj is hand-authored** with no synchronized groups. Every new `.swift`, the baked level
   table and both `.wav` files must be registered manually in four places each, or they silently do
   not build.
4. **Metadata drift.** The chapter taglines "Mind the currents" (`HJModels.swift:93`) and "Chained
   and crowded" (`:96`) and the `HJMoreView` codex entries for Currents and the Tug all become wrong
   until this lands; screenshots need retaking afterwards.

## 6. Definition of done

- Offline harness reports ≥ 140 campaign boards and ≥ 400 daily boards passing all four clauses.
- The zero-thought policy, re-run on the new corpus, three-stars **< 15 %** of boards (from 96.63 %).
- Median witness length ≥ 1.6 × boat count across the corpus.
- Zero levels reachable into a state where no tap has any effect.
- Every board's witness replays cleanly through the shipped engine at app launch of that level.
- Debug + Release `BUILD SUCCEEDED`, zero warnings.
