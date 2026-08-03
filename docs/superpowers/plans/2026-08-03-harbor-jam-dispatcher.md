# Harbor Jam — Port Dispatcher Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Harbor Jam's sliding-block puzzle with a real-time port dispatcher whose difficulty is proven by measurement — a greedy policy must three-star at most 25 % of shifts from port 3 on, and fail outright on at least 30 % of shifts from port 5 on.

**Architecture:** A pure-Foundation, integer-tick simulation (`HJSim`) is the single source of truth for game rules; it compiles both into the app and into a headless harness (`tools/HarborForge`) that generates shifts forward, selects them adversarially, calibrates star targets, and vetoes the whole build if greedy play wins. SwiftUI drives the sim from a 20 Hz timer and renders it from SVG sprites shipped in the asset catalog.

**Tech Stack:** Swift 5 / SwiftUI, iOS 15.6 deployment target, no third-party dependencies. Offline tooling is plain `swiftc` compiled against the real app sources. There is no XCTest target and none is created — the harness is the test surface.

## Global Constraints

- **Deployment target is iOS 15.6.** No iOS 16+ APIs: no `NavigationStack`, no `.scrollContentBackground`, no `Charts`, no `.tracking()`.
- **No SF Symbols and no emoji anywhere.** Icons are custom SwiftUI `Shape`s or bundled SVG sprites.
- **`preferredColorScheme(.dark)`** is forced app-wide (the chart aesthetic is dark). The old code forces `.light` — change it exactly once, in `HJRootView`.
- **The simulation layer must import only `Foundation`.** `HJSimModel.swift`, `HJSim.swift` and `HJShiftCatalog.swift` may not import SwiftUI, UIKit or CoreGraphics — the headless harness compiles these exact files.
- **All sim quantities are integers in ticks.** 1 tick = 1/20 s. No `Double`, no `Date`, no wall-clock in the sim. Fractional multipliers are expressed by scaling the stored unit (patience is stored doubled; unload is stored doubled) — see Task 3.
- **The pbxproj is hand-authored with no synchronized groups and no xcodegen.** Every new `.swift` or resource must be registered in **four** places: `PBXBuildFile`, `PBXFileReference`, the `E8C6ADF1294695810FC9BE0F /* Harbor Jam */` group's `children`, and the build phase — `D0FBB2BBB0982F7A26FCBE9D /* Sources */` for Swift, the existing `F115417AB24C0E0F4821A9A2 /* Resources */` for `shifts.json`. Do not create a second Resources phase. Object ids are assigned per file in the task that creates the file and are never reused.
- **`Assets.xcassets` is a `folder.assetcatalog` file reference.** Adding imagesets inside it requires no pbxproj change.
- **Every `Codable` decode in the save layer uses `decodeIfPresent(...) ?? default`.** A non-optional field added to a `UserDefaults` Codable struct makes the synthesized decoder throw on missing keys and silently wipes all progress. This has already happened once in this portfolio.
- **`TARGETED_DEVICE_FAMILY = "1,2"`, manual signing, bundle id `com.arnljot-dige.harbor-jam`.** Do not touch signing or the bundle id.
- **`HarborJamApp.swift`, `HarborJamLoadingScreen.swift` and `HarborJamWebPanel.swift` are frozen.** The WebView gate, `HarborJamRedirectTracker`, `harborJamLinkReady` / `harborJamSourceLink` / `harborJamCheckDomain` and the domain `harborjam.org` are out of scope in every task.
- **Task 7 is a hard go/no-go.** If the gate does not pass, parameters are retuned and the gate re-run. No app-facing task starts until it passes.
- **Build verification** is `xcodebuild` Debug on `platform=iOS Simulator,name=iPhone 17` and Release on `generic/platform=iOS`. Only iPhone 17-series simulators exist on this machine — `iPhone 15` destinations fail.
- **Never fabricate expected output.** For any command whose output cannot be known ahead of time, state the assertion that must hold and show the code that enforces it.
- Work happens on branch `dispatcher-rebuild`, already created, spec already committed there.

## Reference

The spec is `docs/superpowers/specs/2026-08-03-harbor-jam-dispatcher-design.md`. Where this plan and the spec disagree on a number, the spec's number is the starting value and Task 7 is allowed to change it; where they disagree on a **rule**, the spec wins and the plan is the bug.

## File Structure

| File | Responsibility |
|---|---|
| `Harbor Jam/HJSimModel.swift` | Value types only: cargo, equipment, slot, ship, harbor, shift definition, counters. Foundation only. |
| `Harbor Jam/HJSim.swift` | The rules: tick order, berthing legality, tide, grounding, channel, patience, scoring. Foundation only. |
| `Harbor Jam/HJShiftCatalog.swift` | Tunable constants, port templates, `shifts.json` loading. Foundation only. |
| `Harbor Jam/HJTheme.swift` | Chart palette, fonts, tab-bar `Shape` icons. |
| `Harbor Jam/HJSprites.swift` | Sprite name enum → `Image`, one place that knows asset names. |
| `Harbor Jam/HJSave.swift` | `hbj.state.v3` persistence, upgrades, records, achievements. |
| `Harbor Jam/HJShiftViewModel.swift` | Owns an `HJSim`, drives it from a 20 Hz timer, exposes `@Published` snapshots. |
| `Harbor Jam/HJHarborBoardView.swift` | Renders quay, water, channel, roadstead, ships. Drag and tap hit-testing. |
| `Harbor Jam/HJShiftView.swift` | Game screen: HUD, board, overlays (win/lose/onboarding). |
| `Harbor Jam/HJPortsView.swift` | Port list, shift grid, entry to shipyard. |
| `Harbor Jam/HJShipyardView.swift` | Five upgrade lines, coin spend. |
| `Harbor Jam/HJWatchView.swift` | Endless mode and its record. |
| `Harbor Jam/HJAwardsView.swift` | Achievements + stats (rewritten). |
| `Harbor Jam/HJMoreView.swift` | Settings, manual, privacy (rewritten). |
| `Harbor Jam/HJRootView.swift` | Four-tab shell (edited). |
| `Harbor Jam/HJAdaptive.swift` | iPad column caps (edited). |
| `Harbor Jam/shifts.json` | Baked corpus: 84 shifts with harbours, arrivals, `parTicks`, targets. |
| `tools/HarborForge/*.swift` | Headless: sim assertions, forward generation, policies, gate, bake. |

### pbxproj object ids — assigned once, never reused

| File | `PBXFileReference` | `PBXBuildFile` |
|---|---|---|
| `HJSimModel.swift` | `C0DE510000000000000001` | `C0DE520000000000000001` |
| `HJSim.swift` | `C0DE510000000000000002` | `C0DE520000000000000002` |
| `HJShiftCatalog.swift` | `C0DE510000000000000003` | `C0DE520000000000000003` |
| `HJSprites.swift` | `C0DE510000000000000004` | `C0DE520000000000000004` |
| `HJHarborBoardView.swift` | `C0DE510000000000000005` | `C0DE520000000000000005` |
| `HJShiftView.swift` | `C0DE510000000000000006` | `C0DE520000000000000006` |
| `HJShiftViewModel.swift` | `C0DE510000000000000007` | `C0DE520000000000000007` |
| `HJPortsView.swift` | `C0DE510000000000000008` | `C0DE520000000000000008` |
| `HJShipyardView.swift` | `C0DE510000000000000009` | `C0DE520000000000000009` |
| `HJWatchView.swift` | `C0DE51000000000000000A` | `C0DE52000000000000000A` |
| `shifts.json` | `C0DE51000000000000000B` | `C0DE52000000000000000B` |

---

## Task 1: SVG sprite pipeline spike

Retires the single biggest unknown before any art is drawn: whether `actool` compiles hand-authored SVG into a usable asset on this toolchain.

**Files:**
- Create: `Harbor Jam/Assets.xcassets/hull_4.imageset/hull_4.svg`
- Create: `Harbor Jam/Assets.xcassets/hull_4.imageset/Contents.json`
- Create: `Harbor Jam/HJSprites.swift`
- Modify: `Harbor Jam/HJHarborView.swift` (temporary probe, reverted in Task 9)
- Modify: `Harbor Jam.xcodeproj/project.pbxproj` (register `HJSprites.swift` only)

**Interfaces:**
- Produces: `enum HJSprite: String` with `var image: Image { Image(rawValue) }`, and case `hull4 = "hull_4"`.

- [ ] **Step 1: Author the probe sprite**

`Harbor Jam/Assets.xcassets/hull_4.imageset/hull_4.svg` — a 4-slot hull, 176×44 pt natural size, drawn as a top-down silhouette with the bow to the right. Only `path`/`rect`/`circle`, fill and stroke. No `<text>`, no gradients, no filters, no masks.

```svg
<svg xmlns="http://www.w3.org/2000/svg" width="176" height="44" viewBox="0 0 176 44">
<path d="M6 8 L146 8 Q170 22 146 36 L6 36 Q2 22 6 8 Z" fill="#123A52" stroke="#5FD0E8" stroke-width="2"/>
<rect x="20" y="15" width="26" height="14" rx="2" fill="none" stroke="#2F6C86" stroke-width="1.5"/>
<rect x="52" y="15" width="26" height="14" rx="2" fill="none" stroke="#2F6C86" stroke-width="1.5"/>
<rect x="84" y="15" width="26" height="14" rx="2" fill="none" stroke="#2F6C86" stroke-width="1.5"/>
<path d="M132 14 L142 22 L132 30" fill="none" stroke="#5FD0E8" stroke-width="2"/>
</svg>
```

- [ ] **Step 2: Write the imageset manifest**

`Harbor Jam/Assets.xcassets/hull_4.imageset/Contents.json`:

```json
{
  "images" : [
    {
      "filename" : "hull_4.svg",
      "idiom" : "universal"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  },
  "properties" : {
    "preserves-vector-representation" : true
  }
}
```

- [ ] **Step 3: Create the sprite accessor**

`Harbor Jam/HJSprites.swift`:

```swift
import SwiftUI

/// Every bundled sprite name lives here and nowhere else. A typo becomes a
/// compile error rather than a silently blank image.
enum HJSprite: String {
    case hull4 = "hull_4"

    var image: Image { Image(rawValue) }
}
```

- [ ] **Step 4: Register `HJSprites.swift` in the pbxproj**

Four edits, using the ids from the table above. The asset catalog itself needs no edit.

```
PBXBuildFile:      C0DE520000000000000004 /* HJSprites.swift in Sources */ = {isa = PBXBuildFile; fileRef = C0DE510000000000000004 /* HJSprites.swift */; };
PBXFileReference:  C0DE510000000000000004 /* HJSprites.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = HJSprites.swift; sourceTree = "<group>"; };
group children:    C0DE510000000000000004 /* HJSprites.swift */,
Sources phase:     C0DE520000000000000004 /* HJSprites.swift in Sources */,
```

- [ ] **Step 5: Add a temporary on-screen probe**

In `Harbor Jam/HJHarborView.swift`, inside the existing `ScrollView`'s top-level `VStack`, insert as the first child:

```swift
HJSprite.hull4.image
    .resizable()
    .scaledToFit()
    .frame(width: 300)
```

- [ ] **Step 6: Build and prove the sprite renders**

```bash
cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam" && xcodebuild -project "Harbor Jam.xcodeproj" -scheme "Harbor Jam" -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug build 2>&1 | tail -20
```

The build must succeed **and** the log must not contain `Could not find image` or `unsupported element`. Then install and launch on a booted iPhone 17 simulator and take a screenshot.

Assertion: the screenshot shows a cyan-outlined hull 300 pt wide at the top of the Harbor tab. A blank gap means `actool` silently dropped the SVG — that is the failure this task exists to catch.

- [ ] **Step 7: Decide the pipeline**

If the hull rendered, record in `tools/HarborArt/PIPELINE.md`: `SVG in asset catalog — CONFIRMED WORKING`, plus the exact Contents.json shape and the SVG feature restrictions from Step 1.

If it did **not** render, create `tools/HarborArt/render.swift`: a `swiftc`-compiled CoreGraphics program that draws the same shapes and writes `<name>@2x.png` and `<name>@3x.png` into each imageset, plus a Contents.json listing `2x` and `3x` scales. Record the fallback as chosen in `PIPELINE.md`. Every later art task then produces PNG via this renderer instead of SVG. **Do not proceed to Task 2 until one of the two paths renders a visible hull in a simulator screenshot.**

- [ ] **Step 8: Commit**

```bash
git add "Harbor Jam/Assets.xcassets/hull_4.imageset" "Harbor Jam/HJSprites.swift" "Harbor Jam.xcodeproj/project.pbxproj" "Harbor Jam/HJHarborView.swift" tools/HarborArt/PIPELINE.md
git commit -m "Art: prove the sprite pipeline end to end on one hull"
```

---

## Task 2: Simulation value types

**Files:**
- Create: `Harbor Jam/HJSimModel.swift`
- Modify: `Harbor Jam.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces: every type below. Tasks 3–14 refer to these names exactly.

- [ ] **Step 1: Write the model**

`Harbor Jam/HJSimModel.swift` — Foundation only:

```swift
import Foundation

enum HJCargo: Int, Codable, CaseIterable {
    case container = 0, bulk = 1, liquid = 2

    /// Strictly one-to-one: a berth either has this cargo's gear or it does not.
    var equipment: HJEquipment {
        switch self {
        case .container: return .crane
        case .bulk: return .conveyor
        case .liquid: return .pipeline
        }
    }
}

enum HJEquipment: Int, Codable, CaseIterable {
    case none = 0, crane = 1, conveyor = 2, pipeline = 3
}

