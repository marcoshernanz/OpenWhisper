import AppKit
import CoreGraphics
import Foundation

enum TextInserter {
    static func insert(_ text: String) {
        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot.capture(from: pasteboard)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        sendPasteShortcut()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            snapshot.restore(to: pasteboard)
        }
    }

    private static func sendPasteShortcut() {
        let source = CGEventSource(stateID: .privateState)
        let vKey: CGKeyCode = 9

        let keyDown = CGEvent(
            keyboardEventSource: source,
            virtualKey: vKey,
            keyDown: true
        )
        keyDown?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)

        let keyUp = CGEvent(
            keyboardEventSource: source,
            virtualKey: vKey,
            keyDown: false
        )
        keyUp?.flags = .maskCommand
        keyUp?.post(tap: .cghidEventTap)
    }
}

private struct PasteboardSnapshot {
    let items: [Item]

    static func capture(from pasteboard: NSPasteboard) -> PasteboardSnapshot {
        let items: [Item] = pasteboard.pasteboardItems?.map { item in
            let values = item.types.compactMap { type -> Value? in
                guard let data = item.data(forType: type) else { return nil }
                return Value(type: type, data: data)
            }
            return Item(values: values)
        } ?? []

        return PasteboardSnapshot(items: items)
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let restoredItems = items.map { item in
            let pasteboardItem = NSPasteboardItem()
            for value in item.values {
                pasteboardItem.setData(value.data, forType: value.type)
            }
            return pasteboardItem
        }
        pasteboard.writeObjects(restoredItems)
    }

    struct Item {
        let values: [Value]
    }

    struct Value {
        let type: NSPasteboard.PasteboardType
        let data: Data
    }
}
