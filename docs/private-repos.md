# Private repo guide: create and audit

Use this guide to create a new private repo under `husterk` or to audit an
existing one. It is the companion to `public-repos.md`, and it uses the same
tooling from `husterk/.github`: `mise run audit -- husterk/<repo>`, the files
in `templates/`, the Renovate presets and the linked-issue action. Where a private
repo follows the same rule as a public one, this guide repeats the rule so it
works on its own. Where GitHub treats private repos differently, this guide
says so and gives the substitute.

Each item comes with a command to set it and a command to verify it. Items
marked **Default** are your conventions. Skip one for a repo when that repo has
a reason, and write the reason into the repo's `CLAUDE.md`. The live reference
for a private repo is `husterk/dotfiles-private`.

Set the target once per shell, and quote every `gh api` path that contains a
`?`, because zsh treats it as a glob:

```bash
R=husterk/<repo>
```

## What differs from a public repo

Verified on 2026-09-28 against `husterk/dotfiles-private`:

| Feature                                 | Private repo under `husterk`                                                                                                                                                                                                                                                                                                                                                  | Substitute                                                                 |
| --------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------- |
| Rulesets, including required signatures | ✅ Work: that repo has an active ruleset with `required_signatures`                                                                                                                                                                                                                                                                                                           | None needed                                                                |
| Secret scanning and push protection     | ❌ Not offered (`security_and_analysis` is `null`)                                                                                                                                                                                                                                                                                                                            | gitleaks in CI, plus a full-history scan on every audit                    |
| CodeQL code scanning                    | ❌ Not offered (the API returns 403)                                                                                                                                                                                                                                                                                                                                          | Linters in CI. Put public-facing code in a public repo if it needs CodeQL. |
| Private vulnerability reporting         | ❌ Not offered (404)                                                                                                                                                                                                                                                                                                                                                          | Not needed. Nobody outside the repo can see it.                            |
| Fork PR approval policy                 | ❌ Not offered (422)                                                                                                                                                                                                                                                                                                                                                          | Control who has access (section 5)                                         |
| Dependabot alerts                       | ✅ Work (204)                                                                                                                                                                                                                                                                                                                                                                 | None needed                                                                |
| Actions allowlist and SHA pinning       | ✅ Enforced, including third-party patterns, despite the REST reference saying `patterns_allowed` "only applies to public repositories". A probe workflow was rejected at startup: "not allowed ... because all actions must be from a repository owned by husterk, created by GitHub, or match the pattern ... All actions must also be pinned to a full-length commit SHA." | None needed                                                                |
| Actions minutes                         | Billed against the plan's quota                                                                                                                                                                                                                                                                                                                                               | Section 4                                                                  |

Inferred: rulesets on private repos need a paid plan such as GitHub Pro, so
this account has one. The plan itself was not checked, because the `gh` token
cannot read it.

## 0. Decide whether the repo might ever go public

Decide this at creation and write the answer into `CLAUDE.md`, because the
answer changes how you write commits from day one.

- **Might go public:** follow section 1 of the public guide from the first
  commit. Keep private names, vault IDs, employer terms and IPs out of files
  and commit messages. Put anything private in a separate overlay repo, the
  way `husterk/dotfiles-private` serves `husterk/dotfiles`. Cleaning history
  later costs a full rewrite and a new repo.
- **Stays private:** private details can live in the repo. Secrets still
  cannot. They go in 1Password, because private repos get no secret scanning
  and anyone you ever grant access can read the whole history.

## 1. Content and history

Even a private repo must hold no secrets. With no push protection, nothing
stops one at push time, so scan each branch in CI and scan the full history
on every audit:

```bash
nix run nixpkgs#gitleaks -- git --no-banner --redact /path/to/clone
nix run nixpkgs#trufflehog -- git file:///path/to/clone --no-update --json | nix run nixpkgs#jq -- -r '"\(.DetectorName) verified=\(.Verified) \(.SourceMetadata.Data.Git.file)"'
```

Expected: gitleaks prints `no leaks found`, and trufflehog prints nothing.
When a scanner finds a real secret, rotate it first. Removing it from the
history comes second, because anyone with access may already have a copy.

**Default:** add a CI job that runs gitleaks on the PR's commits, and make it
a required check. Pin the tool through mise, for example
`aqua:gitleaks/gitleaks`, and run
`gitleaks git --log-opts="origin/main..HEAD" --redact`.

## 2. Repo settings

The values match a public repo:

| Setting                                                     | Value                           | Why                                                                                                   |
| ----------------------------------------------------------- | ------------------------------- | ----------------------------------------------------------------------------------------------------- |
| Merge commits                                               | Allowed                         | GitHub signs the merge commit                                                                         |
| Squash merging                                              | Allowed. Commit title: PR title | GitHub signs the squash commit                                                                        |
| Rebase merging                                              | **Off**                         | GitHub rewrites each commit and does not sign it. Vigilant mode then shows every one as "Unverified". |
| Auto-merge, delete head branches, suggest updating branches | On                              |                                                                                                       |
| Issues                                                      | On                              | **Default:** issue-first workflow                                                                     |
| Wiki, Projects, Discussions                                 | Off unless used                 |                                                                                                       |
| Allow forking                                               | Off                             | Inferred: GitHub may only enforce this for organization repos. It is harmless to set.                 |

