# Okkle

Okkle is now a native SwiftUI iOS app for UK courier tax tracking.

The iOS app lives in `ios/Okkle.xcodeproj` and does not require Expo, Metro, EAS, npm, Pods, or a JavaScript bundle to run.

## Open The App

```bash
open ios/Okkle.xcodeproj
```

Or double-click:

```bash
./xcode.command
```

In Xcode, select the `Okkle` scheme, choose an iPhone simulator or device, and press Run.

## Build From Terminal

```bash
xcodebuild \
  -project ios/Okkle.xcodeproj \
  -scheme Okkle \
  -configuration Debug \
  -sdk iphonesimulator \
  -derivedDataPath /tmp/okkle-swift-derived \
  build
```

## TestFlight

Use Xcode:

1. Open `ios/Okkle.xcodeproj`.
2. Select `Any iOS Device`.
3. Product -> Archive.
4. Distribute App -> App Store Connect.

This does not use Expo EAS build credits.

## Current Native Features

- Home dashboard for mileage, earnings, tax saved, progress, and recent activity.
- One-at-a-time logging for income, expenses, and mileage.
- Native camera/photo receipt attachment.
- GPS trip tracking with native `CLLocationManager`.
- Records and history.
- Insights, heat map, best hours, and tax dates.
- Tax estimate and export/share flows.
- Local on-device persistence using `UserDefaults` snapshots.

## Versioning

The app version is controlled by the Xcode target `MARKETING_VERSION`.

For each PR, bump:

- `MARKETING_VERSION`
- `CFBundleVersion` / build number when preparing an App Store or TestFlight archive

Current migration version: `0.4.2`.
