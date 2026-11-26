# Cavli build environments

Docker build environments for Cavli firmware. Pick the README of your product:

- [cavli/README.md](cavli/README.md): cqm220, cqm212, cqm211 and aq62 (SA525M) in one container (`cavli/cavli-setup`).

## Quick start (cqm220, cqm212, cqm211, aq62)

> **Until PR #2 is merged**, `main` has no `cavli/`: download the script from the branch instead:
> `wget https://raw.githubusercontent.com/cavli-wireless/docker/feature/cavli-setup/cavli/cavli-setup`

Needs Linux, Docker, `wget`, `jq`, `curl`, `tar`, `zstd`, `sha256sum`, `flock`, and about 79 GB free for all four
products.

```bash
wget https://raw.githubusercontent.com/cavli-wireless/docker/main/cavli/cavli-setup && chmod +x cavli-setup
./cavli-setup setup                      # or: ./cavli-setup setup cqm220
docker exec -it --user $(id -un) -e HOME=$HOME cavli_$(whoami) bash -l
```

Per product disk and download sizes, `--internal`, what the container can read, build commands and troubleshooting:
[cavli/README.md](cavli/README.md).

`cqm2xx/` and `aq62/` only hold a notice for the old `cqm2xx-setup` and `aq62-setup`, which `cavli-setup` replaces.

Other directories: `cqm22x/` is the previous tool (`cqm22x-setup`, all lines) and the source of the public `cqm22x-buildenv` image (its Dockerfile and `cqm-doctor` now carry the aq62 tools, tag 1.1.7); `sdx/`, `sdx35/`, `c10qm/`,
`cqs290/`, `le/` and `common/` are legacy environments, unchanged.
