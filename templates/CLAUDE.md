# CLAUDE.md

Agent guide for this repository. See [README.md](README.md) for what it is and
how to run it.

## Rules

- **An issue comes first.** One branch and one PR per issue. Name the branch
  `<type>/<issue-number>-<slug>` and put `Closes #<number>` in the PR body.
  Commit messages never contain `#<number>`.
- **Commits are signed.** Merge with the squash or merge button only.
- **Verify before merging.** Run each acceptance criterion and post the
  commands and results as a comment on the issue.
- **Visibility.** State whether this repository might ever become public. If
  it might, keep private names, vault paths, IPs and employer terms out of
  files and commit messages from the first commit.
- **Departures from the baseline.** List every rule from
  `husterk/.github/docs/` this repository skips, with the reason.

## Commands

```bash
mise install
mise run check
```

## CI job to local command

| Failing job    | Local command                                           |
| -------------- | ------------------------------------------------------- |
| `Linked issue` | Put `Closes #<number>` for an open issue in the PR body |
