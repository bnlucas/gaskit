# Gaskit

Gaskit is a flexible, pluggable, and structured operations framework for Ruby and Rails applications. It provides a consistent way to implement application logic using service objects, query objects, flows, and contracts — with robust support for early exits, structured logging, duration tracking, and failure handling.

## ✨ Features

- ✅ `Operation`, `Service`, and `Query` classes
- 🔀 Customizable result and early exit contracts via `use_contract`
- 🧱 Composable multi-step flows using `Flow` DSL
- 🧪 Built-in error declarations and early exits via `exit(:key)`
- ⏱ Integrated duration tracking and structured logging
- 🧰 Generators for Rails to scaffold operations, services, queries, flows, and repositories
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

### Define an Operation

```ruby
class MyOp < Gaskit::Operation
  use_contract :service

  def call(user_id:)
    user = User.find_by(id: user_id)
    exit(:not_found, "User not found") unless user
    
    logger.info("Found user id=#{user_id}")
    user
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
  use_contract :service
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

## 🧪 Generators

```bash
# Generate an operation
rails generate gaskit:operation CreateUser

# Generate a query
rails generate gaskit:query FetchUsers

# Generate a service
rails generate gaskit:service RegisterAccount

# Generate a flow
rails generate gaskit:flow Checkout AddToCart ApplyDiscount FinalizeOrder

# Generate a repository
rails generate gaskit:repository User
```

## 📂 Contracts

You can define contracts using registered result types:

```ruby
class MyResult < Gaskit::OperationResult; end

Gaskit.contracts.register(:custom, MyResult)

class CustomOp < Gaskit::Operation
  use_contract :custom
end
```

Or override just part of the contract:

```ruby
class CustomResult < Gaskit::OperationResult; end

class PartialContractOp < Gaskit::Operation
  use_contract :service, result: CustomResult
end
```

## 🧱 Repositories

```ruby
class UserRepository < Gaskit::Repository
  model User

  def find_by_name_or_slug(name, profile_slug)
    where(name: name).or(where(profile_slug: profile_slug))
  end
end

users = UserRepository.where(active: true)
user = UserRepository.find_by_name_or_slug("User", "user123")
```

## 📈 Logging

Gaskit includes a flexible logger with support for structured JSON or pretty logs:

```ruby
logger = Gaskit::Logger.new(self.class)
logger.info("Started process", context: { user_id: 1 })
```

## 🤝 Contributing

Bug reports and pull requests are welcome! Feel free to fork, extend, and share improvements.

## 📜 License

This gem is licensed under the [MIT License](LICENSE).

---

Made with ❤️ by bnlucas
