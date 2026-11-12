# 20. HSTS for one year right away

- Date: 2026-11-12
- Status: decided (owner); live since 2026-11-12 10:33 CET
- Where: `web/functions/_middleware.js`

## Decision

The website sends `Strict-Transport-Security: max-age=31536000`: browsers that have seen it open rowfrog.com only over HTTPS for a year.

## Why

The site is HTTPS-only anyway; a year is the usual value.

## Turned down

Starting with one day and raising it after a check (safer to undo, since browsers keep the header for its full time).
