#!/usr/bin/env python3
"""Convert a solver `.in` instance into CPLEX LP format.

The CPLEX LP format is read by both external oracles (glpsol --lp, gurobi_cl),
so a single converter feeds both. We emit a MAXIMIZE objective to match the
solver's semantics (max c^T x s.t. A x <= b, x >= 0), which was verified against
both oracles on the course's subject instance.

All variables are non-negative (x >= 0), matching the solver, so we do not emit a
bounds section (LP format defaults to [0, +inf)).
"""

import sys


def parse_in(text):
    """Parse the `.in` format into (n, m, c, b, A).

    Tokens are whitespace-separated and may span lines, but we follow the
    documented line structure: line1=n, line2=m, line3=c, line4=b, then m rows.
    Coefficients may be integers or `p/q` rationals (the generators emit ints,
    but we accept rationals for robustness against hand-written instances).
    """
    lines = [ln for ln in text.splitlines() if ln.strip() != ""]
    n = int(lines[0])
    m = int(lines[1])
    c = lines[2].split()
    b = lines[3].split()
    A = [lines[4 + i].split() for i in range(m)]
    assert len(c) == n, f"objective has {len(c)} coeffs, expected n={n}"
    assert len(b) == m, f"bounds has {len(b)} values, expected m={m}"
    for i, row in enumerate(A):
        assert len(row) == n, f"constraint {i} has {len(row)} coeffs, expected n={n}"
    return n, m, c, b, A


def _num(tok):
    """Return a coefficient token as an exact number.

    LP format does not accept `p/q`, so a rational is converted to a float.
    Integers stay ints to avoid any float rounding.
    """
    if "/" in tok:
        p, q = tok.split("/")
        return int(p) / int(q)
    return int(tok)


def _rhs(tok):
    """Render a right-hand-side value (may be negative, printed as-is)."""
    v = _num(tok)
    return repr(v) if isinstance(v, float) else str(v)


def _linexpr(coeffs):
    """Render `sum_j coeff_j * x_j` with signs folded into the operators.

    CPLEX LP format (as read by glpsol) rejects `+ -9 x2`; the sign must be a
    standalone operator: `- 9 x2`. Zero coefficients are dropped. If every
    coefficient is zero we emit `0 x0` so the expression is never empty.
    """
    parts = []
    for j, tok in enumerate(coeffs):
        v = _num(tok)
        if v == 0:
            continue
        op = "-" if v < 0 else "+"
        mag = -v if v < 0 else v
        mag = repr(mag) if isinstance(mag, float) else str(mag)
        parts.append(f"{op} {mag} x{j}")
    if not parts:
        return "0 x0"
    # Drop a leading "+ " for cleanliness; keep a leading "- ".
    expr = " ".join(parts)
    if expr.startswith("+ "):
        expr = expr[2:]
    return expr


def to_lp(text):
    n, m, c, b, A = parse_in(text)
    out = []
    out.append("\\ auto-generated from .in by to_lp.py")
    out.append("maximize")
    out.append(" obj: " + _linexpr(c))
    out.append("subject to")
    for i in range(m):
        out.append(f" c{i}: " + _linexpr(A[i]) + f" <= {_rhs(b[i])}")
    # x >= 0 is the LP-format default lower bound, so no bounds section needed.
    out.append("end")
    return "\n".join(out) + "\n"


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: to_lp.py <instance.in>   (writes LP to stdout)")
    with open(sys.argv[1]) as f:
        sys.stdout.write(to_lp(f.read()))


if __name__ == "__main__":
    main()
