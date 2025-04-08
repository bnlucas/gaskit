# frozen_string_literal: true

require_relative "configuration"
require_relative "contract_registry"

module Gaskit
  class << self
    # Configures the Gaskit system.
    #
    # This yields the configuration instance, allowing you to modify settings such as logger,
    # global context, log level, and formatting.
    #
    # @yieldparam [Gaskit::Configuration] configuration
    # @return [void]
    def config
      yield(configuration)
    end

    # Retrieves the global Gaskit configuration.
    #
    # @return [Gaskit::Configuration] the configuration instance
    def configuration
      @configuration ||= Configuration.new
    end

    # Returns configuration.debug.
    #
    # @return [Boolean] `true` is Gaskit is set to debug, `false` otherwise.
    def debug?
      Gaskit.configuration.debug
    end

    # Registers a new operation contract.
    #
    # @param name [Symbol, String] Contract name
    # @param result_class [Class<Gaskit::OperationResult>] Result class for the operation
    def register_contract(name, result_class, override: false)
      configuration.register_contract(name, result_class, override: override)
    end

    # Fetches the result and exit classes for the given contract name.
    #
    # @param name [Symbol, String]
    # @return [Class]
    def fetch_contract(name)
      configuration.fetch_contract(name)
    end

    # Returns whether the contract is registered.
    #
    # @param name [Symbol, String]
    # @return [Boolean]
    def contract_registered?(name)
      configuration.contract_registered?(name)
    end

    # Returns all registered contracts.
    #
    # @return [Hash{Symbol=>Hash}]
    def registered_contracts
      configuration.registered_contracts
    end
  end
end
