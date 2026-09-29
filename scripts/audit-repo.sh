#!/usr/bin/env bash
set -euo pipefail

# Compare one repository with the baseline in docs/public-repos.md or
# docs/private-repos.md. Read-only: every call is a GET.
#
#   audit-repo.sh OWNER/REPO
#
# FAIL marks a baseline rule the repository breaks. WARN marks a default the
# repository may skip with a reason in its CLAUDE.md. Exits 1 when any FAIL is
# reported.

repo="${1:?usage: audit-repo.sh OWNER/REPO}"
fails=0
warns=0

pass() { echo "PASS  $1"; }
fail() {
  echo "FAIL  $1"
  fails=$((fails + 1))
}
warn() {
  echo "WARN  $1"
  warns=$((warns + 1))
}
info() { echo "INFO  $1"; }

# expect SEVERITY LABEL ACTUAL EXPECTED
expect() {
  if [ "$3" = "$4" ]; then
    pass "$2"
  else
    "$1" "$2 (is '$3', want '$4')"
  fi
}

api() { gh api "$@" 2> /dev/null || true; }

# field JSON FILTER: jq on possibly empty JSON, printing "unknown" only for null
field() {
  local json="${1:-}"
  [ -n "$json" ] || json='{}'
  jq -r "($2) as \$v | if \$v == null then \"unknown\" else \$v end" <<< "$json"
}

meta="$(gh api "repos/$repo")"
visibility="$(jq -r .visibility <<< "$meta")"
branch="$(jq -r .default_branch <<< "$meta")"

echo "== $repo ($visibility, default branch $branch)"

echo "-- Settings"
expect fail "rebase merging off" "$(jq -r .allow_rebase_merge <<< "$meta")" false
expect fail "squash merging on" "$(jq -r .allow_squash_merge <<< "$meta")" true
expect warn "merge commits on" "$(jq -r .allow_merge_commit <<< "$meta")" true
expect fail "delete head branches on" "$(jq -r .delete_branch_on_merge <<< "$meta")" true
expect warn "auto-merge on" "$(jq -r .allow_auto_merge <<< "$meta")" true
expect fail "issues on" "$(jq -r .has_issues <<< "$meta")" true
expect warn "wiki off" "$(jq -r .has_wiki <<< "$meta")" false
expect warn "projects off" "$(jq -r .has_projects <<< "$meta")" false

echo "-- Security"
alerts="$(gh api -i "repos/$repo/vulnerability-alerts" 2> /dev/null | head -1 | awk '{print $2}' || true)"
expect fail "Dependabot alerts on" "${alerts:-none}" 204
expect warn "Dependabot security updates off (Renovate handles them)" \
  "$(api "repos/$repo/automated-security-fixes" -q .enabled)" false
if [ "$visibility" = public ]; then
  expect fail "secret scanning on" "$(jq -r '.security_and_analysis.secret_scanning.status' <<< "$meta")" enabled
  expect fail "push protection on" "$(jq -r '.security_and_analysis.secret_scanning_push_protection.status' <<< "$meta")" enabled
  expect fail "private vulnerability reporting on" "$(api "repos/$repo/private-vulnerability-reporting" -q .enabled)" true
  expect fail "CodeQL default setup configured" "$(api "repos/$repo/code-scanning/default-setup" -q .state)" configured
fi

echo "-- Actions"
workflow="$(api "repos/$repo/actions/permissions/workflow")"
expect fail "default token read-only" "$(field "$workflow" .default_workflow_permissions)" read
expect fail "token cannot approve PRs" "$(field "$workflow" .can_approve_pull_request_reviews)" false
actions="$(api "repos/$repo/actions/permissions")"
expect fail "only selected actions allowed" "$(field "$actions" .allowed_actions)" selected
expect fail "actions pinned by SHA required" "$(field "$actions" .sha_pinning_required)" true
if [ "$visibility" = public ]; then
  expect fail "fork PRs need approval for all outside contributors" \
    "$(api "repos/$repo/actions/permissions/fork-pr-contributor-approval" -q .approval_policy)" all_external_contributors
fi

