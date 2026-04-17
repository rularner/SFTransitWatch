# iOS Companion App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an iOS app target to `SFTransitWatch.xcodeproj` that reuses the existing `SFTransitWatch/*.swift` source files, embeds the watch app inside it, and shares the 511.org API key from phone to watch via WatchConnectivity.

**Architecture:** New iOS native target (`SFTransitWatch`, bundle ID `org.larner.SFTransitWatch`) compiles the iOS source files already on disk and embeds the existing watch app via a Copy Files build phase. A WCSession bridge on each side syncs the API key (phone → watch via `updateApplicationContext`). `TransitAPI` on the watch checks the phone-supplied key first and falls back to its own `@AppStorage` value.

**Tech Stack:** Swift 5, SwiftUI, WatchKit, WatchConnectivity, Xcode 16.4, iOS 17, watchOS 11.

**Spec:** `docs/superpowers/specs/2026-04-16-ios-companion-app-design.md`

---

## File Structure

**New files:**
- `SFTransitWatch/PhoneSession.swift` — iOS WCSessionDelegate; activates session and pushes the API key when iOS Settings change.
- `SFTransitWatch Watch App/WatchSession.swift` — watchOS WCSessionDelegate; receives the API key and stores it in `@AppStorage`.

**Modified files:**
- `SFTransitWatch/SFTransitWatchApp.swift` — remove `import WatchKit`; add `PhoneSession.shared.activate()` on app init.
- `SFTransitWatch Watch App/SFTransitWatchApp.swift` — add `WatchSession.shared.activate()` on app init.
- `SFTransitWatch/TransitAPI.swift` and `SFTransitWatch Watch App/TransitAPI.swift` — add `phoneKey` lookup; resolve `apiKey` in priority order (phone → local).
- `SFTransitWatch.xcodeproj/project.pbxproj` — add iOS target, build configs, source/resource/copy-files build phases, target dependency.

**Unchanged:**
- All other watch source files.
- `SFTransitWatch Complication/`.
- `SFTransitWatchTests/`.
- Both `Info.plist` files.

---

## Task 1: Verify clean baseline

**Files:** none

- [ ] **Step 1: Confirm git status is clean**

Run: `cd /Users/rustylarner/src/SFTransitWatch && git status`
Expected: `nothing to commit, working tree clean` (the spec was committed in the previous session).

- [ ] **Step 2: Confirm the watch app builds today**

Run:
```bash
cd /Users/rustylarner/src/SFTransitWatch
xcodebuild -project SFTransitWatch.xcodeproj -scheme "SFTransitWatch Watch App" -destination 'generic/platform=watchOS' clean build 2>&1 | tail -30
```
Expected: `** BUILD SUCCEEDED **`. If it fails, stop and resolve before proceeding — the plan assumes a working watch baseline.

- [ ] **Step 3: List current targets and schemes**

Run: `xcodebuild -list -project SFTransitWatch.xcodeproj`
Expected output includes:
```
Targets:
    SFTransitWatch Watch App
    SFTransitWatch Complication
    SFTransitWatchTests
```
Confirm there is no existing `SFTransitWatch` iOS target.

---

## Task 2: Fix iOS source files for iOS-only compilation

`SFTransitWatch/SFTransitWatchApp.swift` currently imports `WatchKit`, which doesn't exist on iOS. Remove the import.

**Files:**
- Modify: `SFTransitWatch/SFTransitWatchApp.swift:2`

- [ ] **Step 1: Edit `SFTransitWatch/SFTransitWatchApp.swift`**

Replace the file contents with:

