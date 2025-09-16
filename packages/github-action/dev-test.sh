#!/bin/bash

# =============================================================================
# Pochi GitHub Action Development Test Script
# =============================================================================
#
# PURPOSE:
#   Automates setting up and testing GitHub Actions for pochi CLI development
#   Allows you to test your CLI changes in a real GitHub Actions environment
#
# USAGE PATTERN:
#   1. Work on your feature branch (e.g., feature/shutdown-fix)
#   2. Run this script from your feature branch: ./packages/github-action/dev-test.sh quick
#   3. Script adds test configuration to your feature branch and creates PR to main
#   4. Comment '/pochi-test <your prompt>' on the PR to test your changes
#
# BRANCH STRATEGY:
#   - Feature Branch: Contains your CLI code changes + test configuration
#   - PR: Direct feature branch → main with integrated testing
#   - The Action will test CLI from the same branch as the PR
#
# EXAMPLE WORKFLOW:
#   git checkout feature/my-awesome-feature
#   # Make your CLI changes...
#   ./packages/github-action/dev-test.sh quick
#   # Script creates feature/my-awesome-feature → main PR
#   # Comment on PR: /pochi-test Please test my feature
#
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Note: GIT_ROOT will be set in detect_setup()

# Default values
FEATURE_BRANCH=""
ACTION_BRANCH=""
CREATE_PR=false
FORK_REMOTE=""
TEST_PROMPT="Please test the updated pochi CLI"

print_usage() {
    echo "Pochi GitHub Action Development Test Script"
    echo ""
    echo "🎯 PURPOSE: Test your CLI changes in GitHub Actions environment"
    echo ""
    echo "📋 WORKFLOW:"
    echo "  1. Work on your feature branch (e.g., feature/my-awesome-feature)"
    echo "  2. Run this script from your feature branch"
    echo "  3. Script adds test config to your branch and creates PR to main"
    echo "  4. Comment '/pochi-test <prompt>' on the PR to test"
    echo ""
    echo "Usage: $0 [COMMAND] [OPTIONS]"
    echo ""
    echo "COMMANDS:"
    echo "  setup     Setup test environment for current branch"
    echo "  quick     Quick setup with PR creation (RECOMMENDED)"
    echo "  clean     Clean up test branches"
    echo "  status    Show current test setup status"
    echo ""
    echo "OPTIONS (for setup/quick):"
    echo "  -f, --feature-branch BRANCH    Feature branch name (current branch if not specified)"
    echo "  -t, --test-prompt TEXT          Test prompt for the action"
    echo "  -r, --fork-remote REMOTE       Fork remote name (default: origin)"
    echo ""
    echo "🚀 QUICK START:"
    echo "  # 1. Switch to your feature branch"
    echo "  git checkout feature/my-awesome-feature"
    echo ""
    echo "  # 2. Run the script"
    echo "  ./packages/github-action/dev-test.sh quick"
    echo ""
    echo "  # 3. Go to the created PR and comment:"
    echo "  /pochi-test Please test my awesome feature"
    echo ""
    echo "📝 MORE EXAMPLES:"
    echo "  $0 quick                              # Quick setup with PR for current branch"
    echo "  $0 setup -f my-feature               # Setup test for specific branch"
    echo "  $0 quick -t 'test my new feature'    # Quick setup with custom prompt"
    echo "  $0 clean                              # Clean up test branches"
    echo "  $0 status                             # Show current status"
    echo ""
    echo "⚠️  IMPORTANT:"
    echo "  - Always run this script from your FEATURE BRANCH"
    echo "  - The script will test the CLI code from your current branch"
    echo "  - Make sure your feature branch is pushed to your fork"
}

log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Parse command line arguments
parse_args() {
    local command=""

    if [[ $# -gt 0 ]]; then
        command="$1"
        shift
    fi

    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--feature-branch)
                FEATURE_BRANCH="$2"
                shift 2
                ;;
            -t|--test-prompt)
                TEST_PROMPT="$2"
                shift 2
                ;;
            -r|--fork-remote)
                FORK_REMOTE="$2"
                shift 2
                ;;
            -h|--help)
                print_usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                ;;
        esac
    done

    echo "$command"
}

