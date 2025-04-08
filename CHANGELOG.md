## [0.1.4] - 2025-04-08

### Added

- Error registration support in `Gaskit::Operation` via the `error` class method. This allows declaring symbolic exit keys with associated messages and optional codes.

  ```ruby
  class MyOperation < Gaskit::Operation
    error :unauthorized, 'User must be authorized', code: 401

    def call
      exit(:unauthorized)
    end
  end
  ```

- Structured `exit` and `error` payloads in `OperationResult#to_h`:
  - `:exit` is present when an operation exited early (via `exit(:key)`), containing:
    - `key`: the symbolic reason (e.g. `:unauthorized`)
    - `message`: a friendly message
    - `code`: optional numeric code if defined
  - `:error` is present for handled errors, containing:
    - `type`: class name of the error
    - `message`: error message
    - `backtrace`: full Ruby backtrace (if available)
  - `:meta` contains duration and context

- `OperationResult#to_json` for automatic JSON serialization of the result object.

### Changed

- `OperationResult#to_h` now returns:
  - `success`: boolean
  - `status`: one of `:success`, `:failure`, `:early_exit`
  - `value`: only present on success
  - `exit`: structured hash for early exits
  - `error`: structured hash for raised errors
  - `meta`: always includes `duration` and optionally includes `context`

## [0.1.3] - 2025-04-08

### Added
- `Gaskit::Repository` base class for service-layer data access patterns:
  - Prevents instantiation (`.new` raises `TypeError`)
  - Adds structured logging and execution time measurement via `.log_execution_time`
  - Supports assigning a model with `.model(ModelClass)`
  - Delegates common ActiveRecord-style methods (e.g., `find`, `where`, `create!`, etc.)
- Repository generator:  
  `rails generate gaskit:repository User`  
  Generates a file like `UserRepository` with `model User` already declared.

### Changed
- `Repository.model` now enforces that a model can only be set once. Attempting to redefine the model raises a `RuntimeError`.
- `Repository.logger` returns a class-scoped `Gaskit::Logger` for structured log formatting with optional context.
- Refactored `.log_execution_time` to use `Gaskit::Helpers.time_execution` internally for cleaner timing logic.

### Fixed
- Specs for `Gaskit::Repository` now use isolated, dynamically generated anonymous classes to avoid model assignment clashes across examples.
- Error messages in `.model` now include the class name for clarity (e.g., `UserRepository already has a model set`).

### Specs
- Full test coverage

## [0.1.2] - 2025-04-08

### Changed
- General cleanup and test coverage.

## [0.1.1] - 2025-04-08

### Added
- `Gaskit::Flow` and `Gaskit::FlowResult` for composing multi-step operation pipelines with full step tracking, duration timing, and input/output logging.
- Support for inline and class-based `Flow` definitions using `step` DSL.
- `step_input` and `compile_step_entry` helpers to track arguments and keyword arguments passed to each flow step.
- `Gaskit::ContractRegistry` with result class validation, contract registration, and fetching.
- `Gaskit::Configuration` with customizable:
    - `logger`, `log_level`, `log_formatter`, and `disable_logging`
    - dynamic `context` provider (e.g., for request or user metadata)
    - contract registration and access
- `Gaskit::OperationResult` class:
    - Unified result structure for all operations
    - Success/failure helpers, `#to_h` serialization, and human-readable `#inspect`
- `Gaskit::OperationExit` for early exits with symbolic keys and messages.

### Changed
- `Operation.result_class` now falls back to the superclass's contract when not explicitly set.
- `Operation.invoke` raises a clear `NotImplementedError` if no contract is defined.
- `Operation.call` and `call!` now log duration in a readable format (`"0.000123"`).
- Refined flow step result propagation:
    - Arrays are passed as positional args
    - Hashes as keyword args
    - Single values are normalized into `[value], {}`

### Fixed
- Resolved double-registration issues in test contracts by using randomized contract names in specs.
- Ensured each step’s inputs and outputs are correctly logged and serialized in `FlowResult#steps`.

### Specs
- Full test coverage added for:
    - `Gaskit::Operation` (contract handling, success/failure, early exits)
    - `Gaskit::ContractRegistry` (validation, fetch, override, registration errors)
    - `Gaskit::Configuration` (logger settings, contract management)
    - `Gaskit::OperationResult` and `OperationExit`
    - `Gaskit::Flow` and `FlowResult`, including multi-step execution and error propagation

---

## [0.1.0] - 2025-04-06

- Initial release
