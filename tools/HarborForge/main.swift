import Foundation

let forgeArgs = Array(CommandLine.arguments.dropFirst())

switch forgeArgs.first ?? "" {
case "probe":
    let salts = forgeArgs.count > 1 ? (Int(forgeArgs[1]) ?? 60) : 60
    exit(Int32(forgeRunYieldProbe(saltsPerLevel: salts)))
case "search":
    exit(Int32(forgeRunSearchChecks()))
case "forge":
    exit(Int32(forgeRunForgeChecks()))
case "engine":
    exit(Int32(forgeRunEngineChecks()))
case "audit":
    exit(Int32(forgeRunAudit()))
default:
    print("HarborForge — offline harness for Harbor Jam")
    print("")
    print("usage: harborforge <subcommand>")
    print("  audit   measure the corpus and assert the known baseline")
    print("  engine  assert the frozen engine invariants")
    print("  forge   assert the forward generator produces legal boards")
    print("  search  assert the witness search is sound")
    print("  probe [salts]  measure acceptance yield and the greedy rate on accepted boards")
    exit(2)
}
