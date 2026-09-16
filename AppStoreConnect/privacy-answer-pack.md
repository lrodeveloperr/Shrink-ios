# App Privacy preparation

This is a preparation record, not a substitute for inspecting the signed archive or completing App Store Connect.

## Developer functional data

Price checks, stores, dates, barcodes, product names, package amounts, prices, quantities, decisions, learned barcode links, and active-trip state are stored in the app container. There is no WorksBien account, cloud backend, runtime product API, analytics SDK, or crash-reporting SDK in the inspected source. The app does not transmit this functional data to WorksBien.

Device backups controlled by the user and Apple can contain app-container data. Support information is collected only when the user leaves the app and chooses to contact WorksBien through the external support page.

## Camera

Camera access is requested when the user starts scanning. Barcode and shelf-price recognition use Apple frameworks. Manual entry remains available. The inspected source does not save video or upload camera frames.

## Google advertising

Google Mobile Ads and User Messaging Platform are bundled. Google's current iOS disclosure guide says the Mobile Ads SDK may collect IP address, crash logs, performance data, device identifiers, advertising data, and product-interaction data. The final App Privacy answers must include the exact production SDK version, enabled features, mediation partners, production settings, consent configuration, and archive privacy manifests.

Current source uses Google sample identifiers. Sample mode bypasses UMP, while production mode runs UMP, checks whether ads may be requested, exposes privacy options when required, and requests ATT authorization before starting ads. This split is deliberate for TestFlight but blocks a production privacy declaration until production identifiers and runtime behavior are verified.

## StoreKit

Apple processes the non-consumable Remove Banner purchase. The app receives StoreKit product metadata, verified transactions, entitlement status, refunds or revocations, and restore results needed to provide the purchase. WorksBien does not receive full payment-card details.

## Privacy manifest blocker

The app privacy manifest currently declares tracking but lists no collected data types and no tracking domains. That file, embedded Google SDK manifests and signatures, App Privacy answers, ATT behavior, UMP behavior, and the public policy must be reconciled from the signed production archive before submission.

