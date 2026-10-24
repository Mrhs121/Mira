import Foundation

func miraLog(_ message: @autoclosure () -> String) {
    guard ProcessInfo.processInfo.environment["MIRA_DEBUG"] == "1" else { return }
    guard let data = ("Mira: " + message() + "\n").data(using: .utf8) else { return }
    FileHandle.standardError.write(data)
}
