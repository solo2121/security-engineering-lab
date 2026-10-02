# Release and Tagging Process

This document defines how Git tags and GitHub Releases are created for this
repository. A release tag is a claim that a defined state of the lab can be
checked out, understood, and deployed as documented. Tags are only created
from a commit that satisfies the checklist below.

## Versioning scheme

- Repository releases use Semantic Versioning in the form `vMAJOR.MINOR.PATCH`.
- Versioning continues from the existing `v1.1` tag. Versions are never
  lowered or reused.
  - `MINOR` increases for new labs, new lab profiles, or substantial scenario
    additions.
  - `PATCH` increases for fixes, documentation corrections, and provisioning
    reliability changes.
- Every release tag is an annotated tag (`git tag -a`). Lightweight tags are
  not used for releases.
- Tags are created on `main` after the change has been merged, never on a
  feature branch commit that may later be rebased or squashed.
- A published tag is never moved or deleted. A mistake is corrected by a new
  patch release.

## Repository releases versus lab revisions

Individual labs carry their own revision numbers in `CHANGELOG.md` (for
example the DevOps/DevSecOps lab, the Active Directory labs, and the Windows
Server Hardening lab). These are lab revisions, not Git tags. Release notes
for a repository tag list the lab revisions included in that release.
Lab revisions are not used as tag names.

## Existing tags

- `v1.1` is an annotated tag from 2026-01-23 that predates this document. It
  is kept as is.
- `portfolio-start` and `pre-cleanup-2026-06-14` are lightweight historical
  markers, not releases. They are kept as is.
- Published tags are never moved or deleted.

## Release gates

A release is only published when all of the following are true:

- Each lab listed as supported has been deployed from a clean clone on the
  documented primary provider, and the result is recorded.
- Known issues listed in `CHANGELOG.md` for supported labs are fixed or have
  documented workarounds.
- CI passes on the release commit, and the deployment evidence is linked from
  the release notes.
- Labs marked experimental are labeled as such in the release notes.

## Pre-release checklist

Complete every item against the exact commit that will be tagged.

- [ ] The commit is on `main` and the change has been merged.
- [ ] CI is green on that commit.
- [ ] `make lint`, `make test`, `make validate`, `make security`, and
      `make docs-refs` pass locally.
- [ ] `./scripts/check-prerequisites.sh --all` passes on the validation host.
- [ ] Each lab included in the release has been deployed from a clean clone on
      the primary provider, with host, provider, and Vagrant versions
      recorded.
- [ ] `CHANGELOG.md` has a dated section for the release and `[Unreleased]`
      contains only changes made after it.
- [ ] README, lab READMEs, and the roadmap agree on supported hosts,
      providers, and lab status.
- [ ] No real credentials, keys, or host-specific data are present. The
      intentional lab credentials are covered by the documented baseline.
- [ ] `LICENSE`, `SECURITY.md`, and `CONTRIBUTING.md` are present and current.
- [ ] Known limitations and known issues are copied into the release notes.

## Tagging procedure

Run from a clean checkout of `main`. Replace the placeholders.

```bash
VERSION=vX.Y.Z
COMMIT=<verified full commit SHA>

git branch --show-current
git status --porcelain
git fetch origin --tags
git tag -l "$VERSION"
git ls-remote --tags origin "refs/tags/$VERSION"
git show --no-patch --format='%H %an %ad %s' "$COMMIT"

git tag -a "$VERSION" "$COMMIT" -m "Release $VERSION"
git show "$VERSION"

git push origin "refs/tags/$VERSION"
```

If the tag was created locally and has not been pushed, it can be removed
with `git tag -d "$VERSION"` and recreated. Once pushed, publish a new patch
release instead of changing the tag.

Create the GitHub Release from the pushed tag. Mark it as a pre-release if
any included lab or validation step is incomplete.

## Release notes template

```markdown
## Summary
One or two sentences describing the state of the lab at this release.

## Included labs and revisions
| Lab | Revision | Status |
| --- | --- | --- |

## Validation
- Host, provider, and Vagrant versions used:
- Labs deployed from a clean clone:
- CI run:

## Known limitations
## Known issues
## Upgrade notes
## Full changelog
```

## What a release does not guarantee

- Third-party Vagrant boxes can change independently of this repository.
- CI validates repository quality and selected provider workflows. It does not
  deploy every lab on every run.
- Hosts and providers outside the documented support matrix are unvalidated.