# Detect current setup
detect_setup() {
    log "Detecting current repository setup..."

    # Check if we're in a git repository
    if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
        error "Not in a git repository"
    fi

    # Get git root directory (but don't change to it)
    GIT_ROOT=$(git rev-parse --show-toplevel)
    log "Git root directory: $GIT_ROOT"

    # Get current branch if not specified
    if [[ -z "$FEATURE_BRANCH" ]]; then
        FEATURE_BRANCH=$(git branch --show-current)
        log "Using current branch as feature branch: $FEATURE_BRANCH"
    fi

    # No need for separate action branch - using feature branch directly
    log "Will use feature branch for both CLI code and GitHub Action"

    # Detect fork remote
    if [[ -z "$FORK_REMOTE" ]]; then
        if git remote | grep -q "origin"; then
            FORK_REMOTE="origin"
        else
            FORK_REMOTE=$(git remote | head -n1)
        fi
        log "Using remote: $FORK_REMOTE"
    fi

    # Get repository info
    REPO_URL=$(git remote get-url "$FORK_REMOTE")
    if [[ "$REPO_URL" =~ github\.com[:/]([^/]+)/([^/.]+) ]]; then
        GITHUB_USER="${BASH_REMATCH[1]}"
        REPO_NAME="${BASH_REMATCH[2]}"
    else
        error "Could not parse GitHub repository URL: $REPO_URL"
    fi

    log "Repository: $GITHUB_USER/$REPO_NAME"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."

    # Check if gh CLI is installed
    if ! command -v gh &> /dev/null; then
        error "GitHub CLI (gh) is required but not installed. Install from: https://cli.github.com/"
    fi

    # Check if bun is installed
    if ! command -v bun &> /dev/null; then
        error "Bun is required but not installed. Install from: https://bun.sh/"
    fi

    # Check if authenticated with gh
    if ! gh auth status &> /dev/null; then
        error "Not authenticated with GitHub CLI. Run: gh auth login"
    fi

    log "All prerequisites satisfied"
}

# Ensure feature branch exists and is pushed
prepare_feature_branch() {
    log "Preparing feature branch: $FEATURE_BRANCH"

    # Check if feature branch exists locally
    if ! git show-ref --verify --quiet "refs/heads/$FEATURE_BRANCH"; then
        error "Feature branch '$FEATURE_BRANCH' does not exist locally"
    fi

    # Switch to feature branch
    git checkout "$FEATURE_BRANCH"

    # Check if there are uncommitted changes
    if ! git diff-index --quiet HEAD --; then
        warn "There are uncommitted changes. Please commit or stash them first."
        git status --short
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi

    # Push feature branch if it doesn't exist on remote
    if ! git ls-remote --exit-code --heads "$FORK_REMOTE" "$FEATURE_BRANCH" > /dev/null 2>&1; then
        log "Pushing feature branch to remote..."
        git push -u "$FORK_REMOTE" "$FEATURE_BRANCH" --no-verify
    else
        log "Feature branch already exists on remote, updating..."
        git push "$FORK_REMOTE" "$FEATURE_BRANCH" --no-verify
    fi
}

# Add test configuration to current branch
add_test_configuration() {
    log "Adding test configuration to current branch: $FEATURE_BRANCH"

    # Create the test workflow
    create_test_workflow

    # Commit changes to current branch (if there are any)
    if ! git diff-index --quiet HEAD --; then
        git add "$GIT_ROOT/.github/"
        git commit -m "feat: add GitHub Action test configuration

- Add test workflow for PR testing
- Configure action to test current branch: $FEATURE_BRANCH
- Enable development mode with verbose logging

Test with: /pochi-test $TEST_PROMPT"

        # Push current branch
        git push "$FORK_REMOTE" "$FEATURE_BRANCH" --no-verify
        log "Test configuration added to current branch"
    else
        log "Test configuration already exists, skipping commit"
    fi
}

