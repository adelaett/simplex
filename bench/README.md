# Simplex benchmarking infrastructure

This directory is a **fitness function and correctness gate for an automated
optimization loop**. The intended workflow is:

1. Claude proposes a change to the solver (`solver/`).
2. The harness checks the change is still **correct**.
3. The harness checks the change is a **real, significant speedup** — not noise,
   not an artifact of overfitting to the instances it was tuned on.

Only changes that pass both gates should be accepted. The design deliberately
follows the SIGPLAN *Empirical Evaluation Checklist* and Heiser's *Systems
Benchmarking Crimes*, because the failure modes those documents warn about are
exactly the ways an automated loop can fool itself.

## Quick start

```bash
# ONE command: compare two git refs. Both are REQUIRED (no implicit default).
uv run python evaluate.py --baseline HEAD --candidate my-optim-branch
# exit 0 = ACCEPT, exit 1 = REJECT, exit 2 = infra error
```

So the loop is: commit the change on a branch, then compare it against the
baseline ref. Each ref is checked out into its **own throwaway git worktree**,
built there (`dune build`; deps come from the shared opam switch), and measured on
the same held-out instances. The caller's checkout and `_build` are untouched, and
both temp worktrees are removed afterwards.

Everything runs through [`uv`](https://docs.astral.sh/uv/); dependencies (numpy,
scipy) are pinned in `pyproject.toml` / `uv.lock`. The harness is pure Python —
`evaluate.py` orchestrates the other modules by importing them directly.

## The two gates

### 1. Correctness — external oracle consensus

Every instance's true optimum is computed by **two independent, external LP
solvers** and our solver must agree with both:

- **GLPK** (`glpsol` 5.0) — also the primary infeasible/unbounded status oracle.
- **Gurobi** (`gurobi_cl` 12) — numeric cross-check, run with `DualReductions=0`
  so it too distinguishes infeasible from unbounded.

Why external? Grading the solver against its own frozen outputs (the cram tests
in `test/`) only catches regressions against *current* behavior — and a proposer
that edits `solver/` could also edit those expected outputs. GLPK and Gurobi are
ground truth the proposer cannot touch. This is the checklist's *appropriate
baseline* and Heiser's *don't evaluate against yourself*.

The gate is verified to catch a silent wrong-answer bug: injecting a `2x`
objective error is flagged `[BAD]` on every instance and rejected before any
timing is even considered.

### 2. Fitness — geometric mean of speedups, with a significance test

`compare.py` computes, per instance, the ratio `baseline_time / candidate_time`
(>1 means the candidate is faster) and summarizes with the **geometric mean** —
the correct summary for normalized ratios (Fleming & Wallace; the checklist's
*inappropriate summary statistics* and *ratios plotted incorrectly*).

A speedup is only called **significant** if a **95% bootstrap confidence
interval** over the per-instance log-ratios lies **entirely above 1.0**. This is
the guard against *treating noise as signal*: on a laptop, timing has real
variance, and without this test the loop would accept meaningless ±2% wobble.

- Verified: comparing the solver **against an identical copy of itself** yields a
  geomean of ~1.00 with a CI straddling 1.0 → correctly **REJECTED** (no signal).

### Pivot count — a deterministic anchor

`compare.py` also reports the geomean **pivot-count** ratio. Pivot count is
deterministic (zero measurement noise), so:

- If time improved but pivots didn't, the win is in **per-pivot cost** (e.g.
  cheaper rational arithmetic) — which is real and worth keeping.
- If pivots dropped but time didn't, the per-pivot cost went **up** (e.g.
  rational blow-up) — a regression that a pivots-only metric would hide.

Reporting both is Heiser's *measure all effects* / the checklist's *fails to
measure all important effects*.

## Instance sources

A single instance distribution invites overfitting, so the corpus spans several
**families**, each seeded for reproducibility (`gen_instances.py`):

| Family | What it is | Why it's here |
|---|---|---|
| `rand_NxM` | dense uniform-random LPs, sizes 5×5 → 25×60 | scaling behavior; bulk of the geomean |
| `assign_K` | balanced K×K assignment LPs | real combinatorial structure, integral optimum |
| `match_LxR` | max-weight bipartite matching | sparse, decouples #vars from #constraints |
| `kleeminty_D` | Klee–Minty cube (base-100 integer form) | large-coefficient stress on exact rationals |
| `degen_N` | highly degenerate LPs | ratio-test ties, anti-cycling stress |