struct HJSlot: Codable, Equatable {
    var depth: Int              // 1...5, before tide
    var equipment: HJEquipment
}

enum HJShipState: Int, Codable {
    case waiting = 0, transitingIn = 1, berthed = 2, aground = 3
    case transitingOut = 4, served = 5, lost = 6
}

struct HJShip: Codable, Equatable, Identifiable {
    var id: Int
    var length: Int             // 2...5 slots
    var draft: Int              // 1...5
    var cargo: HJCargo
    var tons: Int
    /// Stored DOUBLED. Patience burns 2 units per tick normally and 3 during a
    /// storm, which is how the ×1.5 storm multiplier stays in integer maths.
    var patienceTicks: Int
    var isVIP: Bool

    var state: HJShipState = .waiting
    var patienceLeft: Int = 0
    var berthStart: Int? = nil  // index of the first occupied slot
    /// Stored DOUBLED. Unload burns 2 units per tick; mismatched gear costs
    /// 5 units of work per ton instead of 2, i.e. the ×2.5 penalty.
    var unloadLeft: Int = 0
    var transitLeft: Int = 0

    var slots: Range<Int>? {
        guard let s = berthStart else { return nil }
        return s..<(s + length)
    }
    var holdsBerth: Bool {
        state == .berthed || state == .aground || state == .transitingIn
    }
}

struct HJHarborDef: Codable, Equatable {
    var slots: [HJSlot]
    var channelTransitTicks: Int
    var tideAmplitude: Int      // 0, 1 or 2
    var tideStepTicks: Int
    var roadsteadCapacity: Int
}

struct HJArrival: Codable, Equatable {
    var tick: Int
    var ship: HJShip
}

struct HJSlotOutage: Codable, Equatable {
    var slot: Int
    var startTick: Int
    var endTick: Int
}

struct HJStormWindow: Codable, Equatable {
    var startTick: Int
    var endTick: Int
}

struct HJShiftDef: Codable, Equatable {
    var port: Int               // 1...7
    var shift: Int              // 1...12
    var harbor: HJHarborDef
    var arrivals: [HJArrival]
    var outages: [HJSlotOutage]
    var storms: [HJStormWindow]
    var parTicks: Int           // baked by HarborForge from policy S
    var target2: Int
    var target3: Int
}

struct HJUpgradeLevels: Codable, Equatable {
    var cranes: Int = 0         // 0...5, -8 % unload each
    var tugs: Int = 0           // 0...3, -10 % channel transit each
    var dredge: Int = 0         // 0...2, +1 depth on every slot each
    var roadstead: Int = 0      // 0...2, +1 waiting berth each
    var crew: Int = 0           // 0...2, +1 starting reputation each

    static let zero = HJUpgradeLevels()
}

/// Why a berth command was refused. The board draws each differently — a single
/// generic shake is what made the previous game feel arbitrary.
enum HJBerthRefusal: Int, Equatable {
    case none = 0, tooLong, occupied, tooShallow, channelBusy, notWaiting, outage
}

/// Proof that each advertised mechanic actually fired. The acceptance gate reads
/// these; four of five mechanics in the previous game were inert and nobody
/// noticed until a harness counted.
struct HJSimCounters: Codable, Equatable {
    var groundings: Int = 0
    var channelRefusals: Int = 0
    var mismatchedUnloads: Int = 0
    var shipsServed: Int = 0
    var shipsLost: Int = 0
    var tonsServed: Int = 0
    var revenue: Int = 0
}
```

- [ ] **Step 2: Register in the pbxproj**

```
PBXBuildFile:      C0DE520000000000000001 /* HJSimModel.swift in Sources */ = {isa = PBXBuildFile; fileRef = C0DE510000000000000001 /* HJSimModel.swift */; };
PBXFileReference:  C0DE510000000000000001 /* HJSimModel.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = HJSimModel.swift; sourceTree = "<group>"; };
group children:    C0DE510000000000000001 /* HJSimModel.swift */,
Sources phase:     C0DE520000000000000001 /* HJSimModel.swift in Sources */,
```

- [ ] **Step 3: Prove it compiles headless**

```bash
cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam" && swiftc -typecheck "Harbor Jam/HJSimModel.swift" && echo "HEADLESS OK"
```

Expected: `HEADLESS OK`. A failure here means a SwiftUI or UIKit dependency crept in, which would break the harness in Task 5.

- [ ] **Step 4: Prove it compiles in the app**

```bash
cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam" && xcodebuild -project "Harbor Jam.xcodeproj" -scheme "Harbor Jam" -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add "Harbor Jam/HJSimModel.swift" "Harbor Jam.xcodeproj/project.pbxproj"
git commit -m "Sim: value types for ships, berths, harbours and shifts"
```

---

## Task 3: Tunable constants and port templates

**Files:**
- Create: `Harbor Jam/HJShiftCatalog.swift`
- Modify: `Harbor Jam.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: everything from Task 2.
- Produces: `HJTuning` (all constants), `HJPortTemplate`, `HJCatalog.ports`, `HJCatalog.portCount`, `HJCatalog.shiftsPerPort`, `HJCatalog.starsToUnlock(port:)`.

- [ ] **Step 1: Write the catalog**

`Harbor Jam/HJShiftCatalog.swift` — Foundation only. Every number the gate is allowed to move lives in `HJTuning` and nowhere else:

```swift
import Foundation

/// Every balance number in the game. Task 7's tuning loop edits this struct and
/// nothing else — a magic number anywhere else in the codebase is a bug.
enum HJTuning {
    static let tickHz = 20

    /// Work units per ton, in doubled units (see HJShip.unloadLeft).
    static func workPerTon(_ cargo: HJCargo) -> Int {
        switch cargo {
        case .container: return 6
        case .bulk: return 8
        case .liquid: return 5
        }
    }
    /// Coins per ton.
    static func rate(_ cargo: HJCargo) -> Int {
        switch cargo {
        case .container: return 10
        case .bulk: return 8
        case .liquid: return 12
        }
    }
    static let vipRateMultiplier = 3
    static let speedRate = 2            // score per tick saved against par
    static let baseReputation = 3
    static let target3Percent = 92      // of policy S's score
    static let target2Percent = 70

    static let unloadDiscountPerCraneLevel = 8    // percent
    static let transitDiscountPerTugLevel = 10    // percent
    static let longShipLength = 4                 // transit ×1.5 from port 6
    static let patiencePerTick = 2
    static let patiencePerTickInStorm = 3
}

struct HJPortTemplate {
    var index: Int              // 1...7
    var name: String
    var tagline: String
    var slotCount: Int
    var depthRange: ClosedRange<Int>
    var equipment: [HJEquipment]     // pool drawn from when laying out a quay
    var cargoes: [HJCargo]
    var channelTransitTicks: Int
    var tideAmplitude: Int
    var tideStepTicks: Int
    var shipLengths: ClosedRange<Int>
    var draftRange: ClosedRange<Int>
    var shipCount: ClosedRange<Int>
    var usesOutages: Bool
    var usesStorms: Bool
    var usesVIP: Bool
    var longShipTransitPenalty: Bool
}

enum HJCatalog {
    static let shiftsPerPort = 12
    static var portCount: Int { ports.count }
    static var totalShifts: Int { portCount * shiftsPerPort }

    /// Port `n` opens at 20·(n−1) stars, out of 36 available per port.
    static func starsToUnlock(port: Int) -> Int { max(0, 20 * (port - 1)) }

    static let ports: [HJPortTemplate] = [
        HJPortTemplate(index: 1, name: "Quiet Cove", tagline: "Learn the quay",
                       slotCount: 8, depthRange: 5...5, equipment: [.crane],
                       cargoes: [.container], channelTransitTicks: 30,
                       tideAmplitude: 0, tideStepTicks: 0,
                       shipLengths: 2...3, draftRange: 1...3, shipCount: 12...16,
                       usesOutages: false, usesStorms: false, usesVIP: false,
                       longShipTransitPenalty: false),
        HJPortTemplate(index: 2, name: "Tidewater Quay", tagline: "Mind the water line",
                       slotCount: 9, depthRange: 2...5, equipment: [.crane],
                       cargoes: [.container], channelTransitTicks: 30,
                       tideAmplitude: 1, tideStepTicks: 100,
                       shipLengths: 2...4, draftRange: 1...4, shipCount: 14...18,
                       usesOutages: false, usesStorms: false, usesVIP: false,
                       longShipTransitPenalty: false),
        HJPortTemplate(index: 3, name: "Narrow Channel", tagline: "One way in",
                       slotCount: 9, depthRange: 2...5, equipment: [.crane],
                       cargoes: [.container], channelTransitTicks: 80,
                       tideAmplitude: 1, tideStepTicks: 100,
                       shipLengths: 2...4, draftRange: 1...4, shipCount: 16...20,
                       usesOutages: false, usesStorms: false, usesVIP: false,
                       longShipTransitPenalty: false),
        HJPortTemplate(index: 4, name: "Mixed Berths", tagline: "Right gear, right berth",
                       slotCount: 10, depthRange: 2...5,
                       equipment: [.crane, .conveyor, .pipeline, .none],
                       cargoes: [.container, .bulk, .liquid], channelTransitTicks: 80,
                       tideAmplitude: 1, tideStepTicks: 100,
                       shipLengths: 2...4, draftRange: 1...4, shipCount: 16...22,
                       usesOutages: false, usesStorms: false, usesVIP: false,
                       longShipTransitPenalty: false),
        HJPortTemplate(index: 5, name: "Storm Roads", tagline: "Weather and repairs",
                       slotCount: 10, depthRange: 2...5,
                       equipment: [.crane, .conveyor, .pipeline, .none],
                       cargoes: [.container, .bulk, .liquid], channelTransitTicks: 80,
                       tideAmplitude: 1, tideStepTicks: 100,
                       shipLengths: 2...4, draftRange: 1...4, shipCount: 18...24,
                       usesOutages: true, usesStorms: true, usesVIP: false,
                       longShipTransitPenalty: false),
        HJPortTemplate(index: 6, name: "Deepwater Port", tagline: "Big hulls, deep water",
                       slotCount: 12, depthRange: 2...5,
                       equipment: [.crane, .conveyor, .pipeline, .none],
                       cargoes: [.container, .bulk, .liquid], channelTransitTicks: 80,
                       tideAmplitude: 2, tideStepTicks: 90,
                       shipLengths: 3...5, draftRange: 2...5, shipCount: 20...26,
                       usesOutages: true, usesStorms: true, usesVIP: false,
                       longShipTransitPenalty: true),
        HJPortTemplate(index: 7, name: "Grand Harbor", tagline: "Everything at once",
                       slotCount: 12, depthRange: 2...5,
                       equipment: [.crane, .conveyor, .pipeline, .none],
                       cargoes: [.container, .bulk, .liquid], channelTransitTicks: 80,
                       tideAmplitude: 2, tideStepTicks: 90,
                       shipLengths: 2...5, draftRange: 1...5, shipCount: 22...28,
                       usesOutages: true, usesStorms: true, usesVIP: true,
                       longShipTransitPenalty: true),
    ]
}
```

- [ ] **Step 2: Do NOT register this file in the pbxproj yet**

`HJShiftCatalog.swift` declares `enum HJCatalog`, and the old `HJModels.swift` — still in the target until Task 9 — declares an `enum HJCatalog` of its own. Adding both to the Sources phase is an invalid redeclaration and the app stops compiling.

Renaming the new one is the wrong fix: Tasks 5, 6, 7, 13 and 14 all refer to `HJCatalog`, and a later rename back is exactly the kind of sweep that leaks into string literals.

Tasks 4–7 are headless — they compile with `swiftc` against file paths and never consult the Xcode target — so the file simply stays out of the target until `HJModels.swift` leaves it. **Task 9 Step 2a registers `HJShiftCatalog.swift` and `HJSim.swift` together with the deletions.**

- [ ] **Step 3: Verify the headless build, and that the app is untouched**

```bash
cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam" && swiftc -typecheck "Harbor Jam/HJSimModel.swift" "Harbor Jam/HJShiftCatalog.swift" && echo "HEADLESS OK"
```

Expected: `HEADLESS OK`. Then the same `xcodebuild` Debug command as Task 2 Step 4, expecting `** BUILD SUCCEEDED **` — the app must still build precisely because the new file is not in the target.

- [ ] **Step 4: Commit**

```bash
git add "Harbor Jam/HJShiftCatalog.swift" "Harbor Jam.xcodeproj/project.pbxproj"
git commit -m "Sim: tuning constants and the seven port templates"
```

---

## Task 4: The simulation

The heart of the game. Every rule in spec section 3.5 lands here, and nothing else in the codebase is allowed to decide game outcomes.

**Files:**
- Create: `Harbor Jam/HJSim.swift`
- Create: `tools/HarborForge/SimTests.swift`
- Create: `tools/HarborForge/build.sh`
- Modify: `Harbor Jam.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: Tasks 2 and 3.
- Produces:
  - `HJSim.init(def: HJShiftDef, upgrades: HJUpgradeLevels)`
  - `mutating func advance()`, `mutating func berth(shipID: Int, atSlot: Int) -> HJBerthRefusal`, `mutating func depart(shipID: Int) -> Bool`
  - `func canBerth(shipID: Int, atSlot: Int) -> HJBerthRefusal`, `func effectiveDepth(slot: Int) -> Int`, `func tideOffset(at: Int) -> Int`
  - `var tick: Int`, `var ships: [HJShip]`, `var reputation: Int`, `var counters: HJSimCounters`, `var channelBusy: Bool`, `var isOver: Bool`, `var isFailed: Bool`, `var waitingShips: [HJShip]`
  - `func score() -> Int`, `func stars() -> Int`

- [ ] **Step 1: Write the failing tests first**

`tools/HarborForge/SimTests.swift`. There is no XCTest target; these are plain assertions run by the harness binary.

```swift
import Foundation

