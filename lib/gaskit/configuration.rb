# frozen_string_literal: true

require "cattri"
require "logger"

require_relative "hook_registry"
require_relative "stores/memory_store"
require_relative "stores/redis_store"

module Gaskit
  # Gaskit::Configuration holds global configuration for the Gaskit gem.
  #
  # It allows customization of behavior including:
  # - Debug mode and structured logging
  # - Custom loggers, levels, and formatters
  # - Global context injection
  # - Cache store configuration
  #
  # @example Configuring Gaskit
  #   Gaskit.config do |c|
  #     c.debug = true
  #     c.context_provider = -> { { request_id: SecureRandom.uuid } }
  #     c.cache_store :redis, connection: Redis.new
  #
  #     c.setup_logger(Logger.new($stdout), level: :info, formatter: Gaskit::Logger.formatter(:pretty))
  #   end
  class Configuration
    include Cattri

    cattri :enforce_cache_store, true
    cattri :debug, false, predicate: true
    cattri :disable_logging, false, predicate: true
    cattri :logger, -> { ::Logger.new($stdout) }
    # Store a callable; default returns a lambda that returns an empty hash.
    cattri :context_provider, -> { -> { {} } }

    # Initializes the configuration with defaults.
    #
    # Sets:
    # - enforce_cache_store: true
    # - debug: false
    # - disable_logging: false
    # - context_provider: -> { {} }
    # - cache_store: memory
    # - default logger: Logger.new($stdout)
    def initialize
      super
      @hook_registry = HookRegistry.new

      setup_logger(logger)
    end

    # Configures and installs the logger.
    #
    # @param custom_logger [::Logger, nil] A custom logger instance.
    # @param level [Symbol, Integer] Log level (e.g., :debug, Logger::WARN).
    # @param formatter [Proc, nil] Optional custom formatter.
    # @return [void]
    def setup_logger(custom_logger = nil, level: :debug, formatter: nil)
      self.logger = custom_logger || ::Logger.new($stdout)
      effective_formatter = formatter || logger&.formatter || Gaskit::Logger.formatter(:pretty)

      self.log_formatter = effective_formatter if effective_formatter.respond_to?(:call)
      self.log_level = level
    end

    # Sets the log level for the logger.
    #
    # @param level [Symbol, Integer] Symbol (e.g. :info) or constant (e.g. Logger::INFO).
    # @raise [NameError] If symbol does not map to a valid Logger constant.
    # @return [void]
    def log_level=(level)
      level = ::Logger.const_get(level.upcase) if level.is_a?(Symbol)
      logger.level = level
    end

    # Sets a custom log formatter.
    #
    # @param formatter [#call] A callable formatter accepting (severity, time, progname, message).
    # @raise [ArgumentError] If not a callable object.
    # @return [void]
    def log_formatter=(formatter)
      raise ArgumentError, "Formatter must be callable" unless formatter.respond_to?(:call)

      logger.formatter = formatter
    end

    # Sets the global context provider.
    #
    # This callable should return a Hash used in structured logs and flows.
    #
    # @param provider [#call] Proc/lambda that returns a context Hash.
    # @raise [ArgumentError] If not callable.
    # @return [void]
    def context_provider=(provider)
      raise ArgumentError, "Provider must be callable" unless provider.respond_to?(:call)

      cattri_variable_set(:context_provider, provider)
    end

    # Configures or returns the cache store.
    #
    # @param type [Symbol, nil] Optional type (:redis, :memory). If nil, returns current config.
    # @param options [Hash] Optional keyword args passed to the store class (e.g., `connection: Redis.new`).
    # @return [Hash] The configured store and options (e.g., `{ store: RedisStore, options: {...} }`).
    #
    # @example Configure Redis store
    #   config.cache_store :redis, connection: Redis.new
    #
    # @example Read current configuration
    #   config.cache_store
    def cache_store(type = nil, **options)
      type ||= :memory
      if type
        store_class = resolve_cache_store(type)
        @cache_store_config = { store: store_class, options: options }
      end

      @cache_store_config ||= { store: Gaskit::Stores::MemoryStore, options: {} } # rubocop:disable Naming/MemoizedInstanceVariableName
    end

    def register_cache_store(name, klass)
      Gaskit::Stores.register(name, klass)
    end

    def fetch_cache_store(name)
      Gaskit::Stores.fetch(name)
    end

    # @return [HookRegistry] The hook registry instance.
    def hooks
      @hook_registry
    end

    private

    # Resolves a cache store class from a symbolic identifier.
    #
    # @param type [Symbol] The type (e.g. :redis, :memory).
    # @return [Class<Gaskit::Stores::Base>] The resolved store class.
    # @raise [ArgumentError] If an unknown type is given.
    def resolve_cache_store(type)
      case type
      when :redis
        Gaskit::Stores::RedisStore
      when :memory
        Gaskit::Stores::MemoryStore
      else
        raise ArgumentError, "Unsupported cache_store type: #{type.inspect}"
      end
    end
  end
end
