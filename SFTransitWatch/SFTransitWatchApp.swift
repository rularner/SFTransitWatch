import SwiftUI
import SFTransitWatchPackage

@main
struct SFTransitWatchApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var tokenExchange = WorkerTokenExchange()
    @State private var pendingBootstrap: PendingBootstrap?
    @State private var showingSetup = false
    @State private var showingKeyEntry = false
    @State private var pendingKeyEntry = false
    @State private var provisionError: String?
    @State private var subscriptionTiers: [SubscriptionDisplayInfo] = []
    @State private var isPurchasing = false
    @StateObject private var favoritesManager = FavoritesManager()
    @StateObject private var slotsManager = CommuteSlotsManager()
    private let provisionService = SelfProvisionService.makeFromBundle()
    private let subscriptionManager = SubscriptionManager()

    init() {
        PhoneSession.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    if !ConfigurationManager.shared.isConfigured {
                        showingSetup = true
                    }
                }
                .onOpenURL { url in
                    if let key = WorkerConfigLink.apiKey(from: url), !key.isEmpty {
                        ConfigurationManager.shared.apiKey = key
                        return
                    }
                    if let bootstrap = WorkerConfigLink.workerBootstrap(from: url) {
                        pendingBootstrap = PendingBootstrap(url: bootstrap.url, code: bootstrap.code)
                    }
                }
                // Onboarding sheet
                .sheet(isPresented: $showingSetup, onDismiss: {
                    if pendingKeyEntry {
                        showingKeyEntry = true
                        pendingKeyEntry = false
                    }
                }) {
                    SetupView(
                        canSubscribe: provisionService != nil,
                        tiers: subscriptionTiers,
                        isPurchasing: isPurchasing,
                        onSubscribe: { productID in Task { await handleSubscribeAndProvision(productID: productID) } },
                        onUseKey: {
                            pendingKeyEntry = true
                            showingSetup = false
                        }
                    )
                    .task {
                        if subscriptionTiers.isEmpty {
                            subscriptionTiers = SnapshotMode.showPaywall
                                ? SnapshotMode.subscriptionTiers
                                : await subscriptionManager.loadDisplayInfo()
                        }
                    }
                }
                // 511.org key entry fallback
                .sheet(isPresented: $showingKeyEntry) {
                    NavigationStack { SettingsView() }
                }
                // Provision error alert
                .alert("Connection Failed", isPresented: Binding(
                    get: { provisionError != nil },
                    set: { if !$0 { provisionError = nil } }
                )) {
                    Button("Try Again") {
                        Task { await handleSubscribeAndProvision(productID: SubscriptionManager.workerProxyProductID) }
                    }
                    Button("Use 511.org key instead") {
                        provisionError = nil
                        showingKeyEntry = true
                    }
                    Button("Cancel", role: .cancel) { provisionError = nil }
                } message: {
                    Text(provisionError ?? "")
                }
                // Existing deep-link worker bootstrap dialog
                .confirmationDialog(
                    "Use this proxy?",
                    isPresented: Binding(
                        get: { pendingBootstrap != nil },
                        set: { if !$0 { pendingBootstrap = nil } }
                    ),
                    presenting: pendingBootstrap
                ) { bootstrap in
                    Button("Use \(bootstrap.displayHost)") {
                        let captured = bootstrap
                        pendingBootstrap = nil
                        Task { await handleWorkerBootstrap(captured) }
                    }
                    Button("Cancel", role: .cancel) { pendingBootstrap = nil }
                } message: { bootstrap in
                    Text("Route transit requests through \(bootstrap.displayHost)?")
                }
                // Inject here (outside ContentView) so sheets/dialogs presented at the
                // WindowGroup level — e.g. the onboarding key-entry SettingsView — also
                // inherit these environment objects. SettingsView requires them.
                .environmentObject(favoritesManager)
                .environmentObject(slotsManager)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Telemetry.shared.flush()
                Task { await refreshSubscriptionIfNeeded() }
            }
        }
    }

    private func handleSubscribeAndProvision(productID: String) async {
        guard let service = provisionService else { return }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let originalTransactionId: String
            if let existing = await subscriptionManager.activeOriginalTransactionId() {
                originalTransactionId = existing
            } else {
                originalTransactionId = try await subscriptionManager.purchase(productID: productID)
            }

            let result = await service.provision(workerURL: ConfigurationManager.shared.workerBaseURL, originalTransactionId: originalTransactionId)
            switch result {
            case .success:
                showingSetup = false
            case .failure:
                showingSetup = false
                provisionError = "Could not connect to the transit server. Check your internet connection and try again."
            }
        } catch SubscriptionManagerError.purchaseCancelled {
            showingSetup = false
        } catch {
            showingSetup = false
            provisionError = "Could not complete the subscription purchase. Check your internet connection and try again."
        }
    }

    private func refreshSubscriptionIfNeeded() async {
        guard let service = provisionService, ConfigurationManager.shared.isWorkerConfigured else { return }
        let now = Date()
        guard ProvisionRefreshGate.shouldRefresh(lastRefreshAt: ConfigurationManager.shared.lastProvisionRefreshAt, now: now) else { return }
        ConfigurationManager.shared.lastProvisionRefreshAt = now
        guard let originalTransactionId = await subscriptionManager.activeOriginalTransactionId() else { return }
        _ = await service.provision(workerURL: ConfigurationManager.shared.workerBaseURL, originalTransactionId: originalTransactionId)
    }

    private func handleWorkerBootstrap(_ bootstrap: PendingBootstrap) async {
        do {
            let token = try await tokenExchange.exchange(code: bootstrap.code, workerURL: bootstrap.url)
            ConfigurationManager.shared.setWorkerConfig(url: bootstrap.url, token: token)
        } catch {
            print("Worker token exchange failed: \(error.localizedDescription)")
        }
    }
}

private struct PendingBootstrap: Equatable {
    let url: String
    let code: String
    var displayHost: String { URL(string: url)?.host ?? url }
}
