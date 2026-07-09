import AppKit

private let app = NSApplication.shared
private let delegate = AppDelegate()

app.setActivationPolicy(.regular)
app.delegate = delegate
app.run()
