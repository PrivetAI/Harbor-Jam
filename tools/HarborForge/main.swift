import Foundation

let forgeArgs = Array(CommandLine.arguments.dropFirst())

switch forgeArgs.first ?? "" {
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
    exit(2)
}
