import AppKit
import Foundation

let arguments = CommandLine.arguments

if arguments.count > 1, arguments[1] == "hook" {
    HookCommand.run()
}

if arguments.count > 2, arguments[1] == "render-frames" {
    // Debug helper: writes every frame of every pet to PNGs for review.
    RenderFrames.run(to: URL(fileURLWithPath: arguments[2]))
    exit(0)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
