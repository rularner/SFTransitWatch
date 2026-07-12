import XCTest
@testable import SFTransitWatchPackage

final class SubscriptionDisplayInfoTests: XCTestCase {

    private func makeInfo(intro: IntroOfferInfo? = nil) -> SubscriptionDisplayInfo {
        SubscriptionDisplayInfo(
            productID: "org.larner.SFTransitWatch.proxy.monthly",
            displayName: "Monthly",
            displayPrice: "$1.99",
            periodLabel: "month",
            introOffer: intro
        )
    }

    func testPricePerPeriodJoinsPriceAndPeriod() {
        XCTAssertEqual(makeInfo().pricePerPeriod, "$1.99/month")
    }

    func testFreeTrialSummary() {
        let intro = IntroOfferInfo(displayPrice: "Free", periodLabel: "day", periodCount: 7, paymentMode: .freeTrial)
        XCTAssertEqual(intro.summary, "Free for 7 days")
    }

    func testFreeTrialSummarySingularPeriod() {
        let intro = IntroOfferInfo(displayPrice: "Free", periodLabel: "week", periodCount: 1, paymentMode: .freeTrial)
        XCTAssertEqual(intro.summary, "Free for 1 week")
    }

    func testPayAsYouGoSummary() {
        let intro = IntroOfferInfo(displayPrice: "$0.99", periodLabel: "month", periodCount: 3, paymentMode: .payAsYouGo)
        XCTAssertEqual(intro.summary, "$0.99/month for the first 3 months")
    }

    func testPayUpFrontSummary() {
        let intro = IntroOfferInfo(displayPrice: "$4.99", periodLabel: "month", periodCount: 6, paymentMode: .payUpFront)
        XCTAssertEqual(intro.summary, "$4.99 for the first 6 months")
    }

    func testDisclosureWithoutIntroMentionsPriceAndAutoRenew() {
        let text = makeInfo().autoRenewalDisclosure
        XCTAssertTrue(text.contains("$1.99/month"), "disclosure should state the billed price/period")
        XCTAssertTrue(text.contains("automatically renews"), "disclosure should state auto-renewal")
        XCTAssertTrue(text.contains("at least 24 hours"), "disclosure should state the 24-hour cancellation window")
        XCTAssertTrue(text.contains("Account Settings"), "disclosure should state where to manage/cancel")
        XCTAssertFalse(text.contains("Free for"), "no intro terms when there is no intro offer")
    }

    func testDisclosureWithIntroLeadsWithOfferTerms() {
        let intro = IntroOfferInfo(displayPrice: "Free", periodLabel: "day", periodCount: 7, paymentMode: .freeTrial)
        let text = makeInfo(intro: intro).autoRenewalDisclosure
        XCTAssertTrue(text.contains("Free for 7 days"), "disclosure should state the intro terms")
        XCTAssertTrue(text.contains("then $1.99/month"), "disclosure should state the price after the intro")
    }
}
