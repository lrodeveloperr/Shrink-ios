#!/usr/bin/env python3
"""Build the locked offline USDA FoodData Central catalogue.

This importer accepts only the official April 30, 2026 branded-food CSV archive.
It preserves source identity/provenance and creates a separate display name. Retail
package quantity and shelf price are deliberately not imported as current values.
"""

from __future__ import annotations

import argparse
import csv
import functools
import hashlib
import io
import json
import os
import re
import sqlite3
import tempfile
import zipfile
from collections import Counter
from dataclasses import dataclass
from pathlib import Path


ARCHIVE_SHA256 = "26050a5d03197469813754743a21ee0fad4ccf22b6aac2a995846a987719fc49"
SOURCE_URL = "https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_branded_food_csv_2026-04-30.zip"
RELEASE_DATE = "2026-04-30"
LICENSE = "USDA FoodData Central public-domain data"
EXPECTED_COUNT = 426_044
EXPECTED_LENGTHS = {8: 994, 12: 373_799, 13: 29_084, 14: 22_167}

# The exact raw-description hashes make every correction a source-ID + raw-source
# gate. A changed source row is rejected instead of receiving an accidental edit.
FROZEN_CORRECTION_HASHES = {
    355787: "a2233caef3c6c57045f467cf973690d3906ecd06001d20556f1adea3ae352b38",
    355913: "c5edbe528127a3aee694f679edd7c107391375cee405c20742ea695b38fd081c",
    356011: "82e28e405151f01753f9c01d3c544859978d1c4c72b1413105f3bfc01e780e0f",
    356015: "5898d99ed099860ca52ffba7a824f37216e480512e230976e9d4cefd3ee56ce0",
    356094: "9d839d02cfad028969e4ee56bc4a0daaaee1296c52dd1647f560e59969773af8",
    356422: "9a96816c5fb248cd5bd5f2301ee7693b1f095720dd0bb7ed45567264a60f3ee1",
    612778: "8051fdff6c0c782e3437a6f9bba7b75dcd0f5329eba4e3c6c2319cefe303febf",
    613066: "fa1492af5360da33a0ae9574c136cc820d602d54ad1601ebe961902dcebafb0e",
    613154: "8771218efec0e47d7e3e01be9158a99ac905b0b8277dd6c3c71ab36842c1c8af",
    613458: "50367b6c2d30a4a73c324eaf2b536bbf5b443ccd52c61856a48de83c7f8603fb",
    613544: "2633fa8acd086c4e89a63d44b3c6d4cf44c185bd01b7a7660eee6cfbadf5ba84",
    613610: "860e2bc9cbc31e4d231614750aa1b718b5fed44173fd8eaafc5d8b94828736fa",
    613754: "88a650b467dfa5bfcdbe1c4e0eb58f497489c2d43f80c371a38c3f699ab3f466",
    809238: "9d839d02cfad028969e4ee56bc4a0daaaee1296c52dd1647f560e59969773af8",
    809468: "04949de90a6f2b3fa980b8b42e04ff44338a0fce16101782b56426cb9082ef33",
    809634: "8a13d50c3c4c74cb2da41fbae7a7aafb67a8c0e0cd3c871a733579dc199a0411",
    811096: "084c436e081a7f4033786fd3ef7c78f7a465873a4d86c36ea482342a60c0d6dd",
    1461558: "084c436e081a7f4033786fd3ef7c78f7a465873a4d86c36ea482342a60c0d6dd",
    1874863: "b07a5aa9a7cf4ddb49957fc579f33c52a29e472fef6bec88349acb6176e4654f",
    1728658: "5060fef89c865b9b246604a0fefaeed04cc58b3f16ecf5fbc743635c51f26a27",
    1881254: "f01312b23e531f8664ec24a07a909aa33c52cbb3a9251ea9ab97a638184511e7",
    2123463: "2ce70c8c458e38ae85a312f374aba4d4c05c4ca24ccdb1ae75a297d04fb5e686",
    2153279: "83e300fbdbcd0702c7142cf1953b5ceffb17e4be3204d10a44e0f1cbd9c9bcec",
    2165683: "3d7d3397f5a7bc3c42e12d367df7c9997ed40150bcbc9295450f57583de405b7",
    2170661: "c2b69c8ae00f01c7617504ee0205069a19e456ee20d4667cf51edaf544807fbe",
    2187256: "3e745de4f42e73cfcaef846af9f01d75721ecac8210e60703fb49b128e3c5429",
    2187260: "723a8331e137f66d2e03ac80abaa81b1f5657afd96a4e7e0af35ab4e863d7d45",
    2269704: "c0f909f5de8150d9342220bb510c67bd7b1aa3eba31bb0d7e1e36c36bb383e1f",
    2286996: "723a8331e137f66d2e03ac80abaa81b1f5657afd96a4e7e0af35ab4e863d7d45",
    2424704: "41094fae2ddb17180d318f76ba85a3bdc00d02de508ad8908c12d8b8bb9a4a63",
    2429028: "6eb01763ebf2210af54e9e05f76ec45dfeb430e9caa837985a39ea7e8352cc07",
    2632567: "46d8bac76c52ef0964961446211c665e2fb37abc28564c5167820a7f0ca3d5f7",
    2703902: "0832ffac8cb956b81c4dc72e048a369d03542c7b80ca155d70d1e7cacf8438b7",
    2704457: "24290fc333869cb5474862e7d5c4b2df434a2bed7d9cb7e0d55dc1b1771eb9f0",
    917020: "15b84fbc43dc3d83bfdcefc3eeb1f449fe9b69e6cba65849915845205c8653dd",
    2724869: "adbaccffa60373d4d4089985d333dc701e19613d06b782dc54f05b68db547ae3",
    2734531: "6e95e995f3338ea6476010d29cebe38a9be02c2de00e176d5bfed26ff9641ca4",
    2734540: "78c5dba960d473b3e74f966ec57624036b12976901f349808d09dfba8876e431",
    2737151: "b3acdea2ec92d8140c0d283b8f86dff7fe51033e07d7cff19a5658f932bdede5",
    2737178: "752bea6169858dcb2b406942d00487bf20df48dd24a50e61b566382932e48d0a",
    2737755: "61912931e1eadb60e6a9b30ce78314d788872f83faa8f9c48fec8dac5673a4bc",
    1462145: "a3d9b97691522afbd85728625581eb2b6173b85ad7e0dde2f24dec250ebc3bc0",
    2520750: "d1e523c9902be9464fde06c7ad9d4c4d9224cf818d83df9c91d4f55fbadb4790",
    1627758: "fc7d51b297a22562eefdbe298eb61b2b83935d65f399ed9ce4569340aacdb255",
    1457267: "cc257e94f79b5a0f4e4bf420109eb744e3bcc4318d9045cc843f7950a9c752c7",
    1458406: "2657363cde1f87f76d1322f90eec76fecbbc65a05f7b685b1dc3e86bf04863d8",
    2369476: "dc0b67d978480b1a2663fdb78749ee413329fe8132da9a485ee52f45f9ec4736",
    2671760: "a36a5bd8348fcc1310ec03bfb6361dd48cc8b17a4e8039566cd3da8cb4a67334",
    2736792: "9c47cb39ae31ac3bed1ea462faaa80e14114798ce7770c3651f2226853dbda3f",
    611744: "9b5a022d86a58737c51f0b641e302d39f4043b1985fa43bf6d7e3df90fe59a8b",
    2626409: "bfd34567b95ed64cd63e156f0a8ad0a962c8884110915c2c2984c47a213b7272",
}

