# Upstreaming plan - fork > yuuki-kagura/rakuyomi

Plan of match for porting fork-authored work to the new upstream
(`upstream` = yuuki-kagura/rakuyomi, 1.43.8 / `2bbbc40` as of 2026-11-22).
Constraint from the maintainer: small PRs, independent, mergeable in any order.

Base for every PR: a fresh branch off `upstream/main`. Source of content: fork `main`.
Never copy policy content (BaconDroid links, self-update URLs, release bumps, CHANGELOG).

## Waves

### Wave 1 - shipped (PRs opened 2026-11-17)

PRs live on the dedicated fork `BaconDroid/rakuyomi-upstream` (fork of the new upstream;
created because `BaconDroid/rakuyomi` forks the old upstream and GitHub rejects
cross-repo PRs from it). Remote name in this repo: `upstream-fork`.

| PR | Upstream PR | Branch | Commit | Diff | Validation |
|----|-------------|--------|--------|------|------------|
| 7  | [#5](https://github.com/yuuki-kagura/rakuyomi/pull/5) | `pr/p1-realpath-history`    | `dd0b62d` | +8 -1 | luacheck 0/0 |
| 10 | [#6](https://github.com/yuuki-kagura/rakuyomi/pull/6) | `pr/p1-cbz-html-guard`      | `b35cc3b` | +127 -6 | cargo test chapter_downloader 5 pass |
| 1  | [#7](https://github.com/yuuki-kagura/rakuyomi/pull/7) | `pr/p1-cookie-bot-hardening`| `2b11240` | +36 -12 (stripped: the two added test files and the store_test assertion revert; sources unchanged) | bun test 33 pass, tsc clean |
| 8a | [#8](https://github.com/yuuki-kagura/rakuyomi/pull/8) | `pr/p1a-backend-liveness`   | `2c6e69b` | +295 -53 | luacheck 0/0 |
| 8b | [#9](https://github.com/yuuki-kagura/rakuyomi/pull/9) | `pr/p1b-backend-recovery`   | `f7972b6` | +471 -202 (stripped variant) | luacheck 0/0, cargo test shared lib 306 pass, cargo fmt clean |

PR descriptions: see conversation of 2026-11-17 ("P1 descriptions"), pattern: state the
delta only, never re-explain the maintainer's own architecture to them.

Split of old PR8 (2026-11-17, user request): two independent PRs instead of one +937.
`pr/p1a-backend-liveness` (platform layer, keeps upstream's isAlive API upgraded to
is_alive via a 1-line Backend running() patch) and `pr/p1b-backend-recovery` (protocol:
Backend restart/replay/cancel, LoadingDialog, Job+spec, Rust cleanup). Both stand alone
on upstream/main: B degrades gracefully without A (`is_alive == nil -> running() true`),
A is complete without B (isAlive callers patched). Coupling: both edit Backend.lua near
running(); merging the second needs a trivial "take the later one" resolution there.
The superseded branch `pr/p1-dead-backend-gaps` (e11b74d) is kept unmerged as reference
(safe delete refuses; remove by hand when the two new branches are pushed).

Stripped variant of 8b (user request 2026-11-17): `67a047b` removed the added tests
(Job_spec, orphan-sweep test, install_update mod tests) and the added inline comments,
keeping only the doc comments AGENTS.md requires (KDoc/EmmyLua). +679 -> +507.
Upstream's own chapter_storage test and its helpers are preserved. Cost: the sweep,
the plugin-dir gate and the cancel/replay rules carry no regression tests in this
variant - the reference branch e11b74d keeps them if the maintainer asks.

### Wave 2 - medium security/edge-case fixes (P2)

| PR | Scope | Diff | Independent |
|----|-------|------|-------------|
| 1b | hono/zod patched bumps (cookie-bot) | +6 -6 | yes (lockfile may conflict with PR1, not semantic) |
| 2  | pared 0.4.0 (drops GHSA-vgmh-mqm4-8j88 git branch) | +24 -23 | yes |
| 3  | UTF-16 U+FFFD trailing byte (supersedes upstream's reverted 6c78036) | +39 -18 | yes |
| 6  | backend security: session ID validation, HTTPS-or-loopback redirect/OAuth, no username logging | +165 -30 | yes |

### Wave 3 - features (P3, maintainer buy-in) - final plan 2026-11-18

GATE: wave 3 starts only after wave 1 is merged upstream. Lean policy applies
(no new tests, comments limited to AGENTS.md-required doc comments), one commit
per PR, bodies delta-only with no coverage claims, review on the final scoped
diff, oracle loop to two consecutive clean passes.

| PR | Scope | Diff (reviewed, lean) |
|----|-------|-----------------------|
| 12 | source settings hot reload - commit 98d16ad alone (test commit 273f4fb dropped) | +78 -0 |
| 14 | tracker push-on-link + fix as one (99d501d + 1030491; the 7 tests inside 99d501d are stripped under the lean policy; 23 inline comments stripped) | ~+180 -15 |
| 11 | reading-status FEATURE PR - backend (module ~100, usecases, models, migration renumbered after upstream's latest, status listing re-derived against upstream's current 20-query structure) + UI (Backend API block, filter button, StatusPickerDialog, handler, Library title bar carrying the fork's order with TitleBarButtonHeight alignment fixes) | ~+740 -70 (+~200 generated sqlx caches) |

PR11 narrowing decided 2026-11-18 (oracle simplify/step-back):
- Sort by reading status is DEFERRED (Settings option + db.rs sort branch) unless the
  build-time SQL trace shows it inseparable from the filter; documented as follow-up.
- The MangaSearchResults context entry is DEFERRED (-10 lines); the library entry point
  suffices for v1.
- LibraryView: default carries the fork's title bar order and alignment fixes (user
  decision 2026-11-18); fallback to a minimal native filter-button insertion (~-90
  lines) if the KOReader slot contract blocks the port.
- Deferred items are documented as follow-ups in the PR body, not shipped behavior.

PR11 risk mitigation (added): before any validation, enumerate every affected query
variant and verify status-filter behavior, bindings and generated sqlx metadata
against a freshly migrated database. One reproducible `cargo sqlx prepare` run, its
configuration recorded in the PR validation notes; cache changes diffed against the
final queries. No separate cache PR.

Total wave 3: ~+1000 reviewed lines across three independent PRs (12, 14, 11).
manga/routes.rs hunk-splits between 14 (tracker) and 11 (status) - distinct hunks,
mergeable in any order.

## Excluded (fork-policy / decided)

- epub-builder switch: keeping upstream's git-fork approach (user decision 2026-11-17).
  Consequence: EPUB EBADF/EOCD fixes (a27af1d + 2335267, +58 -17) are deferred - they
  depend on the fork's `set_zip_comment` patch and need adapting to upstream's epub-builder.
- titlebar standardization: deferred pending KOReader slot-contract check (user decision).
- clippy -D warnings: dropped (old-upstream origin, not fork work).
- wasmi 2.0 / syn 3.x manifest drift: no demonstrated upstream need.
- Fork-policy items never to PR: BaconDroid URLs, self-update target, releases 1.44.4-1.45.4,
  CHANGELOG, Android build removal, build.yml restructure, issue-template fork links.

## Old-upstream commits the new upstream lacks (case-by-case, user decides)

99d501d tracking push (in PR14) - 4ca2937 update temp file next to plugin dir (folded into PR8's
install_update.rs) - a214f47 XHTML epub - d115492 Keiyoushi - 942c4ec rquickjs pin -
backend/tree.tx deletion. Excluded by decision: 7b59e49 clippy -D.

## Oracle review outcomes (2026-11-17)

- PR8: fixed Android release URL back to `tachibana-shin/rakuyomi_bridge` (porting error),
  documented Android's unconfirmed stop in `android_platform.lua`. "Job started in the
  Trapper subprocess cannot be cancelled from the parent" is pre-existing upstream/fork
  behavior (as_backend_worker exists in upstream's 8be3a90 too), NOT a regression of this
  commit - candidate follow-up issue. Temp-file relocation stays folded into install_update.rs
  (coupled with the scoped cleanup); note it in the PR body. No Lua spec exists for the
  recovery protocol; note that in the PR body as follow-up.
- PR1: ready. Follow-up ideas (not fork content): `deleteWebhook` or error-level log when
  WEBHOOK_SECRET is unset, error-level (not throttled warn) signal.
- PR7: fixed - raw `file == self.path` short-circuit before realpath fallbacks.
- PR10 (`62715c0`): commit message reworded - the "count retries" half does not apply on
  this base (no downloader retry loop; the `attempts: 1` convention is pre-existing
  upstream, our added site follows it). Added BOM/whitespace test (4 pass). Follow-up
  noted: a downloader-level regression test (HTML response never lands in the CBZ).
- `chapters/findNextChapter_spec.lua`: 6 pass / 1 fail identically on pristine
  upstream/main - pre-existing upstream failure, do not attribute to our PRs.

## Implementation notes

- Working tree of the main repo sits on `fix/epub-zip-comment-ebadf` - always build from refs.
- Squash commit 6fbb432 re-includes ~+1190 lines of listing machinery already counted in the
  refactor; extract, never copy the squash wholesale (PR7 done this way).
- Upstream's 6c78036 + revert eedf8e9 nets to zero - no resolution needed there.
- Where fork rewrote files upstream also touched (Backend.lua, generic_unix_platform.lua,
  util.lua, install_update.rs, chapter_storage.rs), resolution is "take fork": the fork
  contains a cherry-pick of upstream's 8be3a90 plus the follow-ups.
- Wave-1 worktrees: ../rakuyomi-wt1, wt7, wt8, wt10 (remove after PRs are opened).

## Next steps

1. PR10 branch lands (lane) - then push the 4 wave-1 branches and open the PRs
   (order: 8, 10, 1, 7); confirm push rights/target with the user first.
2. Remove the wave-1 worktrees after the PRs are open.
3. Waves 2-4: build on demand, same rules (fresh branch off upstream/main, one commit,
   policy hunks stripped, validation before proposing).
Fork-fidelity recheck 2026-11-18 (all PRs vs fork main, diff per file):
- PR1 and the PR8a platform files: byte-identical to the fork (android URL + stop
  comment are the only deliberate deltas). Backend.lua of 8a keeps upstream's 8be3a90
  socket-error block, which 8b replaces - the 8a/8b merge conflict region is that block,
  resolution "take 8b".
- PR7: the raw-equality short-circuit is a deliberate, oracle-driven superset of the
  fork's condition (same result when resolution succeeds; skips filesystem work on
  exact equality).
- PR8b: the reading-status API block that had leaked into its Backend.lua was removed
  (36 lines); Backend.lua, LoadingDialog.lua and Job.lua are now byte-identical to the
  fork. install_update/chapter_storage differ only by the stripped tests, inline
  comments and the policy URL.
- PR10: the inlined markup detection was a real drift - the port now carries the fork's
  full looks_like_html (BOM, leading `<!-- ... -->` comments incl. truncated ones,
  512-byte tag-marker scan) + a comment-prefixed test (5 pass).
- Wave-3 sources unchanged (fork main moved only for docs commits).

Oracle loop, final (2026-11-18): every wave-1 PR reached two consecutive clean passes
(pass counts: #5 x4, #6 x6, #7 x5, #8a x7, #9 x8). Fixes taken along the way:
nil-file guard on #5; full fork-faithful looks_like_html port + 5 discriminating tests
(case-insensitivity, truncated comment, 512-byte window) on #6; DO batching/ordering/
sanitization + registerBotCommands regression tests on #7; _meta completion + body
accuracy (reaped-on-replace, kill(pid,0) fallbacks qualified) on #8; running() shim
falling back to this base's isAlive until 8a lands + honest validation section on #9.
PR bodies now carry their known-limitations and validation sections; the companion
branch pr/p1-dead-backend-gaps (pushed to rakuyomi-upstream) holds the tests stripped
from #9.

Stripped to minimal diffs (2026-11-18, user decision): #6 lost its 9 predicate tests
and the private-fn doc/inline comments (upstream has no tests in chapter_downloader);
#7 lost the two added test files and the store_test assertion change (sources were
already comment-free). The detector/logic code itself is unchanged from the
oracle-validated content; the tests live on in the fork and in branch history
(6624450 / 6be34e6).

Simplify/step-back pass (2026-11-18): all five PRs ship as-is code-wise. PR bodies
reframed: #6 body now carries the commit message's detection details; #7 body makes no
coverage claim; #8/#9 intros restate full independence (each correct standalone,
mergeable in any order) with only a one-line rebase note on the shared running()
line; no test offer anywhere (lean per user decision). Kept: #9's isAlive shim, #8's spawn pcall,
no further splitting. Wave 1 is closed; waves 2-3 on hold for the go. Upstream has since merged PR #5; the remaining wave-1 branches must be rebased onto the new upstream tip before further review.

Backports to the fork (2026-11-19): the review fixes made on the upstream PRs were
brought back to fork main in four commits grouped by source PR - "bring back the
review fixes from the upstream recovery PR" (storage counter, socket-error liveness
gate, dismiss_callback transfer, confirmation-open suspension, shm allocation order,
restored docblock summaries), "accept form feed as an HTML tag boundary",
"guard and short-circuit the ReadHistory path comparison", and the cookie-bot README
(argv-free curl, WEBHOOK_SECRET charset). No tests added, mirroring the upstream
PRs. Validation on the fork: luacheck 0/0 over 84 files, cargo test -p shared --lib
361 pass.


Upstream sync and fork backport (2026-11-22): upstream merged PR #5 as
`b3303ad`, byte-identical to `dd0b62d`. Upstream then advanced to `2bbbc40`
(1.43.8) with `80ee2ad` (broken source-list/file tolerance) and related
follow-ups. That commit was ported to fork `main` as `f5781dd`, retaining the
fork's recovery protocol and existing policy changes; the port adds broken-file
skipping, restart-failure capping, spawn-failure handling, and the corresponding
source-list updates. Validation: luacheck 0/0 over 84 files, cargo fmt clean,
`cargo test -p shared --lib` 365 passed / 0 failed / 7 ignored.

Plan impact: rebase the remaining wave-1 PRs onto upstream `2bbbc40`; PR #9
needs a manual reconciliation with upstream's new Backend restart cap and
spawn handling. PR12 must be re-derived against the rewritten `source_manager.rs`;
its hot-reload delta cannot be applied from the old `98d16ad` base. The source-list
URL/default-entry carve-outs are already present upstream and should be removed
from any future PR scope. Wave 3 remains gated on wave 1 acceptance.

## Current gate (2026-11-22)

Phase 3 is the next planned implementation wave after Phase 1 is completely
merged upstream. Until every Phase-1 PR is merged or explicitly closed, do not
start Phase-3 branches, rebase its feature commits, or open its PRs. Once that
gate clears, begin with PR12 on the then-current `upstream/main`, then PR14 and
PR11 as independent branches; re-check their file ownership against the final
upstream tip before splitting or porting anything.

No tracking issue is created yet: the merge gate is the current dependency, and
the existing plan remains the source of truth while upstream reviews the open
Phase-1 PRs. Create or update a Phase-3 issue only when the gate clears and the
three final diffs have been regenerated.

