# frozen_string_literal: true

require_relative "core"
require_relative "operation_result"
require_relative "operation_exit"
require_relative "helpers"
require_relative "core/hookable"

module Gaskit
  # The Gaskit::Operation class defines a structured and extensible pattern for building application operations.
  # It enforces consistent behavior across operations while supporting customization via contracts.
  #
  # # Features
  # - Pluggable contracts via `use_contract`, allowing you to define or reference a `result` class.
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
  #     use_contract result: MyResult
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
    include Gaskit::Core::Hookable

    class << self
      def result_class
        return @result_class if defined?(@result_class) && @result_class
        return superclass&.result_class if superclass.respond_to?(:result_class)

        nil
      end

      # Defines the result class for this operation.
      # Can reference a named contract registered in `Gaskit::Registry`, or define one without
      # using a registered contract.
      #
      # @example Use a registered contract
      #   use_contract :service
      #
      # @example Define a contract that has not been registered
      #   use_contract result: CustomResult
      #
      # @param contract [Symbol, nil] A registered contract name (e.g., `:service`)
      # @param result [Class, nil] A class that inherits from `Gaskit::BaseResult`
      # @raise [ArgumentError] if contract is not a symbol or unexpected args are passed
      # @raise [ResultTypeError] if `result` is not a subclass of `Gaskit::BaseResult`
      # @return [void]
      def use_contract(contract = nil, result: nil)
        if contract
          raise ArgumentError, "use_contract must be called with a symbol or keyword args" unless contract.is_a?(Symbol)

          result = Gaskit.contracts.fetch(contract)
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
        raise ArgumentError, "Error key must be a symbol or a string, received #{key}" unless key.is_a?(Symbol)
        raise ArgumentError, "Error message must be a string" unless message.is_a?(String)
        raise ArgumentError, "Error key :#{key} is already registered" if errors_registry.key?(key)

        errors_registry[key.to_sym] = { message: message, code: code }
      end

      # Returns the error registry for the operation class
      #
      # @return [void]
      def errors_registry
        @errors_registry ||= {}
      end

      # Executes the operation with soft-failure handling
      #
      # @param args [Array] Positional arguments for the first step
      # @param context [Hash] Shared context across all steps
      # @param kwargs [Hash] Keyword arguments for the first step
      # @return [Gaskit::OperationResult]
      def call(*args, context: {}, **kwargs, &block)
        invoke(false, context, *args, **kwargs, &block)
      end

      # Executes the operation with hard-failure handling (raises on unhandled errors)
      #
      # @param args [Array] Positional arguments for the first step
      # @param context [Hash] Shared context across all steps
      # @param kwargs [Hash] Keyword arguments for the first step
      # @return [Gaskit::OperationResult]
      def call!(*args, context: {}, **kwargs, &block)
        invoke(true, context, *args, **kwargs, &block)
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
      def invoke(raise_on_failure, context, *args, **kwargs, &block)
        unless result_class
          raise NotImplementedError, "No result_class defined for #{name} or its ancestors. " \
                                     "Did you forget to call `use_contract`?"
        end

        operation = new(raise_on_failure, context: context)
        duration, (result, error) = execute(operation, *args, **kwargs, &block)

        result = build_result(result, error, duration, operation.context)

        begin
          operation.apply_after_hooks(result)
        rescue StandardError => e
          result = handle_after_hook_error(operation, result, e, duration)
        end

        log_execution_debug(operation, duration)

        result
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
          operation.apply_hooks(:before, :around) do
            [operation.call(*args, **kwargs, &block), nil]
          end
        rescue StandardError => e
          handle_execution_error(operation, e)
        end
      end

      # Builds an OperationResult instance.
      #
      # @param [Object, nil] result The result of the operation.
      # @param [StandardError] error The error, if any.
      # @param [Float] duration The duration of the operation.
      # @param [Gaskit::Context] context The operation context.
      # @return [OperationResult]
      def build_result(result, error, duration, context)
        result_class.new(
          error.nil?,
          result,
          error,
          duration: duration,
          context: context
        )
      end

      # Logs execution information about the operation if Gaskit.debug? == true.
      #
      # @param [Gaskit::Operation] operation The operation instance.
      # @param [Float] duration The operation's duration.
      def log_execution_debug(operation, duration)
        return unless Gaskit.debug?

        operation.logger.debug(context: { duration: duration }) do
          "Operation completed in #{duration} seconds"
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
      # @param [StandardError] exception The raised exception.
      # @return [void]
      def log_exception(operation, exception)
        operation.logger.error { "[#{exception.class}] #{exception.message}" }
        operation.logger.error { exception.backtrace&.join("\n") }
      end

      # Handles exceptions during execution.
      #
      # @param [Gaskit::Operation] operation The operation instance.
      # @param [StandardError] error The raised error.
      # @return [Array] The result and the error.
      def handle_execution_error(operation, error)
        if error.is_a?(Gaskit::OperationExit)
          log_exit(operation, error)
        else
          log_exception(operation, error)
          raise error if operation.raise_on_failure?
        end

        [nil, error]
      end

      # Handles errors raised after executing hooks.
      #
      # @param [Gaskit::Operation] operation The operation instance.
      # @param [OperationResult] result The current operation result.
      # @param [StandardError] error The encountered error.
      # @param [Float] duration The execution duration.
      def handle_after_hook_error(operation, result, error, duration)
        log_exception(operation, error)
        raise error if operation.raise_on_failure?

        build_result(result, error, duration, operation.context)
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
      @logger = Gaskit::Logger.new(self, context: @context)

      return unless self.class.result_class.nil?

      raise Gaskit::Error, "No result_class defined for #{self.class.name} or its ancestors."
    end

    def raise_on_failure?
      @raise_on_failure
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

    protected

    # Terminates the operation early with a symbolic key.
    #
    # If the key was previously registered via `self.error`, it uses the declared message and code.
    # Otherwise, it uses the key as the message.
    #
    # @param error_key [Symbol] The symbolic reason for exiting.
    # @param message [String, nil] Optional message override.
    # @param code [String, nil] Optional error code.
    # @raise [OperationExit] always raises an instance with message and optional code
    def exit(error_key, message = nil, code: nil)
      error_key = error_key.to_sym
      definition = self.class.errors_registry.fetch(error_key, nil)

      if definition
        message ||= definition[:message]
        code ||= definition[:code]
      end

      raise OperationExit.new(error_key, message, code: code)
    end

    # @see #exit
    alias abort exit

    private

    # Applies global context, if set, from Gaskit.configuration.context_provider.
    #
    # @param context [Hash] The context provided directly to the Flow.
    # @return [Hash] The fully applied context Hash.
    def apply_context(context = {})
      default_context = Gaskit.configuration.context_provider.call
      Helpers.deep_compact(default_context.merge(context))
    end
  end
end
