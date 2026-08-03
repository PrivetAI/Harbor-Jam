import Foundation

let args = CommandLine.arguments
let command = args.count > 1 ? args[1] : "test"

switch command {
case "test":
    exit(SimTests.run() ? 0 : 1)

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

default:
    print("unknown command: \(command)")
    print("usage: harborforge [test|generate|policies]")
    exit(2)
}
