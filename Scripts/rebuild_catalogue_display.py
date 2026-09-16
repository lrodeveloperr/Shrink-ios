#!/usr/bin/env python3
"""Rebuild only reviewed display names from the validated bundled catalogue.

This path exists for source-gated display-name corrections when the immutable
official USDA archive is not present locally. It refuses any database whose
non-display identity digest is not the locked April 30, 2026 selection.
"""

from __future__ import annotations

import argparse
from pathlib import Path
import sqlite3

from build_catalogue import (
    ARCHIVE_SHA256,
    EXPECTED_COUNT,
    Product,
    human_name,
    identity_digest,
    semantic_masks,
    write_database,
)


EXPECTED_IDENTITY_DIGEST = "e26f12ba18709f761423bf458ab4f5083d5ed64c37f617c3d644b52255a7a364"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    arguments = parser.parse_args()
    if arguments.source.resolve() == arguments.output.resolve():
        raise SystemExit("Source and output must differ; validate before replacing the bundled database")

    with sqlite3.connect(f"file:{arguments.source}?mode=ro", uri=True) as db:
        db.row_factory = sqlite3.Row
        if db.execute("PRAGMA integrity_check").fetchone()[0] != "ok":
            raise SystemExit("Source catalogue failed SQLite integrity_check")
        metadata = dict(db.execute("SELECT key, value FROM metadata"))
        if metadata.get("archive_sha256") != ARCHIVE_SHA256:
            raise SystemExit("Source catalogue is not the locked official archive selection")
        rows = list(db.execute("SELECT * FROM products ORDER BY gtin14"))

    if len(rows) != EXPECTED_COUNT:
        raise SystemExit(f"Expected {EXPECTED_COUNT:,} products, found {len(rows):,}")
    products = [
        Product(
            gtin14=row["gtin14"],
            original_gtin=row["original_gtin"],
            original_length=row["original_gtin_length"],
            fdc_id=int(row["usda_fdc_id"]),
            source_description=row["source_description"],
            product_name=human_name(
                int(row["usda_fdc_id"]), row["source_description"], row["gtin14"], row["category"]
            ),
            family_id=row["family_id"],
            brand=row["brand"],
            category=row["category"],
            data_source=row["data_source"],
            publication_date=row["publication_date"],
            modified_date=row["modified_date"],
            available_date=row["available_date"],
            discontinued_date=row["discontinued_date"],
            market_country=row["market_country"],
        )
        for row in rows
    ]
    actual_identity = identity_digest(products)
    if actual_identity != EXPECTED_IDENTITY_DIGEST or metadata.get("identity_digest_sha256") != actual_identity:
        raise SystemExit("Source catalogue non-display identity differs from the locked selection")

    masks = semantic_masks(products)
    write_database(products, masks, arguments.output)
    print(f"Rebuilt {len(products):,} display names without changing catalogue identity")


if __name__ == "__main__":
    main()
