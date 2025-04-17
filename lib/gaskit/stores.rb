# frozen_string_literal: true

require_relative "stores/redis_store"
require_relative "stores/memory_store"

module Gaskit
  module Stores
    # Internal registry for Gaskit cache stores.
    #
    # Supports registration of custom cache backends and lookup by name.
    #
    # By default, two stores are registered:
    # - `:memory` → {Gaskit::Stores::MemoryStore}
    # - `:redis` → {Gaskit::Stores::RedisStore}
    #
    # Custom stores must inherit from {Gaskit::Stores::Base} and implement:
    #   - `initialize(namespace, logger:, **options)`
    #   - `read_all!(*keys)` → Hash
    #
    # @example
    #   class MyStore < Gaskit::Stores::Base
    #     def initialize(namespace, logger:, **options); end
    #     def read_all!(*keys); end
    #   end
    #
    #   Gaskit::Stores.register(:mystore, MyStore)
    #   klass = Gaskit::Stores.fetch(:mystore)
    #
    # Used internally by `Gaskit.configuration.cache_store` and `Gaskit::Core::Cacheable`.
    @stores = {
      memory: Gaskit::Stores::MemoryStore,
      redis: Gaskit::Stores::RedisStore
    }

    class << self
      # Registers a custom cache store class under a given name.
      #
      # The class must inherit from {Gaskit::Stores::Base}.
      #
      # @param name [Symbol, String] The identifier to associate with the store (e.g., `:redis`)
      # @param klass [Class] The class implementing the store, inheriting from {Gaskit::Stores::Base}
      #
      # @raise [Gaskit::Error] if the class does not inherit from {Gaskit::Stores::Base}
      # @return [void]
      def register(name, klass)
        raise Gaskit::Error, "Stores must inherit from Gaskit::Stores::Base" unless klass < Gaskit::Stores::Base

        @stores[name.to_sym] = klass
      end

      # Fetches a cache store class by name.
      #
      # @param name [Symbol, String] The identifier of the store to fetch
      # @return [Class] The registered cache store class
      #
      # @raise [ArgumentError] if the store is not found and
      #   `Gaskit.configuration.enforce_cache_store` is true
      #
      # @note If the store is missing and enforcement is disabled,
      #   this will log a warning and fall back to `:memory`
      def fetch(name)
        name = name.to_sym
        @stores.fetch(name) do
          raise ArgumentError, "Unknown store #{name}" if Gaskit.configuration.enforce_cache_store

          warn "Store #{name} not found, falling back to :memory"
          return @stores[:memory]
        end
      end
    end
  end
end
