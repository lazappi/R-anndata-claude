#!/usr/bin/env bash
# The check that decides whether a ticket is done. Run from anywhere.
#
# Usage:
#   scripts/check.sh                          full check, stops at the first failing step:
#                                             air format, lintr, document, R CMD check
#   scripts/check.sh --coverage               covr::package_coverage() report (not part of the
#                                             full check, because it runs the tests a second time)
#   scripts/check.sh --quick [test files...]  air format, lintr on changed R files and
#                                             devtools::test() on the given test files (all if none)
set -euo pipefail

cd "$(dirname "$0")/.."
export _R_CHECK_SYSTEM_CLOCK_=false
# testthat runs 2 parallel workers by default, use more on machines that have them
export TESTTHAT_CPUS="${TESTTHAT_CPUS:-4}"

# Fail with a clear message instead of running past the 10-minute limit of an
# agent's shell command (a hanging test, or a suite that has become too slow).
# The whole process group is killed, so no R or Python process is left behind.
if [ -z "${ANNDATA_CHECK_TIMED:-}" ] && [ "${1:-}" != "--coverage" ]; then
    export ANNDATA_CHECK_TIMED=1
    exec perl -e '
        my $limit = shift;
        my $pid = fork();
        if (!$pid) { setpgrp(0, 0); exec @ARGV or die "exec: $!"; }
        # R CMD check starts its tests in their own process groups, so collect
        # every descendant, not just the process group
        sub tree {
            my @all = (shift);
            for (my $i = 0; $i < @all; $i++) {
                push @all, grep { /\d/ } split /\s+/, `pgrep -P $all[$i]`;
            }
            return @all;
        }
        $SIG{ALRM} = sub {
            my @procs = tree($pid);
            kill "TERM", -$pid, @procs; sleep 3; kill "KILL", -$pid, @procs, tree($pid);
            print STDERR "\nFAILED: timed out after $limit seconds: a test is hanging, or the suite is too slow\n";
            exit 124;
        };
        alarm $limit;
        waitpid($pid, 0);
        exit($? & 127 ? 1 : $? >> 8);
    ' "${ANNDATA_CHECK_TIMEOUT:-570}" "$0" "$@"
fi

step() { printf '\n==> %s\n' "$1"; }
fail() { printf '\nFAILED: %s\n' "$1" >&2; exit 1; }

doc_state() {
    find man NAMESPACE -type f -exec shasum {} + 2>/dev/null | sort
}

if [ "${1:-}" = "--coverage" ]; then
    step "covr::package_coverage()"
    Rscript -e 'print(covr::package_coverage())' || fail "covr::package_coverage()"
    exit 0
fi

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

step "1/4 air format --check"
air format --check . || fail "air format --check"

step "2/4 lintr::lint_package()"
Rscript -e 'pkgload::load_all(quiet = TRUE); lints <- lintr::lint_package(); if (length(lints)) { print(lints); quit(status = 1) }' || fail "lintr::lint_package()"

step "3/4 devtools::document()"
before=$(doc_state)
Rscript -e 'devtools::document()' || fail "devtools::document()"
after=$(doc_state)
[ "$before" = "$after" ] || fail "devtools::document() changed man/ or NAMESPACE, commit the regenerated files"

step "4/4 devtools::check()"
Rscript -e 'devtools::check(error_on = "note")' || fail "devtools::check()"

printf '\nAll checks passed\n'
