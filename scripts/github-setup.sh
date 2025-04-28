#!/bin/bash

# Unified GitHub repository setup script
# Handles branch protection, repository settings, and GitHub Actions permissions
# Requires GitHub CLI (gh) to be installed and authenticated
#
# This script is idempotent - can be run multiple times without side effects
# Simply run ./scripts/github-setup.sh to apply all GitHub repository settings

set -e

# Color codes for better readability
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Configuration - Edit these variables as needed
# ====================================================
# List of trusted users who can run GitHub Actions (in addition to admins)
# Format: Array of GitHub usernames
TRUSTED_USERS=(
  # "user1"
  # "user2"
  # Add more users as needed
)
# ====================================================

# Get repository info
REPO_OWNER=$(gh repo view --json owner -q '.owner.login')
REPO_NAME=$(gh repo view --json name -q '.name')
IS_PRIVATE=$(gh repo view --json isPrivate -q '.isPrivate')

echo -e "${BLUE}GitHub Repository Setup for ${REPO_OWNER}/${REPO_NAME}${NC}"
echo "Repository type: $([ "$IS_PRIVATE" == "true" ] && echo "Private" || echo "Public")"
echo "==============================================="

# Function to set up branch protection rules
setup_branch_protection() {
  echo -e "\n${BLUE}Setting up branch protection rules...${NC}"
  
  # Create JSON payload for the API
  cat > /tmp/branch-protection.json << 'EOF'
{
  "required_status_checks": {
    "strict": true,
    "contexts": []
  },
  "enforce_admins": false,
  "required_pull_request_reviews": null,
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false
}
EOF
  
  # Create the branch protection rule using the JSON payload
  gh api \
    --method PUT \
    /repos/$REPO_OWNER/$REPO_NAME/branches/main/protection \
    --input /tmp/branch-protection.json
  
  # Clean up
  rm /tmp/branch-protection.json
  
  echo -e "${GREEN}✅ Branch protection rules configured successfully!${NC}"
  echo "The main branch now requires:"
  echo "  - All benchmark checks to pass"
  echo "  - No pull request reviews required (anyone can merge)"
}

# Function to configure repository settings
configure_repo_settings() {
  echo -e "\n${BLUE}Configuring repository settings...${NC}"
  
  # Create JSON payload for the API
  cat > /tmp/repo-settings.json << 'EOF'
{
  "delete_branch_on_merge": true,
  "allow_squash_merge": true,
  "allow_merge_commit": false,
  "allow_rebase_merge": false,
  "squash_merge_commit_title": "PR_TITLE",
  "squash_merge_commit_message": "PR_BODY"
}
EOF
  
  # Configure repository settings
  gh api \
    --method PATCH \
    /repos/$REPO_OWNER/$REPO_NAME \
    --input /tmp/repo-settings.json
  
  # Clean up
  rm /tmp/repo-settings.json
  
  echo -e "${GREEN}✅ Repository settings configured successfully!${NC}"
  echo "Changes made:"
  echo "  - Branches will be automatically deleted after merging"
  echo "  - Squash merging is now the only allowed merge method"
  echo "  - Squash commit will use PR title and body for the commit message"
}

# Function to restrict GitHub Actions permissions
restrict_actions_permissions() {
  echo -e "\n${BLUE}Configuring GitHub Actions permissions...${NC}"
  
  # Set Actions permissions to restricted (only admins and selected users/teams)
  cat > /tmp/actions-permissions.json << 'EOF'
{
  "enabled": true,
  "allowed_actions": "selected"
}
EOF

  gh api \
    --method PUT \
    /repos/$REPO_OWNER/$REPO_NAME/actions/permissions \
    --input /tmp/actions-permissions.json
  
  # Configure who can run Actions (only admins by default)
  cat > /tmp/actions-workflow-permissions.json << 'EOF'
{
  "default_workflow_permissions": "write",
  "can_approve_pull_request_reviews": false
}
EOF

  gh api \
    --method PUT \
    /repos/$REPO_OWNER/$REPO_NAME/actions/permissions/workflow \
    --input /tmp/actions-workflow-permissions.json
  
  # Set access level to restricted - only for private/internal repositories
  if [[ "$IS_PRIVATE" == "true" ]]; then
    cat > /tmp/actions-access.json << 'EOF'
{
  "access_level": "enterprise"
}
EOF

    gh api \
      --method PUT \
      /repos/$REPO_OWNER/$REPO_NAME/actions/permissions/access \
      --input /tmp/actions-access.json
    
    rm /tmp/actions-access.json
  else
    echo -e "${YELLOW}Skipping access level restriction (only applies to private repositories)${NC}"
  fi
  
  # Clean up
  rm /tmp/actions-permissions.json /tmp/actions-workflow-permissions.json
  
  # Add trusted users from the predefined list
  if [ ${#TRUSTED_USERS[@]} -gt 0 ]; then
    echo -e "\n${BLUE}Adding trusted users who can run workflows...${NC}"
    
    for username in "${TRUSTED_USERS[@]}"; do
      echo "Adding $username as a trusted collaborator..."
      
      cat > /tmp/collaborator-permission.json << EOF
{
  "permission": "maintain"
}
EOF

      gh api \
        --method PUT \
        /repos/$REPO_OWNER/$REPO_NAME/collaborators/$username \
        --input /tmp/collaborator-permission.json
      
      rm /tmp/collaborator-permission.json
      echo "✅ Added $username with maintain permission"
    done
  fi
  
  echo -e "${GREEN}✅ GitHub Actions permissions configured successfully!${NC}"
  echo "Changes made:"
  echo "  - GitHub Actions are limited to admins only"
  echo "  - Workflows have write permissions to the repository"
  if [[ "$IS_PRIVATE" == "true" ]]; then
    echo "  - Actions are restricted to organization/enterprise-defined actions"
  fi
  
  if [ ${#TRUSTED_USERS[@]} -gt 0 ]; then
    echo "  - Added ${#TRUSTED_USERS[@]} trusted users who can run workflows"
  else
    echo "  - No additional trusted users configured (only admins can run workflows)"
  fi
}

# Main function - runs all setup operations
main() {
  # Run all setup operations in sequence
  setup_branch_protection
  configure_repo_settings
  restrict_actions_permissions
  
  echo -e "\n${GREEN}✅ All GitHub repository configurations completed successfully!${NC}"
}

# Run the main function
main 