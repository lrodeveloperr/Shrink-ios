#!/usr/bin/env python3
"""Validate Apple .strings key parity, duplicates, and format placeholders."""

from __future__ import annotations

import re
import sys
import plistlib
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1] / "App" / "Resources"
LOCALES = ("en", "es-419")
LINE = re.compile(r'^\s*"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)";\s*$')
PLACEHOLDER = re.compile(r"%(?:\d+\$)?(?:@|lld|ld|d|\.\d+f|f)")
SWIFT_LITERAL = re.compile(r'AppLocalization\.text\("([^"]+)"')


def read_strings(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        line = raw.strip()
        if not line or line.startswith("//"):
            continue
        match = LINE.match(raw)
        if not match:
            raise ValueError(f"{path}:{number}: invalid .strings syntax")
        key, value = match.groups()
        if key in values:
            raise ValueError(f"{path}:{number}: duplicate key {key!r}")
        values[key] = value
    return values


def main() -> int:
    localized = {
        locale: read_strings(ROOT / f"{locale}.lproj" / "Localizable.strings")
        for locale in LOCALES
    }
    base_keys = set(localized["en"])
    errors: list[str] = []
    for locale in LOCALES[1:]:
        keys = set(localized[locale])
        missing = sorted(base_keys - keys)
        extra = sorted(keys - base_keys)
        if missing:
            errors.append(f"{locale}: missing keys: {', '.join(missing)}")
        if extra:
            errors.append(f"{locale}: unexpected keys: {', '.join(extra)}")
        for key in sorted(base_keys & keys):
            expected = PLACEHOLDER.findall(localized["en"][key])
            actual = PLACEHOLDER.findall(localized[locale][key])
            if expected != actual:
                errors.append(f"{locale}: placeholder mismatch for {key!r}: {expected} != {actual}")

    for locale in LOCALES:
        read_strings(ROOT / f"{locale}.lproj" / "InfoPlist.strings")

    plural_keys: dict[str, set[str]] = {}
    required_plural_keys = {"radar.caught_today_format"}
    for locale in LOCALES:
        path = ROOT / f"{locale}.lproj" / "Localizable.stringsdict"
        with path.open("rb") as stream:
            plural_data = plistlib.load(stream)
        plural_keys[locale] = set(plural_data)
        if plural_keys[locale] != required_plural_keys:
            errors.append(f"{locale}: plural keys must be {sorted(required_plural_keys)}")
        for key, entry in plural_data.items():
            variable_name = entry.get("NSStringLocalizedFormatKey", "").replace("%#@", "").replace("@", "")
            variable = entry.get(variable_name, {})
            if variable.get("NSStringFormatSpecTypeKey") != "NSStringPluralRuleType":
                errors.append(f"{locale}: {key!r} is not a plural rule")
            for form in ("one", "other"):
                if form not in variable:
                    errors.append(f"{locale}: {key!r} is missing plural form {form!r}")

    app_root = ROOT.parent
    swift_keys: set[str] = set()
    for path in app_root.rglob("*.swift"):
        swift_keys.update(SWIFT_LITERAL.findall(path.read_text(encoding="utf-8")))
    literal_swift_keys = {key for key in swift_keys if "\\(" not in key}
    missing_swift_keys = sorted(literal_swift_keys - base_keys - required_plural_keys)
    if missing_swift_keys:
        errors.append(f"Swift uses missing localization keys: {', '.join(missing_swift_keys)}")

    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    if len(base_keys) != 198:
        errors.append(f"Expected exactly 198 string keys, found {len(base_keys)}")

    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    print(f"Localization checks passed: {len(base_keys)} strings and one plural across {', '.join(LOCALES)}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
