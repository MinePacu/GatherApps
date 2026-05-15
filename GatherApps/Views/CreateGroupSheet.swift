import SwiftUI

struct CreateGroupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var groupName = ""

    let onCreate: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("createGroup.title")
                .font(.title2)
                .fontWeight(.semibold)

            TextField("createGroup.namePlaceholder", text: $groupName)
                .textFieldStyle(.roundedBorder)
                .onSubmit(create)

            HStack {
                Spacer()
                Button("common.cancel") {
                    dismiss()
                }
                Button("common.create") {
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
