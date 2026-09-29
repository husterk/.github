# CLAUDE.md

Agent guide for `husterk/.github`, the account-wide defaults and shared
building blocks for every repository `husterk` owns.

## Rules

- **This repository is public.** Never write the names of private
  repositories, private app names, 1Password vault or item paths, IPs,
  employer terms, or audit findings about other repositories here, in files
  or commit messages. Findings go into issues in the audited repository.
- **Default community health files take effect on merge.** `SECURITY.md`,
  `CONTRIBUTING.md`, `.github/ISSUE_TEMPLATE/` and
  `.github/pull_request_template.md` appear at once in every repository that
  lacks its own copy, private ones included. Write them so they read correctly
  from any repository.
- **Everything else reaches other repositories only through a release.**
  Presets and actions are pinned by tag or SHA, so merging to `main` changes
  nothing elsewhere until a tag ships and each repository merges Renovate's
  bump.
- **An issue comes first.** One branch and one PR per issue. Name the branch
  `<type>/<issue-number>-<slug>` and put `Closes #<number>` in the PR body.
  Commit messages never contain `#<number>`.
- **Commits are signed** through the 1Password SSH agent. Merge with the
  squash or merge button only; rebase-merge is disabled because it drops
  signatures.
- **Verify before merging.** Run each acceptance criterion and post the
  commands and results as a comment on the issue.

## Releasing

1. Add a `CHANGELOG.md` entry under the new version.
2. After the PR merges, tag the merge commit with a signed tag:
   `git tag -s vX.Y.Z -m vX.Y.Z && git push origin vX.Y.Z`.
3. Create the GitHub release from the tag with the CHANGELOG entry as notes.
4. Merge the `husterk/.github` PR Renovate then opens in this repository. It
   moves the pins in `templates/` to the new tag, so new repositories start
   on the latest release.

A breaking change (a renamed check, a removed input, a preset option that
changes behavior) bumps the major version.

## CI job to local command

| Failing job    | Local command                                           |
| -------------- | ------------------------------------------------------- |
| `Lint`         | `mise run check`                                        |
| `Self-test`    | `mise run self-test`                                    |
| `Linked issue` | Put `Closes #<number>` for an open issue in the PR body |
