# Shrinkflation Price Scanner — iOS V1

Native SwiftUI utility for answering: “Has this product quietly become worse value?” without an account or backend.

## Locked V1

- English, Latin American Spanish (`es-419`, including Puerto Rico), and Canadian French (`fr-CA`)
- iPhone and iPad, iOS 17+
- United States (including Puerto Rico) and Canada
- UPC-A, UPC-E, EAN-13, EAN-8 and GTIN-14 support
- Bundled read-only catalogue; unknown barcodes are learned locally
- Supermarket-scoped shopping trips; every scan inherits supermarket and date
- Shopper-approved Shrink Radar home: store context, dominant scan action, verified caught-today counter and latest result
- Scan → confirm amount and unit → automatic comparison; price stays optional
- Optional on-device shelf-price text scanning
- Successful first-sighting and captured-draft states for unknown barcodes
- Searchable/filterable History with edit, delete and Undo
- Native Swift Charts Scorecard using honest Bought/Skipped/Switched decisions
- Local history in SQLite; no cloud analytics or user account
- Permanent anchored adaptive AdMob banner
- One-time `Remove Banner Forever` StoreKit purchase
- Production house-banner fallback whenever AdMob is unavailable or has no fill
- Public Privacy Policy and Terms of Use in English, Canadian French and Latin American Spanish; Settings opens the matching language automatically

## Open and run

1. Open `ShrinkflationPriceScanner.xcodeproj` in Xcode 16 or newer.
2. Choose the `ShrinkflationPriceScanner` scheme.
3. Select your development team under Signing & Capabilities.
4. Run on a physical device for barcode and shelf-label scanning.

The project uses Swift Package Manager for Google Mobile Ads 12.12+ and Google User Messaging Platform 3+.

## Required release configuration

TestFlight validation builds intentionally retain Google's official sample application
and banner identifiers in both target configurations. This keeps all pre-release ad
traffic in Google's test environment. Before the public App Store archive, replace:

- `INFOPLIST_KEY_GADApplicationIdentifier`
- `INFOPLIST_KEY_GADBannerAdUnitID`

Register this non-consumable in App Store Connect:

```text
com.worksbienstudios.shrinkflationpricescanner.removeads
```

Configure the matching AdMob privacy messages and verify the current SKAdNetwork list before the public App Store archive. Never ship the Google sample identifiers to App Store production.

Public policy URLs:

- Privacy: `https://worksbienstudios.com/apps/shrinkflation-price-scanner/en/privacy/`
- Terms: `https://worksbienstudios.com/apps/shrinkflation-price-scanner/en/terms/`

The app routes French devices to `/fr-ca/` and Spanish devices to `/es-419/` automatically. Use the English privacy URL in App Store Connect; the public page includes a language switcher.

## Build the production barcode catalogue

The repository contains a tiny six-row demo catalogue so the complete product flow works immediately. Replace it before release with a filtered US/Canada export:

```bash
python3 Scripts/build_catalogue.py /path/to/openfoodfacts-products.csv \
  --output App/Resources/catalogue.sqlite3 \
  --max-records 500000
```

The importer:

- verifies GTIN check digits;
- normalizes identifiers to GTIN-14;
- keeps products tagged for the US or Canada;
- requires a product name and parseable package quantity;
- ranks repeat-purchase shrinkflation categories, completeness, scan activity and recency;
- stores only product identity, quantity, category, market and update date;
- removes images, nutrition, ingredients and prices.

The CSV reader accepts comma-, semicolon- or tab-delimited Open Food Facts-style exports. The key fields are `code`, `product_name_en` (or `product_name`), `product_name_es`, `product_name_fr`, `brands`, `quantity`, `countries_tags`, `categories_tags`, `last_modified_t` and optionally `unique_scans_n`.

The barcode/GTIN and product-family identity are language-neutral. The app displays an official Spanish or French product name only when the source supplies it, otherwise it preserves the English/original package name. Brand and supermarket names are never machine-translated.

For production data, preserve Open Food Facts attribution and comply with the Open Database License. Keep the bundled source catalogue logically separate from the user's private observations, as implemented here.

## Core data model

`catalogue.sqlite3` is immutable inside the app bundle. Device-created information is stored separately under Application Support:

- `learned_products`: unknown or corrected barcode identities
- `observations`: append-only sightings with trip, supermarket, date, amount, unit, optional price context, decision and purchase quantity

The `family_id` connects a replacement barcode to an existing product. When a scan is unknown, **Same product, new barcode** presents recent products as one-tap link candidates.

Package amount can be compared across supermarkets. Dollar impact is intentionally scored only when supermarket, currency, channel, price type and any recorded branch are compatible. USD and CAD totals are always separate.

The production interface is designed to be hosted by the approved `Swift-UI-shell-ios` shell, which owns navigation, large-title collapse, system sheets, safe areas, transitions and phone/iPad adaptation. The selected Shrink Radar home is built entirely with native SwiftUI shapes, SF Symbols, buttons and system materials. App-owned Scan, History and Scorecard surfaces follow Apple Food Truck sample patterns for compact cards, data summaries, empty states and Swift Charts, while the Grocery Benefits digit-buffer keypad remains the price-entry pattern. No second navigation shell or third-party UI framework is included.

## Verification

The XCTest target covers:

- UPC/EAN/GTIN normalization and check-digit rejection
- UPC-E expansion
- shrinkflation and unit-price calculations
- cross-store package evidence without false monetary scoring
- optional-price package-change detection
- incompatible-unit protection
- shelf-price extraction

Run `python3 Scripts/check_localizations.py` and `python3 Scripts/validate_release.py` before every localized release, then complete every item in `LOCALIZATION_CHECKLIST.md` on iPhone and iPad.

The TestFlight upload workflow deliberately performs no unit tests and no simulator
tests. It runs the two static release checks, compiles a generic Release archive,
verifies that the official Google sample banner identifiers are present, signs the
archive for App Store distribution, validates the IPA, and uploads it to TestFlight.

This Linux workspace does not contain Xcode or the Swift toolchain, so the final Apple SDK compile and camera run must be performed on a Mac. The project, resources, package references and shared scheme are included.
