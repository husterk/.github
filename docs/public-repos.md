# Public repo guide: create and audit

Use this guide to create a new public repo under `husterk`, to publish a
private repo, or to audit a public repo that already exists.

The tooling this guide uses lives in `husterk/.github`:

| Path                    | Use                                                                               |
| ----------------------- | --------------------------------------------------------------------------------- |
| `scripts/audit-repo.sh` | `mise run audit -- husterk/<repo>` reports every difference from this guide       |
| `templates/`            | Ruleset JSON, `renovate.json`, `pr-policy.yml` and a `CLAUDE.md` skeleton to copy |
| `renovate/`             | Shared Renovate presets, pinned by tag                                            |
| `actions/linked-issue/` | The linked-issue check, pinned by SHA                                             |

Each item comes with a command to set it and a command to verify it, so you or
a Claude session can work through an audit from start to finish. Items marked
**Default** are your conventions. Skip one for a repo when that repo has a
reason, and write the reason into the repo's `CLAUDE.md`.

The live reference is `husterk/dotfiles`. When this guide and that repo
disagree, read that repo's settings through the API before changing anything.

## How to use it

- **Creating:** work through sections 1 to 10 in order. Create the ruleset
  (section 4) after CI has run once, so the check names already exist.
- **Publishing a private repo:** do section 1 first. Nothing else matters
  until the history is clean.
- **Auditing:** run `mise run audit -- husterk/<repo>` from a clone of
  `husterk/.github` (section 11), then open one issue per FAIL or WARN in that
  repo. A WARN the repo deliberately skips needs a line in its `CLAUDE.md`
  instead. Each issue
  needs checkable acceptance criteria and the recommended fix.

Set the target once per shell:

```bash
R=husterk/<repo>
```

zsh treats `?` in a URL as a glob and aborts with `no matches found`. Quote
every `gh api` path that has a query string.

## 0. Account-level settings (once, not per repo)

| Item                       | Expected                                                    | How to check                                                                                                                                                                   |
| -------------------------- | ----------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Vigilant mode              | On                                                          | https://github.com/settings/keys, "Flag unsigned commits as unverified". Every unsigned commit you author now shows "Unverified", which is why section 4 forbids rebase-merge. |
| Renovate app               | "Only select repositories", with each repo added on purpose | https://github.com/settings/installations, then Renovate, then Configure                                                                                                       |
| 1Password service accounts | Each one used by a live repo, and none left over            | my.1password.com, Developer, Service Accounts. Delete any account whose repo is gone.                                                                                          |
| Profile pins               | The repos you want seen                                     | `gh api graphql -f query='{user(login:"husterk"){pinnedItems(first:6){nodes{... on Repository{name}}}}}'`                                                                      |

## 1. Content and history (before anything goes public)

Once a repo is public, assume every byte in it has been copied. You can
rewrite the history afterwards, but you cannot take it back.

### 1a. What must never be in a public repo

Check both the files and every commit message:

- Secrets, tokens and private keys.
- 1Password vault IDs and the names of items that reveal private detail.
  Plain `op://vault/item/field` references in a deploy workflow are fine,
  because they are useless without the service account token.
- Private app names, employer names and internal hostnames, IPs, or network
  details.
- Personal data that you did not mean to publish, such as a phone number or
  your home location.
- Links to issue or PR numbers in another repo. `#12` in a commit message
  links to whatever issue 12 is in the repo where the commit lands.

When a public repo needs something private, keep that part in a separate
private repo and pull it in at build time. `husterk/dotfiles` does this with
`husterk/dotfiles-private`, which it passes as a flake input. The public repo
then carries only a stub, and the stub fails safely when the private repo is
missing.

### 1b. Scan the full history

Run both scanners, because each catches things the other misses:

```bash
nix run nixpkgs#gitleaks -- git --no-banner --redact /path/to/clone
nix run nixpkgs#trufflehog -- git file:///path/to/clone --no-update --json | nix run nixpkgs#jq -- -r '"\(.DetectorName) verified=\(.Verified) \(.SourceMetadata.Data.Git.file)"'
```

Expected: gitleaks prints `no leaks found`, and trufflehog prints nothing.

Then search the history for your own blocklist: private names, vault IDs,
employer terms and IPs. Include commit messages and binary files:

