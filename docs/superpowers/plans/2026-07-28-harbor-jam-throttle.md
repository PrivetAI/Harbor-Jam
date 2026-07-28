# Harbor Jam — Throttle & Turning Basins Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Harbor Jam's core move rule, level generator and scoring instrument so the game contains an actual puzzle — a zero-thought policy currently three-stars 96.63 % of the 140-level corpus, and must end below 15 %.

**Architecture:** A tap stops sliding a boat to the edge and instead advances it exactly its printed throttle (1–3 cells), so a boat's resting position becomes a chosen obstacle rather than a deletion. Turning basins add the only cycle in an otherwise acyclic move graph, giving back the "park it and come back for it" move class. Level generation moves off the device entirely: an offline harness at `tools/HarborForge` generates boards forward, searches a witness line, filters them through a four-clause adversarial acceptance gate, and bakes `levels.json`, which the app replays through the real engine as an integrity check.

**Tech Stack:** Swift 5 / SwiftUI, iOS 15.6 deployment target, no third-party dependencies. Offline tooling is plain `swiftc` compiled against the real app sources plus one Python stdlib script for audio synthesis. No XCTest target exists; the harness is the test surface.

## Global Constraints

- **Deployment target is iOS 15.6.** No iOS 16+ APIs. Specifically no `.tracking()`, no `NavigationStack`, no `.scrollContentBackground`, no `Charts`.
- **No SF Symbols and no emoji anywhere** — every icon is a custom SwiftUI `Shape` in `HJTheme.swift`.
- **The pbxproj is hand-authored with no synchronized groups.** Every new `.swift` file or resource must be registered in **four** places: `PBXBuildFile`, `PBXFileReference`, the `E8C6ADF1294695810FC9BE0F /* Harbor Jam */` group's `children` array, and the target's Sources or Resources build phase. Object ids are centrally assigned per file in the task that creates it — never reuse one.
- **The Resources build phase already exists:** `F115417AB24C0E0F4821A9A2 /* Resources */`, currently holding only `Assets.xcassets`. Do not create a second one.
- **All bundled files live flat in `Harbor Jam/`**, alongside the Swift sources and `Assets.xcassets`. There is no `Resources/` subfolder and none is created.
- **Every `Codable` decode in the save layer uses `decodeIfPresent(...) ?? default`.** Adding a non-optional field to a `UserDefaults` Codable save struct makes the synthesized decoder throw on missing keys and silently wipes all player progress. This has already happened once in this portfolio.
- **The engine is frozen after Task 4.** Nothing in Tasks 5–13 may change `tap`, `march`, `tickWorld`, `applyCurrents` or the basin rule — the corpus baked in Task 7 must be computed against the engine that ships.
- **Task 7 is a go/no-go checkpoint.** If the accepted corpus's zero-thought three-star rate is not below 15 %, work stops and parameters are retuned before any further app change.
- **The baked level table is `Harbor Jam/levels.json`** — that exact name everywhere, in tooling, in the app and in the audit.
- **The per-level save record type is `HJProgressRecord`.** The baked-table record type is `HJLevelRecord`. They are different types with different jobs; do not merge or rename them.
- **Save compatibility is deliberately broken** (`saveKey` → `hbj.state.v2`). `par` changes meaning, so every previously earned star is meaningless. The app has not been released, so this is acceptable.
- **Never fabricate expected output.** For any command whose output cannot be known in advance, state the assertion that must hold and show the code that enforces it.
- Build verification is `xcodebuild` Debug on `platform=iOS Simulator,name=iPhone 17` and Release on `generic/platform=iOS`. Only iPhone 17-series simulators exist on this machine.
- `TARGETED_DEVICE_FAMILY = "1,2"` (iPhone + iPad) and manual code signing stay as they are. Do not touch signing.

## Measured baseline this plan must beat

Reproduced by `tools/HarborForge/harborforge audit` over all 140 campaign levels, 70 000 rollouts, against the real engine:

| Property | Before | Required after |
|---|---|---|
| Levels where `par == boat count` | 140 / 140 | 0 / 140 |
| Zero-thought policy three-stars | 96.63 % | < 15 % |
| Boats exiting on the first tap | 777 / 1170 (66.4 %) | not gated, but reported |
| Opening taps that mutate nothing | 247 / 1170 (21.1 %) | 0 — every tap ticks the world |
| Levels reachable into a dead state | 21 / 140 | 0 / 140 |
| Median witness length ÷ boat count | 1.00 | ≥ 1.60 |

---


---

## Execution status

Tasks 1 and 2 are **already implemented and committed** — they were unblocked by the spec alone and
were done while the rest of the plan was being written. Verify rather than redo them:

| Task | Commit | Result |
|---|---|---|
| 1 — HarborForge harness | `df80f40` | Reproduces the baseline; `tools/HarborForge/BASELINE.md` committed |
| 2 — Every tap ticks the world | `83ab4db` | Free probing 21.11 % → 0.00 %; dead-end levels 21 → 1 |

Two deliberate divergences from the task text as written, already in the tree:

- The harness uses free functions `forgeRolloutA` / `forgeRolloutB` / `forgeOptions` rather than an
  `enum ForgeRollouts` namespace, and its own `ForgeRNG` rather than a `typealias` to `HJRandom`.
  Later tasks that call these names must use the shipped ones.
- `HJBlockReason` and `HJTapOutcome.blocked(reason:)` landed in Task 2, not Task 4. Task 4 consumes
  them rather than introducing them.
- Policy B waits rather than giving up when nothing can move: a refused tap now spends a tick, so
  waiting is a real move. Without that correction the harness still reported 21 dead ends after the
  fix. One level, 6-5, is a genuine dead end that waiting cannot rescue; Task 7's acceptance gate is
  what removes it, by rejecting boards with a reachable dead state.

## Known gaps in this plan

- **The two adversarial audits did not run** — both hit the session limit. The plan has been through
  my own self-review only (placeholder scan: 0 hits; symbol-ordering check; pbxproj id ownership
  check: no collisions; one filename `levels.json` throughout, 72 uses, no variants). Treat Task 7
  onward as unaudited and read each task before executing it.
- **Task 11 was authored by hand** after the agent writing it was cut off mid-output. It is complete
  but has had no second reader.

---


---

### Task 1: HarborForge harness and the measured baseline

Creates the offline harness the whole plan is instrumented by: `tools/HarborForge/`, compiled with plain `swiftc` against the **real** `HJModels.swift` / `HJEngine.swift` / `HJGenerator.swift`, plus an `audit` subcommand that reproduces the five baseline numbers quoted in §1 of the spec and asserts them so a later regression **in the tool** is caught. This is the checkpoint gate of spec §2.5: it runs before any app change lands.

Nothing in this task touches an app source file, `Harbor Jam.xcodeproj/project.pbxproj`, or `Assets.xcassets`.

**Files:**
- `tools/HarborForge/.gitignore` (new)
- `tools/HarborForge/build.sh` (new, executable)
- `tools/HarborForge/Rollouts.swift` (new)
- `tools/HarborForge/Audit.swift` (new)
- `tools/HarborForge/main.swift` (new)
- `tools/HarborForge/BASELINE.md` (new)

**Interfaces:**

*Consumes* (all pre-existing, unchanged, read-only — Task 1 is the first task, so it defines nothing of the frozen contract and depends on no later task):
- `HJRandom` — `struct HJRandom { init(seed: UInt64); mutating func next() -> UInt64; mutating func int(_ upper: Int) -> Int; mutating func bool() -> Bool; mutating func pick<T>(_ array: [T]) -> T? }` (`Harbor Jam/HJGenerator.swift:4-23`)
- `HJBoardState` — `var boats: [HJBoat]; var taps: Int; var isCleared: Bool` (`Harbor Jam/HJEngine.swift:4-57`)
- `HJTapOutcome` — the **current** five-case shape `.exited(boatID:) / .moved(boatID:distance:) / .blocked / .anchored / .invalid` (`Harbor Jam/HJEngine.swift:59-65`). Note `.blocked` here carries **no** associated value; the `HJBlockReason` payload arrives in Task 4 and this task must not anticipate it.
- `HJEngine.tap(boatID:state:) -> HJTapOutcome` (`Harbor Jam/HJEngine.swift:70`)
- `HJGeneratedLevel` — `var start: HJBoardState; var par: Int; var solutionOrder: [Int]` (`Harbor Jam/HJGenerator.swift:25-29`)
- `HJGenerator.campaignLevel(chapter:level:) -> HJGeneratedLevel?` (`Harbor Jam/HJGenerator.swift:48`)
- `HJCatalog.chapters`, `HJCatalog.levelsPerChapter`, `HJCatalog.totalLevels` (`Harbor Jam/HJModels.swift:91-101`)

*Produces* (harness-only; none of these ship in the app bundle):
- `enum ForgeProbe { case exits; case advances; case inert; case invalid }`
- `typealias ForgeRandom = HJRandom`
- `enum ForgeRollouts`
  - `static func probeAll(_ state: HJBoardState) -> [(id: Int, kind: ForgeProbe)]`
  - `struct Result { var cleared: Bool; var taps: Int; var deadlocked: Bool }`
  - `static func policyA(_ start: HJBoardState, rng: inout ForgeRandom, stepCap: Int) -> Result`
  - `static func policyB(_ start: HJBoardState, rng: inout ForgeRandom, stepCap: Int) -> Result`
- `struct ForgeLevelStats { var chapter, level, boats, par: Int; var parEqualsBoats: Bool; var exitsOnTapOne, inertOpeningTaps, threeStarRollouts: Int; var deadlockReached: Bool }`
- `enum ForgeAudit { static let rolloutsPerLevel: Int; static func run() -> Int }`
- executable `tools/HarborForge/harborforge` with subcommand `audit` (git-ignored, not committed)

---

- [ ] **Step 1: Create the harness directory and keep the built binary out of git.**

Run exactly (the repo path contains a space — keep every quote):

```bash
mkdir -p "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam/tools/HarborForge"
cat > "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam/tools/HarborForge/.gitignore" <<'EOF'
harborforge
*.o
EOF
```

- [ ] **Step 2: Write `tools/HarborForge/build.sh`.**

The app-source list is an **explicit array**, not a glob. Two reasons, both load-bearing: most files in `Harbor Jam/` are SwiftUI and will not compile for macOS, and Task 8 deletes `HJGenerator.swift` — the array makes that a hard error here instead of a silent behaviour change. Create the file with exactly this content:

```bash
cat > "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam/tools/HarborForge/build.sh" <<'EOF'
#!/bin/bash
# HarborForge — offline harness for Harbor Jam.
# Compiles the harness sources together with the REAL app sources, so every
# measurement is made against the engine that ships. Nothing here is in the
# Xcode target and nothing here is compiled into the app.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
APP="$REPO/Harbor Jam"

# App sources the harness links against. Kept as an EXPLICIT array, not a glob:
# most files in "$APP" are SwiftUI and will not compile for macOS, and later
# tasks delete files from this list. If you delete an app source, edit this
# array — a silent glob would hide the breakage.
APP_SOURCES=(
  "$APP/HJModels.swift"
  "$APP/HJEngine.swift"
  "$APP/HJGenerator.swift"
)

for f in "${APP_SOURCES[@]}"; do
  if [ ! -f "$f" ]; then
    echo "build.sh: missing app source: $f" >&2
    echo "build.sh: if this file was deleted on purpose, remove it from APP_SOURCES." >&2
    exit 1
  fi
done

# Harness sources are globbed — new harness files are picked up automatically.
HARNESS_SOURCES=("$HERE"/*.swift)
if [ ${#HARNESS_SOURCES[@]} -eq 0 ]; then
  echo "build.sh: no harness sources in $HERE" >&2
  exit 1
fi

# -swift-version 5 is required: HJGenerator.swift:47 holds a mutable static cache
#   private static var cache: [String: HJGeneratedLevel] = [:]
# which is an error under the Swift 6 language mode.
swiftc -O -swift-version 5 \
  -o "$HERE/harborforge" \
  "${APP_SOURCES[@]}" "${HARNESS_SOURCES[@]}"

echo "built: $HERE/harborforge"
EOF
chmod +x "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam/tools/HarborForge/build.sh"
```

- [ ] **Step 3: Write `tools/HarborForge/Rollouts.swift` — the two policies.**

Policy A commits **only** exits, uniformly at random; if nothing can exit the rollout stops un-cleared. Policy B commits any state-changing tap, prefers exits, and reports a deadlock when neither an exit nor an advance exists and the board is not cleared. `probeAll` taps a **copy** of the state, which is safe because `HJBoardState` is a value type (`Harbor Jam/HJEngine.swift:4`) and `HJEngine.tap` is deterministic.

```swift
cat > "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam/tools/HarborForge/Rollouts.swift" <<'EOF'
import Foundation

/// Deterministic RNG local to the harness. HJRandom (HJGenerator.swift:4-23) is a plain
/// SplitMix64 value type, so the harness reuses it rather than shipping a second one.
typealias ForgeRandom = HJRandom

/// What a single probe of one boat would do to the board, without committing it.
enum ForgeProbe {
    case exits
    case advances
    case inert          // .blocked or .anchored — the board is untouched
    case invalid
}

enum ForgeRollouts {

    /// Probe every boat on `state` without mutating it.
    static func probeAll(_ state: HJBoardState) -> [(id: Int, kind: ForgeProbe)] {
        var out: [(id: Int, kind: ForgeProbe)] = []
        for boat in state.boats {
            var copy = state
            switch HJEngine.tap(boatID: boat.id, state: &copy) {
            case .exited:  out.append((boat.id, .exits))
            case .moved:   out.append((boat.id, .advances))
            case .blocked, .anchored: out.append((boat.id, .inert))
            case .invalid: out.append((boat.id, .invalid))
            }
        }
        return out
    }

    struct Result {
        var cleared: Bool
        var taps: Int
        var deadlocked: Bool     // not cleared and no tap has any effect
    }

    /// Policy A — the zero-thought policy. Commits ONLY exits, chosen uniformly at random.
    /// If no boat can exit, the rollout stops; it has not cleared.
    static func policyA(_ start: HJBoardState, rng: inout ForgeRandom, stepCap: Int) -> Result {
        var state = start
        var steps = 0
        while !state.isCleared && steps < stepCap {
            let exits = probeAll(state).filter { $0.kind == .exits }.map { $0.id }
            if exits.isEmpty { break }
            let pick = exits[rng.int(exits.count)]
            _ = HJEngine.tap(boatID: pick, state: &state)
            steps += 1
        }
        return Result(cleared: state.isCleared, taps: state.taps, deadlocked: false)
    }

    /// Policy B — commits any state-changing tap, preferring exits. Reports a deadlock when
    /// neither an exit nor an advance exists and the board is not cleared.
    static func policyB(_ start: HJBoardState, rng: inout ForgeRandom, stepCap: Int) -> Result {
        var state = start
        var steps = 0
        while !state.isCleared && steps < stepCap {
            let probes = probeAll(state)
            let exits = probes.filter { $0.kind == .exits }.map { $0.id }
            let advances = probes.filter { $0.kind == .advances }.map { $0.id }
            if !exits.isEmpty {
                _ = HJEngine.tap(boatID: exits[rng.int(exits.count)], state: &state)
            } else if !advances.isEmpty {
                _ = HJEngine.tap(boatID: advances[rng.int(advances.count)], state: &state)
            } else {
                return Result(cleared: false, taps: state.taps, deadlocked: true)
            }
            steps += 1
        }
        return Result(cleared: state.isCleared, taps: state.taps, deadlocked: false)
    }
}
EOF
```

- [ ] **Step 4: Write `tools/HarborForge/Audit.swift` — the measurement and its assertions.**

500 rollouts of each policy per level over all 140 campaign levels (7 chapters × 20, `HJModels.swift:100-101`) = 70 000 rollouts per policy. Three stars under the *current* rules means cleared in `taps <= par`, which is also the top band of the new `HJSave.stars` in the frozen contract, so this metric stays comparable after Task 4. RNG seeds are derived from `(chapter, level)` so the run is bit-reproducible.

```swift
cat > "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam/tools/HarborForge/Audit.swift" <<'EOF'
import Foundation

struct ForgeLevelStats {
    var chapter: Int
    var level: Int
    var boats: Int
    var par: Int
    var parEqualsBoats: Bool
    var exitsOnTapOne: Int
    var inertOpeningTaps: Int
    var threeStarRollouts: Int
    var deadlockReached: Bool
}

enum ForgeAudit {

    static let rolloutsPerLevel = 500

    static func run() -> Int {
        var stats: [ForgeLevelStats] = []
        var missing: [String] = []

        for chapter in 0..<HJCatalog.chapters.count {
            for level in 0..<HJCatalog.levelsPerChapter {
                guard let g = HJGenerator.campaignLevel(chapter: chapter, level: level) else {
                    missing.append("\(chapter)-\(level)")
                    continue
                }
                let start = g.start
                let n = start.boats.count

                // Opening-tap census: deterministic, one probe per boat from the start state.
                var exitsOnOne = 0
                var inertOpening = 0
                for p in ForgeRollouts.probeAll(start) {
                    switch p.kind {
                    case .exits:    exitsOnOne += 1
                    case .inert:    inertOpening += 1
                    default:        break
                    }
                }

                // Policy A — zero-thought. 3 stars == cleared in <= par taps.
                var threeStar = 0
                var rngA = ForgeRandom(seed: 0xA000_0000 &+ UInt64(chapter) &* 1_000 &+ UInt64(level))
                for _ in 0..<rolloutsPerLevel {
                    let r = ForgeRollouts.policyA(start, rng: &rngA, stepCap: n * 4 + 8)
                    if r.cleared && r.taps <= g.par { threeStar += 1 }
                }

                // Policy B — deadlock reachability.
                var dead = false
                var rngB = ForgeRandom(seed: 0xB000_0000 &+ UInt64(chapter) &* 1_000 &+ UInt64(level))
                for _ in 0..<rolloutsPerLevel {
                    let r = ForgeRollouts.policyB(start, rng: &rngB, stepCap: n * 8 + 16)
                    if r.deadlocked { dead = true }
                }

                stats.append(ForgeLevelStats(chapter: chapter, level: level, boats: n, par: g.par,
                                             parEqualsBoats: g.par == n,
                                             exitsOnTapOne: exitsOnOne,
                                             inertOpeningTaps: inertOpening,
                                             threeStarRollouts: threeStar,
                                             deadlockReached: dead))
            }
        }

        let totalBoats = stats.reduce(0) { $0 + $1.boats }
        let parEqualsBoats = stats.filter { $0.parEqualsBoats }.count
        let exitsOnOne = stats.reduce(0) { $0 + $1.exitsOnTapOne }
        let inert = stats.reduce(0) { $0 + $1.inertOpeningTaps }
        let threeStar = stats.reduce(0) { $0 + $1.threeStarRollouts }
        let rolloutTotal = stats.count * rolloutsPerLevel
        let deadLevels = stats.filter { $0.deadlockReached }
        let threeStarRate = rolloutTotal == 0 ? 0 : Double(threeStar) * 100.0 / Double(rolloutTotal)

        print("levels generated        : \(stats.count) / \(HJCatalog.totalLevels)")
        print("total boats             : \(totalBoats)")
        print("par == boat count       : \(parEqualsBoats) / \(stats.count)")
        print(String(format: "zero-thought 3-star rate: %.2f %% (%d / %d rollouts)",
                     threeStarRate, threeStar, rolloutTotal))
        print("boats exiting on tap 1  : \(exitsOnOne) / \(totalBoats)")
        print("inert opening taps      : \(inert) / \(totalBoats)")
        print("dead-state levels       : \(deadLevels.count) / \(stats.count)")
        print("dead-state level list   : " + deadLevels.map { "\($0.chapter)-\($0.level)" }.joined(separator: " "))
        var byChapter: [Int: Int] = [:]
        for s in deadLevels { byChapter[s.chapter, default: 0] += 1 }
        print("dead-state by chapter   : " + (0..<HJCatalog.chapters.count).map { "ch\($0)=\(byChapter[$0] ?? 0)" }.joined(separator: " "))
        if !missing.isEmpty { print("MISSING LEVELS          : " + missing.joined(separator: " ")) }

        var failures: [String] = []
        func check(_ label: String, _ ok: Bool) {
            print((ok ? "PASS  " : "FAIL  ") + label)
            if !ok { failures.append(label) }
        }
        check("all 140 campaign levels generate", stats.count == HJCatalog.totalLevels)
        check("corpus holds 1170 boats", totalBoats == 1170)
        check("par == boat count on every level", parEqualsBoats == stats.count)
        check("zero-thought 3-star rate >= 90%", threeStarRate >= 90.0)
        check("boats exiting on tap one == 777", exitsOnOne == 777)
        check("inert opening taps == 247", inert == 247)
        check("dead-state levels >= 20", deadLevels.count >= 20)

        if failures.isEmpty {
            print("AUDIT OK")
            return 0
        }
        print("AUDIT FAILED: \(failures.count) assertion(s)")
        return 1
    }
}
EOF
```

- [ ] **Step 5: Write `tools/HarborForge/main.swift` — the subcommand dispatch.**

The file **must** be named `main.swift`; `swiftc` rejects top-level expressions in any other file. `audit` exits with `ForgeAudit.run()`; an unknown or absent subcommand prints usage and exits 2.

```swift
cat > "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam/tools/HarborForge/main.swift" <<'EOF'
import Foundation

let args = Array(CommandLine.arguments.dropFirst())
let sub = args.first ?? ""

switch sub {
case "audit":
    exit(Int32(ForgeAudit.run()))
default:
    print("HarborForge — offline harness for Harbor Jam")
    print("usage: harborforge <subcommand>")
    print("  audit    measure the campaign corpus and assert the recorded baseline")
    exit(2)
}
EOF
```

- [ ] **Step 6: Build the harness and confirm it compiles clean.**

```bash
cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam" && ./tools/HarborForge/build.sh
```

Must print exactly one line ending `built: .../tools/HarborForge/harborforge`, and **no** warning or error lines. Confirm the exit status and the no-subcommand path in one go:

```bash
cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam" && ./tools/HarborForge/harborforge; echo "EXIT=$?"
```

Expected: the three usage lines followed by `EXIT=2`. If instead you get an `swiftc` diagnostic about `HJGenerator.cache` and concurrency-safe global state, `-swift-version 5` is missing from build.sh — restore it rather than mutating the app source.

- [ ] **Step 7: Run the audit and confirm every assertion passes.**

```bash
cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam" && ./tools/HarborForge/harborforge audit; echo "EXIT=$?"
```

Takes roughly 20 seconds. The output is fully deterministic — it must match this, byte for byte:

```text
levels generated        : 140 / 140
total boats             : 1170
par == boat count       : 140 / 140
zero-thought 3-star rate: 96.67 % (67668 / 70000 rollouts)
boats exiting on tap 1  : 777 / 1170
inert opening taps      : 247 / 1170
dead-state levels       : 21 / 140
dead-state level list   : 2-0 2-7 2-8 2-9 2-10 2-12 2-13 2-16 2-18 5-3 5-6 5-8 5-12 6-5 6-6 6-7 6-10 6-11 6-15 6-16
dead-state by chapter   : ch0=0 ch1=0 ch2=9 ch3=0 ch4=0 ch5=4 ch6=8
PASS  all 140 campaign levels generate
PASS  corpus holds 1170 boats
PASS  par == boat count on every level
PASS  zero-thought 3-star rate >= 90%
PASS  boats exiting on tap one == 777
PASS  inert opening taps == 247
PASS  dead-state levels >= 20
AUDIT OK
EXIT=0
```

(The dead-state list is 21 entries: `6-14` sits between `6-11` and `6-15`.) The two hard equalities — 777 and 247 — are pure deterministic probes of the start states and carry no randomness, so any drift in them means a real change in `HJEngine.tap` or `HJGenerator`. The two rate assertions are thresholds (`>= 90 %`, `>= 20`) because they are sampled: the spec's §1 figures of 96.63 % and 21 came from a different rollout ordering, and 96.67 % / 21 here confirms them rather than contradicting them. Do **not** tighten those two into equalities.

If `AUDIT FAILED` appears, stop and reconcile before continuing — every later task's before/after comparison is anchored to this run.

- [ ] **Step 8: Write `tools/HarborForge/BASELINE.md` with the measured numbers.**

```bash
cat > "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam/tools/HarborForge/BASELINE.md" <<'EOF'
# Harbor Jam — measured baseline (pre-throttle)

Recorded by `./tools/HarborForge/harborforge audit` against the shipping engine at commit
`eea0f74`, before any change from the Throttle & Turning Basins spec landed. Re-running the
audit on an unmodified tree must reproduce these figures exactly; the harness asserts them.

Method: all 140 campaign levels (7 chapters x 20, `HJModels.swift:100-101`) generated through
the real `HJGenerator.campaignLevel`, then 500 rollouts of each of two policies per level
(70 000 rollouts per policy). RNG seeds are derived from `(chapter, level)`, so the run is
bit-reproducible.

- Policy A — the zero-thought policy. Commits only taps that fully exit a boat, chosen
  uniformly at random. Stops un-cleared if nothing can exit. Three stars = cleared with
  `taps <= par`.
- Policy B — commits any state-changing tap, preferring exits over partial advances. Reports
  a deadlock when the board is not cleared and neither an exit nor an advance exists.

## Results

| Property | Measured | Asserted by the audit |
|---|---|---|
| Campaign levels that generate | 140 / 140 | `== 140` |
| Boats in the corpus | 1170 | `== 1170` |
| Levels where `par == boat count` | 140 / 140 | every level |
| Zero-thought policy clears at 3 stars | 96.67 % (67 668 / 70 000) | `>= 90 %` |
| Boats that exit on the very first tap | 777 / 1170 (66.4 %) | `== 777` |
| Opening taps that mutate nothing | 247 / 1170 (21.1 %) | `== 247` |
| Levels reachable into a state where no tap does anything | 21 / 140 | `>= 20` |

The two hard equalities are deterministic start-state probes with no randomness in them, so
they are exact. The two rates are sampled and are asserted as thresholds; the spec's own
figures (96.63 %, 21) came from a different rollout ordering and agree with these.

## Dead-state levels

2-0 2-7 2-8 2-9 2-10 2-12 2-13 2-16 2-18
5-3 5-6 5-8 5-12
6-5 6-6 6-7 6-10 6-11 6-14 6-15 6-16

Per chapter: ch0=0 ch1=0 ch2=9 ch3=0 ch4=0 ch5=4 ch6=8.

All 21 fall in chapters 2, 5 and 6 — exactly the three chapters with `useFerry: true`
(`HJModels.swift:117`, `:129`, `:133`); the four chapters without a ferry produce none. This
confirms the mechanism named in spec section 1: `if steps == 0 { return .blocked }` at
`HJEngine.swift:111` returns above the `advanceFerry(&state)` call at `:136`, so once every
remaining boat is blocked the ferry can never move again and the board is frozen.

## Targets this baseline is measured against

From spec section 6 (Definition of done), re-run on the new corpus:

- zero-thought three-star rate below 15 % (from 96.67 %)
- median witness length at least 1.6 x boat count
- zero levels reachable into a state where no tap has any effect (from 21)
EOF
```

- [ ] **Step 9: Commit.**

The built `harborforge` binary is excluded by `tools/HarborForge/.gitignore` from Step 1 — confirm `git status --short` lists only the six text files below, then commit:

```bash
cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam" && git add tools/HarborForge/.gitignore tools/HarborForge/build.sh tools/HarborForge/main.swift tools/HarborForge/Rollouts.swift tools/HarborForge/Audit.swift tools/HarborForge/BASELINE.md && git commit -m "HarborForge: offline harness and the measured pre-throttle baseline

Compiles HJModels/HJEngine/HJGenerator with plain swiftc (-swift-version 5,
required by the mutable static cache at HJGenerator.swift:47) and adds an
audit subcommand over all 140 campaign levels, 500 rollouts per policy.

Reproduces and asserts the figures in the throttle design spec: par == boat
count on 140/140, zero-thought three-star rate 96.67%, 777/1170 boats exiting
on tap one, 247/1170 inert opening taps, and 21/140 levels reachable into a
dead state -- all 21 in the three ferry chapters.

No app source or pbxproj change.

Co-Authored-By: Claude <noreply@anthropic.com>"
```


---

### Task 2: Every tap ticks the world

Deletes the two pre-mutation early returns in `HJEngine.tap` so that a blocked or anchored tap is a **wait move**: the tap counter, the tide toggle and the ferry advance are hoisted into `HJEngine.tickWorld(_:)`, which runs on every outcome except `.invalid`. Introduces `HJBlockReason` and reshapes `.blocked` to carry it.

This is a bug fix, not a difficulty change. The three things it fixes: probing the engine for free (21.1 % of opening taps mutate nothing today), the missing wait verb, and the frozen boards — a board whose remaining boats are all blocked by the ferry can never change again today, because `if steps == 0 { return .blocked }` at `HJEngine.swift:111` sits *above* `advanceFerry(&state)` at `:136`.

**Files:**

- `Harbor Jam/HJEngine.swift` — modified (the whole task's substance)
- `Harbor Jam/HJGameViewModel.swift` — modified, one line (`:80`)
- `tools/HarborForge/check_tickworld.swift` — new

**Interfaces:**

*Consumes (all defined at or before Task 1):*
- Task 1: the `tools/HarborForge/` harness directory and its convention of compiling plain `swiftc` against the real app sources.
- Already shipped: `HJBoardState` (`HJEngine.swift:4-57`), its `occupied(excluding:)` `:22`, `ferryCells()` `:30`, `inBounds(_:)` `:49`, `isAnchored(_:)` `:53`; `HJBoat` (`HJModels.swift:32`); `HJCell` (`HJModels.swift:27`); `HJCatalog` (`HJModels.swift:90`); `HJRandom` (`HJGenerator.swift:4`); `HJGeneratedLevel` (`HJGenerator.swift:25`); `HJGenerator.campaignLevel(chapter:level:)` (`HJGenerator.swift:48`).

*Produces:*
```swift
enum HJBlockReason: Int, Codable, Equatable { case hull, sandbar, ferry, edge }
enum HJTapOutcome: Equatable {
    case exited(boatID: Int)
    case moved(boatID: Int, distance: Int)
    case blocked(reason: HJBlockReason)
    case anchored
    case invalid
}
extension HJEngine { static func tickWorld(_ state: inout HJBoardState) }
// plus, file-private to HJEngine.swift:
//   private static func blockReason(for boat: HJBoat, state: HJBoardState) -> HJBlockReason
```

*Deliberately NOT produced here* — these belong to later tasks and must not appear in this commit: `march`, `preview`, `HJMovePreview`, `bowCells(of:)`, `applyCurrents(_:)`, `basins`, `throttle`, `HJSound`, the deletion of the tug economy. `applyCurrent(_:boatID:)` and `advanceFerry(_:)` keep their current private signatures and bodies untouched.

*Why this is safe for the baked corpus:* the engine is final at Task 4 and the corpus is baked after it, so changing `tap` here is in-order. And this change does not touch any successful tap — `HJGenerator.verify()` (`HJGenerator.swift:192-215`) replays a canonical all-`.exited` line, and `tickWorld` increments `taps` in exactly the position `afterMove` did, so `state.taps == level.par` at `:200` still holds and all 140 levels still generate (Step 10 measures this).

---

- [ ] **Step 1: Record the pre-change facts.**

  Run from the repo root and confirm the output matches character for character. If it does not, stop — the file is not the one this task was written against.

  ```bash
  cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam"
  grep -rn --include="*.swift" "\.blocked" .
  grep -rn --include="*.swift" "\.anchored" .
  grep -rn --include="*.swift" "afterMove" .
  ```

  Expected, exactly:

  ```text
  Harbor Jam/HJGameViewModel.swift:80:        case .blocked, .anchored:
  Harbor Jam/HJEngine.swift:111:        if steps == 0 { return .blocked }
  Harbor Jam/HJEngine.swift:72:        if state.isAnchored(boat) { return .anchored }
  Harbor Jam/HJGameViewModel.swift:80:        case .blocked, .anchored:
  Harbor Jam/HJEngine.swift:116:            afterMove(&state, movedBoatID: nil)
  Harbor Jam/HJEngine.swift:123:            afterMove(&state, movedBoatID: boatID)
  Harbor Jam/HJEngine.swift:129:    private static func afterMove(_ state: inout HJBoardState, movedBoatID: Int?) {
  ```

  **The count that matters: `.blocked` appears twice in the whole repo — `HJEngine.swift:111` constructs it, and `HJGameViewModel.swift:80` is the one and only pattern-match on it.** `.anchored` likewise has exactly one match site, the same line. `HJGenerator.swift:198` and `:209` match `.exited` only and need no edit.

- [ ] **Step 2: Add the harness check.**

  Create `tools/HarborForge/check_tickworld.swift` with exactly this content. It compiles against **both** the old and the new `HJTapOutcome` (it never names `.blocked`), which is what lets Step 3 take a red baseline before any engine edit.

  ```bash
  cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam"
  mkdir -p tools/HarborForge
  ```

  ```swift
  import Foundation

  // Harbor Jam — Task 2 check: "every tap ticks the world".
  // Compiled by plain swiftc against the real HJModels / HJEngine / HJGenerator sources.
  // Measures three things and fails the gate on the first two.

  /// The board with the tap counter erased — two states are the "same board" when only
  /// the counter differs.
  private func stripped(_ s: HJBoardState) -> HJBoardState { var t = s; t.taps = 0; return t }

  /// A board is dead when no sequence of taps can ever change it again. Advance the world
  /// with wasted taps for `horizon` ticks; if no boat tap ever alters board content, the
  /// level is frozen and restart is the player's only exit.
  private func isDead(_ s0: HJBoardState, horizon: Int = 24) -> Bool {
      var s = s0
      if s.isCleared { return false }
      for _ in 0..<horizon {
          for b in s.boats {
              var probe = s
              _ = HJEngine.tap(boatID: b.id, state: &probe)
              if stripped(probe) != stripped(s) { return false }
          }
          guard let first = s.boats.first else { return false }
          _ = HJEngine.tap(boatID: first.id, state: &s)
      }
      return true
  }

  @main
  struct HJCheckTickWorld {

      static func main() {
          var failures = 0

          // 1. The whole campaign must still generate.
          var levels: [(Int, Int, HJGeneratedLevel)] = []
          for ch in 0..<HJCatalog.chapters.count {
              for lv in 0..<HJCatalog.levelsPerChapter {
                  if let g = HJGenerator.campaignLevel(chapter: ch, level: lv) {
                      levels.append((ch, lv, g))
                  }
              }
          }
          let wanted = HJCatalog.chapters.count * HJCatalog.levelsPerChapter
          print("LEVELS_GENERATED \(levels.count) / \(wanted)")
          if levels.count == wanted {
              print("PASS  every campaign level generates")
          } else {
              print("FAIL  \(wanted - levels.count) campaign levels failed to generate")
              failures += 1
          }

          // 2. No level may be driven into a frozen board.
          var dead: [String] = []
          for (ch, lv, g) in levels {
              var rng = HJRandom(seed: UInt64(ch) &* 1000 &+ UInt64(lv) &+ 999)
              var frozen = false
              outer: for _ in 0..<300 {
                  var s = g.start
                  for _ in 0..<200 {
                      if s.isCleared { break }
                      if isDead(s) { frozen = true; break outer }
                      guard let b = rng.pick(s.boats) else { break }
                      _ = HJEngine.tap(boatID: b.id, state: &s)
                  }
              }
              if frozen { dead.append("\(ch)-\(lv)") }
          }
          print("DEAD_STATE_LEVELS \(dead.count) :: \(dead.joined(separator: ","))")
          if dead.isEmpty {
              print("PASS  no level reaches a frozen board")
          } else {
              print("FAIL  \(dead.count) levels reach a frozen board")
              failures += 1
          }

          // 3. The zero-thought policy rate. Task 2 is a bug fix, not a depth change, so
          //    this number must NOT move: it is reported, and only a wild swing fails.
          var threeStar = 0, cleared = 0, rollouts = 0
          for (ch, lv, g) in levels {
              var rng = HJRandom(seed: UInt64(ch) &* 77 &+ UInt64(lv) &* 13 &+ 5)
              for _ in 0..<100 {
                  var s = g.start
                  var steps = 0
                  while !s.isCleared && steps < 400 {
                      steps += 1
                      var exiters: [Int] = [], movers: [Int] = []
                      for b in s.boats {
                          var probe = s
                          let o = HJEngine.tap(boatID: b.id, state: &probe)
                          if case .exited = o { exiters.append(b.id) }
                          else if case .moved = o { movers.append(b.id) }
                      }
                      let pool = exiters.isEmpty ? movers : exiters
                      if pool.isEmpty { break }
                      _ = HJEngine.tap(boatID: pool[rng.int(pool.count)], state: &s)
                  }
                  rollouts += 1
                  if s.isCleared {
                      cleared += 1
                      if s.taps <= g.par { threeStar += 1 }
                  }
              }
          }
          let rate = Double(threeStar) / Double(rollouts) * 100.0
          let clr = Double(cleared) / Double(rollouts) * 100.0
          print(String(format: "GREEDY_3STAR %.2f%%  GREEDY_CLEARED %.2f%%  ROLLOUTS %d",
                       rate, clr, rollouts))
          if rate >= 90.0 {
              print("PASS  zero-thought rate unchanged (depth is Task 3's job, not Task 2's)")
          } else {
              print("FAIL  zero-thought rate moved — Task 2 must not change reachable difficulty")
              failures += 1
          }

          print(failures == 0 ? "ALL CHECKS PASSED" : "\(failures) CHECK(S) FAILED")
          exit(failures == 0 ? 0 : 1)
      }
  }
  ```

  This file carries its own `@main` and is compiled on its own source list, so it never collides with the Task 1 harness entry point.

- [ ] **Step 3: Take the red baseline — run the check against the UNCHANGED engine.**

  ```bash
  cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam"
  swiftc -O -o /tmp/hj_check_tickworld \
    "Harbor Jam/HJModels.swift" \
    "Harbor Jam/HJEngine.swift" \
    "Harbor Jam/HJGenerator.swift" \
    tools/HarborForge/check_tickworld.swift
  /tmp/hj_check_tickworld; echo "exit=$?"
  ```

  Takes about 5 s. The run is fully deterministic (`HJRandom` is SplitMix64 and no `Set` is ever iterated), so the output is reproducible byte for byte. Expected now — **exit=1 is correct at this step, it is the red test**:

  ```text
  LEVELS_GENERATED 140 / 140
  PASS  every campaign level generates
  DEAD_STATE_LEVELS 35 :: 2-0,2-3,2-4,2-6,2-7,2-8,2-9,2-10,2-12,2-13,2-16,2-18,2-19,5-1,5-3,5-4,5-6,5-9,5-12,5-13,5-15,5-16,6-1,6-4,6-5,6-6,6-7,6-10,6-11,6-12,6-14,6-15,6-16,6-17,6-18
  FAIL  35 levels reach a frozen board
  GREEDY_3STAR 96.54%  GREEDY_CLEARED 98.76%  ROLLOUTS 14000
  PASS  zero-thought rate unchanged (depth is Task 3's job, not Task 2's)
  1 CHECK(S) FAILED
  exit=1
  ```

  Note the 35 frozen levels sit only in chapters 2, 5 and 6 — the three ferry chapters, exactly as the spec's root-cause 5 predicts. Write down `GREEDY_3STAR 96.54%`; Step 10 must reprint it unchanged.

- [ ] **Step 4: `HJEngine.swift` — add `HJBlockReason` and reshape `.blocked`.**

  Replace the whole outcome declaration at `Harbor Jam/HJEngine.swift:59-65`:

  ```swift
  enum HJTapOutcome: Equatable {
      case exited(boatID: Int)
      case moved(boatID: Int, distance: Int)
      case blocked          // boat could not move at all (shake, no move cost)
      case anchored         // locked by buoy chain
      case invalid
  }
  ```

  with:

  ```swift
  /// Why a boat could not take its first step.
  enum HJBlockReason: Int, Codable, Equatable {
      case hull = 0       // another boat's hull
      case sandbar = 1    // a sandbar exposed at low tide
      case ferry = 2      // the ferry footprint
      case edge = 3       // the board edge on a non-bow side
  }

  enum HJTapOutcome: Equatable {
      case exited(boatID: Int)
      case moved(boatID: Int, distance: Int)
      case blocked(reason: HJBlockReason)   // boat could not move; the world still ticks
      case anchored                         // locked by buoy chain; the world still ticks
      case invalid
  }
  ```

- [ ] **Step 5: `HJEngine.swift` — the anchored tap becomes a wait move.**

  Replace the single line at `:72`:

  ```swift
          if state.isAnchored(boat) { return .anchored }
  ```

  with:

  ```swift
          if state.isAnchored(boat) {
              tickWorld(&state)
              return .anchored
          }
  ```

  `boat` was already read out of `state` on the line above, so mutating `state` here is safe.

- [ ] **Step 6: `HJEngine.swift` — the blocked tap becomes a wait move and names its reason.**

  Replace the single line at `:111`:

  ```swift
          if steps == 0 { return .blocked }
  ```

  with:

  ```swift
          if steps == 0 {
              let reason = blockReason(for: boat, state: state)
              tickWorld(&state)
              return .blocked(reason: reason)
          }
  ```

  Order is load-bearing: the reason describes why *this* tap failed, so it is classified against the pre-tick world, before the tide or the ferry move.

- [ ] **Step 7: `HJEngine.swift` — retarget the two `afterMove` call sites.**

  In the exit branch, replace `:116`:

  ```swift
              afterMove(&state, movedBoatID: nil)
  ```

  with:

  ```swift
              tickWorld(&state)
  ```

  In the move branch, replace `:123`:

  ```swift
              afterMove(&state, movedBoatID: boatID)
  ```

  with:

  ```swift
              tickWorld(&state)
              applyCurrent(&state, boatID: boatID)
  ```

  This preserves the old ordering exactly — `afterMove` ran taps, tide, ferry, *then* `applyCurrent`, and passed `nil` on an exit so no current fired. Successful taps therefore behave bit-identically, which is why the generator still yields 140/140.

- [ ] **Step 8: `HJEngine.swift` — replace `afterMove` with `tickWorld` + `blockReason`.**

  Replace the whole function at `:128-140`:

  ```swift
      /// Post-move world updates: tap counter, tide toggle, ferry advance, current push.
      private static func afterMove(_ state: inout HJBoardState, movedBoatID: Int?) {
          state.taps += 1
          if state.tideEnabled && state.taps % 3 == 0 {
              state.tideHigh.toggle()
              // A tide drop never traps a boat mid-sandbar: boats and sandbars never overlap
              // because sandbar cells are excluded from all placements and rest positions.
          }
          advanceFerry(&state)
          if let id = movedBoatID {
              applyCurrent(&state, boatID: id)
          }
      }
  ```

  with:

  ```swift
      /// One world advance. Runs on every tap outcome except `.invalid` — a blocked or an
      /// anchored tap is a wait move, so the tide and the ferry still move. This is what
      /// stops a ferry-blocked board from freezing forever.
      static func tickWorld(_ state: inout HJBoardState) {
          state.taps += 1
          if state.tideEnabled && state.taps % 3 == 0 {
              state.tideHigh.toggle()
              // A tide drop never traps a boat mid-sandbar: boats and sandbars never overlap
              // because sandbar cells are excluded from all placements and rest positions,
              // and a wait move does not relocate any hull.
          }
          advanceFerry(&state)
      }

      /// Classify why the first step of the march failed, by re-probing that one step.
      /// Reached only when the march advanced zero cells, so exactly one of these holds:
      /// an in-bounds cell of the candidate is solid, or a cell would have left the board
      /// on a side that is not the bow side.
      private static func blockReason(for boat: HJBoat, state: HJBoardState) -> HJBlockReason {
          var candidate = boat
          candidate.x += boat.bow.dx
          candidate.y += boat.bow.dy
          let insideCells = candidate.cells.filter { state.inBounds($0) }
          let hulls = state.occupied(excluding: boat.id)
          if insideCells.contains(where: { hulls.contains($0) }) { return .hull }
          let ferry = state.ferryCells()
          if insideCells.contains(where: { ferry.contains($0) }) { return .ferry }
          if state.tideEnabled && !state.tideHigh {
              let sand = Set(state.sandbars)
              if insideCells.contains(where: { sand.contains($0) }) { return .sandbar }
          }
          return .edge
      }
  ```

  `tickWorld` is internal, not private — the frozen contract exposes it on `HJEngine`. `advanceFerry` (`:142`) and `applyCurrent` (`:163`) stay exactly as they are; `applyCurrent` becomes `applyCurrents(_:)` in a later task, not here.

- [ ] **Step 9: `HJGameViewModel.swift:80` — the one external pattern-match.**

  Replace:

  ```swift
          case .blocked, .anchored:
  ```

  with:

  ```swift
          case .blocked(_), .anchored:
  ```

  Behaviour is unchanged on purpose: splitting the shake into "blocked by hull" / "blocked by sandbar" / "anchored" is spec §2.7 and belongs to the feedback task, not to this one. The explicit `(_)` records that the case now carries a payload so the next reader does not mistake the untouched body for an oversight. This is the only site in the repo — Step 1's grep proved the count is 1.

- [ ] **Step 10: Rerun the harness check — it must go green.**

  ```bash
  cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam"
  swiftc -O -o /tmp/hj_check_tickworld \
    "Harbor Jam/HJModels.swift" \
    "Harbor Jam/HJEngine.swift" \
    "Harbor Jam/HJGenerator.swift" \
    tools/HarborForge/check_tickworld.swift
  /tmp/hj_check_tickworld; echo "exit=$?"
  ```

  Required output, exactly:

  ```text
  LEVELS_GENERATED 140 / 140
  PASS  every campaign level generates
  DEAD_STATE_LEVELS 0 :: 
  PASS  no level reaches a frozen board
  GREEDY_3STAR 96.54%  GREEDY_CLEARED 98.76%  ROLLOUTS 14000
  PASS  zero-thought rate unchanged (depth is Task 3's job, not Task 2's)
  ALL CHECKS PASSED
  exit=0
  ```

  Three assertions, all enforced by the tool: 140/140 levels still generate, frozen boards go 35 → 0, and `GREEDY_3STAR` reprints the Step 3 figure to the hundredth. That last agreement is the point — Task 2 must not move reachable difficulty; if the rate shifts at all, a successful tap was changed and Step 7's ordering is wrong.

- [ ] **Step 11: Compile the app, Debug, iPhone 17 simulator.**

  ```bash
  cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam"
  xcodebuild -project "Harbor Jam.xcodeproj" -scheme "Harbor Jam" \
    -configuration Debug \
    -destination 'platform=iOS Simulator,name=iPhone 17' \
    -derivedDataPath /tmp/hj_dd_task2 build 2>&1 | tail -20
  ```

  Must end in `** BUILD SUCCEEDED **` with zero warnings. No pbxproj edit is needed for this task: `tools/HarborForge/check_tickworld.swift` lives outside the `Harbor Jam/` group and is never compiled into the app, and no `.swift` file was added to the target.

- [ ] **Step 12: Commit.**

  ```bash
  cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam"
  git add "Harbor Jam/HJEngine.swift" "Harbor Jam/HJGameViewModel.swift" tools/HarborForge/check_tickworld.swift
  git commit -m "Engine: every tap ticks the world; blocked taps name their reason

Delete the pre-mutation early returns for .anchored and .blocked. The tap
counter, the tide toggle and the ferry advance move into HJEngine.tickWorld,
which now runs on every outcome except .invalid, so a blocked or anchored tap
is a wait move. Add HJBlockReason and reshape .blocked to carry it, classified
by re-probing the first failed step.

Harness check_tickworld: frozen boards 35 -> 0 across the 140 campaign levels,
all 140 still generate, zero-thought 3-star rate unchanged at 96.54% (this is a
bug fix, not a depth change).

Co-Authored-By: Claude <noreply@anthropic.com>"
  ```


---

### Task 3: Model fields, the tug economy deleted, and the content-scale cap

Three jobs that must land together and must land before anything is baked:

**(a) New model fields.** `HJDirection.opposite`, `HJBoat.throttle`, `HJCurrentLane.period` + `effectivePush(atTick:)`, `HJBoardState.basins`, `HJLevelConfig.basinCount`. Every one of these lands with a hand-written `init(from:)` that uses `decodeIfPresent ?? default` on **every** key. A non-optional field added to a persisted `Codable` struct makes the synthesized decode throw on older payloads, and in this app that reads as "all progress silently wiped" — it has happened before, and `HJSave.swift:12-16` already shows the house pattern.

**(b) The tug economy is deleted, not stubbed.** `tugRotate`, `tugTokens`, `tugArmed`, `tugsUsed`, `tugChip`, `tugs_15`. Five later tasks assume it is gone; deleting it is real work with an exact grep gate below. `HJTugShape` (`HJTheme.swift:218`) **survives** — spec §2.4 reuses it as the basin tile art in a later UI task, so after this task it deliberately has zero call sites. That is correct, and it produces no warning (verified).

**(c) The content envelope is capped now.** Grids to 8×8, boats to 10, `basinCount >= 1` on every chapter from 2 onward. Task 7 bakes the shipped corpus out of this envelope; a cap applied after the bake would invalidate every witness, so it cannot wait.

**What this task does NOT do.** It does not touch `HJEngine.tap`, the march loop, `afterMove`, `advanceFerry` or `applyCurrent` — the engine becomes final in Task 4, and nothing after Task 4 may change it. It does not place a single basin cell: `basins` is declared and every generated board ships `basins: []`. It does not add `movesCommitted`, `HJProgressRecord`, the `hbj.state.v2` key, the new star bands, `HJMovePreview`, `preview`, `bowCells`, `HJSound` or the achievement rewrite — all later tasks.

**The audit numbers will move, and that is expected.** Chapter 6 loses a 9×9 grid and 4 boats, chapter 5 loses a row, chapter 4 loses a boat. Every seed that fed those configs now produces a different board, so the §1 measurements (96.63 % zero-thought clears, 777 first-tap exits, 21 dead-state levels) are all measured against boards that no longer exist. Do not re-measure them here and do not carry them forward. **The only assertion that must hold at the end of this task** is the one Step 15 enforces: all 140 campaign levels and 30 consecutive daily keys still generate, no generated *start* board is dead, and the capped envelope is respected on every one of the 141 configs. The *reachable* dead-state count is an engine property that Task 4's `tickWorld` fixes; it is not measurable — and not meaningful — against this task's unchanged engine.

**Files:**
- `/Users/vik/Documents/development/for_human_review_apps/Harbor Jam/Harbor Jam/HJModels.swift`
- `/Users/vik/Documents/development/for_human_review_apps/Harbor Jam/Harbor Jam/HJEngine.swift`
- `/Users/vik/Documents/development/for_human_review_apps/Harbor Jam/Harbor Jam/HJGenerator.swift`
- `/Users/vik/Documents/development/for_human_review_apps/Harbor Jam/Harbor Jam/HJGameViewModel.swift`
- `/Users/vik/Documents/development/for_human_review_apps/Harbor Jam/Harbor Jam/HJGameView.swift`
- `/Users/vik/Documents/development/for_human_review_apps/Harbor Jam/Harbor Jam/HJSave.swift`
- `/Users/vik/Documents/development/for_human_review_apps/Harbor Jam/Harbor Jam/HJAwardsView.swift`
- `/Users/vik/Documents/development/for_human_review_apps/Harbor Jam/Harbor Jam/HJMoreView.swift`
- `/Users/vik/Documents/development/for_human_review_apps/Harbor Jam/tools/checks/task3-envelope/main.swift` *(new; plain `swiftc`, not in the Xcode target, not in any package — no pbxproj change in this task)*

**Interfaces:**

*Consumes* — nothing from Task 1 or Task 2. Every symbol this task reads already exists at HEAD:
```swift
enum HJDirection: Int, Codable, CaseIterable            // HJModels.swift:4   — .dx/.dy/.rotatedCW/.isHorizontal
struct HJCell: Hashable, Codable                        // HJModels.swift:27
struct HJFerry: Codable, Equatable                      // HJModels.swift:62
enum HJCatalog                                          // HJModels.swift:90  — chapters, levelsPerChapter, totalLevels, seed(chapter:level:)
static func HJEngine.tap(boatID:state:) -> HJTapOutcome // HJEngine.swift:70  — read only, NOT modified here
enum HJGenerator                                        // HJGenerator.swift:31 — campaignLevel(chapter:level:), dailyLevel(dayKey:)
struct HJGeneratedLevel                                 // HJGenerator.swift:25
final class HJStore                                     // HJSave.swift:131
```

*Produces:*
```swift
// HJModels.swift
var HJDirection.opposite: HJDirection                                   // (rawValue + 2) % 4
var HJBoat.throttle: Int                                                // 1...3 once Task 5 tunes it
init(id:x:y:length:isBarge:bow:hullIndex:anchoredBy:throttle:)          // HJBoat, explicit
init(from decoder: Decoder) throws                                      // HJBoat, all keys decodeIfPresent
var HJCurrentLane.period: Int                                           // 0 = steady lane
init(isRow:index:push:period:)                                          // HJCurrentLane, explicit
init(from decoder: Decoder) throws                                      // HJCurrentLane, all keys decodeIfPresent
func HJCurrentLane.effectivePush(atTick tick: Int) -> HJDirection
var HJLevelConfig.basinCount: Int                                       // replaces tugTokens

// HJEngine.swift
var HJBoardState.basins: [HJCell]
init(gridW:gridH:boats:exitedIDs:sandbars:basins:currents:ferry:tideEnabled:tideHigh:taps:night:)
init(from decoder: Decoder) throws                                      // HJBoardState, all keys decodeIfPresent

// HJSave.swift — signatures narrowed, tugsUsed argument removed
func HJStore.reportCampaignWin(chapter:level:taps:par:usedUndo:boatsExited:undos:) -> Int
func HJStore.reportDailyWin(dayKey:taps:usedUndo:boatsExited:undos:)

// DELETED by this task
HJEngine.tugRotate(boatID:state:)      HJBoardState.tugTokens      HJLevelConfig.tugTokens
HJGameViewModel.tugArmed               HJGameViewModel.tugsUsed    HJGameView.tugChip
HJStats.tugsUsed                       achievement id "tugs_15"
```

---

- [ ] **Step 1: Add `HJDirection.opposite`.**
  In `Harbor Jam/HJModels.swift`, replace the `rotatedCW` property at lines 21-23 with the pair below. The frozen contract writes this as `extension HJDirection { var opposite: HJDirection }`; the symbol and signature are identical either way, and spec §2.3 asks for "the same shape as `rotatedCW`" — so it goes in the enum body immediately after it.
```swift
    var rotatedCW: HJDirection {
        HJDirection(rawValue: (rawValue + 1) % 4) ?? .north
    }
    /// 180° reversal. Same shape as `rotatedCW`; used by turning basins and by
    /// current lanes that flip polarity, neither of which may change a footprint.
    var opposite: HJDirection {
        HJDirection(rawValue: (rawValue + 2) % 4) ?? .north
    }
```

- [ ] **Step 2: Add `HJBoat.throttle` with explicit inits.**
  In `Harbor Jam/HJModels.swift`, replace lines 40-42 — that is, the `anchoredBy` declaration, the blank line, and the `var width: Int` line that follows it — with:
```swift
    var anchoredBy: Int?    // boat id that must exit before this one can move
    var throttle: Int       // cells advanced per tap (1...3), printed on the hull

    init(id: Int, x: Int, y: Int, length: Int, isBarge: Bool, bow: HJDirection,
         hullIndex: Int, anchoredBy: Int?, throttle: Int) {
        self.id = id
        self.x = x
        self.y = y
        self.length = length
        self.isBarge = isBarge
        self.bow = bow
        self.hullIndex = hullIndex
        self.anchoredBy = anchoredBy
        self.throttle = throttle
    }

    /// Every key is `decodeIfPresent`: a non-optional field added to a persisted
    /// Codable struct makes the synthesized decode throw on older data, which in
    /// this app reads as "all progress silently wiped".
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(Int.self, forKey: .id) ?? 0
        x = try c.decodeIfPresent(Int.self, forKey: .x) ?? 0
        y = try c.decodeIfPresent(Int.self, forKey: .y) ?? 0
        length = try c.decodeIfPresent(Int.self, forKey: .length) ?? 2
        isBarge = try c.decodeIfPresent(Bool.self, forKey: .isBarge) ?? false
        bow = try c.decodeIfPresent(HJDirection.self, forKey: .bow) ?? .east
        hullIndex = try c.decodeIfPresent(Int.self, forKey: .hullIndex) ?? 0
        anchoredBy = try c.decodeIfPresent(Int.self, forKey: .anchoredBy)
        throttle = try c.decodeIfPresent(Int.self, forKey: .throttle) ?? 1
    }

    var width: Int
```
  Declaring an explicit `init` suppresses the synthesized memberwise one, which is why it is written out by hand. `CodingKeys` is still synthesized (the `Encodable` half is), exactly as in `HJSave.swift:12-16`. Note `throttle` has **no** default in the memberwise init — the compiler must flag every construction site.

- [ ] **Step 3: Add `HJCurrentLane.period` and `effectivePush(atTick:)`.**
  In `Harbor Jam/HJModels.swift`, replace the whole `HJCurrentLane` struct at lines 56-60 with:
```swift
struct HJCurrentLane: Codable, Equatable {
    var isRow: Bool
    var index: Int              // row y or column x
    var push: HJDirection       // perpendicular push direction
    var period: Int             // 0 = steady lane; N > 0 flips the push every N ticks

    init(isRow: Bool, index: Int, push: HJDirection, period: Int) {
        self.isRow = isRow
        self.index = index
        self.push = push
        self.period = period
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isRow = try c.decodeIfPresent(Bool.self, forKey: .isRow) ?? true
        index = try c.decodeIfPresent(Int.self, forKey: .index) ?? 0
        push = try c.decodeIfPresent(HJDirection.self, forKey: .push) ?? .north
        period = try c.decodeIfPresent(Int.self, forKey: .period) ?? 0
    }

    /// The push actually applied on world tick `tick`. `period == 0` is a steady
    /// lane and always returns `push`, so a board built before periods existed
    /// behaves exactly as it did.
    func effectivePush(atTick tick: Int) -> HJDirection {
        guard period > 0 else { return push }
        return (tick / period) % 2 == 1 ? push.opposite : push
    }
}
```
  The `guard period > 0` is not optional: `period == 0` is the "no flip yet" default this task ships, and `tick / 0` traps. Task 5 draws periods from {2, 3, 4}; Task 4 is the only task that may call this from the engine.

- [ ] **Step 4: Swap `HJLevelConfig.tugTokens` for `basinCount`.**
  In `Harbor Jam/HJModels.swift`, replace lines 78-80:
```swift
    var chainCount: Int         // buoy anchor chains
    var basinCount: Int         // turning basins (a boat entering one flips its bow 180°)
    var night: Bool
```
  The file will not compile again until Step 5 rewrites the eight `HJLevelConfig(...)` call sites. That is intended — the compiler is the checklist.

- [ ] **Step 5: Rewrite `HJCatalog.config` — the content cap, all seven rows.**
  In `Harbor Jam/HJModels.swift`, replace the entire `static func config(chapter:level:)` body at lines 103-136 with the block below. Grid ≤ 8×8, boats ≤ 10, `basinCount >= 1` from chapter 2 on. Everything not forced by the cap is left exactly as it was, so the diff is auditable:
  - ch 0-3: mechanics, grids and ramps untouched; only `tugTokens: 0` → `basinCount:` 0/0/1/1.
  - ch 4: grid already 8×8; ramp top capped 11 → 10; `basinCount` ramps 1 → 2.
  - ch 5: 8×9 → 8×8 (72 cells → 64, −11 %), so the opening count drops 8 → 7 to hold density roughly constant; top capped 12 → 10.
  - ch 6: 9×9 → 8×8 (81 → 64, −21 %); ramp 9…14 → 8…10.
```swift
    static func config(chapter: Int, level: Int) -> HJLevelConfig {
        let t = Double(level) / Double(levelsPerChapter - 1)   // 0..1 inside chapter
        func ramp(_ a: Int, _ b: Int) -> Int { a + Int((Double(b - a) * t).rounded()) }
        switch chapter {
        case 0:
            return HJLevelConfig(gridW: 6, gridH: 6, boatCount: ramp(3, 7), bargeCount: 0,
                                 useCurrents: false, useTide: false, useFerry: false,
                                 chainCount: 0, basinCount: 0, night: false)
        case 1:
            return HJLevelConfig(gridW: 6, gridH: 7, boatCount: ramp(5, 9), bargeCount: level >= 12 ? 1 : 0,
                                 useCurrents: true, useTide: false, useFerry: false,
                                 chainCount: 0, basinCount: 0, night: false)
        case 2:
            return HJLevelConfig(gridW: 7, gridH: 7, boatCount: ramp(6, 10), bargeCount: level >= 10 ? 1 : 0,
                                 useCurrents: false, useTide: false, useFerry: true,
                                 chainCount: 0, basinCount: 1, night: false)
        case 3:
            return HJLevelConfig(gridW: 7, gridH: 8, boatCount: ramp(6, 10), bargeCount: 1,
                                 useCurrents: false, useTide: true, useFerry: false,
                                 chainCount: 0, basinCount: 1, night: false)
        case 4:
            return HJLevelConfig(gridW: 8, gridH: 8, boatCount: ramp(7, 10), bargeCount: 1,
                                 useCurrents: true, useTide: true, useFerry: false,
                                 chainCount: level >= 6 ? 2 : 1, basinCount: ramp(1, 2), night: false)
        case 5:
            return HJLevelConfig(gridW: 8, gridH: 8, boatCount: ramp(7, 10), bargeCount: 1,
                                 useCurrents: true, useTide: false, useFerry: true,
                                 chainCount: 1, basinCount: 2, night: true)
        default:
            return HJLevelConfig(gridW: 8, gridH: 8, boatCount: ramp(8, 10), bargeCount: 2,
                                 useCurrents: true, useTide: true, useFerry: true,
                                 chainCount: 2, basinCount: 2, night: false)
        }
    }
```

- [ ] **Step 6: Rewrite `dailyConfig`.**
  In `Harbor Jam/HJModels.swift`, replace lines 147-149. 7×8 is already inside the cap, so only the tug field changes:
```swift
    static let dailyConfig = HJLevelConfig(gridW: 7, gridH: 8, boatCount: 9, bargeCount: 1,
                                           useCurrents: true, useTide: true, useFerry: false,
                                           chainCount: 1, basinCount: 2, night: false)
```

- [ ] **Step 7: `HJBoardState` — add `basins`, drop `tugTokens`, hand-write both inits.**
  In `Harbor Jam/HJEngine.swift`, replace lines 7-18 (from `var boats: [HJBoat]` through the `isCleared` line) with:
```swift
    var boats: [HJBoat]
    var exitedIDs: [Int]
    var sandbars: [HJCell]
    var basins: [HJCell]        // turning basins: a bow entering one stops and flips 180°
    var currents: [HJCurrentLane]
    var ferry: HJFerry?
    var tideEnabled: Bool
    var tideHigh: Bool
    var taps: Int
    var night: Bool

    init(gridW: Int, gridH: Int, boats: [HJBoat], exitedIDs: [Int], sandbars: [HJCell],
         basins: [HJCell], currents: [HJCurrentLane], ferry: HJFerry?,
         tideEnabled: Bool, tideHigh: Bool, taps: Int, night: Bool) {
        self.gridW = gridW
        self.gridH = gridH
        self.boats = boats
        self.exitedIDs = exitedIDs
        self.sandbars = sandbars
        self.basins = basins
        self.currents = currents
        self.ferry = ferry
        self.tideEnabled = tideEnabled
        self.tideHigh = tideHigh
        self.taps = taps
        self.night = night
    }

    /// Every key is `decodeIfPresent`. This state is what the baked level table
    /// carries, so a field added later must never make an older payload throw.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        gridW = try c.decodeIfPresent(Int.self, forKey: .gridW) ?? 6
        gridH = try c.decodeIfPresent(Int.self, forKey: .gridH) ?? 6
        boats = try c.decodeIfPresent([HJBoat].self, forKey: .boats) ?? []
        exitedIDs = try c.decodeIfPresent([Int].self, forKey: .exitedIDs) ?? []
        sandbars = try c.decodeIfPresent([HJCell].self, forKey: .sandbars) ?? []
        basins = try c.decodeIfPresent([HJCell].self, forKey: .basins) ?? []
        currents = try c.decodeIfPresent([HJCurrentLane].self, forKey: .currents) ?? []
        ferry = try c.decodeIfPresent(HJFerry.self, forKey: .ferry)
        tideEnabled = try c.decodeIfPresent(Bool.self, forKey: .tideEnabled) ?? false
        tideHigh = try c.decodeIfPresent(Bool.self, forKey: .tideHigh) ?? true
        taps = try c.decodeIfPresent(Int.self, forKey: .taps) ?? 0
        night = try c.decodeIfPresent(Bool.self, forKey: .night) ?? false
    }

    var isCleared: Bool { boats.isEmpty }
```
  `basins` sits directly after `sandbars` — both are cell decorations and the two are read together by the board renderer later. Do **not** give `basins` a default in the memberwise init.

- [ ] **Step 8: Delete `tugRotate`.**
  In `Harbor Jam/HJEngine.swift`, delete lines 180-200 — the doc comment `/// Tug power-up: rotate a boat 90° clockwise in place around its top-left cell.` through the closing `}` of the function — leaving the file ending:
```swift
        let solids = state.solidCells(excluding: boatID)
        let cells = moved.cells
        guard cells.allSatisfy({ state.inBounds($0) && !solids.contains($0) }) else { return }
        state.boats[idx] = moved
    }
}
```
  Nothing else in `HJEngine.swift` changes in this task. `tap`, the `while true` march, `afterMove`, `advanceFerry` and `applyCurrent` are Task 4's to rewrite.

- [ ] **Step 9: `HJGenerator` — throttle, period, basins, no tug.**
  Three edits in `Harbor Jam/HJGenerator.swift`.
  (i) Lines 88-89 become:
```swift
                var boat = HJBoat(id: exitIndex, x: 0, y: 0, length: length, isBarge: isBarge,
                                  bow: bow, hullIndex: rng.int(8), anchoredBy: nil,
                                  throttle: w + h + 4)
```
  `w + h + 4` is deliberate: it is the exact safety bound the current march uses at `HJEngine.swift:108`, so when Task 4 turns `while true` into `for _ in 0..<boat.throttle` the march is bit-identical to today's on every board this generator makes. Task 5 replaces the whole construction and draws throttle from 1…3.
  (ii) Line 155 becomes:
```swift
                currents.append(HJCurrentLane(isRow: isRow, index: index, push: push, period: 0))
```
  (iii) Lines 166-169 become:
```swift
        let state = HJBoardState(gridW: w, gridH: h, boats: boats, exitedIDs: [],
                                 sandbars: sandbars, basins: [], currents: currents,
                                 ferry: ferry, tideEnabled: config.useTide, tideHigh: true,
                                 taps: 0, night: config.night)
```

- [ ] **Step 10: Strip the tug from `HJGameViewModel`.**
  Four edits in `Harbor Jam/HJGameViewModel.swift`.
  (i) Delete line 21 `@Published var tugArmed = false`.
  (ii) Delete line 25 `private(set) var tugsUsed = 0`.
  (iii) Replace lines 51-65 — from `guard !won else { return }` through `let before = state` — with:
```swift
        guard !won else { return }
        let before = state
```
  (iv) In `restart()`, delete line 101 `tugArmed = false`, leaving:
```swift
        state = initialState
    }
```
  (v) Drop the `tugsUsed:` argument from both report calls (lines 110-114 and 117-120):
```swift
            earnedStars = store.reportCampaignWin(chapter: chapter, level: level,
                                                  taps: state.taps, par: par,
                                                  usedUndo: undosUsed > 0,
                                                  boatsExited: totalBoats,
                                                  undos: undosUsed)
```
```swift
            store.reportDailyWin(dayKey: dayKey, taps: state.taps,
                                 usedUndo: undosUsed > 0,
                                 boatsExited: totalBoats,
                                 undos: undosUsed)
```

- [ ] **Step 11: Delete `tugChip` from `HJGameView`.**
  Two edits in `Harbor Jam/HJGameView.swift`.
  (i) Delete lines 90-92 from `hudRow`, so it reads:
```swift
    private var hudRow: some View {
        HStack(spacing: 8) {
            hudChip(label: "MOVES", value: "\(vm.state.taps)/\(vm.par)")
            hudChip(label: "BOATS", value: "\(vm.boatsRemaining)/\(vm.totalBoats)")
            if vm.state.tideEnabled {
                tideChip
            }
        }
    }
```
  (ii) Delete the whole `tugChip` property, lines 129-147, plus the blank line after it — `private var controls: some View {` now follows `tideChip`'s closing brace.

- [ ] **Step 12: Strip the tug from `HJSave`.**
  Six edits in `Harbor Jam/HJSave.swift`.
  (i) Delete line 24 `var tugsUsed: Int` from `HJStats`.
  (ii) Line 30 becomes `        boatsExited = 0; dailiesCompleted = 0; winsWithoutUndo = 0`.
  (iii) Delete line 38, the `tugsUsed` `decodeIfPresent`.
  (iv) Delete line 126, the `tugs_15` achievement. The list is now 19 entries; Task 9 rewrites it around first clears and Clean Lines.
  (v) Narrow the three signatures — line 188, line 204, line 223 — to drop `tugsUsed: Int`:
```swift
    func reportCampaignWin(chapter: Int, level: Int, taps: Int, par: Int, usedUndo: Bool, boatsExited: Int, undos: Int) -> Int {
```
```swift
    func reportDailyWin(dayKey: Int, taps: Int, usedUndo: Bool, boatsExited: Int, undos: Int) {
```
```swift
    private func applyCommonWinStats(taps: Int, usedUndo: Bool, boatsExited: Int, undos: Int) {
```
  (vi) Both call sites (lines 197 and 218) become `applyCommonWinStats(taps: taps, usedUndo: usedUndo, boatsExited: boatsExited, undos: undos)`, and line 227 `save.stats.tugsUsed += tugsUsed` is deleted so the body reads:
```swift
        save.stats.totalTaps += taps
        save.stats.totalUndos += undos
        save.stats.boatsExited += boatsExited
        if !usedUndo { save.stats.winsWithoutUndo += 1 }
```
  The save key is **not** bumped here — `hbj.state.v2` is the scoring task's change. Removing a stat field is safe on old payloads precisely because `HJStats.init(from:)` is all `decodeIfPresent`.

- [ ] **Step 13: Delete the two remaining tug surfaces in the UI.**
  (i) `Harbor Jam/HJAwardsView.swift` line 60: delete `            statRow("Tug rotations", "\(store.save.stats.tugsUsed)")` — it no longer compiles anyway.
  (ii) `Harbor Jam/HJMoreView.swift` lines 181-186: delete the entire "The Tug" codex entry, so the "Buoy Chains" entry's closing `}` is followed directly by `codexEntry(title: "Barges",`. It is copy describing a mechanic that no longer exists; the Turning Basin entry that replaces it (reusing `HJTugShape` as its icon) belongs to the later UI task.

- [ ] **Step 14: Grep gate — the economy must reach zero.**
  Run both, from the repo root:
```bash
cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam"
grep -rnE 'tugTokens|tugRotate|tugArmed|tugsUsed|tugChip|tugs_15' "Harbor Jam" --include='*.swift' | wc -l
grep -rni 'tug' "Harbor Jam" --include='*.swift'
```
  At HEAD the first command prints **45** and the second prints **51** lines. After Steps 1-13 the first command must print **0**, and the second must print exactly one line and no more:
```
Harbor Jam/HJTheme.swift:218:struct HJTugShape: Shape {
```
  Any other survivor is a missed deletion — fix it before continuing. `HJTugShape` itself is kept on purpose (spec §2.4, basin tile art) and having no call sites produces no warning.

- [ ] **Step 15: Write the envelope check tool.**
  Paste verbatim, from the repo root. This is a standalone `swiftc` program compiled against the three real sources — it does not join any Xcode target, any SwiftPM package, or `tools/HarborForge`, so nothing an earlier or later task builds can collide with it. The filename must be `main.swift`: Swift only permits top-level statements in a file with that name.
```bash
cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam"
mkdir -p tools/checks/task3-envelope
cat > tools/checks/task3-envelope/main.swift <<'SWIFTEOF'
// Task 3 acceptance check. Compiled directly with swiftc against the real
// HJModels / HJEngine / HJGenerator sources — no Xcode target, no package.
// Prints PASS/FAIL per clause and exits non-zero if any clause fails.
import Foundation

var failures: [String] = []

func check(_ name: String, _ ok: Bool, _ detail: String) {
    print("\(ok ? "PASS" : "FAIL")  \(name)  — \(detail)")
    if !ok { failures.append(name) }
}

// C1 — the whole campaign still generates under the capped envelope.
var generated: [(Int, Int, HJGeneratedLevel)] = []
var misses: [String] = []
for ch in 0..<HJCatalog.chapters.count {
    for lv in 0..<HJCatalog.levelsPerChapter {
        if let g = HJGenerator.campaignLevel(chapter: ch, level: lv) {
            generated.append((ch, lv, g))
        } else {
            misses.append("\(ch)-\(lv)")
        }
    }
}
check("C1 campaign generates", misses.isEmpty && generated.count == HJCatalog.totalLevels,
      "\(generated.count)/\(HJCatalog.totalLevels) generated, misses: \(misses)")

// C2 — the daily config generates for a run of day keys.
var dailyMisses = 0
for day in 9000..<9030 where HJGenerator.dailyLevel(dayKey: day) == nil { dailyMisses += 1 }
check("C2 daily generates", dailyMisses == 0, "\(30 - dailyMisses)/30 day keys produced a board")

// C3 — the content envelope is capped everywhere.
var badEnvelope: [String] = []
func auditConfig(_ label: String, _ c: HJLevelConfig, chapter: Int?) {
    if c.gridW > 8 || c.gridH > 8 { badEnvelope.append("\(label) grid \(c.gridW)x\(c.gridH)") }
    if c.boatCount > 10 { badEnvelope.append("\(label) boats \(c.boatCount)") }
    if let ch = chapter, ch >= 2, c.basinCount < 1 { badEnvelope.append("\(label) basinCount \(c.basinCount)") }
}
for ch in 0..<HJCatalog.chapters.count {
    for lv in 0..<HJCatalog.levelsPerChapter {
        auditConfig("ch\(ch)-\(lv)", HJCatalog.config(chapter: ch, level: lv), chapter: ch)
    }
}
auditConfig("daily", HJCatalog.dailyConfig, chapter: nil)
check("C3 envelope capped", badEnvelope.isEmpty, "violations: \(badEnvelope)")

// C4 — no generated START board is dead: at least one tap changes the board.
// Reachable dead states are an engine property; Task 4's tickWorld owns those.
var deadStarts: [String] = []
for (ch, lv, g) in generated {
    var alive = false
    for boat in g.start.boats {
        var probe = g.start
        switch HJEngine.tap(boatID: boat.id, state: &probe) {
        case .exited, .moved: alive = true
        default: break
        }
        if alive { break }
    }
    if !alive { deadStarts.append("\(ch)-\(lv)") }
}
check("C4 no dead start boards", deadStarts.isEmpty, "dead starts: \(deadStarts)")

// C5 — every boat carries a usable throttle and every lane a legal period.
var badBoats = 0
var badLanes = 0
for (_, _, g) in generated {
    for b in g.start.boats where b.throttle < 1 { badBoats += 1 }
    for l in g.start.currents {
        if l.period < 0 { badLanes += 1 }
        if l.effectivePush(atTick: 0) != l.push { badLanes += 1 }
    }
}
check("C5 throttle + period sane", badBoats == 0 && badLanes == 0,
      "boats with throttle < 1: \(badBoats), bad lanes: \(badLanes)")

// C6 — opposite is an involution and preserves the horizontal/vertical axis.
var badDir = 0
for d in HJDirection.allCases {
    if d.opposite.opposite != d { badDir += 1 }
    if d.opposite.isHorizontal != d.isHorizontal { badDir += 1 }
    if d.opposite == d { badDir += 1 }
}
check("C6 opposite well-formed", badDir == 0, "violations: \(badDir)")

// C7 — a lane with a period actually flips, and flips back.
let lane = HJCurrentLane(isRow: true, index: 0, push: .north, period: 2)
let flips = (lane.effectivePush(atTick: 0) == .north)
    && (lane.effectivePush(atTick: 1) == .north)
    && (lane.effectivePush(atTick: 2) == .south)
    && (lane.effectivePush(atTick: 3) == .south)
    && (lane.effectivePush(atTick: 4) == .north)
check("C7 period flips push", flips, "period-2 lane over ticks 0...4")

// C8 — a payload written before throttle/basins/period existed still decodes.
let legacy = """
{"gridW":6,"gridH":6,"boats":[{"id":0,"x":0,"y":0,"length":2,"isBarge":false,"bow":1,"hullIndex":0}],
 "exitedIDs":[],"sandbars":[],"currents":[{"isRow":true,"index":0,"push":0}],
 "tideEnabled":false,"tideHigh":true,"taps":0,"night":false}
"""
do {
    let s = try JSONDecoder().decode(HJBoardState.self, from: Data(legacy.utf8))
    check("C8 legacy decode", s.boats.count == 1 && s.boats[0].throttle == 1
          && s.basins.isEmpty && s.currents[0].period == 0,
          "throttle \(s.boats[0].throttle), basins \(s.basins.count), period \(s.currents[0].period)")
} catch {
    check("C8 legacy decode", false, "threw: \(error)")
}

print(failures.isEmpty ? "\nALL CHECKS PASSED" : "\nFAILED: \(failures.joined(separator: ", "))")
exit(failures.isEmpty ? 0 : 1)
SWIFTEOF
```

- [ ] **Step 16: Compile and run the check.**
```bash
cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam"
mkdir -p build
swiftc -O -o build/hjcheck-task3 \
  "Harbor Jam/HJModels.swift" "Harbor Jam/HJEngine.swift" "Harbor Jam/HJGenerator.swift" \
  tools/checks/task3-envelope/main.swift
./build/hjcheck-task3
echo "EXIT=$?"
```
  **The assertion:** the compile emits nothing, all eight lines print `PASS`, the last line is `ALL CHECKS PASSED`, and `EXIT=0`. `build/` is already in `.gitignore` (line 2), so the binary is never committed. If C1 or C2 fails, the capped envelope has starved the reverse generator on some seed — raise that chapter's grid back toward 8×8 or lower its boat ramp by one and re-run; do **not** relax the 8×8 / 10-boat cap, because Task 7 bakes against it.

- [ ] **Step 17: Compile-check the app target.**
```bash
cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam"
xcodebuild -project "Harbor Jam.xcodeproj" -scheme "Harbor Jam" \
  -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath build/dd-task3 build 2>&1 | tail -20
```
  **The assertion:** the output ends `** BUILD SUCCEEDED **` with zero warnings. Only `iPhone 17`-series simulators exist on this machine — `iPhone 15` destinations fail here. No file was added to the Xcode target in this task, so the hand-authored pbxproj is untouched; if the build complains about a missing file, something outside this task's scope changed it.

- [ ] **Step 18: Commit.**
```bash
cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam"
rm -rf build/dd-task3 build/hjcheck-task3
git add "Harbor Jam/HJModels.swift" "Harbor Jam/HJEngine.swift" "Harbor Jam/HJGenerator.swift" \
        "Harbor Jam/HJGameViewModel.swift" "Harbor Jam/HJGameView.swift" "Harbor Jam/HJSave.swift" \
        "Harbor Jam/HJAwardsView.swift" "Harbor Jam/HJMoreView.swift" \
        tools/checks/task3-envelope/main.swift
git commit -m "Models: throttle, basins, lane periods; delete the tug economy; cap content at 8x8/10 boats

Adds HJDirection.opposite, HJBoat.throttle, HJCurrentLane.period +
effectivePush(atTick:), HJBoardState.basins and HJLevelConfig.basinCount.
Every new field lands with a hand-written init(from:) that decodeIfPresent's
every key, so no persisted payload can throw.

Deletes the tug economy outright: tugRotate, tugTokens, tugArmed, tugsUsed,
tugChip, the tugs_15 achievement and the Tug codex entry. HJTugShape is kept
for the basin tile art. Economy references: 45 -> 0.

Caps the content envelope before anything is baked: grids at 8x8, boats at 10,
basinCount >= 1 from chapter 2 on. Chapter 6 drops 9x9/14 boats, chapter 5
drops a row. Board contents move as a result; tools/checks/task3-envelope
asserts 140/140 campaign levels and 30/30 daily keys still generate, no start
board is dead, and the cap holds on all 141 configs.

The engine's march is untouched; the generator ships throttle = w + h + 4 so
Task 4's bounded march is bit-identical on these boards. No basin cell is
placed yet.

Co-Authored-By: Claude <noreply@anthropic.com>"
```


---

### Task 4: The engine, final — march, throttle, basins, live currents, preview

**This is the last task that may touch game rules.** When it lands, `march`, `tap`, `tickWorld`, `applyCurrents` and the basin rule are frozen: Task 7 bakes every par and witness line by searching against exactly these functions, so any later edit to them silently invalidates the whole corpus.

**Files:**

| Path | Change |
|---|---|
| `Harbor Jam/HJEngine.swift` | rewritten in full (201 → ~310 lines) |
| `Harbor Jam/HJGenerator.swift` | one line — `basins: []` in the `HJBoardState(...)` construction at `:166-169` |
| `Harbor Jam/HJBoardView.swift` | one line — `.clipped()` on `boatLayer` (`:172`) |
| `tools/HarborForge/EngineChecks/Support.swift` | new |
| `tools/HarborForge/EngineChecks/main.swift` | new |

No pbxproj work: this task adds no file to the app target, so it uses none of the centrally-assigned object ids. The two new `.swift` files live under `tools/` and are compiled by `swiftc` only.

**Interfaces:**

*Consumes* (all defined by earlier tasks; Step 1 is the gate that proves they landed):

- `HJDirection.opposite: HJDirection` — `HJModels.swift` (models task)
- `HJBoat.throttle: Int` (1…3, declared last in the struct, so it is the last memberwise-init label) — `HJModels.swift` (models task)
- `HJCurrentLane.period: Int` and `func effectivePush(atTick tick: Int) -> HJDirection` — `HJModels.swift` (models task)
- the tug economy is already deleted: no `tugTokens` on `HJBoardState`/`HJLevelConfig`, no `HJEngine.tugRotate`, no `tugArmed`/`tugsUsed` on the view model, no `tugChip` in `HJGameView` (deletions task)
- `tools/HarborForge/` exists (harness task). No dependency on its contents — this task compiles a separate binary from its own subdirectory, and Step 7 creates the subdirectory either way.

*Produces:*

```
enum HJBlockReason: Int, Codable, Equatable { case hull, sandbar, ferry, edge }

enum HJTapOutcome: Equatable {
    case exited(boatID: Int)
    case moved(boatID: Int, distance: Int)
    case blocked(reason: HJBlockReason)
    case anchored
    case invalid
}

struct HJMovePreview: Equatable {
    var landing: [HJCell]        // footprint after the move, incl. cells past the bow-side edge
    var exits: Bool
    var distance: Int            // 0...throttle
    var stopReason: HJBlockReason?
}

HJBoardState.basins: [HJCell]                       // new stored property, after `sandbars`
HJBoardState.sandbarCells() -> Set<HJCell>          // new helper; solidCells now unions it

HJEngine.bowCells(of boat: HJBoat) -> [HJCell]      // DECLARED ONCE — here, and nowhere else
HJEngine.march(boat: HJBoat, state: HJBoardState) -> HJMovePreview
HJEngine.preview(boatID: Int, state: HJBoardState) -> HJMovePreview
HJEngine.tap(boatID: Int, state: inout HJBoardState) -> HJTapOutcome
HJEngine.tickWorld(_ state: inout HJBoardState)
HJEngine.applyCurrents(_ state: inout HJBoardState)
```

*Deleted:* `HJEngine.afterMove(_:movedBoatID:)`, `HJEngine.applyCurrent(_:boatID:)`, the unbounded `while true` march, the free `.blocked` / `.anchored` early returns.

---

- [ ] **Step 1: Gate — prove the prerequisite tasks landed.** From the repo root `/Users/vik/Documents/development/for_human_review_apps/Harbor Jam`:

```bash
cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam"
grep -n "var opposite\|var throttle\|var period\|func effectivePush" "Harbor Jam/HJModels.swift"
grep -rn "tug\|Tug" "Harbor Jam"/*.swift | wc -l
```

The first command must print four lines (one per symbol). The second must print `0`. If either assertion fails, the models task or the deletions task has not landed — stop here and finish it first; every step below assumes both.

- [ ] **Step 2: Rewrite `Harbor Jam/HJEngine.swift` in full.** Replace the entire file with the text below. It carries `HJBoardState` (plus `basins` and `sandbarCells()`), the outcome/preview types, the one walker, the thin `tap`, `tickWorld` and `applyCurrents`. `advanceFerry` is unchanged except that it now calls `state.sandbarCells()` instead of recomputing the low-tide set inline.

```swift
import Foundation

/// Full, deterministic play-state of one level. Value type — undo is a snapshot stack.
///
/// Never written to the save file (HJSave persists per-level records only); it is decoded
/// solely from the baked `levels.json`, which is regenerated whenever this type changes.
struct HJBoardState: Codable, Equatable {
    var gridW: Int
    var gridH: Int
    var boats: [HJBoat]
    var exitedIDs: [Int]
    var sandbars: [HJCell]
    /// Turning basins. A boat whose bow cell enters one stops on it and its bow flips 180°.
    var basins: [HJCell]
    var currents: [HJCurrentLane]
    var ferry: HJFerry?
    var tideEnabled: Bool
    var tideHigh: Bool
    var taps: Int
    var night: Bool

    var isCleared: Bool { boats.isEmpty }

    func boat(withID id: Int) -> HJBoat? { boats.first(where: { $0.id == id }) }

    func occupied(excluding boatID: Int? = nil) -> Set<HJCell> {
        var out = Set<HJCell>()
        for b in boats where b.id != boatID {
            for c in b.cells { out.insert(c) }
        }
        return out
    }

    func ferryCells() -> Set<HJCell> {
        guard let f = ferry else { return [] }
        var out = Set<HJCell>()
        for i in 0..<f.length {
            let x = (f.x + i) % gridW
            out.insert(HJCell(x: x, y: f.row))
        }
        return out
    }

    /// Sandbars are solid only at low tide.
    func sandbarCells() -> Set<HJCell> {
        (tideEnabled && !tideHigh) ? Set(sandbars) : []
    }

    func solidCells(excluding boatID: Int? = nil) -> Set<HJCell> {
        var out = occupied(excluding: boatID)
        out.formUnion(ferryCells())
        out.formUnion(sandbarCells())
        return out
    }

    func inBounds(_ c: HJCell) -> Bool {
        c.x >= 0 && c.x < gridW && c.y >= 0 && c.y < gridH
    }

    func isAnchored(_ boat: HJBoat) -> Bool {
        guard let key = boat.anchoredBy else { return false }
        return !exitedIDs.contains(key)
    }
}

/// Why a march stopped short of its throttle. Raw values are stable — they cross the
/// engine/UI boundary and are read back from diagnostics.
enum HJBlockReason: Int, Codable, Equatable {
    case hull, sandbar, ferry, edge
}

enum HJTapOutcome: Equatable {
    case exited(boatID: Int)
    case moved(boatID: Int, distance: Int)
    case blocked(reason: HJBlockReason)
    case anchored         // locked by buoy chain
    case invalid
}

/// Where a boat ends up, as computed by `HJEngine.march`. `preview` and `tap` read the same
/// value, so the ghost hull the player is shown and the move the engine commits cannot disagree.
struct HJMovePreview: Equatable {
    /// The boat's footprint after the move, including any cells past the bow-side edge.
    /// Empty when the boat exits or cannot move at all.
    var landing: [HJCell]
    var exits: Bool
    /// Cells advanced, 0…throttle.
    var distance: Int
    /// Non-nil only when an obstruction ended the march early. A full-throttle move and a
    /// basin stop both report nil; a zero-distance march always reports a reason.
    var stopReason: HJBlockReason?
}

enum HJEngine {

    // MARK: - March — the one walker

    /// The leading edge of a boat's footprint, one cell thick, on the bow side.
    static func bowCells(of boat: HJBoat) -> [HJCell] {
        switch boat.bow {
        case .east:
            let x = boat.x + boat.width - 1
            return (0..<boat.height).map { HJCell(x: x, y: boat.y + $0) }
        case .west:
            return (0..<boat.height).map { HJCell(x: boat.x, y: boat.y + $0) }
        case .south:
            let y = boat.y + boat.height - 1
            return (0..<boat.width).map { HJCell(x: boat.x + $0, y: y) }
        case .north:
            return (0..<boat.width).map { HJCell(x: boat.x + $0, y: boat.y) }
        }
    }

    private struct MarchDetail {
        var preview: HJMovePreview
        /// The boat as it comes to rest, bow already flipped if it stopped in a basin.
        /// nil when the boat exits or does not move.
        var landed: HJBoat?
    }

    /// THE single source of truth for where a tapped boat goes. `tap` commits what this
    /// returns and `preview` shows it, so the two can never diverge.
    ///
    /// Walks at most `boat.throttle` cells along the bow, one cell at a time:
    /// * an in-bounds candidate cell that is solid ends the march and names the cause;
    /// * a candidate shedding cells past an edge other than the bow-side edge is illegal and
    ///   ends the march with `.edge` (defensive: straight travel only sheds past the bow side);
    /// * shedding every in-bounds cell is an exit;
    /// * a bow cell landing on a turning basin ends the march there and flips the bow 180°.
    ///   `opposite` swaps east↔west / north↔south and `HJBoat.width`/`height`
    ///   (HJModels.swift:42-43) derive purely from `bow.isHorizontal`, so the footprint is
    ///   unchanged and no collision check is needed.
    ///
    /// FROZEN. Every baked par and witness line in levels.json is searched against this
    /// function; changing it invalidates the whole corpus.
    static func march(boat: HJBoat, state: HJBoardState) -> HJMovePreview {
        marchDetail(boat: boat, state: state).preview
    }

    /// Read-only march for a boat already on the board. Buoy chains are not consulted —
    /// a caller drawing a ghost checks `state.isAnchored(boat)` itself.
    static func preview(boatID: Int, state: HJBoardState) -> HJMovePreview {
        guard let boat = state.boat(withID: boatID) else {
            return HJMovePreview(landing: [], exits: false, distance: 0, stopReason: nil)
        }
        return march(boat: boat, state: state)
    }

    private static func marchDetail(boat: HJBoat, state: HJBoardState) -> MarchDetail {
        let hulls = state.occupied(excluding: boat.id)
        let ferry = state.ferryCells()
        let sand = state.sandbarCells()
        let basins = Set(state.basins)
        let dx = boat.bow.dx, dy = boat.bow.dy

        var current = boat
        var distance = 0
        var stopReason: HJBlockReason? = nil

        // throttle is 1…3 by construction; the clamp keeps the loop from running zero times,
        // so a zero-distance march always carries a reason.
        for _ in 0..<max(1, boat.throttle) {
            var candidate = current
            candidate.x += dx
            candidate.y += dy
            let cells = candidate.cells
            let inside = cells.filter { state.inBounds($0) }
            if let reason = blockReason(inside, hulls: hulls, ferry: ferry, sand: sand) {
                stopReason = reason
                break
            }
            let outside = cells.filter { !state.inBounds($0) }
            if !outside.isEmpty {
                let legal = outside.allSatisfy { c in
                    switch boat.bow {
                    case .east: return c.x >= state.gridW
                    case .west: return c.x < 0
                    case .south: return c.y >= state.gridH
                    case .north: return c.y < 0
                    }
                }
                if !legal { stopReason = .edge; break }
            }
            current = candidate
            distance += 1
            if inside.isEmpty {
                return MarchDetail(preview: HJMovePreview(landing: [], exits: true,
                                                          distance: distance, stopReason: nil),
                                   landed: nil)
            }
            if bowCells(of: current).contains(where: { basins.contains($0) }) {
                current.bow = current.bow.opposite
                break
            }
        }

        if distance == 0 {
            return MarchDetail(preview: HJMovePreview(landing: [], exits: false,
                                                      distance: 0, stopReason: stopReason),
                               landed: nil)
        }
        return MarchDetail(preview: HJMovePreview(landing: current.cells, exits: false,
                                                  distance: distance, stopReason: stopReason),
                           landed: current)
    }

    /// Deterministic priority: a cell that is both hull and sandbar reports `.hull`.
    /// The union of the three sets is exactly `HJBoardState.solidCells(excluding:)`.
    private static func blockReason(_ inside: [HJCell], hulls: Set<HJCell>,
                                    ferry: Set<HJCell>, sand: Set<HJCell>) -> HJBlockReason? {
        if inside.contains(where: { hulls.contains($0) }) { return .hull }
        if inside.contains(where: { ferry.contains($0) }) { return .ferry }
        if inside.contains(where: { sand.contains($0) }) { return .sandbar }
        return nil
    }

    // MARK: - Tap — a thin commit wrapper around march

    /// Resolve tapping a boat. Mutates `state` in place. Fully deterministic.
    /// Every outcome except `.invalid` ticks the world: probing is no longer free, and a
    /// board whose remaining boats are all blocked can no longer freeze.
    static func tap(boatID: Int, state: inout HJBoardState) -> HJTapOutcome {
        guard let boat = state.boat(withID: boatID) else { return .invalid }
        if state.isAnchored(boat) {
            tickWorld(&state)
            return .anchored
        }
        let detail = marchDetail(boat: boat, state: state)
        if detail.preview.exits {
            state.boats.removeAll { $0.id == boatID }
            state.exitedIDs.append(boatID)
            tickWorld(&state)
            return .exited(boatID: boatID)
        }
        if detail.preview.distance == 0 {
            tickWorld(&state)
            // marchDetail always names a reason when it advances zero cells.
            return .blocked(reason: detail.preview.stopReason ?? .hull)
        }
        if let landed = detail.landed,
           let idx = state.boats.firstIndex(where: { $0.id == boatID }) {
            state.boats[idx] = landed
        }
        tickWorld(&state)
        return .moved(boatID: boatID, distance: detail.preview.distance)
    }

    // MARK: - World tick

    /// One world beat: tap counter, tide toggle, ferry, currents — in that order.
    /// The order is load-bearing. `taps` is incremented first, so the tide and the lane
    /// flips read the same post-tap phase the baked witness was searched against.
    ///
    /// A boat may now be caught on a sandbar when the tide drops (sandbars sit inside exit
    /// corridors). It is stranded until the tide rises three taps later; the toggle is
    /// unconditional, so this can never deadlock a board.
    static func tickWorld(_ state: inout HJBoardState) {
        state.taps += 1
        if state.tideEnabled && state.taps % 3 == 0 {
            state.tideHigh.toggle()
        }
        advanceFerry(&state)
        applyCurrents(&state)
    }

    private static func advanceFerry(_ state: inout HJBoardState) {
        guard var f = state.ferry else { return }
        let occ = state.occupied()
        let sand = state.sandbarCells()
        var advanced = 0
        var x = f.x
        while advanced < f.stride {
            let nx = (x + 1) % state.gridW
            var free = true
            for i in 0..<f.length {
                let cell = HJCell(x: (nx + i) % state.gridW, y: f.row)
                if occ.contains(cell) || sand.contains(cell) { free = false; break }
            }
            if !free { break }   // ferry waits, deterministic
            x = nx
            advanced += 1
        }
        f.x = x
        state.ferry = f
    }

    /// Drift every lane resident, once per tick.
    ///
    /// Lanes are visited in array order and a boat drifts in the first lane it belongs to,
    /// which is the rule the single-boat version used. Inside a lane the residents move
    /// far-side-first — the boat nearest the wall the current pushes toward goes first — so a
    /// queue of boats resolves without any of them colliding with the boat ahead. Ties break
    /// on `id` because `Array.sort` is not stable and the baked corpus needs one exact order.
    ///
    /// Barges are exempt: they are the drift anchors the player positions.
    static func applyCurrents(_ state: inout HJBoardState) {
        guard !state.currents.isEmpty else { return }
        var handled = Set<Int>()
        for lane in state.currents {
            let push = lane.effectivePush(atTick: state.taps)
            var residents = state.boats.filter { b in
                !b.isBarge && !handled.contains(b.id) &&
                b.cells.contains { lane.isRow ? $0.y == lane.index : $0.x == lane.index }
            }
            residents.sort { a, b in
                let ka = driftKey(a, push: push), kb = driftKey(b, push: push)
                return ka == kb ? a.id < b.id : ka > kb
            }
            for r in residents {
                handled.insert(r.id)
                guard let idx = state.boats.firstIndex(where: { $0.id == r.id }) else { continue }
                var moved = state.boats[idx]
                moved.x += push.dx
                moved.y += push.dy
                let solids = state.solidCells(excluding: moved.id)
                guard moved.cells.allSatisfy({ state.inBounds($0) && !solids.contains($0) })
                else { continue }
                state.boats[idx] = moved
            }
        }
    }

    /// Higher = further along the push direction.
    private static func driftKey(_ boat: HJBoat, push: HJDirection) -> Int {
        switch push {
        case .east: return boat.x
        case .west: return -boat.x
        case .south: return boat.y
        case .north: return -boat.y
        }
    }
}
```

- [ ] **Step 3: Give the generator's board construction the new field.** `Harbor Jam/HJGenerator.swift:167` is the only `HJBoardState(...)` call in the app. Edit that one line — the anchor below is the line as it reads after the tug deletion, which only touched `:169`:

Find:

```swift
                                 sandbars: sandbars, currents: currents, ferry: ferry,
```

Replace with:

```swift
                                 sandbars: sandbars, basins: [], currents: currents, ferry: ferry,
```

Empty is correct for now: the generator that actually places basins is a later task. This edit only keeps the build green in between.

- [ ] **Step 4: Sweep the harness for other board constructions.** Any `HJBoardState(...)` written by the earlier harness task needs the same new label or it stops compiling:

```bash
cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam"
grep -rn "HJBoardState(" tools/
```

For every hit, insert `basins: []` immediately after the `sandbars:` argument. If the command prints nothing, there is nothing to do — move on.

- [ ] **Step 5: Clip the boat layer.** A boat can now come to rest with part of its footprint past the bow-side edge (a 3-cell hull with throttle 1 sheds one cell per tap), and `boatLayer` positions hulls by cell centre with no clipping — an un-clipped hull draws outside the board frame and over the HUD. Check D6 in Step 9 asserts that this state is reachable. In `Harbor Jam/HJBoardView.swift`, find this block (unique — it is the one `.frame(width: boardSize.width, ...)` followed by `cellCenter`):

```swift
        .frame(width: boardSize.width, height: boardSize.height)
    }

    private func cellCenter(x: Int, y: Int) -> CGPoint {
```

Replace with:

```swift
        .frame(width: boardSize.width, height: boardSize.height)
        // A hull may now rest partly past the bow-side edge; without this it draws over the HUD.
        .clipped()
    }

    private func cellCenter(x: Int, y: Int) -> CGPoint {
```

`.clipped()` clips rendering only — the visible half of a departing hull is still tappable.

- [ ] **Step 6: Compile the app.** `HJGameViewModel.swift:80` reads `case .blocked, .anchored:`; a case pattern with no sub-pattern matches any payload, so the new associated value needs no view-model edit in this task.

```bash
cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam"
xcodebuild -project "Harbor Jam.xcodeproj" -scheme "Harbor Jam" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -configuration Debug build 2>&1 | grep -E "error:|warning:|BUILD" | sort -u
```

Assertion: the output is exactly `** BUILD SUCCEEDED **` — no `error:` and no `warning:` lines. Anything else, fix it before continuing.

- [ ] **Step 7: Write the harness support file.** Create `tools/HarborForge/EngineChecks/Support.swift` (its own directory and its own `main.swift`, so it links as a separate binary and cannot collide with the existing forge tool's top-level code):

```bash
mkdir -p "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam/tools/HarborForge/EngineChecks"
```

```swift
import Foundation

// MARK: - Tally

final class HJTally {
    var run = 0
    var failed = 0
}
let tally = HJTally()

func check(_ name: String, _ passed: Bool, _ detail: @autoclosure () -> String = "") {
    tally.run += 1
    if passed {
        print("PASS  \(name)")
    } else {
        tally.failed += 1
        let d = detail()
        print("FAIL  \(name)" + (d.isEmpty ? "" : "  — " + d))
    }
}

// MARK: - Deterministic RNG (SplitMix64, same shape as HJRandom)

struct HJCheckRandom {
    private var s: UInt64
    init(seed: UInt64) { s = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        s = s &+ 0x9E3779B97F4A7C15
        var z = s
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func int(_ upper: Int) -> Int { upper <= 0 ? 0 : Int(next() % UInt64(upper)) }
    mutating func bool() -> Bool { next() % 2 == 0 }
}

// MARK: - Random boards

/// A deliberately hostile board: boats may sit on sandbars and basins, the ferry may overlap
/// hulls, the tide may be out. Every one of these is a legal input to `march`.
func randomBoard(_ rng: inout HJCheckRandom) -> HJBoardState {
    let w = 5 + rng.int(4)          // 5…8
    let h = 5 + rng.int(4)
    let want = 2 + rng.int(4)       // 2…5
    var boats: [HJBoat] = []
    var used = Set<HJCell>()
    var attempts = 0
    while boats.count < want && attempts < 200 {
        attempts += 1
        let isBarge = rng.int(5) == 0
        let length = isBarge ? 2 : (2 + rng.int(2))
        let bow = HJDirection(rawValue: rng.int(4)) ?? .north
        var b = HJBoat(id: boats.count, x: 0, y: 0, length: length, isBarge: isBarge,
                       bow: bow, hullIndex: rng.int(8), anchoredBy: nil,
                       throttle: 1 + rng.int(3))
        guard w - b.width >= 0, h - b.height >= 0 else { continue }
        b.x = rng.int(w - b.width + 1)
        b.y = rng.int(h - b.height + 1)
        let footprint = Set(b.cells)
        guard footprint.isDisjoint(with: used) else { continue }
        used.formUnion(footprint)
        boats.append(b)
    }

    var sandbars: [HJCell] = []
    for _ in 0..<rng.int(4) { sandbars.append(HJCell(x: rng.int(w), y: rng.int(h))) }
    var basins: [HJCell] = []
    for _ in 0..<(1 + rng.int(3)) { basins.append(HJCell(x: rng.int(w), y: rng.int(h))) }

    var currents: [HJCurrentLane] = []
    if rng.bool() {
        let isRow = rng.bool()
        currents.append(HJCurrentLane(isRow: isRow,
                                      index: isRow ? rng.int(h) : rng.int(w),
                                      push: isRow ? (rng.bool() ? .north : .south)
                                                  : (rng.bool() ? .east : .west),
                                      period: 2 + rng.int(3)))
    }
    var ferry: HJFerry? = nil
    if rng.bool() {
        ferry = HJFerry(row: rng.int(h), x: rng.int(w), length: 2, stride: 1 + rng.int(2))
    }

    return HJBoardState(gridW: w, gridH: h, boats: boats, exitedIDs: [],
                        sandbars: sandbars, basins: basins, currents: currents, ferry: ferry,
                        tideEnabled: rng.bool(), tideHigh: rng.bool(),
                        taps: rng.int(6), night: false)
}
```

- [ ] **Step 8: Write the checks.** Create `tools/HarborForge/EngineChecks/main.swift`:

```swift
import Foundation

print("HarborForge — engine checks (Task 4)")
print("")

// MARK: - A. One lane, two boats: a single tap drifts BOTH, far-side-first.

do {
    // Tapper sits in column 0 rows 0-1 and never enters the lane.
    let tapper = HJBoat(id: 0, x: 0, y: 0, length: 2, isBarge: false, bow: .south,
                        hullIndex: 0, anchoredBy: nil, throttle: 1)
    // Two horizontal hulls queued along the push direction inside row 3.
    let near = HJBoat(id: 1, x: 0, y: 3, length: 2, isBarge: false, bow: .east,
                      hullIndex: 1, anchoredBy: nil, throttle: 1)
    let far = HJBoat(id: 2, x: 2, y: 3, length: 2, isBarge: false, bow: .east,
                     hullIndex: 2, anchoredBy: nil, throttle: 1)
    var s = HJBoardState(gridW: 6, gridH: 6, boats: [tapper, near, far], exitedIDs: [],
                         sandbars: [], basins: [],
                         currents: [HJCurrentLane(isRow: true, index: 3, push: .east, period: 4)],
                         ferry: nil, tideEnabled: false, tideHigh: true, taps: 0, night: false)

    let outcome = HJEngine.tap(boatID: 0, state: &s)
    check("A1 tap resolves", outcome == .moved(boatID: 0, distance: 1), "\(outcome)")
    check("A2 the world ticked", s.taps == 1, "taps=\(s.taps)")
    check("A3 tapper is not a lane resident", s.boat(withID: 0)?.y == 1,
          "y=\(String(describing: s.boat(withID: 0)?.y))")
    check("A4 far boat drifted", s.boat(withID: 2)?.x == 3,
          "x=\(String(describing: s.boat(withID: 2)?.x))")
    check("A5 near boat drifted too (queue resolved far-side-first)", s.boat(withID: 1)?.x == 1,
          "x=\(String(describing: s.boat(withID: 1)?.x)) — near-first ordering leaves it at 0")
}

// MARK: - B. A basin reverses the bow and preserves the footprint.

do {
    let b = HJBoat(id: 0, x: 0, y: 0, length: 2, isBarge: false, bow: .east,
                   hullIndex: 0, anchoredBy: nil, throttle: 3)
    var s = HJBoardState(gridW: 6, gridH: 6, boats: [b], exitedIDs: [], sandbars: [],
                         basins: [HJCell(x: 3, y: 0)], currents: [], ferry: nil,
                         tideEnabled: false, tideHigh: true, taps: 0, night: false)
    let p = HJEngine.preview(boatID: 0, state: s)
    let outcome = HJEngine.tap(boatID: 0, state: &s)
    let after = s.boat(withID: 0)

    check("B1 stopped in the basin, short of full throttle",
          outcome == .moved(boatID: 0, distance: 2), "\(outcome)")
    check("B2 bow reversed 180°", after?.bow == .west, "\(String(describing: after?.bow))")
    check("B3 footprint preserved", after?.width == b.width && after?.height == b.height,
          "\(String(describing: after?.width))x\(String(describing: after?.height))")
    check("B4 rests on the basin cell",
          Set(after?.cells ?? []) == Set([HJCell(x: 2, y: 0), HJCell(x: 3, y: 0)]),
          "\(String(describing: after?.cells))")
    check("B5 preview named the same landing",
          Set(p.landing) == Set(after?.cells ?? []) && p.distance == 2 && p.stopReason == nil,
          "\(p)")
}

// MARK: - C. An anchored tap still ticks the world (no more frozen boards).

do {
    let key = HJBoat(id: 0, x: 0, y: 0, length: 2, isBarge: false, bow: .north,
                     hullIndex: 0, anchoredBy: nil, throttle: 2)
    let locked = HJBoat(id: 1, x: 3, y: 3, length: 2, isBarge: false, bow: .east,
                        hullIndex: 1, anchoredBy: 0, throttle: 2)
    var s = HJBoardState(gridW: 6, gridH: 6, boats: [key, locked], exitedIDs: [], sandbars: [],
                         basins: [], currents: [],
                         ferry: HJFerry(row: 5, x: 0, length: 2, stride: 1),
                         tideEnabled: false, tideHigh: true, taps: 0, night: false)
    let outcome = HJEngine.tap(boatID: 1, state: &s)
    check("C1 anchored boat reports .anchored", outcome == .anchored, "\(outcome)")
    check("C2 anchored tap still ticks the world", s.taps == 1, "taps=\(s.taps)")
    check("C3 the ferry moved on that tick", s.ferry?.x == 1, "\(String(describing: s.ferry?.x))")
}

// MARK: - D. preview and tap agree on 10 000 random (board, boat) pairs.

do {
    var rng = HJCheckRandom(seed: 0x484A_C0DE_0004)
    var pairs = 0
    var mismatches = 0
    var exits = 0, moves = 0, blocks = 0, flips = 0, partials = 0
    var firstFailure = ""

    while pairs < 10_000 {
        let board = randomBoard(&rng)
        if board.boats.isEmpty { continue }
        let boat = board.boats[rng.int(board.boats.count)]
        pairs += 1

        // march never reads the currents, so the drift tickWorld applies after the commit
        // cannot be what makes preview and tap agree. Prove that, then compare landings on a
        // drift-free copy where the boat's post-tap cells ARE the landing cells.
        var still = board
        still.currents = []
        let pFull = HJEngine.preview(boatID: boat.id, state: board)
        let pStill = HJEngine.preview(boatID: boat.id, state: still)

        var ok = (pFull == pStill)
        if !ok && firstFailure.isEmpty {
            firstFailure = "currents changed the march: \(pFull) vs \(pStill)"
        }

        var s = still
        let outcome = HJEngine.tap(boatID: boat.id, state: &s)
        if pStill.exits {
            exits += 1
            ok = ok && outcome == .exited(boatID: boat.id)
            ok = ok && s.boat(withID: boat.id) == nil && s.exitedIDs.contains(boat.id)
            ok = ok && pStill.landing.isEmpty
        } else if pStill.distance == 0 {
            blocks += 1
            if case .blocked(let reason) = outcome {
                ok = ok && reason == pStill.stopReason
            } else {
                ok = false
            }
            ok = ok && (s.boat(withID: boat.id).map { Set($0.cells) == Set(boat.cells) } ?? false)
        } else {
            moves += 1
            ok = ok && outcome == .moved(boatID: boat.id, distance: pStill.distance)
            ok = ok && (s.boat(withID: boat.id).map { Set($0.cells) == Set(pStill.landing) } ?? false)
            if s.boat(withID: boat.id)?.bow != boat.bow { flips += 1 }
            if pStill.landing.contains(where: { !still.inBounds($0) }) { partials += 1 }
        }

        // The full board — currents and all — must report the identical outcome.
        var sFull = board
        let outcomeFull = HJEngine.tap(boatID: boat.id, state: &sFull)
        ok = ok && (outcome == outcomeFull)

        if !ok {
            mismatches += 1
            if firstFailure.isEmpty {
                firstFailure = "boat \(boat) preview \(pStill) outcome \(outcome)"
            }
        }
    }

    print("      pairs=\(pairs) exits=\(exits) moves=\(moves) blocked=\(blocks) basinFlips=\(flips) partialRests=\(partials)")
    check("D1 preview and tap agree on 10 000 pairs", mismatches == 0,
          "\(mismatches) mismatches; first: \(firstFailure)")
    check("D2 sample covers exits", exits >= 100, "only \(exits) — widen randomBoard")
    check("D3 sample covers moves", moves >= 100, "only \(moves) — widen randomBoard")
    check("D4 sample covers blocks", blocks >= 100, "only \(blocks) — widen randomBoard")
    check("D5 sample exercises the basin flip", flips > 0, "no basin stop was sampled")
    check("D6 a boat can rest partly past the bow-side edge (boatLayer must clip)",
          partials > 0, "no partial rest was sampled")
}

print("")
print("\(tally.run - tally.failed)/\(tally.run) checks passed")
if tally.failed > 0 {
    print("ENGINE CHECKS FAILED")
    exit(1)
}
print("ENGINE CHECKS OK")
exit(0)
```

- [ ] **Step 9: Build and run the checks.** `build/` is already gitignored, so the binary stays out of the tree:

```bash
cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam"
mkdir -p build
swiftc -O "Harbor Jam/HJModels.swift" "Harbor Jam/HJEngine.swift" \
  tools/HarborForge/EngineChecks/Support.swift \
  tools/HarborForge/EngineChecks/main.swift \
  -o build/enginechecks
./build/enginechecks; echo "exit=$?"
```

Assertions: `swiftc` emits nothing at all (no warnings), every printed line starts with `PASS`, the last three lines are the count line `19/19 checks passed`, `ENGINE CHECKS OK`, and `exit=0`. The `pairs=… exits=… moves=… blocked=… basinFlips=… partialRests=…` line is informational — the floors in D2–D6 are what is being asserted. If any check prints `FAIL` the engine is wrong, not the check; fix `HJEngine.swift` and re-run.

- [ ] **Step 10: Prove A5 is not vacuous.** The far-side-first ordering is the whole reason a lane queue resolves, so confirm the check actually detects the wrong order. In `Harbor Jam/HJEngine.swift`, temporarily change the comparator inside `applyCurrents`:

```swift
                return ka == kb ? a.id < b.id : ka > kb
```

to

```swift
                return ka == kb ? a.id < b.id : ka < kb
```

then re-run Step 9's two commands. Assertion: `A5` prints `FAIL … x=Optional(0) — near-first ordering leaves it at 0` and the binary exits non-zero. Now restore the line to `ka > kb`, re-run Step 9, and confirm `19/19 checks passed` / `exit=0` again before committing.

- [ ] **Step 11: Commit.**

```bash
cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam"
git add "Harbor Jam/HJEngine.swift" "Harbor Jam/HJGenerator.swift" "Harbor Jam/HJBoardView.swift" \
        tools/HarborForge/EngineChecks/Support.swift tools/HarborForge/EngineChecks/main.swift
git commit -m "Engine, final: march/throttle/basins/live currents/preview

march(boat:state:) is the single walker: it advances at most boat.throttle cells,
names why it stopped (hull/sandbar/ferry/edge), and applies the turning-basin rule
(bow cell enters a basin -> stop there, bow flips 180 deg, footprint preserved
because width/height derive only from bow.isHorizontal). tap commits what march
returns and preview shows it, so the ghost and the move cannot disagree.

Every outcome except .invalid now ticks the world: taps, tide, ferry, currents.
applyCurrents replaces applyCurrent(_:boatID:) and drifts every lane resident
far-side-first with an id tiebreak, keeping the barge exemption and the legality
guard. HJBoardState gains basins; boatLayer clips, because a hull can now rest
partly past the bow-side edge.

Frozen as of this commit: the baked corpus is searched against these rules.
Harness: tools/HarborForge/EngineChecks, 19/19 checks, including preview/tap
agreement over 10 000 random (board, boat) pairs.

Co-Authored-By: Claude <noreply@anthropic.com>"
```


---

### Task 5: Forward board generator (HJForge)

**Files:**
- `tools/HarborForge/Forge.swift` — new, the forward generator (replaces reverse construction)
- `tools/HarborForge/ForgeCheck.swift` — new, the structural harness check
- `tools/HarborForge/CheckForge/main.swift` — new, entry point for the check binary
- `.gitignore` — one appended line for the build output directory
- Read-only inputs (this task modifies **no** file under `Harbor Jam/`): `Harbor Jam/HJModels.swift`, `Harbor Jam/HJEngine.swift`

**Interfaces:**

*Consumes* (all defined in Tasks 1–4, nothing later):
```
HJDirection (.allCases, .dx, .dy, .isHorizontal)                 // Harbor Jam/HJModels.swift:4
HJCell(x:y:)                                                     // Harbor Jam/HJModels.swift:27
HJBoat(id:x:y:length:isBarge:bow:hullIndex:anchoredBy:throttle:) // throttle appended in Task 1
HJBoat.cells, .width, .height
HJCurrentLane(isRow:index:push:period:)                          // period added in Task 1
HJFerry(row:x:length:stride:)                                    // Harbor Jam/HJModels.swift:62
HJLevelConfig  .gridW .gridH .boatCount .bargeCount .useCurrents .useTide
               .useFerry .chainCount .basinCount .night          // tugTokens deleted in Task 1
HJCatalog.chapters, .levelsPerChapter, .config(chapter:level:), .seed(chapter:level:)
HJBoardState(gridW:gridH:boats:exitedIDs:sandbars:currents:ferry:
             tideEnabled:tideHigh:taps:night:basins:)            // tugTokens out, basins in
HJBoardState.inBounds(_:)                                        // Harbor Jam/HJEngine.swift:49
```
This task calls **no** engine function. `march`, `preview`, `tap`, `tickWorld`, `applyCurrents`, `bowCells` and the basin rule are frozen at Task 4 and are neither used nor touched here — the forge only emits a start position, so nothing in this task can invalidate a witness baked later.

*Produces:*
```
struct HJForgeRandom {                                    // tools/HarborForge/Forge.swift
    init(seed: UInt64)
    mutating func next() -> UInt64
    mutating func int(_ upper: Int) -> Int
    mutating func bool() -> Bool
    mutating func pick<T>(_ array: [T]) -> T?
}
enum HJForge {
    static func board(seed: UInt64, config: HJLevelConfig) -> HJBoardState?
    static func exitCorridor(for boat: HJBoat, gridW: Int, gridH: Int) -> Set<HJCell>
}
enum HJForgeCheck { static func run() -> Int32 }           // tools/HarborForge/ForgeCheck.swift
tools/HarborForge/bin/forgecheck                           // build artifact, gitignored
```
Not produced here and not to be invented here: any solvability search, any witness, any `par`, any difficulty metric. Task 6 owns solvability, Task 7 owns difficulty.

---

- [ ] **Step 1: Confirm Tasks 1–4 landed the fields this generator writes, and create the directories.**

  Run from the repo root `/Users/vik/Documents/development/for_human_review_apps/Harbor Jam`:

  ```sh
  mkdir -p tools/HarborForge/CheckForge tools/HarborForge/bin
  grep -n "var throttle: Int"   "Harbor Jam/HJModels.swift"
  grep -n "var period: Int"     "Harbor Jam/HJModels.swift"
  grep -n "var basinCount: Int" "Harbor Jam/HJModels.swift"
  grep -n "var basins: \[HJCell\]" "Harbor Jam/HJEngine.swift"
  grep -rn "tugTokens" "Harbor Jam/HJModels.swift" "Harbor Jam/HJEngine.swift" | wc -l
  ```

  Assertion: the first four greps each print exactly one line, and the last command prints `0`. Anything else means an earlier task is incomplete — stop and finish it before writing this one; the code below will not compile against the old field set.

- [ ] **Step 2: Create `tools/HarborForge/Forge.swift` with the RNG.**

  The name `HJForgeRandom` exists so this file can be compiled into the same binary as the app's `HJRandom` (`Harbor Jam/HJGenerator.swift:4`) without a redeclaration error.

  ```sh
  cat > tools/HarborForge/Forge.swift <<'SWIFT'
  import Foundation

  // Offline forward board generator for Harbor Jam. Compiled only into the tools/HarborForge
  // harness, never into the app target. It emits START POSITIONS ONLY: no canonical solution,
  // no par, no solvability claim. Solvability is the solver's job, difficulty is the gate's.
  //
  // This deliberately does not reuse HJGenerator.construct. Reverse construction placed boat i
  // only after every boat with id > i and required i's exit corridor to be clear of them
  // ("Harbor Jam/HJGenerator.swift:97"), which made the ascending exit order a complete solver
  // with zero lookahead. Here boats are packed forward at random legal positions and no exit
  // order is guaranteed to exist at all.

  /// Deterministic SplitMix64 — same shape as the app's HJRandom, separate name so both can be
  /// linked into one harness binary.
  struct HJForgeRandom {
      private var state: UInt64
      init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }

      mutating func next() -> UInt64 {
          state = state &+ 0x9E3779B97F4A7C15
          var z = state
          z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
          z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
          return z ^ (z >> 31)
      }

      mutating func int(_ upper: Int) -> Int {
          guard upper > 0 else { return 0 }
          return Int(next() % UInt64(upper))
      }

      mutating func bool() -> Bool { next() % 2 == 0 }

      mutating func pick<T>(_ array: [T]) -> T? {
          guard !array.isEmpty else { return nil }
          return array[int(array.count)]
      }
  }
  SWIFT
  ```

- [ ] **Step 3: Append the entry point and the assembly order.**

  This opens `enum HJForge {`; the brace is closed in Step 7. Every collection this file derives from a `Set` or `Dictionary` is sorted before an RNG draw touches it — Swift hashing is seeded per process, so an unsorted draw would make the same seed produce different boards on different runs and silently invalidate every baked witness.

  ```sh
  cat >> tools/HarborForge/Forge.swift <<'SWIFT'

  enum HJForge {

      private static let maxSalts = 40
      private static let placeAttempts = 200

      /// A start position for `seed` under `config`, or nil if this seed cannot be packed.
      /// Retries internally on successive salts exactly like the surviving loop at
      /// "Harbor Jam/HJGenerator.swift:36-42"; a nil here means "try another seed".
      static func board(seed: UInt64, config: HJLevelConfig) -> HJBoardState? {
          for salt in 0..<maxSalts {
              var rng = HJForgeRandom(seed: seed &+ UInt64(salt) &* 0x2545F4914F6CDD1D)
              if let state = attempt(rng: &rng, config: config) { return state }
          }
          return nil
      }

      private static func attempt(rng: inout HJForgeRandom, config: HJLevelConfig) -> HJBoardState? {
          let w = config.gridW, h = config.gridH
          guard var boats = packBoats(rng: &rng, config: config) else { return nil }

          let footprints = Set(boats.flatMap { $0.cells })

          // Cell -> ids of the boats whose straight exit corridor covers it. Boat footprints are
          // excluded so nothing below can ever be placed under a hull.
          var corridorOwners: [HJCell: Set<Int>] = [:]
          for boat in boats {
              for cell in exitCorridor(for: boat, gridW: w, gridH: h) where !footprints.contains(cell) {
                  corridorOwners[cell, default: []].insert(boat.id)
              }
          }

          // Inverted polarity: sandbars are drawn FROM the corridors, not from their complement
          // ("Harbor Jam/HJGenerator.swift:122-135" drew from the complement, which is why the
          // tide could never block anything).
          var sandbars: [HJCell] = []
          if config.useTide {
              guard let picked = pickSandbars(rng: &rng, corridorOwners: corridorOwners) else { return nil }
              sandbars = picked
          }

          var blocked = footprints
          blocked.formUnion(sandbars)

          guard let basins = pickBasins(rng: &rng, gridW: w, gridH: h,
                                        count: config.basinCount, blocked: blocked) else { return nil }

          var currents: [HJCurrentLane] = []
          if config.useCurrents { currents = makeCurrents(rng: &rng, gridW: w, gridH: h) }

          var ferry: HJFerry? = nil
          if config.useFerry {
              guard let f = placeFerry(rng: &rng, gridW: w, gridH: h, blocked: blocked) else { return nil }
              ferry = f
          }

          guard applyChains(rng: &rng, boats: &boats, count: config.chainCount) else { return nil }

          return HJBoardState(gridW: w, gridH: h, boats: boats, exitedIDs: [],
                              sandbars: sandbars, currents: currents, ferry: ferry,
                              tideEnabled: config.useTide, tideHigh: true,
                              taps: 0, night: config.night, basins: basins)
      }
  SWIFT
  ```

- [ ] **Step 4: Append forward packing and the corridor ray.**

  ```sh
  cat >> tools/HarborForge/Forge.swift <<'SWIFT'

      /// Pack the grid forward: each boat lands at a random legal footprint with a random bow and
      /// a throttle drawn from {1,2,3}. No corridor is reserved for anybody, so no exit order is
      /// guaranteed — that is the whole point of this file.
      private static func packBoats(rng: inout HJForgeRandom, config: HJLevelConfig) -> [HJBoat]? {
          let w = config.gridW, h = config.gridH
          var boats: [HJBoat] = []
          var occupied = Set<HJCell>()

          for id in 0..<config.boatCount {
              let isBarge = id < config.bargeCount
              var placed = false
              for _ in 0..<placeAttempts {
                  let length = isBarge ? 2 : (rng.int(3) == 0 ? 3 : 2)
                  guard let bow = rng.pick(HJDirection.allCases) else { return nil }
                  var boat = HJBoat(id: id, x: 0, y: 0, length: length, isBarge: isBarge,
                                    bow: bow, hullIndex: rng.int(8), anchoredBy: nil,
                                    throttle: 1 + rng.int(3))
                  let maxX = w - boat.width, maxY = h - boat.height
                  guard maxX >= 0, maxY >= 0 else { continue }
                  boat.x = rng.int(maxX + 1)
                  boat.y = rng.int(maxY + 1)
                  let cells = Set(boat.cells)
                  guard cells.isDisjoint(with: occupied) else { continue }
                  occupied.formUnion(cells)
                  boats.append(boat)
                  placed = true
                  break
              }
              if !placed { return nil }
          }
          return boats
      }

      /// Every in-bounds cell the boat would sweep marching along its bow to the edge, excluding
      /// its own current footprint. Same ray as "Harbor Jam/HJGenerator.swift:173-185"; internal
      /// rather than private so the harness can assert the sandbar polarity independently.
      static func exitCorridor(for boat: HJBoat, gridW: Int, gridH: Int) -> Set<HJCell> {
          var out = Set<HJCell>()
          var probe = boat
          while true {
              probe.x += boat.bow.dx
              probe.y += boat.bow.dy
              let inside = probe.cells.filter { $0.x >= 0 && $0.x < gridW && $0.y >= 0 && $0.y < gridH }
              if inside.isEmpty { break }
              out.formUnion(inside)
              if out.count > gridW * gridH { break }
          }
          return out
      }
  SWIFT
  ```

- [ ] **Step 5: Append sandbar and basin placement.**

  ```sh
  cat >> tools/HarborForge/Forge.swift <<'SWIFT'

      /// Sandbars, drawn from the union of the exit corridors. Requires the chosen cells to sit in
      /// at least two DISTINCT boats' corridors, so a tide drop always threatens more than one
      /// boat's line. Returns nil when that is impossible on this board.
      private static func pickSandbars(rng: inout HJForgeRandom,
                                       corridorOwners: [HJCell: Set<Int>]) -> [HJCell]? {
          // Sorted: dictionary key order is not stable across processes.
          var remaining = corridorOwners.keys.sorted { $0.y == $1.y ? $0.x < $1.x : $0.y < $1.y }
          let want = min(2 + rng.int(3), remaining.count)
          guard want >= 2 else { return nil }

          var chosen: [HJCell] = []
          var covered = Set<Int>()
          while chosen.count < want && !remaining.isEmpty {
              var candidates = remaining
              if covered.count == 1 {
                  // Steer the next pick toward a second boat's corridor.
                  let widening = remaining.filter { !(corridorOwners[$0] ?? []).isSubset(of: covered) }
                  if !widening.isEmpty { candidates = widening }
              }
              guard let cell = rng.pick(candidates),
                    let idx = remaining.firstIndex(of: cell) else { break }
              remaining.remove(at: idx)
              chosen.append(cell)
              covered.formUnion(corridorOwners[cell] ?? [])
          }
          guard chosen.count == want, covered.count >= 2 else { return nil }
          return chosen
      }

      /// Turning basins: exactly `count` distinct cells, never under a starting hull and never on a
      /// sandbar (a cell cannot be both a flip pad and a tide obstruction). A basin inside a
      /// corridor is desirable and is not excluded.
      private static func pickBasins(rng: inout HJForgeRandom, gridW: Int, gridH: Int,
                                     count: Int, blocked: Set<HJCell>) -> [HJCell]? {
          guard count > 0 else { return [] }
          var pool: [HJCell] = []
          for y in 0..<gridH {
              for x in 0..<gridW {
                  let c = HJCell(x: x, y: y)
                  if !blocked.contains(c) { pool.append(c) }
              }
          }
          guard pool.count >= count else { return nil }
          var chosen: [HJCell] = []
          for _ in 0..<count { chosen.append(pool.remove(at: rng.int(pool.count))) }
          return chosen
      }
  SWIFT
  ```

- [ ] **Step 6: Append current lanes, the ferry and the buoy chains.**

  ```sh
  cat >> tools/HarborForge/Forge.swift <<'SWIFT'

      /// One or two lanes, each with a flip period drawn from {2,3,4} so a lane cannot saturate a
      /// boat against the far wall and go inert.
      private static func makeCurrents(rng: inout HJForgeRandom, gridW: Int, gridH: Int) -> [HJCurrentLane] {
          let laneCount = 1 + rng.int(2)
          var lanes: [HJCurrentLane] = []
          var attempts = 0
          while lanes.count < laneCount && attempts < 30 {
              attempts += 1
              let isRow = rng.bool()
              let index = isRow ? rng.int(gridH) : rng.int(gridW)
              if lanes.contains(where: { $0.isRow == isRow && $0.index == index }) { continue }
              let push: HJDirection = isRow ? (rng.bool() ? .north : .south)
                                            : (rng.bool() ? .east : .west)
              lanes.append(HJCurrentLane(isRow: isRow, index: index, push: push, period: 2 + rng.int(3)))
          }
          return lanes
      }

      /// The ferry starts clear of every hull and sandbar; it may share a row with anything else.
      private static func placeFerry(rng: inout HJForgeRandom, gridW: Int, gridH: Int,
                                     blocked: Set<HJCell>) -> HJFerry? {
          for _ in 0..<40 {
              let row = rng.int(gridH)
              let x = rng.int(gridW)
              let stride = 1 + rng.int(2)
              let cells = (0..<2).map { HJCell(x: (x + $0) % gridW, y: row) }
              if cells.contains(where: { blocked.contains($0) }) { continue }
              return HJFerry(row: row, x: x, length: 2, stride: stride)
          }
          return nil
      }

      /// Buoy chains with NO ordering constraint between key and lock. The old rule at
      /// "Harbor Jam/HJGenerator.swift:113-117" forced keyIdx < lockIdx, so ascending exit order
      /// pre-satisfied every chain and all of them were free. Here the key may exit after the lock
      /// would like to, which is exactly the constraint that has to be planned around.
      /// The only rejection is a cycle in the anchor graph, which is not an ordering rule: a cycle
      /// is unsolvable by construction and would only waste the solver's node budget in Task 6.
      private static func applyChains(rng: inout HJForgeRandom, boats: inout [HJBoat], count: Int) -> Bool {
          guard count > 0 else { return true }
          guard boats.count >= 2 else { return false }
          var placed = 0
          var attempts = 0
          while placed < count && attempts < 200 {
              attempts += 1
              let lockIdx = rng.int(boats.count)
              let keyIdx = rng.int(boats.count)
              if lockIdx == keyIdx { continue }
              if boats[lockIdx].isBarge { continue }
              if boats[lockIdx].anchoredBy != nil { continue }
              var trial = boats
              trial[lockIdx].anchoredBy = boats[keyIdx].id
              if hasAnchorCycle(trial) { continue }
              boats = trial
              placed += 1
          }
          return placed == count
      }

      private static func hasAnchorCycle(_ boats: [HJBoat]) -> Bool {
          var anchor: [Int: Int] = [:]
          for b in boats { if let key = b.anchoredBy { anchor[b.id] = key } }
          for b in boats {
              var seen: Set<Int> = [b.id]
              var cur = b.id
              while let next = anchor[cur] {
                  if seen.contains(next) { return true }
                  seen.insert(next)
                  cur = next
              }
          }
          return false
      }
  }
  SWIFT
  ```

- [ ] **Step 7: Verify the file is brace-balanced and syntactically whole before writing the check.**

  ```sh
  xcrun -sdk macosx swiftc -swift-version 5 -parse \
    "Harbor Jam/HJModels.swift" "Harbor Jam/HJEngine.swift" tools/HarborForge/Forge.swift \
    && echo "PARSE OK"
  ```

  Assertion: the command exits 0 and prints `PARSE OK`. A brace error here means one of the four `cat >>` appends in Steps 3–6 was pasted out of order.

- [ ] **Step 8: Create `tools/HarborForge/ForgeCheck.swift` — the per-board structural validator.**

  ```sh
  cat > tools/HarborForge/ForgeCheck.swift <<'SWIFT'
  import Foundation

  /// Structural harness check for HJForge. Asserts PROPERTIES of generated boards only — it makes
  /// no claim about solvability or difficulty and calls no engine function.
  enum HJForgeCheck {

      struct Failure { var label: String; var reason: String }

      /// Every structural invariant a start position must satisfy.
      static func validate(_ s: HJBoardState, config: HJLevelConfig, label: String) -> [Failure] {
          var out: [Failure] = []
          func fail(_ reason: String) { out.append(Failure(label: label, reason: reason)) }

          // 1. Every boat entirely in bounds.
          for b in s.boats where !b.cells.allSatisfy({ s.inBounds($0) }) {
              fail("boat \(b.id) out of bounds at (\(b.x),\(b.y)) bow \(b.bow.rawValue)")
          }

          // 2. No overlapping footprints.
          var footprints = Set<HJCell>()
          var overlapped = false
          for b in s.boats {
              for c in b.cells where !footprints.insert(c).inserted { overlapped = true }
          }
          if overlapped { fail("overlapping boat footprints") }
          if s.boats.count != config.boatCount { fail("boat count \(s.boats.count) != \(config.boatCount)") }

          // 3. Sandbars disjoint from boat footprints.
          if !Set(s.sandbars).isDisjoint(with: footprints) { fail("sandbar under a hull") }
          if Set(s.sandbars).count != s.sandbars.count { fail("duplicate sandbar cell") }

          // 4. Basins disjoint from sandbars, exactly basinCount of them, all distinct.
          if !Set(s.basins).isDisjoint(with: Set(s.sandbars)) { fail("basin on a sandbar") }
          if Set(s.basins).count != s.basins.count { fail("duplicate basin cell") }
          if s.basins.count != config.basinCount {
              fail("basin count \(s.basins.count) != \(config.basinCount)")
          }
          for c in s.basins where !s.inBounds(c) { fail("basin out of bounds at (\(c.x),\(c.y))") }

          // 5. Exactly chainCount chains, no self-anchor, no cycle.
          let chains = s.boats.filter { $0.anchoredBy != nil }
          if chains.count != config.chainCount {
              fail("chain count \(chains.count) != \(config.chainCount)")
          }
          let ids = Set(s.boats.map { $0.id })
          for b in chains {
              guard let key = b.anchoredBy else { continue }
              if key == b.id { fail("boat \(b.id) anchored by itself") }
              if !ids.contains(key) { fail("boat \(b.id) anchored by missing boat \(key)") }
          }
          var anchor: [Int: Int] = [:]
          for b in s.boats { if let k = b.anchoredBy { anchor[b.id] = k } }
          for b in s.boats {
              var seen: Set<Int> = [b.id]
              var cur = b.id
              while let next = anchor[cur] {
                  if seen.contains(next) { fail("anchor cycle through boat \(b.id)"); break }
                  seen.insert(next)
                  cur = next
              }
          }

          // 6. Throttle in 1...3 on every hull.
          for b in s.boats where b.throttle < 1 || b.throttle > 3 {
              fail("boat \(b.id) throttle \(b.throttle) outside 1...3")
          }

          // 7. Lane periods in {2,3,4}; no lanes at all when the envelope says no currents.
          if !config.useCurrents && !s.currents.isEmpty { fail("currents on a no-current envelope") }
          for lane in s.currents where lane.period < 2 || lane.period > 4 {
              fail("lane period \(lane.period) outside 2...4")
          }

          // 8. Inverted sandbar polarity: every sandbar sits in some boat's exit corridor, and the
          //    sandbars together threaten at least two distinct boats.
          if config.useTide {
              if s.sandbars.count < 2 { fail("tide envelope with \(s.sandbars.count) sandbars") }
              var owners: [HJCell: Set<Int>] = [:]
              for b in s.boats {
                  for c in HJForge.exitCorridor(for: b, gridW: s.gridW, gridH: s.gridH)
                  where !footprints.contains(c) {
                      owners[c, default: []].insert(b.id)
                  }
              }
              var covered = Set<Int>()
              for c in s.sandbars {
                  guard let o = owners[c] else { fail("sandbar (\(c.x),\(c.y)) outside every corridor"); continue }
                  covered.formUnion(o)
              }
              if covered.count < 2 { fail("sandbars threaten \(covered.count) distinct boats, need 2") }
          } else if !s.sandbars.isEmpty {
              fail("sandbars on a no-tide envelope")
          }

          // 9. Ferry starts clear of hulls and sandbars.
          if let f = s.ferry {
              if f.row < 0 || f.row >= s.gridH { fail("ferry row \(f.row) out of bounds") }
              for i in 0..<f.length {
                  let c = HJCell(x: (f.x + i) % s.gridW, y: f.row)
                  if footprints.contains(c) { fail("ferry starts under boat at (\(c.x),\(c.y))") }
                  if s.sandbars.contains(c) { fail("ferry starts on sandbar at (\(c.x),\(c.y))") }
              }
          } else if config.useFerry {
              fail("ferry envelope produced no ferry")
          }

          return out
      }
  }
  SWIFT
  ```

- [ ] **Step 9: Append the 1 000-seed driver to `tools/HarborForge/ForgeCheck.swift`.**

  Note what is asserted and what is only reported. Board counts, yields and failure seeds are values nobody can know before the first run, so they are **printed** as INFO. What is **asserted** is properties: every produced board is structurally sound, every chapter envelope produces at least one board (otherwise the invariants above would pass vacuously), and chains occur in both id directions (which is the proof that the old `keyIdx < lockIdx` rule is gone).

  ```sh
  cat >> tools/HarborForge/ForgeCheck.swift <<'SWIFT'

  extension HJForgeCheck {

      static func run() -> Int32 {
          let seedCount = 1000
          let chapterCount = HJCatalog.chapters.count

          var failures: [Failure] = []
          var attempted = [Int](repeating: 0, count: chapterCount)
          var produced  = [Int](repeating: 0, count: chapterCount)
          var chainsKeyBelowLock = 0
          var chainsKeyAboveLock = 0
          var totalChains = 0

          for i in 0..<seedCount {
              let chapter = i % chapterCount
              let level = (i / chapterCount) % HJCatalog.levelsPerChapter
              let config = HJCatalog.config(chapter: chapter, level: level)
              let seed = HJCatalog.seed(chapter: chapter, level: level)
                  &+ UInt64(i) &* 0x9E3779B97F4A7C15
              let label = "ch\(chapter) lv\(level) i=\(i)"

              attempted[chapter] += 1
              guard let board = HJForge.board(seed: seed, config: config) else { continue }
              produced[chapter] += 1
              failures.append(contentsOf: validate(board, config: config, label: label))

              for b in board.boats {
                  guard let key = b.anchoredBy else { continue }
                  totalChains += 1
                  if key < b.id { chainsKeyBelowLock += 1 } else { chainsKeyAboveLock += 1 }
              }
          }

          print("HJForge structural check — \(seedCount) seeds")
          for c in 0..<chapterCount {
              print("  chapter \(c): produced \(produced[c]) / \(attempted[c]) attempted")
          }
          print("  chains: \(totalChains) total, key id < lock id: \(chainsKeyBelowLock), key id > lock id: \(chainsKeyAboveLock)")

          var hard: [String] = []
          for c in 0..<chapterCount where produced[c] == 0 {
              hard.append("chapter \(c) produced zero boards over \(attempted[c]) seeds")
          }
          if totalChains == 0 {
              hard.append("no chained board was produced — chapters with chainCount > 0 never generated")
          } else if chainsKeyBelowLock == 0 || chainsKeyAboveLock == 0 {
              hard.append("chains run in one id direction only — an ordering constraint has crept back in")
          }

          if failures.isEmpty && hard.isEmpty {
              print("PASS")
              return 0
          }
          for h in hard { print("FAIL \(h)") }
          for f in failures.prefix(20) { print("FAIL [\(f.label)] \(f.reason)") }
          if failures.count > 20 { print("FAIL ... and \(failures.count - 20) more board failures") }
          print("FAIL — \(failures.count) board failure(s), \(hard.count) corpus failure(s)")
          return 1
      }
  }
  SWIFT
  ```

- [ ] **Step 10: Create the check binary's entry point.**

  It lives in its own directory so it never collides with another `main.swift` under `tools/HarborForge`; only one file per swiftc invocation may carry top-level code.

  ```sh
  cat > tools/HarborForge/CheckForge/main.swift <<'SWIFT'
  import Foundation

  exit(HJForgeCheck.run())
  SWIFT
  ```

- [ ] **Step 11: Keep the build output out of git.**

  ```sh
  grep -qxF 'tools/HarborForge/bin/' .gitignore || printf 'tools/HarborForge/bin/\n' >> .gitignore
  tail -3 .gitignore
  ```

  Assertion: `tools/HarborForge/bin/` appears exactly once — `grep -c 'tools/HarborForge/bin/' .gitignore` prints `1`.

- [ ] **Step 12: Build the check binary.**

  ```sh
  xcrun -sdk macosx swiftc -swift-version 5 -O \
    -o tools/HarborForge/bin/forgecheck \
    "Harbor Jam/HJModels.swift" \
    "Harbor Jam/HJEngine.swift" \
    tools/HarborForge/Forge.swift \
    tools/HarborForge/ForgeCheck.swift \
    tools/HarborForge/CheckForge/main.swift
  echo "exit=$?"
  ```

  Assertion: `exit=0` and `tools/HarborForge/bin/forgecheck` exists. The app's generator (`Harbor Jam/HJGenerator.swift`) is deliberately **not** on this list — the forge replaces it and does not link against it.

- [ ] **Step 13: Run the check.**

  ```sh
  ./tools/HarborForge/bin/forgecheck; echo "exit=$?"
  ```

  Assertion: the last printed line is `PASS` and `exit=0`. The per-chapter `produced / attempted` lines are informational; record them in the commit body as the first measured packing yield. Any `FAIL` line names the exact board (`ch<n> lv<n> i=<n>`) — reproduce it by re-running, since the seed is a pure function of that triple.

- [ ] **Step 14: Prove determinism (no hash-order leak).**

  ```sh
  ./tools/HarborForge/bin/forgecheck > /tmp/forgecheck.a.txt
  ./tools/HarborForge/bin/forgecheck > /tmp/forgecheck.b.txt
  diff -q /tmp/forgecheck.a.txt /tmp/forgecheck.b.txt && echo "DETERMINISTIC"
  ```

  Assertion: `diff` reports no difference and `DETERMINISTIC` prints. A difference means some RNG draw is reading an unsorted `Set`/`Dictionary`, which would make every witness baked in Task 8 unreproducible; the only sanctioned fix is to sort the collection before drawing from it, as `pickSandbars` does.

- [ ] **Step 15: Confirm nothing in the app target was touched, then commit.**

  ```sh
  git status --porcelain
  ```

  Assertion: the only entries are `.gitignore` (modified) and the three new files under `tools/HarborForge/`. No path beginning with `Harbor Jam/` may appear.

  ```sh
  git add tools/HarborForge/Forge.swift \
          tools/HarborForge/ForgeCheck.swift \
          tools/HarborForge/CheckForge/main.swift \
          .gitignore
  git commit -m "Forge: forward board generation replaces reverse construction

  HJForge packs the grid forward — random legal footprints, random bows, throttle
  drawn from {1,2,3} — instead of placing boat i only after every boat with id > i
  with a clear corridor (HJGenerator.swift:97), which made ascending exit order a
  complete solver. Sandbars now come FROM the exit corridors rather than their
  complement (inverting HJGenerator.swift:122-135) and must threaten two distinct
  boats; buoy chains drop the keyIdx < lockIdx rule (:113-117) and reject only
  anchor cycles; lanes carry a flip period from {2,3,4}; basins are placed clear of
  hulls and sandbars.

  No solution, no par and no solvability claim are produced here. The structural
  harness (tools/HarborForge/bin/forgecheck, 1000 seeds over every chapter
  envelope) asserts in-bounds non-overlapping hulls, sandbars clear of hulls,
  basins clear of sandbars, exact basin and chain counts, throttle and period
  ranges, chains running in both id directions, and byte-identical output across
  two runs.

  Co-Authored-By: Claude <noreply@anthropic.com>"
  ```


---

### Task 6: Witness search (HJSearch)

**Files:**
- `tools/HarborForge/Search.swift` — new
- `tools/HarborForge/checks/main.swift` — new
- (no file under `Harbor Jam/` is touched; the pbxproj is not touched — the harness is offline and never enters the app target)

**Interfaces:**

*Consumes* (all defined in Tasks 1–4, all already on disk when this task starts):
```swift
// Task 1 — Harbor Jam/HJModels.swift
struct HJCell: Hashable, Codable { var x: Int; var y: Int }
struct HJBoat: Codable, Identifiable, Equatable {
    var id: Int; var x: Int; var y: Int; var length: Int; var isBarge: Bool
    var bow: HJDirection; var hullIndex: Int; var anchoredBy: Int?; var throttle: Int
}
struct HJCurrentLane: Codable, Equatable { var isRow: Bool; var index: Int
                                           var push: HJDirection; var period: Int }
enum HJDirection: Int, Codable, CaseIterable { case north = 0, east = 1, south = 2, west = 3 }
struct HJFerry: Codable, Equatable { var row: Int; var x: Int; var length: Int; var stride: Int }

// Task 4 — Harbor Jam/HJEngine.swift  (the engine is FINAL as of Task 4)
struct HJBoardState: Codable, Equatable { /* …; var basins: [HJCell]; var taps: Int; … */
    var boats: [HJBoat]; var currents: [HJCurrentLane]; var ferry: HJFerry?
    var tideHigh: Bool; var isCleared: Bool { get } }
enum HJTapOutcome: Equatable { case exited(boatID: Int); case moved(boatID: Int, distance: Int)
                               case blocked(reason: HJBlockReason); case anchored; case invalid }
enum HJEngine { static func tap(boatID: Int, state: inout HJBoardState) -> HJTapOutcome }

// Task 5 — the tools/HarborForge directory and its plain-swiftc build convention.
```
This task consumes `HJEngine.tap` as an opaque black box and nothing else from the engine. It does **not** call `march`, `preview` or `bowCells`, and it defines no engine behaviour of its own.

*Produces*:
```swift
// tools/HarborForge/Search.swift  (offline only — never compiled into the app target)
enum HJSearchOutcome: Equatable {
    case found([Int])
    case exhausted
    case capped(nodesExpanded: Int)
}
enum HJSearch {
    static func gcd(_ a: Int, _ b: Int) -> Int
    static func lcm(_ a: Int, _ b: Int) -> Int
    static func phaseModulus(_ state: HJBoardState) -> Int
    static func fingerprint(_ state: HJBoardState, phaseModulus: Int) -> UInt64
    static func search(from start: HJBoardState, nodeCap: Int = 2_000_000,
                       depthCap: Int? = nil) -> HJSearchOutcome
    static func witness(from start: HJBoardState, nodeCap: Int = 2_000_000,
                        depthCap: Int? = nil) -> [Int]?
}
```
`witness(from:nodeCap:depthCap:)` is the signature Task 7 bakes against. `search` is the same walk with the reason for failure attached, so a check can tell "no line exists" apart from "a cap stopped us" — spec §2.5 rejects the seed either way, but the harness must be able to prove which happened.

---

**Board derivations (authored and solved by hand here; Step 3 pastes them, Step 4 lets the machine confirm them).**

Both fixtures set `tideEnabled: false`, `currents: []`, `ferry: null`. On such a board `tickWorld` can only increment `taps`, and `phaseModulus` is 1, so `taps` drops out of the canonical key. Every state change is therefore player-caused, and the derivations below depend on nothing but the throttle march, the exit rule, hull blocking and the basin flip.

**Board A — 5×5, two boats, one basin. Minimum line = 6 taps.**

```
        x0    x1    x2    x3    x4
  y0    ..    ..    ..    ..    ..
  y1    ..    ..    ..    ..    1v      boat 1: length 2, bow SOUTH, throttle 3
  y2    BB    ..    0<    0=    1v      boat 0: length 2, bow WEST,  throttle 2
  y3    ..    ..    ..    ..    ..      BB = basin at (0,2)
  y4    ..    ..    ..    ..    ..
```
Boat 0 occupies `(2,2),(3,2)`, bow cell `(2,2)`. Boat 1 occupies `(4,1),(4,2)`, bow cell `(4,2)`.

*Boat 0 costs exactly 4 taps, and the sequence has no branch in it:*
- Tap 1 (west, throttle 2): step to `x=1` → cells `(1,2),(2,2)`, bow `(1,2)`, not a basin. Step to `x=0` → cells `(0,2),(1,2)`, bow `(0,2)` **is** the basin → stop, bow flips to EAST. Distance 2.
- The basin sits on the west edge of row 2, so boat 0 can never reach `x=-1`: the only way out is east. And the only basin on the board flips *to* east, so once east, always east.
- Tap 2 (east): `x=1`, then `x=2` → cells `(2,2),(3,2)`. Distance 2.
- Tap 3 (east): `x=3` → cells `(3,2),(4,2)` — needs `(4,2)` free. Then `x=4` → cells `(4,2),(5,2)`; `(5,2)` is out past the bow-side edge and `(4,2)` is still in bounds, so this is a rest, not an exit. Distance 2.
- Tap 4 (east): `x=5` → cells `(5,2),(6,2)`, no in-bounds cell left → **exited**.

Total travel is 2 west + 5 east = 7 cell-steps, and the basin truncates tap 1's second half onto the flip, so 4 taps is both the count and the floor for a throttle-2 hull.

*Boat 1 costs exactly 2 taps:* from `y=1`, throttle 3 walks `y=2, y=3, y=4` (at `y=4` cells are `(4,4),(4,5)`; `(4,4)` is in bounds, so it rests). Tap 2 steps to `y=5`, both cells out → exited. Four cell-steps at throttle 3 cannot be done in one tap.

*Ordering:* boat 1 occupies `(4,2)` at the start, so boat 0's tap 3 is blocked until boat 1 has taken at least one tap. Boat 1's column (`x=4`, rows 2→5) is never occupied by boat 0 before boat 0's tap 3 lands, so boat 1's own march is never blocked. No tap serves both hulls and a blocked tap only adds length, so the minimum is **4 + 2 = 6**, and 6 is achieved by e.g. `[1,0,0,0,0,1]` or `[1,0,0,1,0,0]`. Several distinct 6-tap orders exist, so the check asserts the **length** and the **multiset** — any 6-tap line must be exactly four taps of boat 0 and two of boat 1 — not one particular ordering.

**Board B — 4×4, one boat facing a wall of two mutually blocked barges, no basin. Provably unsolvable.**

```
        x0    x1    x2    x3
  y0    ..    ..    AA    AA      A = barge id 1 (2x2 at (2,0)), bow SOUTH
  y1    0=    0>    Av    Av      0 = boat id 0, length 2, bow EAST, throttle 3
  y2    ..    ..    B^    B^      B = barge id 2 (2x2 at (2,2)), bow NORTH
  y3    ..    ..    BB    BB
```
- Barge 1 marching south would need `(2,2),(3,2)` — barge 2 holds them. Distance 0.
- Barge 2 marching north would need `(2,1),(3,1)` — barge 1 holds them. Distance 0.
- Boat 0 marching east would need `(2,1)` — barge 1 holds it. Distance 0.

Every tap is `.blocked`, and `.blocked` mutates nothing but `taps`, which is outside the canonical key on a laneless, tideless board. So all three successors of the root fold back onto the root, the frontier empties on the first sweep, and the search returns `.exhausted` — not `.capped`. That distinction is the whole point of the fixture: an unsolvable board must be *proved* unsolvable, not merely give up.

---

- [ ] **Step 1: Create the harness directories and prove Tasks 1–4 actually landed the symbols this search reads.**

```bash
cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam"
mkdir -p tools/HarborForge/checks
fail=0
need() { if grep -qF "$2" "$1"; then echo "PASS  $1 has: $2"; else echo "FAIL  $1 missing: $2"; fail=1; fi; }
gone() { if grep -qF "$2" "$1"; then echo "FAIL  $1 still has: $2"; fail=1; else echo "PASS  $1 free of: $2"; fi; }
need "Harbor Jam/HJModels.swift" "var throttle: Int"
need "Harbor Jam/HJModels.swift" "var period: Int"
need "Harbor Jam/HJEngine.swift" "var basins: [HJCell]"
need "Harbor Jam/HJEngine.swift" "static func tap(boatID: Int, state: inout HJBoardState) -> HJTapOutcome"
gone "Harbor Jam/HJEngine.swift" "tugTokens"
gone "Harbor Jam/HJModels.swift" "tugTokens"
[ $fail -eq 0 ] && echo "ALL PRECONDITIONS PASS" || echo "STOP: preconditions not met, do not start Task 6"
```
Do not continue unless the last line reads `ALL PRECONDITIONS PASS`.

- [ ] **Step 2: Write `tools/HarborForge/Search.swift` in full.**

```bash
cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam"
cat > tools/HarborForge/Search.swift <<'SWIFT'
import Foundation

// HarborForge — witness search (spec 2.5 "The search").
//
// Breadth-first over COMMITTED board states. Successors come from the real
// HJEngine.tap, so any line this returns is valid by construction; the baking
// tool still replays it before shipping. This file is offline only — it is never
// added to the Xcode target, because solidCells() allocates a fresh Set per query
// and the device must never search.

/// Why the search stopped.
enum HJSearchOutcome: Equatable {
    /// A complete line: boat ids to tap, in order, that clear the board.
    case found([Int])
    /// The whole reachable state space was enumerated and holds no cleared board.
    case exhausted
    /// A cap stopped the walk first. Per spec 2.5 the seed is REJECTED either way,
    /// but a corpus tool needs to tell an impossible board from an expensive one.
    case capped(nodesExpanded: Int)
}

enum HJSearch {

    // MARK: - Canonical key

    static func gcd(_ a: Int, _ b: Int) -> Int {
        var x = abs(a), y = abs(b)
        while y != 0 { let t = x % y; x = y; y = t }
        return x
    }

    static func lcm(_ a: Int, _ b: Int) -> Int {
        let g = gcd(a, b)
        return g == 0 ? 0 : abs(a / g * b)
    }

    /// lcm of every current lane's period, 1 when the board has no lanes.
    /// `taps` enters the key only modulo this, so on a laneless board a
    /// world-ticking `.blocked` tap folds straight back onto its own parent
    /// instead of spawning an infinite ladder of identical positions.
    static func phaseModulus(_ state: HJBoardState) -> Int {
        var m = 1
        for lane in state.currents where lane.period > 0 {
            m = lcm(m, lane.period)
        }
        return max(1, m)
    }

    /// Deterministic 64-bit fingerprint of (boats sorted by id: id, x, y, bow,
    /// throttle; tideHigh; ferry.x; taps % phaseModulus).
    ///
    /// Hand-rolled rather than Swift's Hasher: Hasher is seeded per process, and a
    /// baking tool that returns a different witness on every run is not a baking
    /// tool. `id` is folded in as well as used for the sort, so two boards with
    /// interchangeable hulls at the same coordinates cannot collapse into one node.
    /// A fingerprint collision can only prune a branch, never forge a line — the
    /// path is replayed through the engine before it is used.
    static func fingerprint(_ state: HJBoardState, phaseModulus: Int) -> UInt64 {
        var h: UInt64 = 0xCBF2_9CE4_8422_2325          // FNV-1a offset basis
        func mix(_ v: Int) {
            var u = UInt64(bitPattern: Int64(v))
            u = (u ^ (u >> 30)) &* 0xBF58_476D_1CE4_E5B9
            u = (u ^ (u >> 27)) &* 0x94D0_49BB_1331_11EB
            u ^= (u >> 31)
            h = (h ^ u) &* 0x0000_0100_0000_01B3        // FNV prime
        }
        for b in state.boats.sorted(by: { $0.id < $1.id }) {
            mix(b.id); mix(b.x); mix(b.y); mix(b.bow.rawValue); mix(b.throttle)
        }
        mix(state.tideHigh ? 1 : 0)
        mix(state.ferry?.x ?? -1)
        mix(phaseModulus > 1 ? state.taps % phaseModulus : 0)
        return h
    }

    // MARK: - Breadth-first walk

    /// Level-synchronous BFS. Only the current and next frontier hold whole board
    /// states; every visited node costs two Ints in `trail` (for path rebuilding)
    /// and eight bytes in `seen`, so the 2 000 000 node cap is tens of megabytes of
    /// bookkeeping plus one frontier.
    ///
    /// - Parameters:
    ///   - nodeCap: maximum nodes EXPANDED before giving up (spec: 2 000 000).
    ///   - depthCap: maximum witness length; nil means 4 x boat count (spec).
    static func search(from start: HJBoardState,
                       nodeCap: Int = 2_000_000,
                       depthCap: Int? = nil) -> HJSearchOutcome {
        if start.isCleared { return .found([]) }
        let maxDepth = depthCap ?? (4 * start.boats.count)
        if maxDepth <= 0 { return .capped(nodesExpanded: 0) }
        let modulus = phaseModulus(start)

        // trail[i] = (index of parent node, boat id tapped to reach i). Root is (-1, -1).
        var trail: [(parent: Int, tap: Int)] = [(-1, -1)]
        var seen: Set<UInt64> = [fingerprint(start, phaseModulus: modulus)]

        var frontier: [HJBoardState] = [start]
        var frontierNode: [Int] = [0]
        var depth = 0
        var nodesExpanded = 0
        var hitCap = false

        while !frontier.isEmpty {
            if depth >= maxDepth { hitCap = true; break }
            var nextStates: [HJBoardState] = []
            var nextNodes: [Int] = []
            for (slot, parentState) in frontier.enumerated() {
                if nodesExpanded >= nodeCap { hitCap = true; break }
                nodesExpanded += 1
                let parentNode = frontierNode[slot]
                for boat in parentState.boats.sorted(by: { $0.id < $1.id }) {
                    var child = parentState
                    let outcome = HJEngine.tap(boatID: boat.id, state: &child)
                    if case .invalid = outcome { continue }
                    let fp = fingerprint(child, phaseModulus: modulus)
                    if seen.contains(fp) { continue }
                    seen.insert(fp)
                    trail.append((parent: parentNode, tap: boat.id))
                    let node = trail.count - 1
                    if child.isCleared {
                        return .found(line(to: node, trail: trail))
                    }
                    nextStates.append(child)
                    nextNodes.append(node)
                }
            }
            if hitCap { break }
            frontier = nextStates
            frontierNode = nextNodes
            depth += 1
        }
        return hitCap ? .capped(nodesExpanded: nodesExpanded) : .exhausted
    }

    /// The line the baking tool stores. nil means the seed is rejected — an
    /// unproven par is never shipped.
    static func witness(from start: HJBoardState,
                        nodeCap: Int = 2_000_000,
                        depthCap: Int? = nil) -> [Int]? {
        if case .found(let line) = search(from: start, nodeCap: nodeCap, depthCap: depthCap) {
            return line
        }
        return nil
    }

    private static func line(to node: Int, trail: [(parent: Int, tap: Int)]) -> [Int] {
        var out: [Int] = []
        var i = node
        while i > 0 {
            out.append(trail[i].tap)
            i = trail[i].parent
        }
        return out.reversed()
    }
}
SWIFT
```

- [ ] **Step 3: Write the first half of `tools/HarborForge/checks/main.swift` — the check helper and the two hand-authored boards.**

The fixtures are JSON decoded through `HJBoardState`'s synthesized `Codable`, not a memberwise initializer. That makes them immune to the field ORDER that Tasks 1 and 4 chose inside the struct, and it exercises the exact decode path `levels.json` relies on in Task 7. Omitted optional keys (`anchoredBy`) decode as nil.

```bash
cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam"
cat > tools/HarborForge/checks/main.swift <<'SWIFT'
import Foundation

// HarborForge — Task 6 search checks.
//
// Board A  5x5, two boats, one basin, no currents/tide/ferry.
//          Derived by hand in the plan: minimum line is exactly 6 taps,
//          four of boat 0 and two of boat 1.
// Board B  4x4, one boat facing a wall of two mutually blocked barges, no basin.
//          Derived by hand: no tap ever changes the board, so the search must
//          EXHAUST the space and return nil, not hit a cap.

var failures = 0

func check(_ name: String, _ passed: Bool, _ detail: String = "") {
    if passed {
        print("PASS  \(name)")
    } else {
        failures += 1
        print("FAIL  \(name)" + (detail.isEmpty ? "" : " -- " + detail))
    }
}

func board(_ label: String, _ json: String) -> HJBoardState {
    do {
        return try JSONDecoder().decode(HJBoardState.self, from: Data(json.utf8))
    } catch {
        print("FAIL  \(label): fixture does not decode into HJBoardState -- \(error)")
        exit(1)
    }
}

// bow raw values: north 0, east 1, south 2, west 3.

let boardAJSON = """
{
  "gridW": 5,
  "gridH": 5,
  "boats": [
    { "id": 0, "x": 2, "y": 2, "length": 2, "isBarge": false, "bow": 3, "hullIndex": 0, "throttle": 2 },
    { "id": 1, "x": 4, "y": 1, "length": 2, "isBarge": false, "bow": 2, "hullIndex": 1, "throttle": 3 }
  ],
  "exitedIDs": [],
  "sandbars": [],
  "currents": [],
  "ferry": null,
  "tideEnabled": false,
  "tideHigh": true,
  "basins": [ { "x": 0, "y": 2 } ],
  "taps": 0,
  "night": false
}
"""

let boardBJSON = """
{
  "gridW": 4,
  "gridH": 4,
  "boats": [
    { "id": 0, "x": 0, "y": 1, "length": 2, "isBarge": false, "bow": 1, "hullIndex": 0, "throttle": 3 },
    { "id": 1, "x": 2, "y": 0, "length": 2, "isBarge": true,  "bow": 2, "hullIndex": 1, "throttle": 2 },
    { "id": 2, "x": 2, "y": 2, "length": 2, "isBarge": true,  "bow": 0, "hullIndex": 2, "throttle": 2 }
  ],
  "exitedIDs": [],
  "sandbars": [],
  "currents": [],
  "ferry": null,
  "tideEnabled": false,
  "tideHigh": true,
  "basins": [],
  "taps": 0,
  "night": false
}
"""

let boardA = board("boardA", boardAJSON)
let boardB = board("boardB", boardBJSON)
SWIFT
```

- [ ] **Step 4: Append the assertions to `tools/HarborForge/checks/main.swift`.**

```bash
cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam"
cat >> tools/HarborForge/checks/main.swift <<'SWIFT'

// MARK: - Board A: solvable, and the answer is 6

switch HJSearch.search(from: boardA) {
case .found(let witness):
    check("A1 witness length is 6", witness.count == 6, "got \(witness.count): \(witness)")
    check("A2 witness is four taps of boat 0 and two of boat 1",
          witness.sorted() == [0, 0, 0, 0, 1, 1], "got \(witness)")

    var replay = boardA
    var everyTapProductive = true
    var trace: [String] = []
    for id in witness {
        let outcome = HJEngine.tap(boatID: id, state: &replay)
        trace.append("\(id)->\(outcome)")
        switch outcome {
        case .moved, .exited: break
        default: everyTapProductive = false
        }
    }
    check("A3 witness replays through HJEngine.tap with no blocked/anchored/invalid tap",
          everyTapProductive, trace.joined(separator: "  "))
    check("A4 witness replays to a cleared board", replay.isCleared,
          "boats still afloat: \(replay.boats.map { $0.id })")
case .exhausted:
    check("A1 search finds a line", false, "search reported .exhausted on a solvable board")
case .capped(let n):
    check("A1 search finds a line", false, "search reported .capped after \(n) nodes")
}

var cappedByDepth = false
if case .capped = HJSearch.search(from: boardA, depthCap: 3) { cappedByDepth = true }
check("A5 a depth cap below the true answer reports .capped", cappedByDepth)
check("A6 a depth cap below the true answer yields no witness",
      HJSearch.witness(from: boardA, depthCap: 3) == nil)

var cappedByNodes = false
if case .capped = HJSearch.search(from: boardA, nodeCap: 1) { cappedByNodes = true }
check("A7 a node cap of 1 reports .capped", cappedByNodes)

// MARK: - Board B: provably unsolvable

var allBlocked = true
var openingTaps: [String] = []
for b in boardB.boats {
    var probe = boardB
    let outcome = HJEngine.tap(boatID: b.id, state: &probe)
    openingTaps.append("\(b.id)->\(outcome)")
    if case .blocked = outcome {} else { allBlocked = false }
}
check("B1 every hull on board B is blocked on the opening tap", allBlocked,
      openingTaps.joined(separator: "  "))

let outcomeB = HJSearch.search(from: boardB)
check("B2 board B is EXHAUSTED, not capped -- unsolvability is proved, not assumed",
      outcomeB == .exhausted, "got \(outcomeB)")
check("B3 board B has no witness", HJSearch.witness(from: boardB) == nil)

// MARK: - Verdict

if failures == 0 {
    print("\nOK  all search checks passed")
    exit(0)
} else {
    print("\n\(failures) SEARCH CHECK(S) FAILED")
    exit(1)
}
SWIFT
```

- [ ] **Step 5: Build the check binary with plain swiftc against the real engine sources.**

`-swift-version 5` is required: the check file keeps a top-level `var failures`, which Swift 6 language mode rejects as global mutable state. The binary goes under `tools/HarborForge/build/`, which the repo's existing `.gitignore` rule `build/` already excludes, so no `.gitignore` edit is needed.

```bash
cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam"
mkdir -p tools/HarborForge/build
swiftc -swift-version 5 -O \
  -o tools/HarborForge/build/searchcheck \
  "Harbor Jam/HJModels.swift" \
  "Harbor Jam/HJEngine.swift" \
  tools/HarborForge/Search.swift \
  tools/HarborForge/checks/main.swift
echo "swiftc exit: $?"
```
Required assertion: `swiftc exit: 0` with no warnings printed above it.

- [ ] **Step 6: Run the checks; every line must be PASS and the process must exit 0.**

```bash
cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam"
./tools/HarborForge/build/searchcheck
echo "searchcheck exit: $?"
```
Required assertions, all enforced by the binary itself:
- ten `PASS` lines, `A1`–`A7` and `B1`–`B3`, and zero `FAIL` lines;
- final line `searchcheck exit: 0`.

If `A1` reports a length other than 6, the engine from Task 4 does not implement the throttle march or the basin flip as spec §2.1/§2.4 state — fix Task 4, do not adjust the expected 6, because 6 is derived above from the spec rather than observed from the code. If `B2` reports `.capped`, `.blocked` is leaking a state change into the canonical key (check that `tickWorld` touches nothing but `taps` on a laneless, tideless, ferryless board).

- [ ] **Step 7: Commit.**

```bash
cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam"
git add tools/HarborForge/Search.swift tools/HarborForge/checks/main.swift
git commit -m "$(cat <<'MSG'
HarborForge: witness search over committed board states

Breadth-first search whose successors come from the real HJEngine.tap, so any
line it returns is valid by construction. Transposition set keyed on a
deterministic 64-bit fingerprint of the boats (sorted by id: id, x, y, bow,
throttle), tideHigh, ferry.x and taps modulo the lcm of the lane periods; node
cap 2 000 000, depth cap 4 x boat count. Reaching a cap returns nil so the
seed is rejected rather than shipped with an unproven par.

Checks cover two hand-derived boards: a 5x5 two-boat board with a basin on the
west edge of the boat's row, whose minimum line is provably 6 taps, and a 4x4
board where a hull faces two mutually blocked barges with no basin, which the
search must EXHAUST rather than give up on.

Co-Authored-By: Claude <noreply@anthropic.com>
MSG
)"
```


---

### Task 7: Acceptance gate, the bake, and the go/no-go checkpoint

This is the checkpoint the spec demands (§2.5 "Checkpoint gate", §5 risk 1). It measures the one number nobody has: the acceptance yield on real boards, and the greedy three-star rate on the corpus that would actually ship. **No app-behaviour change lands in Tasks 8+ until this task's verdict is GO.**

The engine is FINAL as of Task 4. Nothing in this task touches `tap`, `march`, `preview`, `tickWorld`, `applyCurrents` or the basin rule — the corpus is only meaningful because every witness in it was searched against the exact engine binary-identical to the one that ships.

**Files:**

- `tools/HarborForge/Gate.swift` — new
- `tools/HarborForge/main.swift` — one insertion (the `bake` subcommand)
- `Harbor Jam/levels.json` — new, generated (flat in `Harbor Jam/`, **not** a `Resources/` subfolder)
- `tools/HarborForge/YIELD.md` — new, generated
- `Harbor Jam.xcodeproj/project.pbxproj` — four insertions registering `levels.json`
- Retuning levers only, and only if the verdict is NO-GO: `Harbor Jam/HJGenerator.swift`, `Harbor Jam/HJModels.swift`

**Interfaces:**

*Consumes* (every symbol below is defined in a task numbered lower than 7):

- Task 1 — `func forgeRolloutB(start: HJBoardState, seed: UInt64, moveCap: Int) -> Int?` (moves taken to clear under the "tap anything that advances, prefer anything that exits" policy; `nil` = did not clear inside `moveCap`)
- Task 1 — `tools/HarborForge/main.swift`, a subcommand `switch` with exactly one bare `default:` line
- Tasks 2–3 — `HJBoat.throttle`, `HJBoardState.basins`, `HJLevelConfig.basinCount`, `HJCatalog.chapters`, `HJCatalog.levelsPerChapter`, `HJCatalog.config(chapter:level:)`, `HJCatalog.seed(chapter:level:)`, `HJCatalog.dailyConfig`
- Task 4 — `HJEngine.tap(boatID:state:) -> HJTapOutcome`, `HJTapOutcome` (Equatable), `HJBoardState.isCleared`
- Task 5 — `HJGenerator.level(seed:config:maxSalts:) -> HJGeneratedLevel?` (exists today at `Harbor Jam/HJGenerator.swift:35`; Task 5 rewrites its body, keeping the signature), and `HJGeneratedLevel.start`
- Task 6 — `func forgeSearch(start: HJBoardState, nodeCap: Int, depthCap: Int) -> [Int]?` (breadth-first witness search, boat ids in tap order; `nil` = no line inside the node/depth caps)

*Produces:*

```
func gateSearch(_ board: HJBoardState) -> [Int]?
func gateRolloutSeed(_ start: HJBoardState, _ index: Int) -> UInt64
func gateVariants(of start: HJBoardState) -> [GateVariant]
func gateEvaluate(start: HJBoardState, report: inout GateReport) -> GateOutcome
func gateBakeOne(baseSeed: UInt64, config: HJLevelConfig, report: inout GateReport) -> HJLevelRecord?
func gateSelfCheck(path: String) -> String
func gateFinish(root: String, smoke: Bool, report: GateReport,
                campaign: [String: HJLevelRecord], daily: [HJLevelRecord],
                t0: Date, failure: String?) -> Never
func forgeBake(smoke: Bool)
struct HJLevelRecord: Codable { var par: Int; var witness: [Int]; var start: HJBoardState }
struct HJLevelTableFile: Codable { var version: Int; var campaign: [String: HJLevelRecord]; var daily: [HJLevelRecord] }
enum GateClause: Int, CaseIterable { case a, b, c, d }
struct GateVariant { var name: String; var board: HJBoardState }
struct GateResult { var witness: [Int]; var greedyBest: Int? }
enum GateOutcome { case accepted(GateResult); case rejected(GateClause); case unsearchable }
struct GateReport { ... }
```

plus the artifacts `Harbor Jam/levels.json` and `tools/HarborForge/YIELD.md`.

---

- [ ] **Step 1: Preflight — prove the six consumed symbols exist before writing a line against them.**

`Gate.swift` has exactly two call sites into other people's harness code (`gateSearch` wraps `forgeSearch`; `gateEvaluate` calls `forgeRolloutB`). Run this first; if it prints FAIL, fix the call site spelling in Step 3 and nowhere else.

```bash
cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam" && python3 - <<'PY'
import glob, io, sys
need = [
    ("func forgeRolloutB",     glob.glob("tools/HarborForge/*.swift"), "Task 1"),
    ("func forgeSearch",       glob.glob("tools/HarborForge/*.swift"), "Task 6"),
    ("static func level(seed", ["Harbor Jam/HJGenerator.swift"],       "Task 5"),
    ("var basins",             ["Harbor Jam/HJEngine.swift"],          "Task 4"),
    ("var throttle",           ["Harbor Jam/HJModels.swift"],          "Tasks 2-3"),
    ("var basinCount",         ["Harbor Jam/HJModels.swift"],          "Tasks 2-3"),
]
ok = True
for token, files, owner in need:
    found = []
    for f in files:
        try:
            for i, line in enumerate(io.open(f, encoding="utf-8"), 1):
                if token in line:
                    found.append("%s:%d  %s" % (f, i, line.rstrip()))
        except IOError:
            pass
    if found:
        for f in found:
            print("  ok   %s" % f)
    else:
        ok = False
        print("  MISSING  %r (owed by %s) in %s" % (token, owner, files))
bare = 0
try:
    for line in io.open("tools/HarborForge/main.swift", encoding="utf-8"):
        if line.strip() == "default:":
            bare += 1
except IOError:
    ok = False
    print("  MISSING  tools/HarborForge/main.swift (owed by Task 1)")
if bare != 1:
    ok = False
    print("  FAIL  main.swift has %d bare 'default:' lines, want exactly 1" % bare)
print("PASS: every consumed symbol is present" if ok else "FAIL: Task 7 cannot start")
sys.exit(0 if ok else 1)
PY
```

- [ ] **Step 2: Create `tools/HarborForge/Gate.swift` — tunables, the wire format, and the report type.**

```bash
cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam" && cat > tools/HarborForge/Gate.swift <<'SWIFT'
import Foundation

// ============================================================================
// Task 7 — the acceptance gate (spec 2.5) and the bake.
//
// HJEngine is FINAL as of Task 4. This file READS tap / preview / march /
// tickWorld / applyCurrents and never redefines or reaches around them: every
// witness baked here is only valid because it was searched against the exact
// engine that ships.
// ============================================================================

// MARK: - Tunables (these are the retuning levers; see tools/HarborForge/YIELD.md)

let gateRolloutCount    = 200          // spec 2.5 clause (b)
let gateRolloutRatio    = 1.25         // LEVER 3 — clause (b) ratio
let gateSearchNodeCap   = 2_000_000    // spec 2.5
let gateMaxSalts        = 1_500        // salts tried per (chapter, level)
let gateDailyCount      = 400          // spec 2.10
let gateGreedyLimit     = 0.15         // spec 6 — the go/no-go number
let gateTableVersion    = 1            // levels.json format version

// MARK: - Wire format of Harbor Jam/levels.json

/// DELIBERATE MIRROR. These two types are declared a second time in the app,
/// in `Harbor Jam/HJLevelTable.swift` (a later task). The harness and the app
/// are separate compilation units — this file is never compiled into the app
/// and HJLevelTable.swift is never compiled into the harness — so this is not
/// a duplicate symbol. The field names and types ARE the wire format of
/// Harbor Jam/levels.json and must stay byte-identical in both places.
struct HJLevelRecord: Codable {
    var par: Int
    var witness: [Int]
    var start: HJBoardState
}

struct HJLevelTableFile: Codable {
    var version: Int
    var campaign: [String: HJLevelRecord]   // key "chapter-level", same shape as
                                            // HJGenerator.swift:49 and HJSave's record keys
    var daily: [HJLevelRecord]
}

// MARK: - Clause bookkeeping

enum GateClause: Int, CaseIterable {
    case a = 0, b, c, d

    var label: String {
        switch self {
        case .a: return "(a) witness no longer than the boat count"
        case .b: return "(b) greedy median under the required ratio"
        case .c: return "(c) fewer than two boats tapped 3+ times"
        case .d: return "(d) some mechanic on the board is decorative"
        }
    }
}

struct GateVariant {
    var name: String
    var board: HJBoardState
}

struct GateResult {
    var witness: [Int]
    var greedyBest: Int?     // fewest moves any clause-(b) rollout needed; nil = never cleared
}

enum GateOutcome {
    case accepted(GateResult)
    case rejected(GateClause)
    case unsearchable        // no line inside the node/depth caps — never shipped (spec 2.5)
}

struct GateReport {
    var boardsTried = 0
    var constructionFailures = 0
    var unsearchable = 0
    var rejections = [0, 0, 0, 0]        // indexed by GateClause.rawValue
    var accepted = 0
    var greedyThreeStars = 0
    var dVariantCapped = 0               // clause (d) decided by a cap, not by a proof
    var witnessLengths: [Int] = []
    var boatCounts: [Int] = []
}

func gateProgress(_ line: String) {
    FileHandle.standardError.write(Data(("[forge] " + line + "\n").utf8))
}

func gateMedian(_ xs: [Double]) -> Double {
    guard !xs.isEmpty else { return 0 }
    let s = xs.sorted()
    return s[s.count / 2]
}
SWIFT
echo "PASS: Gate.swift part 1 written ($(wc -l < tools/HarborForge/Gate.swift) lines)"</parameter>
```

- [ ] **Step 3: Append the four clauses of spec §2.5, verbatim.**

Clause order is cheapest-first so the rejection histogram is meaningful and the expensive searches run last: one search, then (a), then (c), then 200 rollouts for (b), then up to five more searches for (d).

```bash
cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam" && cat >> tools/HarborForge/Gate.swift <<'SWIFT'

// MARK: - The only bridge to Task 6's search

/// If Task 6 spelled its parameters differently, THIS THREE-LINE FUNCTION is
/// the only thing in Task 7 that has to change. Nothing else calls forgeSearch.
func gateSearch(_ board: HJBoardState) -> [Int]? {
    forgeSearch(start: board,                                   // CALL SITE (Task 6)
                nodeCap: gateSearchNodeCap,
                depthCap: 4 * max(1, board.boats.count))
}

/// Deterministic per-board, per-rollout seed: the same board always draws the
/// same 200 rollouts, so a rerun of the bake reproduces the same verdict.
func gateRolloutSeed(_ start: HJBoardState, _ index: Int) -> UInt64 {
    var h: UInt64 = 0xCBF29CE484222325
    for b in start.boats {
        var v = b.id
        v = v &* 31 &+ b.x
        v = v &* 31 &+ b.y
        v = v &* 31 &+ b.bow.rawValue
        v = v &* 31 &+ b.throttle
        h = (h ^ UInt64(bitPattern: Int64(v))) &* 0x100000001B3
    }
    h = (h ^ UInt64(bitPattern: Int64(start.gridW &* 97 &+ start.gridH))) &* 0x100000001B3
    return h &+ UInt64(index) &* 0x2545F4914F6CDD1D
}

/// Clause (d): one variant per mechanic actually PRESENT on this board.
/// Pure value-type surgery on HJBoardState — no engine symbol is touched here,
/// and the re-search below goes through HJEngine.tap exactly like the primary
/// search does.
func gateVariants(of start: HJBoardState) -> [GateVariant] {
    var out: [GateVariant] = []
    if !start.sandbars.isEmpty {
        var b = start; b.sandbars = []
        out.append(GateVariant(name: "sandbars", board: b))
    }
    if !start.currents.isEmpty {
        var b = start; b.currents = []
        out.append(GateVariant(name: "currents", board: b))
    }
    if start.ferry != nil {
        var b = start; b.ferry = nil
        out.append(GateVariant(name: "ferry", board: b))
    }
    if !start.basins.isEmpty {
        var b = start; b.basins = []
        out.append(GateVariant(name: "basins", board: b))
    }
    if start.boats.contains(where: { $0.anchoredBy != nil }) {
        var b = start
        for i in b.boats.indices { b.boats[i].anchoredBy = nil }
        out.append(GateVariant(name: "chains", board: b))
    }
    return out
}

// MARK: - The gate

func gateEvaluate(start: HJBoardState, report: inout GateReport) -> GateOutcome {
    guard let witness = gateSearch(start) else { return .unsearchable }
    let boatCount = start.boats.count

    // (a) witness length > boat count
    if witness.count <= boatCount { return .rejected(.a) }

    // (c) at least two boats appear three or more times in the witness
    var perBoat: [Int: Int] = [:]
    for id in witness { perBoat[id, default: 0] += 1 }
    if perBoat.values.filter({ $0 >= 3 }).count < 2 { return .rejected(.c) }

    // (b) over gateRolloutCount randomised greedy rollouts, the MEDIAN result is
    //     >= gateRolloutRatio x the witness length, or fails to clear.
    //     Stated as a ratio so it does not get easier to satisfy as par grows.
    var results: [Int] = []
    results.reserveCapacity(gateRolloutCount)
    var best = Int.max
    let moveCap = 12 * max(1, boatCount)
    for i in 0..<gateRolloutCount {
        if let moves = forgeRolloutB(start: start,                       // CALL SITE (Task 1)
                                     seed: gateRolloutSeed(start, i),
                                     moveCap: moveCap) {
            results.append(moves)
            if moves < best { best = moves }
        } else {
            results.append(Int.max)     // did not clear — sorts above every finite result
        }
    }
    results.sort()
    let median = results[gateRolloutCount / 2]
    if median != Int.max && Double(median) < gateRolloutRatio * Double(witness.count) {
        return .rejected(.b)
    }

    // (d) removing any single mechanic present on the board must change the
    //     witness length or make the board unsolvable.
    for variant in gateVariants(of: start) {
        if let re = gateSearch(variant.board) {
            if re.count == witness.count { return .rejected(.d) }
        } else {
            // Unsolvable OR node-capped — indistinguishable, so it counts as
            // "changed" and is tallied separately rather than hidden.
            report.dVariantCapped += 1
        }
    }

    return .accepted(GateResult(witness: witness, greedyBest: best == Int.max ? nil : best))
}

/// Try salts for one (chapter, level) until a board passes all four clauses.
/// The salt derivation is HJGenerator.swift:37 verbatim, so passing maxSalts: 1
/// makes HJGenerator.level consume exactly the salt chosen here.
func gateBakeOne(baseSeed: UInt64, config: HJLevelConfig, report: inout GateReport) -> HJLevelRecord? {
    for salt in 0..<gateMaxSalts {
        let seed = baseSeed &+ UInt64(salt) &* 0x2545F4914F6CDD1D
        report.boardsTried += 1
        guard let candidate = HJGenerator.level(seed: seed, config: config, maxSalts: 1) else {
            report.constructionFailures += 1
            continue
        }
        switch gateEvaluate(start: candidate.start, report: &report) {
        case .unsearchable:
            report.unsearchable += 1
        case .rejected(let clause):
            report.rejections[clause.rawValue] += 1
        case .accepted(let r):
            report.accepted += 1
            report.witnessLengths.append(r.witness.count)
            report.boatCounts.append(candidate.start.boats.count)
            if let b = r.greedyBest, b <= r.witness.count { report.greedyThreeStars += 1 }
            return HJLevelRecord(par: r.witness.count, witness: r.witness, start: candidate.start)
        }
    }
    return nil
}
SWIFT
echo "PASS: Gate.swift part 2 written ($(wc -l < tools/HarborForge/Gate.swift) lines)"
```

- [ ] **Step 4: Append the bake driver, the self-check, and the YIELD.md writer.**

`gateFinish` always writes YIELD.md — including on the failure path — so a bake that cannot fill the corpus still leaves the numbers behind rather than a bare non-zero exit.

```bash
cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam" && cat >> tools/HarborForge/Gate.swift <<'SWIFT'

// MARK: - The bake

func gateRepoRoot() -> String {
    let cwd = FileManager.default.currentDirectoryPath
    if !FileManager.default.fileExists(atPath: cwd + "/Harbor Jam/HJModels.swift") {
        print("FAIL: run the harness from the repo root (no 'Harbor Jam/HJModels.swift' under \(cwd))")
        exit(1)
    }
    return cwd
}

func forgeBake(smoke: Bool) {
    let root = gateRepoRoot()
    let t0 = Date()
    var report = GateReport()

    let chapterCount = smoke ? 1 : HJCatalog.chapters.count
    let levelCount   = smoke ? 3 : HJCatalog.levelsPerChapter
    let dailyCount   = smoke ? 4 : gateDailyCount

    var campaign: [String: HJLevelRecord] = [:]
    for chapter in 0..<chapterCount {
        for level in 0..<levelCount {
            let cfg  = HJCatalog.config(chapter: chapter, level: level)
            let base = HJCatalog.seed(chapter: chapter, level: level)
            guard let rec = gateBakeOne(baseSeed: base, config: cfg, report: &report) else {
                gateFinish(root: root, smoke: smoke, report: report,
                           campaign: campaign, daily: [], t0: t0,
                           failure: "no board passed all four clauses for campaign \(chapter)-\(level) in \(gateMaxSalts) salts")
            }
            campaign["\(chapter)-\(level)"] = rec
            gateProgress("campaign \(chapter)-\(level)  par \(rec.par)  boats \(rec.start.boats.count)  tried \(report.boardsTried)")
        }
    }

    var daily: [HJLevelRecord] = []
    for i in 0..<dailyCount {
        // Same shape as HJCatalog.dailyFallbackSeeds (HJModels.swift:143-145), widened to the pool size.
        let base = UInt64(0xDA_11) &* 0x9E3779B97F4A7C15 &+ UInt64(i) &* 6151 &+ 3
        guard let rec = gateBakeOne(baseSeed: base, config: HJCatalog.dailyConfig, report: &report) else {
            gateFinish(root: root, smoke: smoke, report: report,
                       campaign: campaign, daily: daily, t0: t0,
                       failure: "no board passed all four clauses for daily \(i) in \(gateMaxSalts) salts")
        }
        daily.append(rec)
        gateProgress("daily \(i)  par \(rec.par)  boats \(rec.start.boats.count)  tried \(report.boardsTried)")
    }

    gateFinish(root: root, smoke: smoke, report: report,
               campaign: campaign, daily: daily, t0: t0, failure: nil)
}

/// Re-read the emitted file and replay every witness through the shipped engine,
/// exactly as the app will (spec 6, bullet 5). Any deviation is a hard failure.
func gateSelfCheck(path: String) -> String {
    guard let data = FileManager.default.contents(atPath: path),
          let file = try? JSONDecoder().decode(HJLevelTableFile.self, from: data) else {
        print("FAIL: emitted \(path) does not decode as HJLevelTableFile")
        exit(1)
    }
    var records: [(String, HJLevelRecord)] = file.campaign.map { ($0.key, $0.value) }
    for (i, r) in file.daily.enumerated() { records.append(("daily-\(i)", r)) }
    for (name, rec) in records {
        var state = rec.start
        var moves = 0
        for id in rec.witness {
            if HJEngine.tap(boatID: id, state: &state) == .invalid {
                print("FAIL: witness for \(name) produced .invalid on boat \(id) at move \(moves)")
                exit(1)
            }
            moves += 1
        }
        if !state.isCleared {
            print("FAIL: witness for \(name) did not clear the board")
            exit(1)
        }
        if moves != rec.par {
            print("FAIL: witness for \(name) is \(moves) moves but par is \(rec.par)")
            exit(1)
        }
    }
    return "PASS — \(records.count) boards replayed through the shipped engine"
}

func gateFinish(root: String, smoke: Bool, report: GateReport,
                campaign: [String: HJLevelRecord], daily: [HJLevelRecord],
                t0: Date, failure: String?) -> Never {
    let wall = Date().timeIntervalSince(t0)
    let jsonPath  = smoke ? root + "/build/levels.smoke.json" : root + "/Harbor Jam/levels.json"
    let yieldPath = smoke ? root + "/build/YIELD.smoke.md"    : root + "/tools/HarborForge/YIELD.md"

    var selfCheck = "not run (bake did not complete)"
    if failure == nil {
        let file = HJLevelTableFile(version: gateTableVersion, campaign: campaign, daily: daily)
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        guard let data = try? enc.encode(file) else {
            print("FAIL: could not encode the level table")
            exit(1)
        }
        try? FileManager.default.createDirectory(
            atPath: (jsonPath as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true)
        do { try data.write(to: URL(fileURLWithPath: jsonPath)) }
        catch { print("FAIL: could not write \(jsonPath): \(error)"); exit(1) }
        selfCheck = gateSelfCheck(path: jsonPath)
    }

    let acc = max(1, report.accepted)
    let perAcceptance = Double(report.boardsTried) / Double(acc)
    let rate = Double(report.greedyThreeStars) / Double(acc)
    let ratios = zip(report.witnessLengths, report.boatCounts).map { Double($0) / Double(max(1, $1)) }
    let medianRatio = gateMedian(ratios)

    let verdict: String
    let code: Int32
    if let f = failure {
        verdict = "NO-GO — the bake did not complete: " + f
        code = 2
    } else if rate < gateGreedyLimit {
        verdict = "GO"
        code = 0
    } else {
        verdict = "NO-GO — the greedy three-star rate is not below the limit"
        code = 3
    }

    func pct(_ n: Int) -> String {
        let d = max(1, report.boardsTried)
        return String(format: "%.2f", 100.0 * Double(n) / Double(d)) + "%"
    }

    let doc = """
    # Harbor Jam — acceptance yield (Task 7 checkpoint)

    Generated by `tools/HarborForge` subcommand `bake`. Every number below is measured,
    not estimated. Smoke run: \(smoke ? "YES — partial corpus, NOT a verdict" : "no").

    ## Verdict

    **\(verdict)**

    ## Corpus

    | | |
    |---|---|
    | Campaign boards accepted | \(campaign.count) (spec 6 requires 140) |
    | Daily boards accepted | \(daily.count) (spec 6 requires 400) |
    | Witness replay self-check | \(selfCheck) |
    | Level table | \(jsonPath) |

    ## Yield

    | | |
    |---|---|
    | Boards constructed and evaluated | \(report.boardsTried) |
    | Boards accepted | \(report.accepted) |
    | **Boards tried per acceptance** | **\(String(format: "%.1f", perAcceptance))** |
    | Wall clock | \(String(format: "%.1f", wall)) s (\(String(format: "%.2f", wall / 3600.0)) h) |

    ## Rejections

    | Reason | Boards | Share of tried |
    |---|---|---|
    | construction returned nil | \(report.constructionFailures) | \(pct(report.constructionFailures)) |
    | no witness inside the caps | \(report.unsearchable) | \(pct(report.unsearchable)) |
    | \(GateClause.a.label) | \(report.rejections[0]) | \(pct(report.rejections[0])) |
    | \(GateClause.b.label) | \(report.rejections[1]) | \(pct(report.rejections[1])) |
    | \(GateClause.c.label) | \(report.rejections[2]) | \(pct(report.rejections[2])) |
    | \(GateClause.d.label) | \(report.rejections[3]) | \(pct(report.rejections[3])) |

    Clause (d) variant searches that hit the node cap instead of proving
    unsolvability: \(report.dVariantCapped). Those were counted as "changed", so
    clause (d) is that many decisions weaker than it looks.

    ## The checkpoint number

    | | |
    |---|---|
    | Greedy three-star boards | \(report.greedyThreeStars) of \(report.accepted) |
    | **Greedy three-star rate** | **\(String(format: "%.2f", rate * 100.0))%** (limit: below \(String(format: "%.0f", gateGreedyLimit * 100.0))%) |
    | Median witness / boat count | \(String(format: "%.2f", medianRatio))x (spec 6 requires 1.60x) |

    A board counts as a greedy three-star if ANY of its \(gateRolloutCount) clause-(b)
    rollouts cleared it in par moves or fewer. That is the strictest reading of the
    zero-thought policy and the direct successor of the 96.63% measured in spec 1.

    ## STOP RULE

    If the greedy three-star rate is not below \(String(format: "%.0f", gateGreedyLimit * 100.0))%, or either corpus is short,
    **work STOPS here**. No further app change lands. Parameters are retuned and the
    FULL bake is re-run — never mix boards from two parameter sets in one levels.json.

    Retuning levers, in order (each one, then re-bake, then re-read this file):

    1. Bias the throttle draw toward 1 and 3 in `Harbor Jam/HJGenerator.swift`:
       replace `throttle: 1 + rng.int(3)` with `throttle: [1, 1, 1, 3, 3, 3, 2][rng.int(7)]`.
       Mixed extremes are what make one boat overshoot the lane another one needs.
    2. Raise `basinCount` by 1 in every `HJLevelConfig` literal in `Harbor Jam/HJModels.swift`.
       Basins are the only cycle in the move graph; more of them is more lookahead.
    3. Raise the clause-(b) ratio in `tools/HarborForge/Gate.swift`:
       `let gateRolloutRatio    = 1.25` becomes `let gateRolloutRatio    = 1.40`.
       This does not make boards harder, it makes the gate stricter — costs yield.
    4. Lower `boatCount` by 1 in every `HJLevelConfig` literal in `Harbor Jam/HJModels.swift`
       (floor 3). Per spec 2.9 more boats means more simultaneously-correct moves; fewer
       boats is a difficulty increase, not a decrease.

    Levers 1, 2 and 4 change board generation, so the whole corpus changes. Lever 3
    changes only acceptance. Exact, assert-guarded commands for all four are in the
    plan, Task 7 Step 8.
    """

    try? FileManager.default.createDirectory(
        atPath: (yieldPath as NSString).deletingLastPathComponent,
        withIntermediateDirectories: true)
    try? doc.write(toFile: yieldPath, atomically: true, encoding: .utf8)

    print(doc)
    print("")
    print("wrote \(yieldPath)")
    print(code == 0 ? "PASS: VERDICT GO" : "FAIL: VERDICT NO-GO (exit \(code))")
    exit(code)
}
SWIFT
echo "PASS: Gate.swift complete ($(wc -l < tools/HarborForge/Gate.swift) lines)"
```

- [ ] **Step 5: Insert the `bake` subcommand into `tools/HarborForge/main.swift`.**

One insertion, immediately above the switch's single bare `default:` line. The script refuses to run if there is not exactly one, or if a `bake` case already exists.

```bash
cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam" && python3 - <<'PY'
import io, sys
p = "tools/HarborForge/main.swift"
src = io.open(p, encoding="utf-8").read()
if 'case "bake"' in src:
    print("FAIL: main.swift already has a bake case"); sys.exit(1)
lines = src.split("\n")
hits = [i for i, l in enumerate(lines) if l.strip() == "default:"]
if len(hits) != 1:
    print("FAIL: expected exactly one bare 'default:' line in %s, found %d" % (p, len(hits)))
    sys.exit(1)
i = hits[0]
indent = lines[i][:len(lines[i]) - len(lines[i].lstrip())]
lines[i:i] = [indent + 'case "bake":',
              indent + '    forgeBake(smoke: CommandLine.arguments.contains("--smoke"))']
io.open(p, "w", encoding="utf-8").write("\n".join(lines))
print("PASS: bake subcommand inserted at %s:%d" % (p, i + 1))
PY
sed -n '1,200p' tools/HarborForge/main.swift | grep -n -B4 -A4 'case "bake"'
```

- [ ] **Step 6: Build the harness and smoke-run the bake on three campaign boards and four dailies.**

`build/` is gitignored (`.gitignore:2`), so the binary and the smoke artifacts never enter git. The smoke run writes `build/levels.smoke.json` and `build/YIELD.smoke.md` and does not touch `Harbor Jam/levels.json` or `tools/HarborForge/YIELD.md` — a partial run must never be mistaken for the verdict.

```bash
cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam" && mkdir -p build && \
xcrun swiftc -O -swift-version 5 \
  -sdk "$(xcrun --show-sdk-path --sdk macosx)" \
  -o build/harborforge \
  "Harbor Jam/HJModels.swift" "Harbor Jam/HJEngine.swift" "Harbor Jam/HJGenerator.swift" \
  tools/HarborForge/*.swift \
&& echo "PASS: harness built" \
&& ./build/harborforge bake --smoke ; echo "exit=$?"
```

The assertion: the command prints `PASS: harness built`, then the smoke bake ends in either `PASS: VERDICT GO` with `exit=0` or `FAIL: VERDICT NO-GO` with `exit=3`. Any other exit code is a defect in this task, not a checkpoint result:

- `exit=1` — the harness was not run from the repo root, or the emitted JSON failed to decode or a witness failed to replay. Fix before continuing.
- `exit=2` — three campaign boards could not be filled in `gateMaxSalts` salts. That is a real yield signal; go to Step 8 now rather than spending hours on the full bake.

- [ ] **Step 7: Run the full bake. THIS IS THE CHECKPOINT.**

140 campaign boards (7 chapters x 20, `HJModels.swift:91-101`) and 400 dailies, each one a breadth-first search plus up to five more for clause (d). Run it detached with a wall-clock record; progress goes to stderr, one line per accepted board.

```bash
cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam" && \
( time ./build/harborforge bake ) > build/bake.stdout.log 2> build/bake.stderr.log ; \
echo "exit=$?" ; tail -5 build/bake.stderr.log
```

Then read the verdict:

```bash
cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam" && \
cat tools/HarborForge/YIELD.md && \
echo "--- levels.json ---" && ls -l "Harbor Jam/levels.json" && \
python3 -c "
import json, io
f = json.load(io.open('Harbor Jam/levels.json', encoding='utf-8'))
print('version', f['version'], 'campaign', len(f['campaign']), 'daily', len(f['daily']))
assert len(f['campaign']) == 140, 'FAIL: campaign is not 140 boards'
assert len(f['daily']) == 400, 'FAIL: daily pool is not 400 boards'
assert all('tugTokens' not in r['start'] for r in f['daily']), 'FAIL: tugTokens leaked into the wire format'
print('PASS: corpus shape')
"
```

The assertions that must hold: `exit=0`, `PASS: corpus shape`, and in `YIELD.md` a **Verdict** of `GO`, a greedy three-star rate below 15%, and a median witness/boat-count ratio at or above 1.60x (spec §6).

- [ ] **Step 8: The go/no-go decision.**

**If the verdict is GO** — skip to Step 9.

**If the verdict is NO-GO — work STOPS.** Do not proceed to Step 9, do not commit `levels.json`, and land no further app change. Apply the levers in order, one at a time, re-running Step 6 (build) and Step 7 (full bake) after each. Never merge boards from two parameter sets into one `levels.json`.

Lever 1 — bias the throttle draw toward 1 and 3:

```bash
cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam" && python3 - <<'PY'
import io, sys
p = "Harbor Jam/HJGenerator.swift"
s = io.open(p, encoding="utf-8").read()
old, new = "throttle: 1 + rng.int(3)", "throttle: [1, 1, 1, 3, 3, 3, 2][rng.int(7)]"
n = s.count(old)
if n != 1:
    print("FAIL: found %d occurrences of %r in %s" % (n, old, p)); sys.exit(1)
io.open(p, "w", encoding="utf-8").write(s.replace(old, new, 1))
print("PASS: throttle draw is now 3/7 ones, 3/7 threes, 1/7 twos")
PY
```

Lever 2 — raise `basinCount` by 1 in every config literal:

```bash
cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam" && python3 - <<'PY'
import io, re, sys
p = "Harbor Jam/HJModels.swift"
s = io.open(p, encoding="utf-8").read()
hits = re.findall(r"basinCount: (\d+)", s)
if not hits:
    print("FAIL: no 'basinCount: <int>' literal in %s" % p); sys.exit(1)
s = re.sub(r"basinCount: (\d+)", lambda m: "basinCount: %d" % (int(m.group(1)) + 1), s)
io.open(p, "w", encoding="utf-8").write(s)
print("PASS: bumped %d basinCount literals %s -> %s"
      % (len(hits), hits, [str(int(h) + 1) for h in hits]))
PY
```

Lever 3 — raise the clause-(b) ratio:

```bash
cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam" && python3 - <<'PY'
import io, sys
p = "tools/HarborForge/Gate.swift"
s = io.open(p, encoding="utf-8").read()
old, new = "let gateRolloutRatio    = 1.25", "let gateRolloutRatio    = 1.40"
if s.count(old) != 1:
    print("FAIL: gateRolloutRatio line not found verbatim in %s" % p); sys.exit(1)
io.open(p, "w", encoding="utf-8").write(s.replace(old, new, 1))
print("PASS: clause (b) ratio raised to 1.40")
PY
```

Lever 4 — lower `boatCount` by 1 everywhere (floor 3):

```bash
cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam" && python3 - <<'PY'
import io, re, sys
p = "Harbor Jam/HJModels.swift"
s = io.open(p, encoding="utf-8").read()
def ramp(m):
    return "boatCount: ramp(%d, %d)" % (max(3, int(m.group(1)) - 1), max(3, int(m.group(2)) - 1))
s, n1 = re.subn(r"boatCount: ramp\((\d+), (\d+)\)", ramp, s)
s, n2 = re.subn(r"boatCount: (\d+)", lambda m: "boatCount: %d" % max(3, int(m.group(1)) - 1), s)
if n1 + n2 == 0:
    print("FAIL: no boatCount literal in %s" % p); sys.exit(1)
io.open(p, "w", encoding="utf-8").write(s)
print("PASS: lowered %d ramp() and %d literal boat counts by 1 (floor 3)" % (n1, n2))
PY
```

- [ ] **Step 9: Register `levels.json` in the pbxproj — four insertions, centrally assigned ids.**

The project has no synchronized groups (spec §5 risk 3): a resource that is not registered in all four places silently does not ship. Ids `C0DEFA000000000000000101` / `C0DEFA000000000000000102` belong to this task alone. Every anchor below was verified unique in the current file.

```bash
cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam" && python3 - <<'PY'
import io, sys
p = "Harbor Jam.xcodeproj/project.pbxproj"
s = io.open(p, encoding="utf-8").read()
if "C0DEFA000000000000000101" in s:
    print("FAIL: levels.json is already registered in the pbxproj"); sys.exit(1)
edits = [
  ("/* Begin PBXBuildFile section */\n",
   "/* Begin PBXBuildFile section */\n"
   "\t\tC0DEFA000000000000000102 /* levels.json in Resources */ = "
   "{isa = PBXBuildFile; fileRef = C0DEFA000000000000000101 /* levels.json */; };\n"),
  ("/* Begin PBXFileReference section */\n",
   "/* Begin PBXFileReference section */\n"
   "\t\tC0DEFA000000000000000101 /* levels.json */ = "
   "{isa = PBXFileReference; lastKnownFileType = text.json; path = levels.json; sourceTree = \"<group>\"; };\n"),
  ("\t\t\t\tED7ABB41533F46E128EC3724 /* HJTheme.swift */,\n",
   "\t\t\t\tED7ABB41533F46E128EC3724 /* HJTheme.swift */,\n"
   "\t\t\t\tC0DEFA000000000000000101 /* levels.json */,\n"),
  ("\t\t\t\t379ED52CC4E8AA0A381B3FB1 /* Assets.xcassets in Resources */,\n",
   "\t\t\t\t379ED52CC4E8AA0A381B3FB1 /* Assets.xcassets in Resources */,\n"
   "\t\t\t\tC0DEFA000000000000000102 /* levels.json in Resources */,\n"),
]
for anchor, repl in edits:
    n = s.count(anchor)
    if n != 1:
        print("FAIL: anchor occurs %d times (want 1): %r" % (n, anchor[:64])); sys.exit(1)
    s = s.replace(anchor, repl, 1)
io.open(p, "w", encoding="utf-8").write(s)
print("PASS: levels.json registered in 4 places (PBXBuildFile, PBXFileReference, group E8C6ADF1..., Resources phase F1154...)")
PY
plutil -lint "Harbor Jam.xcodeproj/project.pbxproj"
```

Assertion: `PASS: levels.json registered in 4 places` followed by `project.pbxproj: OK`.

- [ ] **Step 10: Prove the app still builds and that `levels.json` lands inside the bundle.**

Nothing in the app reads the table yet — that is a later task. This step only proves the resource is wired and Debug + Release still compile clean.

```bash
cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam" && \
for CFG in Debug Release; do
  xcodebuild -project "Harbor Jam.xcodeproj" -scheme "Harbor Jam" -configuration "$CFG" \
    -destination 'platform=iOS Simulator,name=iPhone 17' \
    -derivedDataPath build/dd-gate build 2>&1 | tail -3
done
APP=$(find build/dd-gate -name "Harbor Jam.app" -type d | head -1) && \
test -f "$APP/levels.json" && echo "PASS: levels.json is inside $APP" || echo "FAIL: levels.json missing from the bundle"
```

Assertion: `** BUILD SUCCEEDED **` twice, then `PASS: levels.json is inside ...`.

- [ ] **Step 11: Commit the checkpoint.**

Run only after Step 7 reported `VERDICT GO` and Step 10 printed both `BUILD SUCCEEDED` and the bundle PASS.

```bash
cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam" && \
git add tools/HarborForge/Gate.swift tools/HarborForge/main.swift tools/HarborForge/YIELD.md \
        "Harbor Jam/levels.json" "Harbor Jam.xcodeproj/project.pbxproj" && \
git status --short && \
git commit -m "$(cat <<'MSG'
Forge: four-clause acceptance gate, bake the level corpus, checkpoint GO

Implements spec 2.5 verbatim: (a) witness longer than the boat count,
(b) median of 200 greedy rollouts at or above 1.25x the witness as a ratio,
(c) two or more boats tapped three or more times, (d) removing any mechanic
present on the board changes the witness length or makes it unsolvable.

Bakes 140 campaign boards and a 400-board daily pool into Harbor Jam/levels.json
and registers it in the hand-authored pbxproj Resources phase. Every witness is
searched against the engine frozen at Task 4 and replayed back through it before
the file is accepted. Measured yield, per-clause rejections, wall clock and the
greedy three-star rate are in tools/HarborForge/YIELD.md.

Co-Authored-By: Claude <noreply@anthropic.com>
MSG
)"
```


---

### Task 8: The app loads the baked table; on-device generation is deleted

`HJGenerator` is the last piece of the old design still shipping. It reverse-constructs boards at runtime (`Harbor Jam/HJGenerator.swift:73-171`), stamps `par: total, solutionOrder: Array(0..<total)` (`:170`), and re-rolls up to 120 salts per level (`:35-44`) until a canonical-order replay clears the board. Everything it asserts is now false: par is a witnessed line, not the boat count, and the corpus was baked offline in an earlier task. This task replaces it with a bundle read plus a real-engine replay, and deletes the file.

It also removes a live performance hazard. `HJHarborView.gameDestination` (`Harbor Jam/HJHarborView.swift:170-183`) builds `HJGameView` — and therefore `HJGameViewModel.init` — **inside** a `NavigationLink(destination:)`. On iOS 15 those destinations are constructed eagerly, so opening a chapter grid today runs the 120-salt generator synchronously for every unlocked cell on screen. After this task the same eager construction is a dictionary lookup plus one cached witness replay, which is why the verified cache below must also cache *failures*.

**Files:**
- `Harbor Jam/HJLevelTable.swift` — new
- `Harbor Jam/HJGenerator.swift` — deleted
- `Harbor Jam/HJGameViewModel.swift` — edited (`:29-44`)
- `Harbor Jam.xcodeproj/project.pbxproj` — edited (remove 4 lines, add 4 lines)
- `tools/HarborForge/build.sh` — edited
- `tools/HarborForge/Audit.swift` — deleted
- `tools/HarborForge/HJForgeRandom.swift` — new, only if the harness does not already declare `HJRandom`

**Interfaces:**

*Consumes* (all from lower-numbered tasks):
- `HJEngine.tap(boatID: Int, state: inout HJBoardState) -> HJTapOutcome` — Task 4. The engine is final; this task does not touch it.
- `enum HJTapOutcome: Equatable` with case `.invalid` — Task 4.
- `HJBoardState` (`Codable`, with `basins: [HJCell]`, without `tugTokens`) and its `isCleared` — Tasks 2-4.
- `Harbor Jam/levels.json`, already baked **and already registered** in the Resources build phase as fileRef `C0DEFA000000000000000101` / buildFile `C0DEFA000000000000000102` — Task 7. This task does not touch those ids.
- The save layer's per-level type is named `HJProgressRecord` (frozen contract), which is what frees the name `HJLevelRecord` for the baked-table row below.

*Produces* (all in `Harbor Jam/HJLevelTable.swift`):
```
struct HJLevelRecord: Codable { var par: Int; var witness: [Int]; var start: HJBoardState }
struct HJLevelTableFile: Codable { var version: Int; var campaign: [String: HJLevelRecord]; var daily: [HJLevelRecord] }
struct HJGeneratedLevel { var start: HJBoardState; var par: Int; var solutionOrder: [Int] }
enum HJLevelTable {
    static func campaignLevel(chapter: Int, level: Int) -> HJGeneratedLevel?
    static func dailyLevel(dayKey: Int) -> HJGeneratedLevel?
}
```
`HJGeneratedLevel` keeps the exact shape it has today at `HJGenerator.swift:25-29`, so `HJGameViewModel.init` needs only its call sites repointed.

*Removed:* `HJGenerator`, `HJRandom` and `HJGeneratedLevel`'s old home — the whole of `Harbor Jam/HJGenerator.swift`.

---

- [ ] **Step 1: Confirm the preconditions this task is built on.**

  All four assertions must pass before anything is edited. If any FAILs, stop — an earlier task has not landed.

  ```bash
  cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam"
  ok=0
  test -f "Harbor Jam/levels.json" && echo "PASS levels.json exists" || { echo "FAIL levels.json missing (Task 7)"; ok=1; }
  test "$(grep -c 'levels.json' 'Harbor Jam.xcodeproj/project.pbxproj')" = "4" \
    && echo "PASS levels.json registered in 4 places" \
    || { echo "FAIL levels.json not registered in the pbxproj (Task 7)"; ok=1; }
  grep -rq "HJLevelRecord" "Harbor Jam" --include="*.swift" \
    && { echo "FAIL HJLevelRecord still declared in app sources; the save rename to HJProgressRecord has not landed"; ok=1; } \
    || echo "PASS HJLevelRecord name is free"
  test -f "tools/HarborForge/build.sh" && echo "PASS harness present" || { echo "FAIL tools/HarborForge/build.sh missing (Task 1)"; ok=1; }
  exit $ok
  ```

- [ ] **Step 2: Write `Harbor Jam/HJLevelTable.swift`.**

  The witness replay is the same referee the old generator used at `HJGenerator.swift:196-199` — the real engine, not a model of it. The one rule change: a witness tap is rejected only when it is `.invalid` (a boat id not on the board). Under the Task 4 engine a `.blocked` tap still runs `tickWorld`, so it is a legal *wait* move (spec §2.2) and a witness may legitimately contain one.

  ```swift
  import Foundation

  /// One baked board: the start state, its proven par, and the witness line that
  /// proves it. Decoded from `levels.json` — never generated on device.
  struct HJLevelRecord: Codable {
      var par: Int
      var witness: [Int]          // boat ids in tap order; length == par
      var start: HJBoardState
  }

  /// Root object of `levels.json`.
  struct HJLevelTableFile: Codable {
      var version: Int
      var campaign: [String: HJLevelRecord]   // key: "chapter-level"
      var daily: [HJLevelRecord]
  }

  /// A level handed to the view model. Same shape the app has always used.
  struct HJGeneratedLevel {
      var start: HJBoardState
      var par: Int
      var solutionOrder: [Int]
  }

  /// Reads the offline-baked corpus. The device never searches: it replays each
  /// record's witness through the shipped `HJEngine` once, the first time that
  /// record is asked for, and withholds any record whose line does not clear.
  enum HJLevelTable {

      // MARK: - Bundle load (exactly once)

      /// Lazy `static let` — Swift guarantees a single initialisation, so the
      /// JSON is parsed on first access and never again.
      private static let file: HJLevelTableFile? = {
          guard let url = Bundle.main.url(forResource: "levels", withExtension: "json"),
                let data = try? Data(contentsOf: url),
                let decoded = try? JSONDecoder().decode(HJLevelTableFile.self, from: data)
          else { return nil }
          return decoded
      }()

      // MARK: - Verified cache

      /// Records already replayed. A cached `nil` means the witness failed and the
      /// level is withheld. Failures are cached too: `HJHarborView.gameDestination`
      /// is inside a `NavigationLink` destination, which iOS 15 builds eagerly for
      /// every visible cell, so an uncached rejection would re-replay on every
      /// body evaluation. Touched only from the main thread (view construction).
      private static var verified: [String: HJGeneratedLevel?] = [:]

      static func campaignLevel(chapter: Int, level: Int) -> HJGeneratedLevel? {
          let key = "\(chapter)-\(level)"
          if let cached = verified[key] { return cached }
          var result: HJGeneratedLevel? = nil
          if let f = file, let record = f.campaign[key] {
              result = accept(record)
          }
          verified[key] = result
          return result
      }

      static func dailyLevel(dayKey: Int) -> HJGeneratedLevel? {
          guard let pool = file?.daily, !pool.isEmpty else { return nil }
          // dayKey modulo the pool count, trap-free for a negative dayKey.
          let idx = ((dayKey % pool.count) + pool.count) % pool.count
          let key = "daily-\(idx)"
          if let cached = verified[key] { return cached }
          let result = accept(pool[idx])
          verified[key] = result
          return result
      }

      // MARK: - Integrity check (real-engine witness replay)

      /// Replays the baked witness through the engine that actually ships, exactly
      /// as the retired generator's `verify()` did. A `.blocked` tap is a legal wait
      /// under the current engine, so only `.invalid` — a boat that is not on the
      /// board — rejects the line, along with a board that does not end cleared.
      private static func accept(_ record: HJLevelRecord) -> HJGeneratedLevel? {
          guard record.par == record.witness.count else { return nil }
          var state = record.start
          guard !state.isCleared else { return nil }
          for id in record.witness {
              if HJEngine.tap(boatID: id, state: &state) == .invalid { return nil }
          }
          guard state.isCleared else { return nil }
          return HJGeneratedLevel(start: record.start,
                                  par: record.par,
                                  solutionOrder: record.witness)
      }
  }
  ```

- [ ] **Step 3: Repoint `HJGameViewModel.init` at the table.**

  Two call sites, `Harbor Jam/HJGameViewModel.swift:34` and `:36`. Both substrings are unique in the file, so this survives whatever the earlier scoring tasks did to the surrounding lines.

  ```bash
  cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam"
  sed -i '' \
    -e 's/HJGenerator\.campaignLevel(chapter: chapter, level: level)/HJLevelTable.campaignLevel(chapter: chapter, level: level)/' \
    -e 's/HJGenerator\.dailyLevel(dayKey: dayKey)/HJLevelTable.dailyLevel(dayKey: dayKey)/' \
    "Harbor Jam/HJGameViewModel.swift"
  grep -n "HJLevelTable\.\|HJGenerator" "Harbor Jam/HJGameViewModel.swift"
  ```

  Assertion — the grep must print exactly two lines, both `HJLevelTable.`, and no `HJGenerator`:

  ```bash
  cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam"
  test "$(grep -c 'HJLevelTable\.' 'Harbor Jam/HJGameViewModel.swift')" = "2" \
    && ! grep -q 'HJGenerator' "Harbor Jam/HJGameViewModel.swift" \
    && echo "PASS view model repointed" || { echo "FAIL view model not repointed"; exit 1; }
  ```

  `let generated: HJGeneratedLevel?` at `:31` needs no edit — `HJGeneratedLevel` is now declared in `HJLevelTable.swift` with the identical shape.

- [ ] **Step 4: Preserve the two offline-only survivors before deleting the generator.**

  Spec §3 keeps `HJRandom` (`HJGenerator.swift:4-23`) and `exitCorridor` (`:173-185`) — but *offline*, in the harness. The harness built its own generator in an earlier task, so this step is almost certainly a no-op; run it so the deletion cannot strand the harness. The copy is verbatim from the file being deleted, minus everything that depends on the retired `HJLevelConfig.tugTokens`.

  ```bash
  cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam"
  if grep -rq "struct HJRandom" tools/HarborForge; then
    echo "OK: the harness already declares HJRandom; nothing to preserve"
  else
    cat > tools/HarborForge/HJForgeRandom.swift <<'SWIFT'
  import Foundation

  /// Deterministic SplitMix64 RNG — identical sequences across launches for a given seed.
  /// Moved out of the app (retired HJGenerator.swift:4-23); offline-only from now on.
  struct HJRandom {
      private var state: UInt64
      init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
      mutating func next() -> UInt64 {
          state = state &+ 0x9E3779B97F4A7C15
          var z = state
          z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
          z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
          return z ^ (z >> 31)
      }
      mutating func int(_ upper: Int) -> Int {
          guard upper > 0 else { return 0 }
          return Int(next() % UInt64(upper))
      }
      mutating func bool() -> Bool { next() % 2 == 0 }
      mutating func pick<T>(_ array: [T]) -> T? {
          guard !array.isEmpty else { return nil }
          return array[int(array.count)]
      }
  }

  /// Straight-ahead corridor from a boat's bow to the board edge
  /// (retired HJGenerator.swift:173-185, hoisted to a free function).
  func hjExitCorridor(for boat: HJBoat, gridW: Int, gridH: Int) -> Set<HJCell> {
      var out = Set<HJCell>()
      var probe = boat
      while true {
          probe.x += boat.bow.dx
          probe.y += boat.bow.dy
          let inside = probe.cells.filter { $0.x >= 0 && $0.x < gridW && $0.y >= 0 && $0.y < gridH }
          if inside.isEmpty { break }
          out.formUnion(inside)
          if out.count > gridW * gridH { break }
      }
      return out
  }
  SWIFT
    echo "COPIED: HJRandom + exit corridor preserved in tools/HarborForge/HJForgeRandom.swift"
  fi
  ```

- [ ] **Step 5: Delete `Harbor Jam/HJGenerator.swift` and its four pbxproj lines.**

  Every pbxproj line mentioning `HJGenerator` is one of the four registration lines and nothing else, verified: fileRef `91C06264659DAF17535770D6` at line 42, buildFile `6B3A96B9915A1D32A2B4AEF1` at line 20, the group child at line 84, the Sources-phase entry at line 174. Deleting every line containing the token is therefore exact.

  ```bash
  cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam"
  test "$(grep -c 'HJGenerator' 'Harbor Jam.xcodeproj/project.pbxproj')" = "4" \
    || { echo "FAIL expected exactly 4 HJGenerator lines in the pbxproj"; exit 1; }
  grep -n "HJGenerator" "Harbor Jam.xcodeproj/project.pbxproj"
  ```

  That grep must print exactly these four (tabs shown as real tabs in the file):

  ```
  20:		6B3A96B9915A1D32A2B4AEF1 /* HJGenerator.swift in Sources */ = {isa = PBXBuildFile; fileRef = 91C06264659DAF17535770D6 /* HJGenerator.swift */; };
  42:		91C06264659DAF17535770D6 /* HJGenerator.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = HJGenerator.swift; sourceTree = "<group>"; };
  84:				91C06264659DAF17535770D6 /* HJGenerator.swift */,
  174:				6B3A96B9915A1D32A2B4AEF1 /* HJGenerator.swift in Sources */,
  ```

  Now remove them and the file:

  ```bash
  cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam"
  sed -i '' '/HJGenerator/d' "Harbor Jam.xcodeproj/project.pbxproj"
  git rm -f "Harbor Jam/HJGenerator.swift"
  test "$(grep -c 'HJGenerator' 'Harbor Jam.xcodeproj/project.pbxproj')" = "0" \
    && ! test -f "Harbor Jam/HJGenerator.swift" \
    && echo "PASS generator removed from the project" || { echo "FAIL generator not fully removed"; exit 1; }
  ```

- [ ] **Step 6: Register `HJLevelTable.swift` in all four pbxproj places.**

  Ids from the plan's central assignment: fileRef `C0DEBF000000000000000201`, buildFile `C0DEBF000000000000000202`. Each anchor below was checked to occur exactly once in the file.

  ```bash
  cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam"
  python3 - <<'PY'
  import pathlib, sys

  p = pathlib.Path("Harbor Jam.xcodeproj/project.pbxproj")
  s = p.read_text()

  edits = [
      # 1. PBXBuildFile section
      ("\t\t03001EE2CCE333ABA05D4257 /* HJTheme.swift in Sources */ = {isa = PBXBuildFile; fileRef = ED7ABB41533F46E128EC3724 /* HJTheme.swift */; };\n",
       "\t\tC0DEBF000000000000000202 /* HJLevelTable.swift in Sources */ = {isa = PBXBuildFile; fileRef = C0DEBF000000000000000201 /* HJLevelTable.swift */; };\n"),
      # 2. PBXFileReference section
      ("\t\tED7ABB41533F46E128EC3724 /* HJTheme.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = HJTheme.swift; sourceTree = \"<group>\"; };\n",
       "\t\tC0DEBF000000000000000201 /* HJLevelTable.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = HJLevelTable.swift; sourceTree = \"<group>\"; };\n"),
      # 3. PBXGroup "Harbor Jam" (E8C6ADF1294695810FC9BE0F) children
      ("\t\t\t\tED7ABB41533F46E128EC3724 /* HJTheme.swift */,\n",
       "\t\t\t\tC0DEBF000000000000000201 /* HJLevelTable.swift */,\n"),
      # 4. PBXSourcesBuildPhase files
      ("\t\t\t\t03001EE2CCE333ABA05D4257 /* HJTheme.swift in Sources */,\n",
       "\t\t\t\tC0DEBF000000000000000202 /* HJLevelTable.swift in Sources */,\n"),
  ]

  for anchor, added in edits:
      if s.count(anchor) != 1:
          print("FAIL anchor not unique:", anchor.strip()); sys.exit(1)
      s = s.replace(anchor, anchor + added)

  p.write_text(s)
  print("PASS HJLevelTable.swift registered in 4 places")
  PY
  test "$(grep -c 'HJLevelTable' 'Harbor Jam.xcodeproj/project.pbxproj')" = "4" \
    && echo "PASS 4 registration lines" || { echo "FAIL wrong registration count"; exit 1; }
  ```

- [ ] **Step 7: Delete `tools/HarborForge/Audit.swift`.**

  Delete, not rewrite. `Audit.swift` measured the pre-throttle baseline against `HJGenerator.campaignLevel` — the numbers it produced are recorded in the spec (§1) and the symbol it calls no longer exists, so a rewrite would be a new tool, not a repair. The measurement that matters from here on is acceptance clause (b) — the randomised "tap anything that advances, prefer anything that exits" rollout — which the corpus baker already runs per board, on the same boards, as a shipping gate.

  ```bash
  cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam"
  git rm -f tools/HarborForge/Audit.swift
  ```

- [ ] **Step 8: Drop `HJGenerator.swift` and `Audit.swift` from `tools/HarborForge/build.sh`.**

  Look at what you are about to change first:

  ```bash
  cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam"
  grep -n "HJGenerator.swift\|Audit.swift" tools/HarborForge/build.sh
  ```

  Then remove both tokens. The script strips each token together with any attached path prefix and quotes, and drops the line entirely when nothing but punctuation is left — so it is correct whether the sources are one array on one line or one entry per continued line.

  ```bash
  cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam"
  python3 - <<'PY'
  import pathlib, re

  p = pathlib.Path("tools/HarborForge/build.sh")
  tokens = ["HJGenerator.swift", "Audit.swift"]
  out = []
  for line in p.read_text().splitlines(True):
      if not any(t in line for t in tokens):
          out.append(line)
          continue
      new = line
      for t in tokens:
          e = re.escape(t)
          new = re.sub(r'"[^"]*' + e + r'"|\S*' + e, '', new)
      new = re.sub(r'[ \t]+', ' ', new)
      if new.strip() in ("", ",", "\\", ", \\"):
          continue
      out.append(new.rstrip() + "\n")
  p.write_text("".join(out))
  print("edited")
  PY
  test "$(grep -c 'HJGenerator\|Audit' tools/HarborForge/build.sh)" = "0" \
    && echo "PASS build.sh no longer names the generator or the audit tool" \
    || { echo "FAIL build.sh still references a deleted source"; exit 1; }
  ```

- [ ] **Step 9: Assert the harness still builds and the app sources are generator-free.**

  ```bash
  cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam"
  if grep -rn "HJGenerator\|HJRandom" "Harbor Jam" --include="*.swift"; then
    echo "FAIL app sources still reference the retired generator"; exit 1
  else
    echo "PASS app sources are generator-free"
  fi
  bash tools/HarborForge/build.sh && echo "PASS harness builds" || { echo "FAIL harness build broken"; exit 1; }
  ```

  `HJCatalog.config`, `HJCatalog.seed`, `HJCatalog.dailyConfig` and `HJCatalog.dailyFallbackSeeds` (`Harbor Jam/HJModels.swift:103-149`) stay in place even though nothing in the app calls them any more — the harness compiles `HJModels.swift` and drives baking from them. Do not tidy them up here.

- [ ] **Step 10: Debug build.**

  ```bash
  cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam"
  xcodebuild -project "Harbor Jam.xcodeproj" -scheme "Harbor Jam" \
    -configuration Debug \
    -destination 'platform=iOS Simulator,name=iPhone 17' \
    build 2>&1 | tail -25
  ```

  Assertion: the output ends in `** BUILD SUCCEEDED **` and the run prints no `warning:` line.

- [ ] **Step 11: Release build.**

  ```bash
  cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam"
  xcodebuild -project "Harbor Jam.xcodeproj" -scheme "Harbor Jam" \
    -configuration Release \
    -destination 'platform=iOS Simulator,name=iPhone 17' \
    build 2>&1 | tail -25
  ```

  Assertion: `** BUILD SUCCEEDED **`, zero warnings. A Release-only failure here means `levels.json` is missing from the Resources phase — re-run Step 1.

- [ ] **Step 12: Assert `levels.json` is actually inside the built app.**

  A resource that is registered but not copied fails silently: every level would return `nil` and every cell would render "Level unavailable".

  ```bash
  cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam"
  APP="$(xcodebuild -project 'Harbor Jam.xcodeproj' -scheme 'Harbor Jam' -configuration Release \
        -destination 'platform=iOS Simulator,name=iPhone 17' -showBuildSettings 2>/dev/null \
        | awk -F' = ' '/ BUILT_PRODUCTS_DIR/ {print $2; exit}')/Harbor Jam.app"
  test -f "$APP/levels.json" \
    && echo "PASS levels.json is in the bundle at $APP/levels.json" \
    || { echo "FAIL levels.json missing from $APP"; exit 1; }
  ```

- [ ] **Step 13: Commit.**

  ```bash
  cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam"
  git add "Harbor Jam/HJLevelTable.swift" \
          "Harbor Jam/HJGameViewModel.swift" \
          "Harbor Jam.xcodeproj/project.pbxproj" \
          tools/HarborForge
  git add -A "Harbor Jam/HJGenerator.swift" tools/HarborForge/Audit.swift
  git commit -m "$(cat <<'EOF'
  Load the baked level table; delete on-device generation

  HJLevelTable reads levels.json from the bundle once, decodes HJLevelTableFile
  and replays each record's witness through the shipped HJEngine the first time
  that record is asked for — the same real-engine referee the retired generator
  used — withholding any board whose line does not clear instead of shipping it.
  Verified results and rejections are both cached, because HJHarborView builds
  its game destinations inside NavigationLinks and iOS 15 constructs those
  eagerly for every visible cell.

  HJGenerator.swift is deleted along with its two pbxproj object ids; the 120-salt
  reverse-construction search no longer runs on the device at all. Daily selects
  by dayKey modulo the baked pool count. The harness drops the generator and the
  now-meaningless pre-throttle audit tool from its source list.

  Co-Authored-By: Claude <noreply@anthropic.com>
  EOF
  )"
  ```


---

### Task 9: The board that shows the new rules

**Files:**
- `/Users/vik/Documents/development/for_human_review_apps/Harbor Jam/Harbor Jam/HJBoardView.swift` (modified)
- `/Users/vik/Documents/development/for_human_review_apps/Harbor Jam/Harbor Jam/HJGameView.swift` (modified)
- `/Users/vik/Documents/development/for_human_review_apps/Harbor Jam/tools/checks/task09_view_checks.sh` (new; **outside** the app target — it is a shell script, so it is **not** registered in `project.pbxproj`)

This task registers **no** file in `project.pbxproj` and uses **none** of the centrally assigned object ids. It changes no engine, model, view-model, generator, save or sound file. The engine is frozen; this task only *reads* it.

**Interfaces:**

*Consumes* (every symbol below is defined by an earlier task under the plan's frozen interface contract — the models are final before the engine, and the engine is final at Task 4; nothing here is defined later than Task 8):

```swift
extension HJDirection { var opposite: HJDirection }
struct HJBoat { var throttle: Int }                                   // 1...3
struct HJCurrentLane { var period: Int
                       func effectivePush(atTick tick: Int) -> HJDirection }
struct HJBoardState { var basins: [HJCell] }                          // tugTokens already deleted
enum HJBlockReason: Int, Codable, Equatable { case hull, sandbar, ferry, edge }
struct HJMovePreview: Equatable { var landing: [HJCell]; var exits: Bool
                                  var distance: Int; var stopReason: HJBlockReason? }
enum HJEngine {
    static func preview(boatID: Int, state: HJBoardState) -> HJMovePreview
    static func bowCells(of boat: HJBoat) -> [HJCell]
}
```

Plus these, which exist unchanged in the repo today: `HJBoardState.isAnchored(_:)` (`HJEngine.swift:53-56`), `HJBoat.width/height/cells` (`HJModels.swift:42-53`), `HJGameViewModel.tapBoat(_:store:)` (`HJGameViewModel.swift:50`), `HJGameViewModel.won`, `HJGameViewModel.state`, `HJStore.save.colorblindPatterns`, `HJTugShape` (`HJTheme.swift:218`), `HJHullShape` / `HJArrowShape` / `HJLockShape`, `HJTheme`, `HJLayout`.

Task 9 does **not** consume `HJSound`, `HJSoundID`, `HJLevelTable`, `HJProgressRecord`, `HJSave.stars(moves:par:)`, `movesCommitted`, `restartsUsed` or `isCleanLine`. No sound, scoring or HUD-counter work happens here.

*Produces* (all four types are new and live in `HJBoardView.swift`; `HJGameView.swift` uses `HJBoardMessage`):

```swift
struct HJBoardMessage: Equatable { var text: String; var tone: Tone
                                   enum Tone { case neutral, refusal } }
enum HJRefusalKind: Equatable { case blocked(HJBlockReason); case anchored }
struct HJRefusalFlash: Equatable { var boatID: Int; var kind: HJRefusalKind
                                   var bow: HJDirection; var cells: [HJCell]
                                   var partnerID: Int? }
struct HJHoldPreview: Equatable { var boatID: Int; var ghost: HJBoat?; var exits: Bool }

struct HJBoardView: View {                        // new stored input, changes the memberwise init
    @ObservedObject var vm: HJGameViewModel
    var store: HJStore
    var available: CGSize
    @Binding var message: HJBoardMessage?         // NEW — call site becomes
}                                                 // HJBoardView(vm:store:available:message:)

struct HJBoatView: View {                         // signature changes: `shaking` is gone
    var boat: HJBoat
    var cellSize: CGFloat
    var anchored: Bool
    var refusal: HJRefusalKind?                   // NEW (replaces `var shaking: Bool`)
    var highlight: Bool                           // NEW
    var patterns: Bool
    var night: Bool
    var artScale: CGFloat = 1
}
```

---

- [ ] **Step 1: Verify every symbol this task consumes already exists.** If any line prints `MISSING`, stop — an earlier task is incomplete and nothing below will compile. Run exactly:

```bash
cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam/Harbor Jam" && \
for probe in \
  "var opposite: HJDirection:HJModels.swift" \
  "var throttle: Int:HJModels.swift" \
  "var period: Int:HJModels.swift" \
  "func effectivePush(atTick:HJModels.swift" \
  "var basins: \[HJCell\]:HJEngine.swift" \
  "enum HJBlockReason:HJEngine.swift" \
  "struct HJMovePreview:HJEngine.swift" \
  "static func preview(boatID:HJEngine.swift" \
  "static func bowCells(of:HJEngine.swift" ; do
    pat="${probe%:*}"; file="${probe##*:}"
    if grep -q "$pat" "$file"; then echo "ok       $pat"; else echo "MISSING  $pat  ($file)"; fi
  done; \
grep -rn --include='*.swift' "tugTokens\|tugRotate\|tugArmed" . || echo "ok       tug economy fully deleted"
```

The last grep must print `ok       tug economy fully deleted`. If it lists hits in `HJGameView.swift` (today they are at `:90-92` and `:129-147`), the tug-deletion task has not landed and Step 12 below will not apply cleanly.

- [ ] **Step 2: Add the four presentation types and the new board state to `HJBoardView.swift`.** Replace the file's first line, `import SwiftUI`, with the block below (`import Foundation` is added because Steps 9-10 call `DispatchQueue.main.asyncAfter`, and `HJBoardView.swift` currently imports only SwiftUI):

```swift
import SwiftUI
import Foundation

/// One line of board copy, shown by `HJGameView` in the fixed row directly under
/// the marina. Two producers: the press-and-hold label (`.neutral`) and a refused
/// tap (`.refusal`). It lives outside `HJBoardView` because that view ends in
/// `.clipped()` (see `body`), which would crop a caption drawn inside the board.
struct HJBoardMessage: Equatable {
    enum Tone { case neutral, refusal }
    var text: String
    var tone: Tone
}

/// Why a tap did nothing. `HJBlockReason` comes straight from the engine's
/// `HJMovePreview.stopReason`; `.anchored` is the fifth, non-positional refusal.
enum HJRefusalKind: Equatable {
    case blocked(HJBlockReason)
    case anchored
}

/// The live refusal being drawn. Cleared 0.5s after it is set.
struct HJRefusalFlash: Equatable {
    var boatID: Int
    var kind: HJRefusalKind
    var bow: HJDirection
    /// The cells one step beyond the boat's bow — what it would have hit.
    var cells: [HJCell]
    /// For `.anchored`: the boat that must leave first.
    var partnerID: Int?
}

/// The press-and-hold ghost. `ghost` is nil when the boat would leave the
/// harbour (there is nothing left on the board to draw).
struct HJHoldPreview: Equatable {
    var boatID: Int
    var ghost: HJBoat?
    var exits: Bool
}
```

Then, in `struct HJBoardView`, replace these three lines (currently `HJBoardView.swift:6-9`)

```swift
    @ObservedObject var vm: HJGameViewModel
    var store: HJStore
    var available: CGSize
    @Environment(\.horizontalSizeClass) private var hSize
```

with:

```swift
    @ObservedObject var vm: HJGameViewModel
    var store: HJStore
    var available: CGSize
    /// Owned by `HJGameView` so the caption row sits outside the clipped board.
    @Binding var message: HJBoardMessage?
    @Environment(\.horizontalSizeClass) private var hSize

    /// The boat currently under a matured press-and-hold, and where it would land.
    @State private var hold: HJHoldPreview? = nil
    /// The refusal being drawn right now, if any.
    @State private var refusal: HJRefusalFlash? = nil
    /// Set when the finger travels far enough that the release is a drag-off,
    /// not a tap. Every one of these has an initial value, so the synthesized
    /// memberwise init is still `HJBoardView(vm:store:available:message:)`.
    @State private var dragged = false
```

- [ ] **Step 3: Wire the new layers into `body` and add the basin tiles.** Replace the five layer lines in `body` (currently `HJBoardView.swift:60-64`)

```swift
            tileLayer
            currentArrows
            sandbarLayer
            ferryLayer
            boatLayer
```

with:

```swift
            tileLayer
            basinLayer
            currentArrows
            sandbarLayer
            ferryLayer
            boatLayer
            ghostLayer
            wallFlash
```

Then insert this new computed property immediately after the closing brace of `tileLayer` (currently `HJBoardView.swift:88`):

```swift
    /// Turning basins. A boat whose bow cell enters one stops there and swings
    /// 180 degrees, so the tile is drawn as a slack mooring circle carrying the
    /// existing `HJTugShape` turn arrow — the same glyph the deleted tug chip
    /// used, which is why the art reads as "this is where you come about".
    private var basinLayer: some View {
        ZStack {
            ForEach(Array(vm.state.basins.enumerated()), id: \.offset) { _, cell in
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(vm.state.night ? 0.10 : 0.22))
                    Circle()
                        .stroke(HJTheme.navy.opacity(0.30),
                                style: StrokeStyle(lineWidth: 1.2 * artScale,
                                                   dash: [3 * artScale, 3 * artScale]))
                    HJTugShape()
                        .stroke(vm.state.night ? Color.white.opacity(0.75)
                                               : HJTheme.navy.opacity(0.55),
                                style: StrokeStyle(lineWidth: 1.8 * artScale, lineCap: .round))
                        .frame(width: cellSize * 0.5, height: cellSize * 0.5)
                }
                .frame(width: cellSize * 0.82, height: cellSize * 0.82)
                .position(cellCenter(x: cell.x, y: cell.y))
            }
        }
        .frame(width: boardSize.width, height: boardSize.height)
        .allowsHitTesting(false)
    }
```

- [ ] **Step 4: Make the lane arrows flip with the period.** Replace the whole `private var currentArrows: some View` property (currently `HJBoardView.swift:90-111`) with:

```swift
    private var currentArrows: some View {
        ZStack {
            ForEach(Array(vm.state.currents.enumerated()), id: \.offset) { _, lane in
                let now = lane.effectivePush(atTick: vm.state.taps)
                let next = lane.effectivePush(atTick: vm.state.taps + 1)
                // Base shape is always `lane.push` and the flip is a rotation,
                // not a different Shape: a new path would pop, a rotationEffect
                // interpolates, so the player sees the lane turn over.
                let flipped: Double = (now == lane.push) ? 0 : 180
                // The lane brightens on the tick before it turns, which is the
                // only warning the player gets that a drift is about to reverse.
                let ink = HJTheme.navy.opacity(next == now ? 0.22 : 0.45)
                if lane.isRow {
                    ForEach(0..<gridW, id: \.self) { x in
                        HJArrowShape(direction: lane.push)
                            .stroke(ink, lineWidth: 1.6 * artScale)
                            .frame(width: cellSize * 0.6, height: cellSize * 0.6)
                            .rotationEffect(.degrees(flipped))
                            .animation(.easeInOut(duration: 0.25), value: vm.state.taps)
                            .position(cellCenter(x: x, y: lane.index))
                    }
                } else {
                    ForEach(0..<gridH, id: \.self) { y in
                        HJArrowShape(direction: lane.push)
                            .stroke(ink, lineWidth: 1.6 * artScale)
                            .frame(width: cellSize * 0.6, height: cellSize * 0.6)
                            .rotationEffect(.degrees(flipped))
                            .animation(.easeInOut(duration: 0.25), value: vm.state.taps)
                            .position(cellCenter(x: lane.index, y: y))
                    }
                }
            }
        }
        .frame(width: boardSize.width, height: boardSize.height)
        .allowsHitTesting(false)
    }
```

- [ ] **Step 5: Give the sandbar and ferry refusals their own flash.** Replace the whole `private var sandbarLayer: some View` property (currently `HJBoardView.swift:113-132`) with:

```swift
    private var sandbarLayer: some View {
        ZStack {
            ForEach(Array(vm.state.sandbars.enumerated()), id: \.offset) { _, cell in
                let solid = vm.state.tideEnabled && !vm.state.tideHigh
                // This bar is the one the refused boat just grounded on.
                let flashing = refusal?.kind == .blocked(.sandbar)
                    && (refusal?.cells.contains(cell) ?? false)
                ZStack {
                    RoundedRectangle(cornerRadius: cellSize * 0.18)
                        .fill(Color(red: 0.90, green: 0.82, blue: 0.62).opacity(solid ? 0.95 : 0.35))
                    if solid {
                        HJWaveShape()
                            .stroke(HJTheme.driftwood.opacity(0.8), lineWidth: 1.4 * artScale)
                            .frame(width: cellSize * 0.55, height: cellSize * 0.3)
                    }
                    RoundedRectangle(cornerRadius: cellSize * 0.18)
                        .stroke(HJTheme.buoyRed, lineWidth: 2.4 * artScale)
                        .opacity(flashing ? 1 : 0)
                }
                .frame(width: cellSize * 0.88, height: cellSize * 0.88)
                .scaleEffect(flashing ? 1.12 : 1)
                .position(cellCenter(x: cell.x, y: cell.y))
                .animation(.easeInOut(duration: 0.3), value: vm.state.tideHigh)
                .animation(.easeInOut(duration: 0.16).repeatCount(3, autoreverses: true),
                           value: refusal)
            }
        }
        .frame(width: boardSize.width, height: boardSize.height)
        .allowsHitTesting(false)
    }
```

Then replace the whole `private var ferryLayer: some View` property (currently `HJBoardView.swift:134-154`) with:

```swift
    private var ferryLayer: some View {
        ZStack {
            if let f = vm.state.ferry {
                let flashing = refusal?.kind == .blocked(.ferry)
                ForEach(0..<f.length, id: \.self) { i in
                    let x = (f.x + i) % gridW
                    RoundedRectangle(cornerRadius: cellSize * 0.12)
                        .fill(Color(red: 0.35, green: 0.35, blue: 0.4))
                        .overlay(
                            Rectangle()
                                // The gold deck stripe is the ferry's signature
                                // mark, so turning it red is unmistakably "the
                                // ferry did this" and nothing else on the board
                                // moves.
                                .fill(flashing ? HJTheme.buoyRed : HJTheme.sunGold)
                                .frame(height: cellSize * 0.14)
                                .offset(y: -cellSize * 0.22)
                        )
                        .frame(width: cellSize * 0.94, height: cellSize * 0.7)
                        .position(cellCenter(x: x, y: f.row))
                }
            }
        }
        .frame(width: boardSize.width, height: boardSize.height)
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.25), value: vm.state.ferry)
        .animation(.easeInOut(duration: 0.16).repeatCount(3, autoreverses: true), value: refusal)
    }
```

- [ ] **Step 6: Add the ghost hull and the harbour-wall flash.** Insert both properties immediately after the closing brace of `ferryLayer`:

```swift
    /// Press-and-hold preview. Drawn ABOVE the hulls at a dashed outline so it
    /// stays readable when the landing footprint overlaps the boat's own — a
    /// throttle-1 move on a length-3 hull overlaps by two cells.
    private var ghostLayer: some View {
        ZStack {
            if let g = hold?.ghost {
                HJHullShape(bow: g.bow, isBarge: g.isBarge)
                    .stroke(Color.white.opacity(0.92),
                            style: StrokeStyle(lineWidth: 2 * artScale,
                                               dash: [5 * artScale, 4 * artScale]))
                    .frame(width: CGFloat(g.width) * cellSize * 0.92,
                           height: CGFloat(g.height) * cellSize * 0.92)
                    .overlay(
                        // g.bow is already the bow she will be lying on when she
                        // stops, so a basin swing is visible before it is taken.
                        HJArrowShape(direction: g.bow)
                            .stroke(Color.white.opacity(0.92), lineWidth: 1.6 * artScale)
                            .frame(width: cellSize * 0.4, height: cellSize * 0.4)
                    )
                    .position(boatCenter(g))
            }
        }
        .frame(width: boardSize.width, height: boardSize.height)
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.12), value: hold)
    }

    /// `.blocked(.edge)` treatment: the boat holds still and the harbour wall she
    /// is lying against lights up. Nothing else on the board can produce this.
    private var wallFlash: some View {
        ZStack {
            if let r = refusal, r.kind == .blocked(.edge) {
                let horizontal = r.bow.isHorizontal
                RoundedRectangle(cornerRadius: 2)
                    .fill(HJTheme.buoyRed.opacity(0.8))
                    .frame(width: horizontal ? 4 * artScale : boardSize.width,
                           height: horizontal ? boardSize.height : 4 * artScale)
                    .position(x: horizontal
                                ? (r.bow == .east ? boardSize.width - 2 * artScale : 2 * artScale)
                                : boardSize.width / 2,
                              y: horizontal
                                ? boardSize.height / 2
                                : (r.bow == .south ? boardSize.height - 2 * artScale : 2 * artScale))
            }
        }
        .frame(width: boardSize.width, height: boardSize.height)
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.16).repeatCount(3, autoreverses: true), value: refusal)
    }
```

- [ ] **Step 7: Rewrite `boatLayer` for the press gesture, the departure transition and the refusal routing.** Replace the whole `private var boatLayer: some View` property (currently `HJBoardView.swift:156-173`) with:

```swift
    private var boatLayer: some View {
        ZStack {
            ForEach(vm.state.boats) { boat in
                HJBoatView(boat: boat,
                           cellSize: cellSize,
                           anchored: vm.state.isAnchored(boat),
                           refusal: refusal?.boatID == boat.id ? refusal?.kind : nil,
                           highlight: refusal.flatMap { $0.partnerID } == boat.id,
                           patterns: store.save.colorblindPatterns,
                           night: vm.state.night,
                           artScale: artScale)
                    .position(boatCenter(boat))
                    // The ONLY gesture on a hull. There is deliberately no
                    // .onTapGesture: a matured press-and-hold must be able to
                    // end without committing a move, and two competing
                    // recognisers cannot guarantee that.
                    .gesture(pressGesture(for: boat))
                    .animation(.easeOut(duration: 0.22), value: boat.x)
                    .animation(.easeOut(duration: 0.22), value: boat.y)
                    .transition(.asymmetric(
                        insertion: .identity,
                        removal: AnyTransition.move(edge: departEdge(boat.bow))
                            .combined(with: .opacity)))
            }
        }
        .frame(width: boardSize.width, height: boardSize.height)
        // A removal transition only runs if the container's change is animated.
        // The view model removes the boat outside any withAnimation, so the
        // count is the trigger. It fires only when a boat leaves, so an ordinary
        // advance is still carried solely by the per-boat .animation above.
        .animation(.easeInOut(duration: 0.28), value: vm.state.boats.count)
    }

    /// She sails out the way her bow points.
    private func departEdge(_ bow: HJDirection) -> Edge {
        switch bow {
        case .north: return .top
        case .south: return .bottom
        case .east:  return .trailing
        case .west:  return .leading
        }
    }
```

- [ ] **Step 8: Add the gesture and the hold/commit helpers.** Insert this block immediately after the `private func boatCenter(_ boat: HJBoat) -> CGPoint { ... }` helper (currently `HJBoardView.swift:179-182`), still inside `struct HJBoardView`:

```swift
    // MARK: - Press, hold, release

    /// Long press matures -> ghost. Release -> commit, but only if the hold never
    /// matured and the finger did not travel. The DragGesture's `onEnded` is the
    /// release hook (it fires on lift for any finger travel, including zero).
    private func pressGesture(for boat: HJBoat) -> some Gesture {
        LongPressGesture(minimumDuration: 0.25, maximumDistance: 40)
            .onEnded { _ in beginHold(boat) }
            .simultaneously(with:
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        if abs(v.translation.width) > 12 || abs(v.translation.height) > 12 {
                            dragged = true
                        }
                    }
                    .onEnded { _ in endPress(boat) }
            )
    }

    private func beginHold(_ boat: HJBoat) {
        guard !vm.won else { return }
        if vm.state.isAnchored(boat) {
            hold = HJHoldPreview(boatID: boat.id, ghost: nil, exits: false)
            show(HJBoardMessage(text: "Chained — the boat she is tied to must leave first.",
                                tone: .refusal))
            return
        }
        let p = HJEngine.preview(boatID: boat.id, state: vm.state)
        var ghost: HJBoat? = nil
        var swung = false
        if !p.exits,
           let minX = p.landing.map({ $0.x }).min(),
           let minY = p.landing.map({ $0.y }).min() {
            var g = boat
            g.x = minX
            g.y = minY
            // Presentation only: mirrors the engine's basin rule so the ghost
            // shows the bow she will actually be lying on. `HJMovePreview`
            // carries the landing cells but not the resulting heading.
            if HJEngine.bowCells(of: g).contains(where: { vm.state.basins.contains($0) }) {
                g.bow = boat.bow.opposite
                swung = true
            }
            ghost = g
        }
        hold = HJHoldPreview(boatID: boat.id, ghost: ghost, exits: p.exits)
        show(HJBoardMessage(text: holdLabel(distance: p.distance, exits: p.exits,
                                            stop: p.stopReason, swung: swung),
                            tone: .neutral))
    }

    private func endPress(_ boat: HJBoat) {
        let matured = hold?.boatID == boat.id
        let travelled = dragged
        hold = nil
        dragged = false
        if matured || travelled {
            // A hold that showed the ghost, or a finger dragged off the hull,
            // never commits a move.
            message = nil
            return
        }
        commitTap(boat)
    }

    private func commitTap(_ boat: HJBoat) {
        guard !vm.won else { return }
        // Classify BEFORE the tap: the same pure engine the tap is about to run,
        // read against the same state, so the treatment always names the real
        // reason. The tap itself stays the view model's job.
        if vm.state.isAnchored(boat) {
            flashRefusal(.anchored, on: boat, partner: boat.anchoredBy)
        } else {
            let p = HJEngine.preview(boatID: boat.id, state: vm.state)
            if p.distance == 0 && !p.exits {
                flashRefusal(.blocked(p.stopReason ?? .edge), on: boat, partner: nil)
            } else {
                refusal = nil
                message = nil
            }
        }
        vm.tapBoat(boat.id, store: store)
    }

    // MARK: - Copy

    private func holdLabel(distance: Int, exits: Bool,
                           stop: HJBlockReason?, swung: Bool) -> String {
        if exits { return "Clears the harbour." }
        if distance == 0 { return refusalText(.blocked(stop ?? .edge)) }
        let lead = distance == 1 ? "1 ahead" : "\(distance) ahead"
        switch stop {
        case .some(.hull):    return "\(lead) — stops astern of another hull."
        case .some(.sandbar): return "\(lead) — stops at a sandbar at low tide."
        case .some(.ferry):   return "\(lead) — stops behind the ferry."
        case .some(.edge):    return "\(lead) — stops at the harbour wall."
        case .none:           return swung ? "\(lead) — swings about in the turning basin."
                                           : "\(lead) — her throttle is spent."
        }
    }

    private func refusalText(_ kind: HJRefusalKind) -> String {
        switch kind {
        case .anchored:           return "Chained — the boat she is tied to must leave first."
        case .blocked(.hull):     return "Fouled on another hull. The harbour still moved."
        case .blocked(.sandbar):  return "Aground on a sandbar at low tide."
        case .blocked(.ferry):    return "The ferry is across her bow."
        case .blocked(.edge):     return "Hard against the harbour wall."
        }
    }

    // MARK: - Flashes

    private func flashRefusal(_ kind: HJRefusalKind, on boat: HJBoat, partner: Int?) {
        let ahead = HJEngine.bowCells(of: boat).map {
            HJCell(x: $0.x + boat.bow.dx, y: $0.y + boat.bow.dy)
        }
        let r = HJRefusalFlash(boatID: boat.id, kind: kind, bow: boat.bow,
                               cells: ahead, partnerID: partner)
        refusal = r
        show(HJBoardMessage(text: refusalText(kind), tone: .refusal))
        // 0.32s of nudge (4 x 0.08) plus margin.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if refusal == r { refusal = nil }
        }
    }

    private func show(_ m: HJBoardMessage) {
        message = m
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            if message == m { message = nil }
        }
    }
```

- [ ] **Step 9: Rewrite `HJBoatView` in full — throttle pips plus one distinct treatment per refusal.** Replace the entire `struct HJBoatView: View { ... }` declaration (currently `HJBoardView.swift:185-232`, from the line `struct HJBoatView: View {` down to and including its closing brace, leaving `struct HJHullShape` below untouched) with:

```swift
struct HJBoatView: View {
    var boat: HJBoat
    var cellSize: CGFloat
    var anchored: Bool
    /// Non-nil only on the one boat whose last tap was refused, and only for the
    /// ~0.5s the flash lasts.
    var refusal: HJRefusalKind?
    /// True on the boat an `.anchored` refusal is waiting for.
    var highlight: Bool
    var patterns: Bool
    var night: Bool
    /// 1 on iPhone / compact width — see `HJBoardView.artScale`.
    var artScale: CGFloat = 1

    private var hull: Color { HJTheme.hullColors[boat.hullIndex % HJTheme.hullColors.count] }
    private var w: CGFloat { CGFloat(boat.width) * cellSize * 0.92 }
    private var h: CGFloat { CGFloat(boat.height) * cellSize * 0.92 }

    /// The five refusals are told apart by MOTION and by WHICH object reacts,
    /// never by colour alone:
    ///   .blocked(.hull)     this hull nudges 4pt along its bow and bounces back
    ///                       (the old shake, now aimed forward instead of sideways)
    ///   .blocked(.sandbar)  this hull holds dead still; the sandbar ahead pulses
    ///                       red and 12% larger  (HJBoardView.sandbarLayer)
    ///   .blocked(.ferry)    this hull holds dead still; the ferry's gold deck
    ///                       stripe strobes red  (HJBoardView.ferryLayer)
    ///   .blocked(.edge)     this hull holds dead still; the harbour wall on her
    ///                       bow side lights red (HJBoardView.wallFlash)
    ///   .anchored           this hull dims to 0.55 and its buoy badge pulses to
    ///                       135%, and the boat she is chained to takes a white
    ///                       ring. No forward motion at all, because nothing
    ///                       ahead of her is what stopped her.
    private var nudge: CGFloat { refusal == .blocked(.hull) ? 4 * artScale : 0 }

    private var refusalAnimation: Animation {
        switch refusal {
        case .some(.blocked(.hull)):
            return .easeInOut(duration: 0.08).repeatCount(4, autoreverses: true)
        case .some(.anchored):
            return .easeInOut(duration: 0.14).repeatCount(3, autoreverses: true)
        default:
            return .easeInOut(duration: 0.18)
        }
    }

    /// Printed throttle: 1-3 dots in a rung across the deck, astern of the bow
    /// arrow. Geometry, in cell units (cs), for the two hull shapes that exist:
    ///   1xN hull, bow east: half-extent along the bow = 0.92cs (N=2), rung sits
    ///     at 0.66 x 0.92 = 0.607cs astern; the arrow's own half-extent is
    ///     min(w,h) x 0.5 / 2 = 0.23cs and the pip radius is 0.0575cs, so the
    ///     rung's inner edge (0.549cs) clears the arrow and its outer edge
    ///     (0.665cs) stays inside the hull.
    ///   2x2 barge: half-extent 0.92cs, same 0.607cs; the arrow is larger here
    ///     (half-extent 0.46cs) and the rung still clears it by 0.089cs.
    ///   Across the deck the rung is 3 x 0.115 + 2 x 0.075 = 0.495cs wide against
    ///     a 0.92cs beam, so a throttle-3 rung fits the narrowest hull.
    private var throttlePips: some View {
        let d = cellSize * 0.115
        let g = cellSize * 0.075
        let n = max(1, min(3, boat.throttle))
        let run = CGFloat(n) * d + CGFloat(n - 1) * g
        let stern = ((boat.bow.isHorizontal ? w : h) / 2) * 0.66
        return ZStack {
            ForEach(0..<n, id: \.self) { i in
                let t = -run / 2 + d / 2 + CGFloat(i) * (d + g)
                Circle()
                    .fill(Color.white.opacity(0.92))
                    .overlay(Circle().stroke(Color.black.opacity(0.28), lineWidth: 0.8 * artScale))
                    .frame(width: d, height: d)
                    .offset(x: boat.bow.isHorizontal ? CGFloat(boat.bow.opposite.dx) * stern : t,
                            y: boat.bow.isHorizontal ? t : CGFloat(boat.bow.opposite.dy) * stern)
            }
        }
    }

    var body: some View {
        ZStack {
            HJHullShape(bow: boat.bow, isBarge: boat.isBarge)
                .fill(hull)
            HJHullShape(bow: boat.bow, isBarge: boat.isBarge)
                .stroke(Color.black.opacity(0.25), lineWidth: 1.5 * artScale)
            if patterns {
                HJPatternOverlay(index: boat.hullIndex, artScale: artScale)
                    .clipShape(HJHullShape(bow: boat.bow, isBarge: boat.isBarge))
            }
            // deck stripe pointing at the bow
            HJArrowShape(direction: boat.bow)
                .stroke(Color.white.opacity(0.85), lineWidth: 2 * artScale)
                .frame(width: min(w, h) * 0.5, height: min(w, h) * 0.5)
            throttlePips
            if highlight {
                HJHullShape(bow: boat.bow, isBarge: boat.isBarge)
                    .stroke(Color.white, lineWidth: 3 * artScale)
            }
            if anchored {
                Circle()
                    .fill(HJTheme.buoyRed)
                    .frame(width: cellSize * 0.3, height: cellSize * 0.3)
                    .overlay(
                        HJLockShape()
                            .stroke(Color.white, lineWidth: 1.4 * artScale)
                            .frame(width: cellSize * 0.18, height: cellSize * 0.18)
                    )
                    .scaleEffect(refusal == .anchored ? 1.35 : 1)
                    .offset(x: w * 0.28, y: -h * 0.28)
            }
        }
        .frame(width: w, height: h)
        // Aimed along the bow, so the nudge reads as "she tried to go THAT way".
        // 4pt is invisible against a 900pt iPad board, so it scales too.
        .offset(x: nudge * CGFloat(boat.bow.dx), y: nudge * CGFloat(boat.bow.dy))
        .opacity(refusal == .anchored ? 0.55 : (anchored ? 0.82 : 1))
        // One animation modifier, one value: the nudge, the badge pulse and the
        // dim are mutually exclusive, so they cannot fight over the curve.
        .animation(refusalAnimation, value: refusal)
    }
}
```

Note that this removes the last read of `vm.shakeBoatID` anywhere in the app (it was `HJBoardView.swift:162`). Do **not** touch `HJGameViewModel.swift` to delete the now-unread `@Published var shakeBoatID` — that file is out of scope for this task and an unread published property produces no warning.

- [ ] **Step 10: Add the caption row to `HJGameView`.** In `struct HJGameView`, replace the single line (currently `HJGameView.swift:11`)

```swift
    @State private var nextMode: HJGameMode? = nil
```

with:

```swift
    @State private var nextMode: HJGameMode? = nil
    /// One line of board copy: the press-and-hold label, or why a tap was
    /// refused. It lives here, not inside HJBoardView, because that view ends in
    /// `.clipped()` and would crop it.
    @State private var boardMessage: HJBoardMessage? = nil

    /// Height of the caption row. Reserved out of the board's available height
    /// below so adding the row cannot squeeze the marina.
    private let messageRowHeight: CGFloat = 18
```

- [ ] **Step 11: Reserve the caption row's height and render it.** In `body`, replace these three lines (currently `HJGameView.swift:36-38`)

```swift
            let boardAvailable = CGSize(
                width: boardWidth,
                height: geo.size.height - (compact ? 170 : 210) - tabBarInset)
```

with (the constants grow by `messageRowHeight` plus one VStack spacing: 170 + 6 + 18 = 194, 210 + 12 + 18 = 240):

```swift
            let boardAvailable = CGSize(
                width: boardWidth,
                height: geo.size.height - (compact ? 194 : 240) - tabBarInset)
```

Then replace these four lines (currently `HJGameView.swift:46-49`)

```swift
                    HJBoardView(vm: vm, store: store, available: boardAvailable)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    controls
                        .padding(.bottom, (compact ? 6 : 12) + tabBarInset)
```

with:

```swift
                    HJBoardView(vm: vm, store: store, available: boardAvailable,
                                message: $boardMessage)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    messageLine
                        .hjColumn(HJLayout.gameChromeColumn, hSize)
                    controls
                        .padding(.bottom, (compact ? 6 : 12) + tabBarInset)
```

and add `.onChange` to the `ZStack` so a stale caption never sits under the win card — replace these three lines (currently `HJGameView.swift:56-58`)

```swift
                if !store.save.onboardingSeen {
                    HJOnboardingOverlay()
                }
```

with:

```swift
                if !store.save.onboardingSeen {
                    HJOnboardingOverlay()
                }
            }
            .onChange(of: vm.won) { didWin in
                if didWin { boardMessage = nil }
```

(the inserted `}` closes the `ZStack`; the trailing `}` already on the following line then closes the `onChange` closure — read the file back and confirm the brace balance before building).

Finally, insert this property immediately after the closing brace of `private var header: some View` (currently `HJGameView.swift:81`):

```swift
    /// Fixed-height so the board never reflows when a caption appears. The
    /// space keeps the row's height when there is nothing to say.
    private var messageLine: some View {
        Text(boardMessage?.text ?? " ")
            .font(HJTheme.body(12, weight: .semibold))
            .foregroundColor(boardMessage?.tone == .refusal ? HJTheme.buoyRed : HJTheme.inkSoft)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(height: messageRowHeight)
            .frame(maxWidth: .infinity)
            .animation(.easeInOut(duration: 0.15), value: boardMessage)
    }
```

- [ ] **Step 12: Confirm the existing motion animation carries multi-cell moves and drift, and write the confirmation down.** Run:

```bash
cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam/Harbor Jam" && \
grep -n "animation(.easeOut(duration: 0.22), value: boat.x)\|animation(.easeOut(duration: 0.22), value: boat.y)\|position(boatCenter(boat))" HJBoardView.swift && \
grep -n "struct HJBoat: Codable, Identifiable, Equatable" HJModels.swift
```

All four lines must print. The confirmation, which belongs as a comment above the two `.animation` lines in `boatLayer` — add it verbatim:

```swift
                    // Multi-cell throttle moves and current drift need NO new
                    // animation code. The hull is placed by .position(boatCenter(boat)),
                    // which is a pure function of boat.x / boat.y (HJBoardView.boatCenter),
                    // and HJBoat is Identifiable on `id` (HJModels.swift:32), so the
                    // ForEach keeps the SAME view across a move instead of replacing it.
                    // .animation(_:value:) therefore interpolates the position for ANY
                    // delta: 1 cell or 3. A current push mutates boat.x / boat.y inside
                    // the same state commit as the tap, so the drift rides the identical
                    // modifier and lands in the same 0.22s.
```

- [ ] **Step 13: Write the source-invariant check script.** The project has no XCTest target, so the assertions are grep-level invariants over the two files this task owns. Create `/Users/vik/Documents/development/for_human_review_apps/Harbor Jam/tools/checks/task09_view_checks.sh` with exactly this content:

```bash
#!/bin/bash
# Task 9 view-layer invariants. Prints PASS/FAIL per check, exits non-zero on any FAIL.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BV="$ROOT/Harbor Jam/HJBoardView.swift"
GV="$ROOT/Harbor Jam/HJGameView.swift"
fail=0
pass() { echo "PASS  $1"; }
bad()  { echo "FAIL  $1"; fail=1; }
present() { if grep -qF -- "$1" "$3"; then pass "$2"; else bad "$2"; fi; }
absent()  { if grep -qF -- "$1" "$3"; then bad "$2"; else pass "$2"; fi; }

# The engine froze at Task 4: the view reads it and never mutates through it.
absent  "HJEngine.tap("         "board never calls HJEngine.tap"          "$BV"
absent  "HJEngine.march("       "board never calls HJEngine.march"        "$BV"
absent  "HJEngine.tickWorld("   "board never calls HJEngine.tickWorld"    "$BV"
absent  "HJEngine.applyCurrents" "board never calls applyCurrents"        "$BV"
present "HJEngine.preview("     "board reads the engine preview"          "$BV"
present "HJEngine.bowCells("    "board reads engine bowCells"             "$BV"

# A matured hold must not be able to commit a move through a second recogniser.
absent  "onTapGesture"          "no onTapGesture anywhere on the board"   "$BV"
present "LongPressGesture"      "press-and-hold is the hold recogniser"   "$BV"
present "DragGesture"           "release is driven by DragGesture.onEnded" "$BV"

# The new rules are actually drawn.
present "boat.throttle"         "throttle pips read boat.throttle"        "$BV"
present "vm.state.basins"       "basin tiles read state.basins"           "$BV"
present "HJTugShape()"          "basin tile reuses HJTugShape"            "$BV"
present "effectivePush(atTick:" "lane arrows use the flipping push"       "$BV"
present ".transition("          "departures have a transition"            "$BV"
present "animation(.easeOut(duration: 0.22), value: boat.x)" \
        "existing 0.22s motion animation survives"                        "$BV"

# All five refusals get their own treatment.
for k in ".blocked(.hull)" ".blocked(.sandbar)" ".blocked(.ferry)" ".blocked(.edge)" ".anchored"; do
  present "$k" "refusal treatment exists for $k" "$BV"
done

# Caption row wiring.
present "message: \$boardMessage" "board is handed the caption binding"   "$GV"
present "messageLine"             "caption row is in the layout"          "$GV"

# House rules: iOS 15.6 floor, no SF Symbols, no emoji.
for f in "$BV" "$GV"; do
  n="$(basename "$f")"
  absent "Image(systemName" "no SF Symbols in $n" "$f"
  absent ".tracking("       "no .tracking() in $n" "$f"
  for api in "NavigationStack" "AnyLayout" "ViewThatFits" ".scrollDisabled" ".symbolEffect" "Gauge(" ".presentationDetents"; do
    absent "$api" "no iOS 16+ API $api in $n" "$f"
  done
done

if python3 - "$BV" "$GV" <<'PY'
import sys, re
pat = re.compile('[\U0001F000-\U0001FAFF\u2600-\u27BF\u2B00-\u2BFF\uFE0F]')
hits = []
for path in sys.argv[1:]:
    with open(path, encoding='utf-8') as fh:
        for i, line in enumerate(fh, 1):
            if pat.search(line):
                hits.append("%s:%d" % (path, i))
for h in hits:
    print("  pictograph at " + h)
sys.exit(1 if hits else 0)
PY
then pass "no emoji or pictographs"; else bad "no emoji or pictographs"; fi

if [ "$fail" -eq 0 ]; then echo "ALL CHECKS PASSED"; else echo "CHECKS FAILED"; fi
exit "$fail"
```

Then make it executable and run it. The required assertion: **it exits 0 and its last line is `ALL CHECKS PASSED`.**

```bash
chmod +x "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam/tools/checks/task09_view_checks.sh" && \
"/Users/vik/Documents/development/for_human_review_apps/Harbor Jam/tools/checks/task09_view_checks.sh"; echo "exit=$?"
```

- [ ] **Step 14: Compile Debug and Release with zero warnings.** Both commands must end in `** BUILD SUCCEEDED **`, and the `grep -c` must print `0`:

```bash
cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam" && \
xcodebuild -project "Harbor Jam.xcodeproj" -scheme "Harbor Jam" -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tee /tmp/hj_task9_debug.log | tail -3 && \
xcodebuild -project "Harbor Jam.xcodeproj" -scheme "Harbor Jam" -configuration Release \
  -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tee /tmp/hj_task9_release.log | tail -3 && \
grep -c "warning:" /tmp/hj_task9_debug.log /tmp/hj_task9_release.log
```

If `grep -c` reports any warning, fix it before committing — the definition of done in the spec (§6) is Debug + Release `BUILD SUCCEEDED`, zero warnings.

- [ ] **Step 15: Confirm the blast radius is exactly three files, then commit.** The first command must list precisely `Harbor Jam/HJBoardView.swift`, `Harbor Jam/HJGameView.swift` and `tools/checks/task09_view_checks.sh` and nothing else:

```bash
cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam" && git status --porcelain && \
git add "Harbor Jam/HJBoardView.swift" "Harbor Jam/HJGameView.swift" "tools/checks/task09_view_checks.sh" && \
git commit -m "Board: throttle pips, basins, flipping lanes and a legible refusal

Draws the new rules on the marina. Every hull prints its throttle as 1-3 dots
in a rung astern of the bow arrow; turning basins are mooring circles carrying
the HJTugShape turn glyph; lane arrows rotate 180 degrees on the tick their
period flips and brighten the tick before.

Press-and-hold ghosts the landing footprint from HJEngine.preview - including
the 180 degree swing when she comes about in a basin - and names the stop in one
line under the board. Releasing a matured hold commits nothing: the hull carries
a single composed gesture and no onTapGesture, so there is no second recogniser
to fire.

The one 4pt shake splits five ways. Fouled on a hull nudges the hull along its
bow; a sandbar, the ferry and the harbour wall each leave the hull dead still
and light the thing that stopped her; a chained boat dims, pulses its buoy and
puts a white ring on the boat it is waiting for. Departures sail out on a move
transition. Multi-cell moves and current drift need no new animation code - the
existing 0.22s easeOut on boat.x / boat.y already carries them.

No engine, model, view-model or pbxproj change.

Co-Authored-By: Claude <noreply@anthropic.com>"
```


---

### Task 10: The harbour bell

Replaces the generic system alert win sound (`AudioServicesPlaySystemSound(1025)`, currently `Harbor Jam/HJGameViewModel.swift:107`) with a bundled, synthesised bronze bell, and moves every sound the game makes behind one named vocabulary so an exit and a partial advance — the two outcomes that only became distinguishable under throttle — are guaranteed to sound different. Implements spec §2.8 in full.

**Files:**
- `tools/HarborForge/mkbell.py` — new (pure Python stdlib synthesiser)
- `Harbor Jam/win_bell.wav` — new (generated, committed)
- `Harbor Jam/win_bell_double.wav` — new (generated, committed)
- `Harbor Jam/HJSound.swift` — new
- `Harbor Jam/HJGameViewModel.swift` — edited (4 call sites, 1 helper, 1 import, init/deinit)
- `Harbor Jam.xcodeproj/project.pbxproj` — edited (3 files × 4 registrations)

**Interfaces:**

*Consumes*
- From Task 4 (engine final): `enum HJTapOutcome` — its `.exited` / `.moved` / `.blocked` / `.anchored` / `.invalid` cases are the `switch` in `HJGameViewModel.tapBoat(_:store:)` whose bodies hold the call sites this task retypes. No engine behaviour is read or changed here.
- Pre-existing, untouched by any earlier task: `HJSave.soundOn: Bool` (`Harbor Jam/HJSave.swift:51`), surfaced as `HJGameViewModel.soundOn` (`:26`, assigned at `:42`); the private helper `HJGameViewModel.playSound(_:)` (`:136-139`).

*Produces*
```swift
// Harbor Jam/HJSound.swift
enum HJSoundID { case advance; case exit; case blocked; case win; case winPerfect }
enum HJSound {
    static func prepare()
    static func play(_ id: HJSoundID, enabled: Bool)
    static func teardown()
}
// Harbor Jam/HJGameViewModel.swift
private func playSound(_ id: HJSoundID)   // was: (_ id: SystemSoundID)
```
`.winPerfect` is **defined and playable but never called by this task.** It is wired by Task 11, which owns `HJGameViewModel.isCleanLine` and therefore owns the decision of when a win is perfect. Both bells exist and both are registered after this task; Task 11 adds exactly one call site. Do not add a caller here — you would have to guess the mastery condition, and Task 11 would then have two.

`.blocked` is likewise defined and not called: it is deliberately silent (a refused tap is drawn by the 4pt shake and felt by the heavy haptic). It exists so that a block tone, if §2.7's feedback work later wants one, is a one-line change inside `HJSound.play` and touches nothing else.

---

- [ ] **Step 1: Write the synthesiser `tools/HarborForge/mkbell.py`.**

Create the directory if Task 1 has not already:

```bash
mkdir -p "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam/tools/HarborForge"
```

Then write `/Users/vik/Documents/development/for_human_review_apps/Harbor Jam/tools/HarborForge/mkbell.py` with exactly this content (Python 3.9 compatible — no 3.10 syntax, no numpy, only `wave`, `math`, `struct`, `os`, `sys`):

```python
#!/usr/bin/env python3
# Harbor Jam - harbour bell synthesiser.
# Pure Python standard library: wave, math, struct. No numpy, no third-party audio.
# Writes mono 44100 Hz 16-bit PCM WAV files, per spec 2.8.
#
#   win_bell.wav         a single struck bronze bell, fundamental ~587 Hz
#   win_bell_double.wav  the same strike answered a fifth higher (~880 Hz) 200 ms later

import math
import os
import struct
import sys
import wave

SAMPLE_RATE = 44100
FUNDAMENTAL = 587.33                              # D5, the "~587 Hz" of spec 2.8
ANSWER = 880.00                                   # a fifth above, the answering bell
PARTIALS = (1.0, 2.0, 3.0, 4.2)                   # inharmonic, exactly as specified
PARTIAL_GAIN = (1.00, 0.55, 0.32, 0.20)
PARTIAL_DECAY_SCALE = (1.00, 0.72, 0.55, 0.42)    # higher partials die first
DECAY_SECONDS = 1.4                               # amplitude falls 60 dB in this long
ATTACK_SECONDS = 0.005                            # 5 ms ramp, so the strike does not click
ANSWER_DELAY = 0.200                              # 200 ms between the two bells
TAIL_SECONDS = 0.2                                # silence after the last audible decay
PEAK = 0.89                                       # normalisation target, leaves headroom


def strike(buf, start_sample, freq, gain):
    """Add one struck-bell voice into buf (a list of floats) starting at start_sample."""
    base_tau = DECAY_SECONDS / math.log(1000.0)   # -60 dB at DECAY_SECONDS
    n = len(buf)
    for p_index, ratio in enumerate(PARTIALS):
        w = 2.0 * math.pi * freq * ratio
        amp = PARTIAL_GAIN[p_index] * gain
        tau = base_tau * PARTIAL_DECAY_SCALE[p_index]
        life = int(tau * math.log(10000.0) * SAMPLE_RATE)   # stop 80 dB down
        for i in range(life):
            j = start_sample + i
            if j >= n:
                break
            t = i / float(SAMPLE_RATE)
            env = math.exp(-t / tau)
            if t < ATTACK_SECONDS:
                env *= t / ATTACK_SECONDS
            buf[j] += amp * env * math.sin(w * t)


def write_wav(path, buf):
    peak = max(abs(v) for v in buf)
    scale = (PEAK / peak) if peak > 0.0 else 0.0
    frames = bytearray()
    for v in buf:
        s = int(round(v * scale * 32767.0))
        if s > 32767:
            s = 32767
        if s < -32768:
            s = -32768
        frames += struct.pack('<h', s)
    w = wave.open(path, 'wb')
    try:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SAMPLE_RATE)
        w.writeframes(bytes(frames))
    finally:
        w.close()
    print("wrote %s  %.3f s  %d frames" % (path, len(buf) / float(SAMPLE_RATE), len(buf)))


def main():
    if len(sys.argv) != 2:
        sys.stderr.write("usage: mkbell.py <output-directory>\n")
        return 2
    out_dir = sys.argv[1]
    if not os.path.isdir(out_dir):
        sys.stderr.write("not a directory: %s\n" % out_dir)
        return 2

    single_len = int((DECAY_SECONDS + TAIL_SECONDS) * SAMPLE_RATE)
    single = [0.0] * single_len
    strike(single, 0, FUNDAMENTAL, 1.0)
    write_wav(os.path.join(out_dir, 'win_bell.wav'), single)

    double_len = int((ANSWER_DELAY + DECAY_SECONDS + TAIL_SECONDS) * SAMPLE_RATE)
    double = [0.0] * double_len
    strike(double, 0, FUNDAMENTAL, 1.0)
    strike(double, int(ANSWER_DELAY * SAMPLE_RATE), ANSWER, 0.85)
    write_wav(os.path.join(out_dir, 'win_bell_double.wav'), double)
    return 0


if __name__ == '__main__':
    sys.exit(main())
```

Every number in this file maps to a sentence in spec §2.8: `FUNDAMENTAL` ≈ 587 Hz, `PARTIALS` at ×2.0 / ×3.0 / ×4.2, `DECAY_SECONDS` 1.4 s, `ATTACK_SECONDS` 5 ms, `ANSWER` a fifth higher at 880 Hz, `ANSWER_DELAY` 200 ms.

- [ ] **Step 2: Generate the two WAVs straight into the app source folder.**

The bundled resources live flat in `Harbor Jam/`, beside the `.swift` files and `Assets.xcassets` — the same flat group the contract names for `levels.json`. There is no `Resources/` subfolder in this project.

```bash
cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam" && python3 tools/HarborForge/mkbell.py "Harbor Jam"
```

Assertion: the command exits 0 and prints two `wrote …` lines, one per file. If it prints `not a directory`, you ran it from the wrong place — the argument is the app source folder, not the repo root.

- [ ] **Step 3: Verify both files against their real headers.**

Do not check file size — it is not a property the spec states. Read the actual audio header with `afinfo` and assert format and duration. Paste as one command:

```bash
cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam" && python3 - <<'PY'
import re, subprocess, sys

CHECKS = (("Harbor Jam/win_bell.wav", 1.50, 1.70),
          ("Harbor Jam/win_bell_double.wav", 1.70, 1.90))
ok = True
for path, lo, hi in CHECKS:
    out = subprocess.run(["afinfo", path], capture_output=True, text=True).stdout
    fmt = re.search(r"Data format:\s*(\d+) ch,\s*(\d+) Hz, (\S+)", out)
    dur = re.search(r"estimated duration: ([0-9.]+) sec", out)
    if not fmt or not dur:
        print("FAIL %s: afinfo reported no format/duration" % path); ok = False; continue
    ch, hz, enc = fmt.group(1), fmt.group(2), fmt.group(3)
    d = float(dur.group(1))
    bad = []
    if ch != "1": bad.append("channels=%s want 1" % ch)
    if hz != "44100": bad.append("rate=%s want 44100" % hz)
    if enc != "Int16": bad.append("encoding=%s want Int16" % enc)
    if not (lo <= d <= hi): bad.append("duration=%.3f want %.2f..%.2f s" % (d, lo, hi))
    if d >= 30.0: bad.append("duration >= 30 s, AudioServices will not take it")
    if bad:
        print("FAIL %s: %s" % (path, "; ".join(bad))); ok = False
    else:
        print("PASS %s: 1 ch, 44100 Hz, Int16, %.3f s" % (path, d))
sys.exit(0 if ok else 1)
PY
```

Assertion: exit status 0 and two `PASS` lines. The `< 30 s` clause is the one that matters for the mechanism — `AudioServicesCreateSystemSoundID` refuses longer files, and refusing silently is exactly the failure this check exists to prevent.

- [ ] **Step 4: Create `Harbor Jam/HJSound.swift`.**

Write this file exactly:

```swift
import Foundation
import AudioToolbox

/// Every outcome that has a voice. `.blocked` and `.winPerfect` are declared here so the
/// whole audio vocabulary lives in one place; see `HJSound.play` for what each one does today.
enum HJSoundID {
    case advance
    case exit
    case blocked
    case win
    case winPerfect
}

/// The app's only audio path.
///
/// The two bells are bundled PCM WAVs (mono, 44.1 kHz, 16-bit, under 30 s), which is a format
/// `AudioServicesCreateSystemSoundID` accepts directly - no `AVFoundation`, no extra framework
/// link. They are created once and disposed in `teardown()`.
///
/// The move sounds stay the short system tones the game already used, but they now sit behind
/// this switch so the two outcomes that matter under throttle - a boat that leaves the harbour
/// and a boat that only shuffles forward - are guaranteed to sound different.
enum HJSound {

    private static var sounds: [String: SystemSoundID] = [:]
    private static var registered = false
    private static var clients = 0

    // MARK: - Lifecycle

    /// Call once per owner (the game view model) before the first `play`.
    /// Balanced by `teardown()`; the bells survive until the last owner goes away, so building
    /// the next level's view model before the previous one deinits cannot dispose a sound in use.
    static func prepare() {
        clients += 1
        ensureRegistered()
    }

    /// Balances one `prepare()`. Disposes the bundled sounds when the last owner is gone.
    static func teardown() {
        clients = max(0, clients - 1)
        guard clients == 0 else { return }
        for (_, sid) in sounds {
            AudioServicesDisposeSystemSoundID(sid)
        }
        sounds.removeAll()
        registered = false
    }

    // MARK: - Playback

    /// `enabled` is the player's `soundOn` setting; nothing is played when it is off.
    static func play(_ id: HJSoundID, enabled: Bool) {
        guard enabled else { return }
        switch id {
        case .advance:
            AudioServicesPlaySystemSound(1104)
        case .exit:
            AudioServicesPlaySystemSound(1057)
        case .blocked:
            // Deliberately silent. A refused tap is drawn (the 4pt shake) and felt (the heavy
            // haptic); a third short tone on a verb the player presses constantly reads as an
            // error chime. The case exists so that adding a block tone is a one-line change here.
            break
        case .win:
            playBundled("win_bell")
        case .winPerfect:
            playBundled("win_bell_double")
        }
    }

    // MARK: - Private

    private static func ensureRegistered() {
        guard !registered else { return }
        registered = true
        register("win_bell")
        register("win_bell_double")
    }

    private static func register(_ name: String) {
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav") else { return }
        var sid: SystemSoundID = 0
        if AudioServicesCreateSystemSoundID(url as CFURL, &sid) == noErr {
            sounds[name] = sid
        }
    }

    private static func playBundled(_ name: String) {
        ensureRegistered()
        if let sid = sounds[name] {
            AudioServicesPlaySystemSound(sid)
        } else {
            // The WAV is not in the bundle (a pbxproj registration that did not land).
            // Fall back to the old system alert rather than winning in silence.
            AudioServicesPlaySystemSound(1025)
        }
    }
}
```

`1057` and `1104` are the exact system sound ids the game already plays for an exit and an advance (`HJGameViewModel.swift:72` and `:79` before this task) — they are moved, not chosen.

- [ ] **Step 5: Typecheck the new file on its own against the iOS 15.6 SDK.**

Catch a bad API shape now, before the file is inside the project and every other error is competing for attention:

```bash
cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam" && xcrun -sdk iphonesimulator swiftc -target arm64-apple-ios15.6-simulator -typecheck "Harbor Jam/HJSound.swift" && echo "PASS: HJSound typechecks with no diagnostics"
```

Assertion: exit 0, the `PASS` line printed, and **no** `warning:` lines above it.

- [ ] **Step 6: Retype the view model's `playSound` helper to route through `HJSound`.**

In `Harbor Jam/HJGameViewModel.swift`, replace this exact block (`:136-139` in the pre-plan file, at the bottom of the class beneath `haptic(_:)`):

```swift
    private func playSound(_ id: SystemSoundID) {
        guard soundOn else { return }
        AudioServicesPlaySystemSound(id)
    }
```

with:

```swift
    private func playSound(_ id: HJSoundID) {
        HJSound.play(id, enabled: soundOn)
    }
```

Then delete the now-unused import — line 3 of the same file, the whole line:

```swift
import AudioToolbox
```

`SystemSoundID` and `AudioServicesPlaySystemSound` were the file's only two AudioToolbox symbols; `import Foundation`, `import SwiftUI` and `import UIKit` all stay (`UIImpactFeedbackGenerator` still needs UIKit). The file will not compile until Step 7 — that is expected and is the point: the retyped parameter turns every remaining numeric call site into a compile error, so none can be missed.

- [ ] **Step 7: Convert the call sites and prove none was left numeric.**

```bash
cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam" && sed -i '' \
  -e 's/playSound(1057)/playSound(.exit)/g' \
  -e 's/playSound(1104)/playSound(.advance)/g' \
  -e 's/playSound(1025)/playSound(.win)/g' \
  "Harbor Jam/HJGameViewModel.swift" && \
grep -n "playSound(" "Harbor Jam/HJGameViewModel.swift" && \
if grep -Eq 'playSound\([0-9]' "Harbor Jam/HJGameViewModel.swift"; then \
  echo "FAIL: a numeric playSound call survived"; exit 1; else \
  echo "PASS: every playSound call names an HJSoundID"; fi
```

Assertions: exit 0, the `PASS` line, and the `grep -n` listing shows **exactly three** call sites plus the helper declaration — `playSound(.exit)` in the `.exited` branch, `playSound(.advance)` in the `.moved` branch, `playSound(.win)` in `finish(store:)`. The global `1104` substitution is written that way on purpose: it covers the case where the tug-token deletion has already removed the second `playSound(1104)` from `tapBoat` and the case where it has not, without either outcome being a silent miss.

`playSound(.win)` is the replacement for `AudioServicesPlaySystemSound(1025)` that spec §2.8 opens with. It fires on **every** clear, one star or three. The three-star variant is `.winPerfect`, which Task 11 adds here once it has `isCleanLine` — leave `finish(store:)` with the single unconditional `.win`.

- [ ] **Step 8: Balance the sound lifecycle on the view model.**

In `Harbor Jam/HJGameViewModel.swift`, `init?(mode:store:)` currently ends with these two lines:

```swift
        soundOn = store.save.soundOn
        hapticsOn = store.save.hapticsOn
```

Append one line so the block reads:

```swift
        soundOn = store.save.soundOn
        hapticsOn = store.save.hapticsOn
        HJSound.prepare()
    }

    deinit {
        HJSound.teardown()
    }
```

(That closing brace is the existing end of `init?`; the `deinit` is new and sits immediately after it, before `var boatsRemaining`.) `prepare()` must come after the `guard let g = generated else { return nil }` — as written it does, so a failed init never leaves an unbalanced client count. This is spec §2.8's "created once and cached … `AudioServicesDisposeSystemSoundID` on deinit", with the cache hoisted into `HJSound` and refcounted, because `HJGameView` builds the next level's `@StateObject` (`HJGameView.swift:19-20`) before the previous view model is released.

- [ ] **Step 9: Register all three new files in the hand-authored pbxproj.**

Three files × four places each. The ids below are the plan's centrally-assigned ones and are used by no other task. Paste as one command:

```bash
cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam" && python3 - <<'PY'
import sys

PROJ = "Harbor Jam.xcodeproj/project.pbxproj"
src = open(PROJ).read()

ITEMS = [
    # (fileRef id, buildFile id, filename, lastKnownFileType, build phase)
    ("C0DEBF000000000000000301", "C0DEBF000000000000000302", "HJSound.swift",       "sourcecode.swift", "Sources"),
    ("C0DEFA000000000000000401", "C0DEFA000000000000000402", "win_bell.wav",        "audio.wav",        "Resources"),
    ("C0DEFA000000000000000501", "C0DEFA000000000000000502", "win_bell_double.wav", "audio.wav",        "Resources"),
]

for r, b, n, t, ph in ITEMS:
    if n in src:
        print("FAIL: %s is already registered in the pbxproj" % n); sys.exit(1)

build_lines = "".join(
    "\t\t%s /* %s in %s */ = {isa = PBXBuildFile; fileRef = %s /* %s */; };\n" % (b, n, ph, r, n)
    for r, b, n, t, ph in ITEMS)
ref_lines = "".join(
    "\t\t%s /* %s */ = {isa = PBXFileReference; lastKnownFileType = %s; path = %s; sourceTree = \"<group>\"; };\n" % (r, n, t, n)
    for r, b, n, t, ph in ITEMS)
child_lines = "".join("\t\t\t\t%s /* %s */,\n" % (r, n) for r, b, n, t, ph in ITEMS)
src_lines = "".join("\t\t\t\t%s /* %s in Sources */,\n" % (b, n) for r, b, n, t, ph in ITEMS if ph == "Sources")
res_lines = "".join("\t\t\t\t%s /* %s in Resources */,\n" % (b, n) for r, b, n, t, ph in ITEMS if ph == "Resources")

EDITS = [
    ("/* End PBXBuildFile section */",     build_lines, "before"),
    ("/* End PBXFileReference section */", ref_lines,   "before"),
    ("\t\t\t\tED7ABB41533F46E128EC3724 /* HJTheme.swift */,\n",                child_lines, "after"),
    ("\t\t\t\t03001EE2CCE333ABA05D4257 /* HJTheme.swift in Sources */,\n",     src_lines,   "after"),
    ("\t\t\t\t379ED52CC4E8AA0A381B3FB1 /* Assets.xcassets in Resources */,\n", res_lines,   "after"),
]

for anchor, payload, where in EDITS:
    if src.count(anchor) != 1:
        print("FAIL: anchor found %d times, expected 1: %r" % (src.count(anchor), anchor)); sys.exit(1)
    src = src.replace(anchor, (payload + anchor) if where == "before" else (anchor + payload))

open(PROJ, "w").write(src)
print("PASS: registered HJSound.swift, win_bell.wav, win_bell_double.wav")
PY
plutil -lint "Harbor Jam.xcodeproj/project.pbxproj"
```

Assertions: the `PASS` line, then `project.pbxproj: OK` from `plutil`. The script refuses to run twice (the "already registered" guard) and refuses to guess (each anchor must appear exactly once). Anchors used: the two `End …section` markers; `ED7ABB41533F46E128EC3724 /* HJTheme.swift */,` — the single-line group-children entry, distinct from the `PBXFileReference` line, which ends in `;` not `,`, and from the Sources entry, which says `in Sources`; `03001EE2CCE333ABA05D4257 /* HJTheme.swift in Sources */,`; and `379ED52CC4E8AA0A381B3FB1 /* Assets.xcassets in Resources */,`, currently the only member of the `F115417AB24C0E0F4821A9A2 /* Resources */` phase. Adding after these anchors is safe regardless of what the `levels.json` / `HJLevelTable.swift` registration in the earlier baking task inserted around them.

- [ ] **Step 10: Build both configurations and prove the bells are actually inside the app bundle.**

A `.wav` that compiles fine but never reaches `Contents` is exactly the silent failure spec §5.3 warns about, so assert on the built product, not on the build log alone. `build/` is already gitignored (`.gitignore:2`), so a dedicated derived-data path inside it keeps this out of the commit and away from any stale sibling DerivedData directory:

```bash
cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam" && rm -rf build/task10 && \
xcodebuild -project "Harbor Jam.xcodeproj" -scheme "Harbor Jam" -configuration Debug \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath build/task10 CODE_SIGNING_ALLOWED=NO build 2>&1 | tee build/task10-debug.log | tail -5 && \
xcodebuild -project "Harbor Jam.xcodeproj" -scheme "Harbor Jam" -configuration Release \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath build/task10 CODE_SIGNING_ALLOWED=NO build 2>&1 | tee build/task10-release.log | tail -5
```

Then the checks:

```bash
cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam" && ok=1; \
for cfg in Debug Release; do \
  app="build/task10/Build/Products/$cfg-iphonesimulator/Harbor Jam.app"; \
  grep -q "BUILD SUCCEEDED" "build/task10-$(echo $cfg | tr A-Z a-z).log" || { echo "FAIL $cfg: no BUILD SUCCEEDED"; ok=0; }; \
  for w in win_bell.wav win_bell_double.wav; do \
    if [ -f "$app/$w" ]; then echo "PASS $cfg: $w is in the bundle"; \
    else echo "FAIL $cfg: $w missing from $app"; ok=0; fi; \
  done; \
done; \
if grep -E "warning:" build/task10-debug.log build/task10-release.log | grep -E "HJSound.swift|HJGameViewModel.swift"; then \
  echo "FAIL: this task's files produced warnings"; ok=0; else echo "PASS: no warnings in HJSound.swift or HJGameViewModel.swift"; fi; \
[ $ok -eq 1 ] && echo "TASK 10 BUILD CHECKS PASS" || { echo "TASK 10 BUILD CHECKS FAIL"; false; }
```

Assertion: `TASK 10 BUILD CHECKS PASS`, preceded by four `PASS … is in the bundle` lines (two files × two configurations). A missing `.wav` here means the Resources phase entry in Step 9 did not land; a `BUILD SUCCEEDED` with missing files is precisely the outcome the hand-authored pbxproj produces when only three of the four registrations are made.

- [ ] **Step 11: Commit.**

```bash
cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam" && git add tools/HarborForge/mkbell.py "Harbor Jam/win_bell.wav" "Harbor Jam/win_bell_double.wav" "Harbor Jam/HJSound.swift" "Harbor Jam/HJGameViewModel.swift" "Harbor Jam.xcodeproj/project.pbxproj" && git commit -m "$(cat <<'EOF'
Task 10: replace the system win alert with a synthesised harbour bell

Spec 2.8. tools/HarborForge/mkbell.py (stdlib wave/math/struct) synthesises
win_bell.wav and win_bell_double.wav: mono 44.1 kHz 16-bit PCM, fundamental
587 Hz with inharmonic partials at x2.0/x3.0/x4.2, 1.4 s exponential decay,
5 ms attack; the double answers a fifth higher 200 ms later.

HJSound registers both via AudioServicesCreateSystemSoundID with the bundle
URL (no AVFoundation) and disposes them in teardown(). The exit (1057) and
advance (1104) tones move behind the same switch so the two outcomes that
matter under throttle stay audibly distinct, and finish() now plays .win in
place of AudioServicesPlaySystemSound(1025).

.winPerfect is defined and playable but has no caller yet: Task 11 owns
isCleanLine and adds the single three-star call site. .blocked is silent by
design - a refused tap is the shake plus the heavy haptic.

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```


---

### Task 11: Scoring that can tell players apart

Today the star formula is `taps <= par ? 3 : (taps <= par + 2 ? 2 : 1)` (`Harbor Jam/HJSave.swift:190`) measured against `state.taps` — a counter that lives *inside* the undoable snapshot. Undo therefore refunds the score, restart zeroes it, and three stars measure whether the player noticed undo is free. This task moves the metric out of the snapshot, scales the bands with par, replaces the star gate on chapters with a levels-cleared gate, and rewrites the achievements so they stop being farmable.

**Files:**
- Modify: `Harbor Jam/HJGameViewModel.swift` (`:16-27` published/stored state, `:50-86` `tapBoat`, `:88-102` `undo`/`restart`, `:104-120` `finish`)
- Modify: `Harbor Jam/HJSave.swift` (`:4-10` record type, `:45-52` `HJSaveState`, `:104-127` achievements, `:132` save key, `:170-179` unlock helpers, `:186-200` `reportCampaignWin`, `:223-229` `applyCommonWinStats`)
- Modify: `Harbor Jam/HJModels.swift` (`:83-99` `HJChapterDef` + the seven chapter rows)
- Modify: `Harbor Jam/HJHarborView.swift` (`:93` unlock read, `:185-200` level cell)
- Test: `tools/HarborForge/ScoringChecks.swift` (new — picked up automatically by `build.sh`'s harness glob)

**Interfaces:**
- Consumes:
  - `HJEngine.tap(boatID:state:) -> HJTapOutcome` with `.blocked(reason:)` / `.anchored` (Task 2, Task 4)
  - `HJSound.play(_ id: HJSoundID, enabled: Bool)` and `HJSoundID.win` / `.winPerfect` (Task 10)
  - `HJLevelTable.campaignLevel(chapter:level:)` (Task 8) — supplies `par`, which is now strictly greater than the boat count
- Produces:
  - `struct HJProgressRecord: Codable, Equatable { var stars: Int; var bestMoves: Int }`
  - `HJSave.stars(moves: Int, par: Int) -> Int`
  - `HJSaveState.cleanLines: Set<String>`
  - `HJStore.reportCampaignWin(chapter:level:moves:par:usedUndo:boatsExited:undos:cleanLine:) -> Int`
  - `HJStore.isCleanLine(chapter:level:) -> Bool`
  - `HJChapterDef.levelsToUnlock: Int` (replaces `starsToUnlock`)
  - `HJGameViewModel.movesCommitted`, `.restartsUsed`, `.isCleanLine`
  - `HJStore.saveKey == "hbj.state.v2"`

---

- [ ] **Step 1: Rename the per-level save record and its field**

`HJLevelRecord` is now the *baked table* record type (Task 8, `HJLevelTable.swift`). The save-side type must not share the name. Run:

```bash
cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam"
sed -i '' 's/HJLevelRecord/HJProgressRecord/g; s/bestTaps/bestMoves/g' "Harbor Jam/HJSave.swift"
grep -c "HJProgressRecord\|bestMoves" "Harbor Jam/HJSave.swift"
```

Expected: a count greater than zero, and `grep -n "HJLevelRecord" "Harbor Jam/HJSave.swift"` prints nothing.

- [ ] **Step 2: Add the scaled star formula**

In `Harbor Jam/HJSave.swift`, directly above `final class HJStore: ObservableObject` (`:131`), insert:

```swift
enum HJSave {
    /// Star bands scale with par. A flat +2 window is 40% slack on a 5-move board and
    /// 7% on a 28-move one, which collapses expert and careless play into one bucket
    /// exactly where the boards get interesting.
    static func stars(moves: Int, par: Int) -> Int {
        if moves <= par { return 3 }
        if moves <= par + max(2, par / 6) { return 2 }
        return 1
    }
}
```

- [ ] **Step 3: Add `cleanLines` to the save state**

In `HJSaveState` (`:45-52`) add the stored property beside `records`:

```swift
    var cleanLines: Set<String>               // "chapter-level" cleared at par, no undo, no restart
```

and in its `init(from decoder:)` add, with the rest of the tolerant decodes:

```swift
        cleanLines = try c.decodeIfPresent(Set<String>.self, forKey: .cleanLines) ?? []
```

and in the memberwise/default initialiser: `cleanLines = []`. Every decode in this file uses `decodeIfPresent ?? default` — a non-optional field added to a `UserDefaults` Codable save struct makes the synthesized decoder throw on a missing key and silently wipes all progress.

- [ ] **Step 4: Bump the save key**

`Harbor Jam/HJSave.swift:132` — replace:

```swift
    static let saveKey = "hbj.state.v1"
```

with:

```swift
    static let saveKey = "hbj.state.v2"
```

`par` changed meaning, so every previously earned star is meaningless and a migration would be a lie. The app has not been released.

- [ ] **Step 5: Replace the chapter unlock gate**

In `Harbor Jam/HJModels.swift`, `HJChapterDef` (`:83-88`): rename `starsToUnlock` to `levelsToUnlock`. Then replace the seven rows (`:92-98`) with:

```swift
        HJChapterDef(index: 0, name: "Quiet Cove",    tagline: "Learn the ropes",        levelsToUnlock: 0),
        HJChapterDef(index: 1, name: "Fisher Wharf",  tagline: "Mind the currents",      levelsToUnlock: 12),
        HJChapterDef(index: 2, name: "Ferry Port",    tagline: "Time the crossings",     levelsToUnlock: 28),
        HJChapterDef(index: 3, name: "Tide Flats",    tagline: "Watch the water line",   levelsToUnlock: 45),
        HJChapterDef(index: 4, name: "Storm Marina",  tagline: "Chained and crowded",    levelsToUnlock: 62),
        HJChapterDef(index: 5, name: "Night Harbor",  tagline: "Lanterns on the water",  levelsToUnlock: 80),
        HJChapterDef(index: 6, name: "Grand Regatta", tagline: "Everything at once",     levelsToUnlock: 100),
```

Then in `HJSave.swift:170-179` replace `isChapterUnlocked`:

```swift
    func levelsCleared() -> Int {
        save.records.values.filter { $0.stars >= 1 }.count
    }

    func isChapterUnlocked(_ chapter: Int) -> Bool {
        guard chapter < HJCatalog.chapters.count else { return false }
        return levelsCleared() >= HJCatalog.chapters[chapter].levelsToUnlock
    }
```

The old gate was 166 of a possible 420 stars, which opened the final chapter after 56 of 140 levels — and it was tuned when three stars were unloseable. Under the new bands a competent player can be walled out by a gate that a careless one used to pass.

Update the read at `Harbor Jam/HJHarborView.swift:93` to match the new field name.

- [ ] **Step 6: Rewrite `reportCampaignWin`**

Replace `Harbor Jam/HJSave.swift:186-200` with:

```swift
    /// Report a campaign win. `moves` is the committed-move count, which undo and restart
    /// do NOT refund — see HJGameViewModel.movesCommitted. Returns earned stars.
    func reportCampaignWin(chapter: Int, level: Int, moves: Int, par: Int,
                           usedUndo: Bool, boatsExited: Int, undos: Int,
                           cleanLine: Bool) -> Int {
        let stars = HJSave.stars(moves: moves, par: par)
        let key = "\(chapter)-\(level)"
        let old = save.records[key]
        let firstClear = old == nil
        if firstClear || stars > (old?.stars ?? 0) || moves < (old?.bestMoves ?? Int.max) {
            save.records[key] = HJProgressRecord(stars: max(stars, old?.stars ?? 0),
                                                 bestMoves: min(moves, old?.bestMoves ?? Int.max))
        }
        if cleanLine { save.cleanLines.insert(key) }
        // Cumulative stats advance on FIRST clear only. They used to advance on every
        // clear, so 18 of the 20 achievements were farmable by replaying the 3-boat
        // opening level.
        if firstClear {
            applyCommonWinStats(moves: moves, usedUndo: usedUndo, boatsExited: boatsExited, undos: undos)
            save.stats.levelsCleared += 1
        }
        refreshAchievements()
        persist()
        return stars
    }

    func isCleanLine(chapter: Int, level: Int) -> Bool {
        save.cleanLines.contains("\(chapter)-\(level)")
    }
```

and `applyCommonWinStats` (`:223-229`) with:

```swift
    private func applyCommonWinStats(moves: Int, usedUndo: Bool, boatsExited: Int, undos: Int) {
        save.stats.totalTaps += moves
        save.stats.totalUndos += undos
        save.stats.boatsExited += boatsExited
        if !usedUndo { save.stats.winsWithoutUndo += 1 }
    }
```

`tugsUsed` is gone from both signatures — the tug economy was deleted in Task 3. Update the `reportDailyWin` call site accordingly.

- [ ] **Step 7: Rewrite the achievement list**

Replace the `tugs_15`, `boats_1500` and `taps_2000` entries in `HJAchievements.all` (`:104-127`). The first names a deleted mechanic; the other two are unreachable — a complete perfect playthrough of the old corpus exits exactly 1 170 boats and spends exactly 1 170 moves. Replace them with three that measure the new skill:

```swift
        HJAchievement(id: "clean_1", title: "Clean Line", detail: "Clear a level at par with no undo and no restart") { !$0.cleanLines.isEmpty },
        HJAchievement(id: "clean_25", title: "Steady Pilot", detail: "Clear 25 levels at par with no undo and no restart") { $0.cleanLines.count >= 25 },
        HJAchievement(id: "clean_ch0", title: "Cove Clean", detail: "Clean-line every level in Quiet Cove") { save in
            (0..<HJCatalog.levelsPerChapter).allSatisfy { save.cleanLines.contains("0-\($0)") }
        },
```

- [ ] **Step 8: Move the metric out of the snapshot in the view model**

In `Harbor Jam/HJGameViewModel.swift` add beside `undosUsed` (`:24`):

```swift
    private(set) var movesCommitted = 0
    private(set) var restartsUsed = 0

    var isCleanLine: Bool { movesCommitted <= par && undosUsed == 0 && restartsUsed == 0 }
```

In `tapBoat` (`:66-85`), increment it once for every outcome except `.invalid` — including `.blocked` and `.anchored`, which now spend a tick:

```swift
        let outcome = HJEngine.tap(boatID: id, state: &state)
        if outcome != .invalid { movesCommitted += 1 }
```

In `restart()` (`:94-102`) add `restartsUsed += 1` alongside the existing `undosUsed += 1`.

**Do not touch `state.taps`.** It stays inside `HJBoardState` because it is the world phase that the tide (`HJEngine.swift:131`) and the current-lane flips read; an undo that did not rewind it would desynchronise the harbor from the board the player is looking at. `movesCommitted` is a separate counter with a separate job: `taps` is *when the world is*, `movesCommitted` is *what the player spent*. Undo and restart stay free and unlimited; they simply stop refunding the score.

- [ ] **Step 9: Score the win on `movesCommitted` and sound the right bell**

In `finish(store:)` (`:104-120`) replace the campaign branch:

```swift
        case .campaign(let chapter, let level):
            let clean = isCleanLine
            earnedStars = store.reportCampaignWin(chapter: chapter, level: level,
                                                  moves: movesCommitted, par: par,
                                                  usedUndo: undosUsed > 0,
                                                  boatsExited: totalBoats,
                                                  undos: undosUsed,
                                                  cleanLine: clean)
            HJSound.play(clean ? .winPerfect : .win, enabled: soundOn)
```

and the daily branch's star computation with `earnedStars = HJSave.stars(moves: movesCommitted, par: par)`. Remove the now-duplicated `playSound(1025)` at `:107`.

- [ ] **Step 10: Show the Clean Line pennant**

In `Harbor Jam/HJHarborView.swift:185-200`, inside the level cell, add above the star row:

```swift
                    if store.isCleanLine(chapter: chapter, level: level) {
                        HJPennantShape()
                            .fill(HJTheme.gold)
                            .frame(width: 10, height: 12)
                    }
```

and add `HJPennantShape` to `Harbor Jam/HJTheme.swift` beside the other custom shapes — a triangular burgee, drawn with `Path`, no SF Symbol.

- [ ] **Step 11: Write the harness checks**

Create `tools/HarborForge/ScoringChecks.swift`:

```swift
import Foundation

/// Star bands are pure arithmetic, so they are checked directly rather than through a board.
func forgeRunScoringChecks() -> Int {
    var failures = 0
    func expect(_ ok: Bool, _ what: String) {
        print(ok ? "PASS  \(what)" : "FAIL  \(what)")
        if !ok { failures += 1 }
    }

    expect(HJSave.stars(moves: 10, par: 10) == 3, "par exactly earns three stars")
    expect(HJSave.stars(moves: 9,  par: 10) == 3, "under par earns three stars")
    expect(HJSave.stars(moves: 12, par: 10) == 2, "par + 2 earns two stars on a small board")
    expect(HJSave.stars(moves: 13, par: 10) == 1, "par + 3 drops to one star on a small board")
    // The whole point of scaling: a 28-move board tolerates 4, not 2.
    expect(HJSave.stars(moves: 32, par: 28) == 2, "par + 4 still earns two stars on a large board")
    expect(HJSave.stars(moves: 33, par: 28) == 1, "par + 5 drops to one star on a large board")

    if failures == 0 { print("SCORING OK"); return 0 }
    print("SCORING FAILED — \(failures) assertion(s)")
    return 1
}
```

and add `case "scoring": exit(Int32(forgeRunScoringChecks()))` to the `switch` in `tools/HarborForge/main.swift`, immediately above `default:`.

- [ ] **Step 12: Run the checks**

```bash
cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam"
./tools/HarborForge/build.sh && ./tools/HarborForge/harborforge scoring
echo "exit=$?"
```

Expected: six `PASS` lines, `SCORING OK`, `exit=0`.

- [ ] **Step 13: Build the app**

```bash
cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam"
xcodebuild -project "Harbor Jam.xcodeproj" -scheme "Harbor Jam" \
  -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug build 2>&1 \
  | grep -E "BUILD SUCCEEDED|BUILD FAILED|error:"
```

Expected: `** BUILD SUCCEEDED **` and no `error:` lines.

- [ ] **Step 14: Commit**

```bash
cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam"
git add "Harbor Jam/HJGameViewModel.swift" "Harbor Jam/HJSave.swift" "Harbor Jam/HJModels.swift" \
        "Harbor Jam/HJHarborView.swift" "Harbor Jam/HJTheme.swift" tools/HarborForge/ScoringChecks.swift \
        tools/HarborForge/main.swift
git commit -m "Scoring: a metric undo cannot refund

movesCommitted lives on the view model, not inside the undoable snapshot, so
undo and restart stay free and unlimited without returning the score. Star
bands scale with par instead of a flat +2 window that was 7% slack on a
28-move board. Chapters unlock on levels cleared rather than 166 of 420 stars,
which opened the finale after 56 of 140 levels. Clean Line — par, no undo, no
restart — is the one signal that cannot be farmed, and it sounds the second
bell.

Cumulative stats now advance on first clear only; 18 of the 20 achievements
were farmable by replaying the opening level, and two of them were unreachable
by a perfect playthrough.

Co-Authored-By: Claude <noreply@anthropic.com>"
```


---

### Task 12: Copy that the new rules made true

Everything the game *tells* the player is currently a description of the old game. `"…sails straight
ahead"` is false the moment throttle bounds a move, `"Undo and restart are always free"` is a
half-truth now that neither refunds the move counter, the codex still documents a mechanic that no
longer exists, and the Daily card promises a freshly generated board when the board now comes out of
a baked pool. This task replaces the strings — no rules change, no engine change.

**Files:**
- `Harbor Jam/HJGameView.swift` — the onboarding card deck (`HJOnboardingOverlay.steps`, currently lines 258-262)
- `Harbor Jam/HJModels.swift` — the `HJCatalog.chapters` taglines (currently lines 92-98)
- `Harbor Jam/HJMoreView.swift` — the Harbor Manual codex (`codexEntries`, currently lines 148-193, plus the doc comment at 132-134)
- `Harbor Jam/HJDailyView.swift` — the Daily hero card (lines 7-8 and 30-36)

**Interfaces:**

*Consumes* (every symbol below is produced by a lower-numbered task, or already exists on `main`):
- `HJLevelTable.dailyLevel(dayKey: Int) -> HJGeneratedLevel?` — the baked-table loader
- `HJGeneratedLevel { var start: HJBoardState; var par: Int; var solutionOrder: [Int] }`
- `HJBoardState.boats: [HJBoat]` (`Harbor Jam/HJEngine.swift:7`)
- `HJChapterDef { var index: Int; var name: String; var tagline: String; var levelsToUnlock: Int }` — Task 11 renamed `starsToUnlock` to `levelsToUnlock`; this task edits only the `tagline:` argument on each row and never re-types the number
- Existing art, unchanged: `HJArrowShape`, `HJWaveShape`, `HJPulseShape`, `HJTugShape` (`Harbor Jam/HJTheme.swift:218`, reused as the basin tile per spec §2.4), `HJTheme.navy/seafoam/buoyRed/driftwood`, `HJTheme.display/body/mono`
- The tug HUD chip is already gone from `HJGameView.swift` (earlier task). This task does not touch `hudRow`, `winCard`, or anything outside the `steps` array in that file.

*Produces:* no new types, no new signatures, no pbxproj change. String content, one new private computed property `HJDailyView.todayBoard: HJGeneratedLevel?`, and one extra `if let` row in the Daily hero card.

---

- [ ] **Step 1: Replace the three onboarding cards with five (throttle and basins added)**

  `HJOnboardingOverlay` already sizes its page dots from `steps.count` (`HJGameView.swift:292`) and
  already labels the last button `"Set Sail"` via `step < steps.count - 1` (`:306`, `:308`), so
  growing the array from 3 to 5 needs no other edit in that file.

  ```bash
  python3 - <<'PY'
  import sys
  p = "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam/Harbor Jam/HJGameView.swift"
  old = r'''    private let steps: [(String, String)] = [
          ("Tap a Boat", "Tap any boat and it sails straight ahead in the direction of its bow. If the water is clear all the way, it leaves the harbor."),
          ("Blocked Paths", "A boat blocked by another slides up to it and bumps. Clear the way first — order is everything."),
          ("Stars and Par", "Clear every boat. Match par for 3 stars. Undo and restart are always free."),
      ]'''.replace("\n      ", "\n    ")
  new = r'''    private let steps: [(String, String)] = [
        ("Tap a Boat", "Tap any boat and it sails forward along its bow — never sideways, never astern. Carry it past the edge of the board and it has left the harbor for good."),
        ("Blocked Paths", "A hull, a sandbar or the ferry stops a boat early: it slides up to the obstacle and rests there. Every tap counts as a move, even one that gets nowhere, and the tide, the ferry and the currents all move on around you."),
        ("Stars and Par", "Clear every boat. Par is a line the harbormaster has already sailed — match it for 3 stars. Undo and restart cost nothing to use, but neither one gives you the move back."),
        ("Read the Throttle", "The dots beside a bow are that boat's throttle: one, two or three. A tap advances it exactly that many cells, or fewer if something is in the way. Where a boat comes to rest is your choice — and a boat parked in the wrong lane blocks the boat behind it."),
        ("Turning Basins", "A ringed cell of calm water turns a boat around. A boat whose bow reaches a basin stops on it and swings a full 180 degrees. It is the only way to send a hull back the way it came."),
    ]'''
  s = open(p, encoding="utf-8").read()
  if s.count(old) != 1:
      print("FAIL: expected exactly 1 occurrence of the old steps array, found %d" % s.count(old))
      sys.exit(1)
  open(p, "w", encoding="utf-8").write(s.replace(old, new))
  print("PASS: onboarding now teaches bow, blocking + world tick, scoring, throttle, basins")
  PY
  ```

- [ ] **Step 2: Rewrite the five chapter taglines that the new rules made true or false**

  Each replacement matches the `tagline: "…"` argument only, so the `levelsToUnlock:` values Task 3
  and Task 11 set on those same lines are never touched. Chapter 0 (`"Learn the ropes"`) and
  chapter 6 (`"Everything at once"`) are still accurate and are deliberately left alone.

  ```bash
  python3 - <<'PY'
  import sys
  p = "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam/Harbor Jam/HJModels.swift"
  pairs = [
      (r'tagline: "Mind the currents"',     r'tagline: "The water moves on its own"'),
      (r'tagline: "Time the crossings"',    r'tagline: "The ferry never waits for you"'),
      (r'tagline: "Watch the water line"',  r'tagline: "Low tide turns the shallows to stone"'),
      (r'tagline: "Chained and crowded"',   r'tagline: "Buoy chains and a turning tide"'),
      (r'tagline: "Lanterns on the water"', r'tagline: "Lanterns, drift and a moving ferry"'),
  ]
  s = open(p, encoding="utf-8").read()
  for old, new in pairs:
      if s.count(old) != 1:
          print("FAIL: expected exactly 1 occurrence of %s, found %d" % (old, s.count(old)))
          sys.exit(1)
      s = s.replace(old, new)
  open(p, "w", encoding="utf-8").write(s)
  print("PASS: 5 taglines rewritten, levelsToUnlock values untouched")
  PY
  ```

- [ ] **Step 3: Verify the tagline edit changed nothing but taglines**

  ```bash
  cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam" && git diff --unified=0 -- "Harbor Jam/HJModels.swift" | grep -E '^[+-][^+-]' | grep -v 'tagline:' | grep -c . | xargs -I{} sh -c 'if [ {} -ne 0 ]; then echo "FAIL: {} changed line(s) in HJModels.swift do not carry a tagline"; exit 1; else echo "PASS: only tagline-bearing lines changed"; fi'
  ```

- [ ] **Step 4: Rewrite the codex — Boats & Bows through Buoy Chains, with Throttle and Turning Basins replacing The Tug**

  This replaces one contiguous region of `codexEntries` (`HJMoreView.swift:150-186`). The `Barges`
  entry that follows it is correct as written (barges are still exempt from the current push and
  still block lane residents) and is left in place.

  ```bash
  python3 - <<'PY'
  import sys
  p = "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam/Harbor Jam/HJMoreView.swift"
  old = r'''        codexEntry(title: "Boats & Bows",
                     text: "Every boat sails only forward, in the direction of its pointed bow. A clear line to the edge means it exits for good. Blocked boats bump and wait.") {
              AnyView(HJArrowShape(direction: .east)
                  .stroke(HJTheme.navy, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                  .frame(width: 26, height: 26))
          }
          codexEntry(title: "Currents",
                     text: "Arrow lanes mark flowing water. A boat that ends its slide inside a lane is pushed one cell sideways — plan around the drift, or use it as a shortcut.") {
              AnyView(HJWaveShape()
                  .stroke(HJTheme.navy, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                  .frame(width: 26, height: 16))
          }
          codexEntry(title: "Tides",
                     text: "The tide turns every 3 moves. At low tide, sandy shallows harden into solid bars no hull can cross. At high tide they flood over and open up.") {
              AnyView(HJPulseShape()
                  .stroke(HJTheme.navy, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                  .frame(width: 26, height: 18))
          }
          codexEntry(title: "The Ferry",
                     text: "The grey ferry crosses its row on a fixed schedule, advancing after each of your moves and wrapping around. It never stops for anyone — time your crossings.") {
              AnyView(Rectangle()
                  .fill(HJTheme.navy.opacity(0.7))
                  .frame(width: 26, height: 12)
                  .cornerRadius(3))
          }
          codexEntry(title: "Buoy Chains",
                     text: "A boat wearing a red buoy is anchored in place. Its key boat — somewhere in the harbor — must exit first to cast it loose.") {
              AnyView(Circle()
                  .fill(HJTheme.buoyRed)
                  .frame(width: 18, height: 18))
          }
          codexEntry(title: "The Tug",
                     text: "Tug tokens rotate any free boat 90 degrees in place, when its new footprint fits. Scarce and precious — spend them wisely.") {
              AnyView(HJTugShape()
                  .stroke(HJTheme.navy, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                  .frame(width: 22, height: 22))
          }'''.replace("\n      ", "\n    ")
  new = r'''        codexEntry(title: "Boats & Bows",
                   text: "Every boat sails only forward, in the direction of its pointed bow — never sideways, never astern. A boat that carries its last cell past the edge has left the harbor for good.") {
            AnyView(HJArrowShape(direction: .east)
                .stroke(HJTheme.navy, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 26, height: 26))
        }
        codexEntry(title: "Throttle",
                   text: "The dots printed beside a hull's bow are its throttle: one, two or three. A tap advances the boat exactly that many cells, or stops it early against the first hull, sandbar or ferry in the way. Where a boat comes to rest is a decision, not an accident.") {
            AnyView(HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle()
                        .fill(HJTheme.navy)
                        .frame(width: 6, height: 6)
                }
            })
        }
        codexEntry(title: "Turning Basins",
                   text: "A ringed cell of calm water. A boat whose bow reaches a basin stops on it and swings a full 180 degrees, facing back the way it came. It always fits — a hull turned end for end covers exactly the same cells.") {
            AnyView(HJTugShape()
                .stroke(HJTheme.navy, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 22, height: 22))
        }
        codexEntry(title: "Currents",
                   text: "Arrow lanes mark flowing water. After every move you make — even a tap that gets nowhere — every boat sitting in a lane is pushed one cell sideways if there is room for it, and each lane reverses its push every few moves. Barges are too heavy to shift.") {
            AnyView(HJWaveShape()
                .stroke(HJTheme.navy, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 26, height: 16))
        }
        codexEntry(title: "Tides",
                   text: "The tide turns every 3 moves, and every tap is a move — even one that gets nowhere. At low tide the sandy shallows harden into bars no hull can cross; at high tide they flood over and open up.") {
            AnyView(HJPulseShape()
                .stroke(HJTheme.navy, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 26, height: 18))
        }
        codexEntry(title: "The Ferry",
                   text: "The grey ferry crosses its row after every single move of yours, bump or not, and wraps around at the far edge. It never stops for anyone — but it can never leave the harbor frozen either.") {
            AnyView(Rectangle()
                .fill(HJTheme.navy.opacity(0.7))
                .frame(width: 26, height: 12)
                .cornerRadius(3))
        }
        codexEntry(title: "Buoy Chains",
                   text: "A boat wearing a red buoy is anchored in place. Its key boat — somewhere in the harbor — must leave before the chain drops. Tapping an anchored boat still spends a move, and the harbor still moves around you.") {
            AnyView(Circle()
                .fill(HJTheme.buoyRed)
                .frame(width: 18, height: 18))
        }'''
  s = open(p, encoding="utf-8").read()
  if s.count(old) != 1:
      print("FAIL: expected exactly 1 occurrence of the old codex region, found %d" % s.count(old))
      sys.exit(1)
  open(p, "w", encoding="utf-8").write(s.replace(old, new))
  print("PASS: codex rewritten — Tug entry gone, Throttle and Turning Basins added")
  PY
  ```

- [ ] **Step 5: Fix the codex layout comment, which still counts seven entries**

  ```bash
  python3 - <<'PY'
  import sys
  p = "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam/Harbor Jam/HJMoreView.swift"
  old = r'''    /// The seven manual entries stack on iPhone (unchanged) and go two-up on a'''
  new = r'''    /// The eight manual entries stack on iPhone (unchanged) and go two-up on a'''
  s = open(p, encoding="utf-8").read()
  if s.count(old) != 1:
      print("FAIL: expected exactly 1 occurrence of the codex layout comment, found %d" % s.count(old))
      sys.exit(1)
  open(p, "w", encoding="utf-8").write(s.replace(old, new))
  print("PASS: codex layout comment now says eight")
  PY
  ```

- [ ] **Step 6: Point `HJDailyView` at the baked pool by date**

  The screen currently only hands a `dayKey` to `HJGameView` and says nothing about the board.
  Reading the record itself lets the card advertise the exact board that will open, and it is the
  read that proves the pool is wired by date.

  ```bash
  python3 - <<'PY'
  import sys
  p = "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam/Harbor Jam/HJDailyView.swift"
  old = r'''    private var doneToday: Bool { store.save.bestDailyTaps[String(todayKey)] != nil }'''
  new = r'''    private var doneToday: Bool { store.save.bestDailyTaps[String(todayKey)] != nil }

    /// The Daily is no longer generated on the device: the date indexes the baked
    /// pool, so the board this card advertises is exactly the board that opens.
    private var todayBoard: HJGeneratedLevel? { HJLevelTable.dailyLevel(dayKey: todayKey) }'''
  s = open(p, encoding="utf-8").read()
  if s.count(old) != 1:
      print("FAIL: expected exactly 1 occurrence of the doneToday property, found %d" % s.count(old))
      sys.exit(1)
  open(p, "w", encoding="utf-8").write(s.replace(old, new))
  print("PASS: HJDailyView reads the baked pool by date")
  PY
  ```

- [ ] **Step 7: Replace the Daily promise with what the pool actually guarantees**

  ```bash
  python3 - <<'PY'
  import sys
  p = "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam/Harbor Jam/HJDailyView.swift"
  old = r'''                            Text("A fresh harbor every day")
                                  .font(HJTheme.display(18))
                                  .foregroundColor(.white)
                              Text("One handcrafted-feel jam, seeded by the date.\nSame board for everyone, once per day.")
                                  .font(HJTheme.body(12))
                                  .foregroundColor(Color.white.opacity(0.75))
                                  .multilineTextAlignment(.center)'''.replace("\n      ", "\n    ")
  new = r'''                            Text("A different harbor every day")
                                .font(HJTheme.display(18))
                                .foregroundColor(.white)
                            Text("The date picks today's board from a pool of harbors we have already sailed and solved.\nSame board for everyone, and over a year before one comes round again.")
                                .font(HJTheme.body(12))
                                .foregroundColor(Color.white.opacity(0.75))
                                .multilineTextAlignment(.center)
                            if let board = todayBoard {
                                Text("\(board.start.boats.count) boats · par \(board.par)")
                                    .font(HJTheme.mono(12))
                                    .foregroundColor(HJTheme.seafoam)
                            }'''
  s = open(p, encoding="utf-8").read()
  if s.count(old) != 1:
      print("FAIL: expected exactly 1 occurrence of the Daily promise block, found %d" % s.count(old))
      sys.exit(1)
  open(p, "w", encoding="utf-8").write(s.replace(old, new))
  print("PASS: Daily card promises the pool, and prints today's boat count and par")
  PY
  ```

- [ ] **Step 8: Assert the shipped pool is large enough for the sentence "over a year before one comes round again"**

  The card now makes a numeric promise. This is the check that the promise is backed by the baked
  table: it must exit 0 and report a `daily` array of at least 400 records.

  ```bash
  python3 - <<'PY'
  import json, sys
  p = "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam/Harbor Jam/levels.json"
  table = json.load(open(p, encoding="utf-8"))
  n = len(table["daily"])
  print("daily pool size: %d" % n)
  if n < 400:
      print("FAIL: the Daily card promises over a year without a repeat; that needs >= 400 boards, found %d" % n)
      sys.exit(1)
  print("PASS: daily pool >= 400 boards, copy is backed by the table")
  PY
  ```

- [ ] **Step 9: Assert every retired string is gone from the sources**

  ```bash
  cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam" && if grep -RnF --include="*.swift" -e "sails straight ahead" -e "Undo and restart are always free" -e "Tug tokens" -e "A fresh harbor every day" -e "seeded by the date" -e "Mind the currents" -e "Chained and crowded" -e "Time the crossings" -e "Watch the water line" -e "Lanterns on the water" -e "The seven manual entries" "Harbor Jam"; then echo "FAIL: stale copy above still ships"; exit 1; else echo "PASS: no stale copy in any Swift source"; fi
  ```

- [ ] **Step 10: Debug build, zero warnings**

  ```bash
  cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam" && xcodebuild -project "Harbor Jam.xcodeproj" -scheme "Harbor Jam" -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath build/dd build > build/hj12-debug.log 2>&1; W=$(grep -c " warning:" build/hj12-debug.log); echo "warnings: $W"; if grep -q "BUILD SUCCEEDED" build/hj12-debug.log && [ "$W" -eq 0 ]; then echo "PASS: Debug build clean"; else tail -40 build/hj12-debug.log; echo "FAIL: Debug build"; exit 1; fi
  ```

- [ ] **Step 11: Release build, zero warnings**

  ```bash
  cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam" && xcodebuild -project "Harbor Jam.xcodeproj" -scheme "Harbor Jam" -configuration Release -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath build/dd build > build/hj12-release.log 2>&1; W=$(grep -c " warning:" build/hj12-release.log); echo "warnings: $W"; if grep -q "BUILD SUCCEEDED" build/hj12-release.log && [ "$W" -eq 0 ]; then echo "PASS: Release build clean"; else tail -40 build/hj12-release.log; echo "FAIL: Release build"; exit 1; fi
  ```

- [ ] **Step 12: Commit**

  ```bash
  cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam" && git add "Harbor Jam/HJGameView.swift" "Harbor Jam/HJModels.swift" "Harbor Jam/HJMoreView.swift" "Harbor Jam/HJDailyView.swift" && git commit -m "$(cat <<'EOF'
Copy: say what the game now actually does

Onboarding goes from three cards to five: the bow card no longer claims a boat
sails straight ahead until it leaves, the blocking card states that a bump still
costs a move and still ticks the tide, ferry and currents, the scoring card says
undo and restart are free to use but do not give the move back, and two new
cards teach throttle and turning basins.

Codex: adds Throttle and Turning Basins (the Tug entry is gone with the
mechanic), and rewrites Currents, Tides, The Ferry and Buoy Chains around the
every-tap world tick and the lane reversal.

Chapter taglines now name the mechanic each chapter really runs. Daily reads the
baked pool by date and advertises today's boat count and par instead of
promising a board generated fresh from the date.

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
  ```


---

### Task 13: Definition of done

Closes the plan. **No new app behaviour is written in this task.** It (a) re-runs the offline harness against the *shipped* `Harbor Jam/levels.json` and enforces spec §6 as hard, non-zero-exit gates, (b) records the before/after in the repo, (c) proves both build configurations are clean and the bundle is still store-shaped, and (d) updates the two portfolio ledgers — including the explicit statement that **the app is not submittable until store screenshots and the App Store review notes are redone**, because the core verb changed.

Repo root for every command below: `/Users/vik/Documents/development/for_human_review_apps/Harbor Jam`

**Files:**
- create `tools/HarborForge/Verify/main.swift`
- create `tools/HarborForge/SHIPPED.md` (written by the tool, not by hand)
- edit `/Users/vik/Documents/development/APP_TRACKER.md`
- edit `/Users/vik/Documents/development/for_human_review_apps/APP_DESCRIPTIONS.md`
- reads only, never edits: `Harbor Jam/HJModels.swift`, `Harbor Jam/HJEngine.swift`, `Harbor Jam/HJLevelTable.swift`, `Harbor Jam/levels.json`, `Harbor Jam/Info.plist`, `Harbor Jam.xcodeproj/project.pbxproj`, `tools/HarborForge/BASELINE.md`

**pbxproj object ids used by this task: none.** Task 13 registers no new file in the Xcode target — `tools/` is outside the app target and `SHIPPED.md` is documentation. Do not touch `Harbor Jam.xcodeproj/project.pbxproj` in this task.

**Interfaces:**

*Consumes* (all defined in lower-numbered tasks; this task defines no app symbol and changes no engine behaviour):
```
HJBoardState                                     // incl. var basins: [HJCell]; no tugTokens
  var gridW, gridH: Int; var boats: [HJBoat]; var exitedIDs: [Int]
  var currents: [HJCurrentLane]; var ferry: HJFerry?
  var tideEnabled, tideHigh: Bool; var taps: Int; var isCleared: Bool
HJBoat            var id, x, y: Int; var bow: HJDirection; var throttle: Int
HJCurrentLane     var period: Int
HJMovePreview     var exits: Bool; var distance: Int
HJTapOutcome      case exited/moved/blocked(reason:)/anchored/invalid   (Equatable)
HJEngine.preview(boatID: Int, state: HJBoardState) -> HJMovePreview
HJEngine.tap(boatID: Int, state: inout HJBoardState) -> HJTapOutcome
HJLevelRecord     struct { var par: Int; var witness: [Int]; var start: HJBoardState }  (Codable)
HJLevelTableFile  struct { var version: Int; var campaign: [String: HJLevelRecord]; var daily: [HJLevelRecord] }  (Codable)
Harbor Jam/levels.json                           // the shipped, baked corpus
tools/HarborForge/BASELINE.md                    // the committed pre-change measurement
```

*Produces* (no Swift symbol reaches the app target):
```
tools/HarborForge/Verify/main.swift    // executable `hjverify`, top-level code
tools/HarborForge/SHIPPED.md           // generated; the after-side of BASELINE.md
```

---

- [ ] **Step 1: Confirm the preconditions — clean tree, baked corpus present, baseline committed.**

```bash
cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam"
git status --porcelain
test -f "Harbor Jam/levels.json"      && echo "PASS levels.json present"      || { echo "FAIL levels.json missing"; exit 1; }
test -f "tools/HarborForge/BASELINE.md" && echo "PASS BASELINE.md present"    || { echo "FAIL BASELINE.md missing"; exit 1; }
git log --oneline -1 -- "tools/HarborForge/BASELINE.md"
```

`git status --porcelain` must print nothing. If it prints anything, stop: Task 13 measures the *shipped* tree, and an uncommitted edit means the corpus and the engine you are about to gate are not the ones in HEAD. Both `test` lines must print PASS.

- [ ] **Step 2: Prove the three engine/data sources still compile as plain Swift with no UI framework.**

The verifier links `HJModels.swift`, `HJEngine.swift` and `HJLevelTable.swift` outside Xcode. If any of them has acquired a `import SwiftUI` / `import UIKit` / `import AudioToolbox`, the harness can no longer be built and the gate below is unrunnable.

```bash
cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam"
grep -h "^import" "Harbor Jam/HJModels.swift" "Harbor Jam/HJEngine.swift" "Harbor Jam/HJLevelTable.swift" \
  | sort -u | tee /tmp/hj_imports.txt
grep -vE "^import (Foundation|CoreGraphics)$" /tmp/hj_imports.txt \
  && { echo "FAIL harness sources import a UI framework"; exit 1; } \
  || echo "PASS harness sources are Foundation-only"
```

Expect the final line to be `PASS harness sources are Foundation-only`. (`grep -v` exits 1 when it filters everything out, which is the success path here.)

- [ ] **Step 3: Write the shipped-corpus verifier.**

Create `tools/HarborForge/Verify/main.swift` with exactly this content. It lives in its own `Verify/` subdirectory so its `main.swift` cannot collide with the forge's own `main.swift`.

```bash
mkdir -p "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam/tools/HarborForge/Verify"
```

```swift
import Foundation

// ===========================================================================
// Harbor Jam — shipped-corpus verifier.
//
// Built with plain swiftc against the SHIPPED Harbor Jam/HJModels.swift,
// HJEngine.swift and HJLevelTable.swift. It reads the SHIPPED
// Harbor Jam/levels.json and enforces every clause of spec section 6 as a
// hard gate. Any failing gate makes the process exit 1.
//
// Usage:
//   hjverify <levels.json> [--no-freeze] [--freeze-only] [--shard i/n]
//            [--out <freeze-log>] [--freeze-log <merged-log>]
//            [--markdown <SHIPPED.md>] [--json <metrics.json>]
// ===========================================================================

// ------------------------------------------------------------ gate constants
let kRollouts           = 200
let kFreezeNodeCap      = 2_000_000
let kMinCampaign        = 140
let kMinDaily           = 400
let kMaxGrid            = 8
let kMaxBoats           = 10
let kMaxZeroThoughtRate = 0.15
let kMinMedianRatio     = 1.6

// Pre-throttle measurements, quoted from
// docs/superpowers/specs/2026-07-28-harbor-jam-throttle-design.md section 1.
let kBaselineZeroThought = 0.9663
let kBaselineDeadLevels  = 21

// ----------------------------------------------------------------- utilities
func fnv1a(_ s: String) -> UInt64 {
    var h: UInt64 = 0xcbf2_9ce4_8422_2325
    for b in s.utf8 { h ^= UInt64(b); h = h &* 0x0000_0100_0000_01b3 }
    return h
}

struct VFRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed }
    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func below(_ n: Int) -> Int { n <= 1 ? 0 : Int(next() % UInt64(n)) }
}

func median(_ xs: [Double]) -> Double {
    if xs.isEmpty { return 0 }
    let s = xs.sorted()
    let m = s.count / 2
    return s.count % 2 == 1 ? s[m] : (s[m - 1] + s[m]) / 2
}

func pct(_ x: Double) -> String { String(format: "%.2f%%", x * 100) }
func f2(_ x: Double) -> String { String(format: "%.2f", x) }

// ------------------------------------------------------------- board wrapper
struct Board {
    let key: String          // "C:<campaign key>" or "D:<index>"
    let rec: HJLevelRecord
    let isDaily: Bool
    var boatCount: Int { rec.start.boats.count }
}

// -------------------------------------------------- canonical / freeze keys
// Same canonical hash the bake search used (spec 2.5): boats sorted by id
// (x, y, bow, throttle), tideHigh, ferry.x, taps % lcm(lane periods).
func lanePeriodLCM(_ s: HJBoardState) -> Int {
    func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }
    var l = 1
    for lane in s.currents where lane.period > 0 {
        l = l / gcd(l, lane.period) * lane.period
        if l > 5040 { return 5040 }
    }
    return max(1, l)
}

func canonicalKey(_ s: HJBoardState, mod: Int) -> UInt64 {
    var out = ""
    for b in s.boats.sorted(by: { $0.id < $1.id }) {
        out += "\(b.id),\(b.x),\(b.y),\(b.bow.rawValue),\(b.throttle);"
    }
    out += "|T\(s.tideHigh ? 1 : 0)|F\(s.ferry?.x ?? -1)|P\(mod > 0 ? s.taps % mod : 0)"
    return fnv1a(out)
}

// Board content only — deliberately excludes `taps`, so "nothing happened"
// means nothing on the water moved, not merely that the counter stood still.
func boardSignature(_ s: HJBoardState) -> String {
    var out = ""
    for b in s.boats.sorted(by: { $0.id < $1.id }) {
        out += "\(b.id),\(b.x),\(b.y),\(b.bow.rawValue);"
    }
    out += "|E\(s.exitedIDs.count)|T\(s.tideHigh ? 1 : 0)|F\(s.ferry?.x ?? -1)"
    return out
}

/// A state where no tap has any effect: not cleared, and every legal tap
/// leaves the board signature identical.
func isFrozen(_ s: HJBoardState) -> Bool {
    if s.isCleared { return false }
    let sig = boardSignature(s)
    for b in s.boats {
        var t = s
        if HJEngine.tap(boatID: b.id, state: &t) == .invalid { continue }
        if boardSignature(t) != sig { return false }
    }
    return true
}

// -------------------------------------------------------------- gate 3: replay
struct ReplayResult { let ok: Bool; let detail: String }

func replayWitness(_ b: Board) -> ReplayResult {
    if b.rec.witness.count != b.rec.par {
        return ReplayResult(ok: false, detail: "witness length \(b.rec.witness.count) != par \(b.rec.par)")
    }
    var s = b.rec.start
    for (i, id) in b.rec.witness.enumerated() {
        let outcome = HJEngine.tap(boatID: id, state: &s)
        if outcome == .invalid {
            return ReplayResult(ok: false, detail: "tap \(i) on boat \(id) returned .invalid")
        }
    }
    if !s.isCleared {
        return ReplayResult(ok: false, detail: "witness ended with \(s.boats.count) boat(s) still berthed")
    }
    return ReplayResult(ok: true, detail: "")
}

// ------------------------------------------------------- gate 5: zero thought
// "Tap anything that exits; otherwise tap anything that advances; otherwise
// tap anything at all." The only freedom is the tie-break, so it is randomised
// over kRollouts seeded runs. A board counts against us if ANY rollout clears
// within par — i.e. we ask whether a player who never thinks can stumble into
// three stars, not whether they usually do.
func zeroThoughtThreeStars(_ b: Board) -> Bool {
    let seedBase = fnv1a(b.key)
    for r in 0..<kRollouts {
        var rng = VFRandom(seed: seedBase &+ UInt64(r) &* 0x9E37_79B9)
        var s = b.rec.start
        var moves = 0
        while moves < b.rec.par && !s.isCleared {
            var exiters: [Int] = []
            var advancers: [Int] = []
            for boat in s.boats {
                let p = HJEngine.preview(boatID: boat.id, state: s)
                if p.exits { exiters.append(boat.id) }
                else if p.distance > 0 { advancers.append(boat.id) }
            }
            let pool = !exiters.isEmpty ? exiters
                     : (!advancers.isEmpty ? advancers : s.boats.map { $0.id })
            if pool.isEmpty { break }
            let pick = pool[rng.below(pool.count)]
            _ = HJEngine.tap(boatID: pick, state: &s)
            moves += 1
        }
        if s.isCleared { return true }
    }
    return false
}

// -------------------------------------------------------- gate 6: freeze search
enum FreezeResult { case ok(nodes: Int, depth: Int), frozen(depth: Int), capped(nodes: Int) }

func freezeSearch(_ b: Board) -> FreezeResult {
    let start = b.rec.start
    let depthCap = 4 * max(1, b.boatCount)
    let mod = lanePeriodLCM(start)

    if isFrozen(start) { return .frozen(depth: 0) }

    var seen = Set<UInt64>()
    seen.reserveCapacity(1 << 16)
    seen.insert(canonicalKey(start, mod: mod))
    var frontier: [HJBoardState] = [start]
    var nodes = 1
    var depth = 0

    while depth < depthCap && !frontier.isEmpty {
        var next: [HJBoardState] = []
        for s in frontier {
            if s.isCleared { continue }
            for boat in s.boats {
                var t = s
                if HJEngine.tap(boatID: boat.id, state: &t) == .invalid { continue }
                if !seen.insert(canonicalKey(t, mod: mod)).inserted { continue }
                nodes += 1
                if nodes > kFreezeNodeCap { return .capped(nodes: nodes) }
                if isFrozen(t) { return .frozen(depth: depth + 1) }
                next.append(t)
            }
        }
        frontier = next
        depth += 1
    }
    return .ok(nodes: nodes, depth: depth)
}

// -------------------------------------------------------------------- arguments
var levelsPath = ""
var runGates = true
var runFreeze = true
var shardIndex = 0
var shardCount = 1
var freezeOutPath: String? = nil
var freezeLogPath: String? = nil
var markdownPath: String? = nil
var jsonPath: String? = nil

let argv = Array(CommandLine.arguments.dropFirst())
var ai = 0
while ai < argv.count {
    let a = argv[ai]
    switch a {
    case "--no-freeze":   runFreeze = false
    case "--freeze-only": runGates = false
    case "--shard":
        ai += 1
        let parts = argv[ai].split(separator: "/")
        shardIndex = parts.count > 0 ? (Int(parts[0]) ?? 0) : 0
        let n = parts.count > 1 ? (Int(parts[1]) ?? 1) : 1
        shardCount = max(1, n)
    case "--out":        ai += 1; freezeOutPath = argv[ai]
    case "--freeze-log": ai += 1; freezeLogPath = argv[ai]
    case "--markdown":   ai += 1; markdownPath = argv[ai]
    case "--json":       ai += 1; jsonPath = argv[ai]
    default:             levelsPath = a
    }
    ai += 1
}

if levelsPath.isEmpty {
    FileHandle.standardError.write(Data("usage: hjverify <levels.json> [flags]\n".utf8))
    exit(2)
}

// ------------------------------------------------------------------- load corpus
var boards: [Board] = []
var campaignCount = 0
var dailyCount = 0
var tableVersion = 0
do {
    let data = try Data(contentsOf: URL(fileURLWithPath: levelsPath))
    let file = try JSONDecoder().decode(HJLevelTableFile.self, from: data)
    tableVersion = file.version
    for k in file.campaign.keys.sorted() {
        boards.append(Board(key: "C:\(k)", rec: file.campaign[k]!, isDaily: false))
    }
    for (i, r) in file.daily.enumerated() {
        boards.append(Board(key: "D:\(i)", rec: r, isDaily: true))
    }
    campaignCount = file.campaign.count
    dailyCount = file.daily.count
} catch {
    print("FAIL  levels.json did not decode into HJLevelTableFile: \(error)")
    exit(1)
}

// ------------------------------------------------------------- freeze shard mode
if !runGates {
    let mine = boards.enumerated().filter { $0.offset % shardCount == shardIndex }.map { $0.element }
    var lines: [String] = []
    var bad = 0
    for b in mine {
        switch freezeSearch(b) {
        case .ok(let n, let d):
            lines.append("OK\t\(b.key)\t\(n)\t\(d)")
        case .frozen(let d):
            lines.append("FROZEN\t\(b.key)\t0\t\(d)")
            print("FAIL  frozen state reachable on \(b.key) at depth \(d)")
            bad += 1
        case .capped(let n):
            lines.append("CAPPED\t\(b.key)\t\(n)\t0")
            print("FAIL  \(b.key) hit the \(kFreezeNodeCap)-node cap — freedom from dead states is UNPROVEN")
            bad += 1
        }
    }
    let text = lines.joined(separator: "\n") + "\n"
    if let p = freezeOutPath {
        try? text.write(toFile: p, atomically: true, encoding: .utf8)
    } else {
        print(text, terminator: "")
    }
    print("shard \(shardIndex)/\(shardCount): \(mine.count) board(s), \(bad) failure(s)")
    exit(bad == 0 ? 0 : 1)
}

// ------------------------------------------------------------------- gates 1..5
var failures: [String] = []

// Gate 1 — corpus size.
let g1 = campaignCount >= kMinCampaign && dailyCount >= kMinDaily
print("\(g1 ? "PASS" : "FAIL")  gate 1 corpus size: campaign \(campaignCount) (need >= \(kMinCampaign)), daily \(dailyCount) (need >= \(kMinDaily))")
if !g1 { failures.append("corpus size") }

// Gate 2 — content envelope.
var maxW = 0, maxH = 0, maxB = 0
var envelopeOffenders: [String] = []
for b in boards {
    maxW = max(maxW, b.rec.start.gridW)
    maxH = max(maxH, b.rec.start.gridH)
    maxB = max(maxB, b.boatCount)
    if b.rec.start.gridW > kMaxGrid || b.rec.start.gridH > kMaxGrid || b.boatCount > kMaxBoats {
        envelopeOffenders.append("\(b.key) \(b.rec.start.gridW)x\(b.rec.start.gridH)/\(b.boatCount)")
    }
}
let g2 = envelopeOffenders.isEmpty
print("\(g2 ? "PASS" : "FAIL")  gate 2 envelope: largest grid \(maxW)x\(maxH), most boats \(maxB) (cap \(kMaxGrid)x\(kMaxGrid) / \(kMaxBoats))")
for o in envelopeOffenders.prefix(20) { print("        over envelope: \(o)") }
if !g2 { failures.append("content envelope") }

// Gate 3 — witness replays through the shipped engine.
var replayFailures = 0
for b in boards {
    let r = replayWitness(b)
    if !r.ok { replayFailures += 1; if replayFailures <= 20 { print("        replay: \(b.key) — \(r.detail)") } }
}
let g3 = replayFailures == 0
print("\(g3 ? "PASS" : "FAIL")  gate 3 witness replay: \(boards.count - replayFailures)/\(boards.count) boards clear on their witness")
if !g3 { failures.append("witness replay") }

// Gate 4 — median witness length as a multiple of boat count.
let ratios = boards.map { Double($0.rec.witness.count) / Double(max(1, $0.boatCount)) }
let medRatio = median(ratios)
let medWitness = median(boards.map { Double($0.rec.witness.count) })
let medBoats = median(boards.map { Double($0.boatCount) })
let g4 = medRatio >= kMinMedianRatio
print("\(g4 ? "PASS" : "FAIL")  gate 4 median witness: \(f2(medRatio))x boat count (need >= \(f2(kMinMedianRatio))); median witness \(f2(medWitness)) taps over median \(f2(medBoats)) boats")
if !g4 { failures.append("median witness length") }

// Gate 5 — zero-thought policy three-stars.
var zt = 0
for b in boards where zeroThoughtThreeStars(b) { zt += 1 }
let ztRate = boards.isEmpty ? 1.0 : Double(zt) / Double(boards.count)
let g5 = ztRate < kMaxZeroThoughtRate
print("\(g5 ? "PASS" : "FAIL")  gate 5 zero-thought three-stars: \(zt)/\(boards.count) = \(pct(ztRate)) (need < \(pct(kMaxZeroThoughtRate)); baseline \(pct(kBaselineZeroThought)))")
if !g5 { failures.append("zero-thought three-star rate") }

// -------------------------------------------------------------------- gate 6
var frozenCount = -1
var cappedCount = -1
var g6 = false
var g6Note = "not run"

if runFreeze || freezeLogPath != nil {
    var status: [String: String] = [:]
    if let lp = freezeLogPath, let text = try? String(contentsOfFile: lp, encoding: .utf8) {
        for line in text.split(separator: "\n") {
            let f = line.split(separator: "\t")
            if f.count >= 2 { status[String(f[1])] = String(f[0]) }
        }
        g6Note = "from \(lp)"
    } else if runFreeze {
        for b in boards {
            switch freezeSearch(b) {
            case .ok:     status[b.key] = "OK"
            case .frozen: status[b.key] = "FROZEN"
            case .capped: status[b.key] = "CAPPED"
            }
        }
        g6Note = "searched in-process"
    }
    var missing = 0
    frozenCount = 0
    cappedCount = 0
    for b in boards {
        switch status[b.key] {
        case .some("OK"):     break
        case .some("FROZEN"): frozenCount += 1; if frozenCount <= 20 { print("        frozen: \(b.key)") }
        case .some("CAPPED"): cappedCount += 1; if cappedCount <= 20 { print("        unproven (node cap): \(b.key)") }
        default:              missing += 1; if missing <= 20 { print("        MISSING from freeze log: \(b.key)") }
        }
    }
    g6 = frozenCount == 0 && cappedCount == 0 && missing == 0
    print("\(g6 ? "PASS" : "FAIL")  gate 6 dead states (\(g6Note)): \(frozenCount) frozen, \(cappedCount) unproven, \(missing) unsearched of \(boards.count) (baseline \(kBaselineDeadLevels)/140)")
    if !g6 { failures.append("dead-state freedom") }
} else {
    print("SKIP  gate 6 dead states — rerun with --freeze-log to close it")
    failures.append("dead-state freedom (not run)")
}

// --------------------------------------------------------------------- reports
if let jp = jsonPath {
    let obj: [String: Any] = [
        "tableVersion": tableVersion,
        "campaign": campaignCount,
        "daily": dailyCount,
        "boards": boards.count,
        "maxGridW": maxW, "maxGridH": maxH, "maxBoats": maxB,
        "replayFailures": replayFailures,
        "medianRatio": medRatio, "medianWitness": medWitness, "medianBoats": medBoats,
        "zeroThoughtBoards": zt, "zeroThoughtRate": ztRate,
        "frozen": frozenCount, "capped": cappedCount,
        "pass": failures.isEmpty
    ]
    if let d = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]) {
        try? d.write(to: URL(fileURLWithPath: jp))
    }
}

if let mp = markdownPath {
    var m = ""
    m += "# Harbor Jam — shipped-corpus verification\n\n"
    m += "Generated by `tools/HarborForge/Verify/main.swift` against the shipped\n"
    m += "`\(levelsPath)` (table version \(tableVersion)) and the shipped `HJEngine`.\n"
    m += "The before column is the pre-throttle measurement recorded in `BASELINE.md`\n"
    m += "and in spec section 1.\n\n"
    m += "| Property | Before | After | Gate | Verdict |\n"
    m += "|---|---|---|---|---|\n"
    m += "| Campaign boards | 140 | \(campaignCount) | >= \(kMinCampaign) | \(g1 ? "PASS" : "FAIL") |\n"
    m += "| Daily boards | 30 fallback seeds | \(dailyCount) | >= \(kMinDaily) | \(g1 ? "PASS" : "FAIL") |\n"
    m += "| Largest grid | 9x9 | \(maxW)x\(maxH) | <= \(kMaxGrid)x\(kMaxGrid) | \(g2 ? "PASS" : "FAIL") |\n"
    m += "| Most boats on a board | 14 | \(maxB) | <= \(kMaxBoats) | \(g2 ? "PASS" : "FAIL") |\n"
    m += "| Witness replay failures | n/a (par was a permutation) | \(replayFailures) | 0 | \(g3 ? "PASS" : "FAIL") |\n"
    m += "| Median witness / boat count | 1.00x | \(f2(medRatio))x | >= \(f2(kMinMedianRatio))x | \(g4 ? "PASS" : "FAIL") |\n"
    m += "| Zero-thought three-stars | \(pct(kBaselineZeroThought)) | \(pct(ztRate)) (\(zt)/\(boards.count)) | < \(pct(kMaxZeroThoughtRate)) | \(g5 ? "PASS" : "FAIL") |\n"
    m += "| Boards with a reachable dead state | \(kBaselineDeadLevels)/140 | \(frozenCount)/\(boards.count) | 0 | \(g6 ? "PASS" : "FAIL") |\n"
    m += "| Boards where dead-state freedom is unproven | n/a | \(cappedCount)/\(boards.count) | 0 | \(g6 ? "PASS" : "FAIL") |\n\n"
    m += "## How each number is produced\n\n"
    m += "- **Witness replay** taps `HJLevelRecord.witness` into `HJEngine.tap` on the shipped\n"
    m += "  engine. A board passes only if `witness.count == par`, no tap returns `.invalid`,\n"
    m += "  and the final state `isCleared`.\n"
    m += "- **Median witness / boat count** is the median of the per-board ratio, so it does not\n"
    m += "  become easier to satisfy as boards grow.\n"
    m += "- **Zero-thought three-stars** runs \(kRollouts) seeded rollouts of \"tap anything that\n"
    m += "  exits, else anything that advances, else anything\" and counts a board against us if\n"
    m += "  ANY rollout clears within par. That is the strictest reading: it asks whether a player\n"
    m += "  who never thinks can stumble into three stars at all.\n"
    m += "- **Dead states** are found by breadth-first search from the start state over the same\n"
    m += "  canonical key the bake used (boats by id: x, y, bow, throttle; tideHigh; ferry.x;\n"
    m += "  taps % lcm(lane periods)), depth cap 4 x boat count, node cap \(kFreezeNodeCap).\n"
    m += "  Every state entered is tested: a state is dead when it is not cleared and every legal\n"
    m += "  tap leaves the board signature (boat positions and bows, exited count, tideHigh,\n"
    m += "  ferry.x) unchanged. Hitting the node cap is reported as UNPROVEN and fails the gate --\n"
    m += "  it is not counted as a pass.\n\n"
    m += "## Result\n\n"
    m += (failures.isEmpty
          ? "All spec section 6 corpus gates PASS.\n"
          : "FAILING GATES: \(failures.joined(separator: ", ")).\n")
    try? m.write(toFile: mp, atomically: true, encoding: .utf8)
    print("wrote \(mp)")
}

if failures.isEmpty {
    print("ALL CORPUS GATES PASS")
    exit(0)
} else {
    print("FAILED GATES: \(failures.joined(separator: ", "))")
    exit(1)
}
```

- [ ] **Step 4: Build the verifier.**

```bash
cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam"
mkdir -p tools/HarborForge/build
swiftc -O -swift-version 5 \
  -o tools/HarborForge/build/hjverify \
  "Harbor Jam/HJModels.swift" \
  "Harbor Jam/HJEngine.swift" \
  "Harbor Jam/HJLevelTable.swift" \
  tools/HarborForge/Verify/main.swift
echo "swiftc exit $?"
```

Assertion: `swiftc exit 0` and no `warning:` lines. `tools/HarborForge/build/` is covered by the repo's existing `build/` ignore rule, so the binary is never committed.

- [ ] **Step 5: Run the fast gates (1–5) and require exit 0.**

```bash
cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam"
tools/HarborForge/build/hjverify "Harbor Jam/levels.json" --no-freeze
echo "gates exit $?"
```

Assertion: every printed gate line begins `PASS` for gates 1–5, gate 6 prints `SKIP`, and the process exits **1** *only* because of the skipped gate 6 (the final line reads `FAILED GATES: dead-state freedom (not run)`). If any of gates 1–5 prints `FAIL`, stop and fix the corpus — do not proceed. Do not hand-edit `levels.json`; a failing gate means the bake parameters need retuning in the task that produced the table.

- [ ] **Step 6: Run the dead-state search, sharded four ways, and require every shard to exit 0.**

The freeze search is the long pole: it is a real BFS per board with a 2,000,000-node cap. Four shards is the ceiling here — each shard holds its own visited set and current frontier in memory, so raising the shard count raises peak RSS proportionally.

```bash
cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam"
rm -f tools/HarborForge/build/freeze-*.txt
for s in 0 1 2 3; do
  tools/HarborForge/build/hjverify "Harbor Jam/levels.json" \
    --freeze-only --shard $s/4 --out "tools/HarborForge/build/freeze-$s.txt" \
    > "tools/HarborForge/build/freeze-$s.log" 2>&1 &
done
wait
for s in 0 1 2 3; do
  tail -1 "tools/HarborForge/build/freeze-$s.log"
done
grep -h -c "" tools/HarborForge/build/freeze-*.txt
grep -h -E "^(FROZEN|CAPPED)" tools/HarborForge/build/freeze-*.txt && { echo "FAIL dead states or unproven boards"; exit 1; } || echo "PASS no frozen, no unproven"
```

Assertion: each shard's last log line reads `shard <i>/4: <n> board(s), 0 failure(s)`, the four per-shard line counts sum to the total board count printed by Step 5, and the final line is `PASS no frozen, no unproven`.

- [ ] **Step 7: Merge the shard logs, close all six gates in one pass, and generate `SHIPPED.md`.**

```bash
cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam"
cat tools/HarborForge/build/freeze-*.txt > tools/HarborForge/build/freeze-all.txt
tools/HarborForge/build/hjverify "Harbor Jam/levels.json" \
  --no-freeze \
  --freeze-log tools/HarborForge/build/freeze-all.txt \
  --markdown tools/HarborForge/SHIPPED.md \
  --json tools/HarborForge/build/shipped-metrics.json
echo "final exit $?"
cat tools/HarborForge/SHIPPED.md
```

Assertion: the run prints `PASS` on all six gate lines, `wrote tools/HarborForge/SHIPPED.md`, `ALL CORPUS GATES PASS`, and `final exit 0`. Every number in `SHIPPED.md` is written by the tool from the shipped corpus — do not type a figure into that file by hand.

- [ ] **Step 8: Debug build on the iPhone 17 simulator — `BUILD SUCCEEDED`, zero warnings.**

```bash
cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam"
rm -rf build/dd-debug
xcodebuild -project "Harbor Jam.xcodeproj" -scheme "Harbor Jam" \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath build/dd-debug \
  clean build 2>&1 | tee build/dd-debug.log | tail -3
echo "warnings: $(grep -c 'warning:' build/dd-debug.log)"
grep -q '\*\* BUILD SUCCEEDED \*\*' build/dd-debug.log && [ "$(grep -c 'warning:' build/dd-debug.log)" -eq 0 ] \
  && echo "PASS debug clean" || { echo "FAIL debug"; exit 1; }
```

Assertion: `warnings: 0` and `PASS debug clean`.

- [ ] **Step 9: Release build for generic iOS — `BUILD SUCCEEDED`, zero warnings.**

The target uses `CODE_SIGN_STYLE = Manual` with an empty `DevelopmentTeam`, so signing must be switched off explicitly for a device-SDK build.

```bash
cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam"
rm -rf build/dd-release
xcodebuild -project "Harbor Jam.xcodeproj" -scheme "Harbor Jam" \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build/dd-release \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  clean build 2>&1 | tee build/dd-release.log | tail -3
echo "warnings: $(grep -c 'warning:' build/dd-release.log)"
grep -q '\*\* BUILD SUCCEEDED \*\*' build/dd-release.log && [ "$(grep -c 'warning:' build/dd-release.log)" -eq 0 ] \
  && echo "PASS release clean" || { echo "FAIL release"; exit 1; }
```

Assertion: `warnings: 0` and `PASS release clean`.

- [ ] **Step 10: Confirm the icon is still opaque and still declared.**

`CFBundleIconFiles` is produced by `actool` into the *built* `Info.plist`, nested under `CFBundleIcons → CFBundlePrimaryIcon`; it is not in the source `Info.plist`. Read it from the Release product built in Step 9.

```bash
cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam"
sips -g hasAlpha "Harbor Jam/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
APP="build/dd-release/Build/Products/Release-iphoneos/Harbor Jam.app"
/usr/libexec/PlistBuddy -c "Print :CFBundleIcons:CFBundlePrimaryIcon:CFBundleIconFiles" "$APP/Info.plist"
ls "$APP" | grep AppIcon
```

Assertion: `sips` prints `hasAlpha: no`; PlistBuddy prints an array containing `AppIcon60x60`; `ls` lists `AppIcon60x60@2x.png`. Any other result is a store-reject class (opaque-icon rule / "Missing 120x120") — stop and fix before committing.

- [ ] **Step 11: Grep the app target for SF Symbols, emoji and iOS 16+ APIs.**

```bash
cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam"
fail=0

grep -rn "Image(systemName\|systemImage:" "Harbor Jam" --include='*.swift' \
  && { echo "FAIL sf-symbols"; fail=1; } || echo "PASS sf-symbols"

find "Harbor Jam" -name '*.swift' -print0 | xargs -0 perl -ne \
  'print "$ARGV:$.: $_" if /[\x{1F000}-\x{1FAFF}\x{1F1E6}-\x{1F1FF}\x{2190}-\x{21FF}\x{2300}-\x{27BF}\x{2B00}-\x{2BFF}\x{FE0F}\x{2934}\x{2935}]/' \
  | grep . && { echo "FAIL emoji"; fail=1; } || echo "PASS emoji"

grep -rn "NavigationStack\|NavigationSplitView\|\.scrollDisabled(\|\.presentationDetents(\|ShareLink(\|AnyLayout\|Gauge(\|\.toolbarBackground(\|\.scrollContentBackground(\|ViewThatFits\|ImageRenderer\|\.contentTransition(\|\.fontDesign(\|\.scrollIndicators(\|\.tracking(\|import Charts" \
  "Harbor Jam" --include='*.swift' \
  && { echo "FAIL ios16-api"; fail=1; } || echo "PASS ios16-api"

exit $fail
```

Assertion: three `PASS` lines and exit 0. The emoji scan deliberately excludes U+2014 em-dash, U+00D7 multiplication sign and U+00B7 middle dot, which the codebase already uses in comments and UI copy and which are not emoji.

- [ ] **Step 12: Update the canonical `APP_TRACKER.md` entry and append the rebuild record.**

`APP_TRACKER.md` contains **two** lines starting `- **Harbor Jam** ·` — the canonical portfolio entry and a bug-log entry from the simulator pass (`- **Harbor Jam** · commit 3487016 · …`). Target the canonical one by the folder path, and assert the match is unique.

```bash
python3 - <<'PY'
import json, io, sys, datetime
tracker = "/Users/vik/Documents/development/APP_TRACKER.md"
metrics = json.load(open("/Users/vik/Documents/development/for_human_review_apps/Harbor Jam/tools/HarborForge/build/shipped-metrics.json"))

lines = io.open(tracker, encoding="utf-8").read().split("\n")
hits = [i for i, l in enumerate(lines)
        if l.startswith("- **Harbor Jam** \u00b7") and "for_human_review_apps/Harbor Jam" in l]
assert len(hits) == 1, "expected exactly one canonical Harbor Jam entry, found %d at %s" % (len(hits), hits)
i = hits[0]

new = (
 "- **Harbor Jam** \u00b7 for_human_review_apps/Harbor Jam \u00b7 NOT SUBMITTABLE (core verb changed \u2014 store screenshots and App Store review notes MUST be redone before any upload) \u00b7 "
 "bundle com.arnljot-dige.harbor-jam (ASC, Apple ID 6795255857) \u00b7 GitHub PUBLIC github.com/PrivetAI/Harbor-Jam \u00b7 "
 "WebView https://harborjam.org/ (Cloudflare Worker \u2192 click.php key 8rzul8kgxg7xpi8x0feb) \u00b7 check harborjam.org/privacy-policy \u00b7 "
 "REBUILT 2026-07-28 to the Throttle & Turning Basins design (docs/superpowers/specs/2026-07-28-harbor-jam-throttle-design.md): the old build had no puzzle in it \u2014 a headless harness proved a zero-thought policy three-starred %s of levels. "
 "Every hull now carries a printed throttle of 1\u20133 and a tap advances exactly that many cells, so a productive-looking move can plug the lane another boat needs; every tap ticks the world (no free probing, no frozen ferry); current lanes flip polarity on a per-lane period; sandbars are drawn INSIDE exit corridors instead of outside them; turning basins flip a bow 180\u00b0 and replace the tug token economy entirely. "
 "Levels are no longer generated on device: an offline harness (tools/HarborForge, plain swiftc against the real HJEngine/HJModels) BFS-searches each seed and bakes par + a witness line into Harbor Jam/levels.json (%d campaign, %d daily); the app replays the witness through the real engine. "
 "Par is a witnessed line, not the boat count; stars are 3 at \u2264 par / 2 at \u2264 par + max(2, par/6) / 1 otherwise; chapter unlock moved from stars to levels cleared; per-level Clean Line pennant (par, zero undos, zero restarts). Bundled harbour-bell win sound (win_bell.wav + win_bell_double.wav on three stars) replaces AudioServices system sound 1025. Content envelope capped at 8\u00d78 / 10 boats. Save key bumped to hbj.state.v2 (progress intentionally wiped; par changed meaning). "
 "SHIPPED VERIFICATION (tools/HarborForge/SHIPPED.md, regenerated from the shipped corpus): zero-thought three-stars %s (was %s), median witness %sx boat count (was 1.00x), %d/%d witnesses replay clean, %d boards with a reachable dead state (was 21/140), %d boards unproven, largest grid %dx%d, most boats %d. "
 "Debug (iPhone 17 sim) + Release (generic/platform=iOS) BUILD SUCCEEDED, zero warnings. Opaque icon (hasAlpha: no), CFBundleIconFiles lists AppIcon60x60. No SF Symbols, no emoji, no iOS 16+ APIs. Bright nautical morning palette, custom Shapes only, iPhone+iPad \"1,2\", iOS 15.6+."
) % (
 "96.63%",
 metrics["campaign"], metrics["daily"],
 ("%.2f%%" % (metrics["zeroThoughtRate"] * 100)), "96.63%",
 ("%.2f" % metrics["medianRatio"]),
 metrics["boards"] - metrics["replayFailures"], metrics["boards"],
 metrics["frozen"], metrics["capped"],
 metrics["maxGridW"], metrics["maxGridH"], metrics["maxBoats"],
)
lines[i] = new

lines.append("")
lines.append("## Rebuild 2026-07-28 (Harbor Jam \u2014 Throttle & Turning Basins)")
lines.append("- **Why:** the shipped game was provably not a puzzle. Par was defined as the boat count and the verifier enforced it, so search depth was exactly 1; reverse construction guaranteed a greedy exit order; four of five advertised mechanics were inert; 21 of 140 levels could be walked into a state where nothing could ever change again. Measured, not asserted \u2014 see tools/HarborForge/BASELINE.md.")
lines.append("- **Fix:** throttle-limited advances, a world tick on every tap, per-lane current periods, corridor-interior sandbars, turning basins replacing the tug, an offline BFS bake with a witnessed par, and an adversarial four-clause acceptance gate. Full rationale in docs/superpowers/specs/2026-07-28-harbor-jam-throttle-design.md.")
lines.append("- **Evidence in-repo:** tools/HarborForge/BASELINE.md (before) and tools/HarborForge/SHIPPED.md (after), both generated by the harness, never hand-written.")
lines.append("- **BLOCKING before any App Store submission:** the core verb changed, so (1) all store screenshots are stale and must be retaken against the shipped build, and (2) the App Store review notes must be rewritten \u2014 the old notes describe tug tokens and a par equal to the boat count, neither of which exists. Until both are done, this app is NOT submittable. The chapter taglines and the HJMoreView mechanics codex were rewritten in-app, but the store listing copy has NOT been re-reviewed against the new rules.")

io.open(tracker, "w", encoding="utf-8").write("\n".join(lines))
print("PASS updated canonical entry at line %d and appended the rebuild record" % (i + 1))
PY
```

Assertion: prints `PASS updated canonical entry at line …`. If the assert fires, the file has drifted — locate the canonical entry by hand before rerunning; never blind-replace the first `- **Harbor Jam** ·` match.

- [ ] **Step 13: Update the `APP_DESCRIPTIONS.md` row.**

One table row, matched on the exact cell text so the bug-log wording elsewhere cannot be hit.

```bash
python3 - <<'PY'
import io
p = "/Users/vik/Documents/development/for_human_review_apps/APP_DESCRIPTIONS.md"
lines = io.open(p, encoding="utf-8").read().split("\n")
hits = [i for i, l in enumerate(lines) if l.startswith("| **Harbor Jam** |")]
assert len(hits) == 1, "expected exactly one Harbor Jam row, found %d" % len(hits)
lines[hits[0]] = (
 "| **Harbor Jam** | \u0413\u043e\u043b\u043e\u0432\u043e\u043b\u043e\u043c\u043a\u0430-\u00ab\u043f\u0440\u043e\u0431\u043a\u0430\u00bb \u0438\u0437 \u043b\u043e\u0434\u043e\u043a \u0432 \u043c\u0430\u0440\u0438\u043d\u0435. \u041d\u0430 \u043a\u0430\u0436\u0434\u043e\u043c \u043a\u043e\u0440\u043f\u0443\u0441\u0435 \u043d\u0430\u043f\u0435\u0447\u0430\u0442\u0430\u043d \u0442\u0440\u043e\u0442\u0442\u043b\u044c 1\u20133 \u2014 \u0442\u0430\u043f \u043f\u0440\u043e\u0434\u0432\u0438\u0433\u0430\u0435\u0442 \u043b\u043e\u0434\u043a\u0443 \u0440\u043e\u0432\u043d\u043e \u043d\u0430 \u0441\u0442\u043e\u043b\u044c\u043a\u043e \u043a\u043b\u0435\u0442\u043e\u043a \u043f\u043e \u043d\u0430\u043f\u0440\u0430\u0432\u043b\u0435\u043d\u0438\u044e \u043d\u043e\u0441\u0430, \u043f\u043e\u044d\u0442\u043e\u043c\u0443 \u00ab\u043f\u043e\u043b\u0435\u0437\u043d\u044b\u0439\u00bb \u0445\u043e\u0434 \u043b\u0435\u0433\u043a\u043e \u0437\u0430\u0442\u044b\u043a\u0430\u0435\u0442 \u0435\u0434\u0438\u043d\u0441\u0442\u0432\u0435\u043d\u043d\u044b\u0439 \u0444\u0430\u0440\u0432\u0430\u0442\u0435\u0440 \u0441\u043e\u0441\u0435\u0434\u0430. \u041a\u0430\u0436\u0434\u044b\u0439 \u0442\u0430\u043f \u0442\u0438\u043a\u0430\u0435\u0442 \u043c\u0438\u0440: \u0442\u0435\u0447\u0435\u043d\u0438\u044f \u0441 \u0441\u043e\u0431\u0441\u0442\u0432\u0435\u043d\u043d\u044b\u043c \u043f\u0435\u0440\u0438\u043e\u0434\u043e\u043c \u043c\u0435\u043d\u044f\u044e\u0442 \u043f\u043e\u043b\u044f\u0440\u043d\u043e\u0441\u0442\u044c, \u043f\u0440\u0438\u043b\u0438\u0432 \u0442\u0432\u0435\u0440\u0434\u0438\u0442 \u043c\u0435\u043b\u0438 \u0432\u043d\u0443\u0442\u0440\u0438 \u0432\u044b\u0445\u043e\u0434\u043d\u044b\u0445 \u043a\u043e\u0440\u0438\u0434\u043e\u0440\u043e\u0432, \u043f\u0430\u0440\u043e\u043c \u0438\u0434\u0451\u0442 \u0432\u0441\u0435\u0433\u0434\u0430. \u0420\u0430\u0437\u0432\u043e\u0440\u043e\u0442\u043d\u044b\u0435 \u0431\u0430\u0441\u0441\u0435\u0439\u043d\u044b \u0440\u0430\u0437\u0432\u043e\u0440\u0430\u0447\u0438\u0432\u0430\u044e\u0442 \u043d\u043e\u0441 \u043d\u0430 180\u00b0 (\u0432\u043c\u0435\u0441\u0442\u043e \u0436\u0435\u0442\u043e\u043d\u043e\u0432 \u0431\u0443\u043a\u0441\u0438\u0440\u0430). \u0423\u0440\u043e\u0432\u043d\u0438 \u043d\u0435 \u0433\u0435\u043d\u0435\u0440\u0438\u0440\u0443\u044e\u0442\u0441\u044f \u043d\u0430 \u0443\u0441\u0442\u0440\u043e\u0439\u0441\u0442\u0432\u0435: \u043e\u0444\u0444\u043b\u0430\u0439\u043d-\u0445\u0430\u0440\u043d\u0435\u0441\u0441 \u0438\u0449\u0435\u0442 \u0440\u0435\u0448\u0435\u043d\u0438\u0435 BFS \u0438 \u0437\u0430\u043f\u0435\u043a\u0430\u0435\u0442 par + \u043b\u0438\u043d\u0438\u044e-\u0441\u0432\u0438\u0434\u0435\u0442\u0435\u043b\u044f \u0432 levels.json, \u0430 \u043f\u0440\u0438\u043b\u043e\u0436\u0435\u043d\u0438\u0435 \u043f\u0435\u0440\u0435\u043f\u0440\u043e\u0432\u0435\u0440\u044f\u0435\u0442 \u0435\u0451 \u0440\u0435\u0430\u043b\u044c\u043d\u044b\u043c \u0434\u0432\u0438\u0436\u043a\u043e\u043c. \u0417\u0432\u0451\u0437\u0434\u044b \u043e\u0442 par, \u0432\u044b\u043c\u043f\u0435\u043b Clean Line, \u0433\u043b\u0430\u0432\u044b \u043e\u0442\u043a\u0440\u044b\u0432\u0430\u044e\u0442\u0441\u044f \u0437\u0430 \u043f\u0440\u043e\u0439\u0434\u0435\u043d\u043d\u044b\u0435 \u0443\u0440\u043e\u0432\u043d\u0438, Daily \u0438\u0437 \u0437\u0430\u043f\u0435\u0447\u0451\u043d\u043d\u043e\u0433\u043e \u043f\u0443\u043b\u0430, \u0441\u0443\u0434\u043e\u0432\u043e\u0439 \u043a\u043e\u043b\u043e\u043a\u043e\u043b \u043d\u0430 \u043f\u043e\u0431\u0435\u0434\u0435. \u0421\u0435\u0442\u043a\u0438 \u0434\u043e 8\u00d78, \u0434\u043e 10 \u043b\u043e\u0434\u043e\u043a. \u0421\u0432\u0435\u0442\u043b\u0430\u044f \u043c\u043e\u0440\u0441\u043a\u0430\u044f \u043f\u0430\u043b\u0438\u0442\u0440\u0430 \u043a\u0440\u0435\u043c/\u043d\u0430\u0432\u0438/\u0441\u0438\u0444\u043e\u043c. WebView: https://harborjam.org/ \u00b7 check: harborjam.org/privacy-policy \u00b7 bundle: com.arnljot-dige.harbor-jam \u00b7 \u0421\u041a\u0420\u0418\u041d\u0428\u041e\u0422\u042b \u0418 REVIEW NOTES \u0423\u0421\u0422\u0410\u0420\u0415\u041b\u0418 \u2014 \u043f\u0435\u0440\u0435\u0434\u0435\u043b\u0430\u0442\u044c \u043f\u0435\u0440\u0435\u0434 \u0441\u0430\u0431\u043c\u0438\u0442\u043e\u043c |"
)
io.open(p, "w", encoding="utf-8").write("\n".join(lines))
print("PASS updated Harbor Jam description row at line %d" % (hits[0] + 1))
PY
```

Assertion: prints `PASS updated Harbor Jam description row at line …`. Note `/Users/vik/Documents/development` is **not** a git repository, so these two ledger files are saved in place and are not part of the commit below.

- [ ] **Step 14: Commit the verifier and the shipped report.**

Only two files enter the repo: the verifier source and the generated report. The compiled binary, the shard logs and both derived-data trees sit under `build/`, which the repo already ignores.

```bash
cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam"
git status --porcelain
git add tools/HarborForge/Verify/main.swift tools/HarborForge/SHIPPED.md
git commit -m "$(cat <<'EOF'
Definition of done: gate the shipped corpus and record the before/after

Adds tools/HarborForge/Verify/main.swift, a headless verifier built with
plain swiftc against the shipped HJModels/HJEngine/HJLevelTable. It reads
the shipped Harbor Jam/levels.json and enforces every clause of spec
section 6 as a hard gate, exiting non-zero on any failure:

  1. >= 140 campaign and >= 400 daily boards
  2. every board inside the 8x8 / 10-boat content envelope
  3. every witness replays clean through the shipped engine and clears
  4. median witness length >= 1.6x boat count
  5. zero-thought policy three-stars < 15% (was 96.63%)
  6. zero boards with a reachable dead state, found by BFS from the start
     over the bake's canonical key within the 4x-boat-count depth cap --
     hitting the node cap is reported UNPROVEN and fails, never passes

tools/HarborForge/SHIPPED.md is generated by the tool from the shipped
corpus and sits next to the committed BASELINE.md, so the before and the
after are both in the repo and neither was typed by hand.

Debug (iPhone 17 simulator) and Release (generic/platform=iOS) both
BUILD SUCCEEDED with zero warnings. Icon still opaque (hasAlpha: no) and
CFBundleIconFiles still lists AppIcon60x60. No SF Symbols, no emoji, no
iOS 16+ APIs in the target.

NOT SUBMITTABLE: the core verb changed, so the store screenshots and the
App Store review notes are stale and must be redone before any upload.

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
git log --oneline -1
git status --porcelain
```

Assertion: the first `git status --porcelain` shows exactly two untracked/modified paths (`tools/HarborForge/Verify/main.swift`, `tools/HarborForge/SHIPPED.md`), and the final `git status --porcelain` prints nothing. Do not push — the plan's Global Constraints leave publishing to the operator, and this app must not reach the store until the screenshots and review notes are redone.
