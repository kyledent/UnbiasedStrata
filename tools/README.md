# tools/ — vendored from upstream Strata

These five files are **upstream Strata's**, copied here unmodified except where noted.
They are the offline preparation tools that build the `--pack` and `--mtp` inputs the
engine consumes. They are **not** part of the serving path: nothing here runs when the
model is served, and nothing here is in the container that runs the engine.

## Provenance

| | |
|---|---|
| Source | https://github.com/Niko1221/Strata |
| Commit | `6f32ec070f23ced9f50e704d854d775da52591ab` (engine 0.1.39) — the commit this fork imported |
| Licence | MIT, © 2026 Niko1221 and the Strata contributors (see the repository root `LICENSE`) |

## Why they are vendored rather than cloned

`UPSTREAM.md` records that this fork's prepared artifacts were produced with upstream's
tools **at that commit**. Fetching them at build time turned out not to be dependable:

> `git branch -a --contains 6f32ec0` on upstream returns nothing. The pinned commit is
> reachable from **no upstream branch** (`main` and `rc/0.1.30` are the only ones), so a
> fresh `git clone` followed by `git checkout 6f32ec0` **fails**. It can still be had
> with an explicit `git fetch origin <sha>`, because GitHub serves unreachable objects —
> but that is not a guarantee, and unreachable objects are eventually collected.

So vendoring is what actually preserves them. It also means they are pinned by *this*
repository's history, which is stronger than a reference to a commit that may disappear.

Of the five, four are byte-identical to upstream's current `main`; only `iq_pack.py`
differs between the pin and `main`, and the pinned version is the one here.

## What each one does

| File | |
|---|---|
| `iq_pack.py` | builds the `--pack` directory from a GGUF: `index.txt`, `dense.bin`, `native_experts.txt` |
| `mtp_pack.py` | packs the fetched BF16 draft-head tensors into a Strata GGUF, quantising the routed experts |
| `mtp_rt.py` | converts that GGUF into the engine's runtime layout: `experts.bin`, `dense.bin` |
| `_paths.py` | finds llama.cpp's `gguf-py`. In this fork it resolves to `third_party/llama.cpp/gguf-py` with no `STRATA_GGUF_PY` needed |
| `gguf_reader.py` | the minimal GGUF reader `iq_pack.py` uses |

**Not vendored:** `mtp_fetch.py`, replaced by `strata/mtp_fetch_safe.py` in the
deployment repo — it is the only networked tool and its output is provably checkable
against pinned hashes, so it was worth owning. Also **not** vendored:
`strata_tokenizer.py`, because this fork has no use for it (below).

## The one local change

`iq_pack.py` no longer spawns `strata_tokenizer.py` to write `<out>/tokenizer/`.
This fork does not need it:

- the engine has no tokenizer — *"the prompt arrives as IDS via `--tokens`"*
  (`src/program/generate.cpp:9`);
- the front end tokenises with llama.cpp from the GGUF's own vocabulary and Jinja
  template (`frontend/main.cpp:9`).

Removing it also removes the only `subprocess` spawn in these files and the only
`regex` dependency, so the preparation venv needs `numpy` alone. The change is marked
in place with a comment; `git log` for the file shows exactly what was removed.

## Running them

Not directly. `strata/run_tools_sandboxed.sh` in the deployment repo runs them under
bubblewrap with no network and writes confined to one output directory, and audits them
statically first (`UnbiasedStrata_dev/tests/audit_strata_tools.py`). They need Python
3.10+ with `numpy`.
