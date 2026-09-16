set shell := ["bash", "-euo", "pipefail", "-c"]

# renovate: datasource=golang-version depName=go
go_version := "1.26.8"
# renovate: datasource=python-version depName=python
python_version := "3.13"

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
    shellcheck install/*.sh tests/*.sh
    pwsh -NoProfile -File tests/parse-powershell.ps1

# Run focused distribution regressions.
[group('check')]
test:
    GOTOOLCHAIN=local go test ./...
    python3 -m unittest discover -s tests -p 'test_*.py'

# Run the pre-commit gate.
[group('check')]
check: fmt-check lint test

# Build pinned Linux candidate archives (requires Docker).
[group('build')]
build-linux version:
    python3 build/build.py linux {{ quote(version) }}

# Build pinned Windows candidate archives on Windows.
[group('build')]
build-windows version:
    python3 build/build.py windows {{ quote(version) }}

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

# Publish the verified candidate bytes without rebuilding.
[group('release')]
publish version sha: publish-check
    gh release create {{ quote(version) }} dist/* --target {{ quote(sha) }} --prerelease --title {{ quote(version + ' (provisional platform support)') }} --notes-file docs/candidate-notes.md

# Check SDK integrity records against the pinned build inputs.
[group('release')]
publish-check:
    python3 build/publish_check.py
