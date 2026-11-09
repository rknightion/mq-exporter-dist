# Loop: mq-exporter-dist
tier: guarded
gate: just check
ci-required: actionlint / Run actionlint, ci-success, dependency-review / Dependency review, zizmor / Run zizmor
grafana-stack: none
tracker: github
landing: pr

Issues are public: synthetic examples only, and no hostname, address, email or private diagnostic in any
issue, pull request or doc. Run `just` with stdin from `/dev/null`.

The tracker working model is `~/repos/agent-docs/docs/github-tracker.md` (maintainers only).

## Queue

- The queue is `just tracker queue`: open issues at Project Status Ready on the rknightion Project.
- A charter selects work by labels (`type:task`, `type:bug`, `type:feature`, `needs-owner`,
  `needs-triage`) and Project fields (Status, Priority, Effort, Lane). Never queue a `needs-owner` or
  `needs-triage` issue, or the Dependency Dashboard (#6).
- Only the root writes issues and the Project, through `just tracker`. A lane returns the status and
  the AC ticks it wants.
- A queue row names the issue as `#N`. A legacy board id (`MQ-1`) resolves with `just issue <ID>`;
  `.github/tracker/id-map.json` is the map.

## Traps

- No live IBM MQ queue manager and no Windows or Linux native host is available to a lane. A task whose
  acceptance needs one stays open with what was implemented, what could not be observed and the exact
  command a human with the hardware would run; never redefine acceptance downward.
- `.github/workflows/` changes never carry a closing keyword: write `Task: none, <reason>` and hand the
  issue to the owner.
- IBM MQ SDK and runtime files are build inputs only. Never commit them or paste their text into an issue.
