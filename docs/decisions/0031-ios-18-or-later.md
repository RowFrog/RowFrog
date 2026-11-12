# 31. iOS 18 or later

- Date: 2026-11-12
- Status: decided (owner)
- Where: `ios/project.yml` (`deploymentTarget`), the former `#available(iOS 18…)` checks in `LocationListView.swift`, `LocationPageView.swift`, `SafetyNotice.swift` and `LaunchPointMapCard.swift`

## Decision

The app needs iOS 18 or later (was iOS 17). The iOS 17 fallbacks are gone: everyone gets the Apple Maps place card in the Location sheet, the shrinking list title and the plain safety-notice stack.

## Why

Every iPhone that runs iOS 17 can also run iOS 18, so no device is left out. iOS 17 and older were about 2 % of iPhones at the end of October 2026 (TelemetryDeck: iOS 26 55 %, iOS 27 36 %, iOS 18 6.6 %). iOS 18 brings TipKit's ordered tip groups for the tip pacing, the place card for everyone, and one iOS version less to test.

## Turned down

Staying on iOS 17 (the pacing can be built without tip groups, but the place card and the extra test version stay). iOS 26 or later (would drop the iPhone XS and XR, and about 7 % of iPhones still on iOS 18).