enum SimTests {
    static var failures: [String] = []

    static func expect(_ cond: Bool, _ label: String) {
        if !cond { failures.append(label) }
    }
    static func expectEqual<T: Equatable>(_ a: T, _ b: T, _ label: String) {
        if a != b { failures.append("\(label): got \(a), want \(b)") }
    }

    /// A one-slot-deep harbour with a single ship, used by most rule tests.
    static func harbour(slots: [HJSlot], channel: Int = 10,
                        amplitude: Int = 0, step: Int = 0,
                        roadstead: Int = 4) -> HJHarborDef {
        HJHarborDef(slots: slots, channelTransitTicks: channel,
                    tideAmplitude: amplitude, tideStepTicks: step,
                    roadsteadCapacity: roadstead)
    }

    static func ship(id: Int = 1, length: Int = 2, draft: Int = 1,
                     cargo: HJCargo = .container, tons: Int = 4,
                     patience: Int = 1000, vip: Bool = false) -> HJShip {
        HJShip(id: id, length: length, draft: draft, cargo: cargo, tons: tons,
               patienceTicks: patience, isVIP: vip)
    }

    static func shift(harbor: HJHarborDef, arrivals: [HJArrival],
                      outages: [HJSlotOutage] = [], storms: [HJStormWindow] = [],
                      par: Int = 100_000) -> HJShiftDef {
        HJShiftDef(port: 1, shift: 1, harbor: harbor, arrivals: arrivals,
                   outages: outages, storms: storms,
                   parTicks: par, target2: 0, target3: Int.max)
    }

    static func run() -> Bool {
        failures = []
        testBerthLegality()
        testChannelIsExclusive()
        testTideTriangleWave()
        testGroundingHoldsTheBerth()
        testMismatchedGearCostsMore()
        testPatienceOnlyBurnsWhileWaiting()
        testRoadsteadOverflowLosesShip()
        testSlotsFreeAtStartOfDeparture()
        testUpgradesApply()
        testDeterminism()
        for f in failures { print("FAIL  \(f)") }
        print(failures.isEmpty ? "SIM TESTS OK (\(10) cases)" : "SIM TESTS FAILED (\(failures.count))")
        return failures.isEmpty
    }

    static func testBerthLegality() {
        let quay = harbour(slots: [HJSlot(depth: 5, equipment: .crane),
                                   HJSlot(depth: 5, equipment: .crane),
                                   HJSlot(depth: 2, equipment: .crane)])
        var sim = HJSim(def: shift(harbor: quay,
                                   arrivals: [HJArrival(tick: 1, ship: ship(length: 2, draft: 3))]),
                        upgrades: .zero)
        sim.advance()
        expectEqual(sim.canBerth(shipID: 1, atSlot: 2), .tooLong, "length must fit the quay")
        expectEqual(sim.canBerth(shipID: 1, atSlot: 1), .tooShallow, "draft 3 cannot use a depth-2 slot")
        expectEqual(sim.canBerth(shipID: 1, atSlot: 0), .none, "a legal berth is accepted")
    }

    static func testChannelIsExclusive() {
        let quay = harbour(slots: Array(repeating: HJSlot(depth: 5, equipment: .crane), count: 6),
                           channel: 20)
        var sim = HJSim(def: shift(harbor: quay, arrivals: [
            HJArrival(tick: 1, ship: ship(id: 1)),
            HJArrival(tick: 1, ship: ship(id: 2)),
        ]), upgrades: .zero)
        sim.advance()
        expectEqual(sim.berth(shipID: 1, atSlot: 0), .none, "first ship enters")
        expectEqual(sim.canBerth(shipID: 2, atSlot: 2), .channelBusy, "channel admits one ship at a time")
        for _ in 0..<20 { sim.advance() }
        expectEqual(sim.canBerth(shipID: 2, atSlot: 2), .none, "channel frees when the transit ends")
    }

    static func testTideTriangleWave() {
        let quay = harbour(slots: [HJSlot(depth: 3, equipment: .crane)],
                           amplitude: 1, step: 10)
        let sim = HJSim(def: shift(harbor: quay, arrivals: []), upgrades: .zero)
        expectEqual(sim.tideOffset(at: 0), -1, "cycle starts at low water")
        expectEqual(sim.tideOffset(at: 10), 0, "one step up after one step of ticks")
        expectEqual(sim.tideOffset(at: 20), 1, "high water at the top of the ramp")
        expectEqual(sim.tideOffset(at: 30), 0, "and back down")
        expectEqual(sim.tideOffset(at: 40), -1, "full cycle is 4 steps at amplitude 1")
        expectEqual(sim.tideOffset(at: 41), -1, "cycle repeats")
    }

    static func testGroundingHoldsTheBerth() {
        let quay = harbour(slots: [HJSlot(depth: 3, equipment: .crane),
                                   HJSlot(depth: 3, equipment: .crane)],
                           channel: 1, amplitude: 1, step: 10)
        // Ship of draft 4 can only enter at high water (depth 3 + 1).
        var sim = HJSim(def: shift(harbor: quay, arrivals: [
            HJArrival(tick: 1, ship: ship(length: 2, draft: 4, tons: 1)),
        ]), upgrades: .zero)
        while sim.tick < 20 { sim.advance() }          // high water
        expectEqual(sim.berth(shipID: 1, atSlot: 0), .none, "enters on the tide")
        while sim.tick < 32 { sim.advance() }          // water has fallen
        expectEqual(sim.ships[0].state, .aground, "falling water grounds the hull")
        expect(!sim.depart(shipID: 1), "an aground ship cannot leave")
        expect(sim.counters.groundings >= 1, "grounding is counted for the gate")
        expect(sim.ships[0].slots != nil, "an aground ship still holds its berths")
    }

    static func testMismatchedGearCostsMore() {
        let matched = harbour(slots: [HJSlot(depth: 5, equipment: .crane),
                                      HJSlot(depth: 5, equipment: .crane)], channel: 1)
        let wrong = harbour(slots: [HJSlot(depth: 5, equipment: .pipeline),
                                    HJSlot(depth: 5, equipment: .pipeline)], channel: 1)
        func unloadTicks(_ quay: HJHarborDef) -> Int {
            var sim = HJSim(def: shift(harbor: quay, arrivals: [
                HJArrival(tick: 1, ship: ship(tons: 4, cargo: .container)),
            ]), upgrades: .zero)
            sim.advance()
            _ = sim.berth(shipID: 1, atSlot: 0)
            var t = 0
            while sim.ships[0].unloadLeft > 0 && t < 10_000 { sim.advance(); t += 1 }
            return t
        }
        let fast = unloadTicks(matched), slow = unloadTicks(wrong)
        expect(slow > fast * 2, "wrong gear costs ×2.5: \(slow) vs \(fast)")
    }

    static func testPatienceOnlyBurnsWhileWaiting() {
        let quay = harbour(slots: [HJSlot(depth: 5, equipment: .crane),
                                   HJSlot(depth: 5, equipment: .crane)], channel: 40)
        var sim = HJSim(def: shift(harbor: quay, arrivals: [
            HJArrival(tick: 1, ship: ship(patience: 200)),
        ]), upgrades: .zero)
        sim.advance()
        for _ in 0..<10 { sim.advance() }
        let afterWaiting = sim.ships[0].patienceLeft
        expect(afterWaiting < 200, "patience burns on the roadstead")
        _ = sim.berth(shipID: 1, atSlot: 0)
        let atBerthing = sim.ships[0].patienceLeft
        for _ in 0..<30 { sim.advance() }
        expectEqual(sim.ships[0].patienceLeft, atBerthing, "patience freezes once under way")
    }

    static func testRoadsteadOverflowLosesShip() {
        let quay = harbour(slots: [HJSlot(depth: 5, equipment: .crane)], roadstead: 2)
        var sim = HJSim(def: shift(harbor: quay, arrivals: [
            HJArrival(tick: 1, ship: ship(id: 1)),
            HJArrival(tick: 1, ship: ship(id: 2)),
            HJArrival(tick: 1, ship: ship(id: 3)),
        ]), upgrades: .zero)
        sim.advance()
        expectEqual(sim.waitingShips.count, 2, "roadstead holds its capacity")
        expectEqual(sim.ships.first(where: { $0.id == 3 })?.state, .lost, "the overflow ship is lost")
        expectEqual(sim.reputation, HJTuning.baseReputation - 1, "and costs reputation")
    }

    static func testSlotsFreeAtStartOfDeparture() {
        let quay = harbour(slots: Array(repeating: HJSlot(depth: 5, equipment: .crane), count: 4),
                           channel: 20)
        var sim = HJSim(def: shift(harbor: quay, arrivals: [
            HJArrival(tick: 1, ship: ship(id: 1, tons: 1)),
        ]), upgrades: .zero)
        sim.advance()
        _ = sim.berth(shipID: 1, atSlot: 0)
        while sim.ships[0].state == .transitingIn { sim.advance() }
        while sim.ships[0].unloadLeft > 0 { sim.advance() }
        expect(sim.depart(shipID: 1), "a finished ship departs")
        expectEqual(sim.ships[0].state, .transitingOut, "and is under way")
        expect(sim.occupiedSlots.isEmpty, "its berths are free the moment it pulls out")
    }

    static func testUpgradesApply() {
        let quay = harbour(slots: [HJSlot(depth: 1, equipment: .crane),
                                   HJSlot(depth: 1, equipment: .crane)], channel: 100)
        var plain = HJSim(def: shift(harbor: quay,
                                     arrivals: [HJArrival(tick: 1, ship: ship(draft: 2))]),
                          upgrades: .zero)
        plain.advance()
        expectEqual(plain.canBerth(shipID: 1, atSlot: 0), .tooShallow, "draft 2 over depth 1 is refused")

        var dredged = HJSim(def: shift(harbor: quay,
                                       arrivals: [HJArrival(tick: 1, ship: ship(draft: 2))]),
                            upgrades: HJUpgradeLevels(cranes: 0, tugs: 0, dredge: 1,
                                                      roadstead: 0, crew: 0))
        dredged.advance()
        expectEqual(dredged.canBerth(shipID: 1, atSlot: 0), .none, "dredging one level admits it")

        let crewed = HJSim(def: shift(harbor: quay, arrivals: []),
                           upgrades: HJUpgradeLevels(cranes: 0, tugs: 0, dredge: 0,
                                                     roadstead: 0, crew: 2))
        expectEqual(crewed.reputation, HJTuning.baseReputation + 2, "crew raises starting reputation")
    }

    static func testDeterminism() {
        let quay = harbour(slots: Array(repeating: HJSlot(depth: 4, equipment: .crane), count: 6),
                           channel: 15, amplitude: 1, step: 12)
        let arrivals = (1...6).map { HJArrival(tick: $0 * 7, ship: ship(id: $0, tons: 3)) }
        func replay() -> [Int] {
            var sim = HJSim(def: shift(harbor: quay, arrivals: arrivals), upgrades: .zero)
            var trace: [Int] = []
            for _ in 0..<400 {
                sim.advance()
                if let w = sim.waitingShips.first, !sim.channelBusy {
                    _ = sim.berth(shipID: w.id, atSlot: 0)
                }
                for s in sim.ships where s.state == .berthed && s.unloadLeft == 0 {
                    _ = sim.depart(shipID: s.id)
                }
                trace.append(sim.counters.tonsServed)
            }
            return trace
        }
        expectEqual(replay(), replay(), "the same inputs must produce the same trace")
    }
}
```

- [ ] **Step 2: Write the harness build script**

`tools/HarborForge/build.sh`:

```bash
#!/bin/bash
set -e
cd "$(dirname "$0")/../.."
swiftc -O \
  "Harbor Jam/HJSimModel.swift" \
  "Harbor Jam/HJSim.swift" \
  "Harbor Jam/HJShiftCatalog.swift" \
  tools/HarborForge/SimTests.swift \
  tools/HarborForge/main.swift \
  -o tools/HarborForge/harborforge
echo "built tools/HarborForge/harborforge"
```

`chmod +x tools/HarborForge/build.sh`. Create a minimal `tools/HarborForge/main.swift` for now:

```swift
import Foundation

let args = CommandLine.arguments
let command = args.count > 1 ? args[1] : "test"
switch command {
case "test":
    exit(SimTests.run() ? 0 : 1)
default:
    print("unknown command: \(command)")
    exit(2)
}
```

- [ ] **Step 3: Run the tests and watch them fail**

```bash
cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam" && ./tools/HarborForge/build.sh
```

Expected: compilation fails with `cannot find 'HJSim' in scope`. That is the correct starting state.

- [ ] **Step 4: Implement the simulation**

`Harbor Jam/HJSim.swift` — Foundation only. The tick order below is normative; the app and the harness both depend on it exactly.

```swift
import Foundation

struct HJSim {
    let def: HJShiftDef
    let upgrades: HJUpgradeLevels

    private(set) var tick: Int = 0
    private(set) var ships: [HJShip] = []
    private(set) var reputation: Int
    private(set) var counters = HJSimCounters()
    private(set) var endTick: Int? = nil

    private var pending: [HJArrival]        // not yet arrived, ascending by tick
    private let roadsteadCapacity: Int

    init(def: HJShiftDef, upgrades: HJUpgradeLevels) {
        self.def = def
        self.upgrades = upgrades
        self.reputation = HJTuning.baseReputation + upgrades.crew
        self.pending = def.arrivals.sorted { $0.tick < $1.tick }
        self.roadsteadCapacity = def.harbor.roadsteadCapacity + upgrades.roadstead
    }

