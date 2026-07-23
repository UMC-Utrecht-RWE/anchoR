> The pluggable function (named by metadata's `constructor` column) that computes `window_start`/`window_end` for a batch of cross-joined population-metadata rows sharing that constructor name.

Resolved by name at runtime: `resolve_window_constructor()` looks for a function called `<constructor>_window` (lower-cased) first inside the anchoR package itself, then in a caller-supplied `constructor_env` (defaulting to the global environment). This is how a user-defined constructor, built with make_constructor() can sit alongside the built-in ones without editing the package.

Built-in constructors:
- GENERIC:  a fixed offset around one anchor date; the only constructor needed for [single-anchor](<Anchor Column (T0).md>) study variables.
- Pre-configured selection rules over the shared [Episode-Based Window Engine](<Episode-Based Window Engine.md>):
	- [IN_PRIOR_PREG](IN_PRIOR_PREG.md)
	- [SINCE_START_CURRENT_PREG](SINCE_START_CURRENT_PREG.md)
	- [ANYTIME_CURRENT_PREG](ANYTIME_CURRENT_PREG.md)
	- [OUTSIDE_ALL_PREG](OUTSIDE_ALL_PREG.md)
`apply_window_constructors()` runs one constructor per unique `constructor` value present in the metadata and row-binds the outputs, so a single anchoring run can freely mix `GENERIC` variables with episode-based variables in the same metadata table.

