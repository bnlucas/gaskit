# frozen_string_literal: true

require "logger"

require_relative "contract_registry"
require_relative "hook_registry"

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
      @hook_registry = HookRegistry.new

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

    # Returns the ContractRegistry instance.
    #
    # @return [Gaskit::ContractRegistry] The ContractRegistry instance.
    def contracts
      @contract_registry
    end

    # Returns the HookRegistry instance.
    #
    # @return [Gaskit::HookRegistry] The HookRegistry instance.
    def hooks
      @hook_registry
    end
  end
end