```swift
import SwiftUI

@main
struct SFTransitWatchApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

(Removes `import WatchKit`. We'll add `PhoneSession.shared.activate()` in Task 9 once that file exists.)

- [ ] **Step 2: Commit**

```bash
cd /Users/rustylarner/src/SFTransitWatch
git add "SFTransitWatch/SFTransitWatchApp.swift"
git commit -m "Remove WatchKit import from iOS SFTransitWatchApp"
```

---

## Task 3: Add iOS native target to project.pbxproj

This is the largest single edit. We add the iOS target along with all build phases, configurations, and file references in one consistent change so we never leave the project in a half-broken state.

**Files:**
- Modify: `SFTransitWatch.xcodeproj/project.pbxproj`

ID prefix convention used for all new objects: `CAFE000000000000000020xx` (iOS target objects). This avoids collision with the existing `CAFE...12-19xx` (watch), `CAFE...C0xx` (complication), and `CAFE...T0xx` (tests) ranges.

- [ ] **Step 1: Back up the pbxproj**

Run: `cp SFTransitWatch.xcodeproj/project.pbxproj SFTransitWatch.xcodeproj/project.pbxproj.bak`

This is a temporary safety net while editing. We'll delete it at the end of this task.

- [ ] **Step 2: Add PBXBuildFile entries for iOS sources**

In `SFTransitWatch.xcodeproj/project.pbxproj`, find the line:
```
/* End PBXBuildFile section */
```

Insert immediately before it (after the existing build files):

```
		CAFE000000000000000020A0 /* SFTransitWatchApp.swift in Sources */ = {isa = PBXBuildFile; fileRef = CAFE000000000000000020B0 /* SFTransitWatchApp.swift */; };
		CAFE000000000000000020A1 /* ContentView.swift in Sources */ = {isa = PBXBuildFile; fileRef = CAFE000000000000000020B1 /* ContentView.swift */; };
		CAFE000000000000000020A2 /* BusStopListView.swift in Sources */ = {isa = PBXBuildFile; fileRef = CAFE000000000000000020B2 /* BusStopListView.swift */; };
		CAFE000000000000000020A3 /* BusArrivalView.swift in Sources */ = {isa = PBXBuildFile; fileRef = CAFE000000000000000020B3 /* BusArrivalView.swift */; };
		CAFE000000000000000020A4 /* LocationManager.swift in Sources */ = {isa = PBXBuildFile; fileRef = CAFE000000000000000020B4 /* LocationManager.swift */; };
		CAFE000000000000000020A5 /* TransitAPI.swift in Sources */ = {isa = PBXBuildFile; fileRef = CAFE000000000000000020B5 /* TransitAPI.swift */; };
		CAFE000000000000000020A6 /* BusStop.swift in Sources */ = {isa = PBXBuildFile; fileRef = CAFE000000000000000020B6 /* BusStop.swift */; };
		CAFE000000000000000020A7 /* BusArrival.swift in Sources */ = {isa = PBXBuildFile; fileRef = CAFE000000000000000020B7 /* BusArrival.swift */; };
		CAFE000000000000000020A8 /* FavoritesManager.swift in Sources */ = {isa = PBXBuildFile; fileRef = CAFE000000000000000020B8 /* FavoritesManager.swift */; };
		CAFE000000000000000020A9 /* SettingsView.swift in Sources */ = {isa = PBXBuildFile; fileRef = CAFE000000000000000020B9 /* SettingsView.swift */; };
		CAFE000000000000000020AA /* SiriManager.swift in Sources */ = {isa = PBXBuildFile; fileRef = CAFE000000000000000020BA /* SiriManager.swift */; };
		CAFE000000000000000020AB /* SiriShortcutsView.swift in Sources */ = {isa = PBXBuildFile; fileRef = CAFE000000000000000020BB /* SiriShortcutsView.swift */; };
		CAFE000000000000000020AC /* Assets.xcassets in Resources */ = {isa = PBXBuildFile; fileRef = CAFE000000000000000020BC /* Assets.xcassets */; };
		CAFE000000000000000020AD /* Preview Assets.xcassets in Resources */ = {isa = PBXBuildFile; fileRef = CAFE000000000000000020BD /* Preview Assets.xcassets */; };
		CAFE000000000000000020AE /* SFTransitWatch Watch App.app in Embed Watch Content */ = {isa = PBXBuildFile; fileRef = CAFE000000000000000016A0 /* SFTransitWatch Watch App.app */; settings = {ATTRIBUTES = (RemoveHeadersOnCopy, ); }; };
```

- [ ] **Step 3: Add PBXFileReference entries**

Find the line:
```
/* End PBXFileReference section */
```

Insert immediately before it:

```
		CAFE000000000000000020B0 /* SFTransitWatchApp.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = SFTransitWatchApp.swift; sourceTree = "<group>"; };
		CAFE000000000000000020B1 /* ContentView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ContentView.swift; sourceTree = "<group>"; };
		CAFE000000000000000020B2 /* BusStopListView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = BusStopListView.swift; sourceTree = "<group>"; };
		CAFE000000000000000020B3 /* BusArrivalView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = BusArrivalView.swift; sourceTree = "<group>"; };
		CAFE000000000000000020B4 /* LocationManager.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = LocationManager.swift; sourceTree = "<group>"; };
		CAFE000000000000000020B5 /* TransitAPI.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = TransitAPI.swift; sourceTree = "<group>"; };
		CAFE000000000000000020B6 /* BusStop.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = BusStop.swift; sourceTree = "<group>"; };
		CAFE000000000000000020B7 /* BusArrival.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = BusArrival.swift; sourceTree = "<group>"; };
		CAFE000000000000000020B8 /* FavoritesManager.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = FavoritesManager.swift; sourceTree = "<group>"; };
		CAFE000000000000000020B9 /* SettingsView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = SettingsView.swift; sourceTree = "<group>"; };
		CAFE000000000000000020BA /* SiriManager.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = SiriManager.swift; sourceTree = "<group>"; };
		CAFE000000000000000020BB /* SiriShortcutsView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = SiriShortcutsView.swift; sourceTree = "<group>"; };
		CAFE000000000000000020BC /* Assets.xcassets */ = {isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = "<group>"; };
		CAFE000000000000000020BD /* Preview Assets.xcassets */ = {isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = "Preview Assets.xcassets"; sourceTree = "<group>"; };
		CAFE000000000000000020BE /* Info.plist */ = {isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; };
		CAFE000000000000000020BF /* SFTransitWatch.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = SFTransitWatch.app; sourceTree = BUILT_PRODUCTS_DIR; };
```

- [ ] **Step 4: Add iOS PBXGroup and Preview Content subgroup; register iOS group in main group**

Find the existing `Preview Content` group (it appears after the `Products` group):

```
		CAFE000000000000000019A0 /* Preview Content */ = {
			isa = PBXGroup;
			children = (
				CAFE000000000000000013B0 /* Preview Assets.xcassets */,
			);
			path = "Preview Content";
			sourceTree = "<group>";
		};
