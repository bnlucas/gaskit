# Gaskit

Gaskit is a flexible, pluggable, and structured operations framework for Ruby applications. It provides a consistent way to implement application logic using service objects, query objects, flows, and contracts — with robust support for early exits, structured logging, duration tracking, and failure handling.

## ✨ Features

- ✅ `Operation`, `Service`, and `Query` classes
- 🔀 Customizable result and early exit contracts via explicit `input_contract` / `output_contract`
- 🧱 Composable multi-step flows using `Flow` DSL
- 🧪 Built-in error declarations and early exits via `exit(:key)`
- ⏱ Integrated duration tracking and structured logging
- 🪝 Hook system for before/after/around instrumentation and auditing

## 📦 Installation

Add this line to your application's Gemfile:

```ruby
gem 'gaskit'
```

And then execute:

```bash
$ bundle install
```

Or install it yourself as:

```bash
$ gem install gaskit
```

## 🔧 Configuration

You can configure Gaskit via an initializer:

```ruby
Gaskit.configure do |config|
  config.context_provider = -> { { request_id: RequestStore.store[:request_id] } }
  config.setup_logger(Logger.new($stdout), formatter: Gaskit::Logger.formatter(:pretty))
end
```

## 🚀 Usage

### Basic Operation (No Contracts)

```ruby
class Ping < Gaskit::Operation
  def call
    "pong"
  end
end

result = Ping.call
result.value # => "pong"
```

`Operation.call` always returns a `Gaskit::OperationResult` wrapper.

### Define an Operation

```ruby
class MyOp < Gaskit::Operation
  output_contract do
    string :status
  end

  def call(user_id:)
    user = User.find_by(id: user_id)
    exit(:not_found, "User not found") unless user
    
    logger.info("Found user id=#{user_id}")
    { status: "ok" }
  end
end
```

### Handle Result

```ruby
result = MyOp.call(user_id: 42)

if result.success?
  puts "Found user: #{result.value}"
elsif result.early_exit?
  puts "Early exit: #{result.to_h[:exit]}"
else
  puts "Failure: #{result.to_h[:error]}"
end
```

### Define Errors

```ruby
class AuthOp < Gaskit::Operation
  error :unauthorized, "Not allowed", code: "AUTH-001"

  def call
    exit(:unauthorized)
  end
end
```

### Composing Flows

```ruby
class CheckoutFlow < Gaskit::Flow
  step AddToCart
  step ApplyDiscount
  step FinalizeOrder
end

result = CheckoutFlow.call(user_id: 123)
```

## 🪝 Hooks

Use `use_hooks` to activate instrumentation:

```ruby
class HookedOp < Gaskit::Operation
  use_hooks :audit

  before do |op|
    op.logger.info("Starting operation")
  end

  after do |op, result:, error:|
    op.logger.info("Finished with result=#{result.inspect} error=#{error.inspect}")
  end

  def call
    "hello"
  end
end
```

Register global hooks via:

```ruby
Gaskit.hooks.register(:before, :audit) { |op| puts "Before: #{op.class}" }
```

## 📂 Contracts

Gaskit uses Castkit for input/output validation at the operation boundary.
Input contracts run before any hooks. Output contracts run after a successful call
and before after hooks, so after hooks observe the final `OperationResult`.

### Input contracts with DTOs

```ruby
class UserInput < Castkit::DataObject
  string :user_id
  integer :limit, required: false
end

class FindUser < Gaskit::Operation
  input_contract UserInput

  def call(payload:)
    payload.user_id
  end
end
```

### Output contracts with DTOs

```ruby
class UserOutput < Castkit::DataObject
  string :name
  string :role
end

class LoadUser < Gaskit::Operation
  output_contract UserOutput

  def call(user_id:)
    { name: "user-#{user_id}", role: "admin" }
  end
end

result = LoadUser.call(user_id: 42)
result.value # => #<UserOutput ...>
```

### Input/Output validation with Castkit

Optionally validate inputs and outputs using Castkit contracts or DTOs:

```ruby
class ValidateOp < Gaskit::Operation
  input_contract do
    string :user_id
    integer :limit, required: false
  end

  output_contract do
    string :status
    hash :meta, required: false
  end

  def call(user_id:, limit: 10)
    { status: "ok", meta: { limit: limit.to_i } }
  end
end
```

`input_contract` and `output_contract` accept either a Castkit contract class, a Castkit data object, or a DSL block. Validation runs before executing `#call` (inputs) and after a successful call (outputs). Failures raise `Castkit::ContractError` (returned as a failure result for `.call`, raised for `.call!`). Input payloads are normalized (`payload:` hash, then kwargs, then a single Hash arg, else `{ args: [...] }`). Outputs are validated directly when hashes, otherwise wrapped as `{ value: result }` and unwrapped after casting.

### Calling convention

- If you call with kwargs (including `payload:`), the casted payload is passed as keyword args when it is a symbol-keyed Hash; otherwise it is passed as `payload:`.
- If you call with positional args, the casted payload is passed as a single positional argument.

### Failure behavior

- `.call` returns a failure `OperationResult` for contract errors or raised exceptions.
- `.call!` raises on contract errors and StandardError exceptions from `#call`.
- `OperationExit` raised via `exit(:key, ...)` always returns an early-exit `OperationResult` for both `.call` and `.call!`.

### Castkit defaults

Gaskit configures Castkit with strict defaults (`enforce_typing`, `enforce_attribute_access`, `enforce_array_options`, `strict_by_default`) and registers `:any`/`:symbol` types (aliases `:object` and `:sym`).

### Cache stores

Gaskit ships with `Gaskit::Stores::MemoryStore` and `Gaskit::Stores::RedisStore`. Configure globally via:

```ruby
Gaskit.configure do |config|
  config.cache_store :redis, connection: Redis.new
end
```

Use `Gaskit::Stores.register(:name, Klass)` for custom stores. For cacheable classes, you can disable caching with `cache_store :disabled`, and `config.enforce_cache_store` controls whether missing stores raise.

## 🧱 Repositories

```ruby
class UserRepository < Gaskit::Repository
  model User

  rls_scope do |context|
    model.where(tenant_id: context[:tenant_id])
  end

  def find_by_name_or_slug(name, profile_slug)
    where(name: name).or(where(profile_slug: profile_slug))
  end
end

users = UserRepository.with_context(tenant_id: current_user.tenant_id).where(active: true)
user = UserRepository.find_by_name_or_slug("User", "user123")
```

## 📈 Logging

Gaskit includes a flexible logger with support for structured JSON or pretty logs:

```ruby
logger = Gaskit::Logger.new(self.class)
logger.info("Started process", context: { user_id: 1 })
```

## Planned Features

- Caching Flow operations to provide replaying and resume on failure.

## 🤝 Contributing

Bug reports and pull requests are welcome! Feel free to fork, extend, and share improvements.

## 📜 License

This gem is licensed under the [MIT License](LICENSE).

---

Made with ❤️ by bnlucas
