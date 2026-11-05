# Reading status - propose upstream when a canonical repo exists

Reading status (Unread / Reading / Completed / Paused / Dropped, per manga, plus a
library filter and a picker) is merged on `main` via #24. It is a fork-only
feature and belongs upstream too, but **there is no upstream to send it to**:
`tachibana-shin/rakuyomi` returns 404 since 2026 and no community continuation
has taken over. Revisit when one appears.

## Build the branch from the archived history, not from `main`

The squash on `main` also carries this fork's titlebar work
(`TitleBarButtonHeight`, the `[3]`/`[4]` slot layout, bottom-line styling),
because the feature was developed on top of it. A PR containing a titlebar
refactor would be rejected or argued over.

`archive/reading-status-pre-rebase` still has the feature as separate commits:

```sh
git fetch origin archive/reading-status-pre-rebase
git switch -c upstream/reading-status <their-main>
git cherry-pick f08ee85 39c6f14 91aca99 5674de6 bfb98ed 47dfbd4 20fd33a \
                8e74c2e f19e1cd f8a2194 f1196f1 1367810 8c7dd6e
```

| Commit | Scope |
|:--|:--|
| `f08ee85` | migration + model structs |
| `39c6f14` | database functions |
| `91aca99` | use cases |
| `5674de6` | HTTP routes |
| `bfb98ed` | status picker dialog + handler |
| `47dfbd4` | `Backend.lua` API functions |
| `20fd33a` | context-menu entries |
| `8e74c2e` | multi-select library filter |
| `f19e1cd`, `f8a2194`, `f1196f1`, `8c7dd6e` | forward-only default, shared listing body, tests |

Backend commits are self-contained. The Lua ones assume the plugin's existing
structure, so check them against their `main` before picking.

## Things that will bite

- `archive/reading-status-pre-rebase` does **not** contain upstream v1.44.x: it
  branched from `11f672b`, before this fork synced. Cherry-picking onto their
  current `main` is what closes the gap; do not merge the archive branch.
- The migration `backend/shared/migrations/20260902231711_create_reading_statuses.sql`
  is SQLite: `STRICT`, `AUTOINCREMENT`, `INSERT OR IGNORE`. Rename it if their
  migration numbering moved.
- `.sqlx` cache entries are committed here; regenerate them for their query set.
- Reading status adds two `LibrarySortingMode` variants (`ReadingStatusAsc`,
  `ReadingStatusDesc`) and splits `order_by_clause` into `order_by_list` +
  a prefixing `order_by_clause`, so a status heading can be kept when the user
  picks another sort. Port that shape rather than the plain match.
- If their code grew a reading-status feature by then, compare before porting.

## After the upstream PR

Nothing changes here: this fork keeps its `main` and the feature as it is.
