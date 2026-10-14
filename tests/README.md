# Tests

Automated test suites for the security-engineering-lab. These run in CI via
the `run-tests` job in `.github/workflows/ci.yml`, and can also be run
locally before committing.

## Layout

```
tests/
├── python/                              # pytest unit tests for Python tooling
├── bash/                                # bats unit tests for Bash scripts
└── test_windows_hardening_advanced.py   # static checks for the windows-hardening advanced controls
```

## Running the Python tests

```bash
pip install -r requirements-dev.txt
pytest tests/python/ -v
pytest tests/test_windows_hardening_advanced.py -v
```

## Running the Bash tests

Requires [bats-core](https://github.com/bats-core/bats-core):

```bash
sudo apt-get install -y bats   # Debian/Ubuntu
bats tests/bash/
```

## What's covered

These suites intentionally test the **pure logic** in each script — argument
parsing, data structures, configuration tables, and output formatting —
rather than the parts that require root privileges, real network access,
or a live libvirt/Vagrant environment. End-to-end validation of the labs
themselves is handled by `validate-lab.sh` and the lab-specific
`test-*.sh` scripts, which are meant to be run inside a provisioned VM.

## Adding new tests

- For a new Python script: add `tests/python/test_<script_name>.py`.
  If the source file has a hyphen in its name (e.g. `port-scanner.py`),
  load it with `importlib.util.spec_from_file_location` instead of a
  normal `import`, since hyphens aren't valid in Python identifiers.
- For a new Bash script: add `tests/bash/test_<script_name>.bats`.
  Make sure the script guards its `main` call with
  `if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then main "$@"; fi` so it can
  be safely `source`d by the test file without actually executing.
