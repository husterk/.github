# .github

Account-wide defaults and shared building blocks for the repositories owned
by [husterk](https://github.com/husterk).

## Contents

| Path                    | What it is                                                               | How a repo uses it                                          |
| ----------------------- | ------------------------------------------------------------------------ | ----------------------------------------------------------- |
| `actions/linked-issue/` | Composite action that fails a PR whose body does not close an open issue | `uses: husterk/.github/actions/linked-issue@<sha> # vX.Y.Z` |

## Versioning

Changes merge to `main` and ship as signed `vMAJOR.MINOR.PATCH` tags. Other
repositories pin a tag, so a new release reaches each of them as a Renovate
pull request that runs that repository's own CI. A major version marks a
breaking change, such as a renamed check or a removed preset option.

## Development

```bash
mise install
mise run check    # formatting, shellcheck, actionlint, US spelling
```

Every change starts from an issue and lands through a pull request. See
[CLAUDE.md](CLAUDE.md).
