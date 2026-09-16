#!/usr/bin/env python3
"""Independent, read-only validator for the locked USDA catalogue."""

from __future__ import annotations

import argparse
from collections import Counter
import csv
import hashlib
import io
import json
from pathlib import Path
import re
import sqlite3
import zipfile

EXPECTED_ARCHIVE = "26050a5d03197469813754743a21ee0fad4ccf22b6aac2a995846a987719fc49"
EXPECTED_CORRECTION_DIGEST = "b9a4ee42bb3706bf142a0134e638730bce9f124a7fa353cd455725c149600e94"
EXPECTED_SEMANTIC_MANIFEST_SHA256 = "c453f25c50c76fd2bc9105761f4ad1d644eefe86cedeca974cfc733d141bb0b9"
EXPECTED_COUNT = 426_044
EXPECTED_LENGTHS = {8: 994, 12: 373_799, 13: 29_084, 14: 22_167}
EXPECTED_COVERAGE = {
    ("source_description", "biscuit"): 1506,
    ("source_description", "cookie"): 14510,
    ("source_description", "cracker"): 4907,
    ("category", "biscuit"): 15951,
    ("category", "cookie"): 18068,
    ("category", "cracker"): 4556,
}
EXPECTED_EXAMPLES = {
    "1627758": "Mtn Dew Throwback",
    "1457267": "20 Oz. and Up Lobster Tails",
    "1458406": "Langostino Meat 60-90 ct",
    "2369476": "You're the G.O.A.T! with Gummy Candy Hearts",
    "2671760": "Original 7-in-1 Mixed Vegetables",
    "2736792": "Wright Brand Naturally Hickory Smoked Thin Sliced Bacon, 9 Slices/Inch",
    "2520750": "Litehouse Pour on the Taste Greek Vinaigrette",
    "2418303": "80% Lean 20% Fat 1/3-Lb Angus Burgers",
    "2556451": "Whole Sour Pickles, 14-16 Count per Gallon",
    "1457828": "4/6 Oz. CO Vacuum-Packed Redfish",
    "1457217": "10/12 Oz. CO Vacuum-Packed Redfish",
    "766932": "8/10 Oz. Unicorn Filefish",
    "2721203": "Kosher Style Pickles, 18-22 Count per Gallon",
    "2696325": "Hormel Layout Lower Sodium Bacon 18-22 Slices Per Pound",
    "2735113": "Pillsbury Cake Donut Mix Bulk Sack Taste Best #1",
}
EXPECTED_CORRECTION_IDS = {
    355787,355913,356011,356015,356094,356422,612778,613066,613154,613458,613544,613610,613754,809238,809468,809634,811096,1461558,
    1874863,1728658,1881254,2123463,2153279,2165683,2170661,2187256,2187260,2269704,2286996,2424704,2429028,2632567,
    2703902,2704457,917020,2724869,2734531,2734540,2737151,2737178,2737755,1462145,2520750,1627758,1457267,1458406,2369476,2671760,2736792,611744,2626409,
}
PACKAGE_NOISE = re.compile(
    r"(?:,?\s*\b(?:bulk|frozen)\b\s*)$|"
    r"(?:,|-)?\s*\b\d+(?:\.\d+)?\s*(?:fl\.?\s*oz|floz|oz|ounces?|lbs?|pounds?|g|kg|ml|l)\b(?:\s*(?:bottle|box|bag|can|carton|jar|packet|pouch|sheet))?(?:\s*[-/]?\s*\d*\s*(?:pack|pk|count|ct))?\s*$",
    re.IGNORECASE,
)
SEAFOOD_CATEGORY = re.compile(r"fish|shellfish|seafood|aquatic", re.IGNORECASE)
SEAFOOD_LEADING_GRADE = re.compile(
    r"^\s*((?:\d+\s*/\s*\d+|\d+\s*-\s*\d+)\s*(?:oz\.?|ct\.?|cnt)\s*(?:/\s*(?:up|kg))?|\d+\s*oz\.?\s*/\s*up)\b",
    re.IGNORECASE,
)
ADDITIONAL_SEAFOOD_GRADE_GTINS = {
    "00075391015230", "00075391015537", "00075391020036", "00075391020258",
    "00075391043820", "00075391045732", "00075391053812", "00075391058473",
    "00075391058480", "00075391058503", "00075391058510", "00075391940983",
    "00075391955345", "00075391955864", "00075391955895", "00075391965252",
    "00075391965962", "00075391971581", "00075391971901",
}
MIXED_PACKAGE_MEASURE = re.compile(
    r"(?<![\d.#])(\d+)\s+\d+\s*/\s*\d+\s*(?:fl\.?\s*oz|floz|oz|ounces?|lbs?|pounds?|grams?|g|kg|ml|liters?|l)\b",
    re.IGNORECASE,
)
TARGETED_SEMANTIC_NAMES = {
    "00075391006627": (
        "b4140133141ce03697f0cb097e05cba1cefec2bba01dd4d689e98456c4e692bf",
        "5 Lb. and Up Black Grouper Loin",
    ),
    "00075391060865": (
        "32846661d2aa22cddcf56abc2a651d311c75a6478759c2e7a888ab7111342efd",
        "Green Lobsters, 2 Lb. and Up",
    ),
    "00075391948651": (
        "96b8131639379f392d450723c1c3a4a50bc1226f51186dc324520f6cf2d0ddeb",
        "7 Lb. and Up Mahi-Mahi Loins",
    ),
    "00075391027172": (
        "b3a4bf7903113ab5f0b8fb33895856159fba845a0885e7549b96bc772058740a", "10 and Up Whole Gutted Grouper",
    ),
    "00075391028360": (
        "8d00ee898ca82ec3cacae09bc2b5c971e2992121d2707890974fabb3964eea88", "8 and Up Canadian Snow Crab Cluster",
    ),
    "00075391028438": (
        "b7180b4aaf49a6d475bb0040fbf244d745db91ee8a9e1b08685f32b1a53b501d", "8 and Up Snow Crab Clusters",
    ),
    "00075391028919": (
        "859599fe1f68730c9957c9d8db7b18b8b6d484690639d3ef348cf401aabb565f", "150 and Up Gulf Peeled Undeveined Shrimp",
    ),
    "00075391031698": (
        "2c1e4a7ff12fa9a16a37483f6a244a77069d0bc15f1ceaf98e5238a6275811b2", "10 and Up Snow Crab Clusters",
    ),
    "00075391049709": (
        "b5bee97818edffc7d20b1dbd2c0540dcbc2d55a32a06cc6968b4362d5cef4ce3", "2 and Up Wahoo Loins",
    ),
    "00075391051085": (
        "c1a112640065a043d53896de124789c96be9d506d83820cb65ed3cf0cf421634", "10 Oz. and Up Flounder Fillets",
    ),
    "00075391060537": (
        "a3ecb9e4c1fdc7a5736dba5bb931ffaa55350ee7bfda7e33887835bdbd4a6ec8", "8 Oz. and Up Rockfish Fillet",
    ),
    "00075391943335": (
        "38808365e4bc05c64de735b51de5d557804cf9b8164d491256577b6b584d5fd0", "20 and Up Red King Crab Legs",
    ),
    "90075391009119": (
        "fa76fbf0a2a743019a6f523702e2384507ba140d736232d9f596018cb1527b56", "Beef Tenderloin PSMO, 5 and Up",
    ),
    "90075391035446": (
        "da0309ddc753011e5a681a2de934ca9d3ee42e1a5acc992e0070711e70923be3", "Beef Tenderloin CAB, 5 and Up",
    ),
    "90736490042543": (
        "038dd1c5f8251022d69d6527a0bc5ad93192a77b2dc28a291b4fd8bd05dd9ef5", "Pork Spareribs St. Louis Style Wide Cut, 3.25 and Up",
    ),
    "90736490042642": (
        "038dd1c5f8251022d69d6527a0bc5ad93192a77b2dc28a291b4fd8bd05dd9ef5", "Pork Spareribs St. Louis Style Wide Cut, 3.25 and Up",
    ),
}


