# frozen_string_literal: true

require_relative "core"

module Gaskit
  # Represents a registry for managing contracts and their result classes
  #
  # This class allows registering contracts with associated result classes,
  # checking if they are registered, and fetching them for use.
  # It also includes validation to ensure result classes adhere to the expected base class.
  class ContractRegistry
    class << self
      # Verifies that the given class is a subclass of `Gaskit::BaseResult`
      #
      # @param result_class [Class] The class to verify
      # @raise [Gaskit::ResultTypeError] if the class does not inherit from `Gaskit::BaseResult`
      def verify_result_class!(result_class)
        raise Gaskit::ResultTypeError, result_class unless result_class <= Gaskit::OperationResult
      end
    end

    # Initializes a new instance of `ContractRegistry`
    #
    # Sets up the internal hash for storing contracts.
    def initialize
      @contracts = {}
    end

    # Registers a contract with an associated result class
    #
    # @param name [Symbol, String] The name of the contract
    # @param result_class [Class] The class that represents the result for the contract
    # @param override [Boolean] Whether to override an existing registration (default: false)
    # @raise [Gaskit::ContractError] if the contract is already registered and override is not allowed
    # @raise [Gaskit::ResultTypeError] if the result_class does not inherit from `Gaskit::BaseResult`
    # @return [void]
    def register(name, result_class, override: false)
      name = name.to_sym
      raise Gaskit::ContractError, "Contract #{name} already registered" if @contracts.key?(name) && !override

      ContractRegistry.verify_result_class!(result_class)
      @contracts[name] = result_class.freeze

      Gaskit.configuration.logger.debug { "[Gaskit] Registered contract #{name}" } if Gaskit.debug?
    end

    # Checks if a contract is registered
    #
    # @param name [Symbol, String] The name of the contract
    # @return [Boolean] true if the contract is registered, otherwise false
    def registered?(name)
      @contracts.key?(name.to_sym)
    end

    # Fetches a registered contract's result class
    #
    # @param name [Symbol, String] The name of the contract
    # @return [Class] The result class for the contract
    # @raise [Gaskit::ContractError] if the contract is not registered
    def fetch(name)
      @contracts.fetch(name.to_sym) do
        raise Gaskit::ContractError, "Contract #{name} not registered, register it with " \
                                     "Gaskit.configuration.contracts.register(name, result_class)"
      end
    end

    # Returns a duplicate of all registered contracts
    #
    # @return [Hash<Symbol, Class>] A hash of all registered contracts where keys are
    #   contract names and values are their corresponding result classes
    def registered
      @contracts.dup
    end
  end
end
