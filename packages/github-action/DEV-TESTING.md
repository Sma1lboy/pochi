# GitHub Action Development Testing Guide

This guide explains how to set up and test the Pochi GitHub Action during development.

## 🏗️ Architecture Overview

### Branch Strategy

1. **Action Code** (`packages/github-action/`): Must be on an accessible branch
   - Push to your fork's `main` branch or a dedicated `action-dev` branch
   - GitHub Actions can only reference committed code

2. **CLI Code** (`packages/cli/`): Can be on any branch
   - The action will clone and build from the specified repository/branch
   - No need to push CLI changes to main during development

### Repository Structure

```
your-fork/
├── main branch (or action-dev branch)
│   └── packages/github-action/ (action code must be here)
├── feature-branch (your development branch)
│   └── packages/cli/ (CLI code can be here)
└── test-repo/ (optional: separate testing repository)
```

## 🚀 Setup Development Environment

### 1. Fork and Clone

```bash
# Fork the main repository
gh repo fork Sma1lboy/pochi

# Clone your fork
git clone https://github.com/YOUR_USERNAME/pochi.git
cd pochi

# Add upstream remote
git remote add upstream https://github.com/Sma1lboy/pochi.git
```

### 2. Create Development Branch

```bash
# Create and switch to development branch
git checkout -b feature/my-awesome-feature

# Make your changes to CLI code
# Edit packages/cli/src/...
```

### 3. Prepare Action for Testing

```bash
# Ensure action code is on main branch (or dedicated action branch)
git checkout main

# Copy the development action file if needed
cp packages/github-action/action.dev.yml packages/github-action/action.yml

# Commit and push action code
git add packages/github-action/
git commit -m "feat: update GitHub action for testing"
git push origin main
```

## 🧪 Testing Strategies

### Strategy 1: Same Repository Testing

Test within your fork repository:

```yaml
# .github/workflows/test-pochi-dev.yml
name: Test Pochi Development

on:
  issue_comment:
    types: [created]

jobs:
  test-pochi:
    if: contains(github.event.comment.body, '/pochi-dev')
    runs-on: ubuntu-latest
    steps:
      - uses: YOUR_USERNAME/pochi/packages/github-action@main
        with:
          model: "qwen/qwen3-coder"
          source_repo: "YOUR_USERNAME/pochi"
          source_ref: "feature/my-awesome-feature"  # Your dev branch
          dev_mode: "true"
```

### Strategy 2: Dedicated Test Repository

Create a separate test repository:

1. Create a new repository: `YOUR_USERNAME/pochi-test`
2. Add the workflow file:

```yaml
# .github/workflows/pochi-test.yml
name: Pochi Test

on:
  issue_comment:
    types: [created]

jobs:
  pochi:
    if: contains(github.event.comment.body, '/pochi')
    runs-on: ubuntu-latest
    steps:
      - uses: YOUR_USERNAME/pochi/packages/github-action@main
        with:
          source_repo: "YOUR_USERNAME/pochi"
          source_ref: "feature/my-awesome-feature"
          dev_mode: "true"
```

### Strategy 3: Pull Request Testing

Test within a PR in your fork:

```yaml
# .github/workflows/pr-test.yml
name: PR Test

on:
  pull_request_review_comment:
    types: [created]

jobs:
  pochi:
    if: contains(github.event.comment.body, '/pochi')
    runs-on: ubuntu-latest
    steps:
      - uses: YOUR_USERNAME/pochi/packages/github-action@main
        with:
          source_repo: "YOUR_USERNAME/pochi"
          source_ref: ${{ github.event.pull_request.head.ref }}
          dev_mode: "true"
```

## 🛠️ Development Workflow

### Step-by-Step Process

1. **Make CLI Changes**
   ```bash
   git checkout feature/my-awesome-feature
   # Edit packages/cli/src/...
   git add packages/cli/
   git commit -m "feat: improve CLI functionality"
   git push origin feature/my-awesome-feature
   ```

2. **Update Action if Needed**
   ```bash
   git checkout main
   # Edit packages/github-action/ if needed
   git add packages/github-action/
   git commit -m "feat: update action for testing"
   git push origin main
   ```

3. **Test the Action**
   - Go to your test repository or create an issue in your fork
   - Comment `/pochi-dev <your test prompt>` (or `/pochi` depending on setup)
   - Watch the action run with your development code

4. **Debug and Iterate**
   - Check action logs for issues
   - Use `dev_mode: "true"` for verbose logging
   - Make fixes and repeat

### Development Action Features

The `action.dev.yml` provides these development features:

- **Custom Source Repository**: Specify your fork
- **Custom Reference**: Use any branch/tag/commit
- **Development Mode**: Verbose logging and debug info
- **Version Information**: Shows built CLI version and git info

## 🔧 Local Development Tools

### Build Script for Quick Testing

```bash
#!/bin/bash
# scripts/dev-test.sh

FEATURE_BRANCH="feature/my-awesome-feature"
YOUR_USERNAME="YOUR_USERNAME"

echo "🏗️ Building and testing CLI locally..."

# Build CLI
cd packages/cli
bun run build

# Test CLI locally
./dist/pochi --version
./dist/pochi -p "test prompt"

echo "✅ Local test complete"
echo "📤 Push your changes and test in GitHub Action:"
echo "   1. Push feature branch: git push origin $FEATURE_BRANCH"
echo "   2. Comment '/pochi-dev your test prompt' in an issue"
```

### Environment Variables for Testing

```bash
# Set these in your test repository secrets or workflow
POCHI_MODEL=qwen/qwen3-coder
POCHI_GITHUB_ACTION_DEBUG=1

# For testing with different vendors
POCHI_SESSION_TOKEN=your_test_token
```

## 📋 Testing Checklist

Before creating a PR:

- [ ] CLI builds successfully locally
- [ ] Action works with development action.yml
- [ ] Tested with different prompts and scenarios
- [ ] Verified shutdown mechanism works
- [ ] Checked logs for errors or hanging processes
- [ ] Tested signal handling (if applicable)

## 🐛 Troubleshooting

### Common Issues

1. **Action can't find your branch**
   - Ensure the branch is pushed to your fork
   - Check the `source_ref` parameter

2. **Build fails in action**
   - Test local build first: `cd packages/cli && bun run build`
   - Check dependencies in your branch

3. **Action hangs**
   - Check if your shutdown mechanism is working
   - Enable `dev_mode: "true"` for more logging

4. **Permission issues**
   - Ensure your fork's actions are enabled
   - Check repository permissions

### Debug Commands

```bash
# Test CLI build locally
cd packages/cli
bun install
bun run build
./dist/pochi --version

# Check action syntax
cd packages/github-action
# Use GitHub CLI to validate
gh workflow list
```

## 🚢 Deployment to Production

Once testing is complete:

1. Create PR to main repository
2. Update main `action.yml` if needed
3. The production action will use the main repository by default

## 📚 Additional Resources

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Composite Actions Guide](https://docs.github.com/en/actions/creating-actions/creating-a-composite-action)
- [GitHub CLI for testing](https://cli.github.com/)