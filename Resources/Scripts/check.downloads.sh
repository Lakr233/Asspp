#!/bin/bash
set -euo pipefail
download_repo_dir=$(cd "$(dirname "$0")/../.." && pwd)
download_check_dir=$(mktemp -d)
trap 'rm -rf "$download_check_dir"' EXIT
cd "$download_repo_dir"
swiftc Asspp/Backend/AppStore/StoreProtocol.swift \
    Asspp/Backend/AppStore/StoreDiagnostics.swift \
    Asspp/Backend/AppStore/StoreDownloadProtocol.swift \
    Resources/Tests/DownloadProtocolChecks.swift -o "$download_check_dir/download-checks"
"$download_check_dir/download-checks"
/usr/bin/python3 Resources/Tests/LocalizationChecks.py Asspp/Backend/AppStore/StoreDownloadProtocol.swift
