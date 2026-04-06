import CoreGraphics

protocol CharacterEncoder {
    func encode(event: CGEvent) -> String?
}

struct DefaultCharacterEncoder: CharacterEncoder {
    func encode(event: CGEvent) -> String? {
        guard let chars = event.keyboardEventCharacters else { return nil }
        return chars
    }
}
