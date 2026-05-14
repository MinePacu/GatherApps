import SwiftUI

struct FloatingSwitcherView: View {
    @ObservedObject var viewModel: SwitcherViewModel

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            if viewModel.groups.isEmpty {
                ContentUnavailableView("switcher.noGroups", systemImage: "square.grid.2x2")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(viewModel.groups) { group in
                                SwitcherGroupRowView(
                                    group: group,
                                    iconURL: viewModel.iconURL(for: group),
                                    runningAppCount: viewModel.runningAppCount(for: group),
                                    isSelected: viewModel.isSelected(group)
                                )
                                .id(group.id)
                                .onTapGesture {
                                    viewModel.activateGroup(group)
                                }
                            }
                        }
                        .padding(10)
                    }
                    .onChange(of: viewModel.selectedIndex) {
                        scrollSelectionIntoView(proxy)
                    }
                }
            }
        }
        .frame(width: 420, height: 360)
        .background(.regularMaterial)
        .onAppear {
            viewModel.refresh()
        }
    }

    private var header: some View {
        HStack {
            Text("switcher.title")
                .font(.headline)

            Spacer()

            Button {
                viewModel.dismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help(Text("common.close"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func scrollSelectionIntoView(_ proxy: ScrollViewProxy) {
        guard viewModel.groups.indices.contains(viewModel.selectedIndex) else { return }
        proxy.scrollTo(viewModel.groups[viewModel.selectedIndex].id, anchor: .center)
    }
}
