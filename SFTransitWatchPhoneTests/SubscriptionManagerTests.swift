import XCTest
import StoreKitTest
@testable import SFTransitWatchPackage

@available(iOS 17, *)
final class SubscriptionManagerTests: XCTestCase {
    private var session: SKTestSession!

    override func setUp() async throws {
        let url = try XCTUnwrap(Bundle(for: SubscriptionManagerTests.self).url(forResource: "WorkerProxySubscription", withExtension: "storekit"))
        session = try SKTestSession(contentsOf: url)
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
    }

    override func tearDown() async throws {
        session.clearTransactions()
    }

    func testProductIDsIncludeMonthly() {
        XCTAssertTrue(SubscriptionManager.workerProxyProductIDs.contains(SubscriptionManager.workerProxyProductID))
    }

    func testActiveOriginalTransactionIdReturnsNilWithNoSubscription() async {
        let manager = SubscriptionManager()
        let result = await manager.activeOriginalTransactionId()
        XCTAssertNil(result)
    }

    // Known issue: Product.products(for:) returns productNotFound unless the SFTransitWatch
    // scheme's Test action StoreKit Configuration is set to WorkerProxySubscription.storekit.
    // These stay skipped until that scheme setting is applied (see CLAUDE.md / README).
    func testLoadDisplayInfoReturnsTiersSortedByPeriod() async throws {
        try XCTSkipIf(true, "Product.products(for:) returns productNotFound — needs the scheme's Test action StoreKit Configuration set to WorkerProxySubscription.storekit.")

        let manager = SubscriptionManager()
        let tiers = await manager.loadDisplayInfo()
        XCTAssertEqual(tiers.map(\.productID),
                       ["org.larner.SFTransitWatch.proxy.monthly", "org.larner.SFTransitWatch.proxy.yearly"])
        XCTAssertEqual(tiers.first?.introOffer?.paymentMode, .freeTrial)
        XCTAssertEqual(tiers.first?.introOffer?.periodCount, 1)
        XCTAssertEqual(tiers.first?.introOffer?.periodLabel, "week")
        XCTAssertNil(tiers.last?.introOffer)
    }

    func testPurchaseReturnsOriginalTransactionId() async throws {
        try XCTSkipIf(true, "Product.products(for:) returns productNotFound — needs the scheme's Test action StoreKit Configuration set to WorkerProxySubscription.storekit.")

        let manager = SubscriptionManager()
        let originalTransactionId = try await manager.purchase(productID: SubscriptionManager.workerProxyProductID)
        XCTAssertFalse(originalTransactionId.isEmpty)

        let active = await manager.activeOriginalTransactionId()
        XCTAssertEqual(active, originalTransactionId)
    }
}
