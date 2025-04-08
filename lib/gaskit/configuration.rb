# frozen_string_literal: true

require "logger"

module Gaskit
  # Gaskit::Configuration holds global configuration for the Gaskit gem.
  #
  # It allows customization of logging behavior, including:
  # - Log level (`log_level`)
  # - Custom logger (`logger`)
  # - Disabling logging entirely (`disable_logging`)
  # - Structured or custom log formatting (`log_formatter`)
  # - Debug mode (`debug`)
  #
  # @example Configuring Gaskit in an initializer
  #   Gaskit.config do |c|
  #     c.debug = true
  #     c.disable_logging = false
  #
  #     c.context_provider = -> {
  #       {
  #         tenant_id: Current.tenant_id,
  #         user_id: Current.user_id
  #       }
  #     }
  #
  #     # Optionally replace the logger
  #     custom_logger = Logger.new("log/gaskit.log")
  #     c.setup_logger(custom_logger, level: :info, formatter: ->(severity, time, _progname, msg) {
  #       message, context = msg.is_a?(Array) ? msg : [msg, {}]
  #       "[#{time.strftime('%Y-%m-%d %H:%M:%S')} #{severity}] #{message} (#{context.inspect})\n"
  #     })
  #   end
  class Configuration
    # @return [Boolean] Whether debug mode is enabled.
    attr_accessor :debug

    # @return [Boolean] Whether to completely suppress log output.
    attr_accessor :disable_logging

    # @return [Logger] The logger instance used internally by Gaskit.
    attr_reader :logger

    # @return[#call] A callable to apply a global context used for all log entries.
    attr_reader :context_provider

    # Initializes the configuration with default settings.
    #
    # The configuration includes:
    # - Default environment set to `"development"`
    # - Debug mode disabled
    # - Logging to stdout
    # - Default log level set to ::Logger::DEBUG
    # - An empty base context hash
    # - A new `ContractRegistry` instance for contract management
    def initialize
      @debug = false
      @disable_logging = false
      @context_provider = -> { {} }
      @contract_registry = ContractRegistry.new

      setup_logger
    end

    # Sets the logger, formatter, and level in one go.
    #
    # @param custom_logger [::Logger, nil] An optional custom logger.
    # @param level [Symbol, Integer] Log level (e.g., :debug, Logger::WARN)
    # @param formatter [Proc] Custom formatter for log entries.
    def setup_logger(custom_logger = nil, level: :debug, formatter: nil)
      @logger = custom_logger || ::Logger.new($stdout)

      effective_formatter = formatter || @logger&.formatter || Gaskit::Logger.formatter(:pretty)
      self.log_formatter = effective_formatter if effective_formatter.respond_to?(:call)
      self.log_level = level
    end

    # Sets the logging level.
    #
    # @param level [Symbol, Integer] The log level (e.g., :info, :debug, or Logger::WARN).
    # @raise [NameError] If the provided level is a symbol, and it does not map to a valid Logger constant.
    def log_level=(level)
      level = ::Logger.const_get(level.upcase) if level.is_a?(Symbol)
      @logger.level = level
    end

    # Sets a custom log formatter.
    #
    # @param formatter [#call] A callable object that receives log arguments (severity, time, progname, msg).
    # @raise [ArgumentError] If the provided formatter is not callable.
    def log_formatter=(formatter)
      raise ArgumentError, "Formatter must be callable" unless formatter.respond_to?(:call)

      @logger.formatter = formatter
    end

    # Sets the global context provider used for all log entries.
    #
    # @param provider [#call] A proc or lambda returning a Hash of context values.
    # @raise [ArgumentError] If the provided callable is not callable.
    def context_provider=(provider)
      raise ArgumentError, "Provider must be callable" unless provider.respond_to?(:call)

      @context_provider = provider
    end

    # Registers a contract with a name and associated result class.
    #
    # @param name [Symbol, String] The name of the contract.
    # @param result_class [Class] The class that represents the result for the contract.
    # @param override [Boolean] Whether to override an existing contract (default: false).
    # @raise [Gaskit::ContractError] If the contract is already registered and override is not allowed.
    # @raise [Gaskit::ResultTypeError] If the result_class does not inherit from `Gaskit::OperationResult`.
    # @return [void]
    def register_contract(name, result_class, override: false)
      @contract_registry.register(name, result_class, override: override)
    end

    # Fetches a registered contract's result class by its name.
    #
    # @param name [Symbol, String] The name of the contract.
    # @return [Class] The result class associated with the contract.
    # @raise [Gaskit::ContractError] If the contract is not registered.
    def fetch_contract(name)
      @contract_registry.fetch(name)
    end

    # Checks if a contract is registered.
    #
    # @param name [Symbol, String] The name of the contract.
    # @return [Boolean] true if the contract is registered, otherwise false.
    def contract_registered?(name)
      @contract_registry.registered?(name)
    end

    # Lists all registered contracts.
    #
    # @return [Hash<Symbol, Class>] A hash of all registered contracts where keys are
    #   contract names and values are their corresponding result classes.
    def registered_contracts
      @contract_registry.all
    end
  end
end
