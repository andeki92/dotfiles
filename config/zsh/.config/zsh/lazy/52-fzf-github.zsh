# FZF GitHub & Repository Management
# Unified interface for managing repos and GitHub workflows

# =======================================================
# Main Entry Point: Unified Repo/GitHub Browser
# =======================================================

fgh() {
  local repo action

  while true; do
    # Find all git repos in privatespace
    repo=$(fd -H -t d '^\.git$' ~/privatespace --max-depth 3 --exec dirname 2>/dev/null |
           fzf --ansi \
               --preview='_fgh_repo_preview {}' \
               --preview-window='right:60%' \
               --header='Select repo | [Enter]=Menu [Ctrl-P]=PRs [Ctrl-I]=Issues [Ctrl-B]=Branches [Ctrl-C]=CD [ESC]=Quit' \
               --prompt="Repository > " \
               --pointer="→" \
               --bind='ctrl-p:execute(echo pr)+abort' \
               --bind='ctrl-i:execute(echo issue)+abort' \
               --bind='ctrl-b:execute(echo branch)+abort' \
               --bind='ctrl-c:execute(echo cd)+abort' \
               --bind='ctrl-s:execute(echo status)+abort' \
               --bind='ctrl-l:execute(echo log)+abort')

    # Exit if no repo selected
    [[ -z "$repo" ]] && return

    # Store current dir and cd to repo
    local original_dir="$PWD"
    cd "$repo" || return

    # Check what action was triggered
    if [[ -f /tmp/fzf-action ]]; then
      action=$(cat /tmp/fzf-action)
      rm /tmp/fzf-action
    fi

    # Show action menu if Enter was pressed (no action file created)
    if [[ -z "$action" ]]; then
      action=$(_fgh_action_menu "$(basename "$repo")")
    fi

    # Execute the selected action
    case "$action" in
      pr)     _fgh_pr_browser ;;
      issue)  _fgh_issue_browser ;;
      branch) _fgh_branch_manager ;;
      cd)     echo "Changed to: $repo"; return 0 ;;
      status) git status; read -k 1 "?Press any key to continue..."; continue ;;
      log)    git log --oneline --graph --decorate -20 | less; continue ;;
      *)      cd "$original_dir"; return ;;
    esac

    # Return to original directory after action
    cd "$original_dir"

    # Ask if user wants to continue
    echo -n "\nContinue browsing repos? [Y/n] "
    read -k 1 response
    echo
    [[ "$response" =~ ^[Nn]$ ]] && break
  done
}

# =======================================================
# Helper: Repository Preview
# =======================================================

_fgh_repo_preview() {
  local repo="$1"
  cd "$repo" 2>/dev/null || return

  echo "📁 Repository: $(basename "$repo")"
  echo "📍 Path: $repo"
  echo ""

  # Show git status
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "📊 Status:"
  git status -sb 2>/dev/null || echo "Not a git repository"
  echo ""

  # Show recent commits
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "📝 Recent commits:"
  git log --oneline --decorate --graph -5 2>/dev/null || echo "No commits"
  echo ""

  # Show PR count if gh is available
  if command -v gh >/dev/null 2>&1; then
    local pr_count=$(gh pr list --json number 2>/dev/null | jq '. | length' 2>/dev/null)
    local issue_count=$(gh issue list --json number 2>/dev/null | jq '. | length' 2>/dev/null)
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🔀 Pull Requests: ${pr_count:-0}"
    echo "🎯 Issues: ${issue_count:-0}"
  fi
}

# =======================================================
# Helper: Action Menu
# =======================================================

_fgh_action_menu() {
  local repo_name="$1"

  echo "pr\t🔀 View Pull Requests
issue\t🎯 View Issues
branch\t🌳 Manage Branches
status\t📊 Git Status
log\t📝 Git Log
cd\t📁 Change Directory to $repo_name" |
  fzf --delimiter='\t' \
      --with-nth=2 \
      --prompt="Action > " \
      --pointer="→" \
      --header="Select action for $repo_name" \
      --preview-window='hidden' |
  cut -f1
}

# =======================================================
# PR Browser with Actions
# =======================================================

