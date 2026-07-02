#!/usr/bin/env python3
"""Generate benchmark instances for the simplex solver.

Every instance is written in the solver's native `.in` format:

    n                          # number of variables
    m                          # number of constraints
    c_1 ... c_n                # objective coefficients (MAXIMIZE c^T x)
    b_1 ... b_m                # constraint bounds
    A_11 ... A_1n              # constraint matrix, one row per constraint
    ...
    A_m1 ... A_mn

The solved problem is   max c^T x   s.t.   A x <= b,  x >= 0.

Design decisions (see bench/README.md for the rationale):

  * Multiple *families* of instances, not one. A single distribution (e.g. dense
    uniform-random) lets an automated optimizer overfit to that distribution.
    We include random-dense, structured-combinatorial, and adversarial families
    so a change must generalize to be accepted.

  * Every family is *seeded*. Given the same seed an instance is bit-for-bit
    reproducible, which is required both for a fair before/after comparison and
    for the held-out set to be regenerable on demand.

  * Coefficients are integers or small rationals-as-integers so that the exact
    rational solver and the floating-point oracles (GLPK, Gurobi) agree on the
    optimum without rounding ambiguity.

This module is used two ways:
  * as a CLI (`python gen_instances.py <split> --out <dir>`) to populate a corpus,
  * imported, via `family_*` functions returning instance strings.
"""

import argparse
import os
import random


# ---------------------------------------------------------------------------
# Serialization
# ---------------------------------------------------------------------------

def format_instance(c, b, A):
    """Serialize an LP into the solver's `.in` text format.

    c: length-n objective, b: length-m bounds, A: m x n matrix (lists of ints).
    """
    n = len(c)
    m = len(b)
    assert all(len(row) == n for row in A), "A rows must have length n"
    assert len(A) == m, "A must have m rows"
    lines = [str(n), str(m)]
    lines.append(" ".join(str(x) for x in c))
    lines.append(" ".join(str(x) for x in b))
    for row in A:
        lines.append(" ".join(str(x) for x in row))
    return "\n".join(lines) + "\n"


# ---------------------------------------------------------------------------
# Instance families
#
# Each family is a function (rng, **params) -> instance string. Keeping the rng
# explicit (rather than the global `random`) is what makes seeding reliable.
# ---------------------------------------------------------------------------

def family_random_dense(rng, n, m, lo=-9, hi=9, b_lo=1, b_hi=20):
    """Dense LP with uniform-random integer coefficients.

    b is kept strictly positive so that x = 0 is always feasible; this guarantees
    the problem is feasible and lets us focus the comparison on optimization work
    rather than on phase-1 feasibility hunts. (A separate family exercises
    infeasibility.) Cheap and controllable, but *not* realistic on its own -- a
    known limitation, disclosed in the README.
    """
    c = [rng.randint(1, hi) for _ in range(n)]          # positive obj -> nontrivial optimum
    b = [rng.randint(b_lo, b_hi) for _ in range(m)]
    A = [[rng.randint(lo, hi) for _ in range(n)] for _ in range(m)]
    # Ensure each constraint has at least one positive coeff so the feasible
    # region is bounded in that direction (reduces the rate of unbounded LPs,
    # which are trivial and uninteresting for timing).
    for row in A:
        if all(v <= 0 for v in row):
            row[rng.randrange(n)] = rng.randint(1, hi)
    return format_instance(c, b, A)


def family_assignment(rng, k):
    """Balanced assignment LP: assign k agents to k tasks, maximize total value.

    Variables x_ij (k^2 of them). Constraints: each agent used <=1, each task
    used <=1 (2k constraints). The LP relaxation is integral (assignment polytope),
    so the optimum is a clean integer both solvers reproduce exactly. This is a
    genuinely *structured*, real-world-shaped problem, unlike the random family.
    """
    n = k * k
    value = [[rng.randint(1, 20) for _ in range(k)] for _ in range(k)]
    c = [value[i][j] for i in range(k) for j in range(k)]

    A = []
    b = []
    # each agent i assigned to at most one task: sum_j x_ij <= 1
    for i in range(k):
        row = [0] * n
        for j in range(k):
            row[i * k + j] = 1
        A.append(row)
        b.append(1)
    # each task j taken by at most one agent: sum_i x_ij <= 1
    for j in range(k):
        row = [0] * n
        for i in range(k):
            row[i * k + j] = 1
        A.append(row)
        b.append(1)
    return format_instance(c, b, A)


def family_bipartite_matching(rng, n_left, n_right, density):
    """Max-weight fractional matching on a random bipartite graph.

    Variables = edges. Constraints = one per vertex (sum of incident edges <= 1).
    Structured and sparse; the number of constraints (vertices) is decoupled from
    the number of variables (edges), which stresses a different (n, m) regime than
    the square assignment family.
    """
    edges = []
    weights = []
    for u in range(n_left):
        for v in range(n_right):
            if rng.random() < density:
                edges.append((u, v))
                weights.append(rng.randint(1, 20))
    if not edges:                       # guarantee a non-empty problem
        edges.append((0, 0))
        weights.append(1)
    n = len(edges)
    c = weights
    A = []
    b = []
    for u in range(n_left):
        row = [1 if edges[e][0] == u else 0 for e in range(n)]
        if any(row):
            A.append(row)
            b.append(1)
    for v in range(n_right):
        row = [1 if edges[e][1] == v else 0 for e in range(n)]
        if any(row):
            A.append(row)
            b.append(1)
    return format_instance(c, b, A)