```bash
git -C /path/to/clone log --all -p --text | grep -inE 'word1|word2|10\.0\.' | head
git -C /path/to/clone log --all --format='%B' | grep -nE '#[0-9]+'
git -C /path/to/clone log --all --format='%an <%ae> | %cn <%ce>' | sort | uniq -c
```

Expected: no blocklist hits, no `#N` references, and only identities you
meant to publish.

Open every binary file (images and PDFs) and look at it yourself. Scanners
read the text inside binaries but cannot see what an image shows.

### 1c. Publishing a private repo: make a new repo, don't flip visibility

Don't switch an existing private repo to public when its history, issues or
PRs hold anything private. GitHub keeps a `refs/pull/<n>/head` ref for every
PR, and you cannot delete those refs. Old PR bodies, review comments and
issues would go public along with the code.

The procedure that worked for `husterk/dotfiles`:

1. Make a scrubbed copy of the history with `git filter-repo`. Use
   `--replace-text` for strings in files and `--message-callback` for commit
   messages, including removing `#N` references.
2. Re-sign every rewritten commit, because a rewrite drops the signatures. One
   way is
   `git rebase -r --root --committer-date-is-author-date --exec 'git commit --amend --no-edit -S'`.
   Inferred: this is a sound method, but the September 2026 session may have
   used a different one.
3. Gate the result. Rerun every check in 1b on the rewritten repo, and also
   check that:
    - `git log --merges` is empty, if you want linear history.
    - `git log --show-signature` reports a good signature on every commit.
    - The tip tree matches the old `main`: `git diff <old-main> <new-main>`
      prints nothing.
4. Rename the old repo to `<name>-archive`, keep it private, and remove it
   from Renovate.
5. Create the new public repo under the original name, push the scrubbed
   `main`, then apply sections 2 to 10.
6. Replace your local clone with a fresh clone. Remove any git worktrees that
   hang off the old checkout first, because moving the checkout breaks them.
   Keep the old checkout until the new one is proven, then delete it.
7. Archive the old repo. When nothing depends on it, decide whether to delete
   it. Take a `git clone --mirror` first if you might want the history. The
   mirror does not include issues or PR discussion.

A reusable pre-push check: run the 1b checks on `origin/main..HEAD` for each
new branch, so a private string never reaches the public history.

## 2. Repo settings

| Setting                          | Value                           | Why                                                  |
| -------------------------------- | ------------------------------- | ---------------------------------------------------- |
| Merge commits                    | Allowed                         | GitHub signs the merge commit                        |
| Squash merging                   | Allowed. Commit title: PR title | GitHub signs the squash commit                       |
| Rebase merging                   | **Off**                         | GitHub rewrites each commit and does not sign it     |
| Auto-merge                       | On                              | Lets Renovate or you queue a merge until checks pass |
| Delete head branches             | On                              |                                                      |
| Always suggest updating branches | On                              |                                                      |
| Issues                           | On                              | **Default:** issue-first workflow                    |
| Wiki, Projects, Discussions      | Off unless the repo uses them   | Fewer places for stale or private content            |

Set:

```bash
gh api -X PATCH "repos/$R" \
  -F allow_merge_commit=true -F allow_squash_merge=true -F allow_rebase_merge=false \
  -F allow_auto_merge=true -F delete_branch_on_merge=true -F allow_update_branch=true \
  -F has_issues=true -F has_wiki=false -F has_projects=false -F has_discussions=false \
  -f squash_merge_commit_title=PR_TITLE -f squash_merge_commit_message=COMMIT_MESSAGES
```

Verify:

```bash
gh api "repos/$R" -q '{allow_merge_commit,allow_squash_merge,allow_rebase_merge,allow_auto_merge,delete_branch_on_merge,allow_update_branch,has_issues,has_wiki,has_projects,has_discussions,squash_merge_commit_title}'
```

## 3. Security and analysis

| Feature                         | Value                            | Notes                                             |
| ------------------------------- | -------------------------------- | ------------------------------------------------- |
| Secret scanning                 | On                               |                                                   |
| Push protection                 | On                               | Blocks a push that contains a known secret format |
| Dependabot alerts               | On                               | Renovate reads these alerts too                   |
| Dependabot security updates     | **Off when Renovate runs**       | Otherwise both bots open a PR for the same fix    |
| Private vulnerability reporting | On                               | Name it as the first channel in `SECURITY.md`     |
| CodeQL default setup            | On, for every language it offers | Includes `actions`, which lints the workflows     |

