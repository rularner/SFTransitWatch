# iOS Companion App + Phone→Watch Transit Key Sync

**Date:** 2026-04-16
**Status:** Approved

## Background

`SFTransitWatch` ships today as a standalone watchOS app. App Store Connect no longer offers "watchOS" as a creatable platform, and Xcode 16's Organizer does not show "App Store Connect" as a destination for standalone watchOS App Archives. The only viable distribution path is to package the watch app inside an iOS app and submit them as a paired iOS+watchOS app record.

A working set of iOS source files already exists on disk in `SFTransitWatch/` (left over from an earlier paired-app attempt) but is not referenced by the current `project.pbxproj`. This spec wires those files into a new iOS target and adds a small WatchConnectivity bridge so the watch can reuse the iPhone's 511.org API key.

## Goals

1. Add a fully functional iOS app target to the existing Xcode project, reusing the source files in `SFTransitWatch/`.
2. Embed the existing watch app in the iOS app per Apple's standard paired-app structure.
3. Have the iPhone push its 511.org API key to the watch over WatchConnectivity, so users only configure the key once.
4. Preserve the watch's ability to run independently of the phone (existing `WKRunsIndependentlyOfCompanionApp = YES` stays).
5. Make the project archivable as an iOS App Archive that can be uploaded to App Store Connect via Xcode Organizer.

## Non-Goals

- No iCloud sync, app groups, or shared keychain.
- No changes to watch UI or business logic beyond the API-key resolution helper.
- No changes to the existing `SFTransitWatch Complication` widget extension.
- No new test target; existing `SFTransitWatchTests` stays as-is.
- No deletion of the existing `SFTransitWatch/` source files (they are now load-bearing for the iOS target).

## Architecture

### Targets after this change

| Target | Platform | Bundle ID | Notes |
|---|---|---|---|
| `SFTransitWatch` | iOS 17.0+ | `org.larner.SFTransitWatch` | New target. Compiles `SFTransitWatch/*.swift`. Embeds the watch app. |
| `SFTransitWatch Watch App` | watchOS 11.0+ | `org.larner.SFTransitWatch.watchkitapp` | Existing target. Bundle ID matches Apple's `<iOSBundleID>.watchkitapp` convention. |
| `SFTransitWatch Complication` | watchOS | (unchanged) | Existing widget extension. No change. |
| `SFTransitWatchTests` | iOS unit tests | (unchanged) | Existing tests. No change. |

### Embedding

The iOS target gets a Copy Files build phase with destination `Watch` (folder spec 16) that embeds the built `SFTransitWatch Watch App.app` product. A target dependency from iOS → watch ensures correct build order.

The watch's `Info.plist` already declares `WKCompanionAppBundleIdentifier = org.larner.SFTransitWatch`, so no Info.plist changes are needed on the watch side.

### Phone→Watch transit key sync

Two new files implement WatchConnectivity bridges using `WCSession` with `updateApplicationContext` (persistent, latest-wins, survives relaunch):

