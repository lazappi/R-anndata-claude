#!/usr/bin/env bash
# The check that decides whether a ticket is done. Run from anywhere.
#
# Usage:
#   scripts/check.sh                          full check, stops at the first failing step:
#                                             air format, lintr, document, R CMD check, coverage
#   scripts/check.sh --quick [test files...]  air format, lintr on changed R files and
#                                             devtools::test() on the given test files (all if none)
set -euo pipefail

cd "$(dirname "$0")/.."
export _R_CHECK_SYSTEM_CLOCK_=false

step() { printf '\n==> %s\n' "$1"; }
fail() { printf '\nFAILED: %s\n' "$1" >&2; exit 1; }

doc_state() {
    find man NAMESPACE -type f -exec shasum {} + 2>/dev/null | sort
}

if [ "${1:-}" = "--quick" ]; then
    shift

    step "air format --check"
    air format --check . || fail "air format --check"

    step "lintr (changed R files)"
    changed=$({ git diff --name-only HEAD; git ls-files --others --exclude-standard; } | grep -E '\.[Rr]$' | sort -u || true)
    if [ -n "$changed" ]; then
        # shellcheck disable=SC2086
        Rscript -e 'pkgload::load_all(quiet = TRUE)
            files <- commandArgs(TRUE); files <- files[file.exists(files)]
            lints <- do.call(c, lapply(files, lintr::lint))
            if (length(lints)) { print(lints); quit(status = 1) }' $changed || fail "lintr"
    fi

    step "devtools::test()"
    filter=""
    for f in "$@"; do
        name=$(basename "$f")
        name=${name#test-}
        name=${name%.[Rr]}
        filter="${filter:+$filter|}$name"
    done
    if [ -n "$filter" ]; then
        Rscript -e 'devtools::test(filter = commandArgs(TRUE)[1], stop_on_failure = TRUE)' "$filter" || fail "devtools::test()"
    else
        Rscript -e 'devtools::test(stop_on_failure = TRUE)' || fail "devtools::test()"
    fi
    exit 0
fi

step "1/5 air format --check"
air format --check . || fail "air format --check"

step "2/5 lintr::lint_package()"
Rscript -e 'pkgload::load_all(quiet = TRUE); lints <- lintr::lint_package(); if (length(lints)) { print(lints); quit(status = 1) }' || fail "lintr::lint_package()"

step "3/5 devtools::document()"
before=$(doc_state)
Rscript -e 'devtools::document()' || fail "devtools::document()"
after=$(doc_state)
[ "$before" = "$after" ] || fail "devtools::document() changed man/ or NAMESPACE, commit the regenerated files"

step "4/5 devtools::check()"
Rscript -e 'devtools::check(error_on = "note")' || fail "devtools::check()"

step "5/5 covr::package_coverage() (report only)"
Rscript -e 'print(covr::package_coverage())' || fail "covr::package_coverage()"

printf '\nAll checks passed\n'
