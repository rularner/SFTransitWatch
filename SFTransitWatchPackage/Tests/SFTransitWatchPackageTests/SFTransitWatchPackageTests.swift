import Testing
@testable import SFTransitWatchPackage

@Suite struct EffectiveHeadingTests {
    @Test func prefersTrueHeadingWhenPositive() {
        #expect(effectiveHeadingDegrees(trueHeading: 90.0, magneticHeading: 85.0) == 90.0)
    }

    @Test func trueHeadingZeroIsValid() {
        // 0.0 = true north; ≥ 0 so trueHeading should win
        #expect(effectiveHeadingDegrees(trueHeading: 0.0, magneticHeading: 10.0) == 0.0)
    }

    @Test func fallsBackToMagneticWhenTrueIsNegative() {
        // CLHeading uses -1 when trueHeading is uncalibrated
        #expect(effectiveHeadingDegrees(trueHeading: -1.0, magneticHeading: 85.0) == 85.0)
    }

    @Test func trueHeading360IsValid() {
        #expect(effectiveHeadingDegrees(trueHeading: 360.0, magneticHeading: 10.0) == 360.0)
    }
}
