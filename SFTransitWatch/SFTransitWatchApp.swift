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
    @State private var isRestoring = false
    @State private var restoreError: String?
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
                        canSubscribe: true,
                        tiers: subscriptionTiers,
                        isPurchasing: isPurchasing,
                        onSubscribe: { productID in Task { await handleSubscribeAndProvision(productID: productID) } },
                        isRestoring: isRestoring,
                        onRestore: { Task { await handleRestore() } },
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
                    .alert("Restore Purchases", isPresented: Binding(
                        get: { restoreError != nil },
                        set: { if !$0 { restoreError = nil } }
                    )) {
                        Button("OK") { restoreError = nil }
                    } message: {
                        Text(restoreError ?? "")
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
        let service = provisionService
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            var signedTransactionInfo: String
            var usedExistingEntitlement = false
            if let existing = await subscriptionManager.activeEntitlementJWS() {
                signedTransactionInfo = existing
                usedExistingEntitlement = true
            } else {
                signedTransactionInfo = try await subscriptionManager.purchase(productID: productID)
            }

            var result = await service.provision(workerURL: ConfigurationManager.shared.workerBaseURL, signedTransactionInfo: signedTransactionInfo)
            if case .failure = result, usedExistingEntitlement {
                // The cached entitlement didn't hold up server-side (e.g. it actually
                // expired since the local check ran) — fall back to a real purchase
                // instead of leaving the user stuck with no way to subscribe.
                signedTransactionInfo = try await subscriptionManager.purchase(productID: productID)
                result = await service.provision(workerURL: ConfigurationManager.shared.workerBaseURL, signedTransactionInfo: signedTransactionInfo)
            }
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

    private func handleRestore() async {
        let service = provisionService
        isRestoring = true
        defer { isRestoring = false }
        do {
            let signedTransactionInfo = try await subscriptionManager.restore()
            let result = await service.provision(workerURL: ConfigurationManager.shared.workerBaseURL, signedTransactionInfo: signedTransactionInfo)
            switch result {
            case .success:
                showingSetup = false
            case .failure:
                restoreError = "Could not connect to the transit server. Check your internet connection and try again."
            }
        } catch SubscriptionManagerError.noActiveSubscription {
            restoreError = "No active subscription found for this Apple ID."
        } catch {
            restoreError = "Could not restore your purchase. Check your internet connection and try again."
        }
    }

    private func refreshSubscriptionIfNeeded() async {
        guard ConfigurationManager.shared.isWorkerConfigured else { return }
        let now = Date()
        guard ProvisionRefreshGate.shouldRefresh(lastRefreshAt: ConfigurationManager.shared.lastProvisionRefreshAt, now: now) else { return }
        ConfigurationManager.shared.lastProvisionRefreshAt = now
        guard let signedTransactionInfo = await subscriptionManager.activeEntitlementJWS() else { return }
        _ = await provisionService.provision(workerURL: ConfigurationManager.shared.workerBaseURL, signedTransactionInfo: signedTransactionInfo)
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