```

Add immediately after it (before `CAFE0000000000000000C020`):

```
		CAFE000000000000000020C0 /* SFTransitWatch */ = {
			isa = PBXGroup;
			children = (
				CAFE000000000000000020B0 /* SFTransitWatchApp.swift */,
				CAFE000000000000000020B1 /* ContentView.swift */,
				CAFE000000000000000020B2 /* BusStopListView.swift */,
				CAFE000000000000000020B3 /* BusArrivalView.swift */,
				CAFE000000000000000020B4 /* LocationManager.swift */,
				CAFE000000000000000020B5 /* TransitAPI.swift */,
				CAFE000000000000000020B6 /* BusStop.swift */,
				CAFE000000000000000020B7 /* BusArrival.swift */,
				CAFE000000000000000020B8 /* FavoritesManager.swift */,
				CAFE000000000000000020B9 /* SettingsView.swift */,
				CAFE000000000000000020BA /* SiriManager.swift */,
				CAFE000000000000000020BB /* SiriShortcutsView.swift */,
				CAFE000000000000000020BC /* Assets.xcassets */,
				CAFE000000000000000020BE /* Info.plist */,
				CAFE000000000000000020C1 /* Preview Content */,
			);
			path = SFTransitWatch;
			sourceTree = "<group>";
		};
		CAFE000000000000000020C1 /* Preview Content */ = {
			isa = PBXGroup;
			children = (
				CAFE000000000000000020BD /* Preview Assets.xcassets */,
			);
			path = "SFTransitWatch/Preview Content";
			sourceTree = "<group>";
		};
```

Then find the main group:

```
		CAFE000000000000000018A0 = {
			isa = PBXGroup;
			children = (
				CAFE0000000000000000T020 /* SFTransitWatchTests */,
				CAFE0000000000000000C020 /* SFTransitWatch Complication */,
				CAFE000000000000000018C0 /* SFTransitWatch Watch App */,
				CAFE000000000000000018D0 /* Products */,
			);
			sourceTree = "<group>";
		};
```

Replace its `children` to include the new iOS group:

```
		CAFE000000000000000018A0 = {
			isa = PBXGroup;
			children = (
				CAFE000000000000000020C0 /* SFTransitWatch */,
				CAFE0000000000000000T020 /* SFTransitWatchTests */,
				CAFE0000000000000000C020 /* SFTransitWatch Complication */,
				CAFE000000000000000018C0 /* SFTransitWatch Watch App */,
				CAFE000000000000000018D0 /* Products */,
			);
			sourceTree = "<group>";
		};
```

Also add the iOS app product to the Products group. Find:

```
		CAFE000000000000000018D0 /* Products */ = {
			isa = PBXGroup;
			children = (
				CAFE0000000000000000T010 /* SFTransitWatchTests.xctest */,
				CAFE0000000000000000C010 /* SFTransitWatch Complication.appex */,
				CAFE000000000000000016A0 /* SFTransitWatch Watch App.app */,
			);
			name = Products;
			sourceTree = "<group>";
		};
```

Replace with:

```
		CAFE000000000000000018D0 /* Products */ = {
			isa = PBXGroup;
			children = (
				CAFE0000000000000000T010 /* SFTransitWatchTests.xctest */,
				CAFE0000000000000000C010 /* SFTransitWatch Complication.appex */,
				CAFE000000000000000016A0 /* SFTransitWatch Watch App.app */,
				CAFE000000000000000020BF /* SFTransitWatch.app */,
			);
			name = Products;
			sourceTree = "<group>";
		};
