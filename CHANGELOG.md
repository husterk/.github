# Changelog

## v2.0.1

- `renovate/default` keeps every `husterk/.github` update in one PR, even
  when a repository is a major version behind. Before, Renovate split it into
  a PR for the latest minor and a PR for the new major.

## v2.0.0

- `renovate/default` opens at most 3 PRs per repository (`prConcurrentLimit`)
  and 2 per hour (`prHourlyLimit`). Security fix PRs skip both limits.
- `renovate/default` sets `rebaseWhen: "conflicted"`. Under strict required
  checks, the default rebased every open Renovate PR after each merge and
  reran CI on all of them. To merge a PR that is behind `main`, tick its
  rebase checkbox.
- `renovate/default` puts every minor and patch update in one PR
  (`group:allNonMajor`), replacing the GitHub Actions-only group. Each major
  update keeps its own PR.
- `renovate/mise` groups formatter and language server updates only when they
  are major.
- Updates and lock file maintenance run monthly instead of every second month.

## v1.3.1

- The guides drop GitHub's unused default labels (`duplicate`,
  `good first issue`, `help wanted`, `invalid`, `question`, `wontfix`), and
  the audit warns when one is present.
- A closed issue's `next:` label no longer matters, so merging a PR needs no
  label cleanup.

## v1.3.0

- Three labels, `next: agent`, `next: human` and `next: waiting`, mark who
  acts next on every open issue. The guides and `templates/CLAUDE.md` give
  the rules, and `scripts/audit-repo.sh` warns when a label is missing or an
  open issue lacks exactly one of them.

## v1.2.0

- `docs/cloudflare-sites.md` covers sites hosted on Cloudflare: static
  assets on Workers instead of Pages, the deploy and preview jobs, the
  workers.dev noindex rule, the API token, moving a custom domain, and Web
  Analytics setup.
- Preview jobs for Cloudflare Workers use the deploy token. The guides
  record why a separate preview token does not protect production there.
- The guides say a release workflow derives its version from tags and never
  pushes to `main`, and that path-filtered release pipelines exclude the
  baseline files.
- The guides say how Renovate's PRs stay current under strict required
  checks: Renovate rebases them itself, so nobody updates them by hand.

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
