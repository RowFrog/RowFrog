# 19. German texts in a String Catalog

- Date: 2026-11-12
- Status: decided (owner); built later, together with the formatting pass, once the merge queue is empty
- Where: `ios/RowFrog/Localization.swift` today, `ios/RowFrog/Localizable.xcstrings` after the change

## Decision

The app's German texts move from the Swift dictionary in `Localization.swift` to Apple's String Catalog. The `tr()` calls stay as they are; the website's German keeps coming from the same texts.

## Why

Xcode shows missing and unused texts in the catalog itself, and plural forms become possible later.

## Turned down

Doing it right away (it touches the file every open app change also touches, so it waits for an empty queue).
