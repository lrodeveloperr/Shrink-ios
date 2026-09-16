# Shrinkflation Price Scanner — iOS 1.0 (8)

Native SwiftUI utility for detecting package-size and unit-price changes without an account, cloud database, or runtime product API.

## Locked release scope

- United States and Puerto Rico only; region is detected automatically.
- English and Puerto Rico-aware Latin American Spanish (`es-419`) only.
- Money is shown with `$`; all saved monetary values use the single USD code internally.
- Offline April 30, 2026 USDA FoodData Central branded-food catalogue.
- Exact source barcode, raw USDA description, source dates, provenance, and stable product-family identity are retained.
- Shoppers enter the current package quantity/unit and shelf price because those values change.
- UPC-A, UPC-E, EAN-8, EAN-13, GTIN-14, Code 128, ITF-14, and GS1 DataBar scanning.
- Unknown barcodes can be linked to any saved product family.
- Searchable, uncapped local history with deletion and an eight-second undo.
- StoreKit 2 non-consumable `com.worksbienstudios.shrinkflationpricescanner.removeads`.
- A reserved banner area sits below app content with an 8-point navigation separation. Paid users receive no banner gap.

## Open and run

1. Open `ShrinkflationPriceScanner.xcodeproj` in Xcode 16 or newer.
2. Choose the `ShrinkflationPriceScanner` scheme and a signing team.
3. Use a physical iPhone or iPad for camera scanning.

The project uses Swift Package Manager for Google Mobile Ads and Google User Messaging Platform. Google's official sample identifiers are retained for pre-release validation. Sample-ad mode bypasses UMP entirely; invalid advertising configuration fails safely to the WorksBien house banner. Replace sample identifiers only for an approved production App Store archive.

## Policies and App Store materials

- `Policies/` contains the controlled US English and Puerto Rico Spanish privacy and terms sources.
- `WebsitePolicies/` is generated from those sources for the public routes already used by the app.
- `AppStoreConnect/` contains the finalized non-media listing, in-app-purchase localizations, privacy answer pack, review notes, and bilingual TestFlight material.
- TestFlight material is documentation only. It is not connected to App Store Connect, does not select a build, and cannot upload or submit anything.

## Build the official offline catalogue

Download `FoodData_Central_branded_food_csv_2026-04-30.zip` from USDA FoodData Central, then run:

```bash
python3 Scripts/build_catalogue.py /path/to/FoodData_Central_branded_food_csv_2026-04-30.zip \
  --output App/Resources/catalogue.sqlite3
```

The deterministic importer validates the exact official release, selects the approved 426,044 US/PR products, normalizes supported identifiers without losing their source representation, creates stable product families, cleans display names separately from raw descriptions, and emits the frozen source-gated correction and semantic-expression audits. It never imports package quantity or retail price as current shopper data.

The semantic audit contains exactly 152 reviewed identities and gates each one by GTIN, raw-source SHA-256, reason, and exact display name. The validator separately protects 263 category-identified seafood grades plus 19 reviewed seafood identities with incomplete source categories and 16 source-gated “and up” grades, checks duplicate-source output consistency, rejects damaged `/up` residue, and prevents 26 mixed-fraction package weights from leaving dangling numbers. For a display-only rebuild from an already validated catalogue, use `Scripts/rebuild_catalogue_display.py`; it refuses any input whose locked non-display identity differs.

`catalogue.sqlite3` is immutable in the app bundle. Device-created information is stored separately under Application Support in `learned_products` and `observations`.

## Release verification

This reconstruction is code-only. The authorized local checks are:

```bash
python3 Scripts/check_localizations.py
python3 -m py_compile Scripts/build_catalogue.py Scripts/rebuild_catalogue_display.py Scripts/check_localizations.py Scripts/validate_catalogue.py Scripts/validate_release.py
python3 Scripts/validate_release.py --sample-ads
python3 Scripts/validate_catalogue.py App/Resources/catalogue.sqlite3 --database-only
git diff --check
```

`--database-only` must be explicit and validates the catalogue identity plus every source-gated display output. For the full independent source comparison, pass the locked USDA archive with `--archive` instead.

The catalogue builder and release validator also run read-only SQLite integrity, coverage, barcode, provenance, duplicate, correction, and semantic-expression audits. Xcode builds, Swift tests, simulators, devices, and TestFlight uploads remain explicit release gates.

The completed full-archive comparison and deterministic rebuild evidence is recorded in `USDA_VALIDATION_2026-04-30.md`.

The TestFlight workflow uploads only after an exact manual confirmation or a deliberate `[upload-shrink-testflight]` commit marker. The reconstructed final commit must not contain that marker.
