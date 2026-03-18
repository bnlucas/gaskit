# frozen_string_literal: true

require "cattri"

require_relative "castkit"
require_relative "core"
require_relative "operation_result"
require_relative "operation_exit"
require_relative "helpers"
require_relative "core/hookable"

module Gaskit
  # The Gaskit::Operation class defines a structured and extensible pattern for building application operations.
  # It enforces consistent behavior across operations with Castkit-based input/output contracts.
  #
  # # Features
  # - Castkit input/output contracts for typecasting and validation.
  # - Integrated duration tracking, structured logging, and early exits.
  # - Supports `.call` (non-raising) and `.call!` (raising) styles.
  #
  # @example Basic operation (no contracts)
  #   class MyOperation < Gaskit::Operation
  #     def call
  #       "done"
  #     end
  #   end
  #
  # @example Input/output contracts
  #   class TypedOp < Gaskit::Operation
  #     input_contract do
  #       string :user_id
  #     end
  #
  #     output_contract do
  #       string :status
  #     end
  #
  #     def call(user_id:)
  #       { status: "ok-#{user_id}" }
  #     end
  #   end
  #
  # @abstract Subclass this and define `#call` or `#call!` to create a new operation.
  class Operation
    include Cattri
    include Gaskit::Core::Hookable

    cattri :input_contract, nil, scope: :class
    cattri :output_contract, nil, scope: :class
    cattri :errors_registry, -> { {} }, scope: :class

    cattri :raise_on_failure, nil, final: true
    cattri :context, nil, final: true
    cattri :logger, nil, final: true

    class << self
      alias_method :cattri_input_contract, :input_contract
      alias_method :cattri_input_contract=, :input_contract=
      alias_method :cattri_output_contract, :output_contract
      alias_method :cattri_output_contract=, :output_contract=

      # Declares an input contract for validating args/kwargs before executing #call.
      #
      # Input payload normalization:
      # - kwargs of `{ payload: X }` -> X
      # - non-empty kwargs -> kwargs
      # - single Hash arg -> that Hash
      # - otherwise `{ args: args }`
      #
      # Calling convention:
      # - kwargs-style calls pass a symbol-keyed Hash as keywords; otherwise `payload:`.
      # - args-style calls pass the casted payload as a single positional argument.
      #
      # @param contract [Class, Object, nil] Castkit contract or Castkit::DataObject class.
      # @param strict [Boolean, nil] Override Castkit strict mode when building a DSL contract.
      # @param allow_unknown [Boolean, nil] Allow unknown keys when building a DSL contract.
      # @return [Object, nil] The Castkit contract instance/class.
      def input_contract(contract = nil, strict: nil, allow_unknown: nil, &block)
        if contract.nil? && !block_given? && strict.nil? && allow_unknown.nil?
          return cattri_input_contract if instance_variable_defined?(:@input_contract_defined)
          return superclass.input_contract if superclass.respond_to?(:input_contract)

          return nil
        end

        validator, dataobject_class = build_contract(contract, kind: :input, strict: strict,
                                                               allow_unknown: allow_unknown, &block)
        @input_contract_dataobject = dataobject_class
        @input_contract_defined = true
        self.cattri_input_contract = validator
      end

      # Declares an output contract for validating the return value from #call.
      #
      # @param contract [Class, Object, nil] Castkit contract or Castkit::DataObject class.
      # @param strict [Boolean, nil] Override Castkit strict mode when building a DSL contract.
      # @param allow_unknown [Boolean, nil] Allow unknown keys when building a DSL contract.
      # @return [Object, nil] The Castkit contract instance/class.
      def output_contract(contract = nil, strict: nil, allow_unknown: nil, &block)
        if contract.nil? && !block_given? && strict.nil? && allow_unknown.nil?
          return cattri_output_contract if instance_variable_defined?(:@output_contract_defined)
          return superclass.output_contract if superclass.respond_to?(:output_contract)

          return nil
        end

        validator, dataobject_class = build_contract(contract, kind: :output, strict: strict,
                                                               allow_unknown: allow_unknown, &block)
        @output_contract_dataobject = dataobject_class
        @output_contract_defined = true
        self.cattri_output_contract = validator
      end

      # Declares a symbolic error and message for use with `exit(:key)`.
      #
      # @example
      #   error :unauthorized, "You must be signed in", code: "AUTH-001"
      #
      # @param key [String, Symbol] The key used to declare the error.
      # @param message [String] The error message.
      # @param code [String, nil] Optional error code.
      # @return [void]
      def error(key, message, code: nil)
        unless key.is_a?(Symbol) || key.is_a?(String)
          raise ArgumentError, "Error key must be a symbol or a string, received #{key}"
        end
        raise ArgumentError, "Error message must be a string" unless message.is_a?(String)
        raise ArgumentError, "Error key :#{key} is already registered" if errors_registry.key?(key)

        errors_registry[key.to_sym] = { message: message, code: code }
      end

      # Executes the operation with soft-failure handling.
      #
      # @param args [Array] Positional arguments for the first step.
      # @param context [Hash] Shared context across all steps.
      # @param kwargs [Hash] Keyword arguments for the first step.
      # @return [Gaskit::OperationResult]
      def call(*args, context: {}, **kwargs, &block)
        invoke(false, context, *args, **kwargs, &block)
      end

      # Executes the operation with hard-failure handling (raises on unhandled errors).
      #
      # @param args [Array] Positional arguments for the first step.
      # @param context [Hash] Shared context across all steps.
      # @param kwargs [Hash] Keyword arguments for the first step.
      # @return [Gaskit::OperationResult]
      def call!(*args, context: {}, **kwargs, &block)
        invoke(true, context, *args, **kwargs, &block)
      end

      private

      # Core execution logic for operations, handling errors and timing.
      #
      # Input contracts run before any hooks. Output contracts run after a successful call
      # and before after hooks, so hooks always observe the final OperationResult.
      def invoke(raise_on_failure, context, *args, **kwargs, &block)
        operation = new(raise_on_failure, context: context)

        begin
          call_args, call_kwargs = prepare_input(args, kwargs)
        rescue StandardError => e
          return handle_input_failure(operation, raise_on_failure, e)
        end

        duration, (result, error) = execute(operation, call_args, call_kwargs, &block)

        if error.nil?
          begin
            result = apply_output_contract(result)
          rescue StandardError => e
            return handle_output_failure(operation, raise_on_failure, e, duration)
          end
        end

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
      def execute(operation, args, kwargs, &block)
        Helpers.time_execution do
          operation.apply_hooks(:before, :around) do
            [operation.call(*args, **kwargs, &block), nil]
          end
        rescue StandardError, NotImplementedError => e
          handle_execution_error(operation, e)
        end
      end

      # Builds an OperationResult instance.
      def build_result(result, error, duration, context)
        OperationResult.new(
          error.nil?,
          result,
          error,
          duration: duration,
          context: context
        )
      end

      def log_execution_debug(operation, duration)
        return unless Gaskit.debug?

        operation.logger.debug(context: { duration: duration }) do
          "Operation completed in #{duration} seconds"
        end
      end

      def log_exit(operation, operation_exit)
        operation.logger.warn { "Exited early: #{operation_exit.key} – #{operation_exit.message}" }
      end

      def log_exception(operation, exception)
        operation.logger.error { "[#{exception.class}] #{exception.message}" }
        operation.logger.error { exception.backtrace&.join("\n") }
      end

      def handle_execution_error(operation, error)
        if error.is_a?(Gaskit::OperationExit)
          log_exit(operation, error)
        else
          log_exception(operation, error)
          raise error if operation.raise_on_failure?
        end

        [nil, error]
      end

      def handle_after_hook_error(operation, result, error, duration)
        log_exception(operation, error)
        raise error if operation.raise_on_failure?

        build_result(result, error, duration, operation.context)
      end

      def handle_input_failure(operation, raise_on_failure, error)
        raise error if raise_on_failure

        duration = "0.000000"
        result = build_result(nil, error, duration, operation.context)
        begin
          operation.apply_after_hooks(result)
        rescue StandardError => hook_error
          result = handle_after_hook_error(operation, result, hook_error, duration)
        end
        result
      end

      def handle_output_failure(operation, raise_on_failure, error, duration)
        raise error if raise_on_failure

        result = build_result(nil, error, duration, operation.context)
        begin
          operation.apply_after_hooks(result)
        rescue StandardError => hook_error
          result = handle_after_hook_error(operation, result, hook_error, duration)
        end
        result
      end

      def prepare_input(args, kwargs)
        contract = input_contract
        return [args, kwargs] unless contract

        payload = normalize_input_payload(args, kwargs)
        casted_payload = apply_input_contract(payload)
        build_invocation(casted_payload, kwargs)
      end

      def apply_input_contract(payload)
        contract = input_contract
        casted = if contract.respond_to?(:validate!)
                   contract.validate!(payload)
                 else
                   payload
                 end
        if casted.respond_to?(:input)
          casted = casted.input
        elsif casted.respond_to?(:value)
          casted = casted.value
        end

        dataobject = contract_dataobject(:input)
        return dataobject.new(casted) if dataobject

        casted
      end

      def apply_output_contract(result)
        contract = output_contract
        return result unless contract

        wrapped = !result.is_a?(Hash)
        payload = wrapped ? { value: result } : result

        casted = if contract.respond_to?(:validate!)
                   contract.validate!(payload)
                 else
                   payload
                 end
        if casted.respond_to?(:input)
          casted = casted.input
        elsif casted.respond_to?(:value)
          casted = casted.value
        end

        dataobject = contract_dataobject(:output)
        return dataobject.new(casted) if dataobject

        return casted[:value] if wrapped && casted.is_a?(Hash) && casted.key?(:value)

        casted
      end

      def build_invocation(casted_payload, kwargs)
        kwargs_style = kwargs.key?(:payload) || !kwargs.empty?

        if kwargs_style
          if casted_payload.is_a?(Hash) && casted_payload.keys.all? { |key| key.is_a?(Symbol) }
            [[], casted_payload]
          else
            [[], { payload: casted_payload }]
          end
        else
          [[casted_payload], {}]
        end
      end

      def normalize_input_payload(args, kwargs)
        return kwargs[:payload] if kwargs.length == 1 && kwargs.key?(:payload)
        return kwargs unless kwargs.empty?
        return args.first if args.length == 1 && args.first.is_a?(Hash)

        { args: args }
      end

      def build_contract(contract, kind:, strict:, allow_unknown:, &block)
        rules = contract_validation_rules(strict, allow_unknown)

        if contract && block_given?
          raise ArgumentError, "Provide either a contract or a block, not both"
        end

        return [nil, nil] if contract.nil? && !block_given?

        if contract.is_a?(Class) && contract < ::Castkit::DataObject
          if ::Castkit::Contract.respond_to?(:from_dataobject)
            return [::Castkit::Contract.from_dataobject(contract), contract]
          end
          return [contract, contract]
        end
        return [contract, nil] if contract.respond_to?(:validate!)
        if contract.nil?
          name = contract_name(kind)
          return [::Castkit::Contract.build(name, **rules, &block), nil]
        end

        raise ArgumentError, "Unsupported contract type: #{contract.inspect}"
      end

      def contract_validation_rules(strict, allow_unknown)
        {}.tap do |rules|
          rules[:strict] = strict unless strict.nil?
          rules[:allow_unknown] = allow_unknown unless allow_unknown.nil?
        end
      end

      def contract_name(kind)
        "#{Gaskit::Helpers.resolve_name(self)}_#{kind}_contract".gsub("::", "_").downcase.to_sym
      end

      def contract_dataobject(kind)
        ivar = kind == :input ? :@input_contract_dataobject : :@output_contract_dataobject
        return instance_variable_get(ivar) if instance_variable_defined?(ivar)

        return nil unless superclass.respond_to?(:contract_dataobject, true)

        superclass.send(:contract_dataobject, kind)
      end
    end

    # Initializes a new Gaskit::Operation instance.
    #
    # @param [Boolean] raise_on_failure Whether to raise exceptions on failure.
    # @param [Hash] context Context data for the operation.
    # @return [void]
    def initialize(raise_on_failure, context: {})
      self.raise_on_failure = raise_on_failure
      self.context = apply_context(context)
      self.logger = Gaskit::Logger.new(self, context: self.context)
    end

    def raise_on_failure?
      raise_on_failure
    end

    # Executes the operation logic.
    #
    # @param [Array] args Positional arguments passed.
    # @param [Hash] kwargs Keyword arguments passed.
    # @return [void]
    # @raise [NotImplementedError] Must be implemented by subclasses.
    def call(*_args, **_kwargs)
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
