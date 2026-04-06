import AppKit
import UniformTypeIdentifiers

/// Result of a pasteboard restoration operation
enum PasteboardRestoreResult {
    case success
    case failure(Error?)
}

/// Helper for robust pasteboard snapshotting and restoration
/// prevents data loss of non-string types during clipboard operations
final class PasteboardHelper: @unchecked Sendable {
    static let shared = PasteboardHelper()
    
    private let pasteboard = NSPasteboard.general
    
    struct Snapshot {
        let items: [NSPasteboardItem]
        let changeCount: Int
    }
    
    /// Capture current pasteboard state including all types
    func snapshot() -> Snapshot {
        // Deep copy items to ensure they persist
        let items = (pasteboard.pasteboardItems ?? []).map { item -> NSPasteboardItem in
            let newItem = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    newItem.setData(data, forType: type)
                }
            }
            return newItem
        }
        return Snapshot(items: items, changeCount: pasteboard.changeCount)
    }
    
    /// Restore pasteboard state exactly as it was
    @discardableResult
    func restore(_ snapshot: Snapshot) -> Bool {
        // If change count hasn't moved since our snapshot (rare but possible if we were fast),
        // we might not strictly need to restore, but to be safe we always do
        // if user hasn't copied anything new in between.
        
        pasteboard.clearContents()
        let result = pasteboard.writeObjects(snapshot.items)
        return result
    }
    
    /// Helper to set string content temp, perform action, then restore
    func performWithString(_ text: String, action: () async -> Void) async {
        let saved = snapshot()
        
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        
        await action()
        
        // Small delay to ensure consumers have read it
        // (Caller usually handles the main delay (e.g. pasteDelay), implementing a minimal safety here)
        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
        
        restore(saved)
    }
}