echo "-- Ruleset on $branch"
ruleset=""
for id in $(api "repos/$repo/rulesets" -q '.[] | select(.target == "branch" and .enforcement == "active") | .id'); do
  candidate="$(api "repos/$repo/rulesets/$id")"
  if jq -e --arg b "refs/heads/$branch" \
    '.conditions.ref_name.include | index("~DEFAULT_BRANCH") or index($b)' <<< "$candidate" > /dev/null; then
    ruleset="$candidate"
    break
  fi
done
if [ -z "$ruleset" ]; then
  fail "an active ruleset covers $branch"
else
  pass "an active ruleset covers $branch ($(jq -r .name <<< "$ruleset"))"
  expect fail "ruleset has no bypass actors" "$(jq -r '.bypass_actors | length' <<< "$ruleset")" 0
  for rule in deletion non_fast_forward required_signatures pull_request required_status_checks; do
    expect fail "rule $rule" "$(jq -r --arg r "$rule" '[.rules[].type] | index($r) != null' <<< "$ruleset")" true
  done
  expect fail "merge methods exclude rebase" \
    "$(jq -r '[.rules[] | select(.type == "pull_request") | .parameters.allowed_merge_methods[]?] | index("rebase") == null' <<< "$ruleset")" true
  expect warn "required checks are strict" \
    "$(jq -r '[.rules[] | select(.type == "required_status_checks") | .parameters.strict_required_status_checks_policy][0] // false' <<< "$ruleset")" true
  expect warn "Linked issue is a required check" \
    "$(jq -r '[.rules[] | select(.type == "required_status_checks") | .parameters.required_status_checks[]?.context] | index("Linked issue") != null' <<< "$ruleset")" true
fi

echo "-- Commits on $branch"
commits="$(api "repos/$repo/commits?sha=$branch&per_page=20")"
expect fail "newest commit is signed and verified" \
  "$(field "$commits" '.[0].commit.verification.verified')" true
info "unverified commits among the newest 20: $(field "$commits" '[.[] | select(.commit.verification.verified | not)] | length')"

echo "-- Labels"
labels="$(api "repos/$repo/labels?per_page=100" -q '.[].name')"
for label in task bug build dependencies security; do
  if grep -qx "$label" <<< "$labels"; then pass "label $label"; else warn "label $label missing (gh label clone husterk/.github --repo $repo)"; fi
done

echo "-- Shared config"
renovate=""
for path in renovate.json .github/renovate.json renovate.json5 .github/renovate.json5; do
  renovate="$(api "repos/$repo/contents/$path" -q .content | base64 --decode 2> /dev/null || true)"
  [ -n "$renovate" ] && break
done
if [ -z "$renovate" ]; then
  warn "no Renovate config"
elif grep -q 'github>husterk/.github//renovate/default' <<< "$renovate"; then
  pass "Renovate extends the shared default preset"
else
  warn "Renovate does not extend github>husterk/.github//renovate/default"
fi
workflows="$(api "repos/$repo/contents/.github/workflows" -q '.[].name')"
if grep -qx 'update-mise-lockfile.yml' <<< "$workflows"; then
  warn "update-mise-lockfile.yml present; Renovate updates mise.lock itself"
fi
linked=false
for wf in $workflows; do
  if api "repos/$repo/contents/.github/workflows/$wf" -q .content | base64 --decode 2> /dev/null | grep -q 'actions/linked-issue'; then
    linked=true
    break
  fi
done
expect warn "a workflow runs the linked-issue action" "$linked" true

echo "-- Secrets"
for name in $(api "repos/$repo/actions/secrets" -q '.secrets[].name'); do
  info "repository secret $name is readable from every branch"
done
for env in $(api "repos/$repo/environments" -q '.environments[].name'); do
  policy="$(api "repos/$repo/environments/$env" -q '.deployment_branch_policy // "none"')"
  secrets="$(api "repos/$repo/environments/$env/secrets" -q '.total_count')"
  if [ "${secrets:-0}" -gt 0 ] && [ "$policy" = none ]; then
    warn "environment $env holds secrets but has no deployment branch policy"
  fi
done

echo "== $repo: $fails fail, $warns warn"
[ "$fails" -eq 0 ]