```

- [ ] **Step 5: Add iOS PBXSourcesBuildPhase, PBXResourcesBuildPhase, PBXFrameworksBuildPhase, PBXCopyFilesBuildPhase**

Find the existing watch sources phase:

```
		CAFE000000000000000001AC /* Sources */ = {
			isa = PBXSourcesBuildPhase;
```

Add immediately after the closing `};` of that phase (and before `/* End PBXSourcesBuildPhase section */`):

```
		CAFE000000000000000020D0 /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				CAFE000000000000000020A0 /* SFTransitWatchApp.swift in Sources */,
				CAFE000000000000000020A1 /* ContentView.swift in Sources */,
				CAFE000000000000000020A2 /* BusStopListView.swift in Sources */,
				CAFE000000000000000020A3 /* BusArrivalView.swift in Sources */,
				CAFE000000000000000020A4 /* LocationManager.swift in Sources */,
				CAFE000000000000000020A5 /* TransitAPI.swift in Sources */,
				CAFE000000000000000020A6 /* BusStop.swift in Sources */,
				CAFE000000000000000020A7 /* BusArrival.swift in Sources */,
				CAFE000000000000000020A8 /* FavoritesManager.swift in Sources */,
				CAFE000000000000000020A9 /* SettingsView.swift in Sources */,
				CAFE000000000000000020AA /* SiriManager.swift in Sources */,
				CAFE000000000000000020AB /* SiriShortcutsView.swift in Sources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
```

Find the watch resources phase and add after it (before `/* End PBXResourcesBuildPhase section */`):

```
		CAFE000000000000000020D1 /* Resources */ = {
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				CAFE000000000000000020AC /* Assets.xcassets in Resources */,
				CAFE000000000000000020AD /* Preview Assets.xcassets in Resources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
```

Find the watch frameworks phase:

```
		CAFE000000000000000017A0 /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
```

Add after it (before `/* End PBXFrameworksBuildPhase section */`):

```
		CAFE000000000000000020D2 /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
```

The PBXCopyFilesBuildPhase section may not exist yet. After the frameworks section block ends, before `/* Begin PBXGroup section */`, add a new section:

```
/* Begin PBXCopyFilesBuildPhase section */
		CAFE000000000000000020D3 /* Embed Watch Content */ = {
			isa = PBXCopyFilesBuildPhase;
			buildActionMask = 2147483647;
			dstPath = "$(CONTENTS_FOLDER_PATH)/Watch";
			dstSubfolderSpec = 16;
			files = (
				CAFE000000000000000020AE /* SFTransitWatch Watch App.app in Embed Watch Content */,
			);
			name = "Embed Watch Content";
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXCopyFilesBuildPhase section */

```

- [ ] **Step 6: Add PBXContainerItemProxy and PBXTargetDependency for iOS → watch**

Add a new section block after the Copy Files section:

```
/* Begin PBXContainerItemProxy section */
		CAFE000000000000000020D4 /* PBXContainerItemProxy */ = {
			isa = PBXContainerItemProxy;
			containerPortal = CAFE000000000000000000B7 /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = CAFE000000000000000001AA;
			remoteInfo = "SFTransitWatch Watch App";
		};
/* End PBXContainerItemProxy section */

/* Begin PBXTargetDependency section */
		CAFE000000000000000020D5 /* PBXTargetDependency */ = {
			isa = PBXTargetDependency;
			target = CAFE000000000000000001AA /* SFTransitWatch Watch App */;
			targetProxy = CAFE000000000000000020D4 /* PBXContainerItemProxy */;
		};
/* End PBXTargetDependency section */

```

- [ ] **Step 7: Add iOS PBXNativeTarget and register in PBXProject**

Find the existing `PBXNativeTarget section`:

```
/* Begin PBXNativeTarget section */
		CAFE000000000000000001AA /* SFTransitWatch Watch App */ = {
			...
		};
/* End PBXNativeTarget section */
```

Add after the watch target's `};` (still inside the section):

```
		CAFE000000000000000020E0 /* SFTransitWatch */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = CAFE000000000000000020E1 /* Build configuration list for PBXNativeTarget "SFTransitWatch" */;
			buildPhases = (
				CAFE000000000000000020D0 /* Sources */,
				CAFE000000000000000020D2 /* Frameworks */,
				CAFE000000000000000020D1 /* Resources */,
				CAFE000000000000000020D3 /* Embed Watch Content */,
			);
			buildRules = (
			);
			dependencies = (
				CAFE000000000000000020D5 /* PBXTargetDependency */,
			);
			name = SFTransitWatch;
			productName = SFTransitWatch;
			productReference = CAFE000000000000000020BF /* SFTransitWatch.app */;
			productType = "com.apple.product-type.application";
		};
```

Then update the PBXProject's `targets` array. Find:

```
			targets = (
				CAFE000000000000000001AA /* SFTransitWatch Watch App */,
			);
