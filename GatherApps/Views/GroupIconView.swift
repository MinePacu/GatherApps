import AppKit
import SwiftUI

struct GroupIconView: View {
    let iconURL: URL?
    var size: CGFloat = 44

    var body: some View {
        AppIconImage(image: iconImage, size: size)
    }

    private var iconImage: NSImage? {
        guard let iconURL else { return nil }
        return NSImage(contentsOf: iconURL)
    }
}