def file_hash(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def fail(message: str) -> None:
    raise SystemExit(f"Catalogue validation failed: {message}")


def canonical_gtin(raw: str) -> tuple[str, str] | None:
    digits = "".join(character for character in raw if character.isdigit())
    if len(digits) not in {8, 12, 13, 14}:
        return None
    total = sum(int(digit) * (3 if index % 2 == 0 else 1) for index, digit in enumerate(reversed(digits[:-1])))
    if (10 - total % 10) % 10 != int(digits[-1]):
        return None
    return digits.zfill(14), digits


def clean_space(value: str) -> str:
    return re.sub(r"\s+", " ", value).strip()


def recompute_family(brand: str, description: str) -> str:
    stem = clean_space(description).casefold()
    previous = None
    while stem != previous:
        previous = stem
        stem = PACKAGE_NOISE.sub("", stem).strip(" ,-;")
    key = f"{clean_space(brand).casefold()}|{stem}"
    return "usda:" + hashlib.sha256(key.encode("utf-8")).hexdigest()[:24]


def normalized_seafood_grade(raw: str) -> str:
    value = clean_space(raw).upper().replace("CNT", "CT")
    value = re.sub(r"\s*/\s*", "/", value)
    value = re.sub(r"\s*-\s*", "-", value)
    match = re.fullmatch(r"(.+?)\s*(OZ\.?|CT\.?)\s*(?:/(UP|KG))?", value)
    if match is None:
        fail(f"unrecognized seafood grade {raw!r}")
    quantity, unit, suffix = match.groups()
    if unit.startswith("CT"):
        return f"{quantity} Count per kg" if suffix == "KG" else f"{quantity} Count"
    if suffix == "UP":
        return f"{quantity} Oz. and Up"
    if suffix == "KG":
        return f"{quantity} Oz. per kg"
    return f"{quantity} Oz."


parser = argparse.ArgumentParser()
parser.add_argument("database", type=Path)
source_group = parser.add_mutually_exclusive_group(required=True)
source_group.add_argument("--archive", type=Path)
source_group.add_argument("--database-only", action="store_true")
arguments = parser.parse_args()

if arguments.archive is not None and file_hash(arguments.archive) != EXPECTED_ARCHIVE:
    fail("official archive hash differs")

with sqlite3.connect(f"file:{arguments.database}?mode=ro", uri=True) as db:
    db.row_factory = sqlite3.Row
    if db.execute("PRAGMA integrity_check").fetchone()[0] != "ok":
        fail("SQLite integrity_check failed")
    count = db.execute("SELECT COUNT(*) FROM products").fetchone()[0]
    if count != EXPECTED_COUNT:
        fail(f"expected {EXPECTED_COUNT:,} products, found {count:,}")
    unique = db.execute("SELECT COUNT(DISTINCT gtin14) FROM products").fetchone()[0]
    if unique != count:
        fail("canonical GTIN-14 identities are not unique")
    columns = {row[1] for row in db.execute("PRAGMA table_info(products)")}
    if any("fr" in column.casefold() for column in columns):
        fail("French catalogue fields remain")
    lengths = dict(db.execute("SELECT original_gtin_length, COUNT(*) FROM products GROUP BY original_gtin_length"))
    if lengths != EXPECTED_LENGTHS:
        fail(f"original GTIN-length distribution differs: {lengths}")
    if db.execute("SELECT COUNT(*) FROM products WHERE market_country <> 'US' OR discontinued_date <> ''").fetchone()[0]:
        fail("unsupported market or discontinued products remain")
    if db.execute("SELECT COUNT(*) FROM products WHERE lower(product_name) LIKE 'demo %' OR lower(source_description) LIKE 'demo %' OR lower(brand) LIKE 'sample brand%'").fetchone()[0]:
        fail("demo product remains")
    correction_ids = {int(row[0]) for row in db.execute("SELECT usda_fdc_id FROM corrections")}
    if correction_ids != EXPECTED_CORRECTION_IDS:
        fail("the frozen 51 correction identities differ")
    if db.execute("""
        SELECT COUNT(*) FROM corrections c
        LEFT JOIN products p ON p.usda_fdc_id = c.usda_fdc_id
        WHERE p.usda_fdc_id IS NULL OR p.product_name <> c.product_name
    """).fetchone()[0]:
        fail("a frozen correction output differs from its product row")
    correction_digest = hashlib.sha256()
    for row in db.execute("SELECT usda_fdc_id, source_sha256, product_name FROM corrections ORDER BY CAST(usda_fdc_id AS INTEGER)"):
        correction_digest.update("\x1f".join(row).encode("utf-8"))
        correction_digest.update(b"\n")
    if correction_digest.hexdigest() != EXPECTED_CORRECTION_DIGEST:
        fail("the frozen source-hash/output correction digest differs")
    masks = Counter(row[0] for row in db.execute("SELECT reason FROM semantic_masks"))
    if masks != Counter({"piece_rate": 77, "fish_grade": 61, "reviewed_grade": 13, "slices_per_inch": 1}):
        fail(f"semantic mask is not the reviewed 152 identities: {dict(masks)}")
    semantic_manifest = Path(__file__).with_name("semantic_mask_2026-04-30.csv")
    if file_hash(semantic_manifest) != EXPECTED_SEMANTIC_MANIFEST_SHA256:
        fail("the frozen semantic identity manifest changed")
    with semantic_manifest.open(encoding="utf-8", newline="") as source:
        expected_rows = list(csv.DictReader(source))
    expected_masks = {
        (row["gtin14"], row["reason"], row["source_sha256"], row["product_name"])
        for row in expected_rows
    }
    actual_masks = {tuple(row) for row in db.execute("SELECT gtin14, reason, source_sha256, product_name FROM semantic_masks")}
    if actual_masks != expected_masks:
        fail("database semantic identities, source gates, or exact outputs differ from the frozen manifest")
    for row in db.execute("""
        SELECT s.gtin14, s.source_sha256, s.product_name,
               p.source_description, p.product_name
        FROM semantic_masks s JOIN products p ON p.gtin14 = s.gtin14
    """):
        if hashlib.sha256(row[3].encode("utf-8")).hexdigest() != row[1]:
            fail(f"semantic source hash differs for {row[0]}")
        if row[4] != row[2]:
            fail(f"semantic exact product name differs for {row[0]}")
    for source_id, expected in EXPECTED_EXAMPLES.items():
        row = db.execute("SELECT product_name FROM products WHERE usda_fdc_id = ?", (source_id,)).fetchone()
        if row is None or row[0] != expected:
            fail(f"approved name differs for USDA {source_id}: {row[0] if row else 'missing'}")
    metadata = dict(db.execute("SELECT key, value FROM metadata"))
    for key in ("archive_sha256", "source_url", "release_date", "license", "selection", "identity_digest_sha256"):
        if not metadata.get(key):
            fail(f"metadata {key} is missing")
    for (column, word), expected in EXPECTED_COVERAGE.items():
        actual = db.execute(f"SELECT COUNT(*) FROM products WHERE lower({column}) LIKE ?", (f"%{word}%",)).fetchone()[0]
        if actual != expected:
            fail(f"{column} {word} coverage expected {expected}, found {actual}")
    noise = re.compile(
        r"(?:/\s*$|\bEach\s+\.|(?<![\d.])(?:\d+\s*/\s*)?(?:\d+(?:\.\d+)?|\.\d+)\s*(?:fl\.?\s*oz|floz|oz|ounces?|lbs?|pounds?|grams?|g|kg|ml|liters?|l)\b|\b\d+\s*(?:pack|pk)\b|\b\d+\s*[x×]\s*\d+\s*(?:pack|pk)\b|\b\d+(?:\s*[-/]\s*\d+)*\s*(?:count|ct|pieces?|slices?)(?:\s+per\s+(?:package|case|box|bag|carton))?\b)",
        re.IGNORECASE,
    )
    malformed = re.compile(r"(?:\d+/\.|,\s*\.\s*(?:,|$)|\(\s*\.\s*\))")
    masked_gtins = {row[0] for row in db.execute("SELECT gtin14 FROM semantic_masks")}
    semantic_grade_gtins = {
        row[0] for row in db.execute("SELECT gtin14, source_description, category FROM products")
        if SEAFOOD_LEADING_GRADE.match(row[1]) is not None
        and (SEAFOOD_CATEGORY.search(row[2]) or row[0] in ADDITIONAL_SEAFOOD_GRADE_GTINS)
    }
    visible_noise = [
        (row[0], row[1]) for row in db.execute("SELECT gtin14, product_name FROM products")
        if row[0] not in masked_gtins | semantic_grade_gtins | set(TARGETED_SEMANTIC_NAMES) and noise.search(row[1])
    ]
    if visible_noise:
        fail(f"visible package-noise detector found {len(visible_noise)} unreviewed rows; first is {visible_noise[0]}")
    malformed_names = [(row[0], row[1]) for row in db.execute("SELECT gtin14, product_name FROM products") if malformed.search(row[1])]
    if malformed_names:
        fail(f"malformed display-name residue found in {len(malformed_names)} rows; first is {malformed_names[0]}")

    category_grade_count = 0
    additional_grade_count = 0
    mixed_measure_count = 0
    for row in db.execute("SELECT gtin14, source_description, product_name, category FROM products"):
        grade_match = SEAFOOD_LEADING_GRADE.match(row[1])
        category_match = bool(SEAFOOD_CATEGORY.search(row[3])) and grade_match is not None
        additional_match = row[0] in ADDITIONAL_SEAFOOD_GRADE_GTINS and grade_match is not None
        if category_match or additional_match:
            expected_prefix = normalized_seafood_grade(grade_match.group(1))
            if not row[2].casefold().startswith(expected_prefix.casefold()):
                fail(f"seafood grade was not preserved for {row[0]}: {row[2]!r}")
            category_grade_count += int(category_match)
            additional_grade_count += int(additional_match and not category_match)
        mixed_match = MIXED_PACKAGE_MEASURE.search(row[1])
        if mixed_match is not None:
            mixed_measure_count += 1
            dangling = re.compile(rf"(?:^|,\s*){re.escape(mixed_match.group(1))}(?:\s*(?:,|$))")
            if dangling.search(row[2]):
                fail(f"mixed package measure left a dangling whole number for {row[0]}: {row[2]!r}")
    if category_grade_count != 263 or additional_grade_count != 19:
        fail(f"seafood-grade coverage differs: category={category_grade_count}, additional={additional_grade_count}")
    if mixed_measure_count != 26:
        fail(f"mixed package-measure audit expected 26 rows, found {mixed_measure_count}")

    fish_source_outputs = {}
    for row in db.execute("""
        SELECT p.source_description, s.product_name
        FROM semantic_masks s JOIN products p ON p.gtin14 = s.gtin14
        WHERE s.reason = 'fish_grade'
    """):
        prior = fish_source_outputs.setdefault(row[0], row[1])
        if prior != row[1]:
            fail(f"reviewed duplicate fish source has inconsistent exact outputs: {row[0]!r}")
    duplicate_count = 0
    for source_description, expected_name in fish_source_outputs.items():
        for row in db.execute("""
            SELECT p.gtin14, p.product_name FROM products p
            LEFT JOIN semantic_masks s ON s.gtin14 = p.gtin14
            WHERE p.source_description = ? AND s.gtin14 IS NULL
        """, (source_description,)):
            duplicate_count += 1
            if row[1] != expected_name:
                fail(f"duplicate reviewed fish source differs for {row[0]}: {row[1]!r}")
    if duplicate_count != 26:
        fail(f"expected 26 unmasked duplicate fish identities, found {duplicate_count}")

    for gtin14, (source_hash, product_name) in TARGETED_SEMANTIC_NAMES.items():
        row = db.execute(
            "SELECT source_description, product_name FROM products WHERE gtin14 = ?", (gtin14,)
        ).fetchone()
        if row is None or hashlib.sha256(row[0].encode("utf-8")).hexdigest() != source_hash:
            fail(f"targeted semantic source gate differs for {gtin14}")
        if row[1] != product_name:
            fail(f"targeted semantic exact output differs for {gtin14}: {row[1] if row else 'missing'}")
    residual_up = [
        (row[0], row[1]) for row in db.execute("SELECT gtin14, product_name FROM products")
        if re.search(r"/\s*up\b", row[1], re.IGNORECASE)
    ]
    if residual_up:
        fail(f"damaged '/up' grade residue remains; first is {residual_up[0]}")

    identity = hashlib.sha256()
    for row in db.execute("""
        SELECT gtin14, original_gtin, original_gtin_length, usda_fdc_id,
               source_description, family_id, brand, category, data_source,
               publication_date, modified_date, available_date, discontinued_date,
               market_country FROM products ORDER BY gtin14
    """):
        identity.update("\x1f".join(str(value) for value in row).encode("utf-8"))
        identity.update(b"\n")
    if identity.hexdigest() != metadata["identity_digest_sha256"]:
        fail("non-display identity digest differs")

    if arguments.database_only:
        print("Independent database, identity, and exact-name validation passed; official archive comparison was explicitly skipped.")
        raise SystemExit(0)

    # Independently compare every raw source description and correction source hash.
    source_rows = {row["usda_fdc_id"]: (row["source_description"], row["gtin14"]) for row in db.execute("SELECT usda_fdc_id, source_description, gtin14 FROM products")}
    catalogue_rows = {row["gtin14"]: dict(row) for row in db.execute("SELECT * FROM products")}
    correction_hashes = dict(db.execute("SELECT usda_fdc_id, source_sha256 FROM corrections"))
    found = set()
    publication_dates = {}
    with zipfile.ZipFile(arguments.archive) as archive:
        member = next(name for name in archive.namelist() if name.endswith("/food.csv"))
        with archive.open(member) as raw:
            for row in csv.DictReader(io.TextIOWrapper(raw, encoding="utf-8-sig", errors="strict", newline="")):
                source_id = row.get("fdc_id", "")
                expected = source_rows.get(source_id)
                if expected is None:
                    continue
                found.add(source_id)
                publication_dates[source_id] = row.get("publication_date", "")
                if row.get("description", "") != expected[0]:
                    fail(f"raw USDA description changed for {source_id}")
                if source_id in correction_hashes and hashlib.sha256(expected[0].encode("utf-8")).hexdigest() != correction_hashes[source_id]:
                    fail(f"mutated-source gate failed for {source_id}")
    if len(found) != EXPECTED_COUNT:
        fail(f"only {len(found):,} raw descriptions were independently matched")

    # Independently reconstruct the branded-food selection and every retained
    # provenance/family field instead of trusting builder metadata.
    latest = {}
    with zipfile.ZipFile(arguments.archive) as archive:
        member = next(name for name in archive.namelist() if name.endswith("/branded_food.csv"))
        with archive.open(member) as raw:
            for row in csv.DictReader(io.TextIOWrapper(raw, encoding="utf-8-sig", errors="strict", newline="")):
                if clean_space(row.get("market_country", "")) != "United States":
                    continue
                normalized = canonical_gtin(row.get("gtin_upc", ""))
                if normalized is None:
                    continue
                gtin14, original = normalized
                key = (row.get("modified_date", ""), row.get("available_date", ""), int(row.get("fdc_id") or 0))
                if gtin14 not in latest or key > latest[gtin14][0]:
                    latest[gtin14] = (key, row, original)
    selected = {
        gtin14: (row, original)
        for gtin14, (_, row, original) in latest.items()
        if not clean_space(row.get("discontinued_date", ""))
        and not (len(original) == 8 and original[0] in "01")
    }
    if set(selected) != set(catalogue_rows):
        fail("independently reconstructed GTIN selection differs")
    for gtin14, (source, original) in selected.items():
        actual = catalogue_rows[gtin14]
        brand = clean_space(source.get("brand_name") or source.get("brand_owner") or "")
        expected = {
            "original_gtin": original,
            "original_gtin_length": len(original),
            "usda_fdc_id": source.get("fdc_id", ""),
            "brand": brand,
            "category": clean_space(source.get("branded_food_category", "")),
            "data_source": clean_space(source.get("data_source", "")),
            "publication_date": publication_dates[source.get("fdc_id", "")],
            "modified_date": clean_space(source.get("modified_date", "")),
            "available_date": clean_space(source.get("available_date", "")),
            "discontinued_date": clean_space(source.get("discontinued_date", "")),
            "market_country": "US",
            "family_id": recompute_family(brand, actual["source_description"]),
        }
        for field, value in expected.items():
            if actual[field] != value:
                fail(f"provenance field {field} differs for {gtin14}")

print("Independent USDA catalogue validation passed.")