Set:

```bash
gh api -X PATCH "repos/$R" --input - <<'EOF'
{"security_and_analysis":{"secret_scanning":{"status":"enabled"},"secret_scanning_push_protection":{"status":"enabled"}}}
EOF
gh api -X PUT "repos/$R/vulnerability-alerts"
gh api -X DELETE "repos/$R/automated-security-fixes"
gh api -X PUT "repos/$R/private-vulnerability-reporting"
gh api -X PATCH "repos/$R/code-scanning/default-setup" -f state=configured
```

Verify:

```bash
gh api "repos/$R" -q .security_and_analysis
gh api -i "repos/$R/vulnerability-alerts" | head -1          # 204 = on
gh api "repos/$R/automated-security-fixes"                    # enabled:false
gh api "repos/$R/private-vulnerability-reporting"             # enabled:true
gh api "repos/$R/code-scanning/default-setup" -q '{state,languages}'
gh api "repos/$R/secret-scanning/alerts" -q 'map(select(.state=="open"))|length'
gh api "repos/$R/code-scanning/alerts" -q 'map(select(.state=="open"))|length'
gh api "repos/$R/dependabot/alerts" -q 'map(select(.state=="open"))|length'
```

Expected: each alert count is 0, or each open alert has an issue.

## 4. Ruleset for `main`

Use one ruleset on the default branch, with no bypass actors, so the rules
also bind you.

| Rule                                                                    | Why                                                                                                     |
| ----------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------- |
| Restrict deletions                                                      |                                                                                                         |
| Block force pushes                                                      | Feature branches can still be force-pushed                                                              |
| Require signed commits                                                  | Pairs with the merge methods below. Renovate's commits are signed.                                      |
| Require a pull request, 0 approvals, merge methods `merge` and `squash` | **Never allow `rebase`.** Add `required_linear_history` if you want only squash.                        |
| Required status checks, strict                                          | Each check name must exactly match the job's `name:`. Strict means a PR must be up to date with `main`. |

Copy `templates/ruleset-main.json`, add the repo's CI check names next to
`Linked issue`, and create it:

```bash
gh api -X POST "repos/$R/rulesets" --input ruleset-main.json
```

A repo that publishes releases also adds `templates/ruleset-release-tags.json`,
which stops a `v*` tag from being moved or deleted.

The same ruleset, written out:

```bash
gh api -X POST "repos/$R/rulesets" --input - <<'EOF'
{
  "name": "main",
  "target": "branch",
  "enforcement": "active",
  "bypass_actors": [],
  "conditions": {"ref_name": {"include": ["~DEFAULT_BRANCH"], "exclude": []}},
  "rules": [
    {"type": "deletion"},
    {"type": "non_fast_forward"},
    {"type": "required_signatures"},
    {"type": "pull_request", "parameters": {
      "allowed_merge_methods": ["merge", "squash"],
      "required_approving_review_count": 0,
      "dismiss_stale_reviews_on_push": false,
      "require_code_owner_review": false,
      "require_last_push_approval": false,
      "required_review_thread_resolution": false}},
    {"type": "required_status_checks", "parameters": {
      "strict_required_status_checks_policy": true,
      "do_not_enforce_on_create": false,
      "required_status_checks": [{"context": "CHECK NAME 1"}, {"context": "Linked issue"}]}}
  ]
}
EOF
```

Verify:

```bash
gh api "repos/$R/rulesets" -q '.[] | "\(.id) \(.name) \(.enforcement)"'
gh api "repos/$R/rulesets/<id>" -q '{bypass_actors, rules: [.rules[] | {type, parameters}]}'
gh api "repos/$R/branches/main/protection" 2>&1 | tail -1    # "Branch not protected": no classic rule competing with the ruleset
gh api "repos/$R/commits?per_page=20" -q '.[] | "\(.sha[0:7]) \(.commit.verification.verified) \(.commit.verification.reason)"'
```

Expected: every commit on `main` after the ruleset reports `true valid`.

Required checks and conditional jobs: GitHub counts a skipped required check
as passing. If a required job has an `if:`, add a gate job with
`if: always()` that fails unless every job it depends on succeeded, and make
the gate job the required check. `husterk/keith-huster-dot-com-site`'s
`ci.yml` has an example. A required check that never runs blocks every merge,
so the names must match exactly.

