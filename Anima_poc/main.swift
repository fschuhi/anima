// main.swift — Anima PoC entry point
//
// Creates the macOS application and hands control to AppDelegate.
// This is the equivalent of Python's `if __name__ == '__main__'` block
// combined with `AppHelper.runEventLoop()` from PyObjC.

import Cocoa

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