Measured pivot counts differ substantially between the `bland` and `max` rules
across the assignment, matching, random, and degeneracy families — i.e. the
corpus genuinely exercises pivot-strategy differences, which is the signal an
optimizer needs.

> Honest note on Klee–Minty: the textbook cube forces `2^D − 1` pivots under
> Dantzig's rule, but *this* solver's max-rule + lexicographic ratio test happens
> to solve it in one pivot. It is therefore **not** a worst case here; it is kept
> purely as large-coefficient arithmetic stress. This is documented in the
> generator rather than quietly relabeled, to avoid overclaiming.

## Overfitting guard: train / held-out split

- `instances/train/` — the proposer **may** inspect and iterate against these.
- `instances/heldout/` — used **only** for the final accept/reject verdict.

The two splits use **disjoint seed ranges** (train: base 0, held-out: base 1000),
so no held-out instance coincides with a train instance, and both are regenerated
from those fixed seeds on every `evaluate.py` run. This is the direct analog of
ML cross-validation — the checklist's *tested on training set* crime. A change
that only wins by memorizing the train instances will not clear the held-out gate.

## Files

| File | Role |
|---|---|
| `gen_instances.py` | seeded generators for all instance families; `python gen_instances.py {train,heldout} --out DIR` |
| `to_lp.py` | convert a `.in` instance to CPLEX LP format for the oracles |
| `oracle.py` | run GLPK + Gurobi, return their consensus optimum (raises on disagreement) |
| `run_bench.py` | build solver, run corpus, correctness-check vs oracle, parse the solver's `-json` metrics → JSON report |
| `compare.py` | baseline vs candidate → geomean + bootstrap CI + pivot ratio → ACCEPT/REJECT verdict + exit code |
| `evaluate.py` | the single loop entry point tying it all together (pure Python, imports the modules above) |

## Measurement hygiene

- **The solver times itself, with warmup + multiple samples.** In
  `-json --repeat N --warmup W` mode the solver runs W untimed solves (default
  W=3, via `--warmup`) to reach steady state, then N timed solves (default N=15,
  via `--trials`), reporting the min and median over the N samples. The timing
  loop is *in-process*, so it excludes process startup and input parsing — the
  metric is intrinsic solve cost, not a ~4 ms startup floor. The **minimum** is
  the point estimate (least perturbed by external interference for a
  deterministic CPU-bound task); the median is recorded alongside.
- **Near-threshold verdicts need more samples.** At the default `--trials 15` the
  laptop noise floor is a few percent, so a *true* speedup under ~3–4 % can
  occasionally flip a self-vs-self comparison to a false ACCEPT. For a change in
  that range, raise `--trials` (e.g. 30) — a self-vs-self check then stays
  correctly REJECTED, confirming the floor is below your signal.
- Each ref is built with `dune build` in its own temporary git worktree, isolated
  from every other checkout's `_build`.
- Bootstrap uses a fixed seed (`compare.py`), so a verdict is reproducible given
  the same two reports.

## Known limitations (disclosed, not hidden)

- **Comparisons are between committed refs.** The metric source is the solver's
  own `-json` output, which must exist in *both* refs being compared. Uncommitted
  working-tree edits are not measured directly — commit them on a branch first.
- **Corpus size (19 instances).** Enough to detect a solid geomean shift, but
  borderline changes (±a few %) can tip on laptop noise. For a high-stakes
  accept, raise `TRIALS` and/or enlarge the corpus in `gen_instances.py`.
- **Not a realistic workload.** These are synthetic/structured LPs, not
  production models (e.g. Netlib). They span useful structure but a win here is
  evidence, not proof, of a win on real-world LPs.
- **Platform-specific timing.** Absolute times reflect this machine (Apple M4).
  The geomean-ratio design is platform-robust, but re-record the baseline on the
  machine where verdicts are made.
- **Feasibility bias.** Random instances are generated feasible-at-origin to focus
  on optimization work; phase-1 feasibility hunting is under-exercised outside the
  degenerate family.