With strict checks on, update a PR branch by rebasing locally, then run
`git push --force-with-lease`. Don't use GitHub's "Update branch" button.

## 5. GitHub Actions

| Setting                            | Value                                                                                                                                                                                                                                                                          |
| ---------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Allowed actions                    | Selected: GitHub-owned, plus the exact third-party patterns the workflows use. Verified creators off. Actions owned by husterk, such as `husterk/.github/actions/linked-issue`, need no pattern: dotfiles runs it with only `jdx/mise-action@*` and the Nix installer allowed. |
| SHA pinning                        | Required                                                                                                                                                                                                                                                                       |
| Default `GITHUB_TOKEN` permissions | Read-only, and it cannot approve PRs                                                                                                                                                                                                                                           |
| Fork PR workflow approval          | All external contributors                                                                                                                                                                                                                                                      |
| Workflow files                     | Top-level `permissions: contents: read`. Grant more per job, only where a job needs it.                                                                                                                                                                                        |

List the third-party actions a repo uses:

```bash
grep -rhoE 'uses: [^ ]+' .github/workflows | sed 's/uses: //; s/@.*//' | sort -u
grep -rnE 'uses: [^ ]+@' .github/workflows | grep -vE '@[0-9a-f]{40}'    # unpinned actions; expect no output
```

Set:

```bash
gh api -X PUT "repos/$R/actions/permissions" -F enabled=true -f allowed_actions=selected -F sha_pinning_required=true
gh api -X PUT "repos/$R/actions/permissions/selected-actions" --input - <<'EOF'
{"github_owned_allowed": true, "verified_allowed": false, "patterns_allowed": ["jdx/mise-action@*"]}
EOF
gh api -X PUT "repos/$R/actions/permissions/workflow" -f default_workflow_permissions=read -F can_approve_pull_request_reviews=false
gh api -X PUT "repos/$R/actions/permissions/fork-pr-contributor-approval" -f approval_policy=all_external_contributors
```

Verify:

```bash
gh api "repos/$R/actions/permissions"
gh api "repos/$R/actions/permissions/selected-actions"
gh api "repos/$R/actions/permissions/workflow"
gh api "repos/$R/actions/permissions/fork-pr-contributor-approval"
```

Workflow behaviors to know:

- `sha_pinning_required` covers every action, including `husterk/.github`'s
  own. Reusable workflows are exempt and may still be referenced by tag.

- A push made with `GITHUB_TOKEN` starts no workflow runs. A bot that commits
  to a PR branch that way leaves the checks pending or stuck at
  `action_required`. `husterk/dotfiles` removed its mise lockfile bot for this
  reason. Renovate updates `mise.lock` itself.
- Public repos get Actions minutes free, including macOS runners, so a full
  build on every PR costs nothing.

## 6. Secrets and environments

| Item                           | Expected                                                                                                                                                                                                    |
| ------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Repository secrets             | None that can deploy or unlock production. A repo secret is readable from every branch of the repo.                                                                                                         |
| Production credentials         | An environment secret on a `production` environment whose deployment branch policy allows only `main`                                                                                                       |
| 1Password                      | One service account per repo and purpose. Its vault holds only what that workflow needs.                                                                                                                    |
| PR preview or test credentials | A separate environment and service account, never production's                                                                                                                                              |
| Bot PRs                        | Skip any job that loads credentials when `github.event.pull_request.user.login == 'renovate[bot]'`. Renovate branches live in the same repo and pass the usual `head.repo == github.repository` fork guard. |
| Ordering                       | Load secrets after `install` steps only if you trust every dependency. Dependency code runs in later steps that can read exported environment variables.                                                    |

Verify:

```bash
gh secret list --repo "$R"
gh variable list --repo "$R"
gh api "repos/$R/environments" -q '.environments[] | {name, rules: [.protection_rules[]?.type], branch_policy: .deployment_branch_policy}'
for e in $(gh api "repos/$R/environments" -q '.environments[].name'); do echo "== $e"; gh secret list --repo "$R" --env "$e"; done
grep -rn 'secrets\.' .github/workflows
```

## 7. Renovate (Default)

1. Add the repo to the Renovate app (section 0).
2. Copy `templates/renovate.json`. It extends
   `github>husterk/.github//renovate/default#vX.Y.Z`, the base every repo
   shares, and `//renovate/mise#vX.Y.Z` for repos that pin tools with mise.
   Drop the mise preset if the repo has no `mise.toml`. Add only what is
   specific to the repo after the `extends`. `labels` and `schedule` replace
   the preset's value, and `packageRules` add to it.