Set:

```bash
gh api -X PATCH "repos/$R" \
  -F allow_merge_commit=true -F allow_squash_merge=true -F allow_rebase_merge=false \
  -F allow_auto_merge=true -F delete_branch_on_merge=true -F allow_update_branch=true \
  -F has_issues=true -F has_wiki=false -F has_projects=false -F has_discussions=false \
  -F allow_forking=false \
  -f squash_merge_commit_title=PR_TITLE -f squash_merge_commit_message=COMMIT_MESSAGES
```

Verify:

```bash
gh api "repos/$R" -q '{visibility,allow_merge_commit,allow_squash_merge,allow_rebase_merge,allow_auto_merge,delete_branch_on_merge,allow_update_branch,has_issues,has_wiki,has_projects,has_discussions,allow_forking,squash_merge_commit_title}'
```

## 3. Ruleset for `main`

Same as a public repo: one ruleset on the default branch with no bypass
actors. It restricts deletions, blocks force pushes, requires signed commits,
requires a PR with merge methods `merge` and `squash` (never `rebase`), and
enforces strict required status checks.

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
gh api "repos/$R/commits?per_page=20" -q '.[] | "\(.sha[0:7]) \(.commit.verification.verified) \(.commit.verification.reason)"'
```

Create the ruleset after CI has run once, so the check names already exist. A
required check that never runs blocks every merge. GitHub counts a skipped
required check as passing, so any required job with an `if:` needs a gate job
that runs with `if: always()`. With strict checks on, update a PR branch by
rebasing locally, then run `git push --force-with-lease`. Don't use GitHub's
"Update branch" button.

## 4. GitHub Actions

| Setting                            | Value                                                                                                                                                                                                   |
| ---------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Allowed actions                    | Selected: GitHub-owned, plus the exact third-party patterns the workflows use. Actions owned by husterk need no pattern.                                                                                |
| SHA pinning                        | Required                                                                                                                                                                                                |
| Default `GITHUB_TOKEN` permissions | Read-only, and it cannot approve PRs                                                                                                                                                                    |
| Access from other repos' workflows | None                                                                                                                                                                                                    |
| Minutes                            | Every run counts against the quota. Inferred from GitHub's pricing: macOS runners count about 10 times the minutes of Linux ones. Run macOS jobs only when paths that affect them change, or on `main`. |

List the third-party actions a repo uses, and find any that aren't pinned:

```bash
grep -rhoE 'uses: [^ ]+' .github/workflows | sed 's/uses: //; s/@.*//' | sort -u
grep -rnE 'uses: [^ ]+@' .github/workflows | grep -vE '@[0-9a-f]{40}'    # expect no output
```

Set:

```bash
gh api -X PUT "repos/$R/actions/permissions" -F enabled=true -f allowed_actions=selected -F sha_pinning_required=true
gh api -X PUT "repos/$R/actions/permissions/selected-actions" --input - <<'EOF'
{"github_owned_allowed": true, "verified_allowed": false, "patterns_allowed": ["jdx/mise-action@*"]}
EOF
gh api -X PUT "repos/$R/actions/permissions/workflow" -f default_workflow_permissions=read -F can_approve_pull_request_reviews=false
gh api -X PUT "repos/$R/actions/permissions/access" -f access_level=none
```

Verify:

```bash
gh api "repos/$R/actions/permissions"
gh api "repos/$R/actions/permissions/selected-actions"
gh api "repos/$R/actions/permissions/workflow"
gh api "repos/$R/actions/permissions/access"
```

A push made with `GITHUB_TOKEN` starts no workflow runs. A bot that commits
to a PR branch that way leaves the checks stuck. Renovate updates lock files
itself, so no lockfile bot is needed.

## 5. Access

A private repo's security depends on who can read it. Check every route in:

```bash
gh api "repos/$R/collaborators" -q '.[] | "\(.login) \(.role_name)"'
gh api "repos/$R/invitations" -q '.[] | .invitee.login'
gh api "repos/$R/keys" -q '.[] | "\(.id) \(.title) read_only=\(.read_only) \(.created_at)"'
gh api "repos/$R/hooks" -q '.[] | "\(.id) \(.config.url) active=\(.active)"'
```

The installations API rejects a normal `gh` token with a 403 (verified), so
check GitHub App access at https://github.com/settings/installations. Open
Configure on each app and read its repository list.

Expected:

- Only you are a collaborator, and there are no pending invitations.
- Each deploy key is read-only and belongs to something still running.
- Each webhook goes to a service you still use.
- A GitHub App lists the repo only if it should, and every app with access is
  set to "Only select repositories".

## 6. Secrets and environments

| Item                   | Expected                                                                                                                     |
| ---------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| Repository secrets     | None that can deploy or unlock production. A repo secret is readable from every branch.                                      |
| Production credentials | An environment secret on a `production` environment whose deployment branch policy allows only `main`                        |
| 1Password              | One service account per repo and purpose. Its vault holds only what that workflow needs. Delete accounts whose repo is gone. |
| Bot PRs                | Skip any job that loads credentials when `github.event.pull_request.user.login == 'renovate[bot]'`                           |

Verify:

```bash
gh secret list --repo "$R"
gh api "repos/$R/environments" -q '.environments[] | {name, rules: [.protection_rules[]?.type], branch_policy: .deployment_branch_policy}'
for e in $(gh api "repos/$R/environments" -q '.environments[].name'); do echo "== $e"; gh secret list --repo "$R" --env "$e"; done
grep -rn 'secrets\.' .github/workflows
```

## 7. Dependabot and Renovate (Default)

- Turn Dependabot alerts on and Dependabot security updates off, and let
  Renovate open the update PRs:

    ```bash
    gh api -X PUT "repos/$R/vulnerability-alerts"
    gh api -X DELETE "repos/$R/automated-security-fixes"
    gh api -i "repos/$R/vulnerability-alerts" | head -1     # 204 = on
    gh api "repos/$R/dependabot/alerts" -q 'map(select(.state=="open"))|length'
    ```

- Add the repo to the Renovate app ("Only select repositories"). Copy
  `templates/renovate.json`, which extends the shared presets at a pinned tag.
  The presets live in a public repo, so a private repo can extend them. The
  reverse does not work: a public repo's Renovate token cannot read a private
  preset.
- The shared presets already avoid the traps listed in section 7 of the
  public guide: `automergeStrategy` without `automerge`, `matchPackageNames`
  on mise names, and the 1Password CLI lookup.

## 8. Working conventions (Default)

These are the same as in a public repo:

- **Issue first.** One branch and one PR per issue. Name the branch
  `<type>/<issue>-<slug>`, and put `Closes #<n>` in the PR body.
