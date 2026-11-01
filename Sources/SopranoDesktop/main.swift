import AppKit

// Sub-commands run before the app launches and never return (`apply`, `restore`, `status`,
// `export`, `help`). Without one, the menu-bar app starts.
let launchArguments = CommandLine.arguments
if launchArguments.count > 1, CLI.commands.contains(launchArguments[1]) {
    CLI.run(arguments: Array(launchArguments.dropFirst()))
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
