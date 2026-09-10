# Third-party notices

The original Asspp source remains under the MIT license in LICENSE.

The SAP implementation links Unicorn's GPL-2.0 interpreter to perform SAP authentication without
JIT. Distribution of the combined app must comply with GPL-2.0, including supplying
the corresponding source and build scripts. Unicorn includes LGPL components;
license texts and author notices are in Resources/Licenses and are copied into the
app's SAPAssets resource directory. The pinned Unicorn source archive is also copied into SAPAssets.
The exact Unicorn source revision, checksum,
download URL and build options are recorded in Resources/Scripts/prepare.sap.py.

The C++ SAP host and Mach-O loader are adapted from Sorvigolova/ipatool under MIT.
Their copyright and permission notice is in Resources/Licenses/ipatool.txt.

Apple SAP framework data is fetched directly from Apple's software-update server
and verified against the hashes used by official ipatool. Apple retains ownership
of that software. It is not part of this repository's MIT-licensed source.

See Resources/Document/SAP_AUTHENTICATION.md for source revisions and build details.

## Distribution review

Adding notices or a source archive alone does not establish compatibility of the
combined application. Before distributing SAP-enabled binaries, maintainers need
to review Unicorn's GPLv2 terms against Asspp's complete dependency graph (including
Apache-2.0 dependencies), and the redistribution terms for the extracted Apple
framework data. This change does not relicense upstream dependencies or grant
rights to Apple's software. The SAP pull request should remain a draft until this
distribution decision is resolved; the download-only change has no SAP dependency.
