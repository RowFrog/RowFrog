# 33. Screenshots cover every device, orientation, browser and scroll position

- Date: 2026-11-12
- Status: decided (owner, 23:19 CET, thread "Bug Fixes")
- Where: every thread that takes screenshots or compares screens; the Mac merge queue takes them; checklist in `docs/handbook.md` ("Screenshot matrix")

## Decision

Screenshots are taken for this matrix:

| Where | Combinations |
|---|---|
| iPhone app | portrait, landscape |
| iPad app | portrait, landscape; each with the club list (sidebar) shown and hidden |
| Website on a computer (PC/Mac) | Chrome and Safari, several window sizes (wide with the list beside the page, medium, narrow) |
| Website on an iPhone | Chrome and Safari, portrait and landscape |
| Website on an iPad | Chrome and Safari, portrait and landscape; each with the list shown and hidden |

Each at several scroll positions (top, middle, near the end), so app and website are compared at the same places. Light and dark, with a background picture (frosted and solid tiles) and without, and with the keyboard open where there is a text field, as before.

- The whole matrix: for every full comparison of app and website, and for changes that reach several or all screens.
- A part of it: for narrow tasks; the report says which part and why.
- A full app-and-website comparison also runs regularly, as a recurring task.

## Why

On 12 Nov several faults reached the owner first because shots covered only some layouts or one browser: the pinned table header let rows show through only in Safari, the iPad buttons sat at another height than the list's, and a long club name ran under the buttons.

## Notes

Chrome on iPhone and iPad draws pages with Apple's WebKit, like Safari; only its bars (and so the visible height) differ. It can't be installed in the Simulator, so Simulator Safari covers the engine and the visible height is checked by size. Desktop Safari is driven with `safaridriver` (Safari > Settings > Developer > Allow remote automation).
