#!/usr/bin/env python3
"""Run the simplex solver over a corpus, checking correctness and timing it.

This is the measurement core of the optimization loop. For each instance it:

  1. Runs the solver in `-json` metrics mode and parses the JSON object it emits
     (status, objective, pivot_count, and the solver's own solve timing).
  2. CORRECTNESS GATE: compares status+objective against the external oracle
     consensus (GLPK + Gurobi). A mismatch marks the instance as incorrect;
     any incorrect instance fails the whole run.

Timing comes from the solver itself: `-json --repeat N` re-solves the instance N
times in-process and reports the min and median solve time. Because the timing
loop is *inside* the program, it excludes process startup and input parsing --
the ~4 ms floor that would otherwise swamp small instances -- so the reported
number is the intrinsic solve cost. We use the MINIMUM as the point estimate (for
a deterministic CPU-bound computation the minimum is the run least perturbed by
external interference) and keep the median alongside.

Pivot count (also from the JSON) is deterministic, so it is a stability anchor:
if pivots are unchanged but time moved, the change is per-pivot cost (e.g.
rational blow-up), which we want to see, not hide.

`run_corpus()` returns a report dict consumed by compare.py; it is imported by
evaluate.py, which is the harness's sole entry point.

The solver binary is located by running `dune build` then using the known
`_build/default/bin/simplex.exe` path under the dune project root.
"""

import json
import os
import subprocess
import sys

from oracle import solve as oracle_solve, _close


def _project_root():
    """Directory containing dune-project (walk up from this file)."""
    d = os.path.dirname(os.path.abspath(__file__))
    while d != "/":
        if os.path.exists(os.path.join(d, "dune-project")):
            return d
        d = os.path.dirname(d)
    raise RuntimeError("could not find dune-project above bench/")


def build_solver(root=None):
    """Build the solver at `root` (default: this worktree) and return the exe.

    We pass `--root .` so the build is anchored at *that* dune-project and the exe
    lands in its own `_build`, isolated from any other checkout. dune may exit
    non-zero over a spurious alias-name warning from inside a git worktree while
    still producing the exe, so we do not trust the exit code -- we check that the
    exe exists.
    """
    if root is None:
        root = _project_root()
    exe = os.path.join(root, "_build", "default", "bin", "simplex.exe")
    proc = subprocess.run(["dune", "build", "--root", ".", "bin/simplex.exe"],
                          cwd=root, capture_output=True, text=True)
    if not os.path.exists(exe):
        raise RuntimeError(
            f"build failed: {exe} not produced\n{proc.stdout}\n{proc.stderr}")
    return exe


def require_json_support(exe, ref_label):
    """Fail fast, with a clear message, if this solver lacks the -json flag.

    -json is the sole metric source; there is no fallback. A ref that predates the
    -json commit builds a solver whose Arg.parse rejects the flag with an
    "unknown option" message. Rather than let that surface later as an
    unparseable-JSON error (or, worse, a bogus comparison), we detect it up front
    and explain exactly what to do.
    """
    proc = subprocess.run([exe, "-json", "--repeat", "1", "-q", os.devnull],
                          capture_output=True, text=True)
    blob = proc.stdout + proc.stderr
    if "unknown option" in blob and "-json" in blob:
        raise RuntimeError(
            f"ref '{ref_label}' has no -json support: its solver does not "
            f"understand the -json flag, which is the benchmark's only metric "
            f"source.\nFix: pick a baseline that already has -json, or rebase the "
            f"-json commit onto '{ref_label}' first.")


def run_solver_json(exe, rule, instance, repeat, warmup):
    """Run the solver in -json mode and return the parsed metrics dict.

    The solver runs `warmup` untimed solves, then `repeat` timed ones, and emits
    one JSON object with status, objective (exact rational + float), pivots, and
    min/median solve time over the timed samples.
    """
    args = [exe, "-json", "--repeat", str(repeat), "--warmup", str(warmup),
            "--rule", rule, instance]
    proc = subprocess.run(args, capture_output=True, text=True, timeout=300)
    out = proc.stdout.strip()
    try:
        return json.loads(out)
    except json.JSONDecodeError as e:
        raise RuntimeError(
            f"could not parse solver JSON for {instance}:\n{out!r}\n"
            f"stderr:\n{proc.stderr}") from e


# ---------------------------------------------------------------------------
# Per-instance measurement
# ---------------------------------------------------------------------------

def measure_instance(exe, rule, instance, oracle_result, trials, warmup):
    """Check correctness against the oracle and record the solver's own metrics.

    `trials`/`warmup` become the solver's --repeat/--warmup (its in-process timing
    loop). Returns a dict with the correctness verdict and the solver's metrics.
    """
    o_status, o_value = oracle_result

    m = run_solver_json(exe, rule, instance, trials, warmup)
    s_status = m["status"]
    s_value = m.get("value")            # absent for infeasible/unbounded

    correct = (s_status == o_status)
    if correct and o_status == "optimal":
        correct = _close(s_value, o_value)

    return {
        "instance": os.path.basename(instance),
        "correct": correct,
        "oracle_status": o_status,
        "oracle_value": o_value,
        "solver_status": s_status,
        "solver_value": s_value,
        "value_rat": m.get("value_rat"),
        "pivots": m["pivots"],
        "trials": m["trials"],
        "time_min": m["time_min"],
        "time_median": m["time_median"],
    }


# ---------------------------------------------------------------------------
# Corpus driver
# ---------------------------------------------------------------------------

def run_corpus(instances_dir, rule, trials, label, root=None, warmup=3):
    """Build the solver (at `root`), then measure it over the corpus.

    `root` selects which checkout to build (defaults to this worktree); passing a
    temporary git-worktree root lets a caller measure a different revision.
    `trials`/`warmup` are the solver's in-process --repeat/--warmup counts.
    """
    exe = build_solver(root)
    require_json_support(exe, label)
    instances = sorted(
        os.path.join(instances_dir, f)
        for f in os.listdir(instances_dir) if f.endswith(".in"))
    if not instances:
        raise RuntimeError(f"no .in instances in {instances_dir}")

    results = []
    all_correct = True
    for inst in instances:
        oracle_result = oracle_solve(inst)          # (status, value)
        r = measure_instance(exe, rule, inst, oracle_result, trials, warmup)
        results.append(r)
        if not r["correct"]:
            all_correct = False
        flag = "ok " if r["correct"] else "BAD"
        print(f"  [{flag}] {r['instance']:<16} "
              f"pivots={str(r['pivots']):>5}  "
              f"t_min={r['time_min']*1e3:8.3f}ms  "
              f"t_med={r['time_median']*1e3:8.3f}ms",
              file=sys.stderr)

    return {
        "label": label,
        "rule": rule,
        "instances_dir": os.path.abspath(instances_dir),
        "trials": trials,
        "warmup": warmup,
        "all_correct": all_correct,
        "results": results,
    }