**`SFTransitWatch/PhoneSession.swift` (iOS)**
- Singleton `PhoneSession` conforming to `NSObject, WCSessionDelegate`.
- On app launch: activates `WCSession.default` and pushes the current API key.
- Observes changes to `@AppStorage("511_API_KEY")` (via `UserDefaults.didChangeNotification` or an explicit call from `SettingsView`) and pushes the new value via `updateApplicationContext(["transitKey": key])`.
- Handles empty-string key by pushing an empty value (so unsetting the key on the phone clears the watch's cached phone key).

**`SFTransitWatch Watch App/WatchSession.swift` (watchOS)**
- Singleton `WatchSession` conforming to `NSObject, WCSessionDelegate`.
- On app launch: activates `WCSession.default`.
- In `session(_:didReceiveApplicationContext:)`: stores `applicationContext["transitKey"]` into `@AppStorage("511_API_KEY_FROM_PHONE")` (UserDefaults under that key).

### TransitAPI key resolution

Single change to the existing `TransitAPI.swift` (file lives in both `SFTransitWatch/` and `SFTransitWatch Watch App/` — both copies updated identically):

```swift
@AppStorage("511_API_KEY") private var watchLocalKey = ""
@AppStorage("511_API_KEY_FROM_PHONE") private var phoneKey = ""

private var apiKey: String {
    if !phoneKey.isEmpty { return phoneKey }
    return watchLocalKey
}

private var hasUsableKey: Bool {
    !phoneKey.isEmpty || !watchLocalKey.isEmpty
}
```

Existing call sites that currently check `!storedAPIKey.isEmpty` switch to `hasUsableKey`. The behavior on iOS is unchanged because no `WCSession` ever pushes a `transitKey` to the iOS app itself, so `phoneKey` stays empty there.

## Xcode project changes

Edits to `SFTransitWatch.xcodeproj/project.pbxproj` (surgical edits, not a full rewrite):

1. **PBXFileReference entries** for the new files in `SFTransitWatch/` and the new `SFTransitWatch.app` product.
2. **PBXGroup** for `SFTransitWatch` listing all the iOS source files plus `Assets.xcassets`, `Info.plist`, `Preview Content`.
3. **PBXBuildFile** entries for the iOS target's Sources, Resources, and the embed-watch Copy Files phase.
4. **PBXSourcesBuildPhase, PBXResourcesBuildPhase, PBXFrameworksBuildPhase** for the iOS target.
5. **PBXCopyFilesBuildPhase** with `dstSubfolderSpec = 16`, `dstPath = "$(CONTENTS_FOLDER_PATH)/Watch"`, copying `SFTransitWatch Watch App.app`.
6. **PBXTargetDependency + PBXContainerItemProxy** wiring iOS → watch.
7. **PBXNativeTarget** `SFTransitWatch` with productType `com.apple.product-type.application`.
8. **XCBuildConfiguration** entries (Debug + Release) for the iOS target with:
   - `SDKROOT = iphoneos`
   - `IPHONEOS_DEPLOYMENT_TARGET = 17.0`
   - `TARGETED_DEVICE_FAMILY = "1,2"`
   - `PRODUCT_BUNDLE_IDENTIFIER = org.larner.SFTransitWatch`
   - `INFOPLIST_FILE = SFTransitWatch/Info.plist`
   - `CODE_SIGN_STYLE = Automatic`
   - `DEVELOPMENT_TEAM = 7W4U5RR9QZ` (matches existing)
   - Standard SwiftUI app boilerplate flags
9. **XCConfigurationList** for the iOS target.
10. **PBXProject.targets** array updated to include the new iOS target.
11. **Project SDKROOT**: stays `watchos` at the project level since per-target `SDKROOT` overrides it; alternatively switch project-level to `iphoneos` (decision: leave per-target overrides; project-level value is irrelevant when both targets set their own).

## App Store Connect changes (manual, outside the codebase)

After the code changes are merged, the user does this in the web UI (not automated):

1. **Apple Developer portal** → register new bundle ID `org.larner.SFTransitWatch` (Explicit App ID).
2. **App Store Connect** → delete the existing app record with bundle ID `org.larner.SFTransitWatch.watchkitapp` (safe — no builds uploaded).
3. **App Store Connect** → "+" New App → platform iOS → bundle ID `org.larner.SFTransitWatch` → fill in name, SKU, language.
4. **Xcode** → archive (now produces an iOS App Archive that includes the watch app) → Distribute App → App Store Connect should now appear as a destination.

## Open Questions / Risks

- **`SDKROOT = watchos` at project level**: previously rewriting the pbxproj set this; might cause warnings for the new iOS target. Mitigation: per-target `SDKROOT` overrides at the configuration level, which is standard.
- **Asset catalog conflicts**: `SFTransitWatch/Assets.xcassets` and `SFTransitWatch Watch App/Assets.xcassets` are separate; iOS target references only its own. App icons in the iOS catalog need iOS sizes; verify in Xcode after wiring.
- **WCSession activation timing**: must call `WCSession.default.delegate = self; WCSession.default.activate()` early in app launch (in `App.init` or `.onAppear` of root view) on both sides.
- **First-time pairing**: if the watch was installed before the iPhone app, the watch may not receive `applicationContext` until the iPhone app launches once. Acceptable — user will manually launch the iPhone app to enter the key.

## Success Criteria

1. `xcodebuild -scheme "SFTransitWatch" -sdk iphoneos archive` produces a valid `.xcarchive` containing both the iOS `.app` and the embedded watch `.app`.
2. Xcode Organizer → Distribute App offers "App Store Connect" as a destination for the new archive.
3. After entering an API key in the iOS Settings screen and launching the watch app on a paired Apple Watch, the watch fetches real bus data using the phone-supplied key without the user entering it again on the watch.
4. Watch continues to function independently if no phone is paired (using its locally entered key, if any).
5. Existing watch-only flows (favorites, complications, Siri shortcuts) continue to work unchanged.