FROZEN_CORRECTION_OUTPUTS = {
    355787: "Plum Stage 2 Veg Blends Baby Food Spinach Pumpkin Chickpea",
    355913: "Plum Stage 3 Baby Food Chickenpea Tomato Beef",
    356011: "Plum Stage 2 Blends Baby Food Sweet Potato Corn Apple",
    356015: "Plum Stage 2 Grain Baby Food Apple Raisin Quinoa",
    356094: "Plum Stage 2 Blends Baby Food Pumpkin Banana",
    356422: "Plum Stage 2 Veg Blends Baby Food Carrot Spinach Bean",
    612778: "Plum Stage 2 Blends Baby Food Mango Carrot Coconut",
    613066: "Plum Stage 2 Blends Baby Food Apple Spinach Avocado",
    613154: "Plum Stage 2 Grain Baby Food Sweet Potato Mango Millet",
    613458: "Plum Stage 2 Veg Blends Baby Food Kale Sweet Corn Quinoa",
    613544: "Plum Stage 2 Grain Baby Food Berry Barley",
    613610: "Plum Stage 2 Blends Baby Food Guava Pear Pumpkin",
    613754: "Plum Stage 3 Baby Food Sweet Corn Carrot Turkey",
    809238: "Plum Stage 2 Blends Baby Food Pumpkin Banana",
    809468: "Plum Stage 2 Grain Baby Food Zucchini Banana Amaranth",
    809634: "Plum Stage 2 Blends Baby Food Apple Blackberry Coconut",
    811096: "Plum Stage 2 Greek Yogurt Baby Food Raspberry Spinach",
    1461558: "Plum Stage 2 Greek Yogurt Baby Food Raspberry Spinach",
    1874863: "Now and Later Splits 2-in-1 Dual Flavor Chews, Lemon-Blue Raspberry",
    1728658: "2-in-1 Gummies Candy, Green Apple + Cherry, Blue Raspberry + Watermelon, Strawberry + Lemon",
    1881254: "Splits 2-in-1 Soft Chews, Lemonade Blends",
    2123463: "2-in-1 Gummies Misfits, Green Apple + Cherry, Blue Raspberry + Watermelon, Strawberry + Lemon",
    2153279: "2-in-1 Gummies Flavored Candy Misfits, Green Apple + Cherry, Blue Raspberry + Watermelon, Strawberry + Lemon",
    2165683: "2-in-1 Spout Sprinkle Mix",
    2170661: "2-in-1 Gummies Candy Misfits, Green Apple + Cherry, Blue Raspberry + Watermelon, Strawberry + Lemon",
    2187256: "Strawberry Banana Flavored 2-in-1 Dairy Snack",
    2187260: "Strawberry Vanilla Flavored 2-in-1 Dairy Snack",
    2269704: "2-in-1 Gummies, Green Apple + Cherry, Blue Raspberry + Watermelon, Strawberry + Lemon",
    2286996: "Strawberry Vanilla Flavored 2-in-1 Dairy Snack",
    2424704: "All Purpose Gluten Free 1-to-1 Baking Flour",
    2429028: "Gluten Free 1-to-1 Baking Flour",
    2632567: "1-to-1 Baking Flour",
    2703902: "Cheddar Cheese Enchilada with Whole Grain Corn Tortilla, CN Labeled",
    2704457: "Egg, Cheese and Turkey Sausage Wrap with Whole Grain Rich Tortilla, CN Labeled",
    917020: "Vanilla Bean Mallow Bar Dunked in Belgian M*LK Chocolate",
    2724869: "Maggi 2-Minute Noodles Mas",
    2734531: "Pillsbury Frozen Puff Pastry Dough Bulk Sheet 10x15 in",
    2734540: "Pillsbury Frozen Pie Crust Dough Bulk Sheet 10x12 in",
    2737151: "Bonici Frozen Parbaked Pizza Crust Flatbread Rustic Oval 6x9 in",
    2737178: "Bonici Frozen Parbaked Pizza Crust Flatbread Traditional Rectangle 6x13 in",
    2737755: "Pillsbury Frozen Puff Pastry Dough Bulk Square 5x5 in",
    1627758: "Mtn Dew Throwback",
    1457267: "20 Oz. and Up Lobster Tails",
    1458406: "Langostino Meat 60-90 ct",
    2369476: "You're the G.O.A.T! with Gummy Candy Hearts",
    2671760: "Original 7-in-1 Mixed Vegetables",
    2736792: "Wright Brand Naturally Hickory Smoked Thin Sliced Bacon, 9 Slices/Inch",
    1462145: "Litehouse Pour on the Taste White Balsamic Vinaigrette",
    2520750: "Litehouse Pour on the Taste Greek Vinaigrette",
    611744: "Similac Advance Stage 2 Powder",
    2626409: "Goat Milk Stage 3 for Toddlers 1 Year & Up",
}

