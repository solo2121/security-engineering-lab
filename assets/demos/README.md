# Demo recordings

The GIFs in this folder are short previews used by the root README. The full,
unedited deployment recordings are too large for Git, so they are published as
assets of the `media-v1` GitHub Release:

| Recording | Lab | Link |
|---|---|---|
| `dc01.webm` | Active Directory (base) | [download](https://github.com/solo2121/security-engineering-lab/releases/download/media-v1/dc01.webm) |
| `devops1.webm` | DevOps / DevSecOps | [download](https://github.com/solo2121/security-engineering-lab/releases/download/media-v1/devops1.webm) |
| `opnsense-vlan.webm` | Segmented Active Directory (VLAN) | [download](https://github.com/solo2121/security-engineering-lab/releases/download/media-v1/opnsense-vlan.webm) |

CI fails on any tracked file over 10 MB, and `*.webm` / `*.mp4` in this folder
are ignored by Git, so a recording cannot be committed here by accident. To
replace one, publish a new `media-vN` release (see
[the release process](../../docs/project/release-process.md#media-only-releases)).
