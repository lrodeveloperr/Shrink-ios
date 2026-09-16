# Independent USDA Catalogue Validation

Validation completed on September 16, 2026 against the locked USDA FoodData Central branded-food archive dated April 30, 2026.

## Source and reproducibility

- Official source: `https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_branded_food_csv_2026-04-30.zip`
- Archive SHA-256: `26050a5d03197469813754743a21ee0fad4ccf22b6aac2a995846a987719fc49`
- Bundled catalogue SHA-256: `255468433a3b986e2d5e7c85dd02f029cae83401128a8496280459fb39f21cee`
- Independently rebuilt catalogue SHA-256: `255468433a3b986e2d5e7c85dd02f029cae83401128a8496280459fb39f21cee`
- Result: the independently rebuilt database is byte-for-byte identical to the bundled database.

## Passed gates

- Exactly 426,044 unique selected US-market products.
- Original GTIN-length distribution: 994 EAN-8, 373,799 UPC-A, 29,084 EAN-13 and 22,167 GTIN-14 records.
- Every retained raw USDA description, source identifier, date, provenance field and stable family identity matched the official archive.
- All 51 frozen, source-hash-gated display-name corrections matched.
- All 152 reviewed semantic size/rate identities matched their GTIN, source hash, reason and exact display output.
- All protected seafood grades, duplicate-source outputs and mixed-fraction package-weight cases passed.
- No unsupported market, discontinued product, demo product, visible package-noise residue or malformed display name was found.
- SQLite integrity and unique canonical-GTIN checks passed.

## Commands used

```bash
python3 Scripts/validate_catalogue.py App/Resources/catalogue.sqlite3 \
  --archive /path/to/FoodData_Central_branded_food_csv_2026-04-30.zip

python3 Scripts/build_catalogue.py \
  /path/to/FoodData_Central_branded_food_csv_2026-04-30.zip \
  --output /tmp/catalogue-independent.sqlite3

sha256sum App/Resources/catalogue.sqlite3 /tmp/catalogue-independent.sqlite3
```