ACRONYMS = {"BBQ", "CN", "CO", "GMO", "GF", "IPA", "USDA", "V8", "M*LK"}
SMALL_WORDS = {"a", "an", "and", "at", "by", "for", "in", "of", "on", "or", "the", "to", "up", "with"}
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
ADDITIONAL_SEAFOOD_GRADE_GTINS = frozenset({
    "00075391015230", "00075391015537", "00075391020036", "00075391020258",
    "00075391043820", "00075391045732", "00075391053812", "00075391058473",
    "00075391058480", "00075391058503", "00075391058510", "00075391940983",
    "00075391955345", "00075391955864", "00075391955895", "00075391965252",
    "00075391965962", "00075391971581", "00075391971901",
})
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
        "b3a4bf7903113ab5f0b8fb33895856159fba845a0885e7549b96bc772058740a",
        "10 and Up Whole Gutted Grouper",
    ),
    "00075391028360": (
        "8d00ee898ca82ec3cacae09bc2b5c971e2992121d2707890974fabb3964eea88",
        "8 and Up Canadian Snow Crab Cluster",
    ),
    "00075391028438": (
        "b7180b4aaf49a6d475bb0040fbf244d745db91ee8a9e1b08685f32b1a53b501d",
        "8 and Up Snow Crab Clusters",
    ),
    "00075391028919": (
        "859599fe1f68730c9957c9d8db7b18b8b6d484690639d3ef348cf401aabb565f",
        "150 and Up Gulf Peeled Undeveined Shrimp",
    ),
    "00075391031698": (
        "2c1e4a7ff12fa9a16a37483f6a244a77069d0bc15f1ceaf98e5238a6275811b2",
        "10 and Up Snow Crab Clusters",
    ),
    "00075391049709": (
        "b5bee97818edffc7d20b1dbd2c0540dcbc2d55a32a06cc6968b4362d5cef4ce3",
        "2 and Up Wahoo Loins",
    ),
    "00075391051085": (
        "c1a112640065a043d53896de124789c96be9d506d83820cb65ed3cf0cf421634",
        "10 Oz. and Up Flounder Fillets",
    ),
    "00075391060537": (
        "a3ecb9e4c1fdc7a5736dba5bb931ffaa55350ee7bfda7e33887835bdbd4a6ec8",
        "8 Oz. and Up Rockfish Fillet",
    ),
    "00075391943335": (
        "38808365e4bc05c64de735b51de5d557804cf9b8164d491256577b6b584d5fd0",
        "20 and Up Red King Crab Legs",
    ),
    "90075391009119": (
        "fa76fbf0a2a743019a6f523702e2384507ba140d736232d9f596018cb1527b56",
        "Beef Tenderloin PSMO, 5 and Up",
    ),
    "90075391035446": (
        "da0309ddc753011e5a681a2de934ca9d3ee42e1a5acc992e0070711e70923be3",
        "Beef Tenderloin CAB, 5 and Up",
    ),
    "90736490042543": (
        "038dd1c5f8251022d69d6527a0bc5ad93192a77b2dc28a291b4fd8bd05dd9ef5",
        "Pork Spareribs St. Louis Style Wide Cut, 3.25 and Up",
    ),
    "90736490042642": (
        "038dd1c5f8251022d69d6527a0bc5ad93192a77b2dc28a291b4fd8bd05dd9ef5",
        "Pork Spareribs St. Louis Style Wide Cut, 3.25 and Up",
    ),
}


