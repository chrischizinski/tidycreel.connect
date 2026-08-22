# synthetic-boat-counts

**Fabricated data. Not a survey record, and not validated against anything.**

These counts exist for one reason: every real fixture shipped with the package
is a bank-only fishery (`sum(angler_boats) == 0` in `calamus-2016`), so the
boat-to-angler reconstruction path — `angler_boats` × mean party size, via
`tidycreel::derive_angler_count()` — is structurally unreachable end to end
(GH #130). Numbers made up to be non-zero, non-constant, and non-proportional
to the bank counts, so a test cannot pass by coincidence.

Use it to assert the **seam**: that boat counts survive the fetch, reach the
estimator, and change the answer. Never assert an estimate produced from this
file against a reference value. There is no reference value — the numbers are
invented, so any total computed from them is arithmetic, not validation. The
only validated end-to-end numbers in this repo are
`inst/extdata/calamus-2016/reference-outputs.csv`, in the tidycreel package.
