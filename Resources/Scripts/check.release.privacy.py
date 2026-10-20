#!/usr/bin/env python3
"""Reject personal build metadata and signing assets before publishing Asspp."""

import plistlib
import re
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path


def check(archive):
    with tempfile.TemporaryDirectory(prefix="asspp-release-check-") as temporary:
        root = Path(temporary)
        with zipfile.ZipFile(archive) as package:
            for item in package.infolist():
                path = Path(item.filename)
                if path.is_absolute() or ".." in path.parts:
                    raise ValueError("unsafe archive path")
                if path.suffix.lower() in {".mobileprovision", ".provisionprofile", ".p12", ".p8"}:
                    raise ValueError("archive contains provisioning or signing assets")
                if path.name in {"Developer.xcconfig", "rootCA-key.pem"}:
                    raise ValueError("archive contains local developer configuration or a CA private key")
                if not item.is_dir():
                    content = package.read(item)
                    if re.search(rb"/Users/(?!runner(?:admin)?/|Shared/)[A-Za-z0-9._-]+/", content):
                        raise ValueError("archive contains a personal home directory path")
            package.extractall(root)

        apps = list(root.glob("Asspp.app")) + list(root.glob("Payload/Asspp.app"))
        if len(apps) != 1:
            raise ValueError("expected one Asspp application")
        app = apps[0]
        info = app / "Contents/Info.plist" if (app / "Contents").exists() else app / "Info.plist"
        metadata = plistlib.loads(info.read_bytes())
        if any(key in metadata for key in ("TeamIdentifier", "ApplicationIdentifierPrefix", "DeveloperName")):
            raise ValueError("application metadata contains a developer identity")

        signature = subprocess.run(
            ["codesign", "--display", "--verbose=4", str(app)], capture_output=True, text=True
        )
        for line in signature.stderr.splitlines():
            if line.startswith("TeamIdentifier=") and line != "TeamIdentifier=not set":
                raise ValueError("application contains a signing team")
            if line.startswith("Authority="):
                raise ValueError("application contains a developer signing certificate")
        if signature.returncode and "not signed at all" not in signature.stderr:
            raise ValueError("unable to inspect application signature")

        for certificate in app.rglob("*.pem"):
            if "-key" in certificate.stem:
                continue  # The local TLS server requires its bundled leaf key.
            result = subprocess.run(
                ["openssl", "x509", "-in", str(certificate), "-noout", "-subject", "-issuer"],
                capture_output=True, text=True,
            )
            if result.returncode or "@" in result.stdout or "/Users/" in result.stdout:
                raise ValueError("certificate contains personal metadata or cannot be inspected")
        print(f"{Path(archive).name}: release privacy checks passed")


if __name__ == "__main__":
    for argument in sys.argv[1:]:
        check(argument)
