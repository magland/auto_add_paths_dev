#!/usr/bin/env bash
# Compare two path lists produced by auto_add_paths.
#
# Usage: eval.sh <ground_truth.txt> <candidate.txt>
#
# Normalizes both files (trim, strip trailing slashes, sort -u) and prints:
#   - matched paths
#   - missing from candidate (false negatives)
#   - extra in candidate (false positives)
#   - precision / recall / F1
set -euo pipefail

if [ $# -ne 2 ]; then
    echo "usage: $0 <ground_truth.txt> <candidate.txt>" >&2
    exit 2
fi

gt="$1"
cand="$2"

norm() {
    # strip CR, trim whitespace, drop empty lines and comments,
    # strip trailing slashes, sort unique
    sed -e 's/\r$//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
        -e '/^$/d' -e '/^#/d' -e 's:/*$::' "$1" | sort -u
}

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

norm "$gt"   > "$tmpdir/gt"
norm "$cand" > "$tmpdir/cand"

comm -12 "$tmpdir/gt" "$tmpdir/cand" > "$tmpdir/match"
comm -23 "$tmpdir/gt" "$tmpdir/cand" > "$tmpdir/missing"    # in gt, not in cand
comm -13 "$tmpdir/gt" "$tmpdir/cand" > "$tmpdir/extra"      # in cand, not in gt

n_match=$(wc -l < "$tmpdir/match")
n_miss=$(wc -l < "$tmpdir/missing")
n_extra=$(wc -l < "$tmpdir/extra")
n_gt=$(wc -l < "$tmpdir/gt")
n_cand=$(wc -l < "$tmpdir/cand")

echo "=== matched ($n_match) ==="
cat "$tmpdir/match" || true
echo
echo "=== missing from candidate ($n_miss) ==="
cat "$tmpdir/missing" || true
echo
echo "=== extra in candidate ($n_extra) ==="
cat "$tmpdir/extra" || true
echo

prec="0"
rec="0"
f1="0"
if [ "$n_cand" -gt 0 ]; then
    prec=$(awk -v m="$n_match" -v c="$n_cand" 'BEGIN{printf "%.3f", m/c}')
fi
if [ "$n_gt" -gt 0 ]; then
    rec=$(awk -v m="$n_match" -v g="$n_gt" 'BEGIN{printf "%.3f", m/g}')
fi
f1=$(awk -v p="$prec" -v r="$rec" 'BEGIN{
    if (p+r == 0) { print "0.000" } else { printf "%.3f", 2*p*r/(p+r) }
}')

echo "=== summary ==="
printf "ground-truth paths : %d\n" "$n_gt"
printf "candidate paths    : %d\n" "$n_cand"
printf "matched            : %d\n" "$n_match"
printf "missing            : %d\n" "$n_miss"
printf "extra              : %d\n" "$n_extra"
printf "precision          : %s\n" "$prec"
printf "recall             : %s\n" "$rec"
printf "F1                 : %s\n" "$f1"
