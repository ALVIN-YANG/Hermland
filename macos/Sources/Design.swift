import SwiftUI

enum HermlandColor {
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let panel = Color(nsColor: .controlBackgroundColor)
    static let sidebar = Color(nsColor: .underPageBackgroundColor)
    static let line = Color(nsColor: .separatorColor)
    static let secondary = Color(nsColor: .secondaryLabelColor)
    static let tertiary = Color(nsColor: .tertiaryLabelColor)
    static let accent = Color(red: 0.18, green: 0.42, blue: 0.38)
    static let userBubble = Color(red: 0.16, green: 0.38, blue: 0.34)
}

struct StatusDot: View {
    let ok: Bool

    var body: some View {
        Circle()
            .fill(ok ? Color(red: 0.18, green: 0.62, blue: 0.38) : Color.orange)
            .frame(width: 8, height: 8)
    }
}