    // MARK: - Derived state

    /// Triangle wave over 4·amplitude steps, starting at low water. Integer by
    /// construction so the player can count ticks to the turn.
    func tideOffset(at t: Int) -> Int {
        let a = def.harbor.tideAmplitude
        guard a > 0, def.harbor.tideStepTicks > 0 else { return 0 }
        let steps = 4 * a
        let s = (t / def.harbor.tideStepTicks) % steps
        let up = s <= 2 * a ? s : steps - s
        return up - a
    }
    var tideOffset: Int { tideOffset(at: tick) }

    func effectiveDepth(slot: Int) -> Int {
        def.harbor.slots[slot].depth + upgrades.dredge + tideOffset
    }

    func isOutOfService(slot: Int) -> Bool {
        def.outages.contains { $0.slot == slot && tick >= $0.startTick && tick < $0.endTick }
    }

    var stormActive: Bool {
        def.storms.contains { tick >= $0.startTick && tick < $0.endTick }
    }

    var occupiedSlots: Set<Int> {
        var out = Set<Int>()
        for s in ships where s.holdsBerth {
            if let r = s.slots { for i in r { out.insert(i) } }
        }
        return out
    }

    var channelBusy: Bool {
        ships.contains { $0.state == .transitingIn || $0.state == .transitingOut }
    }

    var waitingShips: [HJShip] { ships.filter { $0.state == .waiting } }

    var isFailed: Bool { reputation <= 0 }

    var isOver: Bool {
        isFailed || (pending.isEmpty && ships.allSatisfy { $0.state == .served || $0.state == .lost })
    }

    // MARK: - Commands

    func canBerth(shipID: Int, atSlot slot: Int) -> HJBerthRefusal {
        guard let ship = ships.first(where: { $0.id == shipID }) else { return .notWaiting }
        guard ship.state == .waiting else { return .notWaiting }
        guard slot >= 0, slot + ship.length <= def.harbor.slots.count else { return .tooLong }
        if channelBusy { return .channelBusy }
        let taken = occupiedSlots
        for i in slot..<(slot + ship.length) {
            if taken.contains(i) { return .occupied }
            if isOutOfService(slot: i) { return .outage }
        }
        for i in slot..<(slot + ship.length) where effectiveDepth(slot: i) < ship.draft {
            return .tooShallow
        }
        return .none
    }

    mutating func berth(shipID: Int, atSlot slot: Int) -> HJBerthRefusal {
        let refusal = canBerth(shipID: shipID, atSlot: slot)
        if refusal == .channelBusy { counters.channelRefusals += 1 }
        guard refusal == .none, let idx = ships.firstIndex(where: { $0.id == shipID })
        else { return refusal }

        var ship = ships[idx]
        ship.berthStart = slot
        ship.state = .transitingIn
        ship.transitLeft = transitTicks(for: ship)
        let matched = def.harbor.slots[slot].equipment == ship.cargo.equipment
        if !matched { counters.mismatchedUnloads += 1 }
        ship.unloadLeft = unloadWork(tons: ship.tons, cargo: ship.cargo, matched: matched)
        ships[idx] = ship
        return .none
    }

    mutating func depart(shipID: Int) -> Bool {
        guard !channelBusy,
              let idx = ships.firstIndex(where: { $0.id == shipID }),
              ships[idx].state == .berthed,
              ships[idx].unloadLeft <= 0
        else { return false }
        var ship = ships[idx]
        ship.state = .transitingOut
        ship.transitLeft = transitTicks(for: ship)
        ship.berthStart = nil          // the berth frees the moment she pulls out
        ships[idx] = ship
        return true
    }

    // MARK: - The tick

    /// Order is normative. Arrivals first so a ship can be berthed the tick it
    /// shows up; grounding after transits so a hull that has just moored is
    /// judged against the water it is actually sitting in.
    mutating func advance() {
        guard !isOver else { return }
        tick += 1
        admitArrivals()
        advanceTransits()
        advanceUnloading()
        updateGrounding()
        burnPatience()
        if isOver && endTick == nil { endTick = tick }
    }

    private mutating func admitArrivals() {
        while let next = pending.first, next.tick <= tick {
            pending.removeFirst()
            var ship = next.ship
            ship.patienceLeft = ship.patienceTicks
            if waitingShips.count >= roadsteadCapacity {
                ship.state = .lost
                ships.append(ship)
                loseReputation()
            } else {
                ship.state = .waiting
                ships.append(ship)
            }
        }
    }

    private mutating func advanceTransits() {
        for i in ships.indices {
            guard ships[i].state == .transitingIn || ships[i].state == .transitingOut else { continue }
            ships[i].transitLeft -= 1
            guard ships[i].transitLeft <= 0 else { continue }
            if ships[i].state == .transitingIn {
                ships[i].state = .berthed
            } else {
                ships[i].state = .served
                counters.shipsServed += 1
                counters.tonsServed += ships[i].tons
                counters.revenue += revenue(for: ships[i])
            }
        }
    }

    private mutating func advanceUnloading() {
        for i in ships.indices where ships[i].state == .berthed || ships[i].state == .aground {
            if ships[i].unloadLeft > 0 { ships[i].unloadLeft -= 2 }
        }
    }

    private mutating func updateGrounding() {
        for i in ships.indices {
            guard let slots = ships[i].slots,
                  ships[i].state == .berthed || ships[i].state == .aground else { continue }
            let shallow = slots.contains { effectiveDepth(slot: $0) < ships[i].draft }
            if shallow && ships[i].state == .berthed {
                ships[i].state = .aground
                counters.groundings += 1
            } else if !shallow && ships[i].state == .aground {
                ships[i].state = .berthed
            }
        }
    }

    private mutating func burnPatience() {
        let burn = stormActive ? HJTuning.patiencePerTickInStorm : HJTuning.patiencePerTick
        for i in ships.indices where ships[i].state == .waiting {
            ships[i].patienceLeft -= burn
            if ships[i].patienceLeft <= 0 {
                ships[i].state = .lost
                loseReputation()
            }
        }
    }

    private mutating func loseReputation() {
        reputation -= 1
        counters.shipsLost += 1
    }

    // MARK: - Derived numbers

    private func transitTicks(for ship: HJShip) -> Int {
        var t = def.harbor.channelTransitTicks
        t = t * (100 - HJTuning.transitDiscountPerTugLevel * upgrades.tugs) / 100
        if ship.length >= HJTuning.longShipLength,
           HJCatalog.ports.first(where: { $0.index == def.port })?.longShipTransitPenalty == true {
            t = t * 3 / 2
        }
        return max(1, t)
    }

    private func unloadWork(tons: Int, cargo: HJCargo, matched: Bool) -> Int {
        var w = tons * HJTuning.workPerTon(cargo) * (matched ? 2 : 5)
        w = w * (100 - HJTuning.unloadDiscountPerCraneLevel * upgrades.cranes) / 100
        return max(2, w)
    }

    private func revenue(for ship: HJShip) -> Int {
        ship.tons * HJTuning.rate(ship.cargo) * (ship.isVIP ? HJTuning.vipRateMultiplier : 1)
    }

    func score() -> Int {
        let finished = endTick ?? tick
        let speed = max(0, def.parTicks - finished) * HJTuning.speedRate
        return counters.revenue + speed
    }

    func stars() -> Int {
        guard !isFailed, isOver else { return 0 }
        let s = score()
        if s >= def.target3 { return 3 }
        if s >= def.target2 { return 2 }
        return 1
    }
}
```

- [ ] **Step 5: Register `HJSim.swift` in the pbxproj**

```
PBXBuildFile:      C0DE520000000000000002 /* HJSim.swift in Sources */ = {isa = PBXBuildFile; fileRef = C0DE510000000000000002 /* HJSim.swift */; };
PBXFileReference:  C0DE510000000000000002 /* HJSim.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = HJSim.swift; sourceTree = "<group>"; };
group children:    C0DE510000000000000002 /* HJSim.swift */,
Sources phase:     C0DE520000000000000002 /* HJSim.swift in Sources */,
```

- [ ] **Step 6: Run the tests until they pass**

```bash
cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam" && ./tools/HarborForge/build.sh && ./tools/HarborForge/harborforge test
```

Expected: `SIM TESTS OK (10 cases)` and exit status 0. Every `FAIL` line names the rule that is wrong — fix the simulation, not the test, unless the test contradicts spec section 3.5.

- [ ] **Step 7: Verify the app still builds**

The `xcodebuild` Debug command from Task 2 Step 4, expecting `** BUILD SUCCEEDED **`.

- [ ] **Step 8: Commit**

```bash
git add "Harbor Jam/HJSim.swift" tools/HarborForge "Harbor Jam.xcodeproj/project.pbxproj"
git commit -m "Sim: berthing, tide, grounding, channel and patience with 10 rule tests"
```

---

## Task 5: Forward shift generation

Levels are generated **forward** — a random-but-legal harbour and arrival stream — never by undoing a solution. The previous game was built backwards and had no puzzle in it; this task is where that mistake is structurally prevented.

**Files:**
- Create: `tools/HarborForge/Generate.swift`
- Modify: `tools/HarborForge/build.sh`, `tools/HarborForge/main.swift`

**Interfaces:**
- Consumes: `HJPortTemplate`, `HJShiftDef`, `HJSim` from Tasks 2–4.
- Produces: `ForgeRNG` (SplitMix64), `forgeHarbor(template:rng:)`, `forgeArrivals(template:harbor:rng:)`, `forgeShift(port:shift:salt:) -> HJShiftDef` with `parTicks: 0, target2: 0, target3: 0` (Task 6 fills them in).

- [ ] **Step 1: Write the generator**

`tools/HarborForge/Generate.swift`:

```swift
import Foundation

/// SplitMix64 — identical sequences across runs and machines for a given seed.
struct ForgeRNG {
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
        upper <= 0 ? 0 : Int(next() % UInt64(upper))
    }
    mutating func inRange(_ r: ClosedRange<Int>) -> Int {
        r.lowerBound + int(r.upperBound - r.lowerBound + 1)
    }
    mutating func pick<T>(_ xs: [T]) -> T { xs[int(xs.count)] }
}

func forgeSeed(port: Int, shift: Int, salt: Int) -> UInt64 {
    UInt64(0x484A) &* 0x9E3779B97F4A7C15
        &+ UInt64(port) &* 7919 &+ UInt64(shift) &* 104729 &+ UInt64(salt) &* 1_000_003
}

func forgeHarbor(template t: HJPortTemplate, rng: inout ForgeRNG) -> HJHarborDef {
    var slots: [HJSlot] = []
    for _ in 0..<t.slotCount {
        slots.append(HJSlot(depth: rng.inRange(t.depthRange),
                            equipment: rng.pick(t.equipment)))
    }
    return HJHarborDef(slots: slots,
                       channelTransitTicks: t.channelTransitTicks,
                       tideAmplitude: t.tideAmplitude,
                       tideStepTicks: t.tideStepTicks,
                       roadsteadCapacity: 4)
}

func forgeArrivals(template t: HJPortTemplate, harbor: HJHarborDef,
                   rng: inout ForgeRNG) -> [HJArrival] {
    let count = rng.inRange(t.shipCount)
    let maxDepth = (harbor.slots.map { $0.depth }.max() ?? 5) + t.tideAmplitude
    var arrivals: [HJArrival] = []
    var at = 20
    for id in 1...count {
        let length = rng.inRange(t.shipLengths)
        // Never generate a hull that no berth in this harbour could ever take:
        // an impossible ship is not difficulty, it is a broken level.
        let draft = min(rng.inRange(t.draftRange), maxDepth)
        let cargo = rng.pick(t.cargoes)
        let tons = 2 + rng.int(5)
        let vip = t.usesVIP && rng.int(6) == 0
        let patience = (vip ? 900 : 1600) + rng.int(600)
        arrivals.append(HJArrival(tick: at,
                                  ship: HJShip(id: id, length: length, draft: draft,
                                               cargo: cargo, tons: tons,
                                               patienceTicks: patience * 2, isVIP: vip)))
        at += 30 + rng.int(50)
    }
    return arrivals
}

func forgeEvents(template t: HJPortTemplate, harbor: HJHarborDef, span: Int,
                 rng: inout ForgeRNG) -> ([HJSlotOutage], [HJStormWindow]) {
    var outages: [HJSlotOutage] = []
    var storms: [HJStormWindow] = []
    if t.usesOutages {
        for _ in 0..<(1 + rng.int(2)) {
            let start = 100 + rng.int(max(1, span - 400))
            outages.append(HJSlotOutage(slot: rng.int(harbor.slots.count),
                                        startTick: start,
                                        endTick: start + 200 + rng.int(201)))
        }
    }
    if t.usesStorms {
        let start = 150 + rng.int(max(1, span - 700))
        storms.append(HJStormWindow(startTick: start, endTick: start + 600))
    }
    return (outages, storms)
}

