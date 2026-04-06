#!/usr/bin/env swift
// Generates keyboard layout mappings for ALL macOS layouts
// Usage: swift main.swift > layouts.json

import Carbon
import Foundation

struct LayoutMapping: Codable {
    var n: String?   // normal
    var s: String?   // shift
    var a: String?   // alt/option
    var sa: String?  // shift+alt
}

struct LayoutInfo: Codable {
    let id: String
    let name: String
    let language: String
    let appleId: String  // Full Apple ID for matching at runtime
}

struct LayoutData: Codable {
    var layouts: [LayoutInfo]
    var map: [String: [String: LayoutMapping]]  // keyCode -> layoutId -> mapping
}

// Standard US keyboard key codes
let keyCodes: [(code: UInt16, name: String)] = [
    (18, "Digit1"), (19, "Digit2"), (20, "Digit3"), (21, "Digit4"), (23, "Digit5"),
    (22, "Digit6"), (26, "Digit7"), (28, "Digit8"), (25, "Digit9"), (29, "Digit0"),
    (27, "Minus"), (24, "Equal"),
    (12, "KeyQ"), (13, "KeyW"), (14, "KeyE"), (15, "KeyR"), (17, "KeyT"),
    (16, "KeyY"), (32, "KeyU"), (34, "KeyI"), (31, "KeyO"), (35, "KeyP"),
    (33, "BracketLeft"), (30, "BracketRight"), (42, "Backslash"),
    (0, "KeyA"), (1, "KeyS"), (2, "KeyD"), (3, "KeyF"), (5, "KeyG"),
    (4, "KeyH"), (38, "KeyJ"), (40, "KeyK"), (37, "KeyL"), (41, "Semicolon"), (39, "Quote"),
    (6, "KeyZ"), (7, "KeyX"), (8, "KeyC"), (9, "KeyV"), (11, "KeyB"),
    (45, "KeyN"), (46, "KeyM"), (43, "Comma"), (47, "Period"), (44, "Slash"),
    (50, "Backquote"),
]

func getCharForKey(keyCode: UInt16, shift: Bool, option: Bool, layout: TISInputSource) -> String? {
    guard let layoutData = TISGetInputSourceProperty(layout, kTISPropertyUnicodeKeyLayoutData) else { return nil }
    let data = Unmanaged<CFData>.fromOpaque(layoutData).takeUnretainedValue() as Data
    
    var deadKeyState: UInt32 = 0
    var chars = [UniChar](repeating: 0, count: 4)
    var length: Int = 0
    
    var modifiers: UInt32 = 0
    if shift { modifiers |= UInt32(shiftKey >> 8) }
    if option { modifiers |= UInt32(optionKey >> 8) }
    
    let status = data.withUnsafeBytes { ptr -> OSStatus in
        guard let layoutPtr = ptr.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return -1 }
        return UCKeyTranslate(layoutPtr, keyCode, UInt16(kUCKeyActionDown), modifiers,
                              UInt32(LMGetKbdType()), UInt32(kUCKeyTranslateNoDeadKeysMask),
                              &deadKeyState, chars.count, &length, &chars)
    }
    
    guard status == noErr, length > 0 else { return nil }
    return String(utf16CodeUnits: chars, count: length)
}

func getLayoutId(_ source: TISInputSource) -> String? {
    guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
    return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
}

func getLayoutName(_ source: TISInputSource) -> String? {
    guard let ptr = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) else { return nil }
    return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
}

func getLanguages(_ source: TISInputSource) -> [String] {
    guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) else { return [] }
    return Unmanaged<CFArray>.fromOpaque(ptr).takeUnretainedValue() as? [String] ?? []
}

func detectLanguage(_ shortId: String) -> String? {
    // Russian layouts
    let ruLayouts = ["russian", "russianwin", "russian_phonetic", "byelorussian", "ingush"]
    if ruLayouts.contains(shortId) { return "ru" }
    
    // Hebrew layouts
    if shortId.hasPrefix("hebrew") { return "he" }
    
    // English layouts
    let enLayouts = ["us", "abc", "british", "british_pc", "australian", "canadian", "canadian_csa", 
                     "canadianfrench_pc", "irish", "colemak", "dvorak", "dvorak_left", "dvorak_right",
                     "dvorak_qwertycmd", "usinternational_pc", "austrian"]
    if enLayouts.contains(shortId) { return "en" }
    
    return nil
}

func simplifyLayoutId(_ fullId: String) -> String {
    // com.apple.keylayout.Russian-PC -> russian_pc
    var name = fullId
        .replacingOccurrences(of: "com.apple.keylayout.", with: "")
        .replacingOccurrences(of: "com.apple.inputmethod.", with: "")
    
    // Normalize: lowercase, replace - with _
    name = name.lowercased()
        .replacingOccurrences(of: "-", with: "_")
        .replacingOccurrences(of: " ", with: "_")
    
    return name
}

// Get ALL keyboard layouts (not just installed)
let conditions: CFDictionary = [
    kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as Any
] as CFDictionary

guard let sources = TISCreateInputSourceList(conditions, true)?.takeRetainedValue() as? [TISInputSource] else {
    fputs("Error: Could not get input sources\n", stderr)
    exit(1)
}

// Filter to layouts with Unicode key data
let keyboardLayouts = sources.filter { TISGetInputSourceProperty($0, kTISPropertyUnicodeKeyLayoutData) != nil }

fputs("Found \(keyboardLayouts.count) keyboard layouts\n", stderr)

var layoutData = LayoutData(layouts: [], map: [:])
var processedIds = Set<String>()

for layout in keyboardLayouts {
    guard let fullId = getLayoutId(layout), let name = getLayoutName(layout) else { continue }
    
    let shortId = simplifyLayoutId(fullId)
    
    // Skip duplicates
    if processedIds.contains(shortId) { continue }
    processedIds.insert(shortId)
    
    guard let lang = detectLanguage(shortId) else { continue }  // Skip unsupported
    
    fputs("  \(shortId) (\(name)) - \(lang)\n", stderr)
    
    layoutData.layouts.append(LayoutInfo(id: shortId, name: name, language: lang, appleId: fullId))
    
    for (code, keyName) in keyCodes {
        if layoutData.map[keyName] == nil { layoutData.map[keyName] = [:] }
        
        var mapping = LayoutMapping()
        mapping.n = getCharForKey(keyCode: code, shift: false, option: false, layout: layout)
        mapping.s = getCharForKey(keyCode: code, shift: true, option: false, layout: layout)
        mapping.a = getCharForKey(keyCode: code, shift: false, option: true, layout: layout)
        mapping.sa = getCharForKey(keyCode: code, shift: true, option: true, layout: layout)
        
        layoutData.map[keyName]![shortId] = mapping
    }
}

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
if let json = try? encoder.encode(layoutData) {
    print(String(data: json, encoding: .utf8)!)
}