def family_klee_minty(rng, d):
    """Klee-Minty cube: the classic worst case for Dantzig's pivot rule.

    Standard integer form (Chvatal, Linear Programming, ch. 4; Klee & Minty 1972):

        max  sum_{i=1..d} 10^{d-i} x_i
        s.t. for i=1..d:  2 * sum_{j<i} 10^{i-j} x_j + x_i <= 100^{i-1},  x >= 0

    Under the *textbook* Dantzig rule from the origin this cube forces 2^d - 1
    pivots. NOTE: this solver's "max" rule pairs largest-objective-coefficient
    entering with a lexicographic ratio-test leaving rule, and on this cube that
    combination happens to jump to the apex in a single pivot -- so here it is
    *not* a worst case for max. It is kept in the corpus for a different, still
    valuable reason: the base-100 right-hand sides and factor-of-2 off-diagonals
    produce large integer coefficients, which stresses the exact-rational
    arithmetic (the very cost the project's Discussion.md hypothesizes about).
    Real pivot-rule divergence in this corpus comes from the assignment, matching,
    random, and degeneracy families; see bench/README.md.

    Exact-rational arithmetic makes coefficients grow with d, so d is kept small.
    `rng` is unused (deterministic family) but kept for a uniform interface.
    """
    c = [10 ** (d - i - 1) for i in range(d)]           # i is 0-based here
    A = []
    b = []
    for i in range(d):                                  # constraint i, 0-based
        row = [0] * d
        for j in range(i):
            row[j] = 2 * (10 ** (i - j))
        row[i] = 1
        A.append(row)
        b.append(100 ** i)
    return format_instance(c, b, A)


def family_degenerate(rng, n, extra):
    """Highly degenerate LP: many constraints pass through the same vertex.

    Built by stacking `extra` redundant/near-redundant tight constraints at the
    origin-adjacent vertex, which forces ratio-test ties and stresses anti-cycling
    (Bland). Feasible at x = 0. Complements Klee-Minty with a *degeneracy* stress
    rather than an *exponential-path* stress.
    """
    c = [rng.randint(1, 9) for _ in range(n)]
    A = []
    b = []
    # n bounding constraints
    for i in range(n):
        row = [0] * n
        row[i] = 1
        A.append(row)
        b.append(rng.randint(1, 5))
    # `extra` degenerate constraints that are tight at the same point (b=0 rows
    # with mixed signs create ratio ties without making the LP infeasible).
    for _ in range(extra):
        row = [rng.choice([-1, 0, 1]) for _ in range(n)]
        if all(v == 0 for v in row):
            row[rng.randrange(n)] = 1
        A.append(row)
        b.append(0)
    return format_instance(c, b, A)


# ---------------------------------------------------------------------------
# Corpus definition
#
# A "split" is a list of (name, family_fn, params, seed). The train and heldout
# splits use DISJOINT seed ranges so that no heldout instance can coincide with a
# train instance. Sizes are chosen so the whole corpus runs in seconds-to-minutes
# on a laptop while still spanning small -> medium problems.
# ---------------------------------------------------------------------------

def _split_spec(base_seed):
    """Return the list of instances for a split, parameterized by a seed offset.

    base_seed=0 -> train, base_seed=1000 -> heldout (disjoint seeds).
    """
    spec = []

    # Random dense, a range of sizes (scaling behavior + bulk of the geomean).
    sizes = [(5, 5), (8, 12), (12, 20), (16, 30), (20, 40), (25, 60)]
    for k, (n, m) in enumerate(sizes):
        spec.append((f"rand_{n}x{m}", family_random_dense,
                     dict(n=n, m=m), base_seed + k))

    # Structured: assignment problems.
    for k, size in enumerate([4, 5, 6, 7]):
        spec.append((f"assign_{size}", family_assignment,
                     dict(k=size), base_seed + 100 + k))

    # Structured: bipartite matching.
    for k, (nl, nr) in enumerate([(6, 6), (8, 5), (10, 8)]):
        spec.append((f"match_{nl}x{nr}", family_bipartite_matching,
                     dict(n_left=nl, n_right=nr, density=0.5),
                     base_seed + 200 + k))

    # Adversarial: Klee-Minty (deterministic; seed unused but disjoint anyway).
    for k, d in enumerate([4, 5, 6]):
        spec.append((f"kleeminty_{d}", family_klee_minty,
                     dict(d=d), base_seed + 300 + k))

    # Adversarial: degeneracy.
    for k, (n, extra) in enumerate([(6, 6), (10, 10), (14, 14)]):
        spec.append((f"degen_{n}", family_degenerate,
                     dict(n=n, extra=extra), base_seed + 400 + k))

    return spec


SPLITS = {
    "train": lambda: _split_spec(0),
    "heldout": lambda: _split_spec(1000),
}


def generate_split(split, out_dir):
    """Write every instance of `split` into out_dir as <name>.in. Returns names."""
    os.makedirs(out_dir, exist_ok=True)
    names = []
    for name, fn, params, seed in SPLITS[split]():
        rng = random.Random(seed)
        text = fn(rng, **params)
        path = os.path.join(out_dir, f"{name}.in")
        with open(path, "w") as f:
            f.write(text)
        names.append(name)
    return names


def main():
    ap = argparse.ArgumentParser(description="Generate simplex benchmark instances.")
    ap.add_argument("split", choices=list(SPLITS.keys()))
    ap.add_argument("--out", required=True, help="output directory")
    args = ap.parse_args()
    names = generate_split(args.split, args.out)
    print(f"wrote {len(names)} instances to {args.out}")
    for n in names:
        print("  " + n)


if __name__ == "__main__":
    main()
