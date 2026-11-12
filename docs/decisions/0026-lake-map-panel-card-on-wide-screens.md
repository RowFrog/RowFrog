# 26. The lake map's panel is a card at the bottom left on wide screens

- Date: 2026-11-12
- Status: decided (owner, 15:23 CET)
- Where: app `LakePanelLayout` and `lakePanelChrome` in `ios/RowFrog/LakePanelCard.swift`, used by `LakeMapScreen`; the website copies the numbers
- Mock-ups: https://claude.ai/artifact/6rU4o98GceeKUskyQJAji2 (options A–C)

## Decision

Option B. On every screen at least 600 pt wide inside its safe area (iPad upright and sideways, iPhone sideways, Mac), the lake map's panel is a card at the bottom left, as in Apple Maps: 360 pt wide, 16 pt in from the left and bottom, all corners rounded (22 pt). The legend chip sits beside it, and the layer buttons stay at the right. The lake fits into the map beside the card. An upright iPhone keeps the full-width panel. The app leads and the website copies the numbers.

## Why

The map keeps its full width on big screens, as in Apple Maps. A: a full-width panel on iPad hides a strip of a sideways screen. C: the website's right column made the app and the website differ.
