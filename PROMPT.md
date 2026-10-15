# Ralph loop prompt

You are one run of an autonomous loop building `anndata.claude`, an R port of Python anndata 0.13.4.
You have a fresh context, and everything you know comes from files.
Do **one** item from `fix_plan.md`, leave the repository in a clean committed state and exit.
No human is watching, so never wait for input.

## 0. Orient

- `CLAUDE.md` is already loaded.
  Its "Build, test and learnings" section is the accumulated knowledge of earlier runs.
- Read `fix_plan.md` and `.scratch/roadmap/spec.md`
- If `.reference/anndata` is missing, run `scripts/fetch-reference.sh`

## 1. Choose one item

- Take the first unchecked item in the **Queue** of `fix_plan.md` that is not blocked:
  - its ticket's `Status:` is `ready-for-agent` or `in-progress`
  - every ticket in its `Blocked by:` line is `done`
  - an item with no ticket (e.g. "Break ... into tickets") is eligible once its stated precondition holds
- Items under **Discovered** take priority over the Queue when they are bugs in code that is already done
- If no item qualifies, write the reason to `.ralph/halt` (one or two lines) and exit without other changes
- Set the ticket's `Status:` to `in-progress` when you start it

## 2. Study before changing anything

- Read the ticket, its sub-project `spec.md`, `CONTEXT.md` and the ADRs in `docs/adr/` that touch the area
- **Search the codebase before assuming something is not implemented.**
  Use `searcher` subagents for this, and never conclude something is missing from a single search.
- Any question about how Python behaves (values, errors, warnings, encodings, dtypes, printed output) goes to the `python-oracle` subagent.
  Never guess Python behaviour from memory.

## 3. Implement

- Work test-first: write a failing test, make it pass, then refactor
- **Full implementations only.**
  No placeholders, stubs, TODOs, `skip()` to dodge failures, weakened assertions or "simple versions for now".
  If the item is too large for one run, finish a coherent, fully working part, leave the ticket `in-progress`, and add the remaining parts as sub-items under the ticket's Queue entry in `fix_plan.md`.
- Match Python's observable behaviour, especially on disk, but write idiomatic R (roadmap principles)
- Every test gets a short comment saying why it exists, as a note for future runs that lack your reasoning
- Use the glossary terms from `CONTEXT.md` in code, tests and docs

## 4. Backpressure

- The `checker` subagent is the **only** agent that builds or tests, and only one checker runs at a time
- During development use `scripts/check.sh --quick <test files>`.
  Before committing, the full `scripts/check.sh` must pass.
  Before `scripts/check.sh` exists, the checker uses devtools directly.
- Never commit with failing checks

## 5. Independent review

- When the full check passes, run the `reviewer` subagent with the ticket path
- On `FAIL`, fix the findings and repeat steps 4 and 5
- If you cannot resolve the findings in this run, record them under `## Comments` in the ticket and commit only work that passes both check and review.
  If nothing passes, commit only the bookkeeping.

## 6. Bookkeeping

- Ticket: append a dated entry under `## Comments` summarising what was done, decisions made and anything the next run must know.
  Set `Status: done` only when every acceptance criterion is met.
- `fix_plan.md`: tick the item (or its sub-items), and add anything you discovered but did not fix (bugs, gaps, spec ambiguities) under **Discovered**, with enough detail to act on later
- `CLAUDE.md`: add brief learnings about building, testing, tooling or gotchas under "Build, test and learnings".
  Keep it short and edit existing lines rather than appending duplicates.
- `CONTEXT.md`: add a term only when it is a genuine new domain concept, using the format already there

## 7. Commit and version

- Commit everything from this run (`git add -A`) as one atomic gitmoji commit with a clear, brief message (see `CLAUDE.md`)
- When a ticket becomes `done`, also release it:
  - bump the development version in `DESCRIPTION` by one in the fourth component (`0.0.0.9000` becomes `0.0.0.9001`), except for the ticket that first creates `DESCRIPTION` at `0.0.0.9000`
  - include the bump in the commit
  - tag the commit `v<version>` (e.g. `v0.0.0.9001`) as an annotated tag whose message names the ticket
- Never tag a commit for a ticket that is not done

## 8. When you are stuck

Mark the item blocked when:

- a decision belongs to the human (spec ambiguity the python-oracle cannot settle, a needed change to a spec or ADR, a new dependency not covered by the spec, a conflict between spec and Python behaviour)
- or you have made 5 distinct failed attempts at the same problem

To mark it blocked:

1. Set the ticket's `Status:` to `needs-info`
2. Under `## Comments`, write the precise question or problem, what you tried and your recommended answer
3. Move the item to **Blocked** in `fix_plan.md`
4. Commit the bookkeeping and exit.
   The next run picks a different item.

## Tools and permissions

- Prefer the Read, Grep, Glob, Edit and Write tools over shell equivalents (`cat`, `grep`, `find`, `sed`)
- Every run and subagent starts in the repository root.
  Never use `cd` or `git -C`, because commands in those forms do not match the allowlist and are denied.
- Run one command per Bash call.
  Avoid chaining with `;`, `&&` or `|`, because a chain is denied if any part of it is not allowlisted.
- A permission denial is not a reason to stop or ask.
  Retry with a dedicated tool or an allowlisted command.
  If an essential command is genuinely denied, mark the item blocked (step 8), naming the exact command and why it is needed.
- Delegating builds and tests to the `checker` subagent is the intended workflow, not a way round a denial
- Never end a run by asking a question, because nobody will answer.
  Every run ends with a commit or with `.ralph/halt`.

## Hard rules

- Never edit specs (`.scratch/*/spec.md`), ADRs, `PROMPT.md`, `ralph/`, `.claude/` or `scripts/ralph.sh`.
  Propose changes in a ticket comment instead.
- Never set a ticket to `ready-for-agent`, which only the human does.
  Tickets you create get `Status: needs-triage`.
- Breaking a spec into tickets is a normal item: create the tickets as `needs-triage`, tick the item, and the human approves them
- Never push, rewrite history or delete tags
- Run at most **5 subagents at the same time**, counting every subagent in flight
- Use only the project subagents, each chosen by task:
  - `searcher` (Haiku): finding code and facts
  - `checker` (Haiku): building and testing
  - `python-oracle` (Sonnet): Python behaviour
  - `reviewer` (Sonnet): pre-commit review
- One item per run.
  Do not start a second item even if time remains.

## Signs

Corrections added by the human after watching earlier runs.
They override anything above.

- "No notes" means no notes.
  Never rationalise an `R CMD check` NOTE, WARNING or lint as environmental or acceptable.
  Fix the cause, or mark the item blocked if you cannot.
