import Carbon
import Foundation

let args = CommandLine.arguments
guard args.count >= 2 else {
    print("Usage: switch_layout <list|listall|enable|disable|select> [layout_id]")
    exit(1)
}

let cmd = args[1]

func getInputSources(includeAll: Bool) -> [TISInputSource] {
    let filter: [CFString: Any] = [kTISPropertyInputSourceType: kTISTypeKeyboardLayout]
    guard let list = TISCreateInputSourceList(filter as CFDictionary, includeAll)?.takeRetainedValue() else {
        return []
    }
    var sources: [TISInputSource] = []
    for i in 0..<CFArrayGetCount(list) {
        if let ptr = CFArrayGetValueAtIndex(list, i) {
            sources.append(unsafeBitCast(ptr, to: TISInputSource.self))
        }
    }
    return sources
}

func getSourceID(_ source: TISInputSource) -> String? {
    guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
    return unsafeBitCast(ptr, to: CFString.self) as String
}

func getSourceName(_ source: TISInputSource) -> String? {
    guard let ptr = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) else { return nil }
    return unsafeBitCast(ptr, to: CFString.self) as String
}

func matchLayout(_ sourceID: String, _ target: String) -> Bool {
    // Exact match on full ID
    if sourceID == "com.apple.keylayout.\(target)" { return true }
    // Exact match on short ID (after last dot)
    let shortID = sourceID.components(separatedBy: ".").last ?? ""
    return shortID == target
}

switch cmd {
case "list":
    let enabled = getInputSources(includeAll: false)
    print("Enabled layouts:")
    for src in enabled {
        if let id = getSourceID(src), let name = getSourceName(src) {
            print("  \(id) - \(name)")
        }
    }
    
case "listall":
    let all = getInputSources(includeAll: true)
    print("All available layouts (\(all.count)):")
    for src in all {
        if let id = getSourceID(src), let name = getSourceName(src) {
            let short = id.components(separatedBy: ".").last ?? id
            print("  \(short) - \(name)")
        }
    }

case "enable":
    guard args.count >= 3 else { print("Need layout_id"); exit(1) }
    let target = args[2]
    let all = getInputSources(includeAll: true)
    for src in all {
        if let id = getSourceID(src), matchLayout(id, target) {
            let status = TISEnableInputSource(src)
            print(status == noErr ? "Enabled: \(id)" : "Failed: \(status)")
            exit(status == noErr ? 0 : 1)
        }
    }
    print("Not found: \(target)")
    exit(1)

case "disable":
    guard args.count >= 3 else { print("Need layout_id"); exit(1) }
    let target = args[2]
    let enabled = getInputSources(includeAll: false)
    for src in enabled {
        if let id = getSourceID(src), matchLayout(id, target) {
            let status = TISDisableInputSource(src)
            print(status == noErr ? "Disabled: \(id)" : "Failed: \(status)")
            exit(status == noErr ? 0 : 1)
        }
    }
    print("Not found/enabled: \(target)")
    exit(1)

case "select":
    guard args.count >= 3 else { print("Need layout_id"); exit(1) }
    let target = args[2]
    let enabled = getInputSources(includeAll: false)
    for src in enabled {
        if let id = getSourceID(src), matchLayout(id, target) {
            let status = TISSelectInputSource(src)
            print(status == noErr ? "Selected: \(id)" : "Failed: \(status)")
            exit(status == noErr ? 0 : 1)
        }
    }
    print("Not found/enabled: \(target)")
    exit(1)

default:
    print("Unknown: \(cmd)")
    exit(1)
}
