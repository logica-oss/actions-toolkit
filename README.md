# actions-toolkit

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![autofix.ci](https://github.com/logica-oss/actions-toolkit/actions/workflows/autofix.yaml/badge.svg)](https://github.com/logica-oss/actions-toolkit/actions/workflows/autofix.yaml)
[![Verify (Repo)](https://github.com/logica-oss/actions-toolkit/actions/workflows/verify-repo.yaml/badge.svg)](https://github.com/logica-oss/actions-toolkit/actions/workflows/verify-repo.yaml)
[![CodeQL Advanced](https://github.com/logica-oss/actions-toolkit/actions/workflows/codeql.yaml/badge.svg)](https://github.com/logica-oss/actions-toolkit/actions/workflows/codeql.yaml)

A collection of composite actions

## Composite Actions

### verify-actions

Lints GitHub Actions (workflows / composite actions) with actionlint, ghalint, and zizmor.  
Requires the `contents: read` and `checks: write` permissions.

```yaml
jobs:
  verify-actions:
    runs-on: ubuntu-latest
    timeout-minutes: 20
    permissions:
      contents: read
      checks: write
    steps:
      - name: Checkout
        uses: actions/checkout@v7
        with:
          persist-credentials: false
      - name: Verify actions
        uses: logica-oss/actions-toolkit/verify-actions@main
```

### setup-bun

Sets up JS runtimes (via mise) and installs dependencies with Bun.  
No special permissions are required.

```yaml
jobs:
  setup:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - name: Checkout
        uses: actions/checkout@v7
      - name: Setup Bun environment
        uses: logica-oss/actions-toolkit/setup-bun@main
```

### wait-for-workflow

Waits for another workflow run on the same commit to complete, failing if it does not succeed.  
Requires the `contents: read` and `actions: read` permissions.

```yaml
jobs:
  wait:
    runs-on: ubuntu-latest
    timeout-minutes: 20
    permissions:
      contents: read
      actions: read
    steps:
      - name: Checkout
        uses: actions/checkout@v7
      - name: Wait for tests
        uses: logica-oss/actions-toolkit/wait-for-workflow@main
        with:
          workflow-id: test.yaml
          timeout-minutes: 15 # defaults to 10
```

#### Inputs

| Input                   | Required | Default | Description                                                          |
| ----------------------- | -------- | ------- | -------------------------------------------------------------------- |
| `workflow-id`           | ✅       | —       | Workflow file name or ID to wait for                                 |
| `timeout-minutes`       | —        | `10`    | Maximum time to wait in minutes                                      |
| `poll-interval-seconds` | —        | `30`    | Seconds between status checks. Must resolve to 1–2147483.647 seconds |

### check-release-label

Fails unless exactly one of the patch, minor, or major release labels is attached.  
Draft pull requests are skipped.  
Requires the `pull-requests: read` permission.

```yaml
name: Verify (Release Label)

on:
  pull_request:
    types: [opened, labeled, unlabeled, synchronize, reopened, ready_for_review]

jobs:
  check-release-label:
    runs-on: ubuntu-latest
    timeout-minutes: 5
    permissions:
      pull-requests: read
    steps:
      - name: Check release label
        uses: logica-oss/actions-toolkit/check-release-label@main
        with:
          major-label: major # defaults to major
          minor-label: minor # defaults to minor
          patch-label: patch # defaults to patch
          ignore-authors: | # defaults to renovate[bot] and mergify[bot]
            renovate[bot]
            mergify[bot]
```

#### Inputs

| Input            | Required | Default                       | Description                                  |
| ---------------- | -------- | ----------------------------- | -------------------------------------------- |
| `major-label`    | —        | `major`                       | Label triggering a major release             |
| `minor-label`    | —        | `minor`                       | Label triggering a minor release             |
| `patch-label`    | —        | `patch`                       | Label triggering a patch release             |
| `ignore-authors` | —        | `renovate[bot], mergify[bot]` | Authors skipped without labels, one per line |

### release

Creates a SemVer tag and optionally a GitHub Release from merged PR labels.  
Requires the `contents: write` and `pull-requests: read` permissions.

```yaml
name: Release

on:
  schedule:
    - cron: "0 0 * * 1"
  workflow_dispatch:

concurrency:
  group: release-${{ github.ref }}
  cancel-in-progress: false

jobs:
  release:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    permissions:
      contents: write
      pull-requests: read
    steps:
      - name: Checkout
        uses: actions/checkout@v7
      - name: Create release
        id: release
        uses: logica-oss/actions-toolkit/release@main
        with:
          initial-version: v1.0.0 # defaults to v1.0.0
          major-label: major # defaults to major
          minor-label: minor # defaults to minor
          create-release: "true" # defaults to "true"
```

The `minor` label triggers a minor release.  
The `major` label triggers a major release.  
PRs without either label default to a patch release.

Set `create-release` to `"false"` to create only the tag and let another tool (e.g. GoReleaser) create the release in the same job.  
The next tag is computed from the latest GitHub Release, so the tool must create the Release in the same job.  
Fetch the created tag before running the tool so it can resolve the version from git.

```yaml
steps:
  - name: Checkout
    uses: actions/checkout@v7
    with:
      fetch-depth: 0
  - name: Create tag
    id: release
    uses: logica-oss/actions-toolkit/release@main
    with:
      create-release: "false"
  - name: Fetch created tag
    if: steps.release.outputs.tag != ''
    run: git fetch origin ${{ steps.release.outputs.tag }}
    shell: bash
  - name: Run GoReleaser
    if: steps.release.outputs.tag != ''
    uses: goreleaser/goreleaser-action@v6
    with:
      version: latest
      args: release --clean
    env:
      GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

#### Inputs

| Input             | Required | Default  | Description                                                         |
| ----------------- | -------- | -------- | ------------------------------------------------------------------- |
| `initial-version` | —        | `v1.0.0` | Tag created when no previous release exists                         |
| `major-label`     | —        | `major`  | Label triggering a major release                                    |
| `minor-label`     | —        | `minor`  | Label triggering a minor release                                    |
| `create-release`  | —        | `true`   | Whether to create a GitHub Release (`"false"` creates only the tag) |

#### Outputs

| Output | Description                                 |
| ------ | ------------------------------------------- |
| `tag`  | Created tag, empty when no tag was created. |

### sync-agent-config

Syncs agent configs from canonical sources.  
Requires the `contents: read` permission.  
`AGENTS.md`, `.claude/rules` and `.claude/skills` are fully regenerated on each run; do not place hand-written files there.

Canonical sources and generated mirrors:

| Source                                   | Mirror                                     |
| ---------------------------------------- | ------------------------------------------ |
| `.github/copilot-instructions.md`        | `AGENTS.md`                                |
| `.github/instructions/*.instructions.md` | `.claude/rules/*.md` (`applyTo` → `paths`) |
| `.agents/skills/*`                       | `.claude/skills/*` (copy)                  |

```yaml
name: autofix.ci

on:
  push:
    branches: [main]
  pull_request:

jobs:
  autofix:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    permissions:
      contents: read
    steps:
      - name: Checkout
        uses: actions/checkout@v7
        with:
          persist-credentials: false
      - name: Sync Agent Config
        uses: logica-oss/actions-toolkit/sync-agent-config@main
      - name: Autofix
        uses: autofix-ci/action@v1
```

### autofix-text

Fixes Markdown with markdownlint, formats Shell with shfmt (`-i 2`) and text files with Oxfmt, commits via autofix-ci, then re-lints.  
Requires the `contents: read` permission and the autofix.ci GitHub App.  
The calling workflow's `name` must be `autofix.ci` (required by autofix-ci).

Place this step last of `autofix.ci` workflow; it commits all preceding changes.

```yaml
name: autofix.ci

on:
  push:
    branches: [main]
  pull_request:

jobs:
  autofix:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    permissions:
      contents: read
    steps:
      - name: Checkout
        uses: actions/checkout@v7
        with:
          persist-credentials: false
      - name: Autofix Text
        uses: logica-oss/actions-toolkit/autofix-text@main
```

#### Inputs

| Input            | Required | Default                                                                              | Description                                              |
| ---------------- | -------- | ------------------------------------------------------------------------------------ | -------------------------------------------------------- |
| `markdown-globs` | —        | `**/*.{md,markdown}`                                                                 | Markdown files to lint, newline-delimited                |
| `oxfmt-paths`    | —        | `**/*.md **/*.markdown **/*.yaml **/*.yml **/*.json **/*.jsonc **/*.json5 **/*.toml` | Paths for Oxfmt to format, space-delimited (empty skips) |
| `enable-shfmt`   | —        | `true`                                                                               | Whether to run shfmt formatting (`-i 2` on `.`)          |
