import SwiftUI

@MainActor
public final class CommutePromptState: ObservableObject {
    @Published public var isPresented = false
    @Published public var emptySlots: [CommuteSlotsManager.Slot] = []

    public init() {}

    /// Call right after toggling a favorite. If the toggle just *added* a
    /// favorite and at least one commute slot is unconfigured, presents the
    /// "add to commute?" prompt. No-op when removing a favorite or when
    /// every slot is already configured.
    public func offerIfAdding(_ isAdding: Bool, slotsManager: CommuteSlotsManager) {
        guard isAdding else { return }
        let empty = CommuteSlotsManager.Slot.allCases.filter { slotsManager.stopId(for: $0) == nil }
        guard !empty.isEmpty else { return }
        emptySlots = empty
        isPresented = true
    }
}

private struct CommutePromptModifier: ViewModifier {
    @ObservedObject var state: CommutePromptState
    let stopId: String
    let stopName: String
    let slotsManager: CommuteSlotsManager
    var showNeverAsk: Bool
    var onNeverAsk: (() -> Void)?

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "Add to commute?",
            isPresented: $state.isPresented
        ) {
            if state.emptySlots.contains(.morning) {
                Button("Morning Commute") { slotsManager.setStopId(stopId, for: .morning) }
            }
            if state.emptySlots.contains(.afternoon) {
                Button("Afternoon Commute") { slotsManager.setStopId(stopId, for: .afternoon) }
            }
            if showNeverAsk {
                Button("Never Ask") { onNeverAsk?() }
            }
            Button("Not Now", role: .cancel) { }
        } message: {
            Text("Use \"\(stopName)\" as a commute stop?")
        }
    }
}

public extension View {
    func commutePrompt(
        _ state: CommutePromptState,
        stopId: String,
        stopName: String,
        slotsManager: CommuteSlotsManager,
        showNeverAsk: Bool = false,
        onNeverAsk: (() -> Void)? = nil
    ) -> some View {
        modifier(CommutePromptModifier(
            state: state,
            stopId: stopId,
            stopName: stopName,
            slotsManager: slotsManager,
            showNeverAsk: showNeverAsk,
            onNeverAsk: onNeverAsk
        ))
    }
}

public struct FavoriteToggleButton: View {
    let stop: BusStop
    @ObservedObject var favoritesManager: FavoritesManager
    let slotsManager: CommuteSlotsManager
    @ObservedObject var commutePrompt: CommutePromptState
    var font: Font

    public init(
        stop: BusStop,
        favoritesManager: FavoritesManager,
        slotsManager: CommuteSlotsManager,
        commutePrompt: CommutePromptState,
        font: Font = .title2
    ) {
        self.stop = stop
        self.favoritesManager = favoritesManager
        self.slotsManager = slotsManager
        self.commutePrompt = commutePrompt
        self.font = font
    }

    public var body: some View {
        Button(action: {
            let isAdding = !favoritesManager.isFavorite(stop.id)
            favoritesManager.toggleFavorite(stop)
            commutePrompt.offerIfAdding(isAdding, slotsManager: slotsManager)
        }) {
            Image(systemName: favoritesManager.isFavorite(stop.id) ? "star.fill" : "star")
                .foregroundColor(favoritesManager.isFavorite(stop.id) ? .yellow : .gray)
                .font(font)
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(favoritesManager.isFavorite(stop.id) ? "Remove from favorites" : "Add to favorites")
    }
}
