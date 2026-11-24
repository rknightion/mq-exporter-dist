FROM ghcr.io/rknightion/cursor-cloud-base:1@sha256:d682eea83896694ce529c2035816610edd723c9acbd39ccaf8056743e7ed1756

USER root
# PowerShell needs the native ICU library for the portable installer checks.
RUN set -eu; \
    case "$(dpkg --print-architecture)" in \
        amd64) archive=https://archive.ubuntu.com/ubuntu/; security=https://security.ubuntu.com/ubuntu/ ;; \
        arm64) archive=https://ports.ubuntu.com/ubuntu-ports/; security="$archive" ;; \
        *) exit 1 ;; \
    esac; \
    key=/usr/share/keyrings/ubuntu-archive-keyring.gpg; \
    printf 'deb [signed-by=%s] %s noble main\ndeb [signed-by=%s] %s noble-updates main\ndeb [signed-by=%s] %s noble-security main\n' \
        "$key" "$archive" "$key" "$archive" "$key" "$security" > /tmp/cursor-powershell.list; \
    set -- -o Dir::Etc::sourcelist=/tmp/cursor-powershell.list -o Dir::Etc::sourceparts=-; \
    apt-get "$@" -o APT::Update::Error-Mode=any update; \
    DEBIAN_FRONTEND=noninteractive apt-get "$@" install -y --no-install-recommends libicu74; \
    rm -rf /var/lib/apt/lists/* /tmp/cursor-powershell.list

RUN set -eu; \
    version=7.7.0; \
    case "$(dpkg --print-architecture)" in \
        amd64) arch=x64; digest=c89d9c682d2c403dfe726f3df948e359675235a5bd6fab535776de69729ca0cb ;; \
        arm64) arch=arm64; digest=e59c89776eaa59790d44b3edd14277435225ab08b6e7603763101b89de83d935 ;; \
        *) exit 1 ;; \
    esac; \
    archive="$(mktemp)"; \
    curl -qfsSL --retry 2 --max-time 180 -o "$archive" \
        "https://github.com/PowerShell/PowerShell/releases/download/v$version/powershell-$version-linux-$arch.tar.gz"; \
    printf '%s  %s\n' "$digest" "$archive" | sha256sum --check --status; \
    mkdir -p /opt/powershell; \
    tar -xzf "$archive" --no-same-owner -C /opt/powershell; \
    chmod 0755 /opt/powershell/pwsh; \
    ln -s /opt/powershell/pwsh /usr/local/bin/pwsh; \
    rm -f "$archive"

ENV POWERSHELL_TELEMETRY_OPTOUT=1 POWERSHELL_UPDATECHECK=Off
USER ubuntu
