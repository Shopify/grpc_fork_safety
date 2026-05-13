## [Unreleased]

- Add `disable!(reenable_in_children: false)` with explicit child re-enable control.
- Deprecate `keep_disabled!` in favor of `disable!(reenable_in_children: true)`.
- Ensure disable state can be intentionally preserved across double-fork flows until explicitly reenabled.

## [0.2.1] - 2024-07-31

- Fix `keep_disabled!`.

## [0.2.0] - 2024-07-31

- Make `keep_disabled!` and `reenable!` more usable, by not being noops when called out of order.

## [0.1.0] - 2024-07-24

- Initial release
