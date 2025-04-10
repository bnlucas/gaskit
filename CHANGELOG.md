# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.1] - 2025-04-10

### Added

- Hook system with support for `before`, `after`, and `around` hooks.
- `HookRegistry` for globally registered hooks, similar to `ContractRegistry`.
- `Hookable` concern, enabling hooks for `Operation`, `Flow`, and `Repository`.
- `use_hooks` to enable hooks in a class with optional tag filtering.
- Support for class-level inline hooks via `.before`, `.after`, `.around`.
- `execute_with_hooks` helper for wrapped hook execution.
- Specs for `HookRegistry`, `Hookable`, and integration with `Operation`.

## [0.1.0] - 2025-04-08

- Initial release
