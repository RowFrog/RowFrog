# NNNN. Screenshots cover every device, orientation, browser and scroll position

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

- Automatic geometry checks (alignment, overlap, inside the window) run on every merge, in every combination.
- The whole set of pictures: weekly (recurring task) and before each release, and for every full comparison of app and website.
- A single change: the screens it touches, in every combination; narrowed by screen, never by device or browser.
- Chrome on iPhone and iPad is not shot on its own: it draws with Apple's WebKit like Safari, so Safari stands in, and only its smaller visible height is checked (Chromium at that size). On a computer Chrome and Safari both stay.

(Owner, 23:19 CET; the four lines above as agreed at 23:22 CET.)

## Why

On 12 Nov several faults reached the owner first because shots covered only some layouts or one browser: the pinned table header let rows show through only in Safari, the iPad buttons sat at another height than the list's, and a long club name ran under the buttons.

## Notes

Chrome on iPhone and iPad draws pages with Apple's WebKit, like Safari; only its bars (and so the visible height) differ. It can't be installed in the Simulator, so Simulator Safari covers the engine and the visible height is checked by size. Desktop Safari is driven with `safaridriver` (Safari > Settings > Developer > Allow remote automation).
