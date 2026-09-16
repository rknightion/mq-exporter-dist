# Package signing key

`RPM-GPG-KEY-mq-exporter-dist` is this community project's public OpenPGP key,
not an IBM or Grafana Labs key. `signing-key.json` records its full fingerprints
and expiry dates. Compare the full primary fingerprint through a trusted channel
before importing it into a package manager.

The RSA-4096 primary key certifies a separate RSA-4096 signing subkey. Only the
signing subkey may be used by release automation. Private key material, passphrases
and revocation certificates must never enter this repository or release payloads.

Publishing this key does not mean a signed RPM repository is available, or that
any existing unsigned candidate has been approved for release. Verify each RPM
signature and repository metadata signature when that distribution path launches.
