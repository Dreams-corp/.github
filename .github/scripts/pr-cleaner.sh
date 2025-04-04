#!/bin/bash

# This script automates the cleanup of pull requests and branches in GitHub repositories.
# It can close pull requests with specific branch name prefixes and optionally delete the associated branches.
# Additionally, it can remove orphan branches with a specified prefix.

# Input arguments
ORG_NAME=$1               # GitHub organization name
BRANCH_NAME_PREFIX=$2     # Prefix for branch names to target
BRANCH_DELETE=$3          # Whether to delete branches after closing PRs (true/false)
REMOVE_ORPHAN_BRANCHES=$4 # Whether to remove orphan branches with the specified prefix (true/false)
TARGET_REPO=$5            # Specific repository to target (optional)
COMMENT=$6                # Comment to add when closing PRs
GITHUB_TOKEN=$7           # GitHub token for authentication
DRY_RUN=$8                # Whether to run in dry-run mode (true/false)

# Basic input validation
if [ -z "$ORG_NAME" ] || [ -z "$GITHUB_TOKEN" ]; then
    echo "ORG_NAME and GITHUB_TOKEN are required."
    exit 1
fi

# Logging function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

# Authenticate GitHub CLI using the provided token
authenticate_github() {
    echo "$GITHUB_TOKEN" | gh auth login --with-token || {
        echo "GitHub authentication failed. Exiting..."
        exit 1
    }
}

# Get the list of repositories to process
get_repositories() {
    if [ -n "$TARGET_REPO" ]; then
        echo "$TARGET_REPO"
    else
        gh repo list "$ORG_NAME" --visibility public --limit 1000 --json name --jq '.[].name'
    fi
}

# Close pull requests with the specified branch prefix
close_pull_requests() {
    local repo="$1"
    prs=$(gh pr list --repo "$ORG_NAME/$repo" --state open --json number,headRefName \
        --jq ".[] | select(.headRefName | contains(\"$BRANCH_NAME_PREFIX\")) | .number")

    if [ -z "$prs" ]; then
        log "No matching PRs in $repo"
        return
    fi

    for pr in $prs; do
        log "Closing PR #$pr in $repo"
        if [ "$DRY_RUN" = "true" ]; then
            log "[Dry Run] Would close PR #$pr in $repo"
        else
            if [ "$BRANCH_DELETE" = "true" ]; then
                gh pr close "$pr" --repo "$ORG_NAME/$repo" --delete-branch --comment "$COMMENT"
            else
                gh pr close "$pr" --repo "$ORG_NAME/$repo" --comment "$COMMENT"
            fi
        fi
    done
}

# Remove orphan branches with the specified prefix
remove_orphan_branches() {
    local repo="$1"
    if [ "$REMOVE_ORPHAN_BRANCHES" = "true" ] && [ -n "$BRANCH_NAME_PREFIX" ]; then
        log "Checking for orphan branches in $repo with prefix '$BRANCH_NAME_PREFIX'"
        orphan_branches=$(gh api repos/"$ORG_NAME"/"$repo"/branches \
            --jq ".[] | select(.name | startswith(\"$BRANCH_NAME_PREFIX\")) | .name")

        if [ -z "$orphan_branches" ]; then
            log "No orphan branches with prefix '$BRANCH_NAME_PREFIX' in $repo"
            return
        fi

        for branch in $orphan_branches; do
            log "Deleting orphan branch: $branch"
            if [ "$DRY_RUN" = "true" ]; then
                log "[Dry Run] Would delete branch: $branch"
            else
                gh api -X DELETE repos/"$ORG_NAME"/"$repo"/git/refs/heads/"$branch"
                sleep 3s
            fi
        done
    fi
}

# Main logic
authenticate_github
repos=$(get_repositories)

for repo in $repos; do
    log "Processing repository: $repo"
    close_pull_requests "$repo"
    remove_orphan_branches "$repo"
done

log "Pull request cleanup completed."