func forgeShift(port: Int, shift: Int, salt: Int) -> HJShiftDef {
    let t = HJCatalog.ports[port - 1]
    var rng = ForgeRNG(seed: forgeSeed(port: port, shift: shift, salt: salt))
    let harbor = forgeHarbor(template: t, rng: &rng)
    let arrivals = forgeArrivals(template: t, harbor: harbor, rng: &rng)
    let span = (arrivals.last?.tick ?? 500) + 600
    let (outages, storms) = forgeEvents(template: t, harbor: harbor, span: span, rng: &rng)
    return HJShiftDef(port: port, shift: shift, harbor: harbor, arrivals: arrivals,
                      outages: outages, storms: storms,
                      parTicks: 0, target2: 0, target3: 0)
}
```

- [ ] **Step 2: Add `Generate.swift` to the build script**

Insert `tools/HarborForge/Generate.swift` into the `swiftc` file list in `tools/HarborForge/build.sh`, before `tools/HarborForge/main.swift`.

- [ ] **Step 3: Add a `generate` command that proves determinism**

In `tools/HarborForge/main.swift`, add a case to the switch:

```swift
case "generate":
    var mismatches = 0
    for port in 1...HJCatalog.portCount {
        for shift in 1...HJCatalog.shiftsPerPort {
            let a = forgeShift(port: port, shift: shift, salt: 0)
            let b = forgeShift(port: port, shift: shift, salt: 0)
            if a != b { mismatches += 1 }
            if a.arrivals.isEmpty { mismatches += 1 }
        }
    }
    print(mismatches == 0
          ? "GENERATE OK — \(HJCatalog.totalShifts) shifts, deterministic, all non-empty"
          : "GENERATE FAILED — \(mismatches) mismatches")
    exit(mismatches == 0 ? 0 : 1)
```

- [ ] **Step 4: Run it**

```bash
cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam" && ./tools/HarborForge/build.sh && ./tools/HarborForge/harborforge generate
```

Expected: `GENERATE OK — 84 shifts, deterministic, all non-empty`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add tools/HarborForge
git commit -m "Forge: forward shift generation, deterministic per seed"
```

---

## Task 6: Policies

**Files:**
- Create: `tools/HarborForge/Policies.swift`
- Modify: `tools/HarborForge/build.sh`, `tools/HarborForge/main.swift`

**Interfaces:**
- Produces: `enum ForgePolicy { case greedy, random, smart }`, `func forgeRun(def: HJShiftDef, upgrades: HJUpgradeLevels, policy: ForgePolicy, seed: UInt64) -> ForgeResult`, `struct ForgeResult { var score: Int; var stars: Int; var failed: Bool; var endTick: Int; var counters: HJSimCounters }`.

- [ ] **Step 1: Write the policies**

`tools/HarborForge/Policies.swift`:

```swift
import Foundation

enum ForgePolicy { case greedy, random, smart }

struct ForgeResult {
    var score: Int
    var stars: Int
    var failed: Bool
    var endTick: Int
    var counters: HJSimCounters
}

private let forgeTickCap = 20_000

func forgeRun(def: HJShiftDef, upgrades: HJUpgradeLevels,
              policy: ForgePolicy, seed: UInt64) -> ForgeResult {
    var sim = HJSim(def: def, upgrades: upgrades)
    var rng = ForgeRNG(seed: seed)
    var guardTicks = 0

    while !sim.isOver && guardTicks < forgeTickCap {
        guardTicks += 1
        applyDepartures(&sim, policy: policy)
        applyBerthing(&sim, policy: policy, rng: &rng)
        sim.advance()
    }
    return ForgeResult(score: sim.score(), stars: sim.stars(), failed: sim.isFailed,
                       endTick: guardTicks, counters: sim.counters)
}

private func applyDepartures(_ sim: inout HJSim, policy: ForgePolicy) {
    guard !sim.channelBusy else { return }
    let done = sim.ships.filter { $0.state == .berthed && $0.unloadLeft <= 0 }
    guard let first = done.first else { return }

    switch policy {
    case .greedy, .random:
        _ = sim.depart(shipID: first.id)
    case .smart:
        // Hold the channel if a waiting ship is nearly out of patience and a
        // berth exists for her right now: sending costs the channel, and a lost
        // ship costs reputation.
        let urgent = sim.waitingShips.contains { ship in
            ship.patienceLeft < 240 &&
            (0...(sim.def.harbor.slots.count - ship.length)).contains { slot in
                sim.canBerth(shipID: ship.id, atSlot: slot) == .none
            }
        }
        if !urgent { _ = sim.depart(shipID: first.id) }
    }
}

private func applyBerthing(_ sim: inout HJSim, policy: ForgePolicy, rng: inout ForgeRNG) {
    guard !sim.channelBusy else { return }
    let quay = sim.def.harbor.slots.count

    switch policy {
    case .greedy:
        // First ship, first slot that fits. This is the policy the gate must
        // defeat: if it three-stars the corpus, the game has no puzzle in it.
        for ship in sim.waitingShips {
            for slot in 0...(max(0, quay - ship.length)) where sim.canBerth(shipID: ship.id, atSlot: slot) == .none {
                _ = sim.berth(shipID: ship.id, atSlot: slot)
                return
            }
        }
    case .random:
        let waiting = sim.waitingShips
        guard !waiting.isEmpty else { return }
        let ship = waiting[rng.int(waiting.count)]
        let legal = (0...(max(0, quay - ship.length))).filter {
            sim.canBerth(shipID: ship.id, atSlot: $0) == .none
        }
        guard !legal.isEmpty else { return }
        _ = sim.berth(shipID: ship.id, atSlot: legal[rng.int(legal.count)])
    case .smart:
        var best: (ship: Int, slot: Int, cost: Int)? = nil
        let taken = sim.occupiedSlots
        for ship in sim.waitingShips.sorted(by: { $0.patienceLeft < $1.patienceLeft }) {
            for slot in 0...(max(0, quay - ship.length)) {
                guard sim.canBerth(shipID: ship.id, atSlot: slot) == .none else { continue }
                var cost = 0
                // Best fit: prefer a gap this hull nearly fills, so long hulls
                // keep somewhere to go.
                cost += gapWaste(slot: slot, length: ship.length, quay: quay, taken: taken) * 10
                // Matching gear is worth far more than a tidy quay.
                if sim.def.harbor.slots[slot].equipment != ship.cargo.equipment { cost += 60 }
                // Do not park a deep hull where the falling tide will strand her.
                if wouldGround(sim: sim, ship: ship, slot: slot) { cost += 120 }
                if best == nil || cost < best!.cost { best = (ship.id, slot, cost) }
            }
        }
        if let b = best { _ = sim.berth(shipID: b.ship, atSlot: b.slot) }
    }
}

/// Free cells left on both sides of a hull placed at `slot`, counting only runs
/// too short to take the longest hull the game can produce.
private func gapWaste(slot: Int, length: Int, quay: Int, taken: Set<Int>) -> Int {
    var waste = 0
    var left = slot - 1
    var run = 0
    while left >= 0 && !taken.contains(left) { run += 1; left -= 1 }
    if (1...4).contains(run) { waste += run }
    var right = slot + length
    run = 0
    while right < quay && !taken.contains(right) { run += 1; right += 1 }
    if (1...4).contains(run) { waste += run }
    return waste
}

/// Would the water under this berth fall below the hull's draft before she can
/// finish unloading and leave?
private func wouldGround(sim: HJSim, ship: HJShip, slot: Int) -> Bool {
    let work = ship.tons * HJTuning.workPerTon(ship.cargo) * 5 / 2
    let horizon = sim.tick + work / 2 + sim.def.harbor.channelTransitTicks * 2
    guard sim.def.harbor.tideAmplitude > 0 else { return false }
    var t = sim.tick
    while t < horizon {
        let depth = sim.def.harbor.slots[slot..<(slot + ship.length)].map { $0.depth }.min() ?? 0
        if depth + sim.upgrades.dredge + sim.tideOffset(at: t) < ship.draft { return true }
        t += sim.def.harbor.tideStepTicks
    }
    return false
}
```

- [ ] **Step 2: Add `Policies.swift` to the build script**

Insert into the `swiftc` list in `build.sh`, after `Generate.swift`.

- [ ] **Step 3: Add a smoke command**

In `main.swift`:

```swift
case "policies":
    let def = forgeShift(port: 1, shift: 1, salt: 0)
    for (name, p) in [("G", ForgePolicy.greedy), ("R", .random), ("S", .smart)] {
        let r = forgeRun(def: def, upgrades: .zero, policy: p, seed: 12345)
        print("\(name)  score=\(r.score)  served=\(r.counters.shipsServed)  lost=\(r.counters.shipsLost)  ticks=\(r.endTick)")
    }
    exit(0)
```

- [ ] **Step 4: Run it**

```bash
cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam" && ./tools/HarborForge/build.sh && ./tools/HarborForge/harborforge policies
```

Assertion (checked by reading the three lines): every policy terminates, and `served + lost` equals the shift's arrival count for each. A policy that runs to `forgeTickCap` (`ticks=20000`) means the loop cannot make progress — fix that before continuing, because the gate would then measure a stall rather than a strategy.

- [ ] **Step 5: Commit**

```bash
git add tools/HarborForge
git commit -m "Forge: greedy, random and smart policies"
```

---

## Task 7: The acceptance gate — GO / NO-GO

**This task can stop the project.** Nothing in Tasks 8–15 may begin until `harborforge gate` exits 0.

**Files:**
- Create: `tools/HarborForge/Gate.swift`
- Create: `tools/HarborForge/BASELINE.md`
- Create: `Harbor Jam/shifts.json` (generated output)
- Modify: `tools/HarborForge/build.sh`, `tools/HarborForge/main.swift`, `Harbor Jam/HJShiftCatalog.swift` (tuning only), `Harbor Jam.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces: `harborforge gate` (measures and prints, exit 0 only if all seven clauses pass), `harborforge bake` (writes `Harbor Jam/shifts.json`), and in `HJShiftCatalog.swift`: `HJCatalog.loadShifts() -> [HJShiftDef]`, `HJCatalog.shift(port:shift:) -> HJShiftDef?`.

- [ ] **Step 1: Write the gate**

`tools/HarborForge/Gate.swift`. Adversarial selection lives here: a candidate shift is kept only if greedy play does measurably worse than smart play on it.

```swift
import Foundation

struct ForgeShiftReport {
    var port: Int
    var shift: Int
    var def: HJShiftDef
    var smart: ForgeResult
    var greedy: ForgeResult
    var random: ForgeResult
}

/// Accept a candidate only where greedy underperforms. This is the inverse of
/// the previous generator, which verified that a canonical solution still
/// worked and thereby filtered OUT every board where a mechanic mattered.
func forgeAccept(port: Int, shift: Int, maxSalts: Int = 60) -> ForgeShiftReport? {
    for salt in 0..<maxSalts {
        var def = forgeShift(port: port, shift: shift, salt: salt)
        let s = forgeRun(def: def, upgrades: .zero, policy: .smart, seed: 1)
        guard !s.failed, s.counters.shipsLost == 0 else { continue }

        def.parTicks = s.endTick
        def.target3 = s.score * HJTuning.target3Percent / 100
        def.target2 = s.score * HJTuning.target2Percent / 100

        let g = forgeRun(def: def, upgrades: .zero, policy: .greedy, seed: 2)
        let r = forgeRun(def: def, upgrades: .zero, policy: .random, seed: 3)

        // Ports 1 and 2 teach; they are allowed to be gentle. From port 3 the
        // shift is only accepted if greedy actually loses ground.
        if port >= 3 {
            let greedyBeaten = g.failed || g.stars < 3
            guard greedyBeaten else { continue }
        }
        if r.stars >= 3 { continue }
        return ForgeShiftReport(port: port, shift: shift, def: def,
                                smart: s, greedy: g, random: r)
    }
    return nil
}

func forgeGate() -> (ok: Bool, text: String, reports: [ForgeShiftReport]) {
    var reports: [ForgeShiftReport] = []
    var unbuildable: [String] = []
    for port in 1...HJCatalog.portCount {
        for shift in 1...HJCatalog.shiftsPerPort {
            if let r = forgeAccept(port: port, shift: shift) {
                reports.append(r)
            } else {
                unbuildable.append("\(port)-\(shift)")
            }
        }
    }

    func pct(_ n: Int, _ d: Int) -> Double { d == 0 ? 0 : Double(n) * 100 / Double(d) }
    let late = reports.filter { $0.port >= 3 }
    let veryLate = reports.filter { $0.port >= 5 }

    let smartClears = reports.filter { $0.smart.stars >= 1 }.count
    let smartThree = reports.filter { $0.smart.stars == 3 }.count
    let greedyThreeLate = late.filter { $0.greedy.stars == 3 }.count
    let greedyFailedVeryLate = veryLate.filter { $0.greedy.failed }.count
    let randomThree = reports.filter { $0.random.stars == 3 }.count

    func median(_ xs: [Int]) -> Double {
        guard !xs.isEmpty else { return 0 }
        let s = xs.sorted()
        return s.count % 2 == 1 ? Double(s[s.count / 2])
                                : Double(s[s.count / 2 - 1] + s[s.count / 2]) / 2
    }
    let medS = median(late.map { $0.smart.score })
    let medG = median(late.map { $0.greedy.score })
    let ratio = medG == 0 ? Double.infinity : medS / medG

    let groundingsFromPort2 = reports.filter { $0.port >= 2 }.reduce(0) { $0 + $1.smart.counters.groundings }
    let channelFromPort3 = late.reduce(0) { $0 + $1.smart.counters.channelRefusals }
    let mismatchFromPort4 = reports.filter { $0.port >= 4 }.reduce(0) { $0 + $1.smart.counters.mismatchedUnloads }

    var clauses: [(String, Bool, String)] = []
    clauses.append(("all shifts generate", unbuildable.isEmpty,
                    "\(reports.count)/\(HJCatalog.totalShifts) — missing: \(unbuildable.joined(separator: " "))"))
    clauses.append(("S clears every shift", smartClears == reports.count,
                    "\(smartClears)/\(reports.count)"))
    clauses.append(("S three-stars >= 80 %", pct(smartThree, reports.count) >= 80,
                    String(format: "%.1f %%", pct(smartThree, reports.count))))
    clauses.append(("G three-stars <= 25 % from port 3", pct(greedyThreeLate, late.count) <= 25,
                    String(format: "%.1f %%", pct(greedyThreeLate, late.count))))
    clauses.append(("G fails >= 30 % from port 5", pct(greedyFailedVeryLate, veryLate.count) >= 30,
                    String(format: "%.1f %%", pct(greedyFailedVeryLate, veryLate.count))))
    clauses.append(("R three-stars nothing", randomThree == 0, "\(randomThree)"))
    clauses.append(("median S >= 1.35x median G", ratio >= 1.35,
                    String(format: "%.2fx", ratio)))
    clauses.append(("groundings live from port 2", groundingsFromPort2 > 0, "\(groundingsFromPort2)"))
    clauses.append(("channel refusals live from port 3", channelFromPort3 > 0, "\(channelFromPort3)"))
    clauses.append(("gear mismatch lives from port 4", mismatchFromPort4 > 0, "\(mismatchFromPort4)"))

    var out = "=== HARBOR JAM — ACCEPTANCE GATE ===\n"
    var ok = true
    for (name, pass, detail) in clauses {
        out += "\(pass ? "PASS" : "FAIL")  \(name)  [\(detail)]\n"
        if !pass { ok = false }
    }
    out += ok ? "\nGATE PASSED\n" : "\nGATE FAILED — retune HJTuning / HJCatalog.ports and run again\n"
    return (ok, out, reports)
}
```

- [ ] **Step 2: Add the `gate` and `bake` commands**

In `main.swift`:

```swift
case "gate":
    let (ok, text, _) = forgeGate()
    print(text)
    exit(ok ? 0 : 1)

