# Fetching the inputs (nothing below is committed to this repo)

This repo contains **no** PDK, standard-cell library, LEF, Liberty or GDS files,
and no copy of the Ibex RTL. Everything is taken unmodified from
OpenROAD-flow-scripts (ORFS) at a pinned commit.

| Input | Where it comes from | Pinned version |
|---|---|---|
| Flow scripts | https://github.com/The-OpenROAD-Project/OpenROAD-flow-scripts | commit `c9ac73efc603ec3b830caecd7874b1419c1b7d41` (2026-11-03) |
| Tool binaries (OpenROAD, Yosys + slang, KLayout) | ORFS Docker image `openroad/orfs:26Q4-260-gc9ac73efc` (image tag = same ORFS commit) | OpenROAD submodule `98c6045c72b7`, Yosys 0.68+post, KLayout 0.30.12 |
| Ibex RTL | `flow/designs/src/ibex_sv/` inside ORFS (pruned copy of https://github.com/lowRISC/ibex) | lowRISC commit `77d801001554cce8fe69e742e96539eecbe74425` |
| Design config / SDC | `flow/designs/nangate45/ibex/{config.mk,constraint.sdc}` inside ORFS | same ORFS commit |
| PDK / std cells | `flow/platforms/nangate45/` inside ORFS: FreePDK45 + Nangate Open Cell Library (open-source; **not** a foundry process) | same ORFS commit |

## Option A — Docker (what this study used)

```bash
docker pull openroad/orfs:26Q4-260-gc9ac73efc
```

If Docker Hub answers `429 Too Many Requests` (anonymous pull limit, shared IPs
hit it quickly), the image can be rebuilt from its layer blobs, which are not
rate-limited. See `scripts/fetch_orfs_image.sh` — it reads the layer list from
the Docker Hub web API, downloads and SHA256-verifies each blob, assembles the
root filesystem (applying OCI whiteouts) and runs `docker import`.

## Option B — native ORFS checkout

```bash
git clone https://github.com/The-OpenROAD-Project/OpenROAD-flow-scripts.git
cd OpenROAD-flow-scripts
git checkout c9ac73efc603ec3b830caecd7874b1419c1b7d41
sudo ./setup.sh && ./build_openroad.sh --local   # builds from source, slow
export ORFS_HOME=$PWD
```

then run `ORFS_NATIVE=1 scripts/run.sh ...`.

## What this repo adds on top

* `constraints/ibex_constraint.sdc` — byte-identical copy of the ORFS ibex SDC.
  `scripts/run.sh` only substitutes the `set clk_period` line per run.
* `scripts/` — run wrapper, CTS hook scripts, report summarizer.
