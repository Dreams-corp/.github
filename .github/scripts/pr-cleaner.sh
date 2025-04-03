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

# Authenticate GitHub CLI using the provided token
    echo "$GITHUB_TOKEN" | gh auth login --with-token

# Determine the list of repositories to process
if [ -n "$TARGET_REPO" ]; then
    repos="$TARGET_REPO" # Use the specified repository
else
    # Fetch all public repositories in the organization
    repos=$(gh repo list "$ORG_NAME" --visibility public --limit 1000 --json name --jq '.[].name')
fi

# Process each repository
for repo in $repos; do
    echo "Processing repository: $repo"

    # Get open pull requests with branch names containing the specified prefix
    prs=$(gh pr list --repo "$ORG_NAME"/"$repo" --state open --json number,headRefName --jq ".[] | select(.headRefName | contains(\"$BRANCH_NAME_PREFIX\")) | .number")

    for pr in $prs; do
        echo "Closing PR #$pr in $repo"

        # Close the pull request and optionally delete the branch
        if [ "$BRANCH_DELETE" = "true" ]; then
            gh pr close "$pr" --repo "$ORG_NAME/$repo" --delete-branch --comment "$COMMENT"
        else
            gh pr close "$pr" --repo "$ORG_NAME/$repo" --comment "$COMMENT"
        fi
    done

    # Remove orphan branches if specified
    if [ "$REMOVE_ORPHAN_BRANCHES" = "true" ] && [ -n "$BRANCH_NAME_PREFIX" ]; then
        echo "Removing orphan branches in $repo with prefix '$BRANCH_NAME_PREFIX'"
        orphan_branches=$(gh api repos/"$ORG_NAME"/"$repo"/branches --jq ".[] | select(.name | startswith(\"$BRANCH_NAME_PREFIX\")) | .name")

        for branch in $orphan_branches; do
            echo "Deleting orphan branch: $branch"
            gh api -X DELETE repos/"$ORG_NAME"/"$repo"/git/refs/heads/"$branch"
            sleep 3s # Pause to avoid hitting API rate limits
        done
    fi
done

echo "Pull request cleanup completed."