case "bake":
    let (ok, text, reports) = forgeGate()
    print(text)
    guard ok else { exit(1) }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try! encoder.encode(reports.map { $0.def })
    try! data.write(to: URL(fileURLWithPath: "Harbor Jam/shifts.json"))
    print("baked \(reports.count) shifts to Harbor Jam/shifts.json (\(data.count) bytes)")
    exit(0)
```

Add `tools/HarborForge/Gate.swift` to the `swiftc` list in `build.sh`, after `Policies.swift`.

- [ ] **Step 3: Run the gate**

```bash
cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam" && ./tools/HarborForge/build.sh && ./tools/HarborForge/harborforge gate
```

The output cannot be known in advance. The assertion is: **every one of the ten clauses prints `PASS` and the binary exits 0.**

- [ ] **Step 4: Tune until it passes**

If any clause fails, change **only** `HJTuning` and `HJCatalog.ports` in `Harbor Jam/HJShiftCatalog.swift`, rebuild, re-run. Guidance per failing clause:

- *G three-stars too often from port 3* — raise `shipCount`, shorten patience, or widen `depthRange` downward so the quay has fewer universally usable berths.
- *G does not fail often enough from port 5* — raise `shipCount` and storm frequency, or lower `roadsteadCapacity` in `forgeHarbor`.
- *S does not clear everything* — the ports are too hard, not too easy: lower `shipCount` or lengthen patience.
- *median ratio below 1.35* — the levers greedy ignores are too weak: increase the mismatch penalty's bite by making `.none` more common in `equipment`, or raise `channelTransitTicks`.
- *a mechanic counter is zero* — that mechanic is inert exactly as the previous game's four were. Fix the port template that should be exercising it before touching anything else.

Do not weaken the clauses themselves. If ten tuning rounds do not converge, stop and report: the correct answer at that point is cutting one of the four mechanics, not lowering the bar.

- [ ] **Step 5: Bake the corpus**

```bash
cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam" && ./tools/HarborForge/harborforge bake && ls -la "Harbor Jam/shifts.json"
```

Expected: `GATE PASSED`, then `baked 84 shifts…`, and a non-empty `shifts.json`.

- [ ] **Step 6: Record the measured baseline**

Write `tools/HarborForge/BASELINE.md` containing the exact, unedited output of `harborforge gate`, with a one-line header naming the date and the command. This file is what a later reader trusts instead of re-deriving it.

- [ ] **Step 7: Teach the app to load the corpus**

Append to `Harbor Jam/HJShiftCatalog.swift`:

```swift
extension HJCatalog {
    private static var cache: [HJShiftDef]? = nil

