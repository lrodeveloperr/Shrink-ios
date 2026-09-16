# App Review notes

No account or credentials are required. Camera access is optional; choose manual entry to test without a camera. No external hardware is required.

Start a shopping trip by choosing a supermarket. Scan a supported barcode or enter a product manually, then enter the current package amount and shelf price. A first saved check creates the baseline. Save a later check in the same product family to see a comparison.

The 426,044-product USDA catalogue, saved history, and comparison logic work without an internet connection. Internet is required for StoreKit product metadata and purchases, Google advertising, and the external policy and support pages.

To test an unknown barcode, enter a valid code that is not in the bundled catalogue and link it to any existing saved product family. History supports search, filters, edited decisions, deletion, and an eight-second undo. The Impact tab excludes zero-value chart points.

Banner removal is in Settings under Banner. Remove Banner is a non-consumable purchase with product ID `com.worksbienstudios.shrinkflationpricescanner.removeads`. Restore Purchase is in the same section. Core scanning, comparison, history, and impact features do not require the purchase.

The prepared TestFlight configuration uses Google's official sample ad identifiers. Sample-ad mode intentionally bypasses UMP and should show only sample ads. Invalid, unavailable, or offline ad states fall back to the WorksBien house banner. A production App Store build must use verified production advertising identifiers and matching UMP, ATT, privacy-manifest, and App Privacy configuration.

Availability is limited to the United States and Puerto Rico. The app interface supports English and Puerto Rico-aware Spanish. App Store Connect's Spanish Mexico locale is used only as the available Spanish metadata container.

