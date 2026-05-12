import SwiftUI

struct CreateGroupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var groupName = ""

    let onCreate: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("새 그룹")
                .font(.title2)
                .fontWeight(.semibold)

            TextField("그룹 이름", text: $groupName)
                .textFieldStyle(.roundedBorder)
                .onSubmit(create)

            HStack {
                Spacer()
                Button("취소") {
                    dismiss()
                }
                Button("생성") {
                    create()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 340)
    }

    private func create() {
        onCreate(groupName)
        dismiss()
    }
}