```

Replace with:

```
			targets = (
				CAFE000000000000000020E0 /* SFTransitWatch */,
				CAFE000000000000000001AA /* SFTransitWatch Watch App */,
			);
```

Also update `TargetAttributes`. Find:

```
				TargetAttributes = {
					CAFE000000000000000001AA = {
						CreatedOnToolsVersion = 15.0;
					};
				};
```

Replace with:

```
				TargetAttributes = {
					CAFE000000000000000001AA = {
						CreatedOnToolsVersion = 15.0;
					};
					CAFE000000000000000020E0 = {
						CreatedOnToolsVersion = 16.4;
					};
				};
```

- [ ] **Step 8: Add iOS XCBuildConfiguration entries (Debug + Release)**

Find:

```
/* End XCBuildConfiguration section */
```

Insert immediately before it:

```
		CAFE000000000000000020F0 /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				DEVELOPMENT_ASSET_PATHS = "\"SFTransitWatch/Preview Content\"";
				DEVELOPMENT_TEAM = 7W4U5RR9QZ;
				ENABLE_PREVIEWS = YES;
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = "SFTransitWatch/Info.plist";
				INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;
				INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents = YES;
				INFOPLIST_KEY_UILaunchScreen_Generation = YES;
				INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad = "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
				INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
				IPHONEOS_DEPLOYMENT_TARGET = 17.0;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
				);
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = org.larner.SFTransitWatch;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SDKROOT = iphoneos;
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = "1,2";
			};
			name = Debug;
		};
		CAFE000000000000000020F1 /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				DEVELOPMENT_ASSET_PATHS = "\"SFTransitWatch/Preview Content\"";
				DEVELOPMENT_TEAM = 7W4U5RR9QZ;
				ENABLE_PREVIEWS = YES;
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = "SFTransitWatch/Info.plist";
				INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;
				INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents = YES;
				INFOPLIST_KEY_UILaunchScreen_Generation = YES;
				INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad = "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
				INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
				IPHONEOS_DEPLOYMENT_TARGET = 17.0;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
				);
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = org.larner.SFTransitWatch;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SDKROOT = iphoneos;
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = "1,2";
			};
			name = Release;
		};
```

- [ ] **Step 9: Add iOS XCConfigurationList**

Find:

```
/* End XCConfigurationList section */
```

Insert immediately before it:

```
		CAFE000000000000000020E1 /* Build configuration list for PBXNativeTarget "SFTransitWatch" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				CAFE000000000000000020F0 /* Debug */,
				CAFE000000000000000020F1 /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
