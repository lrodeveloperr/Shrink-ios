#!/usr/bin/env python3
"""Build the compact, read-only iOS catalogue from Open Food Facts-style CSV.

The app only needs identity and package quantity. This intentionally drops images,
nutrition, ingredients and prices. The output schema is stable for the Swift app.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import heapq
import re
import sqlite3
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable


TARGET_CATEGORY_WORDS = {
    "snack", "chip", "crisp", "biscuit", "cookie", "chocolate", "candy",
    "cereal", "coffee", "tea", "beverage", "soda", "juice", "dairy",
    "frozen", "canned", "sauce", "spread", "condiment", "bakery",
    "detergent", "cleaning", "toilet-paper", "paper-towel", "garbage-bag",
    "shampoo", "soap", "toothpaste", "deodorant", "diaper", "wipe",
    "pet-food", "pet-treat",
}

UNIT_ALIASES = {
    "g": "g", "gram": "g", "grams": "g", "gramo": "g", "gramos": "g", "gramme": "g", "grammes": "g",
    "kg": "kg", "kilogram": "kg", "kilograms": "kg", "kilogramo": "kg", "kilogramos": "kg", "kilogramme": "kg", "kilogrammes": "kg",
    "oz": "oz", "ounce": "oz", "ounces": "oz", "onza": "oz", "onzas": "oz",
    "lb": "lb", "lbs": "lb", "pound": "lb", "pounds": "lb", "libra": "lb", "libras": "lb", "livre": "lb", "livres": "lb",
    "ml": "mL", "milliliter": "mL", "milliliters": "mL", "millilitre": "mL", "millilitres": "mL", "mililitro": "mL", "mililitros": "mL",
    "l": "L", "liter": "L", "liters": "L", "litre": "L", "litres": "L", "litro": "L", "litros": "L",
    "fl oz": "fl oz", "floz": "fl oz", "onza líquida": "fl oz", "onzas líquidas": "fl oz", "once liquide": "fl oz", "onces liquides": "fl oz",
    "ct": "items", "count": "items", "item": "items", "items": "items", "unidad": "items", "unidades": "items", "article": "items", "articles": "items",
    "sheet": "sheets", "sheets": "sheets", "hoja": "sheets", "hojas": "sheets", "feuille": "sheets", "feuilles": "sheets",
    "roll": "rolls", "rolls": "rolls", "rollo": "rolls", "rollos": "rolls", "rouleau": "rolls", "rouleaux": "rolls",
    "load": "loads", "loads": "loads", "carga": "loads", "cargas": "loads", "brassée": "loads", "brassées": "loads",
    "pod": "pods", "pods": "pods", "cápsula": "pods", "cápsulas": "pods",
    "wipe": "wipes", "wipes": "wipes", "toallita": "wipes", "toallitas": "wipes", "lingette": "wipes", "lingettes": "wipes",
    "bag": "bags", "bags": "bags", "bolsa": "bags", "bolsas": "bags", "sac": "bags", "sacs": "bags",
    "capsule": "capsules", "capsules": "capsules", "pastilla": "capsules", "pastillas": "capsules", "comprimé": "capsules", "comprimés": "capsules",
}

QUANTITY_RE = re.compile(
    r"^\s*(?:(\d+)\s*[x×]\s*)?([0-9]+(?:[.,][0-9]+)?)\s*"
    r"(onzas?\s+líquidas?|onces?\s+liquides?|fl\s*oz|floz|kilogramos?|kilogrammes?|kg|gramos?|grammes?|g|mililitros?|millilitres?|ml|litros?|litres?|l|onzas?|oz|libras?|livres?|lbs?|unidades?|articles?|ct|count|items?|hojas?|feuilles?|sheets?|rollos?|rouleaux?|rolls?|cargas?|brassées?|loads?|cápsulas?|pods?|toallitas?|lingettes?|wipes?|bolsas?|sacs?|bags?|pastillas?|comprimés?|capsules?)\b",
    re.IGNORECASE,
)


def gtin_is_valid(code: str) -> bool:
    if len(code) not in (8, 12, 13, 14) or not code.isdigit():
        return False
    body = reversed(code[:-1])
    total = sum(int(digit) * (3 if index % 2 == 0 else 1) for index, digit in enumerate(body))
    return (10 - total % 10) % 10 == int(code[-1])


def normalize_gtin(raw: str) -> str | None:
    code = "".join(character for character in raw if character.isdigit())
    if not gtin_is_valid(code):
        return None
    if len(code) == 8:
        return "0" * 6 + code
    if len(code) == 12:
        return "00" + code
    if len(code) == 13:
        return "0" + code
    return code


def parse_quantity(raw: str) -> tuple[float, str, int] | None:
    match = QUANTITY_RE.search(raw or "")
    if not match:
        return None
    pack_count = int(match.group(1) or 1)
    value = float(match.group(2).replace(",", "."))
    key = re.sub(r"\s+", " ", match.group(3).lower()).strip()
    unit = UNIT_ALIASES.get(key)
    if not unit or value <= 0 or pack_count <= 0:
        return None
    return value, unit, pack_count


def clean(value: str | None) -> str:
    return re.sub(r"\s+", " ", value or "").strip()


def family_id(brand: str, name: str, variant: str) -> str:
    key = "|".join(clean(value).casefold() for value in (brand, name, variant))
    return "catalogue:" + hashlib.sha256(key.encode("utf-8")).hexdigest()[:24]


@dataclass(order=True)
class RankedProduct:
    score: float
    gtin14: str = field(compare=False)
    family: str = field(compare=False)
    name: str = field(compare=False)
    name_es: str = field(compare=False)
    name_fr: str = field(compare=False)
    brand: str = field(compare=False)
    variant: str = field(compare=False)
    quantity_value: float = field(compare=False)
    quantity_unit: str = field(compare=False)
    pack_count: int = field(compare=False)
    category: str = field(compare=False)
    market: str = field(compare=False)
    updated_at: int = field(compare=False)


def market_for(row: dict[str, str]) -> str | None:
    fields = " ".join([
        row.get("countries_tags", ""), row.get("countries", ""), row.get("market", "")
    ]).casefold()
    markets = []
    if any(token in fields for token in (
        "en:united-states", "united states", "usa", "us,",
        "en:puerto-rico", "puerto rico",
    )):
        markets.append("US")
    if any(token in fields for token in ("en:canada", "canada", "ca,")):
        markets.append("CA")
    return ",".join(markets) or None


def rank(row: dict[str, str], category: str, updated_at: int) -> float:
    category_folded = category.casefold()
    category_bonus = 50 if any(word in category_folded for word in TARGET_CATEGORY_WORDS) else 0
    scan_count = float(row.get("unique_scans_n") or row.get("scans_n") or 0)
    completeness = sum(bool(clean(row.get(key))) for key in ("product_name", "brands", "quantity")) * 10
    recency = min(max((updated_at - 1_577_836_800) / 31_536_000, 0), 10)
    return category_bonus + completeness + min(scan_count, 10_000) ** 0.5 + recency


def read_products(paths: Iterable[Path], max_records: int) -> list[RankedProduct]:
    heap: list[RankedProduct] = []
    seen: set[str] = set()
    for path in paths:
        with path.open("r", encoding="utf-8", errors="replace", newline="") as source:
            sample = source.read(16_384)
            source.seek(0)
            try:
                dialect = csv.Sniffer().sniff(sample, delimiters="\t,;")
            except csv.Error:
                dialect = csv.excel_tab if "\t" in sample else csv.excel
            for row in csv.DictReader(source, dialect=dialect):
                gtin = normalize_gtin(row.get("code") or row.get("barcode") or row.get("gtin14") or "")
                if not gtin or gtin in seen:
                    continue
                name = clean(row.get("product_name_en") or row.get("product_name") or row.get("name"))
                name_es = clean(row.get("product_name_es"))
                name_fr = clean(row.get("product_name_fr"))
                quantity = parse_quantity(row.get("quantity") or row.get("package_size") or "")
                market = market_for(row)
                if not name or not quantity or not market:
                    continue
                brand = clean(row.get("brands") or row.get("brand"))
                variant = clean(row.get("variant"))
                category = clean(row.get("categories_tags") or row.get("categories") or row.get("category"))
                updated_at = int(float(row.get("last_modified_t") or row.get("updated_at") or 0))
                value, unit, pack_count = quantity
                product = RankedProduct(
                    score=rank(row, category, updated_at), gtin14=gtin,
                    family=family_id(brand, name, variant), name=name,
                    name_es=name_es, name_fr=name_fr, brand=brand,
                    variant=variant, quantity_value=value, quantity_unit=unit,
                    pack_count=pack_count, category=category, market=market,
                    updated_at=updated_at,
                )
                seen.add(gtin)
                if max_records <= 0:
                    heap.append(product)
                elif len(heap) < max_records:
                    heapq.heappush(heap, product)
                elif product.score > heap[0].score:
                    heapq.heapreplace(heap, product)
    return sorted(heap, key=lambda product: (-product.score, product.gtin14))


def build_database(products: list[RankedProduct], output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    if output.exists():
        output.unlink()
    connection = sqlite3.connect(output)
    connection.executescript("""
        PRAGMA journal_mode=OFF;
        PRAGMA synchronous=OFF;
        PRAGMA temp_store=MEMORY;
        CREATE TABLE products (
            gtin14 TEXT PRIMARY KEY NOT NULL,
            family_id TEXT NOT NULL,
            product_name TEXT NOT NULL,
            product_name_es TEXT NOT NULL DEFAULT '',
            product_name_fr TEXT NOT NULL DEFAULT '',
            brand TEXT NOT NULL DEFAULT '',
            variant TEXT NOT NULL DEFAULT '',
            quantity_value REAL NOT NULL,
            quantity_unit TEXT NOT NULL,
            pack_count INTEGER NOT NULL DEFAULT 1,
            category TEXT NOT NULL DEFAULT '',
            market TEXT NOT NULL,
            updated_at INTEGER NOT NULL DEFAULT 0
        ) WITHOUT ROWID;
        CREATE INDEX idx_products_family ON products(family_id);
    """)
    connection.executemany(
        "INSERT INTO products VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        [
            (p.gtin14, p.family, p.name, p.name_es, p.name_fr, p.brand, p.variant, p.quantity_value,
             p.quantity_unit, p.pack_count, p.category, p.market, p.updated_at)
            for p in products
        ],
    )
    connection.commit()
    connection.execute("ANALYZE")
    connection.execute("VACUUM")
    connection.close()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("inputs", nargs="+", type=Path, help="Open Food Facts-style CSV/TSV files")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--max-records", type=int, default=500_000, help="0 keeps every eligible record")
    arguments = parser.parse_args()
    products = read_products(arguments.inputs, arguments.max_records)
    build_database(products, arguments.output)
    size_mb = arguments.output.stat().st_size / 1_048_576
    print(f"Wrote {len(products):,} products to {arguments.output} ({size_mb:.1f} MiB)")


if __name__ == "__main__":
    main()
