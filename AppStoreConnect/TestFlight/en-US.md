# TestFlight metadata English US

Status: prepared only. Do not upload, select a build, invite testers, or submit for Beta App Review yet.

## Beta description

Shrinkflation Price Scanner helps shoppers in the United States and Puerto Rico compare package amounts and unit costs over time. Scan a supported barcode or enter a product manually, record today's package amount and shelf price, then compare it with later trips. The beta includes a bundled USDA branded-food catalogue, searchable local history, impact estimates, English and Puerto Rico-aware Spanish, a fixed banner, and an optional one-time banner-removal purchase. No account is required.

## What to test

Verify US/PR supermarket ordering from the device region; barcode scanning and manual entry; UPC-E and 8-digit format selection; unknown-barcode linking; package and price validation; first-check baseline and later comparison; History search, filters, edit, delete, and eight-second undo; Impact math and chart scaling; airplane-mode catalogue and history behavior; Google sample-ad loading and clean failure with no replacement banner; banner purchase and restore in the StoreKit sandbox; privacy, terms, and support links; VoiceOver, Larger Text, dark mode, portrait, and landscape.

## Beta App Review notes

No account or credentials are required. Camera access is optional; choose manual entry to test without a camera. Start by choosing a supermarket. A first saved check creates a baseline; use the same product family on a later trip to see a comparison. The built-in catalogue and local history can be tested offline. Internet is needed for StoreKit metadata, policy and support pages, and ads. Banner removal is in Settings under Banner; Restore Purchase is in the same section. This beta uses Google sample ad identifiers, so UMP is intentionally bypassed and only sample ads should appear. No external hardware is required.

## Owner-supplied fields still required

- TestFlight feedback email
- App Review contact name, phone, and email
- Tester groups and invitation policy
