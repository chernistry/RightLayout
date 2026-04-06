import CoreGraphics
@testable import RightLayout

class MockCharacterEncoder: CharacterEncoder {
    var mapping: [CGKeyCode: String] = [
        5: "g", 4: "h", 11: "b", 2: "d", 17: "t", 45: "n", 49: " ",
        15: "r", 3: "f", 51: "\u{8}" // Backspace
    ]
    
    func encode(event: CGEvent) -> String? {
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        // Only return if keyDown, keyUp doesn't matter for char gen usually but let's be consistent
        // Or just map regardless.
        return mapping[CGKeyCode(code)]
    }
}