_fgh_pr_browser() {
  local pr selected action pr_number

  # Check if gh is available
  if ! command -v gh >/dev/null 2>&1; then
    echo "❌ GitHub CLI (gh) is not available"
    return 1
  fi

  while true; do
    # Get PR list
    pr=$(gh pr list --limit 50 --json number,title,author,state,updatedAt,headRefName,labels 2>/dev/null |
         jq -r '.[] | "#\(.number)\t\(.title)\t@\(.author.login)\t[\(.state)]\t\(.headRefName)"' |
         fzf --ansi \
             --delimiter='\t' \
             --with-nth=1,2,3,4 \
             --preview='_fgh_pr_preview {1}' \
             --preview-window='right:65%:wrap' \
             --header='[Enter]=Actions [Ctrl-V]=View Web [Ctrl-C]=Checkout [Ctrl-D]=Diff [ESC]=Back' \
             --prompt="PR > " \
             --pointer="→" \
             --marker="✓" \
             --bind='ctrl-v:execute(gh pr view {1} --web)' \
             --bind='ctrl-c:execute(gh pr checkout {1})+abort' \
             --bind='ctrl-d:execute(gh pr diff {1} --color=always | bat --language=diff --paging=always)')

    # Exit if no PR selected
    [[ -z "$pr" ]] && return

    # Extract PR number
    pr_number=$(echo "$pr" | cut -f1 | sed 's/#//')

    # Show action menu
    action=$(_fgh_pr_action_menu "$pr_number")

    case "$action" in
      view)
        gh pr view "$pr_number"
        read -k 1 "?Press any key to continue..."
        ;;
      checkout)
        gh pr checkout "$pr_number"
        echo "\n✅ Checked out PR #$pr_number"
        read -k 1 "?Press any key to continue..."
        ;;
      diff)
        gh pr diff "$pr_number" --color=always | bat --language=diff --paging=always
        ;;
      approve)
        echo "💬 Approval comment (optional, press Enter to skip):"
        read comment
        if [[ -n "$comment" ]]; then
          gh pr review "$pr_number" --approve --body "$comment"
        else
          gh pr review "$pr_number" --approve
        fi
        echo "✅ Approved PR #$pr_number"
        read -k 1 "?Press any key to continue..."
        ;;
      comment)
        echo "💬 Enter your comment:"
        read comment
        [[ -n "$comment" ]] && gh pr comment "$pr_number" --body "$comment"
        echo "✅ Comment added to PR #$pr_number"
        read -k 1 "?Press any key to continue..."
        ;;
      changes)
        echo "💬 Enter your review comment:"
        read comment
        if [[ -n "$comment" ]]; then
          gh pr review "$pr_number" --request-changes --body "$comment"
        else
          gh pr review "$pr_number" --request-changes
        fi
        echo "✅ Requested changes on PR #$pr_number"
        read -k 1 "?Press any key to continue..."
        ;;
      merge)
        echo "⚠️  Merge PR #$pr_number? [y/N]"
        read -k 1 confirm
        echo
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
          gh pr merge "$pr_number" --squash
          echo "✅ Merged PR #$pr_number"
        fi
        read -k 1 "?Press any key to continue..."
        ;;
      close)
        echo "⚠️  Close PR #$pr_number? [y/N]"
        read -k 1 confirm
        echo
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
          gh pr close "$pr_number"
          echo "✅ Closed PR #$pr_number"
        fi
        read -k 1 "?Press any key to continue..."
        ;;
      web)
        gh pr view "$pr_number" --web
        ;;
      *)
        return
        ;;
    esac
  done
}

# =======================================================
# PR Preview
# =======================================================

_fgh_pr_preview() {
  local pr_number=$(echo "$1" | sed 's/#//')
  gh pr view "$pr_number" 2>/dev/null || echo "Unable to load PR details"
}

# =======================================================
# PR Action Menu
# =======================================================

_fgh_pr_action_menu() {
  local pr_number="$1"

  echo "view\t👁️  View PR Details
checkout\t🔀 Checkout PR Branch
diff\t📝 View Diff
approve\t✅ Approve PR
comment\t💬 Add Comment
changes\t⚠️  Request Changes
merge\t🔄 Merge PR (Squash)
close\t❌ Close PR
web\t🌐 Open in Browser" |
  fzf --delimiter='\t' \
      --with-nth=2 \
      --prompt="PR #$pr_number > " \
      --pointer="→" \
      --header="Select action for PR #$pr_number" \
      --preview-window='hidden' |
  cut -f1
}

# =======================================================
# Issue Browser
# =======================================================