```

- [ ] **Step 10: Verify pbxproj parses**

Run: `xcodebuild -list -project SFTransitWatch.xcodeproj`
Expected output now includes `SFTransitWatch` in the Targets list and an `SFTransitWatch` scheme (Xcode auto-creates schemes for new targets on first list/build).

If parsing fails (Xcode prints an error like "The project … cannot be opened because the project file cannot be parsed"), restore the backup with `cp SFTransitWatch.xcodeproj/project.pbxproj.bak SFTransitWatch.xcodeproj/project.pbxproj` and re-do steps 2–9 carefully.

- [ ] **Step 11: Delete the backup**

Run: `rm SFTransitWatch.xcodeproj/project.pbxproj.bak`

- [ ] **Step 12: Commit**

```bash
cd /Users/rustylarner/src/SFTransitWatch
git add SFTransitWatch.xcodeproj/project.pbxproj
git commit -m "Add iOS app target wired to existing SFTransitWatch sources"
```

---

## Task 4: Build the iOS target and fix compile issues

This is where any iOS-incompatible code in `SFTransitWatch/*.swift` surfaces. Expect to iterate on a few fixes.

**Files:** any iOS source files that fail to compile.

- [ ] **Step 1: Build the iOS target for simulator**

Run:
```bash
cd /Users/rustylarner/src/SFTransitWatch
xcodebuild -project SFTransitWatch.xcodeproj -scheme SFTransitWatch -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -50
```

- [ ] **Step 2: Read errors and fix iteratively**

Common issues to expect (fix only if they appear):

- **`Cannot find 'WKExtension' in scope`** in some file: gate with `#if os(watchOS)` or remove the watchOS-only branch from the iOS copy.
- **`'navigationBarTrailing' has been renamed`**: leave as-is on iOS (it's the iOS spelling); only the watchOS copy needs `.topBarTrailing`.
- **Missing `import UIKit`** anywhere using `UIApplication`, etc.
- **Asset catalog missing `AppIcon`**: `SFTransitWatch/Assets.xcassets` may not have an iOS-sized AppIcon. If the build fails on this, the easiest fix is `defaults write` style — but the simplest reliable fix is to open `SFTransitWatch/Assets.xcassets` in Xcode and add the iOS app icon variant. If running headless, set `ASSETCATALOG_COMPILER_APPICON_NAME = ""` temporarily to suppress the requirement.

For each error, edit the offending file with a minimal fix and re-run the build.

- [ ] **Step 3: Confirm build succeeds**

Run:
```bash
xcodebuild -project SFTransitWatch.xcodeproj -scheme SFTransitWatch -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -10
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit any source fixes**

```bash
cd /Users/rustylarner/src/SFTransitWatch
git add -A
git diff --cached --stat
# Confirm only SFTransitWatch/*.swift changes (no pbxproj changes)
git commit -m "Fix iOS-side compile issues for new iOS target"
```

If there were no source changes (only pbxproj from Task 3), skip the commit.

---

## Task 5: Verify the iOS archive includes the embedded watch app

**Files:** none (verification only).

- [ ] **Step 1: Archive the iOS scheme**

Run:
```bash
cd /Users/rustylarner/src/SFTransitWatch
rm -rf build/SFTransitWatch.xcarchive
xcodebuild -project SFTransitWatch.xcodeproj -scheme SFTransitWatch -destination 'generic/platform=iOS' -archivePath build/SFTransitWatch.xcarchive archive 2>&1 | tail -20
```
Expected: `** ARCHIVE SUCCEEDED **`.

- [ ] **Step 2: Verify the watch app is embedded inside the iOS .app**

Run:
```bash
ls "build/SFTransitWatch.xcarchive/Products/Applications/SFTransitWatch.app/Watch/"
```
Expected: a directory listing showing `SFTransitWatch Watch App.app`.

If the directory is missing, the embed phase didn't run. Inspect the archive log and re-check Task 3 Step 5's Copy Files entry.

- [ ] **Step 3: Verify bundle IDs in the archive**

Run:
```bash
/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "build/SFTransitWatch.xcarchive/Products/Applications/SFTransitWatch.app/Info.plist"
/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "build/SFTransitWatch.xcarchive/Products/Applications/SFTransitWatch.app/Watch/SFTransitWatch Watch App.app/Info.plist"
```
Expected:
```
org.larner.SFTransitWatch
org.larner.SFTransitWatch.watchkitapp
```

---

## Task 6: Add WatchSession.swift on watch side

**Files:**
- Create: `SFTransitWatch Watch App/WatchSession.swift`
- Modify: `SFTransitWatch.xcodeproj/project.pbxproj` (add file ref + build file + group entry + sources phase entry)

- [ ] **Step 1: Create the file**

Write `SFTransitWatch Watch App/WatchSession.swift`:

```swift
import Foundation
import WatchConnectivity

final class WatchSession: NSObject, WCSessionDelegate {
    static let shared = WatchSession()

    private override init() { super.init() }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()

        if !session.receivedApplicationContext.isEmpty {
            applyContext(session.receivedApplicationContext)
        }
    }

    private func applyContext(_ context: [String: Any]) {
        let key = (context["transitKey"] as? String) ?? ""
        UserDefaults.standard.set(key, forKey: "511_API_KEY_FROM_PHONE")
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error {
            print("WCSession activation error: \(error.localizedDescription)")
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        DispatchQueue.main.async {
            self.applyContext(applicationContext)
        }
    }
}
```

- [ ] **Step 2: Add file references to pbxproj**

Find `/* End PBXBuildFile section */` and insert before it:

```
		CAFE000000000000000020F8 /* WatchSession.swift in Sources */ = {isa = PBXBuildFile; fileRef = CAFE000000000000000020F9 /* WatchSession.swift */; };
```

Find `/* End PBXFileReference section */` and insert before it:

```
		CAFE000000000000000020F9 /* WatchSession.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = WatchSession.swift; sourceTree = "<group>"; };
```

Find the watch group `CAFE000000000000000018C0 /* SFTransitWatch Watch App */` children list and add `CAFE000000000000000020F9 /* WatchSession.swift */,` after `CAFE0000000000000000C004 /* ComplicationUpdater.swift */,`.

Find the watch sources phase `CAFE000000000000000001AC /* Sources */` files list and add `CAFE000000000000000020F8 /* WatchSession.swift in Sources */,` to the end.

- [ ] **Step 3: Verify watch builds**

Run:
```bash
xcodebuild -project SFTransitWatch.xcodeproj -scheme "SFTransitWatch Watch App" -destination 'generic/platform=watchOS' build 2>&1 | tail -10
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
cd /Users/rustylarner/src/SFTransitWatch
git add "SFTransitWatch Watch App/WatchSession.swift" SFTransitWatch.xcodeproj/project.pbxproj
git commit -m "Add WatchSession to receive transit key from phone"
```

---

## Task 7: Add PhoneSession.swift on iOS side

**Files:**
- Create: `SFTransitWatch/PhoneSession.swift`
- Modify: `SFTransitWatch.xcodeproj/project.pbxproj`

- [ ] **Step 1: Create the file**

Write `SFTransitWatch/PhoneSession.swift`:

```swift
import Foundation
import WatchConnectivity

