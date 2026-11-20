import SwiftUI

struct QuietView: View {
    let fetcher: UsageFetcher

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("All quiet").font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.text)
                .frame(maxWidth: .infinity).padding(.vertical, 18)
            MeterView(label: "5H", window: fetcher.displayUsage?.fiveHour)
            MeterView(label: "7D", window: fetcher.displayUsage?.weekly)
        }
        .padding(16)
        .frame(width: 340)
        .perchPanel()
    }
}