_fgh_issue_browser() {
  local issue selected action issue_number

  # Check if gh is available
  if ! command -v gh >/dev/null 2>&1; then
    echo "❌ GitHub CLI (gh) is not available"
    return 1
  fi

  while true; do
    issue=$(gh issue list --limit 50 --json number,title,state,author,labels 2>/dev/null |
            jq -r '.[] | "#\(.number)\t\(.title)\t@\(.author.login)\t[\(.state)]"' |
            fzf --ansi \
                --delimiter='\t' \
                --with-nth=1,2,3,4 \
                --preview='gh issue view {1}' \
                --preview-window='right:65%:wrap' \
                --header='[Enter]=Actions [Ctrl-V]=View Web [Ctrl-C]=Close [Ctrl-R]=Reopen [ESC]=Back' \
                --prompt="Issue > " \
                --pointer="→" \
                --bind='ctrl-v:execute(gh issue view {1} --web)' \
                --bind='ctrl-c:execute(gh issue close {1})' \
                --bind='ctrl-r:execute(gh issue reopen {1})')

    [[ -z "$issue" ]] && return

    issue_number=$(echo "$issue" | cut -f1 | sed 's/#//')

    action=$(_fgh_issue_action_menu "$issue_number")

    case "$action" in
      view)
        gh issue view "$issue_number"
        read -k 1 "?Press any key to continue..."
        ;;
      comment)
        echo "💬 Enter your comment:"
        read comment
        [[ -n "$comment" ]] && gh issue comment "$issue_number" --body "$comment"
        echo "✅ Comment added to issue #$issue_number"
        read -k 1 "?Press any key to continue..."
        ;;
      close)
        gh issue close "$issue_number"
        echo "✅ Closed issue #$issue_number"
        read -k 1 "?Press any key to continue..."
        ;;
      reopen)
        gh issue reopen "$issue_number"
        echo "✅ Reopened issue #$issue_number"
        read -k 1 "?Press any key to continue..."
        ;;
      web)
        gh pr view "$issue_number" --web
        ;;
      *)
        return
        ;;
    esac
  done
}

# =======================================================
# Issue Action Menu
# =======================================================

_fgh_issue_action_menu() {
  local issue_number="$1"

  echo "view\t👁️  View Issue Details
comment\t💬 Add Comment
close\t❌ Close Issue
reopen\t🔄 Reopen Issue
web\t🌐 Open in Browser" |
  fzf --delimiter='\t' \
      --with-nth=2 \
      --prompt="Issue #$issue_number > " \
      --pointer="→" \
      --header="Select action for Issue #$issue_number" \
      --preview-window='hidden' |
  cut -f1
}

# =======================================================
# Branch Manager
# =======================================================

_fgh_branch_manager() {
  local branch action

  while true; do
    branch=$(git branch --all --sort=-committerdate |
             grep -v HEAD |
             sed 's/^[* ]*//' |
             sed 's#remotes/origin/##' |
             awk '!seen[$0]++' |
             fzf --ansi \
                 --preview='git log --graph --pretty=format:"%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset" --color=always {} -10' \
                 --preview-window='right:65%:wrap' \
                 --header='[Enter]=Checkout [Ctrl-D]=Delete [Ctrl-M]=Merge [Ctrl-P]=Pull [ESC]=Back' \
                 --prompt="Branch > " \
                 --pointer="→" \
                 --bind='ctrl-d:execute(git branch -d {})' \
                 --bind='ctrl-m:execute(git merge {})+abort' \
                 --bind='ctrl-p:execute(git pull origin {})+abort')

    [[ -z "$branch" ]] && return

    action=$(_fgh_branch_action_menu "$branch")

    case "$action" in
      checkout)
        git checkout "$branch"
        echo "✅ Checked out branch: $branch"
        read -k 1 "?Press any key to continue..."
        ;;
      delete)
        echo "⚠️  Delete branch '$branch'? [y/N]"
        read -k 1 confirm
        echo
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
          git branch -d "$branch" 2>/dev/null || git branch -D "$branch"
          echo "✅ Deleted branch: $branch"
        fi
        read -k 1 "?Press any key to continue..."
        ;;
      merge)
        git merge "$branch"
        echo "✅ Merged branch: $branch"
        read -k 1 "?Press any key to continue..."
        ;;
      pull)
        git pull origin "$branch"
        echo "✅ Pulled branch: $branch"
        read -k 1 "?Press any key to continue..."
        ;;
      log)
        git log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --color=always "$branch" -20 | less -R
        ;;
      *)
        return
        ;;
    esac
  done
}

# =======================================================
# Branch Action Menu
# =======================================================

_fgh_branch_action_menu() {
  local branch="$1"

  echo "checkout\t🔀 Checkout Branch
delete\t❌ Delete Branch
merge\t🔄 Merge into Current
pull\t⬇️  Pull from Remote
log\t📝 View Branch Log" |
  fzf --delimiter='\t' \
      --with-nth=2 \
      --prompt="Branch: $branch > " \
      --pointer="→" \
      --header="Select action for branch '$branch'" \
      --preview-window='hidden' |
  cut -f1
}

# =======================================================
# Quick Commands (shortcuts to specific workflows)
# =======================================================

# Quick PR browser for current repo
fpr() {
  _fgh_pr_browser
}

# Quick issue browser for current repo
fissue() {
  _fgh_issue_browser
}

# Quick branch manager for current repo
fbr() {
  _fgh_branch_manager
}