final class PhoneSession: NSObject, WCSessionDelegate {
    static let shared = PhoneSession()

    private var didStartObserving = false

    private override init() { super.init() }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        startObservingDefaults()
    }

    func pushCurrentKey() {
        guard WCSession.default.activationState == .activated,
              WCSession.default.isPaired,
              WCSession.default.isWatchAppInstalled else { return }
        let key = UserDefaults.standard.string(forKey: "511_API_KEY") ?? ""
        do {
            try WCSession.default.updateApplicationContext(["transitKey": key])
        } catch {
            print("WCSession updateApplicationContext error: \(error.localizedDescription)")
        }
    }

    private func startObservingDefaults() {
        guard !didStartObserving else { return }
        didStartObserving = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(defaultsChanged),
            name: UserDefaults.didChangeNotification,
            object: nil
        )
    }

    @objc private func defaultsChanged() {
        pushCurrentKey()
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error {
            print("WCSession activation error: \(error.localizedDescription)")
            return
        }
        pushCurrentKey()
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        pushCurrentKey()
    }
}
```

- [ ] **Step 2: Add file references to pbxproj**

Find `/* End PBXBuildFile section */` and insert before it:

```
		CAFE000000000000000020FA /* PhoneSession.swift in Sources */ = {isa = PBXBuildFile; fileRef = CAFE000000000000000020FB /* PhoneSession.swift */; };
```

Find `/* End PBXFileReference section */` and insert before it:

```
		CAFE000000000000000020FB /* PhoneSession.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = PhoneSession.swift; sourceTree = "<group>"; };
```

Find the iOS group `CAFE000000000000000020C0 /* SFTransitWatch */` children list and add `CAFE000000000000000020FB /* PhoneSession.swift */,` after `CAFE000000000000000020BB /* SiriShortcutsView.swift */,`.

Find the iOS sources phase `CAFE000000000000000020D0 /* Sources */` files list and add `CAFE000000000000000020FA /* PhoneSession.swift in Sources */,` to the end.

- [ ] **Step 3: Verify iOS builds**

Run:
```bash
xcodebuild -project SFTransitWatch.xcodeproj -scheme SFTransitWatch -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -10
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
cd /Users/rustylarner/src/SFTransitWatch
git add SFTransitWatch/PhoneSession.swift SFTransitWatch.xcodeproj/project.pbxproj
git commit -m "Add PhoneSession to push transit key to watch"
```

---

## Task 8: Update TransitAPI key resolution on both sides

The `TransitAPI.swift` file is duplicated on disk in `SFTransitWatch/` and `SFTransitWatch Watch App/`. Both need the same change so the iOS copy compiles cleanly and the watch copy uses the phone-supplied key first.

**Files:**
- Modify: `SFTransitWatch Watch App/TransitAPI.swift:6-13`
- Modify: `SFTransitWatch/TransitAPI.swift` (same change at the same lines)

- [ ] **Step 1: Edit `SFTransitWatch Watch App/TransitAPI.swift`**

Find:

```swift
    private let baseURL = "https://api.511.org/transit"
    @AppStorage("511_API_KEY") private var storedAPIKey = ""
    
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private var apiKey: String {
        return storedAPIKey.isEmpty ? "YOUR_511_API_KEY" : storedAPIKey
    }
```

Replace with:

```swift
    private let baseURL = "https://api.511.org/transit"
    @AppStorage("511_API_KEY") private var storedAPIKey = ""
    @AppStorage("511_API_KEY_FROM_PHONE") private var phoneAPIKey = ""

    @Published var isLoading = false
    @Published var errorMessage: String?

    private var resolvedKey: String {
        return phoneAPIKey.isEmpty ? storedAPIKey : phoneAPIKey
    }

    private var hasUsableKey: Bool {
        return !phoneAPIKey.isEmpty || !storedAPIKey.isEmpty
    }

    private var apiKey: String {
        return resolvedKey.isEmpty ? "YOUR_511_API_KEY" : resolvedKey
    }
