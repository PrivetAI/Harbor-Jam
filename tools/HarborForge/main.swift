import Foundation

let forgeArgs = Array(CommandLine.arguments.dropFirst())

switch forgeArgs.first ?? "" {
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
    exit(2)
}
