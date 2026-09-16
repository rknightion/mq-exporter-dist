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
just build-linux v6.0.0-rc.1
just build-linux v6.0.0-rc.1 otel
# On a Windows build host:
just build-windows v6.0.0-rc.1
just build-windows v6.0.0-rc.1 otel
just release-index
just public-check
```

Each exporter has separate Linux and Windows archives. The default exporter is
Prometheus. Build inputs and workspaces remain in ignored local storage and are
never part of the public payload.

Public release versions follow the pinned IBM exporter source, not the MQ runtime:
exporter v6.0.0 uses distribution v6.0.0, with `-rc.N` for candidates. Distribution
and upstream identities remain separate fields in build metadata. Earlier v0.1.0
candidates predate this naming convention. The MQ SDK/runtime version is an
independent compatibility requirement and does not determine the release version.

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

## RPM candidates

`just build-rpm ARCHIVE CHECKSUMS` wraps a verified Linux archive without rebuilding
or stripping its executables. Run it once per exporter. Unsigned candidates,
SHA-256 files and packaging metadata are written to `.work/rpm-candidates`, never
automatically included in a GitHub release. Existing output names are rejected.
Use a fresh output directory for independent reproducibility comparisons.
Unpublished Candidate release runs also retain these as explicitly named
`unsigned-rpm-*` CI artifacts. The publishing job does not download those artifacts.
`just test-rpm DIRECTORY` checks both packages in disposable EL8/EL9 userspaces.

RPM Version is the pinned upstream tag without `v`; Release is the distribution
version without `v`, replacing `-rc.` with `~rc.`, followed by `.mqdist`. For example,
`6.0.0-6.0.0~rc.1.mqdist` sorts before `6.0.0-6.0.0.mqdist`. Existing archive and
GitHub distribution tags remain distinct from upstream. Never reuse an RPM NEVRA
for changed bytes. Bump the distribution revision when packaging changes.

The build uses the pinned EL8 packaging image and records the resolved image,
RPM inventory, packaging commit, input archive identity and output hash. Automatic
native requirements are retained except `libmqm_r.so`, because IBM's runtime can
be installed outside RPM. IBM MQ remains mandatory. No MQ runtime is bundled.

Before publication, validate install/upgrade/removal and labels on native RHEL8/9,
including active template instances and retained configuration. Container RPM
transactions are not native service or SELinux proof. Package removal must stop
only its own instances; upgrades require an explicit administrator restart.

A public yum/DNF repository is not enabled yet. The dedicated public signing key
and expiry metadata are in [keys](../keys/README.md). After an unpublished Candidate
run succeeds, dispatch **Signed RPM candidate** with its run ID at the same commit.
The protected workflow signs copies of both RPMs, checks that payloads are unchanged,
and signs `createrepo_c` metadata and checksums. It retains a candidate artifact;
it does not publish a release or enable a public repository.

The separate verification job checks package and metadata signatures, rejects
tampering, and installs with `gpgcheck=1` and `repo_gpgcheck=1` on EL8/EL9 userspaces.
`just test-signed-rpm DIRECTORY` runs those checks locally without private keys.
Publication still requires native acceptance and immutable versioned snapshots.
Keep prereleases opt-in. Do not tell users to disable signature verification to
install an unsigned candidate. Offline users receive the same signed RPMs and key.

Use only the signing subkey in automation; keep the certification key and
revocation certificate outside CI. Renew or rotate the signing subkey before its
recorded expiry, publish the updated public key, and verify old and new signatures
on EL8/EL9 before switching. Back up encrypted secret material off-device and
verify restoration. A public key commit alone does not complete CI secret custody
or authorize release publication.

## Documentation site

`just docs-build` generates the static site from approved user-facing pages.
`just docs-lock` refreshes its hash-locked build dependencies. The Pages workflow
deploys main and does not publish binary releases. Theme assets use m7kni design
tokens and self-hosted fonts; font licenses are included in the site payload.
