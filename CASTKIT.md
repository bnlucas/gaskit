# Using Castkit in Projects

This guide is for agents integrating or refactoring code to use Castkit. It summarizes what Castkit provides, how to wire it in, and patterns to migrate safely.

## What Castkit Provides
- Declarative DTO/contract DSLs with type coercion and validation
- Attribute options for access control, defaults, aliases, nesting, and unwrapped fields
- Serialization/deserialization with nil/blank filtering and unknown-key handling
- Plugin system and configurable global defaults
- Built-in primitive types and easy custom type registration

## Installation
1) Add the gem:
```ruby
gem "castkit"
```
2) Bundle with Ruby >= 2.7.0.
3) Require it where needed:
```ruby
require "castkit"
```

## Defining Data Objects
```ruby
class UserDto < Castkit::DataObject
  string  :id
  string  :name
  boolean :admin, default: false
  array   :tags, of: :string, required: false
end

user = UserDto.new(id: "123", name: "Ada")
user.to_h   # => { id: "123", name: "Ada", admin: false, tags: nil }
user.to_json
```

## Defining Contracts
```ruby
UserContract = Castkit::Contract.build(:user) do
  string :id
  string :email, required: false
end

UserContract.validate!(id: "123")          # passes
UserContract.validate!(id: 123)            # raises Castkit::ContractError
```

## Attribute Options (Data Objects)
- `required:` Boolean (default: true)
- `default:` static value or lambda (lambda is lazy)
- `access:` `[:read, :write]`, or subsets for readonly/writeonly
- `ignore_nil:` skip nils in serialization
- `ignore_blank:` skip empty strings/arrays/hashes
- `ignore:` skip entirely (no serialize/deserialize)
- `aliases:` array of alternate keys on input
- `of:` element type for arrays (required for arrays)
- `unwrapped:` true to flatten nested DTO fields; optional `prefix:`
- `validator:` Proc for custom validation

## Access Control
```ruby
string :email, access: [:read]    # read-only
string :password, access: [:write] # write-only
```

## Grouped Declarations
```ruby
required do
  string :id
end

optional do
  integer :age
end

readonly do
  string :token
end
```

## Nested and Unwrapped DTOs
```ruby
class Profile < Castkit::DataObject
  string :bio, required: false
end

class UserDto < Castkit::DataObject
  dataobject :profile, Profile
  unwrapped  :profile, Profile, prefix: "profile"
end
```

## Serialization Options
- `root` (class method): set to wrap output in a root key
- `ignore_nil` (class method): skip nils globally
- `allow_unknown` (class method): include unknown inputs in output

## Global Configuration
```ruby
Castkit.configure do |config|
  config.enforce_typing = true
  config.enforce_attribute_access = true
  config.enforce_array_options = true
  config.strict_by_default = true
  config.register_type(:uuid, MyUuidType, aliases: [:guid])
  config.register_plugin(:custom, CustomPlugin)
  config.default_plugins = [:custom]
end
```

## Gaskit Defaults
When used through Gaskit, Castkit is configured with strict defaults and custom types:
- `enforce_typing`, `enforce_attribute_access`, `enforce_array_options`, and `strict_by_default` are enabled.
- `:any` and `:symbol` types are registered (aliases: `:object`, `:sym`).

## Plugins
- Register via `Castkit.configure { |c| c.register_plugin(:name, Mod) }`.
- Enable on a DTO with `enable_plugins :name`.
- Plugins can define `setup!(klass)` to run activation logic.

## Testing Checklist
- Deserialization: required vs optional handling, aliases, unwrapped prefixes, root wrapping.
- Serialization: ignore_nil/ignore_blank, access control, unknown attributes when allowed.
- Type casting: arrays enforce `of:`, custom validators raise as expected.
- Contracts: validate/validate! paths, strict vs allow_unknown/warn_on_unknown.
- Plugins: activation includes modules and runs setup!.

## Common Migrations
- Replace ad-hoc attribute handling with Castkit DSL (`string`, `integer`, etc.) and options.
- Move manual JSON/hash serialization to `to_h`/`to_json`.
- Replace custom validation layers with `Castkit::Contract` where appropriate.
- Register custom types instead of inline coercion logic.

## Gotchas
- Arrays require `of:` when `enforce_array_options` is true.
- `access: [:write]` skips serialization and read access; `[:read]` skips deserialization.
- Unwrapped attributes need `unwrapped: true`; use `prefix:` to avoid key collisions.
- Strict mode (default) raises on unknown keys; set `allow_unknown` or `strict false` per class if needed.