@dataclass(frozen=True)
class Product:
    gtin14: str
    original_gtin: str
    original_length: int
    fdc_id: int
    source_description: str
    product_name: str
    family_id: str
    brand: str
    category: str
    data_source: str
    publication_date: str
    modified_date: str
    available_date: str
    discontinued_date: str
    market_country: str


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def valid_gtin(raw: str) -> tuple[str, str] | None:
    digits = "".join(character for character in raw if character.isdigit())
    if len(digits) not in {8, 12, 13, 14}:
        return None
    total = sum(int(digit) * (3 if index % 2 == 0 else 1) for index, digit in enumerate(reversed(digits[:-1])))
    if (10 - total % 10) % 10 != int(digits[-1]):
        return None
    return digits.zfill(14), digits


def clean_space(value: str) -> str:
    return re.sub(r"\s+", " ", value).strip()


def identity_stem(description: str) -> str:
    value = clean_space(description).casefold()
    previous = None
    while value != previous:
        previous = value
        value = PACKAGE_NOISE.sub("", value).strip(" ,-;")
    return value


def family_id(brand: str, description: str) -> str:
    key = f"{clean_space(brand).casefold()}|{identity_stem(description)}"
    return "usda:" + hashlib.sha256(key.encode("utf-8")).hexdigest()[:24]


def title_token(token: str, index: int) -> str:
    upper = token.upper()
    if upper in ACRONYMS:
        return upper
    if re.fullmatch(r"\d+(?:[-/]\d+)*(?:-IN-1|-TO-1)?", upper):
        return token.lower()
    lowered = token.lower()
    if index and lowered in SMALL_WORDS:
        return lowered
    if token.startswith("G.O.A.T"):
        return token.replace("G.o.a.t", "G.O.A.T")
    return lowered[:1].upper() + lowered[1:]


@functools.lru_cache(maxsize=1)
def semantic_manifest() -> dict[str, tuple[str, str, str]]:
    """Return the 152 source-gated names approved by human review."""
    manifest = Path(__file__).with_name("semantic_mask_2026-04-30.csv")
    with manifest.open(encoding="utf-8", newline="") as source:
        rows = list(csv.DictReader(source))
    expected = Counter({"piece_rate": 77, "fish_grade": 61, "reviewed_grade": 13, "slices_per_inch": 1})
    if Counter(row.get("reason", "") for row in rows) != expected:
        raise SystemExit("Frozen semantic manifest must contain the reviewed 77 + 61 + 13 + 1 identities")
    if len(rows) != 152 or len({row.get("gtin14", "") for row in rows}) != 152:
        raise SystemExit("Frozen semantic manifest must contain 152 unique GTIN identities")
    result: dict[str, tuple[str, str, str]] = {}
    for row in rows:
        gtin14 = row.get("gtin14", "")
        source_hash = row.get("source_sha256", "")
        product_name = row.get("product_name", "")
        if not re.fullmatch(r"\d{14}", gtin14):
            raise SystemExit(f"Invalid semantic GTIN: {gtin14!r}")
        if not re.fullmatch(r"[0-9a-f]{64}", source_hash):
            raise SystemExit(f"Invalid semantic source hash for {gtin14}")
        if not clean_space(product_name):
            raise SystemExit(f"Blank semantic product name for {gtin14}")
        result[gtin14] = (row["reason"], source_hash, product_name)
    return result


