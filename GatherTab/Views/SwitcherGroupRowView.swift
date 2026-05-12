import SwiftUI

struct SwitcherGroupRowView: View {
    let group: AppGroup
    let iconURL: URL?
    let runningAppCount: Int
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            GroupIconView(iconURL: iconURL, size: 38)

            VStack(alignment: .leading, spacing: 3) {
                Text(group.name)
                    .font(.headline)
                    .lineLimit(1)

                Text("\(group.apps.count)개 앱 · 실행 중 \(runningAppCount)개")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if isSelected {
                Image(systemName: "return")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.22) : Color.clear)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor.opacity(0.55) : Color.clear, lineWidth: 1)
        }
        .contentShape(Rectangle())
    }
}