    static func loadShifts() -> [HJShiftDef] {
        if let c = cache { return c }
        guard let url = Bundle.main.url(forResource: "shifts", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([HJShiftDef].self, from: data)
        else {
            cache = []
            return []
        }
        cache = decoded
        return decoded
    }

    static func shift(port: Int, shift: Int) -> HJShiftDef? {
        loadShifts().first { $0.port == port && $0.shift == shift }
    }
}
```

- [ ] **Step 8: Register `shifts.json` as a bundled resource**

```
PBXBuildFile:      C0DE52000000000000000B /* shifts.json in Resources */ = {isa = PBXBuildFile; fileRef = C0DE51000000000000000B /* shifts.json */; };
PBXFileReference:  C0DE51000000000000000B /* shifts.json */ = {isa = PBXFileReference; lastKnownFileType = text.json; path = shifts.json; sourceTree = "<group>"; };
group children:    C0DE51000000000000000B /* shifts.json */,
Resources phase F115417AB24C0E0F4821A9A2:  C0DE52000000000000000B /* shifts.json in Resources */,
```

Do not create a second Resources phase.

- [ ] **Step 9: Prove the app can read all 84**

Add to `main.swift` a `verify` command that decodes `Harbor Jam/shifts.json` from disk and replays every shift with policy S through `HJSim`, asserting `stars >= 1` on all 84:

```swift
case "verify":
    let data = try! Data(contentsOf: URL(fileURLWithPath: "Harbor Jam/shifts.json"))
    let defs = try! JSONDecoder().decode([HJShiftDef].self, from: data)
    var bad = 0
    for d in defs where forgeRun(def: d, upgrades: .zero, policy: .smart, seed: 1).stars < 1 {
        bad += 1
        print("UNCLEARABLE \(d.port)-\(d.shift)")
    }
    print(bad == 0 ? "VERIFY OK — \(defs.count) shifts clearable" : "VERIFY FAILED — \(bad)")
    exit(bad == 0 ? 0 : 1)
```

```bash
cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam" && ./tools/HarborForge/build.sh && ./tools/HarborForge/harborforge verify
```

Expected: `VERIFY OK — 84 shifts clearable`.

- [ ] **Step 10: Commit**

```bash
git add tools/HarborForge "Harbor Jam/shifts.json" "Harbor Jam/HJShiftCatalog.swift" "Harbor Jam.xcodeproj/project.pbxproj"
git commit -m "Gate: adversarial acceptance, baked 84-shift corpus, measured baseline"
```

---

## Task 8: Chart palette and the full sprite set

**Files:**
- Rewrite: `Harbor Jam/HJTheme.swift`
- Modify: `Harbor Jam/HJSprites.swift`
- Create: 20 further imagesets under `Harbor Jam/Assets.xcassets/`

**Interfaces:**
- Consumes: the pipeline decision recorded in `tools/HarborArt/PIPELINE.md` (Task 1).
- Produces: `HJTheme` colour constants named below; `HJSprite` cases `hull2…hull5`, `cargoContainer`, `cargoBulk`, `cargoLiquid`, `berthEmpty`, `berthCrane`, `berthConveyor`, `berthPipeline`, `buoyPort`, `buoyStarboard`, `buoyCardinal`, `tug`, `iconTonnage`, `iconReputation`, `iconTide`, `iconCoin`, `compassRose`, `depthContours`.

- [ ] **Step 1: Replace the palette**

In `Harbor Jam/HJTheme.swift`, replace the colour constants with the chart palette from spec section 7.1 — keep the `display` / `mono` / `body` font helpers and every existing `Shape` (`HJStarShape`, `HJWaveShape`, `HJChevronShape`, `HJGearShape`, `HJTrophyShape`, `HJLockShape`, `HJPulseShape`, `HJArrowShape`) unchanged, since the tab bar and cards still use them. Delete `hullColors`, `cream`, `seafoam`, `driftwood`, `nightWater`, `nightBoard`.

```swift
enum HJTheme {
    static let chartDeep   = Color(red: 0.047, green: 0.125, blue: 0.200)  // #0C2033
    static let chartGrid   = Color(red: 0.086, green: 0.204, blue: 0.294)  // #16344B
    static let contour     = Color(red: 0.184, green: 0.424, blue: 0.525)  // #2F6C86
    static let cyan        = Color(red: 0.373, green: 0.816, blue: 0.910)  // #5FD0E8
    static let cyanSoft    = Color(red: 0.624, green: 0.910, blue: 0.961)  // #9FE8F5
    static let hullFill    = Color(red: 0.071, green: 0.227, blue: 0.322)  // #123A52
    static let gold        = Color(red: 0.949, green: 0.784, blue: 0.251)  // #F2C840
    static let alert       = Color(red: 0.776, green: 0.271, blue: 0.239)  // #C6453D
    static let success     = Color(red: 0.243, green: 0.549, blue: 0.455)  // #3E8C74
    static let warn        = Color(red: 0.910, green: 0.573, blue: 0.353)  // #E8925A
    static let cardBG      = Color(red: 0.071, green: 0.161, blue: 0.243)
    // fonts and shapes below unchanged
}
```

- [ ] **Step 2: Draw the remaining 20 sprites**

One imageset per name, each with the `Contents.json` shape proven in Task 1, following the same drawing restrictions (no `<text>`, no gradients, no filters, no masks). Natural sizes:

| Sprite | Size (pt) | Content |
|---|---|---|
| `hull_2`, `hull_3`, `hull_5` | 88×44, 132×44, 220×44 | Same hull language as `hull_4`: `#123A52` fill, `#5FD0E8` 2 pt outline, bow chevron right, deck cells outlined `#2F6C86` |
| `cargo_container` | 44×44 | Three stacked outlined boxes |
| `cargo_bulk` | 44×44 | Heap arc with three grain dots |
| `cargo_liquid` | 44×44 | Cylinder with a level line |
| `berth_empty` | 44×56 | Quay cell: gold top edge, dashed cell border |
| `berth_crane` | 44×56 | Quay cell plus gantry legs and boom |
| `berth_conveyor` | 44×56 | Quay cell plus an inclined belt with rollers |
| `berth_pipeline` | 44×56 | Quay cell plus a flanged pipe elbow |
| `buoy_port` | 24×32 | Red can buoy, flat top |
| `buoy_starboard` | 24×32 | Green conical buoy, pointed top |
| `buoy_cardinal` | 24×36 | Black-and-yellow pillar with two cones |
| `tug` | 60×36 | Stubby hull with a raised wheelhouse |
| `icon_tonnage` | 28×28 | Crate outline |
| `icon_reputation` | 28×28 | Anchor |
| `icon_tide` | 28×28 | Two stacked wave crests with a level arrow |
| `icon_coin` | 28×28 | Circle with an inner ring |
| `compass_rose` | 120×120 | Eight-point star, north arm gold |
| `depth_contours` | 320×320 | Three nested irregular closed curves, `#2F6C86` hairlines, no fill |

- [ ] **Step 3: Extend the sprite enum**

Replace the body of `HJSprite` with all 21 cases, raw values exactly matching the imageset folder names.

- [ ] **Step 4: Prove every sprite resolves at runtime**

Add to `HJSprites.swift`:

```swift
#if DEBUG
extension HJSprite {
    /// Names a sprite whose asset is missing. A blank image is otherwise silent.
    static var missing: [String] {
        allCases.map(\.rawValue).filter { UIImage(named: $0) == nil }
    }
}
#endif
```

Make `HJSprite` conform to `CaseIterable`, add `import UIKit` under the `#if DEBUG`, and in `HJRootView.body`, inside `.onAppear`, add `#if DEBUG` `assert(HJSprite.missing.isEmpty, "missing sprites: \(HJSprite.missing)")` `#endif`.

- [ ] **Step 5: Build and run**

Build Debug for iPhone 17, install, launch. Assertion: the app launches without tripping the assert. A trip names the exact sprites `actool` did not compile.

- [ ] **Step 6: Commit**

```bash
git add "Harbor Jam/HJTheme.swift" "Harbor Jam/HJSprites.swift" "Harbor Jam/Assets.xcassets" "Harbor Jam/HJRootView.swift"
git commit -m "Art: chart palette and the full 21-sprite set"
```

---

## Task 9: Save layer v3

**Files:**
- Rewrite: `Harbor Jam/HJSave.swift`
- Delete: `Harbor Jam/HJHarborView.swift`, `Harbor Jam/HJDailyView.swift`, `Harbor Jam/HJBoardView.swift`, `Harbor Jam/HJGameView.swift`, `Harbor Jam/HJGameViewModel.swift`, `Harbor Jam/HJEngine.swift`, `Harbor Jam/HJGenerator.swift`, `Harbor Jam/HJModels.swift`
- Modify: `Harbor Jam/HJRootView.swift`, `Harbor Jam/HJAwardsView.swift`, `Harbor Jam/HJMoreView.swift`, `Harbor Jam.xcodeproj/project.pbxproj`

The old files go in this task rather than earlier because the app must keep compiling at every commit, and this is the first task that can replace what they provided.

**Interfaces:**
- Produces: `HJShiftRecord(stars:bestScore:)`, `HJStats`, `HJSaveState`, `HJStore` with `save`, `persist()`, `resetProgress()`, `record(port:shift:)`, `totalStars()`, `isPortUnlocked(_:)`, `isShiftUnlocked(port:shift:)`, `reportShiftWin(port:shift:score:stars:counters:) -> Int`, `reportWatchRun(tons:)`, `upgradeLevel(_:)`, `buyUpgrade(_:) -> Bool`, `upgradeLevels() -> HJUpgradeLevels`, `HJUpgradeLine` enum with `cost(atLevel:)` and `maxLevel`.

- [ ] **Step 1: Write the save layer**

Key facts that must hold: the key is `hbj.state.v3`; every field decodes with `decodeIfPresent(...) ?? default`; `HJUpgradeLine.rawValue` strings are the dictionary keys and must never change once shipped.

```swift
import Foundation
import SwiftUI

struct HJShiftRecord: Codable, Equatable {
    var stars: Int
    var bestScore: Int

    init(stars: Int, bestScore: Int) { self.stars = stars; self.bestScore = bestScore }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        stars = try c.decodeIfPresent(Int.self, forKey: .stars) ?? 0
        bestScore = try c.decodeIfPresent(Int.self, forKey: .bestScore) ?? 0
    }
}

enum HJUpgradeLine: String, CaseIterable, Identifiable {
    case cranes, tugs, dredge, roadstead, crew
    var id: String { rawValue }

    var title: String {
        switch self {
        case .cranes: return "Cranes"
        case .tugs: return "Tugs"
        case .dredge: return "Dredging"
        case .roadstead: return "Roadstead"
        case .crew: return "Crew"
        }
    }
    var detail: String {
        switch self {
        case .cranes: return "Unload 8 % faster per level"
        case .tugs: return "Channel transit 10 % shorter per level"
        case .dredge: return "Every berth one metre deeper per level"
        case .roadstead: return "One more ship may wait per level"
        case .crew: return "Start each shift with one more reputation"
        }
    }
    var maxLevel: Int {
        switch self {
        case .cranes: return 5
        case .tugs: return 3
        default: return 2
        }
    }
    func cost(atLevel level: Int) -> Int { 400 * (level + 1) * (level + 1) }
}

struct HJStats: Codable, Equatable {
    var shiftsCleared = 0
    var tonsServed = 0
    var shipsServed = 0
    var shipsLost = 0
    var groundings = 0
    var flawlessShifts = 0        // cleared with zero ships lost
    var noGroundingShifts = 0

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        shiftsCleared = try c.decodeIfPresent(Int.self, forKey: .shiftsCleared) ?? 0
        tonsServed = try c.decodeIfPresent(Int.self, forKey: .tonsServed) ?? 0
        shipsServed = try c.decodeIfPresent(Int.self, forKey: .shipsServed) ?? 0
        shipsLost = try c.decodeIfPresent(Int.self, forKey: .shipsLost) ?? 0
        groundings = try c.decodeIfPresent(Int.self, forKey: .groundings) ?? 0
        flawlessShifts = try c.decodeIfPresent(Int.self, forKey: .flawlessShifts) ?? 0
        noGroundingShifts = try c.decodeIfPresent(Int.self, forKey: .noGroundingShifts) ?? 0
    }
}

struct HJSaveState: Codable, Equatable {
    var shiftRecords: [String: HJShiftRecord] = [:]   // "port-shift"
    var coins = 0
    var upgrades: [String: Int] = [:]
    var watchBestTons = 0
    var stats = HJStats()
    var soundOn = true
    var hapticsOn = true
    var onboardingSeen = false

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        shiftRecords = try c.decodeIfPresent([String: HJShiftRecord].self, forKey: .shiftRecords) ?? [:]
        coins = try c.decodeIfPresent(Int.self, forKey: .coins) ?? 0
        upgrades = try c.decodeIfPresent([String: Int].self, forKey: .upgrades) ?? [:]
        watchBestTons = try c.decodeIfPresent(Int.self, forKey: .watchBestTons) ?? 0
        stats = try c.decodeIfPresent(HJStats.self, forKey: .stats) ?? HJStats()
        soundOn = try c.decodeIfPresent(Bool.self, forKey: .soundOn) ?? true
        hapticsOn = try c.decodeIfPresent(Bool.self, forKey: .hapticsOn) ?? true
        onboardingSeen = try c.decodeIfPresent(Bool.self, forKey: .onboardingSeen) ?? false
    }
}
```

`HJStore` mirrors the old class: same `@Published save`, `persist()`, `resetProgress()`, `refreshAchievements()`, plus:

```swift
final class HJStore: ObservableObject {
    static let saveKey = "hbj.state.v3"

    func upgradeLevel(_ line: HJUpgradeLine) -> Int { save.upgrades[line.rawValue] ?? 0 }

    func upgradeLevels() -> HJUpgradeLevels {
        HJUpgradeLevels(cranes: upgradeLevel(.cranes), tugs: upgradeLevel(.tugs),
                        dredge: upgradeLevel(.dredge), roadstead: upgradeLevel(.roadstead),
                        crew: upgradeLevel(.crew))
    }

    func buyUpgrade(_ line: HJUpgradeLine) -> Bool {
        let level = upgradeLevel(line)
        guard level < line.maxLevel else { return false }
        let cost = line.cost(atLevel: level)
        guard save.coins >= cost else { return false }
        save.coins -= cost
        save.upgrades[line.rawValue] = level + 1
        persist()
        return true
    }

    func record(port: Int, shift: Int) -> HJShiftRecord? { save.shiftRecords["\(port)-\(shift)"] }
    func totalStars() -> Int { save.shiftRecords.values.reduce(0) { $0 + $1.stars } }
    func isPortUnlocked(_ port: Int) -> Bool { totalStars() >= HJCatalog.starsToUnlock(port: port) }
    func isShiftUnlocked(port: Int, shift: Int) -> Bool {
        guard isPortUnlocked(port) else { return false }
        if shift == 1 { return true }
        return (record(port: port, shift: shift - 1)?.stars ?? 0) >= 1
    }

    /// Returns the stars earned. Coins are credited on every clear, records only improve.
    func reportShiftWin(port: Int, shift: Int, score: Int, stars: Int,
                        counters: HJSimCounters) -> Int {
        let key = "\(port)-\(shift)"
        let old = save.shiftRecords[key]
        save.shiftRecords[key] = HJShiftRecord(stars: max(stars, old?.stars ?? 0),
                                               bestScore: max(score, old?.bestScore ?? 0))
        save.coins += counters.revenue
        save.stats.shiftsCleared += 1
        save.stats.tonsServed += counters.tonsServed
        save.stats.shipsServed += counters.shipsServed
        save.stats.shipsLost += counters.shipsLost
        save.stats.groundings += counters.groundings
        if counters.shipsLost == 0 { save.stats.flawlessShifts += 1 }
        if counters.groundings == 0 { save.stats.noGroundingShifts += 1 }
        refreshAchievements()
        persist()
        return stars
    }

    func reportWatchRun(tons: Int) {
        save.watchBestTons = max(save.watchBestTons, tons)
        save.stats.tonsServed += tons
        refreshAchievements()
        persist()
    }
}
```

Achievements: 20 entries over the new stats — first shift, 10/40/84 shifts cleared, 1 000 / 25 000 / 200 000 tons, 25/150 stars, all three stars in each of ports 1–3, 10 flawless shifts, 20 no-grounding shifts, all five upgrade lines maxed, Watch records at 500 / 2 000 / 8 000 tons, every port unlocked.

- [ ] **Step 2: Delete the old game**

```bash
cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam"
git rm "Harbor Jam/HJEngine.swift" "Harbor Jam/HJGenerator.swift" "Harbor Jam/HJModels.swift" "Harbor Jam/HJBoardView.swift" "Harbor Jam/HJGameView.swift" "Harbor Jam/HJGameViewModel.swift" "Harbor Jam/HJDailyView.swift" "Harbor Jam/HJHarborView.swift"
```

Remove each of those eight files from all four pbxproj locations (`PBXBuildFile`, `PBXFileReference`, group `children`, `Sources` phase). Their object ids are listed in the pbxproj and are retired, not reused.

- [ ] **Step 2a: Register the two sim files that Task 3 and Task 4 deliberately left out of the target**

`HJShiftCatalog.swift` and `HJSim.swift` were kept out of the Sources phase because `HJModels.swift` owned the name `HJCatalog`. That file is gone as of Step 2, so register both now, in all four places each:

```
PBXBuildFile:      C0DE520000000000000003 /* HJShiftCatalog.swift in Sources */ = {isa = PBXBuildFile; fileRef = C0DE510000000000000003 /* HJShiftCatalog.swift */; };
PBXBuildFile:      C0DE520000000000000002 /* HJSim.swift in Sources */ = {isa = PBXBuildFile; fileRef = C0DE510000000000000002 /* HJSim.swift */; };
PBXFileReference:  C0DE510000000000000003 /* HJShiftCatalog.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = HJShiftCatalog.swift; sourceTree = "<group>"; };
PBXFileReference:  C0DE510000000000000002 /* HJSim.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = HJSim.swift; sourceTree = "<group>"; };
group children:    both file refs
Sources phase:     both build files
```

- [ ] **Step 3: Keep the app compiling with placeholder screens**

`HJRootView` still references four screens. Point tabs 1 and 2 at temporary stubs inside `HJRootView.swift`:

```swift
private struct HJPortsPlaceholder: View {
    var body: some View { Color(HJTheme.chartDeep).overlay(Text("Ports").foregroundColor(HJTheme.cyan)) }
}
private struct HJWatchPlaceholder: View {
    var body: some View { Color(HJTheme.chartDeep).overlay(Text("Watch").foregroundColor(HJTheme.cyan)) }
}
```

Also change `.preferredColorScheme(.light)` to `.dark` here, and rename the tab labels to `Ports`, `Watch`, `Awards`, `More`. `HJAwardsView` and `HJMoreView` need only the minimal edits that make them compile against the new `HJStore` — their full rewrite is Task 14.

- [ ] **Step 4: Build**

`xcodebuild` Debug for iPhone 17. Expected `** BUILD SUCCEEDED **`. Then launch and confirm the app opens on a dark Ports placeholder.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Save: hbj.state.v3, upgrades and new stats; delete the sliding-block game"
```

---

## Task 10: Shift view model

**Files:**
- Create: `Harbor Jam/HJShiftViewModel.swift`
- Modify: `Harbor Jam.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces: `final class HJShiftViewModel: ObservableObject` with `@Published private(set) var sim: HJSim`, `@Published var lastRefusal: (slot: Int, reason: HJBerthRefusal)?`, `@Published private(set) var isRunning: Bool`, and `init(def:upgrades:)`, `start()`, `pause()`, `resume()`, `tryBerth(shipID:atSlot:)`, `send(shipID:)`, `var isOver: Bool`, `var stars: Int`, `var score: Int`.

- [ ] **Step 1: Write the view model**

```swift
import SwiftUI
import Combine

/// Owns the simulation and the only clock that drives it. The sim itself never
/// reads wall-clock time, so pausing is exact and the headless harness sees the
/// same rules the player does.
final class HJShiftViewModel: ObservableObject {
    @Published private(set) var sim: HJSim
    @Published private(set) var isRunning = false
    @Published var lastRefusal: HJRefusalFlash? = nil

    private var timer: AnyCancellable?

    init(def: HJShiftDef, upgrades: HJUpgradeLevels) {
        sim = HJSim(def: def, upgrades: upgrades)
    }

    func start() {
        guard timer == nil else { return }
        isRunning = true
        timer = Timer.publish(every: 1.0 / Double(HJTuning.tickHz), on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.step() }
    }

    func pause() { isRunning = false }
    func resume() { isRunning = !sim.isOver }

    func stop() {
        timer?.cancel()
        timer = nil
        isRunning = false
    }

    private func step() {
        guard isRunning, !sim.isOver else {
            if sim.isOver { stop() }
            return
        }
        sim.advance()
        if sim.isOver { stop() }
    }

    @discardableResult
    func tryBerth(shipID: Int, atSlot slot: Int) -> HJBerthRefusal {
        let refusal = sim.berth(shipID: shipID, atSlot: slot)
        if refusal != .none {
            lastRefusal = HJRefusalFlash(slot: slot, reason: refusal, stamp: sim.tick)
        }
        return refusal
    }

    @discardableResult
    func send(shipID: Int) -> Bool { sim.depart(shipID: shipID) }

    var isOver: Bool { sim.isOver }
    var stars: Int { sim.stars() }
    var score: Int { sim.score() }
}

struct HJRefusalFlash: Equatable {
    var slot: Int
    var reason: HJBerthRefusal
    var stamp: Int

    var message: String {
        switch reason {
        case .tooShallow: return "Too shallow"
        case .occupied: return "Berth taken"
        case .tooLong: return "Will not fit"
        case .channelBusy: return "Channel busy"
        case .outage: return "Berth closed"
        case .notWaiting, .none: return ""
        }
    }
}
```

Register with ids `C0DE510000000000000007` / `C0DE520000000000000007`.

- [ ] **Step 2: Build**

`xcodebuild` Debug for iPhone 17, expecting `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add "Harbor Jam/HJShiftViewModel.swift" "Harbor Jam.xcodeproj/project.pbxproj"
git commit -m "Shift: view model driving the sim from a 20 Hz clock"
```

---

## Task 11: The harbour board

**Files:**
- Create: `Harbor Jam/HJHarborBoardView.swift`
- Modify: `Harbor Jam.xcodeproj/project.pbxproj`, `Harbor Jam/HJAdaptive.swift`

**Interfaces:**
- Consumes: `HJShiftViewModel`, `HJSprite`, `HJTheme`, `HJLayout`.
- Produces: `HJHarborBoardView(vm:screenSize:)`.

- [ ] **Step 1: Write the board**

Layout rules, all derived from the parent-passed `screenSize` and never from a `Canvas` closure's own `size`:

- `slotWidth = min(44, (screenSize.width - 32) / CGFloat(slotCount))`; `quayHeight = 56`.
- Quay row pinned to the top of the board area, one `berth_*` sprite per slot, gold top edge, slot depth drawn as a `Text` under each cell.
- Water fills the rest; `depth_contours` and `compass_rose` drawn at 12 % opacity behind everything.
- Channel: a vertical lane, `slotWidth * 1.2` wide, centred, drawn with two dashed `#2F6C86` edges; when `vm.sim.channelBusy` the lane tints `HJTheme.cyan.opacity(0.12)`.
- Berthed ships: `hull_<length>` scaled to `slotWidth * length`, positioned over their slots, with the cargo overlay and a `Text` of the draft in `HJTheme.cyanSoft`. Aground hulls get an `HJTheme.alert` outline and a static "aground" chip.
- Roadstead: a horizontal `ScrollView` of ship cards at the bottom, each showing hull sprite, length, draft, cargo overlay and a patience bar (`success` → `warn` → `alert` as it drains).

Three pitfalls this file must respect, each of which has already cost a day in this portfolio:

1. **Never place `.contentShape(Rectangle())` after `.position()`** — it becomes a screen-sized tap target that swallows every control beneath it.
2. **A `Button` whose label is only a `Shape` over `Color.clear` has zero tap area** — give every such label an explicit `.contentShape(Rectangle())` *before* positioning.
3. **Any fixed-width child must subtract every nested horizontal inset**, not just the outer one.

Drag: `DragGesture` on each roadstead card; on `onEnded`, map the drop point to a slot index via `Int((point.x - boardOrigin.x) / slotWidth)` and call `vm.tryBerth`. While dragging, highlight legal slots in `HJTheme.success.opacity(0.25)` by querying `vm.sim.canBerth` for the held ship at each slot.

Tap: berthed ships with `unloadLeft <= 0` get `.onTapGesture { vm.send(shipID:) }` and a pulsing gold outline.

Add `HJLayout.boardColumn` usage so an iPad caps the board at 920 pt and centres it.

Register with ids `C0DE510000000000000005` / `C0DE520000000000000005`.

- [ ] **Step 2: Build and eyeball it**

Temporarily point tab 1 at `HJHarborBoardView(vm: HJShiftViewModel(def: HJCatalog.shift(port: 1, shift: 1)!, upgrades: .zero), screenSize: UIScreen.main.bounds.size)` with `.onAppear { vm.start() }`. Build Debug, install, launch, screenshot.

Assertions from the screenshot: the quay row shows eight berth cells with depth numbers; ships appear on the roadstead within the first few seconds and their patience bars visibly drain; nothing is clipped off the right edge.

- [ ] **Step 3: Commit**

```bash
git add "Harbor Jam/HJHarborBoardView.swift" "Harbor Jam/HJAdaptive.swift" "Harbor Jam/HJRootView.swift" "Harbor Jam.xcodeproj/project.pbxproj"
git commit -m "Board: quay, channel, roadstead and drag-to-berth"
```

---

## Task 12: The shift screen

**Files:**
- Create: `Harbor Jam/HJShiftView.swift`
- Modify: `Harbor Jam.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces: `HJShiftView(port:shift:)`, reading `HJStore` from the environment.

- [ ] **Step 1: Write the screen**

Structure, top to bottom: HUD row (`icon_tonnage` + tons served, `icon_reputation` × remaining reputation, `icon_coin` + revenue, pause button); tide strip (only when `tideAmplitude > 0`) — a horizontal bar with the current level, an arrow for direction, and ticks remaining to the turn, computed as `tideStepTicks - (tick % tideStepTicks)`; the board; nothing else.

Overlays, each a `ZStack` sibling rather than a `.sheet` — iOS 15 honours only the last `.sheet` on a view, and this screen needs three:

- **Paused** — resume, restart, quit.
- **Shift complete** — stars earned, score against `target2`/`target3`, revenue, tons, ships lost, buttons for retry and next shift. Calls `store.reportShiftWin(...)` exactly once, guarded by a `@State private var reported = false`.
- **Shift failed** — reputation ran out; retry or quit. Awards nothing.

Onboarding: when `!store.save.onboardingSeen` and this is port 1 shift 1, show four sequential coach chips ("Drag a ship to a free berth", "Wait for her to unload", "Tap her to send her out", "Watch the patience bars"), skippable, setting `onboardingSeen` on completion or skip.

Register with ids `C0DE510000000000000006` / `C0DE520000000000000006`.

- [ ] **Step 2: Play a full shift on the simulator**

Build, install, launch, and play port 1 shift 1 to completion by dragging and tapping.

Assertions: a ship can be berthed by dragging; a second drag while the channel is busy is refused with the "Channel busy" flash; a finished ship departs on tap and frees her berths immediately; the shift ends and the completion overlay shows a star count; re-entering the shift shows the recorded stars.

- [ ] **Step 3: Commit**

```bash
git add "Harbor Jam/HJShiftView.swift" "Harbor Jam.xcodeproj/project.pbxproj"
git commit -m "Shift: HUD, tide strip, overlays and onboarding"
```

---

## Task 13: Ports and shipyard

**Files:**
- Create: `Harbor Jam/HJPortsView.swift`, `Harbor Jam/HJShipyardView.swift`
- Modify: `Harbor Jam/HJRootView.swift`, `Harbor Jam.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces: `HJPortsView()`, `HJShipyardView()`.

- [ ] **Step 1: Ports**

A `NavigationView` list of seven port cards: name, tagline, stars earned out of 36, and a lock with "Needs N stars" when `!store.isPortUnlocked(port)`. Tapping an unlocked port pushes a grid of twelve shift tiles — number, earned stars, lock state from `isShiftUnlocked`. A "Shipyard" bar at the top shows coins and pushes `HJShipyardView`. On iPad, cap with `HJLayout.harborColumn` and use `HJLayout.twoColumns`.

- [ ] **Step 2: Shipyard**

Five rows, one per `HJUpgradeLine`: title, detail, level pips out of `maxLevel`, cost of the next level, and a Buy button disabled when `coins < cost` or the line is maxed. Buying calls `store.buyUpgrade(line)`.

- [ ] **Step 3: Wire the tabs**

Replace `HJPortsPlaceholder` with `HJPortsView()` in `HJRootView`.

- [ ] **Step 4: Verify on the simulator**

Build, install, launch. Assertions: ports 2–7 are locked at zero stars; clearing port 1 shift 1 unlocks shift 2; coins earned in that shift appear in the shipyard; buying an upgrade decrements coins and adds a pip; force-quitting and relaunching preserves all three.

- [ ] **Step 5: Commit**

```bash
git add "Harbor Jam/HJPortsView.swift" "Harbor Jam/HJShipyardView.swift" "Harbor Jam/HJRootView.swift" "Harbor Jam.xcodeproj/project.pbxproj"
git commit -m "Ports: campaign map, shift grid and the shipyard"
```

---

## Task 14: Watch mode, awards and more

**Files:**
- Create: `Harbor Jam/HJWatchView.swift`
- Rewrite: `Harbor Jam/HJAwardsView.swift`, `Harbor Jam/HJMoreView.swift`
- Modify: `Harbor Jam/HJRootView.swift`, `Harbor Jam/HJShiftCatalog.swift`, `Harbor Jam.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces: `HJWatchView()`, `HJCatalog.watchShift(seed:wave:) -> HJShiftDef`.

- [ ] **Step 1: Endless shift generation in the app**

Add to `HJShiftCatalog.swift` a deterministic endless generator: a fixed 10-slot harbour, and arrivals produced in waves whose spacing shrinks by 4 % per wave, floored at 40 % of the opening spacing. It reuses the same `HJShiftDef` type so `HJSim` is unchanged. `parTicks` is `Int.max` and both targets are `Int.max` — Watch scores by tons, not stars.

- [ ] **Step 2: Watch screen**

Same board and HUD as a campaign shift, plus: a wave counter; an upgrade choice overlay every 1 800 ticks offering three random `HJUpgradeLine` levels that apply for the run only and cost no coins; a run-over overlay showing tons served against `store.save.watchBestTons`, calling `store.reportWatchRun(tons:)` once.

- [ ] **Step 3: Awards**

A stats block (shifts cleared, tons served, ships served and lost, groundings, flawless shifts, best Watch run) above a grid of the 20 achievements from Task 9, locked ones dimmed.

- [ ] **Step 4: More**

Settings (sound, haptics, reset progress behind a confirmation alert that removes `hbj.state.v3` before re-saving), a "Harbour manual" section with one page per mechanic — quay packing, tide and draft, the channel, berth gear — and Privacy Policy opening `HarborJamWebPanel` in a `.sheet`. The manual replaces the old codex; keep the existing card styling.

- [ ] **Step 5: Verify**

Build, install, launch. Assertions: a Watch run starts, offers an upgrade choice at the first interval, ends on reputation zero and records a best; Awards shows non-zero stats after a campaign shift; Reset Progress empties records, coins and upgrades and survives a relaunch.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "Watch, Awards and More rebuilt on the dispatcher save layer"
```

---

## Task 15: Icon, universal layout and release check

**Files:**
- Create: `tools/HarborArt/icon.swift`
- Modify: `Harbor Jam/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`
- Modify: `Harbor Jam/Info.plist`, `Harbor Jam.xcodeproj/project.pbxproj` (version only)

- [ ] **Step 1: Draw the icon**

A `swiftc`-compiled CoreGraphics program writing a 1024×1024 **opaque** PNG: deep chart navy background, a gold quay edge across the lower third, a cyan-outlined hull above it, three depth contour arcs, one gold four-point star. Use `CGImageAlphaInfo.noneSkipLast`, then `sips --setProperty hasAlpha no`. A transparent or missing-size icon is a rejection; the `universal` single-size AppIcon format that this project already uses auto-generates every required size and must be kept.

- [ ] **Step 2: Verify the icon**

```bash
cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam" && sips -g pixelWidth -g pixelHeight -g hasAlpha "Harbor Jam/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
```

Expected: `pixelWidth: 1024`, `pixelHeight: 1024`, `hasAlpha: no`.

- [ ] **Step 3: Check both idioms**

Build and launch on an iPhone 17 simulator and on an iPad simulator, in portrait. Assertions: no content is clipped at the right edge on iPad; the board is centred and capped; the tab bar spans the full width with its buttons centred; every control keeps a tap target of at least 44 pt.

- [ ] **Step 4: Release build**

```bash
cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam" && xcodebuild -project "Harbor Jam.xcodeproj" -scheme "Harbor Jam" -destination 'generic/platform=iOS' -configuration Release build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Re-run the whole harness against the shipped sources**

```bash
cd "/Users/vik/Documents/development/for_human_review_apps/Harbor Jam" && ./tools/HarborForge/build.sh && ./tools/HarborForge/harborforge test && ./tools/HarborForge/harborforge verify && ./tools/HarborForge/harborforge gate
```

Expected: `SIM TESTS OK`, `VERIFY OK — 84 shifts clearable`, and every gate clause `PASS`. If the gate now fails, the simulation changed after the corpus was baked — rebake or revert, because `shifts.json` and the engine must agree.

- [ ] **Step 6: Bump the build number**

Set `CFBundleVersion` to `2` in `Harbor Jam/Info.plist` **and** in both `CURRENT_PROJECT_VERSION` entries in the pbxproj. This app's Info.plist carries a literal, not a `$(VARIABLE)`, so both must move together or the archive ships the old number.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "Release: icon, universal layout check and a full harness re-run"
```

---

## Self-Review

**Spec coverage.** Section 3 (field, entities, time, tide, rules, two verbs, scoring) → Tasks 2, 4, 11, 12. Section 4 (7 ports × 12 shifts, shipyard, Watch, awards) → Tasks 3, 7, 13, 14. Section 5 (save v3) → Task 9. Section 6 (gate, policies, bake, `shifts.json`) → Tasks 5, 6, 7. Section 7 (palette, 21 sprites, SVG pipeline) → Tasks 1, 8, 15. Section 8 (four tabs, pushes, onboarding) → Tasks 9, 12, 13, 14. Section 9 (file inventory, pbxproj registration) → every task's registration step plus Task 9's deletions. Section 10 (portfolio pitfalls) → called out in Task 11 where they apply, and in the global constraints. Section 11 (risks) → Task 1 retires the SVG risk; Task 7 owns the tuning risk. Section 12 (out of scope) → the WebView gate is frozen in the global constraints and no task touches it.

**Placeholder scan.** No "TBD", no "handle edge cases", no "similar to Task N". Task 7 Step 3 and Task 11 Step 2 deliberately state assertions instead of expected output, because their output cannot be known ahead of time — that is required by the global constraints, not a placeholder.

**Type consistency.** `HJSim.berth` / `depart` / `canBerth` / `advance` / `score` / `stars` are used with the same signatures in Tasks 6, 7, 10. `HJSimCounters` field names (`revenue`, `tonsServed`, `shipsServed`, `shipsLost`, `groundings`, `channelRefusals`, `mismatchedUnloads`) match between Task 2, the gate in Task 7 and the save layer in Task 9. `HJUpgradeLevels` field names match between Tasks 2, 4 and 9. `HJShiftDef.parTicks` / `target2` / `target3` are written in Task 7 and read in `HJSim.stars()` from Task 4. `HJRefusalFlash` is defined in Task 10 and consumed by the board in Task 11.

**Known rough edge.** `HJSim.canBerth` is a `func` on a struct that the policies call inside tight loops, and `occupiedSlots` rebuilds a `Set` on every call. If Task 7's gate run takes more than a couple of minutes over 84 shifts, cache `occupiedSlots` in the sim and invalidate it on berth, depart and transit completion — but only then, and re-run the sim tests afterwards, because that cache is exactly the kind of change that silently desynchronises the app from the harness.
