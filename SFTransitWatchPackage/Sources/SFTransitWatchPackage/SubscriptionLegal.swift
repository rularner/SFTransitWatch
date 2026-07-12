import Foundation

/// Single source of truth for the functional legal links required in the purchase
/// flow by App Store Review Guideline 3.1.2.
public enum SubscriptionLegal {
    /// Apple's standard Licensed Application EULA (the default terms that apply
    /// when no custom EULA is provided).
    public static let termsOfUseURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    public static let privacyPolicyURL = URL(string: "https://www.sftransitwatch.com/privacy_policy.html")!
}
