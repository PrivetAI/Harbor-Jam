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

default:
    print("unknown command: \(command)")
    print("usage: harborforge [test|generate]")
    exit(2)
}
