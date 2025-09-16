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
#   3. Script creates an action-test branch and test PR
#   4. Comment '/pochi-test <your prompt>' on the PR to test your changes
#
# BRANCH STRATEGY:
#   - Feature Branch: Contains your CLI code changes (where you run this script)
#   - Action Branch: Auto-created branch containing GitHub Action test setup
#   - The Action will clone and build CLI from your Feature Branch
#
# EXAMPLE WORKFLOW:
#   git checkout feature/my-awesome-feature
#   # Make your CLI changes...
#   git push origin feature/my-awesome-feature
#   ./packages/github-action/dev-test.sh quick
#   # Go to created PR and comment: /pochi-test Please test my feature
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
ROOT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

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
    echo "  3. Script creates action-test branch and test PR"
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

    # Get current branch if not specified
    if [[ -z "$FEATURE_BRANCH" ]]; then
        FEATURE_BRANCH=$(git branch --show-current)
        log "Using current branch as feature branch: $FEATURE_BRANCH"
    fi

    # Generate action branch name
    ACTION_BRANCH="action-test-$(echo "$FEATURE_BRANCH" | sed 's/[^a-zA-Z0-9-]/-/g')"
    log "Generated action branch name: $ACTION_BRANCH"

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
        git push -u "$FORK_REMOTE" "$FEATURE_BRANCH"
    else
        log "Feature branch already exists on remote, updating..."
        git push "$FORK_REMOTE" "$FEATURE_BRANCH"
    fi
}

# Create and setup action test branch
create_action_branch() {
    log "Creating action test branch: $ACTION_BRANCH"

    # Get the base branch (usually main)
    BASE_BRANCH=$(git remote show "$FORK_REMOTE" | grep "HEAD branch" | awk '{print $NF}')
    if [[ -z "$BASE_BRANCH" ]]; then
        BASE_BRANCH="main"
    fi

    # Fetch latest changes
    git fetch "$FORK_REMOTE"

    # Create action branch from base branch
    git checkout -B "$ACTION_BRANCH" "$FORK_REMOTE/$BASE_BRANCH"

    # Create the test workflow
    create_test_workflow

    # Commit changes
    git add .github/
    git commit -m "feat: setup GitHub Action testing for $FEATURE_BRANCH

- Add test workflow for development
- Configure action to use development branch: $FEATURE_BRANCH
- Enable development mode with verbose logging

Test with: /pochi-test $TEST_PROMPT"

    # Push action branch
    git push -u "$FORK_REMOTE" "$ACTION_BRANCH"

    log "Action test branch created and pushed"
}

# Create test workflow
create_test_workflow() {
    log "Creating test workflow..."

    mkdir -p "$ROOT_DIR/.github/workflows"

    cat > "$ROOT_DIR/.github/workflows/pochi-dev-test.yml" << EOF
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
        uses: $GITHUB_USER/$REPO_NAME/packages/github-action@$ACTION_BRANCH
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

# Create test PR
create_test_pr() {
    log "Creating test PR..."

    # Create PR with comprehensive description
    PR_BODY="## 🧪 Development Test Setup for \`$FEATURE_BRANCH\`

This PR sets up automated testing for the development branch \`$FEATURE_BRANCH\`.

### How to Test

1. **Comment on this PR**: \`/pochi-test your test prompt here\`
2. **Or use the default test**: \`/pochi-test\`

### What This Tests

- **CLI Branch**: \`$FEATURE_BRANCH\`
- **Action Branch**: \`$ACTION_BRANCH\`
- **Development Mode**: Enabled with verbose logging
- **Repository**: \`$GITHUB_USER/$REPO_NAME\`

### Example Test Commands

\`\`\`
/pochi-test Please test the new shutdown mechanism
/pochi-test List all TypeScript files and count them
/pochi-test Create a simple README file
\`\`\`

### Development Setup

This PR includes:
- ✅ Test workflow that triggers on comments
- ✅ Development action configuration
- ✅ Automatic source branch detection
- ✅ Verbose logging for debugging

### Auto-generated by dev-test.sh

Feature branch: \`$FEATURE_BRANCH\`
Action branch: \`$ACTION_BRANCH\`
Generated at: \`$(date)\`

---

**Ready to test!** Comment \`/pochi-test\` followed by your test prompt."

    PR_URL=$(gh pr create \
        --title "🧪 Test Setup for $FEATURE_BRANCH" \
        --body "$PR_BODY" \
        --label "testing,development" \
        --draft)

    log "Test PR created: $PR_URL"
    echo -e "${BLUE}🔗 Test PR URL: $PR_URL${NC}"
}

# Show current status
show_status() {
    echo -e "${BLUE}📊 Current Test Status${NC}"
    echo ""

    current_branch=$(git branch --show-current)
    echo "Current branch: $current_branch"

    # Check for action test branches
    action_branches=$(git branch -r | grep -E "origin/action-test-" | sed 's/origin\///' | sed 's/^[[:space:]]*//')

    if [[ -n "$action_branches" ]]; then
        echo ""
        echo "Active test branches:"
        echo "$action_branches"
    else
        echo ""
        echo "No active test branches found"
    fi

    # Check for test workflow
    if [[ -f "$ROOT_DIR/.github/workflows/pochi-dev-test.yml" ]]; then
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
            git push origin --delete "$branch" 2>/dev/null || echo "  (already deleted or doesn't exist)"
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
    echo "   Feature Branch: $FEATURE_BRANCH"
    echo "   Action Branch:  $ACTION_BRANCH"
    echo "   Repository:     $GITHUB_USER/$REPO_NAME"
    echo "   Dev Mode:       Enabled"
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
    create_action_branch

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