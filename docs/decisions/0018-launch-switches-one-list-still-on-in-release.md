# 18. Launch switches: one list, still on in Release

- Date: 2026-11-12
- Status: decided (owner)
- Where: `ios/RowFrog/DefaultsKey.swift`, `docs/handbook.md`

## Decision

Every screenshot and test switch the app reads is named in `DefaultsKey.swift` with a one-line note. They stay available in Release builds for now.

## Why

One list lets people and agents find every switch; Release builds are what screenshots and the owner's phone run.

## Turned down

Putting the switches behind `#if DEBUG` (can be decided later, before the App Store).
