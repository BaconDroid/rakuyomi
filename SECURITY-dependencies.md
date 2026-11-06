# Dependency advisories that cannot be fixed from this repository

`zip` 6.0.0 and 8.6.0 stay in the lockfile because the two crates that pull them
in pin an exact version, so neither `cargo update` nor `[patch.crates-io]` can
move them:

| Crate | Requires | Fix available |
|:--|:--|:--|
| `epub-builder` 0.8.3 | `zip = "6.0.0"` (exact) | no newer `epub-builder` release exists |
| `dexvm` 0.2.1 | `zip = "8.6.0"` (exact) | no newer `dexvm` release exists |

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

Every one of them needs an attacker-controlled archive as input, and neither
crate is given one:

- `dexvm` opens archives at `context.rs:134` only to read `classes*.dex` from a
  Keiyoushi APK that the user installs from a source they configured. It never
  calls `extract`, so the symlink and path-traversal advisories do not apply,
  and it reads entry names rather than trusting the central directory.
- `epub-builder` is used by `chapter_downloader.rs` to *write* the EPUB it
  generates from downloaded pages. No archive is read through it.

The direct dependency moved to `zip = "9.0.5"`, so the code reading
user-supplied CBZ files and update packages already uses the patched parser.

## What would change this

If a source ever feeds a `zip`-parsed archive it did not produce, or if
`epub-builder`/`dexvm` gain a reader path, revisit. At that point the choices are
to vendor the two crates with `zip` bumped (7.3 MB, plus the patch to replay on
each upstream release), or to generate EPUB with `zip` directly and drop
`epub-builder` (about 205 lines in `chapter_downloader.rs`).
