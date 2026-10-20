# Local installation certificates

The bundled TLS certificates identify only Asspp and `localhost.qaq.wiki`.
The local HTTPS installer needs the leaf certificate and its private key.
The CA private key is not included in the repository or release packages.

Version 4.2.2 replaces the old CA certificate, whose subject contained a local
username and hostname. To use OTA installation after upgrading, install and
trust the new certificate from Settings again.

Release builds explicitly clear `DEVELOPMENT_TEAM`, disable developer signing,
and check the IPA and macOS archive for personal build paths, provisioning
profiles, developer signing identities, and personal certificate subjects
before publishing them.
