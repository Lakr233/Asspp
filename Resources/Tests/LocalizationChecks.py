"""Validate localized Swift error strings against compiled English/Chinese resources."""
import json
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[2]
catalog = root / "Asspp/App/Localizable.xcstrings"
strings = json.loads(catalog.read_text())["strings"]
keys = set()
for filename in sys.argv[1:]:
    source = (root / filename).read_text()
    for literal in re.findall(r'(?:String\(localized: |(?:Text|TextField|SecureField)\()"((?:\\.|[^"\\])*)"', source):
        key = re.sub(r'\\\((\w+)\)', lambda match: "%lld" if match[1] == "status" else "%@", literal)
        keys.add(key.replace(r'\n', '\n').replace(r'\"', '"'))
assert keys, "No localized strings were selected"
with tempfile.TemporaryDirectory() as directory:
    subprocess.run(["xcrun", "xcstringstool", "compile", str(catalog), "--output-directory", directory,
                    "--serialization-format", "binary"], check=True)
    for language in ("en", "zh-Hans"):
        with open(Path(directory) / (language + ".lproj/Localizable.strings"), "rb") as stream:
            compiled = plistlib.load(stream)
        for key in keys:
            unit = strings[key]["localizations"].get(language, {}).get("stringUnit")
            if language == "en" and unit is None:
                # English source keys are valid fallbacks for existing SwiftUI strings.
                assert compiled.get(key, key) == key
                continue
            assert unit["state"] == "translated", (language, key)
            assert compiled[key] == unit["value"], (language, key)
            assert sorted(re.findall(r'%(?:\d+\$)?(?:lld|@)', key)) == sorted(re.findall(r'%(?:\d+\$)?(?:lld|@)', unit["value"])), (language, key)
print(f"Compiled English and Simplified Chinese localization checks passed ({len(keys)} keys).")
