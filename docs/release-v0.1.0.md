# v0.1.0 preparation

Status: prepared release scope, **publication held for target-platform acceptance**.
The published v0.1.0-rc.1 Linux and Windows artifacts remain provisional and contain
mq_prometheus only. Adding mq_otel requires new candidate bytes and fresh evidence;
it does not retroactively change that release. Prometheus and OTel ship as separate
Linux/Windows archive pairs, never a combined exporter bundle.

## Release acceptance

- Build both unchanged IBM exporters at the pinned upstream commit. Validate each
  with its own actual configuration reader, native inspection and loading tests.
- Exercise installation, upgrade and service lifecycle on the initial targets.
  Distinguish Server Core 2019 container evidence from a full server installation,
  and EL8/EL9 userspace evidence from native RHEL/kernel validation.
- With an authorized MQ lab, validate local bindings, client connections, queue
  coverage and reconnection. For mq_otel, verify receipt at an explicitly chosen
  OTLP receiver; a Prometheus HTTP check cannot validate it.
- Resolve the Windows MQ runtime/version prerequisites and reproduce release
  payloads independently. Record archive reproducibility limits explicitly.
- Run the full gate, privacy review and pre-push code review. Attach exact commit,
  CI run, artifact hashes, SBOM and provenance to the release evidence.

Keep the build's candidate-only version guard until these checks are accepted.
Then build v0.1.0 from a reviewed commit, test those exact bytes and publish them
without rebuilding. Do not rename or replace existing candidate assets.
