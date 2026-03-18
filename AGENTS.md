# Castkit Usage

Use Castkit for DTOs and validation.

## When to use
- Defining structured data transfer objects (DTOs) for service boundaries, API payloads, or internal commands.
- Validating incoming data without building a full model (use `Castkit::Contract`).
- Serialization/deserialization of nested hashes with explicit types.
- Enforcing strict schemas and catching unknown keys early.
- Reusable typed data definitions shared across multiple services or layers.

## Must use
- Any new DTO or input validation layer should be implemented with Castkit `DataObject` or `Contract`.
- Avoid ad-hoc Hash validation or hand-rolled coercion when Castkit can represent the schema.
- Use Castkit types and validators instead of custom casting logic unless a custom type is required.

## How to use
- Add a DTO by inheriting `Castkit::DataObject` and declaring attributes:
  ```ruby
  class UserDto < Castkit::DataObject
    string :id
    string :email, required: false
    array :roles, of: :string
  end
  ```
- Prefer `Castkit::Contract` for request/command validation:
  ```ruby
  UserContract = Castkit::Contract.build(:user) do
    string :id
    string :email, required: false
  end
  ```
- Use strict mode defaults unless a relaxed schema is explicitly required:
  ```ruby
  class LooseDto < Castkit::DataObject
    strict false
    warn_on_unknown true
  end
  ```
- Configure types/plugins in an initializer:
  ```ruby
  Castkit.configure do |config|
    config.register_type(:money, MyApp::Types::Money)
    config.register_plugin(:timestamps, MyApp::Plugins::Timestamps)
  end
  ```
- Use CLI generators for consistent scaffolding:
  ```bash
  castkit generate dataobject User name:string
  castkit generate contract UserInput id:string
  ```

# Cattri Usage

Use Cattri to define class-level and instance-level attributes with one DSL, with safe inheritance, visibility control, and optional write-once semantics.

## When Cattri must be used

- Any class-level configuration or metadata that needs to be inherited safely by subclasses.
- Any attribute that must be write-once (`final: true`) or initialized lazily.
- Any attribute that needs explicit visibility/exposure control (public/protected/private, read/write/none).
- Any shared config in non-Rails code where `class_attribute` is unavailable or too invasive.

If none of the above apply and a plain `attr_reader`/`attr_accessor` is sufficient, prefer the built-in Ruby helpers.

## How to use Cattri

1) Add the gem (`gem "cattri"`) and `include Cattri` in the class or module.
2) Define attributes with `cattri`.
3) Use `scope: :class` for class-level attributes; omit for instance-level (default).
4) Use `final: true` for write-once attributes.
5) Use `expose:` and `visibility:` to control method visibility and read/write access.

### Minimal example

```ruby
class User
  include Cattri

  cattri :type, :standard, final: true, scope: :class
  cattri :id, -> { SecureRandom.uuid }, final: true
  cattri :name, "anonymous"
  cattri :admin, false, predicate: true
end
```

### Exposure and visibility

```ruby
class Profile
  include Cattri

  cattri :token, "secret", expose: :read
  cattri :attempts, 0, expose: :write
  cattri :internal_flag, true, expose: :none

  private
  cattri :audit_tag
end
```

### Optional introspection

Enable introspection only when you need attribute metadata:

```ruby
User.with_cattri_introspection
User.attributes
User.attribute(:type)
User.attribute_methods
```
