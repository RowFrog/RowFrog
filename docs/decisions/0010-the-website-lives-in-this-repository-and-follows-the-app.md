# 10. The website lives in this repository and follows the app

- Date: 2026-10-25
- Status: decided (owner)
- Where: `web/`, `scripts/build_web.py`

## Decision

The website is plain JavaScript in `web/`, built by `scripts/build_web.py` (German taken from the app's `Localization.swift`) and served by Cloudflare Pages. From 2026-10-26, every app feature, bug fix or change is carried over to the website. It stays password-locked and hidden from search engines until it goes public.

## Why

People without an iPhone can use it, and app and website share one repository and the German texts.

## Turned down

The other set-ups offered at the time.
