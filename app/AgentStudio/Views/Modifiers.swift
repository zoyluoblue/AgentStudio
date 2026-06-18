import SwiftUI

extension View {
    /// Strip the "smart" text services from a field so focusing it doesn't pay a synchronous
    /// XPC handshake to system services (Writing Tools / Apple Intelligence, autofill, etc.) —
    /// the thing that can beach-ball the main thread on the first focus on some machines.
    @ViewBuilder
    func plainTextEntry() -> some View {
        if #available(macOS 15.0, *) {
            self.writingToolsBehavior(.disabled)
                .autocorrectionDisabled(true)
                .textContentType(nil)
        } else {
            self.autocorrectionDisabled(true)
                .textContentType(nil)
        }
    }
}
