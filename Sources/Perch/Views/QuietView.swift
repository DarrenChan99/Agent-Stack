import SwiftUI

struct QuietView: View {
    let fetcher: UsageFetcher

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("All quiet").font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.text)
                .frame(maxWidth: .infinity).padding(.vertical, 18)
            MeterView(label: "5H", window: fetcher.usage?.fiveHour)
            MeterView(label: "7D", window: fetcher.usage?.weekly)
        }
        .padding(16)
        .frame(width: 340)
        .perchPanel()
    }
}
