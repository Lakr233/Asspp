# Store downloads and diagnostics

`StoreDownloadService` uses `volumeStoreDownloadProduct` first. It tries the
redownload endpoint once for failure 5002, or a missing/empty songList with no
failure code, customer message, account dialog or action. If the pinned redownload
returns an empty HTTP 500, it tries the bag-advertised `updateProduct` endpoint once,
retaining the same account and version. Other rejections and transport errors are
surfaced without this fallback. Numeric failure codes and
`metrics.messageCode` are recognized, and Apple's customer messages are preserved
in the error UI. License-required responses still use the explicit acquisition UI.

Before an unversioned fallback, the catalog resolves the current external version
ID for the selected platform and account's storefront. This asks redownload
for the selected platform's current build; the downloaded IPA is validated too. Explicit historical version IDs are kept
on all endpoints, using their respective `externalVersionId` / `appExtVrsId` keys.
A catalog failure stops the fallback instead of sending an unpinned request.
Existing saved packages without a platform default to iOS; new search results
retain the selected iPhone, iPad or Apple TV platform.

Xcode and Settings > Logs show `Store download [request ID]` entries with app ID,
platform, storefront, requested/resolved version, endpoint, HTTP status, response
size, item count, numeric error/status codes, and the fallback reason. Cookie
presence and dialog/message presence are booleans. Headers, raw bodies, Apple
messages, emails, DSIDs, device identifiers, signatures and asset URLs are not
logged. ApplePackage verbose logging stays disabled.

```sh
bash Resources/Scripts/check.downloads.sh
```

These checks exercise primary success, a single empty/5002 fallback, pinned
history, the bounded empty-500 update fallback, failed catalog resolution, explicit errors and dialogs, response
redaction, endpoint-specific version keys, and credential redirect restrictions.
The same checks run in a dedicated pull request workflow. Real account downloads
remain necessary to verify Apple's current behavior for any particular app.

The empty volume response and platform selection behavior are tracked in
[ipatool issue 538](https://github.com/majd/ipatool/issues/538#issuecomment-5578405805).

Version-history and version-metadata lookups share the same bounded fallback.
Their cache keys include the platform. After transfer, the main app's Info.plist
must match the expected bundle ID and iOS/tvOS platform before signature injection.
A response that reports a different requested version is rejected.

Legacy downloads do not require the SAP action signature used by login. The
[current ipatool implementation](https://github.com/majd/ipatool/blob/5dc4c8058db3a23e9de081ac766cc917713a65cf/pkg/appstore/appstore_download_product.go)
also has a preferred `ent/download` path with a separate `kbsync` blob; Asspp and
ApplePackage do not implement that path. Adding a login signature to these legacy
requests would not supply that blob.
