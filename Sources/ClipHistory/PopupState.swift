import Foundation
import Observation

/// Shared mutable state between PopupWindowController and PopupView.
/// Lives in the controller; the view observes it via @Bindable.
@Observable
final class PopupState {
    /// Bumped every time the popup opens — SwiftUI uses this to re-focus the search field.
    var showToken    = UUID()
    var searchText   = ""
    var selectedIndex = 0

    /// Prepare for a fresh open. Search is always cleared (it's transient);
    /// pass `keepSelection: true` to preserve the highlighted row so the list
    /// reopens where the user left off instead of snapping to the top.
    func reset(keepSelection: Bool = false) {
        showToken  = UUID()
        searchText = ""
        if !keepSelection { selectedIndex = 0 }
    }
}
