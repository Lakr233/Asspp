# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

**Note**: `CLAUDE.md` is a symlink to `AGENTS.md`. Edit `AGENTS.md` directly.

## Project Overview

Asspp is a multi-account App Store management app (iOS + macOS) for searching, downloading, and installing IPA files. It uses an Xcode workspace (`Asspp.xcworkspace`) with SPM dependencies including [ApplePackage](https://github.com/Lakr233/ApplePackage), the core library for App Store API communication, IPA handling, and signature injection.

Bundle ID: `wiki.qaq.Asspp`. Deployment targets: iOS 17.0, macOS 15.0. Supports iPhone, iPad, and Mac (native, not Catalyst). No test targets exist.

## Build Commands

```bash
# Build for iOS (device)
xcodebuild -workspace Asspp.xcworkspace -scheme Asspp -configuration Debug -destination 'generic/platform=iOS' build | xcbeautify

# Build for macOS
xcodebuild -workspace Asspp.xcworkspace -scheme Asspp -configuration Debug -destination 'platform=macOS' build | xcbeautify

# Build for iOS simulator
xcodebuild -workspace Asspp.xcworkspace -scheme Asspp -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 16' build | xcbeautify

# CI release build (iOS IPA, unsigned)
./Resources/Scripts/compile.release.mobile.ci.sh "$(pwd)" "$(pwd)/Asspp.ipa"

# CI release build (macOS zip)
./Resources/Scripts/compile.release.osx.sh "$(pwd)" "$(pwd)/Asspp.zip"
```

**Important**: Always use `Asspp.xcworkspace` (not `.xcodeproj`) because the workspace manages SPM package resolution. Always pipe xcodebuild output through `xcbeautify` to reduce output verbosity and save tokens.

## Code Signing Setup

`Configuration/Developer.xcconfig` is gitignored and must exist for builds. It provides code signing settings:

```
DEVELOPMENT_TEAM = <your team ID>
CODE_SIGN_STYLE = Automatic
CODE_SIGN_IDENTITY = Apple Development
```

A build phase script errors if this file is missing. The CI scripts generate a no-signing version automatically.

## Build Configuration

xcconfig hierarchy: `Debug.xcconfig`/`Release.xcconfig` → `Base.xcconfig` → `Version.xcconfig`, plus `Developer.xcconfig` for signing. Version numbers are in `Configuration/Version.xcconfig` (single source of truth).

## Architecture

### App Entry Point

`Asspp/App/main.swift` — initializes logging (`LogManagerHandler`), configures `ApplePackage` device identifier, sets up `Digger` download manager (max 3 concurrent), and starts the OTA installer on iOS. On iOS 26+, the main view switches to `NewMainView` (new `Tab` API); otherwise `MainView` is used.

### Backend Layer (`Asspp/Backend/`)

- **AppStore/**: `AppStore` singleton manages accounts and device identifier. `AuthenticationService` handles auth using ApplePackage's SAP-signed authenticator; `AddAccountView` retains the authenticator across verification-code attempts. `AppPackage`/`AppPackageArchive`/`UserAccount` are model wrappers around ApplePackage types.
- **Downloader/**: `Downloads` singleton manages download queue via `Digger`. `PackageManifest` tracks per-download state and IPA signature injection. Downloads persist to `Documents/Asspp/Packages/`.
- **Installer/**: iOS-only Vapor HTTPS server serving IPA files for OTA installation via `itms-services://` protocol. Uses TLS certs from `Certificates/localhost.qaq.wiki/` bundle.
- **DeviceCTL/**: macOS-only device management via `devicectl` CLI. `DeviceManager` handles app installation to connected iOS devices.
- **LogManager.swift**: Thread-safe log singleton feeding `Settings/LogView`.

### Interface Layer (`Asspp/Interface/`)

SwiftUI views organized by feature: Account, Search, Download, Installed (macOS only), Setting, Welcome. `MainView` uses `NavigationSplitView` sidebar on macOS and `TabView` on iOS.

### Key Patterns

- **Observation**: `AppStore`, `Downloads`, `Installer`, `DeviceManager`, `PackageManifest` all use `@Observable` (not legacy `ObservableObject`).
- **Persistence**: Custom `@PublishedPersist` / `@Persist` property wrappers (in `Extension/PublishedPersist.swift`) back properties to file storage (`Documents/Config/`) or Keychain. Accounts stored in Keychain; downloads and settings use file storage.
- **Platform branching**: Heavy use of `#if os(macOS)` / `#if os(iOS)` / `#if canImport(UIKit)` for platform-specific code paths.
- **Singletons**: `AppStore.this`, `Downloads.this` are `@MainActor` singletons.
- **Localization**: English + Simplified Chinese (zh-Hans) via `.xcstrings` format in `Asspp/App/`.

## Dependencies (SPM via Xcode)

- **ApplePackage** (remote) — App Store protocol, IPA handling
- **Vapor** — HTTPS server for iOS OTA installation
- **Digger** — Download manager with progress/speed tracking
- **Kingfisher** — Async image loading
- **ColorfulX** — Gradient animations (welcome screen)
- **KeychainAccess** — Keychain storage for accounts
- **AnyCodable** — Type-erased Codable values
- **ButtonKit** — Async button actions
- **swift-log** — Structured logging (`logger` global)

## Swift Code Style

- **Indentation**: 4 spaces. Opening brace on same line.
- **Naming**: PascalCase for types, camelCase for properties/methods. PascalCase filenames for types, `+` prefix for extension files.
- **Structure**: Early returns, guard statements for unwrapping, single responsibility per extension.
- **Modern Swift**: `@Observable` macro, `async/await`, `@MainActor`, opaque `some` types.
- **Memory**: `weak`/`unowned` references to break cycles, capture lists in closures.
