# AGENTS.md — running the benchmark to compare two solver revisions

This file tells an agent everything needed to benchmark the simplex solver and
decide whether one revision is a **correct** and **significantly faster**
improvement over another. The infrastructure lives in [`bench/`](bench/); read
[`bench/README.md`](bench/README.md) for the *why* (methodology). This file is the
operational contract: the exact commands, and the invariants that are easy to
violate without noticing.

## TL;DR

```bash
cd bench
uv run python evaluate.py --baseline <git-ref> --candidate <git-ref>
```

- Exit **0** = candidate ACCEPTED (correct AND significantly faster).
- Exit **1** = candidate REJECTED (incorrect, regression, or no significant change).
- Exit **2** = infrastructure error (bad ref, missing tool, unparseable output).

Both `--baseline` and `--candidate` are **required**; there is no default. The
baseline is the revision to beat; the candidate is the proposed change.

Typical optimization loop:

```bash
# 1. make a change, commit it on a branch
git checkout -b my-optim
#    ...edit solver/...
git commit -am "try X"

# 2. compare it against the current mainline (or any ref)
cd bench
uv run python evaluate.py --baseline claude/recursing-austin-d29bcb --candidate my-optim
#    exit 0 -> keep it; exit 1 -> discard/iterate
```

## What the command does, step by step

1. Regenerates the `train/` and `heldout/` instance corpora from fixed seeds.
2. For **each** ref (baseline, then candidate):
   - `git worktree add --detach` the ref into a throwaway temp dir.
   - `dune build` the solver *in that worktree* (its own isolated `_build`).
   - Run every held-out instance through `simplex -json --repeat N` and parse the
     JSON metrics (status, objective, pivots, in-process solve time).
   - Correctness-check each result against the GLPK + Gurobi oracle consensus.
   - `git worktree remove --force` the temp worktree.
3. Compare the two reports: geometric-mean speedup + 95% bootstrap CI + pivot
   ratio, and print the verdict.

Only the **solver binary** varies between the two runs. Instances, oracle, and
all statistics come from the *current* `bench/` checkout (see invariants below).

## Prerequisites (must all be present)

| Tool | Used for | Check |
|---|---|---|
| `uv` | Python env (numpy, scipy) | `uv --version` |
| `dune` + opam switch with `zarith`, `menhirSdk` | building the solver | `dune --version`; `opam switch show` |
| `glpsol` (GLPK) | correctness oracle #1 | `glpsol --version` |
| `gurobi_cl` (Gurobi, licensed) | correctness oracle #2 | `gurobi_cl --version` |
| `git` with worktree support | checking out each ref | `git --version` |

Python deps are pinned in `bench/pyproject.toml` / `bench/uv.lock` and installed
automatically by `uv run`. **Do not** `pip install` into system Python — this repo
uses `uv`; always invoke via `uv run python …` from inside `bench/`.

Both oracle solvers must agree on every instance. If GLPK and Gurobi ever
disagree (status or objective), the harness raises rather than guessing — that
means the benchmark itself is broken and the verdict cannot be trusted.

## Options

| Flag / env | Default | Meaning |
|---|---|---|
| `--baseline <ref>` | *(required)* | git ref for the revision to beat |
| `--candidate <ref>` | *(required)* | git ref for the revision under test |
| `--rule <name>` / `RULE=` | `bland` | pivot rule: `bland`, `max`, or `myrule` |
| `--trials <N>` / `TRIALS=` | `15` | in-process re-solves per instance for timing |

`--rule myrule` is **randomized** (mixes bland/max via `Random.bool`), so its
pivot count and timing are non-deterministic run-to-run. Do not use it as the rule
when judging a change — prefer `bland` (deterministic) or `max`. Keep the rule the
**same** for baseline and candidate; the harness already does this.

## Invariants — violate these and the result is wrong or the run fails

1. **Both refs must contain the `-json` solver code.** The timing/metrics come
   from the solver's own `simplex -json --repeat N` output (added in commit
   `d618027`). A ref *older* than that builds a solver with no `-json` flag; the
   run then fails cleanly with **exit 2**, and the error output contains the
   solver's `--help` text — that is the tell-tale sign you picked a pre-`-json`
   ref. Fix: rebase the change onto a ref that has `-json`, or pick a newer
   baseline.

