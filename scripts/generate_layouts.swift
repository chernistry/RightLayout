import Foundation
import Carbon

// All physical key codes we care about
let keyCodes: [(code: Int, name: String)] = [
    (0, "KeyA"), (1, "KeyS"), (2, "KeyD"), (3, "KeyF"), (4, "KeyH"),
    (5, "KeyG"), (6, "KeyZ"), (7, "KeyX"), (8, "KeyC"), (9, "KeyV"),
    (11, "KeyB"), (12, "KeyQ"), (13, "KeyW"), (14, "KeyE"), (15, "KeyR"),
    (16, "KeyY"), (17, "KeyT"), (18, "Digit1"), (19, "Digit2"), (20, "Digit3"),
    (21, "Digit4"), (22, "Digit6"), (23, "Digit5"), (24, "Equal"), (25, "Digit9"),
    (26, "Digit7"), (27, "Minus"), (28, "Digit8"), (29, "Digit0"), (30, "BracketRight"),
    (31, "KeyO"), (32, "KeyU"), (33, "BracketLeft"), (34, "KeyI"), (35, "KeyP"),
    (37, "KeyL"), (38, "KeyJ"), (39, "Quote"), (40, "KeyK"), (41, "Semicolon"),
    (42, "Backslash"), (43, "Comma"), (44, "Slash"), (45, "KeyN"), (46, "KeyM"),
    (47, "Period"), (50, "Backquote")
]

struct LayoutData: Codable {
    let appleId: String
    let id: String
    let language: String
    let name: String
}

func getCharacter(source: TISInputSource, keyCode: Int, shift: Bool, option: Bool) -> String? {
    guard let layoutDataPtr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
        return nil
    }
    let layoutData = unsafeBitCast(layoutDataPtr, to: CFData.self)
    let keyboardLayout = unsafeBitCast(CFDataGetBytePtr(layoutData), to: UnsafePointer<UCKeyboardLayout>.self)
    
    var deadKeyState: UInt32 = 0
    var chars = [UniChar](repeating: 0, count: 4)
    var length: Int = 0
    
    var modifiers: UInt32 = 0
    if shift { modifiers |= (1 << 1) }
    if option { modifiers |= (1 << 3) }
    
    let status = UCKeyTranslate(
        keyboardLayout,
        UInt16(keyCode),
        UInt16(kUCKeyActionDown),
        modifiers,
        UInt32(LMGetKbdType()),
        UInt32(kUCKeyTranslateNoDeadKeysMask),
        &deadKeyState,
        chars.count,
        &length,
        &chars
    )
    
    guard status == noErr, length > 0 else { return nil }
    return String(utf16CodeUnits: chars, count: length)
}

func generateLayoutMap(source: TISInputSource) -> [String: [String: String]] {
    var keyMap: [String: [String: String]] = [:]
    
    for (code, name) in keyCodes {
        var modMap: [String: String] = [:]
        
        if let c = getCharacter(source: source, keyCode: code, shift: false, option: false), !c.isEmpty {
            modMap["n"] = c
        }
        if let c = getCharacter(source: source, keyCode: code, shift: true, option: false), !c.isEmpty {
            modMap["s"] = c
        }
        if let c = getCharacter(source: source, keyCode: code, shift: false, option: true), !c.isEmpty {
            modMap["a"] = c
        }
        if let c = getCharacter(source: source, keyCode: code, shift: true, option: true), !c.isEmpty {
            modMap["sa"] = c
        }
        
        if !modMap.isEmpty {
            keyMap[name] = modMap
        }
    }
    
    return keyMap
}

// Target layouts we want
let targetLayouts: [(appleId: String, id: String, lang: String)] = [
    ("com.apple.keylayout.US", "us", "en"),
    ("com.apple.keylayout.ABC", "abc", "en"),
    ("com.apple.keylayout.British", "british", "en"),
    ("com.apple.keylayout.British-PC", "british_pc", "en"),
    ("com.apple.keylayout.Australian", "australian", "en"),
    ("com.apple.keylayout.Austrian", "austrian", "en"),
    ("com.apple.keylayout.Canadian", "canadian", "en"),
    ("com.apple.keylayout.Canadian-CSA", "canadian_csa", "en"),
    ("com.apple.keylayout.CanadianFrench-PC", "canadianfrench_pc", "en"),
    ("com.apple.keylayout.Irish", "irish", "en"),
    ("com.apple.keylayout.Colemak", "colemak", "en"),
    ("com.apple.keylayout.Dvorak", "dvorak", "en"),
    ("com.apple.keylayout.Dvorak-Left", "dvorak_left", "en"),
    ("com.apple.keylayout.Dvorak-Right", "dvorak_right", "en"),
    ("com.apple.keylayout.DVORAK-QWERTYCMD", "dvorak_qwertycmd", "en"),
    ("com.apple.keylayout.USInternational-PC", "usinternational_pc", "en"),
    ("com.apple.keylayout.Russian", "russian", "ru"),
    ("com.apple.keylayout.RussianWin", "russianwin", "ru"),
    ("com.apple.keylayout.Russian-Phonetic", "russian_phonetic", "ru"),
    ("com.apple.keylayout.Byelorussian", "byelorussian", "ru"),
    ("com.apple.keylayout.Ingush", "ingush", "ru"),
    ("com.apple.keylayout.Hebrew", "hebrew", "he"),
    ("com.apple.keylayout.Hebrew-PC", "hebrew_pc", "he"),
    ("com.apple.keylayout.Hebrew-QWERTY", "hebrew_qwerty", "he"),
]

// Get ALL keyboard layouts (including not enabled) - pass true for includeAllInstalled
let filter: [CFString: Any] = [kTISPropertyInputSourceType: kTISTypeKeyboardLayout]
guard let sourceList = TISCreateInputSourceList(filter as CFDictionary, true)?.takeRetainedValue() else {
    print("Failed to get input sources")
    exit(1)
}

// Build lookup by appleId
var sourceByAppleId: [String: TISInputSource] = [:]
for i in 0..<CFArrayGetCount(sourceList) {
    guard let ptr = CFArrayGetValueAtIndex(sourceList, i) else { continue }
    let source = unsafeBitCast(ptr, to: TISInputSource.self)
    
    guard let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { continue }
    let appleId = unsafeBitCast(idPtr, to: CFString.self) as String
    sourceByAppleId[appleId] = source
}

var layouts: [LayoutData] = []
var fullMap: [String: [String: [String: String]]] = [:]

for target in targetLayouts {
    guard let source = sourceByAppleId[target.appleId] else {
        fputs("WARNING: Layout not found: \(target.appleId)\n", stderr)
        continue
    }
    
    guard let namePtr = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) else { continue }
    let name = unsafeBitCast(namePtr, to: CFString.self) as String
    
    layouts.append(LayoutData(appleId: target.appleId, id: target.id, language: target.lang, name: name))
    fullMap[target.id] = generateLayoutMap(source: source)
}

// Sort layouts
layouts.sort { $0.id < $1.id }

// Build final structure
struct Output: Codable {
    let layouts: [LayoutData]
    let map: [String: [String: [String: String]]]
}

let output = Output(layouts: layouts, map: fullMap)
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

if let data = try? encoder.encode(output),
   let json = String(data: data, encoding: .utf8) {
    print(json)
}
