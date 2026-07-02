#!/usr/bin/env python3
"""Independent ground-truth oracles for the simplex solver.

The correctness gate must not be graded against the very solver being mutated
(the "evaluate against self" crime), and it must not be foolable by a proposer
that also edits the solver's own expected-output files. So we compute the true
optimum with two *external, independent* LP solvers and require our solver to
agree with them:

  * GLPK  (glpsol 5.0)     -- primary status oracle; clean infeasible/unbounded.
  * Gurobi (gurobi_cl 12)  -- numeric cross-check; disambiguated with
                              DualReductions=0 so it also separates the two
                              infeasible/unbounded cases.

Each oracle returns a normalized result:
    ("optimal", value_float) | ("infeasible", None) | ("unbounded", None)

`solve` runs both and returns their consensus, raising if they disagree (which
would mean the benchmark itself is broken and no verdict can be trusted).
"""

import os
import re
import subprocess
import sys
import tempfile

from to_lp import to_lp

# Objective values are compared with a relative tolerance because the oracles
# are floating point while our solver is exact rational. 1e-6 is far tighter
# than any real optimization signal but loose enough for FP round-off.
REL_TOL = 1e-6
ABS_TOL = 1e-6


def _close(a, b):
    return abs(a - b) <= max(ABS_TOL, REL_TOL * max(abs(a), abs(b)))


# ---------------------------------------------------------------------------
# GLPK
# ---------------------------------------------------------------------------

_GLPK_OBJ_RE = re.compile(r"Objective:\s+\S+\s*=\s*([-\d.eE+]+)")


def solve_glpk(lp_path):
    with tempfile.NamedTemporaryFile("r", suffix=".sol", delete=False) as sol:
        sol_path = sol.name
    try:
        proc = subprocess.run(
            ["glpsol", "--lp", lp_path, "--max", "-o", sol_path],
            capture_output=True, text=True, timeout=120,
        )
        out = proc.stdout + proc.stderr
        if "NO PRIMAL FEASIBLE SOLUTION" in out:
            return ("infeasible", None)
        if "NO DUAL FEASIBLE SOLUTION" in out:
            return ("unbounded", None)
        with open(sol_path) as f:
            sol_text = f.read()
        m = _GLPK_OBJ_RE.search(sol_text)
        if m and "OPTIMAL" in sol_text:
            return ("optimal", float(m.group(1)))
        raise RuntimeError(f"glpsol: could not parse result\n{out}\n---\n{sol_text}")
    finally:
        if os.path.exists(sol_path):
            os.unlink(sol_path)


# ---------------------------------------------------------------------------
# Gurobi
# ---------------------------------------------------------------------------

_GRB_OBJ_RE = re.compile(r"Optimal objective\s+([-\d.eE+]+)")


def solve_gurobi(lp_path):
    # LogFile="" stops gurobi_cl from dropping a gurobi.log in the cwd.
    proc = subprocess.run(
        ["gurobi_cl", "DualReductions=0", "LogFile=", lp_path],
        capture_output=True, text=True, timeout=120,
    )
    out = proc.stdout + proc.stderr
    # Order matters: "Infeasible or unbounded" shouldn't occur with
    # DualReductions=0, but check the specific words first.
    if re.search(r"\bInfeasible model\b", out):
        return ("infeasible", None)
    if re.search(r"\bUnbounded model\b", out):
        return ("unbounded", None)
    m = _GRB_OBJ_RE.search(out)
    if m:
        return ("optimal", float(m.group(1)))
    raise RuntimeError(f"gurobi_cl: could not parse result\n{out}")


# ---------------------------------------------------------------------------
# Consensus
# ---------------------------------------------------------------------------

def solve(instance_path):
    """Return the consensus oracle result for an `.in` instance.

    Raises RuntimeError if the two oracles disagree -- that means the benchmark
    harness cannot be trusted for this instance, which is a louder and more
    useful failure than silently picking one.
    """
    with open(instance_path) as f:
        lp = to_lp(f.read())
    with tempfile.NamedTemporaryFile("w", suffix=".lp", delete=False) as fh:
        lp_path = fh.name
        fh.write(lp)
    try:
        g = solve_glpk(lp_path)
        r = solve_gurobi(lp_path)
    finally:
        os.unlink(lp_path)

    if g[0] != r[0]:
        raise RuntimeError(
            f"oracle status disagreement on {instance_path}: "
            f"glpk={g}, gurobi={r}")
    if g[0] == "optimal" and not _close(g[1], r[1]):
        raise RuntimeError(
            f"oracle value disagreement on {instance_path}: "
            f"glpk={g[1]}, gurobi={r[1]}")
    return g


def main():
    if len(sys.argv) < 2:
        sys.exit("usage: oracle.py <instance.in> [instance.in ...]")
    for path in sys.argv[1:]:
        status, val = solve(path)
        val_s = "" if val is None else f" {val}"
        print(f"{os.path.basename(path)}\t{status}{val_s}")


if __name__ == "__main__":
    main()
