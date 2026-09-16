# Installation safety

Release selection is always explicit. There is no moving `latest` resolver. HTTPS
and normal certificate validation remain enabled. curl honors proxy variables and
`CURL_CA_BUNDLE`; Windows uses its configured proxy/trust store. Install your
organization's CA through its normal trust-management process. No insecure switch,
HTTP downgrade, package-signature bypass or GitHub token is required.

SHA-256 catches corrupted, truncated or mixed assets. A checksum delivered beside
an archive is not an independent publisher signature. Online trust is GitHub TLS
and the repository's release permissions; offline transfer must include trusted
integrity metadata. Build-machine users can additionally verify GitHub provenance
with `gh attestation verify <archive> --repo rknightion/mq-exporter-dist`.

Archives have a flat allowlist of regular files. Traversal, duplicates and links
are rejected before extraction. Scratch paths are uniquely owned. Replacement is
staged in the destination filesystem, copied completely, flushed and renamed only
after binary inspection and smoke checks. Existing files are copied to exclusively
created `.bak-*` files first; a failed backup or rename returns failure without
removing the installed executable. Retain backups for manual recovery. Updates
can leave configuration/unit changes partially applied; this is not a whole-install
transaction. On Windows, a failed update after stopping the service can leave it
stopped; inspect the error and backups before restarting it.

System download utilities get a command-local `/usr/lib64:/lib64` library path,
which takes precedence over loader-cache selection. This handles conflicts even
when the caller's LD_LIBRARY_PATH was unset. The exporter instead receives the
selected MQ library path. The linker uses RUNPATH so the explicitly selected MQ
installation can take precedence. No changes are made to global loader files,
preload policy, monitoring agents, crypto policy or system PATH. Loader injections
observed in a diagnostic are not dependencies to bundle.

Linux configuration and password files are private to the service account.
`ProtectHome=true` means ordinary Unix read permission does not make paths under
home directories available. Use protected service configuration paths outside
home/temp directories. `PrivateTmp=false` and the default shared IPC preserve host
namespaces needed for local MQ bindings; changing these is a compatibility decision,
not a harmless hardening toggle. `ProtectSystem=strict` needs lab validation against
the selected MQ installation. The service grants no MQ permissions itself.

Windows configuration uses explicit BOM-free UTF-8 and a restricted installation
ACL. The service account gets read/execute on binaries/config and write access only
to its logs. Existing MQ credentials and account rights remain administrator-owned.
Do not place credentials or CCDT files in writable shared directories. Do not run
the service as an administrator. The installer does not alter MQ, firewall or TLS
configuration on either platform.
