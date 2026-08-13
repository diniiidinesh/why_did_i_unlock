# DOC_UPKEEP — how to keep the docs current cheaply (for Claude Code)

> A guide for future Claude sessions on updating this repo's docs without burning
> context. Written 2026-07-21 after a session where docs were updated many times.

## The doc map and who owns what (don't duplicate — point instead)

| Doc | Owns | Update when |
|---|---|---|
| `CLAUDE.md` | Operational ground truth, working rules, **§11/§12 strategic decisions** | State/architecture/decision changes. It's the tiebreaker if docs disagree. |
| `docs/ARCHITECTURE.md` | Engine topology, native components, event flows, plugin gotchas | The native/overlay/engine layer changes. |
| `docs/PRD.md` | Product requirements, current-vs-planned feature state | A feature ships or scope shifts. |
| `docs/BACKLOG.md` | Tactical deferred work (features/fixes/ideas) + priorities | Something is deferred, shipped (mark `[DONE date]`), or reprioritized. |
| `docs/erd/` | Archived sprint plans (ERD + IA + task breakdown), one dated file per sprint; also dated design-token notes (e.g. Beacon) | May be updated as implementation proceeds or scope changes — append a dated entry to that file's "Update log" section (top of file) describing what changed and why, rather than silently rewriting the body. A new sprint still gets its own new dated file. |
| `README.md` | Front door + doc index | New doc added, or status headline changes. |
| `docs/DATA_MODEL.md` | On-device schema (ERD) + invariants | The `intent_log`/`unlock_log`/preset schema changes. |
| `docs/TEST_PLAN.md` | Automated + manual on-device test tracker | A new behaviour area is touched, or a manual case is run — mark Status/Evidence in place. |
| `docs/USER_INTERVIEWS.md` | Interview questions tied to open product decisions | A decision gets deferred pending user feedback rather than guessed at — add the question under the relevant topic heading; mark `[ASKED]` with a summary once actually put to people. |
| `docs/PLAY_SUBMISSION.md` | Play listing/review prep — FGS justification, Data Safety, closed-test checklist | A submission gate is done, a new dependency changes what Data Safety must say, or Google responds to a real review (log it in §6). |
| `docs/PRIVACY_POLICY.md` | Privacy policy source of truth | The policy text changes — keep the hosted copy (`beacon-site` repo / `docs/site/privacy.html` mirror) in sync in the same change. |
| `docs/SETUP.md` | Dev-environment bring-up (toolchain, device) | Setup steps or toolchain floor change. |
| `docs/debug/` | Dated session logs **and RCAs** from real on-device investigations | New investigation closed or a fix needs a durable "how we found it" record (prefer one dated file per incident cluster; link from BACKLOG/ARCHITECTURE, don't duplicate the full write-up elsewhere) |
| `docs/archive/` | Superseded historical docs, reference only | Never — if it needs updating, it's not archived, move it back. |
| Claude Code local memory | Same-machine convenience only — **does NOT sync across machines** | Keep as pointers to the git-tracked docs, not a second copy. |

Rule: each fact lives in **one** doc; others link to it. Strategic decisions =
CLAUDE.md §11/§12 only. Don't restate them in BACKLOG/PRD. The **what-each-doc-is**
descriptions live in README's doc map (the front door); the table above owns only
the *update trigger* ("Update when") — don't grow it back into a second copy of
README's descriptions. CLAUDE.md §6 points here rather than re-listing the docs.

## Before editing docs: sync to latest `main` first

**Always `git fetch origin main && git merge origin/main` (or rebase) onto your
working branch before touching `CLAUDE.md`, `README.md`, `docs/BACKLOG.md`, or
`docs/PLAY_SUBMISSION.md`.** These files get edited by whichever session/tool
happens to be active — Claude Code sessions, Cursor sessions, sometimes in
parallel — and a checkout that predates someone else's doc fix will silently
*revert* that fix the moment it commits its own version of the same file,
even with no merge conflict (git sees it as a legitimate edit, not damage).
This actually happened 2026-07-29 (see `BACKLOG.md`'s doc-drift note): a PR
built from a stale branch reverted 4 files' worth of corrections made three
days earlier. A 10-second sync at the start of a doc-editing session is cheap
insurance against re-litigating "wait, didn't we already fix this?" later.

## Token-cheap update procedure

1. **Don't re-read a whole file to change one line.** Use `Grep` for the exact
   phrase (e.g. `grep -n "version: 0" CLAUDE.md`), then `Edit` with a tight
   `old_string`. Only `Read` a section (`offset`/`limit`) when you truly need
   surrounding context.
2. **Batch doc edits at the END of a work chunk**, not after every code change.
   One "update all docs" pass beats ten small ones.
3. **Mark, don't delete.** When a backlog item ships, change its tag to
   `[DONE <date>]` in place — cheaper than restructuring, and preserves history
   of the decision.
4. **Prefer appending a dated note** over rewriting a section, when the section
   is long (e.g. CLAUDE.md §2 uses "Post-vX note" blocks rather than rewrites).
5. **Do NOT hand-maintain `Last updated:` dates or `rev N` counters** — `git log`
   is the authoritative timeline and never rots. The one human-facing exception is
   the **README status headline** (the at-a-glance "where is this project" line);
   everywhere else, let git track when.
6. **Version + tag** on merge of a meaningful batch: bump `pubspec.yaml`
   `version:`, update the matching note in CLAUDE.md §2, `git tag -a vX.Y.Z`.
7. **When a feature/fix branch merges to `main`, grep for stale merge-state
   language in the same pass** — this rots silently otherwise. Run something like
   `grep -rln "not yet merged\|on branch\|on this branch\|<old-branch-name>" -- '*.md'`
   (skip `docs/erd/` and `docs/debug/` — those are point-in-time archives *by
   design*, see the doc-map row above, and are meant to still say what was true
   when they were written). Fix every real hit that now claims something is
   unmerged/in-progress when it actually shipped. Found 2026-07-27: `CLAUDE.md`,
   `README.md`, `docs/BACKLOG.md`, `docs/PLAY_SUBMISSION.md`, `docs/PRD.md`, and
   `docs/TEST_PLAN.md` were all still describing merged work as "branch, not yet
   merged" days after the merge — nobody had grepped for it, each doc had just been
   edited in isolation. A repo-wide grep at merge time is cheaper than a fresh
   session re-deriving "wait, is this actually live?" from git log.

## When context is running low (like end of a long thread)

Priority order — do the earlier ones first, they're what a fresh thread needs:
1. **Commit + push the code** (the verified work — never lose it).
2. **BACKLOG.md**: add a `TOP OF NEXT THREAD` block at the header with the
   immediate next tasks, so the next session starts there without re-deriving.
3. **CLAUDE.md §2 current-state**: one dated line on what shipped.
4. ARCHITECTURE/PRD only if the change was architectural/product-facing.

Skip web searches, extra builds, and full-file rewrites when context is tight —
capture the *problem + direction* in BACKLOG and defer the deep work to the
next thread with a clean context window.
