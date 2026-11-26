# Development

## Repository structure

Key directories and project files:

```text
security-engineering-lab/
├── .github/                    # CI workflows, issue templates, and repository automation
├── assets/                     # Architecture diagrams and deployment demonstrations
├── docs/                       # Architecture, setup, security, project, and guide documentation
├── examples/                   # Example configurations and reference material
├── labs/
│   ├── infrastructure/
│   │   └── devops-linux-lab/
│   └── security/
│       ├── active-directory/
│       │   ├── base/
│       │   └── vlan-segmented/
│       └── windows-hardening/  # Experimental, v0.1.0 MVP
├── scripts/                    # Host-readiness, validation, and automation helpers
├── tests/                      # pytest, Bats, and repository validation tests
├── tools/                      # Standalone lab and security utilities
├── CHANGELOG.md
├── CONTRIBUTING.md
├── LICENSE
├── Makefile
├── README.md
├── SECURITY.md
├── pyproject.toml
└── requirements-dev.txt
```

See the [Documentation Index](README.md) for the complete documentation map and each lab directory for provider-specific deployment instructions.

## Development quickstart

Install development dependencies:

```bash
python3 -m pip install -r requirements-dev.txt
```

Install pre-commit hooks:

```bash
pre-commit install
```

Run common quality checks:

```bash
make lint       # ShellCheck and Python linting
make test       # pytest and Bats unit tests
make validate   # Validate lab Vagrantfiles
make security   # Bandit and detect-secrets checks
make docs-refs  # Check for dangling documentation references
```

Additional development targets:

```bash
make format
make typecheck
make coverage
make validate-repo
make docs
make prereq
```

List all available targets:

```bash
make help
```

See [CONTRIBUTING.md](../CONTRIBUTING.md), the [Tests README](../tests/README.md), the [Scripts README](../scripts/README.md), and [Dependencies](dependencies.md) for development details.

> [!NOTE]
> Contributor tooling may have host-specific requirements. Review the relevant setup documentation when running shell, virtualization, or Linux-oriented validation workflows from macOS or Windows.
