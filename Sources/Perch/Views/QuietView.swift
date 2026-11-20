import SwiftUI

/// Empty state for the agent list (no sessions).
struct QuietView: View {
    var body: some View {
        Text("All quiet").font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.text)
            .frame(maxWidth: .infinity).padding(.vertical, 18)
    }
}
