# 34. Build numbers from the commit count, commit in About

- Date: 2026-11-12
- Status: decided (owner)
- Where: `ios/BuildNumber.xcconfig`, `scripts/build_number.sh`, `ios/RowFrog/BuildInfo.swift` (Settings > About), `ios/project.yml` (`configFiles`, `RWCommit`, the "Log device builds" step), `scripts/build_web.py` (website footer and About), `scripts/local/deploy-web.sh`

## Decision

Every build carries a build number and the commit it was built from. The build number is the commit count of the history up to the built commit (`git rev-list --count`), the commit its first seven characters. The version stays 0.1.0 until a real release. The app and the widget share the build number.

The app shows "Version 0.1.0 (723) · 22a69ce" in Settings > About (the same in German). The website copies it: the same line in its Settings > About and "Build 723 · 22a69ce" in the footer. `scripts/build_number.sh` stamps the numbers (run by `update.sh` after a pull, and before screenshots); a build that was never stamped says "(1) · dev". Each device build from Xcode adds a line to `log/device-builds.log` on the Mac.

## Why

The owner asked on 12 Nov 2026 to keep track of builds more easily (merge thread, "Yes, go ahead" 21:06 CET). Until now every build said 0.1.0 (1), so nobody could tell which commit was on the iPhone, the iPad or rowfrog.com. The commit count only goes up along main and needs nothing stored; the sha7 finds the exact commit.

## Turned down

Raising the version for every build (it is for releases). A counter kept in a file (needs a commit per build and clashes between threads). Only command-line overrides for xcodebuild (device builds from Xcode would still say (1)).
