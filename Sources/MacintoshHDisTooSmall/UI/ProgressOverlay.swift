import SwiftUI

struct ProgressOverlay: View {
    let label: String
    let progress: Double

    var body: some View {
        ZStack {
            Color.black.opacity(0.2).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView(value: min(max(progress, 0), 1))
                    .progressViewStyle(.linear)
                    .frame(width: 300)
                Text(label)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(width: 300)
            }
            .padding(28)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .shadow(radius: 24)
        }
    }
}