- **Linked issue check.** Copy `templates/pr-policy.yml` and make
  `Linked issue` a required check.
- **Commits.** Use conventional commits, with a body that explains why. Never
  put `#<n>` in a commit message, and sign every commit.
- **Verify before merging.** Run each acceptance criterion and post the
  results on the issue.
- **CLAUDE.md.** Give the rules, the commands, and a table mapping each CI job
  to its local command. State whether the repo might go public (section 0).
- **Labels.** `task`, `bug`, `build`, `dependencies`, `security`. Copy them
  with `gh label clone husterk/.github --repo "$R"`.

## 9. Lifecycle: archive and delete

Private repos pile up. When a repo stops being used:

1. Archive it with `gh repo archive "$R" --yes`. Reverse it with `gh repo unarchive`.
2. Remove it from the Renovate app and any other app installation, and delete
   its 1Password service account.
3. When nothing depends on it, decide whether to delete it. An archived
   private repo still holds its full history, secrets that were committed by
   mistake included. If you might want the history, take a mirror first:
   `git clone --mirror git@github.com:$R.git`. The mirror does not include
   issues or PR discussion. Then run `gh repo delete "$R"`, which cannot be
   undone.
4. Remove references to the repo from other repos, memory files and docs.

List the candidates:

```bash
gh repo list husterk --visibility private --limit 200 --json name,isArchived,pushedAt -q '.[] | "\(.isArchived) \(.pushedAt[0:10]) \(.name)"' | sort
```

## 10. Audit

From a clone of `husterk/.github`:

```bash
mise run audit -- husterk/<repo>
```

To see the raw settings behind a result, paste this into zsh after setting
`R`:

```bash
for p in "repos/$R" "repos/$R/rulesets" "repos/$R/actions/permissions" \
         "repos/$R/actions/permissions/selected-actions" "repos/$R/actions/permissions/workflow" \
         "repos/$R/actions/permissions/access" "repos/$R/automated-security-fixes" \
         "repos/$R/environments" "repos/$R/collaborators" "repos/$R/keys" "repos/$R/hooks"; do
  echo "== $p"; gh api "$p" 2>&1 | head -c 3000; echo
done
echo "== dependabot alerts on?"; gh api -i "repos/$R/vulnerability-alerts" 2>&1 | head -1
echo "== secrets"; gh secret list --repo "$R"
echo "== signatures on main"; gh api "repos/$R/commits?per_page=50" -q '.[] | "\(.commit.verification.verified) \(.commit.verification.reason)"' | sort | uniq -c
```

Then clone the repo and run the section 1 scans on its full history.

An audit is done when:

- Every row in sections 2 to 7 matches, or the repo's `CLAUDE.md` explains why
  it doesn't.
- Both history scans are clean, or every finding has been rotated.
- Section 0 is answered in `CLAUDE.md`.
- Every finding has an issue in that repo with acceptance criteria and a
  recommended fix.
