#!/usr/bin/env python3
"""Build the public US English and Puerto Rico Spanish policy pages."""

from __future__ import annotations

import html
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUTPUT_ROOT = ROOT / "WebsitePolicies" / "public" / "apps" / "shrinkflation-price-scanner"
BASE = "/apps/shrinkflation-price-scanner"


LOCALES = {
    "en": {
        "source": "en-US",
        "html_lang": "en",
        "privacy": "Privacy Policy",
        "terms": "Terms of Use",
        "nav": "Policy navigation",
        "language": "Language",
        "date": "Effective September 16, 2026 · Last updated September 16, 2026",
        "landing_date": "Effective September 16, 2026",
    },
    "es-419": {
        "source": "es-PR",
        "html_lang": "es-PR",
        "privacy": "Política de privacidad",
        "terms": "Términos de uso",
        "nav": "Navegación de políticas",
        "language": "Idioma",
        "date": "Vigente desde el 16 de septiembre de 2026 · Última actualización: 16 de septiembre de 2026",
        "landing_date": "Vigente desde el 16 de septiembre de 2026",
    },
}


def inline(value: str) -> str:
    escaped = html.escape(value, quote=True)
    escaped = re.sub(r"`([^`]+)`", r"<code>\1</code>", escaped)
    return escaped


def markdown_body(path: Path) -> str:
    lines = path.read_text(encoding="utf-8").splitlines()
    body: list[str] = []
    paragraph: list[str] = []
    in_list = False

    def flush_paragraph() -> None:
        if paragraph:
            body.append(f"<p>{inline(' '.join(paragraph))}</p>")
            paragraph.clear()

    def close_list() -> None:
        nonlocal in_list
        if in_list:
            body.append("</ul>")
            in_list = False

    # The first heading and effective-date line are rendered in the page header.
    content = lines[3:]
    for raw in content:
        line = raw.strip()
        if not line:
            flush_paragraph()
            close_list()
        elif line.startswith("## "):
            flush_paragraph()
            close_list()
            body.append(f"</section><section><h2>{inline(line[3:])}</h2>")
        elif line.startswith("- "):
            flush_paragraph()
            if not in_list:
                body.append("<ul>")
                in_list = True
            body.append(f"<li>{inline(line[2:])}</li>")
        else:
            if in_list:
                close_list()
            paragraph.append(line)
    flush_paragraph()
    close_list()
    rendered = "\n".join(body)
    if rendered.startswith("</section>"):
        rendered = rendered[len("</section>"):]
    return f"<section>{rendered}</section>"


def language_switch(locale: str, kind: str) -> str:
    suffix = "" if kind == "landing" else f"{kind}/"
    current_en = ' aria-current="page"' if locale == "en" else ""
    current_es = ' aria-current="page"' if locale == "es-419" else ""
    return (
        f'<div class="languages" aria-label="{LOCALES[locale]["language"]}">'
        f'<a href="{BASE}/en/{suffix}" lang="en"{current_en}>English</a>'
        f'<a href="{BASE}/es-419/{suffix}" lang="es-PR"{current_es}>Español de Puerto Rico</a>'
        "</div>"
    )


def policy_page(locale: str, kind: str) -> str:
    data = LOCALES[locale]
    title = data[kind]
    other = "terms" if kind == "privacy" else "privacy"
    source = ROOT / "Policies" / data["source"] / f"{kind}.md"
    canonical = f"{BASE}/{locale}/{kind}/"
    description = (
        f"{title} for Shrinkflation Price Scanner by WorksBien Studios Inc."
        if locale == "en"
        else f"{title} de Shrinkflation Price Scanner de WorksBien Studios Inc."
    )
    return f'''<!doctype html>
<html lang="{data['html_lang']}">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="robots" content="index,follow">
  <meta name="theme-color" content="#f5f5f7">
  <title>{title} · Shrinkflation Price Scanner</title>
  <meta name="description" content="{description}">
  <link rel="canonical" href="{canonical}">
  <link rel="stylesheet" href="{BASE}/assets/policies.css">
</head>
<body>
  <header class="site-header">
    <a class="brand" href="{BASE}/{locale}/">Shrinkflation Price Scanner</a>
    <nav aria-label="{data['nav']}">
      <a href="{BASE}/{locale}/privacy/"{' aria-current="page"' if kind == 'privacy' else ''}>{data['privacy']}</a>
      <a href="{BASE}/{locale}/terms/"{' aria-current="page"' if kind == 'terms' else ''}>{data['terms']}</a>
    </nav>
  </header>
  <main>
    <div class="document-head">
      <p class="eyebrow">WorksBien Studios Inc.</p>
      <h1>{title}</h1>
      <p class="date">{data['date']}</p>
      {language_switch(locale, kind)}
    </div>
    <article>
      {markdown_body(source)}
      <section class="links">
        <a href="https://worksbienstudios.com/customerservice" rel="noreferrer">{'WorksBien customer support' if locale == 'en' else 'Servicio al cliente de WorksBien'}<span aria-hidden="true">↗</span></a>
        <a href="https://www.apple.com/legal/internet-services/itunes/dev/stdeula/" rel="noreferrer">{'Apple Standard EULA' if locale == 'en' else 'Contrato de licencia estándar de Apple'}<span aria-hidden="true">↗</span></a>
        <a href="https://policies.google.com/privacy" rel="noreferrer">{'Google privacy policy' if locale == 'en' else 'Política de privacidad de Google'}<span aria-hidden="true">↗</span></a>
        <a href="https://fdc.nal.usda.gov/" rel="noreferrer">USDA FoodData Central<span aria-hidden="true">↗</span></a>
      </section>
    </article>
  </main>
  <footer>© 2026 WorksBien Studios Inc.</footer>
</body>
</html>
'''


def landing_page(locale: str) -> str:
    data = LOCALES[locale]
    return f'''<!doctype html>
<html lang="{data['html_lang']}">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="robots" content="index,follow">
  <meta name="theme-color" content="#f5f5f7">
  <title>Shrinkflation Price Scanner · {'Policies' if locale == 'en' else 'Políticas'}</title>
  <link rel="stylesheet" href="{BASE}/assets/policies.css">
</head>
<body>
  <header class="site-header"><span class="brand">Shrinkflation Price Scanner</span></header>
  <main>
    <div class="document-head">
      <p class="eyebrow">WorksBien Studios Inc.</p>
      <h1>Shrinkflation Price Scanner</h1>
      <p class="date">{data['landing_date']}</p>
    </div>
    <div class="policy-cards">
      <a href="{BASE}/{locale}/privacy/"><strong>{data['privacy']}</strong><span aria-hidden="true">→</span></a>
      <a href="{BASE}/{locale}/terms/"><strong>{data['terms']}</strong><span aria-hidden="true">→</span></a>
    </div>
    {language_switch(locale, 'landing')}
  </main>
  <footer>© 2026 WorksBien Studios Inc.</footer>
</body>
</html>
'''


def main() -> None:
    for locale in LOCALES:
        target = OUTPUT_ROOT / locale
        (target / "privacy").mkdir(parents=True, exist_ok=True)
        (target / "terms").mkdir(parents=True, exist_ok=True)
        (target / "index.html").write_text(landing_page(locale), encoding="utf-8")
        for kind in ("privacy", "terms"):
            (target / kind / "index.html").write_text(policy_page(locale, kind), encoding="utf-8")


if __name__ == "__main__":
    main()
