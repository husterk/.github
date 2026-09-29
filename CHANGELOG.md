# Changelog

## v1.1.1

- `renovate/mise` also resolves the 1Password CLI when `mise.toml` names it
  `1password` rather than `op`.

## v1.1.0

- `renovate/default` groups every `husterk/.github` reference, presets and
  the linked-issue action alike, into one PR per release, opened at any
  time instead of on the bimonthly schedule.
- `scripts/self-test.sh` runs Renovate with its own empty cache and checks
  that the grouping holds.

## v1.0.2

- A private repository under a personal account enforces the Actions
  allowlist, third-party patterns included, and SHA pinning, and allows
  husterk's own actions without a pattern. The private guide records the
  evidence, and `scripts/audit-repo.sh` now reports FAIL for both rules on
  private repositories.

## v1.0.1

- The guides record that a repository set to "selected actions" runs
  husterk's own actions without an allowlist pattern (proven on a public
  repository).
- `templates/pr-policy.yml` pins the linked-issue action to the `v1.0.0`
  commit instead of a placeholder.

## v1.0.0

First release.

- Default community health files: `SECURITY.md`, `CONTRIBUTING.md`, the
  `bug` and `task` issue forms, and the pull request template.
- Renovate presets `renovate/default` and `renovate/mise`. The mise preset
  groups tools by the names written in `mise.toml` and looks up the
  1Password CLI from its release history.
- Composite action `actions/linked-issue`.
- Templates for the `main` and release-tag rulesets, `renovate.json`,
  `pr-policy.yml` and `CLAUDE.md`.
- `scripts/audit-repo.sh` and the public and private repository guides.
