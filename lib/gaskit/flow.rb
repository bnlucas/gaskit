# frozen_string_literal: true

require "securerandom"
require_relative "core"
require_relative "flow_result"
require_relative "helpers"

module Gaskit
  # Base class for defining and executing multi-step operation pipelines
  #
  # @example Inline (block-based) flow
  #   result = Gaskit::Flow.call(1, 2, context: {}) do
  #     step AddOp
  #     step MultOp, multiplier: 2
  #   end
  #
  # @example Class-based flow
  #   class MyFlow < Gaskit::Flow
  #     step AddOp
  #     step MultOp, multiplier: 1.5
  #   end
  #
  #   result = MyFlow.call(5, 5, context: { request_id: "abc123" })
  class Flow
    class << self
      # Inherited hook to initialize step DSL
      #
      # @param subclass [Class] The subclass inheriting from Flow
      # @return [void]
      def inherited(subclass)
        subclass.instance_variable_set(:@defined_steps, [])
        super
      end

      # Returns defined steps for the flow class
      #
      # @return [Array<Array>] An array of [operation, args, kwargs] tuples
      def defined_steps
        @defined_steps ||= []
      end

      # Adds a step to the flow
      #
      # @param operation [Class<Gaskit::Operation>] The operation class
      # @param args [Array] Positional arguments for the step
      # @param context [Hash] Optional context overrides
      # @param kwargs [Hash] Keyword arguments for the step
      # @return [void]
      def step(operation, *args, context: {}, **kwargs)
        kwargs = kwargs.merge(context: context)
        defined_steps << [operation, args, kwargs]
      end

      # Executes the flow with soft-failure handling
      #
      # @param args [Array] Positional arguments for the first step
      # @param context [Hash] Shared context across all steps
      # @param kwargs [Hash] Keyword arguments for the first step
      # @return [FlowResult]
      def call(*args, context: {}, **kwargs, &block)
        invoke(false, context, *args, **kwargs, &block)
      end

      # Executes the flow with hard-failure handling (raises on unhandled errors)
      #
      # @param args [Array] Positional arguments for the first step
      # @param context [Hash] Shared context across all steps
      # @param kwargs [Hash] Keyword arguments for the first step
      # @return [FlowResult]
      def call!(*args, context: {}, **kwargs, &block)
        invoke(true, context, *args, **kwargs, &block)
      end

      private

      # Internal flow initializer
      def invoke(raise_on_failure, context, *args, **kwargs, &block)
        flow = new(raise_on_failure, context, [args, kwargs])
        flow.execute(&block)
      end
    end

    # @return [Hash] Execution context
    attr_reader :context

    # @return [Gaskit::OperationResult] Most recent result
    attr_reader :result

    # @return [Array<Hash>] List of step metadata
    attr_reader :steps

    # Executes a single step of the flow
    #
    # @param operation [Class<Gaskit::Operation>]
    # @param args [Array] Additional positional arguments
    # @param context [Hash] Step-local context
    # @param kwargs [Hash] Additional keyword arguments
    # @return [void]
    def step(operation, *args, context: {}, **kwargs, &block)
      raise ArgumentError, "Operation must be a subclass of Gaskit::Operation" unless operation <= Gaskit::Operation

      return if result&.early_exit?

      kwargs = kwargs.merge(context: context)
      @result = execute_step(operation, *args, **kwargs, &block)
      @steps << compile_step_entry(operation, *args, **kwargs)

      update_input(result)
    end

    # Executes the flow either via block or pre-defined DSL
    #
    # @return [FlowResult]
    def execute(&block)
      duration, = Gaskit::Helpers.time_execution do
        if block_given?
          instance_eval(&block)
        else
          self.class.defined_steps.each { |(op, args, kwargs)| step(op, *args, **kwargs) }
        end

        result
      end

      FlowResult.new(@result, @steps, duration: duration, context: @context)
    end

    private

    # Initializes a flow instance
    #
    # @param raise_on_failure [Boolean] Whether to raise on unexpected errors
    # @param context [Hash] Flow context
    # @param input [Array] Initial args/kwargs input bundle
    def initialize(raise_on_failure, context, input)
      @raise_on_failure = raise_on_failure
      @context = apply_context(context)
      @input = input
      @steps = []
      @result = nil
    end

    # Applies global context, if set, from Gaskit.configuration.context_provider
    # and injects the `gaskit_flow` key to indicate to operations they are a part
    # of a flow.
    #
    # @param context [Hash] The context provided directly to the Flow.
    # @return [Hash] The fully applied context Hash.
    def apply_context(context)
      default_context = Gaskit.configuration.context_provider.call
      context = default_context.merge(
        gaskit_flow: { id: SecureRandom.uuid, name: self.class.name },
        **context
      )

      Helpers.deep_compact(context)
    end

    # Executes a single operation step and handles errors
    #
    # @param operation [Class<Gaskit::Operation>]
    # @param kwargs [Hash] Merged args/kwargs/context
    # @return [Gaskit::OperationResult]
    def execute_step(operation, **kwargs, &block)
      input_args, input_kwargs = @input
      kwargs = (input_kwargs || {}).merge(kwargs).merge(context: @context)

      return operation.call!(*input_args, **kwargs, &block) if @raise_on_failure

      operation.call(*input_args, **kwargs, &block)
    rescue StandardError => e
      raise e if @raise_on_failure

      result_class = operation.class.result_class
      result_class.new(false, nil, e, duration: 0.0, context: @context)
    end

    # Logs a step’s full input and output
    #
    # @param operation [Class]
    # @param args [Array]
    # @param kwargs [Hash]
    # @return [Hash] Step metadata
    def compile_step_entry(operation, *args, **kwargs)
      args, kwargs = step_input(*args, **kwargs)

      {
        operation: operation,
        args: args,
        kwargs: kwargs,
        result: result.to_h
      }
    end

    # Combines current flow input with explicit args for logging
    #
    # @param args [Array]
    # @param kwargs [Hash]
    # @return [Array<Array, Hash>]
    def step_input(*args, **kwargs)
      input_args, input_kwargs = @input
      args = (input_args || []).concat(args)
      kwargs = input_kwargs.merge(kwargs)

      [args, kwargs]
    end

    # Set the input used to call the next operation. Do not set input if the result
    # is a failure or has a nil value.
    #
    # @param result [Gaskit::OperationResult] The result of the operation.
    # @return [void]
    def update_input(result)
      return if result&.failure? || result&.value.nil?

      @input =
        case result.value
        when Array
          [result.value, {}]
        when Hash
          [[], result.value]
        else
          [[result.value], {}]
        end
    end
  end
end
