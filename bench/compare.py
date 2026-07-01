#!/usr/bin/env python3
"""Compare two benchmark reports and decide: real, significant improvement?

This is the *verdict* stage of the optimization loop. Given a BASELINE report and
a CANDIDATE report (both produced by run_bench.py on the SAME instance set), it:

  1. CORRECTNESS: if the candidate is incorrect on any instance, it is rejected
     outright, regardless of speed. (The baseline is assumed already-correct.)

  2. FITNESS: computes the geometric mean of per-instance speed ratios
     baseline_time / candidate_time. A geomean > 1 means the candidate is faster
     on average. The geometric mean is the correct summary for normalized ratios
     (Fleming & Wallace; SIGPLAN checklist "inappropriate summary statistics").

  3. SIGNIFICANCE: a bootstrap 95% confidence interval over the per-instance log
     ratios. We only call an improvement "significant" if the entire CI lies above
     1.0 (i.e. we are confident the geomean speedup is real, not measurement
     noise). This is the guard against "treating noise as signal" -- the failure
     mode that would let an automated loop accept junk changes.

  4. PIVOTS: reports the geomean pivot ratio too. Pivots are deterministic, so a
     pivot-count change is noise-free evidence; if time improved but pivots did
     not, the improvement is in per-pivot cost (and vice-versa). Surfaced, never
     hidden, so per-pivot regressions (e.g. rational blow-up) can't sneak through.

`compare()` returns a verdict dict (`accepted` is the headline); `format_verdict()`
renders it. Both are imported by evaluate.py -- this module has no CLI of its own.

Bootstrap uses a fixed seed so the verdict is reproducible run-to-run given the
same reports.
"""

import math

import numpy as np

# We use the per-instance MINIMUM time as the point estimate (least perturbed by
# external interference for a deterministic CPU-bound task; see run_bench.py).
POINT = "time_min"

BOOTSTRAP_RESAMPLES = 10000
CI = 0.95
SEED = 12345


def _geomean(xs):
    return math.exp(sum(math.log(x) for x in xs) / len(xs))


def compare(baseline, candidate):
    b_idx = {r["instance"]: r for r in baseline["results"]}
    c_idx = {r["instance"]: r for r in candidate["results"]}
    common = sorted(set(b_idx) & set(c_idx))
    if not common:
        raise RuntimeError("baseline and candidate share no instances")

    # --- correctness gate --------------------------------------------------
    incorrect = [name for name in common if not c_idx[name]["correct"]]
    candidate_correct = (len(incorrect) == 0) and candidate["all_correct"]

    # --- per-instance ratios ----------------------------------------------
    time_ratios = []      # baseline / candidate  (>1 == candidate faster)
    pivot_ratios = []
    per_instance = []
    for name in common:
        bt = b_idx[name][POINT]
        ct = c_idx[name][POINT]
        tr = bt / ct
        time_ratios.append(tr)

        bp = b_idx[name]["pivots"]
        cp = c_idx[name]["pivots"]
        pr = (bp / cp) if (bp and cp) else None
        if pr is not None:
            pivot_ratios.append(pr)

        per_instance.append({
            "instance": name,
            "baseline_time": bt,
            "candidate_time": ct,
            "time_ratio": tr,
            "baseline_pivots": bp,
            "candidate_pivots": cp,
            "correct": c_idx[name]["correct"],
        })

    time_geomean = _geomean(time_ratios)
    pivot_geomean = _geomean(pivot_ratios) if pivot_ratios else None

    # --- bootstrap CI on the geomean of time ratios -----------------------
    # Resample the per-instance log-ratios with replacement; the geomean of a
    # resample is exp(mean of its logs). One vectorized draw of shape
    # (resamples, n) does all BOOTSTRAP_RESAMPLES at once.
    rng = np.random.default_rng(SEED)
    log_ratios = np.log(time_ratios)
    resamples = rng.choice(log_ratios, size=(BOOTSTRAP_RESAMPLES, len(log_ratios)),
                           replace=True)
    geomeans = np.exp(resamples.mean(axis=1))
    lo, hi = np.quantile(geomeans, [(1 - CI) / 2, 1 - (1 - CI) / 2])
    lo, hi = float(lo), float(hi)

    significant_speedup = candidate_correct and lo > 1.0
    significant_regression = hi < 1.0

    return {
        "candidate_correct": candidate_correct,
        "incorrect_instances": incorrect,
        "n_instances": len(common),
        "time_geomean": time_geomean,
        "time_ci_low": lo,
        "time_ci_high": hi,
        "pivot_geomean": pivot_geomean,
        "significant_speedup": significant_speedup,
        "significant_regression": significant_regression,
        "accepted": significant_speedup,
        "per_instance": per_instance,
    }


def format_verdict(v, baseline_label, candidate_label):
    lines = []
    lines.append(f"Baseline : {baseline_label}")
    lines.append(f"Candidate: {candidate_label}")
    lines.append(f"Instances: {v['n_instances']}")
    lines.append("")
    if not v["candidate_correct"]:
        lines.append("CORRECTNESS: FAILED")
        lines.append("  incorrect on: " + ", ".join(v["incorrect_instances"]))
        lines.append("")
        lines.append("VERDICT: REJECTED (incorrect)")
        return "\n".join(lines)

    lines.append("CORRECTNESS: passed (matches GLPK+Gurobi on all instances)")
    lines.append("")
    pct = (v["time_geomean"] - 1) * 100
    lines.append(f"Time geomean speedup : {v['time_geomean']:.4f}x "
                 f"({pct:+.2f}%)")
    lines.append(f"  95% bootstrap CI   : [{v['time_ci_low']:.4f}, "
                 f"{v['time_ci_high']:.4f}]")
    if v["pivot_geomean"] is not None:
        ppct = (v["pivot_geomean"] - 1) * 100
        lines.append(f"Pivot geomean ratio  : {v['pivot_geomean']:.4f}x "
                     f"({ppct:+.2f}% fewer pivots)")
    lines.append("")

    # Worst and best individual instances (never summarize away the spread).
    by_ratio = sorted(v["per_instance"], key=lambda r: r["time_ratio"])
    worst = by_ratio[0]
    best = by_ratio[-1]
    lines.append(f"Best  instance: {best['instance']} "
                 f"{best['time_ratio']:.3f}x")
    lines.append(f"Worst instance: {worst['instance']} "
                 f"{worst['time_ratio']:.3f}x")
    lines.append("")

    if v["accepted"]:
        lines.append("VERDICT: ACCEPTED "
                     "(correct and significantly faster: CI entirely above 1.0)")
    elif v["significant_regression"]:
        lines.append("VERDICT: REJECTED "
                     "(significant regression: CI entirely below 1.0)")
    else:
        lines.append("VERDICT: REJECTED "
                     "(no significant improvement: CI includes 1.0)")
    return "\n".join(lines)