# Create test workflow
create_test_workflow() {
    log "Creating test workflow..."

    mkdir -p "$GIT_ROOT/.github/workflows"

    cat > "$GIT_ROOT/.github/workflows/pochi-dev-test.yml" << EOF
name: Pochi Development Test

on:
  issue_comment:
    types: [created]
  pull_request_review_comment:
    types: [created]

jobs:
  pochi-test:
    if: |
      (github.event_name == 'issue_comment' && contains(github.event.comment.body, '/pochi-test')) ||
      (github.event_name == 'pull_request_review_comment' && contains(github.event.comment.body, '/pochi-test'))
    runs-on: ubuntu-latest

    steps:
      - name: React with eyes
        uses: actions/github-script@v7
        with:
          script: |
            const { owner, repo } = context.repo;
            const comment_id = context.payload.comment.id;
            await github.rest.reactions.createForIssueComment({
              owner,
              repo,
              comment_id,
              content: 'eyes'
            });

      - name: Extract prompt from comment
        id: extract-prompt
        uses: actions/github-script@v7
        with:
          script: |
            const comment = context.payload.comment.body;
            const match = comment.match(/\/pochi-test\s+(.+)/s);
            const prompt = match ? match[1].trim() : '$TEST_PROMPT';
            core.setOutput('prompt', prompt);
            console.log('Extracted prompt:', prompt);

      - name: Run Pochi Development Test
        uses: $GITHUB_USER/$REPO_NAME/packages/github-action@$FEATURE_BRANCH
        with:
          model: "qwen/qwen3-coder"
          source_repo: "$GITHUB_USER/$REPO_NAME"
          source_ref: "$FEATURE_BRANCH"
          dev_mode: "true"
        env:
          POCHI_CUSTOM_INSTRUCTIONS: |
            ## Development Test Instructions

            This is a development test of the Pochi CLI from branch: $FEATURE_BRANCH

            User prompt: \${{ steps.extract-prompt.outputs.prompt }}

            Please execute the user's request and verify that the new features work correctly.

            After completing the task, please comment on this issue with:
            1. Summary of what was accomplished
            2. Any issues or improvements noticed
            3. Confirmation that the development changes work as expected
EOF

    log "Test workflow created: .github/workflows/pochi-dev-test.yml"
}

