import AppKit
import os.log

/// Captures a deep copy of the clipboard state to allow non-destructive restoration.
struct ClipboardSnapshot {
    private let items: [UnpackedPasteboardItem]
    let changeCount: Int
    
    private struct UnpackedPasteboardItem {
        let dataMap: [NSPasteboard.PasteboardType: Data]
        
        init(item: NSPasteboardItem) {
            var map: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    map[type] = data
                }
            }
            self.dataMap = map
        }
        
        func toItem() -> NSPasteboardItem {
            let item = NSPasteboardItem()
            for (type, data) in dataMap {
                item.setData(data, forType: type)
            }
            return item
        }
    }
    
    init(pasteboard: NSPasteboard) {
        self.changeCount = pasteboard.changeCount
        // Deep copy all items and their data
        self.items = pasteboard.pasteboardItems?.map { UnpackedPasteboardItem(item: $0) } ?? []
    }
    
    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let objects = items.map { $0.toItem() }
        if !objects.isEmpty {
            pasteboard.writeObjects(objects)
        }
    }
}
