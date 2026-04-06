import Foundation

/// Simulates a text buffer with cursor at end, modeling what the app does during text replacement.
/// Used for testing hotkey correction logic without OS event taps.
struct TextBufferSimulator {
    private(set) var content: String = ""
    
    /// Append text (simulates typing)
    mutating func type(_ text: String) {
        content.append(text)
    }
    
    /// Replace last N characters with new text (simulates delete + insert)
    /// Returns the operation details for verification
    @discardableResult
    mutating func replaceLast(_ n: Int, with newText: String) -> ReplacementOperation {
        let actualDeleteCount = min(n, content.count)
        let deleted = String(content.suffix(actualDeleteCount))
        
        if actualDeleteCount > 0 {
            content.removeLast(actualDeleteCount)
        }
        content.append(newText)
        
        return ReplacementOperation(
            deletedCount: actualDeleteCount,
            deletedText: deleted,
            insertedText: newText,
            resultingContent: content
        )
    }
    
    /// Clear the buffer
    mutating func clear() {
        content = ""
    }
    
    /// Check if content contains any control characters (except allowed ones)
    func containsControlCharacters(allowNewlines: Bool = true, allowTabs: Bool = true) -> Bool {
        for scalar in content.unicodeScalars {
            // C0 control characters: U+0000 to U+001F
            // DEL: U+007F
            if scalar.value <= 0x1F || scalar.value == 0x7F {
                // Check if it's an allowed character
                if allowNewlines && (scalar == "\n" || scalar == "\r") {
                    continue
                }
                if allowTabs && scalar == "\t" {
                    continue
                }
                return true
            }
        }
        return false
    }
    
    /// Get any control characters found in content
    func findControlCharacters() -> [UnicodeScalar] {
        var found: [UnicodeScalar] = []
        for scalar in content.unicodeScalars {
            if scalar.value <= 0x1F || scalar.value == 0x7F {
                if scalar != "\n" && scalar != "\r" && scalar != "\t" {
                    found.append(scalar)
                }
            }
        }
        return found
    }
}

/// Records details of a replacement operation for verification
struct ReplacementOperation {
    let deletedCount: Int
    let deletedText: String
    let insertedText: String
    let resultingContent: String
}