3. Keep the Dependabot security updates off (section 3).
4. Renovate's `renovate-config` manager bumps the pinned preset tag in a PR
   when `husterk/.github` releases a new version.

Traps found in September 2026:

| Trap                                                                                                                                | Fix                                                                                                                                                                                                             |
| ----------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `automergeStrategy` without `automerge: true` does nothing                                                                          | Set `automerge` on purpose or leave both out. Your default is manual merges.                                                                                                                                    |
| `matchPackageNames` matches the resolved package name, such as `mvdan/sh` for mise's `shfmt`, so group rules silently match nothing | Use `matchDepNames` for names as written in `mise.toml`. It doesn't matter for npm, where the two names are the same.                                                                                           |
| A tool with no GitHub releases, such as mise's `op` (1Password CLI), fails lookup and puts a warning on the dashboard               | The mise preset reads 1Password's release history page as a custom datasource. A single-version feed is not enough: without a `mise.lock`, Renovate cannot find the current version in it and proposes nothing. |
| `rangeStrategy: pin` rejects versions from a custom datasource as `invalid-value`, silently                                         | Set `rangeStrategy: replace` on that package rule, as the mise preset does                                                                                                                                      |
| Per-dependency lookup failures never appear as warning-level log lines                                                              | Check `.deps[].warnings` in the dry-run output as well as the log level, as `scripts/self-test.sh` does                                                                                                         |
| "Awaiting schedule" on the dashboard looks like Renovate is broken                                                                  | Tick one box on the Dependency Dashboard issue to get a PR now                                                                                                                                                  |

Test a config change locally before pushing it. Run this from the repo root.
It only looks up versions and writes nothing to GitHub:

```bash
RENOVATE_TOKEN=$(gh auth token) GITHUB_COM_TOKEN=$(gh auth token) LOG_LEVEL=debug LOG_FORMAT=json \
  nix run nixpkgs#renovate -- --platform=local --dry-run=lookup --repository-cache=disabled 2>&1 | grep '^{' > /tmp/renovate.json
jq -r 'select(.level>=40) | .msg' /tmp/renovate.json | sort -u     # warnings: expect none
jq -c 'select(.msg=="packageFiles with updates") | .config[]?[]?.deps[]? | select(.updates|length>0) | {depName, branches: [.updates[].branchName]}' /tmp/renovate.json
```

Verify on GitHub: the Dependency Dashboard issue exists, shows no warnings,
and the first Renovate PR passes every required check with a signed head
commit:

```bash
gh issue list --repo "$R" --search "Dependency Dashboard in:title"
gh api "repos/$R/commits/$(gh pr view <n> --repo "$R" --json headRefOid -q .headRefOid)" -q .commit.verification
```

## 8. Working conventions (Default)

- **Issue first.** Every change starts from an issue with checkable
  acceptance criteria. One branch and one PR per issue. Name the branch
  `<type>/<issue>-<slug>`, and put `Closes #<n>` in the PR body.
- **Linked issue check.** Copy `templates/pr-policy.yml`, which runs
  `husterk/.github/actions/linked-issue` pinned by SHA. The action fails a PR
  whose body doesn't close an open issue, exempts `renovate[bot]`,
  `github-actions[bot]` and `dependabot[bot]`, and needs only `issues: read`.
  The job keeps the name `Linked issue`, so add that to the required checks.
  It is a composite action rather than a reusable workflow on purpose: a
  reusable workflow's check is named `<caller job> / <called job>`.
- **Commits.** Use conventional commits, with a body that explains why. Never
  put `#<n>` in a commit message, because the PR body carries the link. Sign
  every commit through 1Password.
- **Verify before merging.** Run each acceptance criterion and post the
  commands and results as a comment on the issue.
- **CLAUDE.md.** Give the rules, the commands, and a table mapping each
  required CI job to its local command. Where a repo departs from this guide,
  say so there, with the reason.
- **Labels.** At least `task`, `bug`, `build`, `dependencies` and `security`.
  Copy them with `gh label clone husterk/.github --repo "$R"`, which adds
  missing labels and never changes existing ones. Renovate uses
  `dependencies`, and the default issue forms set `task` and `bug`. A repo with its own scheme, such as
  `area:*`, `type:*` or milestones, keeps it.

