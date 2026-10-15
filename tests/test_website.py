"""Keep the bilingual onboarding and the public asset whitelist usable."""

from html.parser import HTMLParser
import json
from pathlib import Path
import re
import subprocess
import unittest
from urllib.parse import unquote, urlsplit


ROOT = Path(__file__).resolve().parents[1]


class PageReferences(HTMLParser):
    def __init__(self, source):
        super().__init__()
        self.translations = set()
        self.references = []
        self.ids = []
        self.feed(source)

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        for key in ("data-i18n", "data-i18n-alt"):
            if key in attrs:
                self.translations.add(attrs[key])
        for key in ("href", "src", "data-en-href"):
            if key in attrs:
                self.references.append(attrs[key])
        if "id" in attrs:
            self.ids.append(attrs["id"])


class WebsiteTests(unittest.TestCase):
    def test_english_covers_each_text_and_image_description(self):
        page = PageReferences((ROOT / "website/index.html").read_text())
        script = (ROOT / "website/site.js").read_text()
        dictionary = json.loads(re.search(r"const english = (\{.*?\n\});", script, re.S)[1])
        self.assertEqual(page.translations, set(dictionary))
        self.assertTrue(all(isinstance(value, str) and value.strip() for value in dictionary.values()))

    def test_site_build_contains_referenced_assets_and_anchor_targets(self):
        subprocess.run(["bash", str(ROOT / "scripts/build-website.sh")], check=True, capture_output=True)
        output = ROOT / "website/.build"
        for file in output.glob("*.html"):
            page = PageReferences(file.read_text())
            self.assertEqual(len(page.ids), len(set(page.ids)), file.name)
            for reference in page.references:
                url = urlsplit(reference)
                if url.scheme or url.netloc:
                    continue
                with self.subTest(page=file.name, target=reference):
                    if url.path and url.path != "./":
                        self.assertTrue((output / unquote(url.path)).is_file())
                    if not url.path and url.fragment:
                        self.assertIn(unquote(url.fragment), page.ids)

    def test_readmes_and_site_link_to_existing_project_documents(self):
        website = PageReferences((ROOT / "website/index.html").read_text())
        references = website.references
        for filename in ("README.md", "README.en.md", "docs/准备中转服务器.md"):
            file = ROOT / filename
            for reference in re.findall(r"\]\(([^\s)]+)\)", file.read_text()):
                url = urlsplit(reference)
                if not url.scheme and not url.netloc and url.path:
                    with self.subTest(page=filename, target=reference):
                        self.assertTrue((file.parent / unquote(url.path)).is_file())
                else:
                    references.append(reference)
        prefix = "https://github.com/ALVIN-YANG/Hermland/blob/main/"
        for reference in references:
            if reference.startswith(prefix):
                path = unquote(urlsplit(reference).path.split("/blob/main/", 1)[1])
                with self.subTest(target=reference):
                    self.assertTrue((ROOT / path).is_file())


if __name__ == "__main__":
    unittest.main()
