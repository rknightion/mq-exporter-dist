set shell := ["bash", "-euo", "pipefail", "-c"]

# renovate: datasource=golang-version depName=go
go_version := "1.27.1"
# renovate: datasource=python-version depName=python
python_version := "3.14"

# renovate: datasource=pypi depName=mkdocs
mkdocs_version := "1.6.1"

# renovate: datasource=rpm depName=rpm-build
rpm_build_version := "4.14.3-32.el8_10"

# renovate: datasource=rpm depName=rpm-sign
rpm_sign_version := "4.16.1.3-40.el9"
# renovate: datasource=rpm depName=createrepo_c
createrepo_version := "0.20.1-4.el9"

# List supported tasks.
default:
    @just --list

# Verify developer prerequisites without installing software.
setup:
    go version
    python3 --version
    pwsh -NoProfile -Command '$PSVersionTable.PSVersion.ToString()'
    shellcheck --version

# Format Go and the task interface.
[group('check')]
fmt:
    gofmt -w cmd internal build/*.go.txt tests/*.go.txt
    just --fmt

# Check source formatting.
[group('check')]
fmt-check:
    test -z "$(gofmt -l cmd internal build/*.go.txt tests/*.go.txt)"
    just --fmt --check

# Lint Go and shell sources and parse PowerShell scripts.
[group('check')]
lint:
    GOTOOLCHAIN=local go vet ./...
    GOOS=windows GOARCH=amd64 CGO_ENABLED=0 GOTOOLCHAIN=local go vet ./cmd/... ./internal/...
    shellcheck install/*.sh tests/*.sh
    pwsh -NoProfile -File tests/parse-powershell.ps1

# Run focused distribution regressions.
[group('check')]
test:
    GOTOOLCHAIN=local go test ./...
    python3 -m unittest discover -s tests -p 'test_*.py'
    pwsh -NoProfile -File tests/installer-preflight.ps1

# Run the pre-commit gate.
[group('check')]
check: fmt-check lint test docs-build

# Exercise the multi-instance updater with a built Linux Prometheus archive (requires Docker and a prior build-linux).
[group('check')]
test-linux-update archive:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p .work
    work=$(mktemp -d "$PWD/.work/update-test-XXXXXXXX")
    mkdir "$work/fake" "$work/sdk"
    cp tests/fake-exporter.go.txt "$work/fake/main.go"
    (cd "$work/fake" && GOOS=linux GOARCH=amd64 CGO_ENABLED=0 GOTOOLCHAIN=local go build -trimpath -o "$work/fake-exporter" main.go)
    (cd "$work/fake" && GOOS=linux GOARCH=amd64 CGO_ENABLED=0 GOTOOLCHAIN=local go build -trimpath -ldflags '-X main.unhealthyPorts=9159' -o "$work/fake-exporter-bad" main.go)
    tar -xzf .work/downloads/mq-linux.tar.gz -C "$work/sdk"
    docker run --rm --platform linux/amd64 -v "$PWD:/project:ro" -v "$(realpath {{ quote(archive) }}):/input/archive.tar.gz:ro" \
      -v "$work:/fixtures:ro" -v "$work/sdk:/sdk-input:ro" mq-exporter-dist-builder:local \
      bash /project/tests/linux-update.sh /input/archive.tar.gz /fixtures/fake-exporter /fixtures/fake-exporter-bad

# Build pinned Linux candidate archives (requires Docker).
[group('build')]
build-linux version exporter="prometheus":
    python3 build/build.py linux {{ quote(version) }} --exporter {{ quote(exporter) }}

# Build pinned Windows candidate archives on Windows.
[group('build')]
build-windows version exporter="prometheus":
    python3 build/build.py windows {{ quote(version) }} --exporter {{ quote(exporter) }}

# Package verified Linux archive bytes as an unsigned candidate RPM (requires Docker).
[group('build')]
build-rpm archive checksums:
    python3 build/rpm.py {{ quote(archive) }} {{ quote(checksums) }}

# Check RPM transactions in EL8/EL9 userspaces (requires Docker; not native SELinux).
[group('check')]
test-rpm packages:
    python3 build/rpm_validate.py {{ quote(packages) }}

# Build the pinned signing tools without secrets (requires Docker).
[group('build')]
build-rpm-signer:
    docker build --platform linux/amd64 --build-arg RPM_SIGN_VERSION={{ rpm_sign_version }} --build-arg CREATEREPO_VERSION={{ createrepo_version }} -f build/rpm-sign.Dockerfile -t mq-dist-rpm-sign build

# Verify the exact successful source run before granting signing access.
[group('release')]
rpm-sign-preflight run:
    python3 build/rpm_sign.py preflight {{ quote(run) }}

# Sign candidate copies with the dedicated subkey (requires Docker and secret environment).
[group('release')]
sign-rpm packages output:
    python3 build/rpm_sign.py sign {{ quote(packages) }} {{ quote(output) }}

# Verify signed candidate trust in EL8/EL9 containers (requires Docker).
[group('check')]
test-signed-rpm packages:
    python3 build/rpm_validate.py --signed {{ quote(packages) }}

# Inspect public source and release payloads before upload.
[group('check')]
public-check:
    python3 build/public_check.py

# Assemble the exact archives' release checksum index.
[group('release')]
release-index:
    python3 build/release_index.py

# Export the CI tool versions from this task interface.
[group('gen')]
ci-tool-versions:
    @printf 'go=%s\npython=%s\n' '{{ go_version }}' '{{ python_version }}'

# Publish verified release bytes without rebuilding; rc versions remain prereleases and custom releases never become "latest".
[group('release')]
publish version sha: publish-check
    #!/usr/bin/env bash
    set -euo pipefail
    version={{ quote(version) }}
    sha={{ quote(sha) }}
    [[ "$sha" =~ ^[0-9a-f]{40}$ ]]
    output=$(python3 -c 'import sys; sys.path.insert(0, "build"); import versions; v = versions.parse(sys.argv[1]); print(v.track, "true" if v.prerelease else "false")' "$version")
    read -r track prerelease <<<"$output"
    args=(--target "$sha" --title "$version" --notes-file docs/candidate-notes.md)
    if [[ "$track" == custom ]]; then
      args=(--target "$sha" --title "$version" --notes-file docs/custom-notes.md --latest=false)
    fi
    if [[ "$prerelease" == true ]]; then args+=(--prerelease); fi
    gh release create "$version" dist/* "${args[@]}"

# Check SDK integrity records against the pinned build inputs.
[group('release')]
publish-check:
    python3 build/publish_check.py

# Probe Server 2019 Hyper-V containers on a disposable Windows host (requires Docker).
[group('check')]
windows2019-probe:
    powershell.exe -NoLogo -NoProfile -NonInteractive -File tests/windows2019-probe.ps1

# Exercise real systemd only on a prepared, authorized disposable native VM.
[group('check')]
native-linux-install-cycle:
    bash tests/linux-native-install.sh

# Exercise real SCM only on a prepared, authorized disposable Server 2019 VM.
[group('check')]
native-windows-install-cycle:
    powershell.exe -NoLogo -NoProfile -NonInteractive -File tests/windows2019-install.ps1

# Refresh the documentation dependency lock (requires uv on the build machine).
[group('gen')]
docs-lock:
    uv pip compile --generate-hashes --no-header --universal --python-version 3.12 --output-file site/requirements.txt - <<< 'mkdocs=={{ mkdocs_version }}'

# Install hash-locked documentation tools on the build machine only.
[group('dev')]
docs-install:
    python3 -m venv .work/docs-venv
    .work/docs-venv/bin/python -m pip install --disable-pip-version-check --require-hashes --only-binary=:all: -r site/requirements.txt

# Build and privacy-check the static documentation with strict link validation.
[group('build')]
docs-build: docs-install
    .work/docs-venv/bin/python build/docs.py
