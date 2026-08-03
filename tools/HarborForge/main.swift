import Foundation

let args = CommandLine.arguments
let command = args.count > 1 ? args[1] : "test"

switch command {
case "test":
    exit(SimTests.run() ? 0 : 1)

case "generate":
    var mismatches = 0
    for port in 1...QLCatalog.portCount {
        for shift in 1...QLCatalog.shiftsPerPort {
            let a = forgeShift(port: port, shift: shift, salt: 0)
            let b = forgeShift(port: port, shift: shift, salt: 0)
            if a != b { mismatches += 1 }
            if a.arrivals.isEmpty { mismatches += 1 }
        }
    }
    print(mismatches == 0
          ? "GENERATE OK — \(QLCatalog.totalShifts) shifts, deterministic, all non-empty"
          : "GENERATE FAILED — \(mismatches) mismatches")
    exit(mismatches == 0 ? 0 : 1)

case "policies":
    for port in [1, 4, 7] {
        let def = forgeShift(port: port, shift: 1, salt: 0)
        print("--- port \(port), shift 1 — \(def.arrivals.count) arrivals ---")
        for p in [ForgePolicy.greedy, .random, .smart] {
            let r = forgeRun(def: def, upgrades: .zero, policy: p, seed: 12345)
            let accounted = r.counters.shipsServed + r.counters.shipsLost
            // A failed shift legitimately ends before every ship has arrived;
            // only a run that hits the tick cap is a stall worth fixing.
            let ok = r.endTick < forgeTickCap && (r.failed || accounted == def.arrivals.count)
            let chanPct = r.endTick == 0 ? 0 : r.counters.channelBusyTicks * 100 / r.endTick
            print("\(p.rawValue)  served=\(r.counters.shipsServed) lost=\(r.counters.shipsLost) "
                  + "ticks=\(r.endTick) revenue=\(r.counters.revenue) "
                  + "ground=\(r.counters.groundings) chan=\(chanPct)% "
                  + "mismatch=\(r.counters.mismatchedUnloads)  \(ok ? "OK" : "STALLED")")
        }
    }
    exit(0)

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
    try! data.write(to: URL(fileURLWithPath: "Quaylock/shifts.json"))
    print("baked \(reports.count) shifts to Quaylock/shifts.json (\(data.count) bytes)")
    exit(0)

case "verify":
    let data = try! Data(contentsOf: URL(fileURLWithPath: "Quaylock/shifts.json"))
    let defs = try! JSONDecoder().decode([QLShiftDef].self, from: data)
    var bad = 0
    for d in defs where forgeRun(def: d, upgrades: .zero, policy: .smart, seed: 1).stars < 1 {
        bad += 1
        print("UNCLEARABLE \(d.port)-\(d.shift)")
    }
    print(bad == 0 ? "VERIFY OK — \(defs.count) shifts clearable" : "VERIFY FAILED — \(bad)")
    exit(bad == 0 ? 0 : 1)

default:
    print("unknown command: \(command)")
    print("usage: harborforge [test|generate|policies|gate|bake|verify]")
    exit(2)
}
