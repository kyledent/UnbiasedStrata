# Relationship to upstream

## Sources

| What | Where | Version |
| --- | --- | --- |
| Engine | https://github.com/Niko1221/Strata | commit `6f32ec070f23ced9f50e704d854d775da52591ab`, engine 0.1.39 |
| ggml (CPU backend, CUDA matrix kernels) | https://github.com/ggml-org/llama.cpp, as the submodule `third_party/llama.cpp` | commit `3cf03257f219afbe7334045ff7c6a06ac68c627d`, the one upstream Strata pins |

The first commit of this repository is the upstream snapshot as published. One file was not imported:
`bench/results/2026-09-30-community-rtx-5090/engine.log`, which upstream's own ignore rules exclude.
`git diff <first commit> HEAD -- src include CMakeLists.txt` shows every change to the engine and its build.

## What this fork changed

- **Build:** ggml is taken from the submodule. Upstream cloned llama.cpp during the build.
- **Removed:** the Python installer and launchers, the Python server and web app, the Python tools, the
  Intel SYCL port, Docker files, benchmark results, the test suite, translations, and all docs except
  `docs/upstream/DETAILS.md` and the paper.
- **Added:** `frontend/`, the C++ front end (tokenizer, chat template, output parser and HTTP API, using
  llama.cpp's code from the submodule), and a build target that links it with the engine into one binary.
- **Engine source (`src/`, `include/`):** unchanged so far. The engine's own program is compiled into the
  binary with its entry point renamed; the front end starts it as a child process.

## Changes in this fork

A further fork, to run the model across several GPUs and to load the three- and four-shard Unsloth
quantisations. Three limits of the front end blocked that; the engine needed no changes for any of
them.

- **Multi-GPU (the layer split) is allowed again.** The front end refused `--layer-split` and
  `--split-device`, but that was a policy blocklist with no code behind it: the front end holds no
  CUDA state at all (it is a pipe-driven HTTP shim) and the engine's split code is upstream's,
  intact. Both flags now reach the engine, and a front-end `--gpus D[,D..]` sets the child's
  `CUDA_VISIBLE_DEVICES` and derives `--layer-split auto --split-device ...`. The engine has no
  device-selection flag, so `CUDA_VISIBLE_DEVICES` is the only way to choose the main card; it also
  renumbers the devices, which is why `--split-device` gets positions in the list rather than
  nvidia-smi numbers. `--peer-device`, `--peer-slots`, `--remote-expert`, `--vision` and `--batch`
  stay refused, now each with its own reason.
  *Why it matters:* one 48 GB card holds only 52% of UD-Q4_K_XL's experts and 81% of IQ3_S's, and
  every miss is a round trip to the CPU pool. Two cards hold all of IQ3_S; the XL needs two on a
  48 GB card or four on a 32 GB one.
- **Models with more than two shards load.** `--model` was required to match `-00001-of-00002`, so
  only the 2-shard GSQ-RCO files worked. Unsloth's UD-IQ4_XS has 3 shards and UD-Q4_K_XL has 4. The
  shard total is now read from the name, every shard is checked to be present, and `--ple-gguf` is
  passed only when there are at most two — with three or more the engine finds the PLE table's shard
  itself from shard 1, which is what upstream's `setup.py` does at step 7.
- **The Makefile can build for Volta.** `EXPERIMENTAL_SM60=1` and `NVCC=<a 12.x nvcc>` were not
  reachable through `make`. CUDA 13 cannot compile sm_60/sm_70 at all, and the CUDA 12 build covers
  sm_60..sm_89 plus PTX, so one binary serves a V100 and an L40S:
  `CUDA_ARCHS='70;89' EXPERIMENTAL_SM60=1 NVCC=/usr/local/cuda-12.8/bin/nvcc make build`.

Not addressed: this fork is still engine 0.1.39 (upstream Strata is 0.1.41), so it lacks
`STRATA_SM70_TABLE` — the opt-in Volta decode kernels — along with the Linux file tier and
`--kv k8v4` KV streaming. The removed test suite also took `qsa_prompt_attn_parity`, the documented
way to check the Volta kernels. UD-Q4_K_XL has not been run on sm_70 by anyone; upstream's V100
measurements used UD-IQ4_XS.

Code paths for other models, AMD cards and Windows are still present in the engine source. They are not
built by `make build`, not tested and not supported here. They are left in place so the engine stays
identical to upstream and can be updated by re-importing it.

## Prepared model files

The pack and the draft head are produced once with upstream Strata's tools at the commit above. These are
the commands that were used, with `U` an upstream checkout, `G` this repository's
`third_party/llama.cpp/gguf-py`, and Python 3 with `numpy` and `regex`:

```
export STRATA_GGUF_PY=$G
# the pack, from the model's first shard (the second must be beside it)
python $U/tools/iq_pack.py --gguf Qwen3.8-Flash-Next-GSQ-RCO-IQ3_XXS-00001-of-00002.gguf --out pack-iq3-xxs
cp $U/data/expert-profile.bin pack-iq3-xxs/

# the draft head, from the original checkpoint's 31 draft-head tensors (about 5 GB, fetched over HTTP)
python $U/tools/mtp_fetch.py fetch  --out mtp-bf16
python $U/tools/mtp_fetch.py verify --out mtp-bf16
python $U/tools/mtp_pack.py --src mtp-bf16 --experts q2_0 --out mtp-bf16/mtp-q2_0.gguf
python $U/tools/mtp_rt.py --gguf mtp-bf16/mtp-q2_0.gguf --out mtp
cp $U/data/draft_vocab.bin mtp/
```

The model shards used were revision `ed59f92082b1e93c0e96d60a8b11aab089b52f09` of
ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-GGUF, verified against their published SHA-256 checksums. The
prepared files have not been published yet, and their checksums were not recorded before the pod that
held them was shut down.
