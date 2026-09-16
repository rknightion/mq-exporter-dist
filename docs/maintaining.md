# Building the packages

These instructions are for build machines. Target servers use the precompiled
archives and need no development tools.

## Prerequisites

Install Git, Go, Python 3.12+, just, shellcheck and PowerShell. Linux builds need
Docker; Windows builds acquire the pinned GCC/binutils toolchain. IBM SDK/client
inputs are downloaded from IBM and verified against pinned SHA-256 hashes.
You must have rights to use those separately licensed inputs.

```bash
just check
just build-linux v0.1.0-rc.3
just build-linux v0.1.0-rc.3 otel
# On a Windows build host:
just build-windows v0.1.0-rc.3
just build-windows v0.1.0-rc.3 otel
just release-index
just public-check
```

Each exporter has separate Linux and Windows archives. The default exporter is
Prometheus. Build inputs and workspaces remain in ignored local storage and are
never part of the public payload.

## Upgrade a dependency

1. Resolve the upstream tag against IBM's remote and pin the exact commit in
   `build/inputs.json`. Review its Go minimum, vendored dependencies and notices.
2. Select a supported Go release and verify its hashes against the
   [Go download manifest](https://go.dev/dl/?mode=json).
   Check the [platform requirements](https://go.dev/wiki/MinimumRequirements),
   including the Windows cgo compiler's DWARF support.
3. Acquire the MQ SDK/client through
   [IBM's published route](https://www.ibm.com/docs/en/ibm-mq/9.3.x?topic=overview-redistributable-mq-clients).
   Update its hash and the receipt in `build/publisher-verification.json`.
   Do not infer older-runtime compatibility from a newer SDK.
4. Update the Linux image digest and toolchain pins together. Run the checks,
   build both exporters and test the exact archives against the compatibility
   matrix. Compare independent builds before claiming byte-for-byte reproducibility.

Builds use fresh checkouts of pinned upstream source, vendored modules,
`GOTOOLCHAIN=local` and disabled module downloads. The matching config checker
uses the collector's upstream configuration reader without connecting to MQ.
The Windows SCM adapter builds separately; it does not implement metrics.

## Release archives

The Candidate release workflow builds all four archives at the selected commit.
Its publication option defaults to false. When enabled, it verifies hashes,
checks input receipts, attests the tested bytes and publishes a prerelease
without rebuilding. Stable version strings remain disabled until target acceptance.

Archives include licenses, dependency notices, an SBOM and machine-readable build
metadata. MQ SDK/runtime files are excluded. The SBOM lists vendored modules and
does not certify that the package is free of vulnerabilities.

Base images and requested tool versions are pinned. Transitive RPM packages are
recorded, but the toolchain is not fully archived. Whole-archive reproducibility
is not yet established because build-image identity can differ between builds.

## Documentation

`just docs-build` generates the static site from approved user-facing pages.
`just docs-lock` refreshes its hash-locked build dependencies. The Pages workflow
deploys main and does not publish binary releases. Theme assets use m7kni design
tokens and self-hosted fonts; font licenses are included in the site payload.
