import AppKit
import SwiftUI

/// Renders one row per `OSCCommand.supportedAddresses` entry — the address
/// pattern (with an `<argHint>` suffix where it takes one) plus a Copy button
/// that puts the bare address on the pasteboard. Shared by the Settings → OSC
/// pane and the OSC monitor so the list and the copy behaviour live in one
/// place; embed it inside a `Section` (Settings) or a `List`/`VStack` (monitor).
struct OSCSupportedAddressList: View {

    var body: some View {
        ForEach(OSCCommand.supportedAddresses) { entry in
            HStack {
                Text(entry.displayPattern)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                Spacer()
                Button("Copy") { Self.copyToPasteboard(entry.address) }
                    .controlSize(.small)
            }
        }
    }

    static func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