def normalized_seafood_grade(raw: str) -> str:
    value = clean_space(raw).upper().replace("CNT", "CT")
    value = re.sub(r"\s*/\s*", "/", value)
    value = re.sub(r"\s*-\s*", "-", value)
    match = re.fullmatch(r"(.+?)\s*(OZ\.?|CT\.?)\s*(?:/(UP|KG))?", value)
    if match is None:
        raise SystemExit(f"Unrecognized reviewed seafood grade: {raw!r}")
    quantity, unit, suffix = match.groups()
    if unit.startswith("CT"):
        return f"{quantity} Count per kg" if suffix == "KG" else f"{quantity} Count"
    if suffix == "UP":
        return f"{quantity} Oz. and Up"
    if suffix == "KG":
        return f"{quantity} Oz. per kg"
    return f"{quantity} Oz."


def expand_seafood_abbreviations(value: str) -> str:
    replacements = (
        (r"\bCkd P&d T/on\b", "Cooked Peeled & Deveined Tail-On"),
        (r"\bCpd T/off\b", "Cooked Peeled & Deveined Tail-Off"),
        (r"\bCp&d\b", "Cooked Peeled & Deveined"),
        (r"\bCkd P&d\b", "Cooked Peeled & Deveined"),
        (r"\bCpto\b", "Cooked Peeled Tail-On"),
        (r"\bP&d T/on\b", "Peeled & Deveined Tail-On"),
        (r"\bP\s*&\s*D\b", "Peeled & Deveined"),
        (r"\bIqf\b", "Individually Quick Frozen"),
        (r"\bS/on\b|\bS/o\b", "Shell-On"),
        (r"\bDom\b", "Domestic"),
        (r"\bWht\b", "White"),
        (r"\bBrd\b", "Breaded"),
        (r"\bBlk\b", "Block"),
        (r"\bCnt\b|\bCt\.?\b", "Count"),
        (r"\bBd Btfly\b", "Breaded Butterfly"),
        (r"\b(?:Ez|E-z|E/z) Peel/eat\b", "Easy Peel-and-Eat"),
        (r"\b(?:Ez|E-z|E/z) Peel\b", "Easy-Peel"),
        (r"\bV/p\b", "Vacuum-Packed"),
        (r"\bF/w\b", "F/W"),
        (r"\bH/on\b", "Head-On"),
    )
    for pattern, replacement in replacements:
        value = re.sub(pattern, replacement, value, flags=re.IGNORECASE)
    tokens = re.split(r"(\s+)", value)
    for index, token in enumerate(tokens):
        core = token.strip("\"'(),.-")
        if core.isalpha() and core.isupper() and core not in ACRONYMS:
            tokens[index] = token.replace(core, core.capitalize())
    return clean_space("".join(tokens))