```

Then find every `guard !storedAPIKey.isEmpty else {` in this file (there are 3 occurrences: in `fetchArrivals`, `fetchNearbyStops`, and `fetchStop`) and replace each with `guard hasUsableKey else {`.

Also find the property `var isAPIKeyConfigured: Bool` and replace its body:

```swift
    var isAPIKeyConfigured: Bool {
        return !storedAPIKey.isEmpty
    }
```

with:

```swift
    var isAPIKeyConfigured: Bool {
        return hasUsableKey
    }
```

- [ ] **Step 2: Apply the same edits to `SFTransitWatch/TransitAPI.swift`**

Make the exact same changes in the iOS copy. Run a diff to confirm the two files differ only in places that were already different before this change:

Run: `diff "SFTransitWatch/TransitAPI.swift" "SFTransitWatch Watch App/TransitAPI.swift"`

Expected: only the pre-existing differences (if any). The new `phoneAPIKey`, `resolvedKey`, `hasUsableKey`, and `apiKey` getters should be identical.

- [ ] **Step 3: Build both targets**

Run:
```bash
xcodebuild -project SFTransitWatch.xcodeproj -scheme SFTransitWatch -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -5
xcodebuild -project SFTransitWatch.xcodeproj -scheme "SFTransitWatch Watch App" -destination 'generic/platform=watchOS' build 2>&1 | tail -5
```
Expected: both `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
cd /Users/rustylarner/src/SFTransitWatch
git add SFTransitWatch/TransitAPI.swift "SFTransitWatch Watch App/TransitAPI.swift"
git commit -m "Resolve transit API key from phone first, then local"
```

---

## Task 9: Activate WCSession on app launch

**Files:**
- Modify: `SFTransitWatch/SFTransitWatchApp.swift`
- Modify: `SFTransitWatch Watch App/SFTransitWatchApp.swift`

- [ ] **Step 1: Update iOS app entry point**

Replace `SFTransitWatch/SFTransitWatchApp.swift` with:

```swift
import SwiftUI

@main
struct SFTransitWatchApp: App {
    init() {
        PhoneSession.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

- [ ] **Step 2: Update watch app entry point**

Read the existing `SFTransitWatch Watch App/SFTransitWatchApp.swift` first to see its current structure. Add `WatchSession.shared.activate()` to its `init()` (create one if it doesn't exist).

Example (adjust to match existing structure — only add the `init` and the `activate()` call):

```swift
import SwiftUI

@main
struct SFTransitWatchApp: App {
    init() {
        WatchSession.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

If the existing file already has an `init()` body, just append the `WatchSession.shared.activate()` line inside it.

- [ ] **Step 3: Build both targets**

Run:
```bash
xcodebuild -project SFTransitWatch.xcodeproj -scheme SFTransitWatch -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -5
xcodebuild -project SFTransitWatch.xcodeproj -scheme "SFTransitWatch Watch App" -destination 'generic/platform=watchOS' build 2>&1 | tail -5
```
Expected: both `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
cd /Users/rustylarner/src/SFTransitWatch
git add SFTransitWatch/SFTransitWatchApp.swift "SFTransitWatch Watch App/SFTransitWatchApp.swift"
git commit -m "Activate WCSession on app launch (both sides)"
```

---

## Task 10: Final archive verification

**Files:** none (verification only).

- [ ] **Step 1: Archive the iOS scheme**

Run:
```bash
cd /Users/rustylarner/src/SFTransitWatch
rm -rf build/SFTransitWatch.xcarchive
xcodebuild -project SFTransitWatch.xcodeproj -scheme SFTransitWatch -destination 'generic/platform=iOS' -archivePath build/SFTransitWatch.xcarchive archive 2>&1 | tail -10
```
Expected: `** ARCHIVE SUCCEEDED **`.

- [ ] **Step 2: Inspect the archive structure**

Run:
```bash
find build/SFTransitWatch.xcarchive/Products/Applications -maxdepth 4 -type d
```
Expected:
```
build/SFTransitWatch.xcarchive/Products/Applications
build/SFTransitWatch.xcarchive/Products/Applications/SFTransitWatch.app
build/SFTransitWatch.xcarchive/Products/Applications/SFTransitWatch.app/Watch
build/SFTransitWatch.xcarchive/Products/Applications/SFTransitWatch.app/Watch/SFTransitWatch Watch App.app
```

- [ ] **Step 3: Confirm archive shows in Xcode Organizer**

Open Xcode → Window → Organizer → Archives. Expected: a new "SFTransitWatch" archive appears with Type "iOS App Archive" (not "watchOS App Archive").

- [ ] **Step 4: Confirm App Store Connect destination is offered**

In Organizer, select the new archive → click **Distribute App**. Expected: the destination chooser now shows **App Store Connect** as a destination icon (alongside or instead of Release Testing / Enterprise / Debugging / Custom).

If App Store Connect is still not shown, the manual App Store Connect setup steps from the spec (delete old record, register new bundle ID, create new app record) have not yet been completed. Refer to the spec § "App Store Connect changes" — those are out of scope for this code plan but blocking for upload.

---

## Done

After Task 10, the project archives as a paired iOS+watchOS app and the watch will use the phone's API key whenever it has been set on the phone. Manual App Store Connect setup (per the spec's § "App Store Connect changes") then enables the upload itself.
