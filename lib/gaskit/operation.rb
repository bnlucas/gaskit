# frozen_string_literal: true

require_relative "core"
require_relative "operation_result"
require_relative "operation_exit"
require_relative "helpers"

module Gaskit
  # The Gaskit::Operation class defines a structured and extensible pattern for building application operations.
  # It enforces consistent behavior across operations while supporting customization via contracts.
  #
  # # Features
  # - Pluggable contracts via `use_contract`, allowing you to define or reference a `result` and
  #   `early_exit` class.
  # - A **contract** is a pairing of a result and early_exit class, either manually defined or registered
  #   under a symbol.
  # - Integrated duration tracking, structured logging, and early exits.
  # - Supports `.call` (non-raising) and `.call!` (raising) styles.
  #
  # @example Using a registered contract
  #   class MyOperation < Gaskit::Operation
  #     use_contract :service
  #
  #     def call
  #       # Do work
  #       "done"
  #     end
  #   end
  #
  # @example Overriding only part of the contract
  #   class MyCustomOp < Gaskit::Operation
  #     use_contract :service, result: MyCustomResult
  #
  #     def call
  #       exit(:unauthorized, "User not allowed") if unauthorized?
  #       "okay"
  #     end
  #   end
  #
  # @example Fully manual contract
  #   class ManualOp < Gaskit::Operation
  #     use_contract result: MyResult, early_exit: MyExit
  #
  #     def call
  #       do_work
  #     end
  #   end
  #
  #   result = ManualOp.call(context: { request_id: "abc123" })
  #
  # @abstract Subclass this and define `#call` or `#call!` to create a new operation.
  class Operation
    class << self
      def result_class
        return @result_class if defined?(@result_class) && @result_class
        return superclass&.result_class if superclass.respond_to?(:result_class)

        nil
      end

      # Defines the result and early exit classes for this operation.
      # Can reference a named contract registered in `Gaskit::Registry`, override either part manually,
      # or define both without using a named contract.
      #
      # @example Use a registered contract
      #   use_contract :service
      #
      # @example Override only result class
      #   use_contract :service, result: CustomResult
      #
      # @example Define both without using a contract name
      #   use_contract result: CustomResult, early_exit: CustomExit
      #
      # @param contract [Symbol, nil] A registered contract name (e.g., `:service`)
      # @param result [Class, nil] A class that inherits from `Gaskit::BaseResult`
      # @raise [ArgumentError] if contract is not a symbol or unexpected args are passed
      # @raise [ResultTypeError] if `result` is not a subclass of `Gaskit::BaseResult`
      # @raise [EarlyExitTypeError] if `early_exit` is not a subclass of `Gaskit::BaseExit`
      # @return [void]
      def use_contract(contract = nil, result: nil)
        if contract
          raise ArgumentError, "use_contract must be called with a symbol or keyword args" unless contract.is_a?(Symbol)

          result = Gaskit.fetch_contract(contract)
        end

        Gaskit::ContractRegistry.verify_result_class!(result)
        @result_class = result
      end

      # Declares a symbolic error and message for use with `exit(:key)`
      #
      # @example
      #   error :unauthorized, "You must be signed in", code: "AUTH-001"
      #
      # @param key [String, Symbol] The key used to declare the error.
      # @param message [String] The error message.
      # @param code [String, nil] Optional error code.
      # @return [void]
      def error(key, message, code: nil)
        errors_registry[key.to_sym] = { message: message, code: code }
      end

      # Returns the error registry for the operation class
      #
      # @return [void]
      def errors_registry
        @errors_registry ||= {}
      end

      # Execute the operation without raising an exception on failure.
      #
      # @param [Array] args Positional arguments passed.
      # @param [Hash] kwargs Keyword arguments passed (with optional :context).
      # @yield [Block] Additional block logic to pass during the operation.
      # @return [OperationResult] The result of the operation.
      def call(*args, **kwargs, &block)
        invoke(false, *args, **kwargs, &block)
      end

      # Execute the operation with raising an exception on failure.
      #
      # @param [Array] args Positional arguments passed.
      # @param [Hash] kwargs Keyword arguments passed (with optional :context).
      # @yield [Block] Additional block logic to pass during the operation.
      # @return [OperationResult] The result of the operation.
      def call!(*args, **kwargs, &block)
        invoke(true, *args, **kwargs, &block)
      end

      private

      # Core execution logic for operations, handling errors and timing.
      #
      # @param [Boolean] raise_on_failure Whether to raise exceptions on failure.
      # @param [Array] args Positional arguments for the operation.
      # @param [Hash] kwargs Keyword arguments, including optional :context.
      # @yield [Block] Additional block logic during execution.
      # @raise [NotImplementedError] If operation type is not set in subclasses.
      # @return [OperationResult] The result of the operation.
      def invoke(raise_on_failure, *args, **kwargs, &block)
        unless result_class
          raise NotImplementedError, "No result_class defined for #{name} or its ancestors. " \
                                     "Did you forget to call `use_contract`?"
        end

        context = kwargs.delete(:context) || {}
        operation = new(raise_on_failure, context: context)
        duration, (result, error) = execute(operation, *args, **kwargs, &block)

        operation.logger.debug(context: { duration: duration }) do
          "Operation completed in #{duration} seconds"
        end

        result_class.new(error.nil?, result, error, duration: duration, context: context)
      end

      # Executes the operation logic and handles potential exceptions.
      #
      # @param [Gaskit::Operation] operation The instance of the current operation.
      # @param [Array] args Positional arguments passed.
      # @param [Hash] kwargs Keyword arguments passed.
      # @yield [Block] Additional block for the operation.
      # @return [Array] The execution duration, result, and error if any.
      def execute(operation, *args, **kwargs, &block)
        Helpers.time_execution do
          [operation.call(*args, **kwargs, &block), nil]
        rescue StandardError => e
          if e.is_a?(Gaskit::OperationExit)
            log_exit(operation, e)
          else
            log_exception(operation, e)
            raise e if operation.raise_on_failure

          end
          [nil, e]
        end
      end

      # Logs an early exit from the operation.
      #
      # @param [Gaskit::Operation] operation The operation instance.
      # @param [StandardError] operation_exit The exit error raised.
      # @return [void]
      def log_exit(operation, operation_exit)
        operation.logger.warn { "Exited early: #{operation_exit.key} – #{operation_exit.message}" }
      end

      # Logs any unhandled exception during the operation.
      #
      # @param [Gaskit::Operation] operation The operation instance.
      # @param [Exception] exception The raised exception.
      # @return [void]
      def log_exception(operation, exception)
        operation.logger.error { "[#{exception.class}] #{exception.message}" }
        operation.logger.error { exception.backtrace&.join("\n") }
      end

      # @return [String] The name of the operation class (e.g., "MyOperation").
      def operation_name
        @operation_name ||= self.class.name.to_s
      end
    end

    attr_reader :raise_on_failure, :context, :logger

    # Initializes a new Gaskit::Operation instance.
    #
    # @param [Boolean] raise_on_failure Whether to raise exceptions on failure.
    # @param [Hash] context Context data for the operation.
    # @return [void]
    def initialize(raise_on_failure, context: {})
      @raise_on_failure = raise_on_failure
      @context = apply_context(context)
      @logger = Gaskit::Logger.new(self.class, context: @context)
    end

    # Applies global context, if set, from Gaskit.configuration.context_provider.
    #
    # @param context [Hash] The context provided directly to the Flow.
    # @return [Hash] The fully applied context Hash.
    def apply_context(context)
      default_context = Gaskit.configuration.context_provider.call
      Helpers.deep_compact(default_context.merge(context))
    end

    # Executes the operation logic.
    #
    # @param [Array] args Positional arguments passed.
    # @param [Hash] kwargs Keyword arguments passed.
    # @return [void]
    # @raise [NotImplementedError] Must be implemented by subclasses.
    def call(*args, **kwargs)
      raise NotImplementedError, "#{self.class.name} must implement `#call`"
    end

    # Terminates the operation early with a symbolic key.
    #
    # If the key was previously registered via `self.error`, it uses the declared message and code.
    # Otherwise, it uses the key as the message.
    #
    # @param exit_key [Symbol] The symbolic reason for exiting.
    # @param message [String, nil] Optional message override.
    # @raise [OperationExit] always raises an instance with message and optional code
    def exit(exit_key, message = nil)
      exit_key = exit_key.to_sym
      definition = self.class.errors_registry[exit_key]

      if definition
        message ||= definition[:message]
        code = definition[:code]
      end

      raise OperationExit.new(exit_key, message, code: code)
    end

    # @see #exit
    alias abort exit
  end
end