def human_name(fdc_id: int, description: str, gtin14: str | None = None, category: str = "") -> str:
    reviewed = semantic_manifest().get(gtin14 or "")
    if reviewed is not None:
        _, expected_hash, product_name = reviewed
        if hashlib.sha256(description.encode("utf-8")).hexdigest() != expected_hash:
            raise SystemExit(f"Semantic-name source gate changed for GTIN {gtin14}")
        return product_name
    targeted = TARGETED_SEMANTIC_NAMES.get(gtin14 or "")
    if targeted is not None:
        expected_hash, product_name = targeted
        if hashlib.sha256(description.encode("utf-8")).hexdigest() != expected_hash:
            raise SystemExit(f"Targeted semantic-name source gate changed for GTIN {gtin14}")
        return product_name
    if fdc_id in FROZEN_CORRECTION_OUTPUTS:
        return FROZEN_CORRECTION_OUTPUTS[fdc_id]
    value = clean_space(description)
    leading_grade: str | None = None
    is_seafood = bool(SEAFOOD_CATEGORY.search(category)) or (gtin14 or "") in ADDITIONAL_SEAFOOD_GRADE_GTINS
    if is_seafood:
        grade_match = SEAFOOD_LEADING_GRADE.match(value)
        if grade_match is not None:
            leading_grade = normalized_seafood_grade(grade_match.group(1))
            value = value[grade_match.end():].lstrip(" ,-;")
    if fdc_id in FROZEN_CORRECTION_HASHES:
        value = re.sub(r"\bSTAGE\s*([23])\b", r"Stage \1", value, flags=re.IGNORECASE)
        value = re.sub(r"\b2\s*IN\s*1\b|\b2IN1\b", "2-in-1", value, flags=re.IGNORECASE)
        value = re.sub(r"\b1\s*TO\s*1\b", "1-to-1", value, flags=re.IGNORECASE)
        value = re.sub(r"\b2\s*-?\s*MINUTE\b", "2-Minute", value, flags=re.IGNORECASE)
        value = re.sub(r"\bCN\s+LABELED\b", "CN Labeled", value, flags=re.IGNORECASE)
    value = re.sub(r"\[\s*Alternate ID\s*:[^\]]+\]", "", value, flags=re.IGNORECASE)
    value = re.sub(
        r"(?<![\d.#])\d+\s+\d+\s*/\s*\d+\s*(?:fl\.?\s*oz|floz|oz|ounces?|lbs?|pounds?|grams?|g|kg|ml|liters?|l)\b",
        "",
        value,
        flags=re.IGNORECASE,
    )
    value = re.sub(
        r"(?<![\d.])(?:\d+(?:\.\d+)?|\.\d+)\s*/\s*(?:\d+(?:\.\d+)?|\.\d+)\s*(?:fl\.?\s*oz|floz|oz|ounces?|lbs?|pounds?|grams?|g|kg|ml|liters?|l)\b",
        "",
        value,
        flags=re.IGNORECASE,
    )
    value = re.sub(
        r"(?<![\d.])(?:\d+(?:\.\d+)?|\.\d+)\s*(?:fl\.?\s*oz|floz|oz|ounces?|lbs?|pounds?|grams?|g|kg|ml|liters?|l)\b",
        "",
        value,
        flags=re.IGNORECASE,
    )
    value = re.sub(r"\b\d+\s*[x×]\s*\d+\s*(?:pack|pk|count|ct)\b", "", value, flags=re.IGNORECASE)
    value = re.sub(r"\b\d+\s*(?:pack|pk)\b", "", value, flags=re.IGNORECASE)
    value = re.sub(
        r"\(?\b\d+(?:\s*[-/]\s*\d+)*\s*(?:count|cnt|ct|pieces?|slices?)(?:\s+per\s+(?:package|case|box|bag|carton))?(?:\s+(?:ea|each))?\b\)?",
        "",
        value,
        flags=re.IGNORECASE,
    )
    value = re.sub(r",?\s*\d+(?:/\d+)*\s*/\s*\.?(?=,|$)", "", value)
    value = re.sub(r"\(\s*[.,]?\s*\)", "", value)
    value = re.sub(r",\s*\.\s*(?=,|$)", "", value)
    value = re.sub(r"\s+([,.;])", r"\1", value)
    value = re.sub(r",(?:\s*,)+", ",", value)
    value = re.sub(r"\s{2,}", " ", value).strip(" ,-;")
    previous = None
    while value != previous:
        previous = value
        value = PACKAGE_NOISE.sub("", value).strip(" ,-;")
    value = re.sub(r",?\s*\d+(?:/\d+)*\s*/\s*$", "", value).strip(" ,-;")
    value = re.sub(r"(?:,\s*)?\.(?=\s*(?:,|$))", "", value)
    value = re.sub(r"(?<!\w)\.(?!\w)", "", value)
    value = re.sub(r"\s+([,.;])", r"\1", value).strip(" ,-;")
    parts = [part.strip() for part in value.split(",")]
    if len(parts) > 1 and parts[-1].casefold() in {part.casefold() for part in parts[:-1]}:
        parts.pop()
    value = ", ".join(part for part in parts if part)
    if value.isupper() or sum(c.isupper() for c in value) > sum(c.islower() for c in value) * 2:
        tokens = re.split(r"(\s+)", value)
        word_index = 0
        converted = []
        for token in tokens:
            if token.isspace():
                converted.append(token)
            else:
                converted.append(title_token(token, word_index))
                word_index += 1
        value = "".join(converted)
    value = value.replace("Mtn dew", "Mtn Dew").replace("M*lk", "M*LK")
    value = re.sub(r"\b(\d+)\s*CT\b", r"\1 ct", value, flags=re.IGNORECASE)
    value = re.sub(r"\b([A-Za-z]+)-\s+([A-Za-z]+)\b", r"\1-\2", value)
    if is_seafood:
        value = expand_seafood_abbreviations(value)
    if leading_grade is not None:
        value = f"{leading_grade} {value}".strip()
    return clean_space(value)


def csv_member(archive: zipfile.ZipFile, suffix: str) -> str:
    matches = [name for name in archive.namelist() if name.endswith("/" + suffix) or name == suffix]
    if len(matches) != 1:
        raise SystemExit(f"Expected one {suffix} in the official archive; found {len(matches)}")
    return matches[0]