2. **Comparisons are between committed refs, never the working tree.** Each ref is
   checked out fresh, so **uncommitted edits are not measured**. Commit your change
   on a branch first. There is no "measure the working tree" mode.

3. **Instances and oracle come from the *current* `bench/`, the solver from each
   ref.** `evaluate.py` runs from your checkout; only the compiled solver differs
   per ref. Therefore both refs must be compatible with the current `bench/` on two
   contracts:
   - the **input format** (`.in`: n / m / objective / bounds / matrix rows), and
   - the **`-json` output schema** (`status`, `value`, `value_rat`, `pivots`,
     `trials`, `time_min`, `time_median`).
   If a change alters either contract, the harness must be updated in lockstep, and
   you cannot meaningfully compare across that change with one `bench/` checkout.

4. **The solver maximizes.** It solves `max cᵀx s.t. Ax ≤ b, x ≥ 0`. (The old
   `Readme.md` says "min" — that is a documentation bug.) The LP converter and
   oracles are built around **maximize**; do not "fix" this to minimize.

5. **The verdict is decided on the held-out split only.** `instances/heldout/` uses
   disjoint seeds from `instances/train/`. If you are hand-tuning a change, look at
   `train/` — never at `heldout/` — or you overfit the very set that judges you.
   Both are regenerated every run, so never commit generated instances or edit them
   by hand.

6. **"Significant" means the whole 95% CI is above 1.0.** A positive geomean alone
   is **not** acceptance — a change is accepted only if the bootstrap CI lies
   entirely above 1.0 (`compare.py`: `accepted = correctness AND lo > 1.0`). A
   geomean of 1.02 with CI `[0.98, 1.06]` is REJECTED as noise. Do not
   cherry-pick the "best instance" number from the output; it is printed only to
   show the spread.

7. **Timing is intrinsic solve cost, not wall time.** `--repeat N` times the solve
   *in-process*, excluding OCaml startup and input parsing. So numbers here (µs–ms)
   are much smaller than end-to-end `time simplex …` and are not comparable to it.

8. **Pivot count is the noise-free anchor.** The output reports a pivot-ratio too.
   If time changed but pivots did not, the change is per-pivot cost (e.g. rational
   blow-up); if pivots changed but time did not, per-pivot cost moved the other
   way. A change that reports `Pivot geomean ratio: 1.0000x` and a time win is the
   cleanest kind (same search path, cheaper arithmetic).

9. **`myrule` and any randomized code path break reproducibility.** The solver
   calls `Random.self_init` and `myrule` uses `Random.bool`. For a trustworthy
   verdict keep the rule deterministic (see Options).

10. **Don't leave worktrees behind.** The harness cleans up its temp worktrees in a
    `finally`. If a run is killed mid-way, check `git worktree list` and
    `git worktree remove --force <path>` any stray `simplex-ref-*` entries before
    the next run.

## Reading the verdict

```
CORRECTNESS: passed (matches GLPK+Gurobi on all instances)
Time geomean speedup : 1.4208x (+42.08%)     <- headline metric
  95% bootstrap CI   : [1.2331, 1.6314]       <- must be entirely > 1.0 to accept
Pivot geomean ratio  : 1.0000x (+0.00% ...)   <- deterministic sanity anchor
Best  instance: match_10x8.in 2.341x          <- spread, not the headline
Worst instance: rand_5x5.in  0.875x
VERDICT: ACCEPTED (correct and significantly faster: CI entirely above 1.0)
```

A `[BAD]` flag on any instance during the run means the candidate disagreed with
the oracle → automatic REJECT (incorrect), regardless of speed.

## Extending the corpus

Instance families and sizes live in `bench/gen_instances.py`. To add a family,
add a `family_*` function and register it in `_split_spec` with **disjoint** seed
ranges for train (base 0) vs heldout (base 1000). Larger/harder instances make
timing signal clearer but slow every run. See `bench/README.md` for the honest
notes on each family (e.g. Klee–Minty is *not* a worst case for this solver's
`max` rule — it is kept only as large-coefficient rational stress).
