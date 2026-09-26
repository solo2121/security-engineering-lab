# Contribution Guidelines

Welcome to the security-engineering-lab contribution guide.

We appreciate your interest in helping improve this project.

**Keep these in sync:** the repo, docs, and learning path for security-engineering-lab. If a change affects a lab's Vagrantfile, version, topology, or credentials, update that lab's own README and `docs/attack-guide.md` (or equivalent), `docs/project/learning-path.md` if the onboarding flow changes, and the root `README.md`/`CHANGELOG.md` in the same PR. Docs that drift from the actual lab are worse than no docs at all.

---

## Table of Contents

- [Ways to Contribute](#ways-to-contribute)
- [Development Workflow](#development-workflow)
- [Code Standards](#code-standards)
- [Pull Request Process](#pull-request-process)
- [Local Setup](#local-setup)
- [Self-Hosted Smoke-Test Runner (Optional)](#self-hosted-smoke-test-runner-optional)
- [Community Guidelines](#community-guidelines)

---

## Ways to Contribute

### Issue Reporting

- **Bug Reports**  
  Use the [bug report template](https://github.com/solo2121/security-engineering-lab/issues/new?template=bug_report.md).

- **Feature Requests**  
  Use the [feature request template](https://github.com/solo2121/security-engineering-lab/issues/new?template=feature_request.md).

- **Documentation Improvements**  
  Open a regular issue with the `[Docs]` prefix in the title.

### Code Contributions

Professional contributions should follow the feature branch workflow. Direct pushes to the `main` branch are discouraged to help keep the repository stable.

1. **Branch:** Create a descriptive branch from `main`.
   - `feat/feature-name` for new functionality.
   - `fix/issue-description` for bug fixes.
   - `docs/update-description` for documentation improvements.
2. **Develop:** Make your changes and verify them locally.
3. **Commit:** Use conventional commit messages in the form `type(scope): description`.
4. **Push:** Push your branch to your remote repository.
5. **Review:** Open a pull request against `main`.
6. **Merge:** After review and validation, merge the PR and delete the branch.

---

## Development Workflow

### Pre-Commit Checks

The repo ships a `.pre-commit-config.yaml` that automates the checks below.
Install it once per clone:

```bash
pip install -r requirements-dev.txt
pre-commit install
```

From then on, `shellcheck`, `flake8`, `detect-secrets`, and a markdown
link checker run automatically on every `git commit`. To run everything
manually against the whole repo:

```bash
pre-commit run --all-files
```

You can still run the checks individually if you prefer:

```bash
# Shell scripts
shellcheck path/to/script.sh

# Python scripts
flake8 path/to/script.py

# Vagrant syntax check
vagrant validate
```

A `Makefile` at the repo root wraps these same commands for convenience
(`make lint`, `make test`, `make validate`, `make security`, `make docs`).
Run `make help` to see all available targets.

### Running the Test Suite

```bash
# Python tests
pytest tests/python/ -v

# Python tests with coverage report
pytest tests/python/ -v --cov=. --cov-report=term-missing

# Bash tests (requires bats-core: sudo apt-get install -y bats)
bats tests/bash/
```

See [`tests/README.md`](tests/README.md) for more detail on what's covered
and how to add new tests. Both suites also run automatically in CI via the
`run-tests` job.

These checks help catch issues before changes are submitted.

---

## Code Standards

### Shell Script Guidelines

```bash
#!/usr/bin/env bash
```

- Scripts must pass `shellcheck`.
- Include a header comment block in each script:

```bash
#!/usr/bin/env bash
# Script Name: example.sh
# Description: Brief description of script functionality
# Author: Your Name
# Usage: ./example.sh [options]
#
```

### Python Script Guidelines

- Scripts must pass `flake8` (see `.github/workflows/ci.yml` and `Makefile` for the exact invocation and ignore list).
- Use type hints where practical.
- Include a module-level docstring that explains the purpose, usage, and author.

### Naming Conventions

- Use kebab-case for filenames, such as `my-script.sh` or `my-tool.py`.
- Do not use spaces in filenames.
- Do not use uppercase letters in filenames.

### Dependency Management

- Limit external dependencies to three or fewer per script whenever possible.
- Document all requirements in script headers and in a `requirements.txt` file if the script is part of a lab.

---

## Pull Request Process

### PR Checklist

- [ ] All scripts pass linting (`shellcheck` for Bash, `flake8` for Python).
- [ ] Changes were tested locally in a VM or lab environment.
- [ ] Documentation was updated to reflect the changes, including `docs/project/learning-path.md` if the onboarding flow or lab order changed.
- [ ] `CHANGELOG.md` was updated under `[Unreleased]`.
- [ ] Code follows existing style and naming conventions.
- [ ] No secrets, credentials, or personal data were committed.

### Commit Message Format

```text
type(scope): brief description

Optional body explaining the changes in more detail
```

**Common types:**
`feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`

**Examples:**
```text
feat(ad-pentest): add ESC8 relay automation script
fix(devops-lab): correct K3s worker join token path
docs(readme): update repository structure diagram
```

---

## Local Setup

1. Clone the repository:

```bash
git clone https://github.com/solo2121/security-engineering-lab.git
cd security-engineering-lab
```

2. Install development Python dependencies:

```bash
pip install -r requirements-dev.txt
```

3. Install ShellCheck for shell script linting:

```bash
sudo apt install shellcheck   # Debian/Ubuntu
sudo dnf install shellcheck   # Rocky/Fedora
```

4. Validate Vagrantfiles before submitting changes:

```bash
cd labs/security/active-directory/base && vagrant validate
cd labs/security/active-directory/vlan-segmented && vagrant validate
cd labs/infrastructure/devops-linux-lab && vagrant validate
```

---

## Self-Hosted Smoke-Test Runner (Optional)

The CI pipeline's `smoke-test-devops-lab` job actually boots the DevOps
lab's `minimal` profile (`devops-1`, `worker-1`) and confirms k3s comes
up cleanly — catching provisioning drift that syntax validation alone
can't. It requires a self-hosted GitHub Actions runner with nested
virtualization enabled, which is not something GitHub-hosted runners
support.

**Security first:** this job is intentionally gated to
`workflow_dispatch` only — it never runs on `push` or `pull_request`.
Self-hosted runners on a public repository are a well-documented attack
vector: a malicious pull request could otherwise get arbitrary code
executed on your runner's network if the job ran automatically. Do not
change this job's trigger to `pull_request` without first restricting it
to non-fork pull requests, and even then, treat that as a deliberate
security decision, not a convenience change.

To set one up:

1. Provision a Linux host (bare metal or a cloud VM) with nested
   virtualization enabled and the same prerequisites as any other
   deployment target for this repo (see the root
   [README's Quick Start](README.md#quick-start)).
2. Register it as a self-hosted runner under this repository's
   **Settings → Actions → Runners**, following
   [GitHub's official runner setup guide](https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners/adding-self-hosted-runners).
3. When registering, add the label `smoke-test` in addition to the
   default `self-hosted` label — the workflow targets
   `runs-on: [self-hosted, smoke-test]` specifically, so a general-purpose
   self-hosted runner without that label will not pick up this job.
4. Trigger it manually from the **Actions** tab → **CI** → **Run workflow**,
   selecting the Vagrant provider your runner has installed.

---

## Community Guidelines

Please review:

- [Code of Conduct](CODE_OF_CONDUCT.md)
- [Security Policy](SECURITY.md)
- [Security Scope](docs/security-scope.md)

For questions or discussions, visit our [GitHub Discussions](https://github.com/solo2121/security-engineering-lab/discussions).

---

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.
