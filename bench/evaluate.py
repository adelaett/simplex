#!/usr/bin/env python3
"""Compare two solver revisions (the loop entry point).

Given two git refs -- a BASELINE (the revision to beat) and a CANDIDATE (the
proposed change) -- this answers:

  1. Is the candidate CORRECT?  (matches the GLPK+Gurobi oracle consensus)
  2. Is it a real, SIGNIFICANT IMPROVEMENT over the baseline?

Both refs are checked out into their own throwaway git worktrees, built there
(`dune build`), and measured on the same held-out instances under identical
conditions. Neither the current working tree nor its `_build` is touched.

    uv run python evaluate.py --baseline HEAD --candidate my-optim-branch

Both refs are REQUIRED -- there is no implicit default, so it is always explicit
which two revisions are being compared.

The verdict is decided on the HELD-OUT split, which the proposer is told not to
inspect or tune against. Both splits are regenerated from fixed disjoint seeds on
every run, so they are reproducible yet mutually independent.

Exit codes:
    0  candidate accepted (correct AND significantly faster than baseline)
    1  candidate rejected (incorrect, regression, or no significant change)
    2  usage / infrastructure error

This module orchestrates the other bench modules by importing them directly
(no shelling out), so the whole harness is pure Python.
"""

import argparse
import json
import os
import subprocess
import sys
import tempfile

from gen_instances import generate_split
from run_bench import run_corpus, _project_root
from compare import compare, format_verdict

HERE = os.path.dirname(os.path.abspath(__file__))
TRAIN_DIR = os.path.join(HERE, "instances", "train")
HELDOUT_DIR = os.path.join(HERE, "instances", "heldout")


def regenerate_splits():
    """Regenerate train + held-out corpora from their fixed seeds."""
    generate_split("train", TRAIN_DIR)
    generate_split("heldout", HELDOUT_DIR)


def measure_ref(ref, side, rule, trials):
    """Check out `ref` into a throwaway worktree, build it, and measure it.

    The ref is checked out with `git worktree add --detach`, the solver is built
    there by run_corpus->build_solver (`dune build`, deps come from the shared
    opam switch), and the corpus is run against it. The temp worktree and its
    `_build` are removed afterwards, so nothing leaks and the caller's checkout is
    untouched. `side` is a label ("baseline"/"candidate") for output.
    """
    root = _project_root()
    with tempfile.TemporaryDirectory(prefix="simplex-ref-") as tmp:
        ref_root = os.path.join(tmp, "ref")
        print(f"[{side}] checking out '{ref}' into a temp worktree...",
              file=sys.stderr)
        add = subprocess.run(
            ["git", "worktree", "add", "--detach", ref_root, ref],
            cwd=root, capture_output=True, text=True)
        if add.returncode != 0:
            raise RuntimeError(
                f"git worktree add failed for ref '{ref}':\n{add.stderr}")
        try:
            print(f"[{side}] building and measuring '{ref}' (rule={rule})...",
                  file=sys.stderr)
            return run_corpus(HELDOUT_DIR, rule, trials, f"{side}:{ref}",
                             root=ref_root)
        finally:
            # Drop the temp worktree registration (the dir is cleaned up by
            # TemporaryDirectory; --force also drops the now-missing checkout).
            subprocess.run(["git", "worktree", "remove", "--force", ref_root],
                           cwd=root, capture_output=True, text=True)


def do_compare(baseline_ref, candidate_ref, rule, trials):
    """Compare two git refs: build+measure each in its own worktree, then judge."""
    try:
        baseline = measure_ref(baseline_ref, "baseline", rule, trials)
        candidate = measure_ref(candidate_ref, "candidate", rule, trials)
    except RuntimeError as e:
        print(str(e), file=sys.stderr)
        return 2

    verdict = compare(baseline, candidate)
    print("", file=sys.stderr)
    print(format_verdict(verdict, baseline_ref, candidate_ref))
    return 0 if verdict["accepted"] else 1


def main():
    ap = argparse.ArgumentParser(
        description="Compare two solver revisions (given as git refs) end-to-end.")
    ap.add_argument("--baseline", required=True,
                    help="git ref for the baseline (the revision to beat)")
    ap.add_argument("--candidate", required=True,
                    help="git ref for the candidate (the revision under test)")
    ap.add_argument("--rule", default=os.environ.get("RULE", "bland"),
                    help="pivot rule under test (default: bland)")
    ap.add_argument("--trials", type=int,
                    default=int(os.environ.get("TRIALS", "15")),
                    help="solver in-process --repeat count for timing")
    args = ap.parse_args()

    # Always refresh the corpus so it is reproducible and never stale.
    regenerate_splits()

    sys.exit(do_compare(args.baseline, args.candidate, args.rule, args.trials))


if __name__ == "__main__":
    main()