def selected_branded_rows(archive: zipfile.ZipFile) -> dict[str, dict[str, str]]:
    latest: dict[str, tuple[tuple[str, str, int], dict[str, str], str]] = {}
    with archive.open(csv_member(archive, "branded_food.csv")) as raw:
        reader = csv.DictReader(io.TextIOWrapper(raw, encoding="utf-8-sig", errors="strict", newline=""))
        for row in reader:
            if clean_space(row.get("market_country", "")) != "United States":
                continue
            normalized = valid_gtin(row.get("gtin_upc", ""))
            if normalized is None:
                continue
            gtin14, original = normalized
            key = (row.get("modified_date", ""), row.get("available_date", ""), int(row.get("fdc_id") or 0))
            if gtin14 not in latest or key > latest[gtin14][0]:
                latest[gtin14] = (key, row, original)
    selected = {
        gtin14: {**row, "_original_gtin": original}
        for gtin14, (_, row, original) in latest.items()
        if not clean_space(row.get("discontinued_date", ""))
        and not (len(original) == 8 and original[0] in "01")
    }
    if len(selected) != EXPECTED_COUNT:
        raise SystemExit(f"Selection mismatch: expected {EXPECTED_COUNT:,}, got {len(selected):,}")
    lengths = Counter(len(row["_original_gtin"]) for row in selected.values())
    if dict(lengths) != EXPECTED_LENGTHS:
        raise SystemExit(f"Original GTIN-length mismatch: {dict(sorted(lengths.items()))}")
    return selected


def build_products(archive: zipfile.ZipFile, selected: dict[str, dict[str, str]]) -> list[Product]:
    by_fdc = {row["fdc_id"]: (gtin14, row) for gtin14, row in selected.items()}
    products: list[Product] = []
    seen_corrections: set[int] = set()
    with archive.open(csv_member(archive, "food.csv")) as raw:
        reader = csv.DictReader(io.TextIOWrapper(raw, encoding="utf-8-sig", errors="strict", newline=""))
        for food in reader:
            joined = by_fdc.get(food.get("fdc_id", ""))
            if joined is None:
                continue
            gtin14, branded = joined
            description = food.get("description", "")
            fdc_id = int(food["fdc_id"])
            if not description:
                raise SystemExit(f"USDA source description is blank for {fdc_id}")
            expected_hash = FROZEN_CORRECTION_HASHES.get(fdc_id)
            if expected_hash is not None:
                actual_hash = hashlib.sha256(description.encode("utf-8")).hexdigest()
                if actual_hash != expected_hash:
                    raise SystemExit(f"Frozen correction source gate changed for USDA {fdc_id}")
                seen_corrections.add(fdc_id)
            brand = clean_space(branded.get("brand_name") or branded.get("brand_owner") or "")
            category = clean_space(branded.get("branded_food_category", ""))
            products.append(Product(
                gtin14=gtin14,
                original_gtin=branded["_original_gtin"],
                original_length=len(branded["_original_gtin"]),
                fdc_id=fdc_id,
                source_description=description,
                product_name=human_name(fdc_id, description, gtin14, category),
                family_id=family_id(brand, description),
                brand=brand,
                category=category,
                data_source=clean_space(branded.get("data_source", "")),
                publication_date=clean_space(food.get("publication_date", "")),
                modified_date=clean_space(branded.get("modified_date", "")),
                available_date=clean_space(branded.get("available_date", "")),
                discontinued_date=clean_space(branded.get("discontinued_date", "")),
                market_country="US",
            ))
    missing = set(FROZEN_CORRECTION_HASHES) - seen_corrections
    if missing:
        raise SystemExit(f"Frozen corrections are absent from selection: {sorted(missing)}")
    if len(products) != EXPECTED_COUNT:
        raise SystemExit(f"Food join mismatch: expected {EXPECTED_COUNT:,}, got {len(products):,}")
    return sorted(products, key=lambda product: product.gtin14)


def semantic_masks(products: list[Product]) -> list[tuple[str, str, str, str]]:
    """Verify every reviewed identity, raw source hash, and exact output."""
    by_gtin = {product.gtin14: product for product in products}
    masks: list[tuple[str, str, str, str]] = []
    for gtin14, (reason, source_hash, product_name) in semantic_manifest().items():
        product = by_gtin.get(gtin14)
        if product is None:
            raise SystemExit(f"Frozen semantic identity is absent from selection: {gtin14}")
        if hashlib.sha256(product.source_description.encode("utf-8")).hexdigest() != source_hash:
            raise SystemExit(f"Frozen semantic source gate changed for GTIN {gtin14}")
        if product.product_name != product_name:
            raise SystemExit(f"Frozen semantic output changed for GTIN {gtin14}")
        masks.append((gtin14, reason, source_hash, product_name))
    return sorted(masks)


def identity_digest(products: list[Product]) -> str:
    digest = hashlib.sha256()
    for product in products:
        fields = (
            product.gtin14, product.original_gtin, str(product.original_length), str(product.fdc_id),
            product.source_description, product.family_id, product.brand, product.category,
            product.data_source, product.publication_date, product.modified_date,
            product.available_date, product.discontinued_date, product.market_country,
        )
        digest.update("\x1f".join(fields).encode("utf-8"))
        digest.update(b"\n")
    return digest.hexdigest()


