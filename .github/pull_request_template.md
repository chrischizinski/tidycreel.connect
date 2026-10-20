## Purpose
<!-- One-liner + linked issue -->

## Summary
- [ ] User-visible behavior unchanged OR documented in README/NEWS
- [ ] API changes? If yes: deprecation note + lifecycle tag added

## R Package Review (GitHub focus)
**Behavior**
- [ ] Messages via `cli`; errors via `rlang::abort()`
- [ ] Return type/class stable; attributes preserved
- [ ] No unexpected side effects (options/RNG/locale/wd); guarded by `withr`/`on.exit`

**API / Contracts**
- [ ] Signatures & defaults compatible (incl. `...`)
- [ ] S3/S4/R6 stable; methods registered
- [ ] Rcpp/C: exported symbols consistent; `.Call` args/types OK; PROTECT/UNPROTECT balanced

**Edge Cases**
- [ ] Handles length-0/1, NA/NaN/Inf/NULL, factors/UTF-8, `Date`/`POSIXct`+TZ
- [ ] Tidy-eval safe (`{{ }}`, quosures); explicit name repair
- [ ] Portable file paths; temp files via `tempfile()`

**Perf / Parallel**
- [ ] Avoid accidental copies; preallocate
- [ ] `data.table` by-ref (`:=`) intended; keys/index explicit
- [ ] Parallel portable (PSOCK on Windows); RNG streams controlled

**Tests**
- [ ] Added/updated tests for edge cases above
- [ ] Snapshot/printing tests stable; error classes asserted
- [ ] Plot snapshots via `vdiffr` if applicable

**Docs**
- [ ] roxygen updated (`@param/@return/@examples/@export`)
- [ ] README install instructions updated
- [ ] NEWS.md entry for user-visible changes
- [ ] pkgdown reference doesn’t break

**CI**
- [ ] `devtools::check()` ok
- [ ] GH Actions green (Linux/macOS/Windows)
- [ ] `lintr`/`styler` clean

## Notes
<!-- Gotchas, performance notes, follow-ups -->
