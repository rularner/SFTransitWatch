import SwiftUI
import WatchKit
import WatchConnectivity
import SFTransitWatchPackage

@main
struct SFTransitWatchApp: App {
    @WKApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var tokenExchange = WorkerTokenExchange()
    @State private var pendingBootstrap: PendingBootstrap?
    @State private var showingSetup = false
    @State private var showingKeyEntry = false
    @State private var provisionError: String?
    private let provisionService = SelfProvisionService.makeFromBundle()
    private let subscriptionManager = SubscriptionManager()

    init() {
        WatchSession.shared.activate()
        SFTransitWatchAppShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    guard !ConfigurationManager.shared.isConfigured else { return }
                    // If the companion iPhone app is installed, wait for WatchConnectivity
                    // to deliver the token rather than self-provisioning here.
                    let companionInstalled = WCSession.isSupported() && WCSession.default.isCompanionAppInstalled
                    if !companionInstalled {
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
                .sheet(isPresented: $showingSetup) {
                    SetupView(
                        canSubscribe: provisionService != nil,
                        onSubscribe: { Task { await handleSubscribeAndProvision() } },
                        onUseKey: {
                            showingSetup = false
                            showingKeyEntry = true
                        }
                    )
                }
                .sheet(isPresented: $showingKeyEntry) {
                    NavigationStack { SettingsView() }
                }
                .alert("Connection Failed", isPresented: Binding(
                    get: { provisionError != nil },
                    set: { if !$0 { provisionError = nil } }
                )) {
                    Button("Try Again") {
                        Task { await handleSubscribeAndProvision() }
                    }
                    Button("Use 511.org key instead") {
                        provisionError = nil
                        showingKeyEntry = true
                    }
                    Button("Cancel", role: .cancel) { provisionError = nil }
                } message: {
                    Text(provisionError ?? "")
                }
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
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Telemetry.shared.flush()
                Task { await refreshSubscriptionIfNeeded() }
            }
        }
    }

    private func handleSubscribeAndProvision() async {
        guard let service = provisionService else { return }
        do {
            let originalTransactionId: String
            if let existing = await subscriptionManager.activeOriginalTransactionId() {
                originalTransactionId = existing
            } else {
                originalTransactionId = try await subscriptionManager.purchase()
            }

            let result = await service.provision(workerURL: ConfigurationManager.shared.workerBaseURL, originalTransactionId: originalTransactionId)
            switch result {
            case .success:
                showingSetup = false
            case .failure:
                showingSetup = false
                provisionError = "Could not connect to the transit server. Check your connection and try again."
            }
        } catch SubscriptionManagerError.purchaseCancelled {
            showingSetup = false
        } catch {
            showingSetup = false
            provisionError = "Could not complete the subscription purchase. Check your connection and try again."
        }
    }

    private func refreshSubscriptionIfNeeded() async {
        guard let service = provisionService, ConfigurationManager.shared.isWorkerConfigured else { return }
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
