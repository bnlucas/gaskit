# Using Cattri in Refactors

This guide is meant for agents adapting projects to use Cattri. It covers what Cattri does, how to wire it in, and how to migrate common patterns safely.

## What Cattri Provides
- One DSL (`cattri`) for both instance and class attributes
- Lazy or static defaults, optional coercion blocks, and `final: true` write-once semantics
- Visibility-aware method generation (public/protected/private), including write-only and read-only shapes
- Predicate helpers via `predicate: true`
- Introspection helpers when `with_cattri_introspection` is enabled

## Installation
1) Add the gem to the project (Gemfile):
```ruby
gem "cattri"
```
2) Bundle and ensure Ruby version matches the Gemfile constraints.
3) Require/integrate where needed:
```ruby
require "cattri"
```

## Defining Attributes
Include Cattri in classes (or modules):
```ruby
class User
  include Cattri

  # instance attribute, lazy default
  cattri :name, -> { "guest" }

  # instance attribute, write-once
  cattri :id, -> { SecureRandom.uuid }, final: true

  # class attribute, mutable
  cattri :config, -> { {} }, scope: :class

  # class attribute, write-once
  cattri :type, :standard, final: true, scope: :class
end
```

## Options Cheat Sheet
- `scope: :instance | :class` — default is `:instance`
- `final: true` — write-once; class-level finals are eager, instance finals are set once (default or explicit)
- `predicate: true` — adds `name?`
- `expose: :read | :write | :read_write | :none` — controls reader/writer generation
- `visibility: :public | :protected | :private` — applies to generated methods
- `&block` or `default:` value — block is lazy; static values are wrapped and duplicated unless immutable
- Custom ivar: `ivar: :@custom_name` if storage must differ

## Refactoring Playbook
1) Identify attribute helpers (`attr_reader`, `attr_accessor`, Rails `cattr_*`, custom singleton accessors).
2) Replace with `cattri` calls, preserving:
   - Scope (instance vs class)
   - Default behavior (static value vs lazy block)
   - Mutability (use `final: true` for constants; `expose:` for read/write shapes)
   - Visibility (set `visibility:` or rely on current context `public/protected/private`)
   - Predicate needs (`predicate: true`)
3) For class-level configuration objects, prefer lazy defaults: `cattri :config, -> { {} }, scope: :class`.
4) For IDs or tokens set in `initialize`, mark `final: true` so reassignment raises.
5) If existing code uses writer-only or reader-only, map to `expose: :write` or `:read`.
6) When refactoring modules that should confer attributes on includers, use `scope:` as needed; Cattri handles module deferral automatically.

## Access Patterns
```ruby
user = User.new
user.name          # reader
user.name = "Ann"  # writer (if exposed)
user.id            # write-once instance attribute

User.config        # class attribute reader
User.config = {}   # writer (if exposed)
User.type          # class final
```

## Introspection (opt-in)
```ruby
class User
  include Cattri
  with_cattri_introspection
  cattri :role, "guest"
end

User.attribute_defined?(:role) # => true
User.attribute_methods         # => { role: #<Set: {:role, :role=}> }
User.attribute_source(:role)   # => User
```

## Testing Checklist
- Verify visibility: writers/readers are defined where expected; write-only readers should be private/protected.
- Final semantics: reassignment of `final` attributes raises `Cattri::AttributeError`.
- Defaults: lazy defaults evaluate once and memoize; class-level finals are eager.
- Inheritance: subclass copies class attributes safely; instance attributes remain isolated per instance.
- Module inclusion: deferred attributes apply when modules are included/extended.

## Common Migrations
- Rails `class_attribute :foo, default: ...` → `cattri :foo, -> { ... }, scope: :class`
- `attr_reader :foo; def initialize; @foo = ... end` → `cattri :foo, -> { ... }` or keep initializer assignment; mark `final: true` if immutable
- Predicate helpers → `cattri :admin, false, predicate: true`
- Write-only (`attr_writer`) → `cattri :token, expose: :write`

Use this as a checklist when converting code to keep behavior and safety aligned with Cattri’s semantics.