## 9. Presentation

| Item                                                   | Expected                                                                                                                                                                                | Set or check                                                                                                                                                  |
| ------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Description and homepage                               | Set                                                                                                                                                                                     | `gh repo edit "$R" --description "..." --homepage https://keithhuster.com`                                                                                    |
| Topics                                                 | Up to 20 that describe the stack                                                                                                                                                        | `gh repo edit "$R" --add-topic nix --add-topic macos`                                                                                                         |
| LICENSE                                                | Present. GitHub reports `NOASSERTION` when you add terms, such as reserving rights to content, which is fine if intended.                                                               | `gh api "repos/$R" -q .license`                                                                                                                               |
| SECURITY.md, CONTRIBUTING.md, issue forms, PR template | The account defaults from `husterk/.github` apply unless the repo needs its own. A repo's own copy replaces the default, and any issue template of its own replaces every default form. | Read the repo's issue chooser page                                                                                                                            |
| README                                                 | Says what it does and how to run it, with a screenshot if it has a UI                                                                                                                   | Read it                                                                                                                                                       |
| Screenshot                                             | Checked by eye for session names, paths, hostnames and notifications. Converted to sRGB, metadata stripped.                                                                             | See below                                                                                                                                                     |
| Social preview                                         | 1280x640 PNG                                                                                                                                                                            | Web UI only: Settings, General, Social preview. Verify with `gh api graphql -f query='{repository(owner:"husterk",name:"<repo>"){usesCustomOpenGraphImage}}'` |
| Pinned on profile                                      | If it represents you                                                                                                                                                                    | Section 0                                                                                                                                                     |

macOS screenshots are in the Display P3 color space. Convert them to sRGB
before stripping metadata, or the colors shift:

```bash
nix run nixpkgs#imagemagick -- shot.jpg -profile "/System/Library/ColorSync/Profiles/sRGB Profile.icc" -resize 2000x docs/images/terminal.png
nix run nixpkgs#exiftool -- -all= -overwrite_original docs/images/terminal.png
nix run nixpkgs#exiftool -- -a -G1 docs/images/terminal.png     # only PNG structure fields should remain
```

For the social preview, fit the window onto a 1280x640 canvas instead of
stretching it:

```bash
nix run nixpkgs#imagemagick -- -size 1280x640 'gradient:#3a0fbe-#140432' \( srgb.png -resize x580 \) -gravity center -composite social-preview.png
```

## 10. Local checkout

- Clone with SSH: `git clone git@github.com:$R.git`.
- `git log --show-signature -1` reports `Good "git" signature`.
- For a repo that deploys files onto this Mac, such as dotfiles, prove the
  deploy with the repo's own verify task after any swap of checkouts.

## 11. Audit

From a clone of `husterk/.github`:

```bash
mise run audit -- husterk/<repo>
```

It only reads. It prints PASS, FAIL, WARN or INFO for every rule in sections 2
to 8 and exits 1 on any FAIL.

To see the raw settings behind a result, paste this into zsh after setting
`R`:

```bash
for p in "repos/$R" "repos/$R/rulesets" "repos/$R/actions/permissions" \
         "repos/$R/actions/permissions/selected-actions" "repos/$R/actions/permissions/workflow" \
         "repos/$R/actions/permissions/fork-pr-contributor-approval" \
         "repos/$R/private-vulnerability-reporting" "repos/$R/automated-security-fixes" \
         "repos/$R/code-scanning/default-setup" "repos/$R/environments"; do
  echo "== $p"; gh api "$p" 2>&1 | head -c 3000; echo
done
echo "== dependabot alerts on?"; gh api -i "repos/$R/vulnerability-alerts" 2>&1 | head -1
echo "== secrets"; gh secret list --repo "$R"
echo "== signatures on main"; gh api "repos/$R/commits?per_page=50" -q '.[] | "\(.commit.verification.verified) \(.commit.verification.reason)"' | sort | uniq -c
echo "== labels"; gh label list --repo "$R" --json name -q '[.[].name]'
```

Then clone the repo and run the 1b scans on its full history.

An audit is done when:

- Every row in sections 2 to 6 matches, or the repo's `CLAUDE.md` explains why
  it doesn't.
- Both history scans are clean.
- Every finding has an issue in that repo with acceptance criteria and a
  recommended fix.
