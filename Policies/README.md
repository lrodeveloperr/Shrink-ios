# Shrinkflation Price Scanner policy source

These policies describe iOS version 1.0 build 8 for the United States and Puerto Rico. The English master and Puerto Rico Spanish localization were assembled from the Global App Policy Lego System and checked against the shipped source.

## Activated policy blocks

- Controller, scope, effective date, changes and contact
- Local functional data and device backup
- Camera permission and on-device recognition
- Google advertising, consent choices and App Tracking Transparency
- StoreKit non-consumable purchase and restore
- Support communications, retention, legal disclosures and user choices
- Offline core behavior and third-party online services
- General-audience and child-directed-use clarification

## Product facts

- Bundle ID: `com.worksbienstudios.shrinkflationpricescanner`
- Version/build: `1.0 (8)`
- Regions: United States and Puerto Rico
- Languages: English and Puerto Rico-aware Spanish
- Accounts: none
- Functional storage: local SQLite and UserDefaults in the app container
- Catalogue: bundled April 30, 2026 USDA FoodData Central branded-food data; 426,044 selected US products
- Runtime product API: none
- Camera: optional barcode and shelf-price scanning; manual entry remains available
- Advertising: Google Mobile Ads in production configuration; Google sample ads in the current TestFlight configuration; WorksBien house banner on invalid, unavailable or offline ad states
- Purchase: StoreKit 2 non-consumable `com.worksbienstudios.shrinkflationpricescanner.removeads`
- Support: `https://worksbienstudios.com/customerservice`

## Public routes

- English privacy: `https://worksbienstudios.com/apps/shrinkflation-price-scanner/en/privacy/`
- English terms: `https://worksbienstudios.com/apps/shrinkflation-price-scanner/en/terms/`
- Spanish privacy: `https://worksbienstudios.com/apps/shrinkflation-price-scanner/es-419/privacy/`
- Spanish terms: `https://worksbienstudios.com/apps/shrinkflation-price-scanner/es-419/terms/`

The app builds these routes from `AppLinks` and the active in-app language. French-Canadian routes are intentionally retired.

