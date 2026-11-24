# Cavli build environments

Docker build environments for Cavli firmware. Pick the README of your product:

- [cavli/README.md](cavli/README.md): cqm220, cqm212, cqm211 and aq62 (SA525M) in one container (`cavli/cavli-setup`).

`cqm2xx/` and `aq62/` only hold a notice for the old `cqm2xx-setup` and `aq62-setup`, which `cavli-setup` replaces.

Other directories: `cqm22x/` is the previous tool (`cqm22x-setup`, all lines) and the source of the public `cqm22x-buildenv` image (its Dockerfile and `cqm-doctor` now carry the aq62 tools, tag 1.1.7); `sdx/`, `sdx35/`, `c10qm/`,
`cqs290/`, `le/` and `common/` are legacy environments, unchanged.