def write_database(products: list[Product], masks: list[tuple[str, str, str, str]], output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    handle, temporary_name = tempfile.mkstemp(prefix="catalogue-", suffix=".sqlite3", dir=output.parent)
    os.close(handle)
    temporary = Path(temporary_name)
    try:
        connection = sqlite3.connect(temporary)
        connection.executescript("""
            PRAGMA journal_mode=OFF;
            PRAGMA synchronous=OFF;
            PRAGMA temp_store=MEMORY;
            CREATE TABLE products (
                gtin14 TEXT PRIMARY KEY NOT NULL,
                original_gtin TEXT NOT NULL,
                original_gtin_length INTEGER NOT NULL,
                usda_fdc_id TEXT NOT NULL UNIQUE,
                source_description TEXT NOT NULL,
                product_name TEXT NOT NULL,
                family_id TEXT NOT NULL,
                brand TEXT NOT NULL DEFAULT '',
                category TEXT NOT NULL DEFAULT '',
                data_source TEXT NOT NULL,
                publication_date TEXT NOT NULL,
                modified_date TEXT NOT NULL,
                available_date TEXT NOT NULL,
                discontinued_date TEXT NOT NULL DEFAULT '',
                market_country TEXT NOT NULL CHECK (market_country = 'US')
            ) WITHOUT ROWID;
            CREATE INDEX idx_products_family ON products(family_id);
            CREATE INDEX idx_products_name ON products(product_name COLLATE NOCASE);
            CREATE TABLE corrections (
                usda_fdc_id TEXT PRIMARY KEY,
                source_sha256 TEXT NOT NULL,
                product_name TEXT NOT NULL
            ) WITHOUT ROWID;
            CREATE TABLE semantic_masks (
                gtin14 TEXT PRIMARY KEY,
                reason TEXT NOT NULL,
                source_sha256 TEXT NOT NULL,
                product_name TEXT NOT NULL
            ) WITHOUT ROWID;
            CREATE TABLE metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL) WITHOUT ROWID;
        """)
        connection.executemany(
            "INSERT INTO products VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
            [(p.gtin14, p.original_gtin, p.original_length, str(p.fdc_id), p.source_description,
              p.product_name, p.family_id, p.brand, p.category, p.data_source, p.publication_date,
              p.modified_date, p.available_date, p.discontinued_date, p.market_country) for p in products],
        )
        by_id = {p.fdc_id: p for p in products}
        connection.executemany(
            "INSERT INTO corrections VALUES (?,?,?)",
            [(str(fdc_id), source_hash, by_id[fdc_id].product_name) for fdc_id, source_hash in sorted(FROZEN_CORRECTION_HASHES.items())],
        )
        connection.executemany("INSERT INTO semantic_masks VALUES (?,?,?,?)", masks)
        metadata = {
            "archive_sha256": ARCHIVE_SHA256,
            "source_url": SOURCE_URL,
            "release_date": RELEASE_DATE,
            "license": LICENSE,
            "selection": "market_country=United States; valid 8/12/13/14 GTIN; reject ambiguous 8-digit 0/1; latest modified/available/fdc identity; no discontinued date",
            "selected_count": str(EXPECTED_COUNT),
            "original_gtin_lengths": json.dumps(EXPECTED_LENGTHS, sort_keys=True),
            "correction_count": str(len(FROZEN_CORRECTION_HASHES)),
            "semantic_mask_count": str(len(masks)),
            "identity_digest_sha256": identity_digest(products),
        }
        connection.executemany("INSERT INTO metadata VALUES (?,?)", sorted(metadata.items()))
        connection.commit()
        if connection.execute("PRAGMA integrity_check").fetchone()[0] != "ok":
            raise SystemExit("Built catalogue failed SQLite integrity_check")
        connection.execute("ANALYZE")
        connection.execute("VACUUM")
        connection.close()
        os.replace(temporary, output)
    finally:
        temporary.unlink(missing_ok=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("archive", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    arguments = parser.parse_args()
    actual_hash = sha256_file(arguments.archive)
    if actual_hash != ARCHIVE_SHA256:
        raise SystemExit(f"Official archive hash mismatch: expected {ARCHIVE_SHA256}, got {actual_hash}")
    with zipfile.ZipFile(arguments.archive) as archive:
        selected = selected_branded_rows(archive)
        products = build_products(archive, selected)
    masks = semantic_masks(products)
    write_database(products, masks, arguments.output)
    print(f"Wrote {len(products):,} official USDA products to {arguments.output}")


if __name__ == "__main__":
    main()
