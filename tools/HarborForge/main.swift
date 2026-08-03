import Foundation

let args = CommandLine.arguments
let command = args.count > 1 ? args[1] : "test"

switch command {
case "test":
    exit(SimTests.run() ? 0 : 1)
default:
    print("unknown command: \(command)")
    print("usage: harborforge [test]")
    exit(2)
}
