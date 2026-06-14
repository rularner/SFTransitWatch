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

    func testActiveOriginalTransactionIdReturnsNilWithNoSubscription() async {
        let manager = SubscriptionManager()
        let result = await manager.activeOriginalTransactionId()
        XCTAssertNil(result)
    }

    func testActiveOriginalTransactionIdReturnsIdAfterPurchase() async throws {
        let manager = SubscriptionManager()
        try await session.buyProduct(productIdentifier: SubscriptionManager.workerProxyProductID)

        let result = await manager.activeOriginalTransactionId()
        XCTAssertNotNil(result)
    }

    func testPurchaseReturnsOriginalTransactionId() async throws {
        let manager = SubscriptionManager()
        let originalTransactionId = try await manager.purchase()
        XCTAssertFalse(originalTransactionId.isEmpty)

        let active = await manager.activeOriginalTransactionId()
        XCTAssertEqual(active, originalTransactionId)
    }
}
