import SwiftUI

// Observe the preference inside each window's view tree so existing windows
// update immediately when the collector's appearance button is clicked.
struct SavedAppearance: ViewModifier {
    @AppStorage("appearance") private var appearance = "system"
    func body(content: Content) -> some View {
        content.preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
    }
}
