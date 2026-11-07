# Dependency advisories that cannot be fixed from this repository

`zip` 6.0.0 and 8.6.0 stay in the lockfile because the two crates that pull them
in depend on the 6.x and 8.x major lines, and neither line has a release with
the fixes. `cargo update` cannot cross the semver-incompatible major, and
`[patch.crates-io]` cannot substitute a version that does not satisfy the
dependent's requirement:

| Crate | Requires | Fix available |
|:--|:--|:--|
| `epub-builder` 0.8.3 | `zip = "6.0.0"` (6.x) | no newer `epub-builder` release exists; 6.0.0 is the only 6.x release |
| `dexvm` 0.2.1 | `zip = "8.6.0"` (8.x) | no newer `dexvm` release exists; 8.6.0 is the last 8.x release |

That leaves five Dependabot alerts open, all on `zip`:

- `GHSA-m665-v7pm-7grj` (critical, fixed in 9.0.5): parser differential on
  dual headers, leading to archive cloaking
- `GHSA-9hj8-73fh-9963` (high, 9.0.0): legacy Shrink/Reduce/Implode decoder DoS
- `GHSA-hjqx-j4rw-g7xv` (high, 9.0.0): arbitrary write outside the extraction
  directory via symlink targets in `ZipArchive::extract`
- `GHSA-q7v9-x93c-xqv3` (high, 9.0.0): unbounded symlink-target handling during
  extraction
- `GHSA-8hxf-qr8p-62x4` (medium, 9.0.0): AES entry HMAC bypass on premature EOF

## Why they are not reachable here

Every one of them needs an attacker-controlled archive on a vulnerable code
path. Neither crate reaches one:

- `dexvm` passes the Keiyoushi APK bytes to `contents_from_apk`
  (`context.rs:134`), which uses `ZipArchive` to read `classes*.dex` and the
  other non-directory entries. It never calls `extract`, so the symlink and
  path-traversal advisories do not apply, and it never uses `ZipStreamReader`,
  the reader at the centre of the parser-differential advisory; it reads the
  central directory, which is the authoritative side of that differential.
  `legacy-zip` is not enabled, so the Shrink/Reduce/Implode decoder is not
  compiled, and the reader supplies no password for an AES entry.
- `epub-builder` is used by `chapter_downloader.rs` through its `ZipLibrary`
  backend to *write* the EPUB it generates from downloaded pages. It only uses
  the zip writer; no archive is read through it.

The direct dependency is `zip = "9.0.5"`, so the code reading user-supplied CBZ
files and update packages already uses the patched parser. The lockfile resolves
9.0.5.

## What would change this

If either crate gains a reader path this repository does not control, or starts
using `extract`/`ZipStreamReader`, revisit. At that point the choices are to
vendor the two crates with `zip` bumped (7.3 MB, plus the patch to replay on each
upstream release), or to generate EPUB with `zip` directly and drop
`epub-builder` (about 205 lines in `chapter_downloader.rs`).
