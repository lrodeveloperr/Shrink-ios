# Localization release checklist

Locales: English (`en`), Latin American Spanish (`es-419`, including Puerto Rico), and Canadian French (`fr-CA`). Market and language are independent.

## Linguistic approval

- [x] Québec French (`fr-CA`) reviewer approved all 232 native UI keys, plural forms, permission prompts, Shrink Radar vocabulary, supermarket terminology, purchase/privacy copy, and placeholder parity.
- [x] Puerto Rico-aware Latin American Spanish (`es-419`) reviewer approved all 232 native UI keys, plural forms, permission prompts, Shrink Radar vocabulary, supermarket terminology, purchase/privacy copy, and placeholder parity.
- [x] Expert reviewers approve the final native Spanish and Québec French copy after the new trip, Scorecard, filter, decision and policy strings are frozen.
- [x] Expert reviewers approved the public Privacy Policy and Terms of Use in Puerto Rico-appropriate Latin American Spanish and Québec French.
- [ ] Expert reviewer approves plurals, decimal input, supermarket terminology, purchase/privacy copy, and StoreKit metadata on device.

## Automated checks

- [x] Run `python3 Scripts/check_localizations.py`.
- [x] Run `python3 Scripts/build_catalogue.py Scripts/seed_catalogue.csv --output App/Resources/catalogue.sqlite3`.
- [x] Confirm the catalogue contains `product_name`, `product_name_es`, and `product_name_fr`.
- [ ] Build and run the XCTest target in Xcode.

## Native UI checks

- [ ] Launch once in English, Spanish, and Canadian French using Xcode scheme language overrides.
- [ ] Verify Scan, History, Impact, Settings, every sheet, alert, error, toast, empty state, purchase screen, and VoiceOver label.
- [ ] Verify small iPhone, large iPhone, and iPad at the largest accessibility text sizes.
- [ ] Confirm long French labels wrap cleanly and no button truncates its action.
- [ ] Confirm Spanish consistently uses informal `tú` and French consistently uses `vous`.
- [ ] Confirm Québec terminology and typography: `réduflation`, `épicerie`, `code-barres`, accents, apostrophes, and currency spacing.

## Data and comparison checks

- [ ] Confirm UPC/EAN/GTIN values and product-family IDs are identical in every language.
- [ ] Confirm official store and brand names are never machine-translated.
- [ ] Confirm an official localized product name is preferred; otherwise the English/original name appears unchanged.
- [ ] Confirm language changes do not change market, currency, shopping trips, history, or comparisons.
- [ ] Confirm US and Puerto Rico records use USD and the US catalogue; Canadian records use CAD and the Canadian catalogue.
- [ ] Confirm custom supermarkets require an actual name and never save as one generic “Other” retailer.
- [ ] Confirm store comparison uses canonical stored names/IDs, not translated labels.
- [ ] Confirm localized units display correctly while calculations continue to use canonical unit codes.
- [ ] Confirm `6 × 50 g` is stored as amount `50 g` and pack count `6`, without double-counting.
- [ ] Confirm dates, decimals, percentages, and currency use the active locale.

## App Store checks

- [x] Publish reviewer-accessible Privacy Policy and Terms of Use pages on `worksbienstudios.com` in English, Spanish, and Canadian French.
- [x] Wire the Settings links to the matching device language on the WorksBien website.
- [x] Confirm the public policy site includes a language switcher and stable direct URLs.
- [ ] Add Spanish and Canadian French App Store metadata, keywords, screenshots, privacy-policy links, and support text.
- [ ] Localize the StoreKit product name and description for the banner-removal purchase.
- [ ] Verify the localized camera and tracking permission prompts on device.
- [ ] Obtain final legal counsel review of every localized privacy and terms page before submission.
- [ ] Have a native Spanish/Québec French reviewer approve final device screenshots before submission.