# Create PR to main with test configuration
create_test_pr() {
    log "Creating PR from $FEATURE_BRANCH to main..."

    # Create PR with comprehensive description
    PR_BODY="## 🚀 Pull Request: $FEATURE_BRANCH

This PR includes the development changes and testing configuration.

### 🧪 How to Test This PR

1. **Comment on this PR**: \`/pochi-test your test prompt here\`
2. **Or use the default test**: \`/pochi-test\`

The GitHub Action will automatically test the CLI code from this branch.

### 📋 What This Tests

- **Branch**: \`$FEATURE_BRANCH\`
- **Development Mode**: Enabled with verbose logging
- **Repository**: \`$GITHUB_USER/$REPO_NAME\`

### 🔧 Example Test Commands

\`\`\`
/pochi-test Please test the new shutdown mechanism
/pochi-test List all TypeScript files and count them
/pochi-test Create a simple README file
/pochi-test Help me analyze the codebase structure
\`\`\`

### ✅ Features Included

- ✅ Test workflow that triggers on PR comments
- ✅ Automatic CLI building from this branch
- ✅ Development mode with verbose logging
- ✅ Real GitHub Actions environment testing

### 🤖 Auto-generated test setup

Branch: \`$FEATURE_BRANCH\`
Generated at: \`$(date)\`
Test prompt: \`$TEST_PROMPT\`

---

**Ready to test!** Comment \`/pochi-test <your prompt>\` to test the CLI changes in this PR."

    PR_URL=$(gh pr create \
        --title "$FEATURE_BRANCH" \
        --body "$PR_BODY" \
        --base main \
        --head "$FEATURE_BRANCH")

    log "PR created: $PR_URL"
    echo -e "${BLUE}🔗 PR URL: $PR_URL${NC}"
}

# Show current status
show_status() {
    echo -e "${BLUE}📊 Current Test Status${NC}"
    echo ""

    current_branch=$(git branch --show-current)
    echo "Current branch: $current_branch"

    # Check for action test branches (legacy)
    action_branches=$(git branch -r | grep -E "origin/action-test-" | sed 's/origin\///' | sed 's/^[[:space:]]*//')

    if [[ -n "$action_branches" ]]; then
        echo ""
        echo "Legacy test branches (can be cleaned up):"
        echo "$action_branches"
    fi

    # Check for test workflow
    if [[ -f "$GIT_ROOT/.github/workflows/pochi-dev-test.yml" ]]; then
        echo ""
        echo "✅ Test workflow exists: .github/workflows/pochi-dev-test.yml"
    else
        echo ""
        echo "❌ No test workflow found"
    fi

    # Check for development action
    if [[ -f "$SCRIPT_DIR/action.dev.yml" ]]; then
        echo "✅ Development action exists: packages/github-action/action.dev.yml"
    else
        echo "❌ No development action found"
    fi
}

# Clean up test branches
clean_branches() {
    echo -e "${YELLOW}🧹 Cleaning up test branches...${NC}"

    current_branch=$(git branch --show-current)

    # Find action test branches
    action_branches=$(git branch -r | grep -E "origin/action-test-" | sed 's/origin\///' | sed 's/^[[:space:]]*//')

    if [[ -z "$action_branches" ]]; then
        echo "No action test branches found to clean up"
        return
    fi

    echo "Found action test branches:"
    echo "$action_branches"
    echo ""

    read -p "Delete these branches? (y/N): " -n 1 -r
    echo

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        for branch in $action_branches; do
            echo "Deleting branch: $branch"
            git push origin --delete "$branch" 2>/dev/null --no-verify || echo "  (already deleted or doesn't exist)"
            git branch -D "$branch" 2>/dev/null || echo "  (local branch doesn't exist)"
        done
        echo -e "${GREEN}✅ Cleanup complete${NC}"
    else
        echo "Cleanup cancelled"
    fi
}

# Generate final instructions
show_instructions() {
    echo ""
    echo -e "${GREEN}✅ Development test setup complete!${NC}"
    echo ""
    echo -e "${BLUE}📋 Next Steps:${NC}"
    echo ""

    if [[ "$CREATE_PR" == true ]]; then
        echo "1. 📝 Go to your test PR and comment:"
        echo -e "   ${YELLOW}/pochi-test $TEST_PROMPT${NC}"
    else
        echo "1. 🔗 Create an issue or PR in your repository:"
        echo -e "   ${YELLOW}https://github.com/$GITHUB_USER/$REPO_NAME${NC}"
        echo ""
        echo "2. 📝 Comment to trigger the test:"
        echo -e "   ${YELLOW}/pochi-test $TEST_PROMPT${NC}"
    fi

    echo ""
    echo -e "${BLUE}📊 Configuration:${NC}"
    echo "   Branch: $FEATURE_BRANCH"
    echo "   Repository: $GITHUB_USER/$REPO_NAME"
    echo "   Dev Mode: Enabled"
    echo ""
    echo -e "${BLUE}🔧 Advanced Usage:${NC}"
    echo "   • Use any prompt: '/pochi-test your custom prompt here'"
    echo "   • Check logs in the Actions tab for detailed output"
    echo "   • Development mode provides verbose logging"
    echo ""
    echo -e "${GREEN}Happy testing! 🚀${NC}"
}

# Main function for setup
setup_test() {
    echo -e "${GREEN}🔧 Pochi GitHub Action Development Test Setup${NC}"
    echo ""

    detect_setup
    check_prerequisites
    prepare_feature_branch
    add_test_configuration

    if [[ "$CREATE_PR" == true ]]; then
        create_test_pr
    fi

    show_instructions
}

# Main execution
main() {
    command=$(parse_args "$@")

    case "$command" in
        setup)
            setup_test
            ;;
        quick)
            CREATE_PR=true
            setup_test
            ;;
        clean)
            clean_branches
            ;;
        status)
            show_status
            ;;
        -h|--help|help)
            print_usage
            ;;
        "")
            echo -e "${YELLOW}No command specified. Use '$0 help' for usage.${NC}"
            echo ""
            echo "Quick options:"
            echo "  $0 quick    # Setup test with PR"
            echo "  $0 setup    # Setup test only"
            echo "  $0 status   # Show current status"
            ;;
        *)
            echo "Unknown command: $command"
            print_usage
            exit 1
            ;;
    esac
}

# Run main function
main "$@"