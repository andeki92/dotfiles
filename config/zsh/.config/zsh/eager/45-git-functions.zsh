# Custom Git Functions
# Push and, if a PR is suggested, create the PR with defaults and then open it in the browser.
function git_push_with_pr() {
  local tmpfile=$(mktemp)
  trap 'rm -f "$tmpfile"' EXIT
  git push 2>&1 | tee "$tmpfile"
  local rc=${pipestatus[1]}
  if grep -qiE 'create a pull request|github.com/.*/pull/new/' "$tmpfile"; then
    gh pr create --fill && gh pr view --web
  fi
  return $rc
} 