import AppKit
import Foundation

if CommandLine.arguments.contains("--diag") {
    setvbuf(stdout, nil, _IONBF, 0)   // 진단 출력을 바로 흘려보낸다
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
