# 11. The newest Xcode decides a merge

- Date: 2026-10-30
- Status: decided (owner)
- Where: `.github/workflows/ci.yml`

## Decision

CI builds and tests on several Xcode versions side by side; the job with the newest Xcode decides whether a change may merge, the others only report.

## Why

The widest coverage, while the build that matters most (newest SDK, newest iOS on the owner's phone) decides. From April 2027 App Store uploads need the iOS 27 SDK.

## Turned down

Only the oldest supported Xcode; all jobs blocking.
