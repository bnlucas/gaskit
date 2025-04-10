# frozen_string_literal: true

require "securerandom"
require_relative "core"
require_relative "flow_result"
require_relative "helpers"
require_relative "hookable"

module Gaskit
  # The `Gaskit::Flow` class defines and executes a pipeline of operations,
  # each of which returns a `Gaskit::OperationResult`. Flows can be defined via
  # a class-based DSL or run inline using a block.
  #
  # Steps share context and flow state, with support for early exits, manual
  # control, and step-by-step walking. A flow is constructed from a sequence of
  # registered operations, each of which may receive and return input to influence
  # subsequent steps.
  #
  # ## Features
  # - Declarative or block-based step definitions
  # - Per-step argument and context overrides
  # - Shared flow-level context with metadata injection
  # - Manual stepping (`walk` and `next_step`)
  # - Rewind capability for retryable flows
  # - Hookable lifecycle via `Gaskit::Hookable`
  #
  # @example Inline (block-based) flow
  #   result = Gaskit::Flow.call(1) do
  #     step Add
  #     step Double
  #   end
  #
  #   result.value # => 4
  #
  # @example Class-based flow
  #   class MyFlow < Gaskit::Flow
  #     step Add
  #     step Double
  #   end
  #
  #   result = MyFlow.call(1)
  #   result.value # => 4
  #
  # @example Step-by-step execution (walk)
  #   flow = MyFlow.walk(1)
  #   while flow.has_next_step?
  #     flow.next_step
  #   end
  #   flow.result.value # => 4
  #
  # @example Rewinding and re-running
  #   flow.rewind
  #   flow.next_step # starts from first step again
  #
  # @see Gaskit::Operation
  # @see Gaskit::FlowResult
  # @see Gaskit::Hookable
  class Flow
    include Gaskit::Hookable

    class << self
      # Called when a subclass is defined, initializing an empty step list.
      #
      # @param subclass [Class] the subclass inheriting from Flow
      # @return [void]
      def inherited(subclass)
        subclass.instance_variable_set(:@steps, @steps)
        super
      end

      # Returns the list of declared steps for the flow class.
      #
      # @return [Array<Array>] An array of [operation, context, kwargs] triples.
      def steps
        @steps ||= []
      end

      # Registers a step in the class-level flow definition.
      #
      # @param operation [Class<Gaskit::Operation>] The operation to run.
      # @param context [Hash] Optional context for this step.
      # @param kwargs [Hash] Keyword arguments for this step.
      # @return [void]
      def step(operation, context: {}, **kwargs)
        steps << [operation, context, kwargs]
      end

      # Executes the flow with soft failure handling.
      #
      # @param args [Array] Positional arguments for the first step.
      # @param context [Hash] Shared context across all steps.
      # @param kwargs [Hash] Keyword arguments for the first step.
      # @return [FlowResult] The result of the flow execution.
      def call(*args, context: {}, **kwargs, &block)
        invoke(false, context, *args, **kwargs, &block)
      end

      # Executes the flow with hard failure handling (raises on unhandled errors).
      #
      # @param args [Array] Positional arguments for the first step.
      # @param context [Hash] Shared context across all steps.
      # @param kwargs [Hash] Keyword arguments for the first step.
      # @return [FlowResult] The result of the flow execution.
      # @raise [StandardError] If an error occurs in any step.
      def call!(*args, context: {}, **kwargs, &block)
        invoke(true, context, *args, **kwargs, &block)
      end

      # Creates a flow instance for step-by-step execution.
      #
      # @param args [Array] Initial positional arguments.
      # @param context [Hash] Shared execution context.
      # @param kwargs [Hash] Initial keyword arguments.
      # @return [Flow] A walkable flow instance.
      def walk(*args, context: {}, **kwargs)
        build(false, context, *args, **kwargs)
      end

      # Same as {#walk} but raises on any step failure.
      #
      # @param args [Array] Initial positional arguments.
      # @param context [Hash] Shared execution context.
      # @param kwargs [Hash] Initial keyword arguments.
      # @return [Flow] A walkable flow instance with hard failure behavior.
      def walk!(*args, context: {}, **kwargs)
        build(true, context, *args, **kwargs)
      end

      # Internal flow execution logic.
      #
      # @param raise_on_failure [Boolean] Whether to raise on failure.
      # @param context [Hash] Execution context.
      # @param args [Array] Initial positional arguments.
      # @param kwargs [Hash] Initial keyword arguments.
      # @return [FlowResult] The result of the executed flow.
      def invoke(raise_on_failure, context, *args, **kwargs, &block)
        flow = build(raise_on_failure, context, *args, **kwargs, &block)
        flow.send(:execute, &block)
      end

      private

      # Constructs a flow instance.
      #
      # @param raise_on_failure [Boolean] Whether the flow should raise on failure.
      # @param context [Hash] Flow context.
      # @param args [Array] Positional args.
      # @param kwargs [Hash] Keyword args.
      # @return [Flow] The constructed flow instance.
      def build(raise_on_failure, context, *args, **kwargs)
        new(raise_on_failure, context, *args, **kwargs)
      end
    end

    attr_reader :logger

    # Returns true if there are more steps remaining in the sequence.
    #
    # @return [Boolean] Whether the flow has more steps to execute.
    def next_step?
      @step_index < @step_sequence.size
    end

    # Returns the metadata for the pending step.
    #
    # @return [Hash, nil] The pending step's operation, context, and kwargs, or nil if no steps remain.
    def pending_step(*args, **kwargs)
      return nil unless next_step?

      operation, context, step_kwargs = @step_sequence[@step_index]
      context = @context.merge(context)
      args, kwargs = resolve_step_input(
        args: args,
        kwargs: kwargs,
        step_kwargs: step_kwargs
      )

      { operation: operation, context: context, args: args, kwargs: kwargs }
    end

    # Executes the next step in the flow.
    #
    # @param args [Array] Optional positional arguments to override input.
    # @param kwargs [Hash] Optional keyword arguments to override input.
    # @return [Gaskit::OperationResult, nil] The result of the step, or nil if no steps remain.
    def next_step(*args, **kwargs)
      return unless next_step?

      operation, context, step_kwargs = @step_sequence[@step_index]
      @step_index += 1

      process_step(operation, context, step_kwargs, args, kwargs)
    end

    # Runs a step inline from within a block-based flow definition.
    #
    # @param operation [Class<Gaskit::Operation>] The operation to execute.
    # @param context [Hash] Additional context for the step.
    # @param kwargs [Hash] Keyword arguments for the step.
    # @return [Gaskit::OperationResult] The result of the step.
    def step(operation, context: {}, **kwargs)
      process_step(operation, context, kwargs)
    end

    # Rewinds the flow to its initial state.
    #
    # @return [void]
    def rewind
      @input = @initial_input.dup
      @result = nil
      @steps.clear
      @step_index = 0
    end

    # Returns the result hashes from all executed steps.
    #
    # @return [Array<Hash>] Array of step metadata hashes including input/output.
    def results
      @steps.map { |entry| entry[:result] }
    end

    private

    # Initializes a new flow instance.
    #
    # @param raise_on_failure [Boolean] Whether to raise on step failure.
    # @param context [Hash] Flow execution context.
    # @param args [Array] Initial positional arguments.
    # @param kwargs [Hash] Initial keyword arguments.
    def initialize(raise_on_failure, context, *args, **kwargs)
      @raise_on_failure = raise_on_failure
      @context = apply_context(context)

      @input = [args, kwargs]
      @initial_input = @input.dup
      @result = nil

      @steps = []
      @step_sequence = self.class.steps.dup
      @step_index = 0

      @logger = Gaskit::Logger.new(self, context: @context)
    end

    # Executes a single step of the flow.
    #
    # @param operation [Class<Gaskit::Operation>] The operation to execute.
    # @param context [Hash] Step-local context.
    # @param step_kwargs [Hash] DSL-defined kwargs.
    # @param override_args [Array] Positional args from manual call.
    # @param override_kwargs [Hash] Kwargs from manual call.
    # @return [Gaskit::OperationResult] The result object.
    def process_step(operation, context, step_kwargs, override_args = [], override_kwargs = {})
      raise ArgumentError, "Operation must be a subclass of Gaskit::Operation" unless operation <= Gaskit::Operation
      return if @result&.early_exit?

      args, kwargs = resolve_step_input(
        args: override_args,
        kwargs: override_kwargs,
        step_kwargs: step_kwargs
      )

      kwargs = kwargs.merge(context: context)

      @result = execute_step(operation, context, args, kwargs)
      @steps << step_entry(operation, args, kwargs)
      @input = next_step_input || [[], {}]

      @result
    end

    # Resolves arguments for a step, merging flow input and overrides.
    #
    # @param args [Array] Overriding args.
    # @param kwargs [Hash] Overriding kwargs.
    # @param step_kwargs [Hash] Default step keyword args.
    # @return [Array<Array, Hash>] Final [args, kwargs] pair.
    def resolve_step_input(args: [], kwargs: {}, step_kwargs: {})
      input_args, input_kwargs = @input

      args = input_args if args.empty?
      kwargs = input_kwargs.merge(step_kwargs).merge(kwargs)

      [args, kwargs]
    end

    # Executes all steps in the flow.
    #
    # @return [FlowResult] The result of the executed flow.
    def execute(&block)
      duration, (_, error) = time_execution(&block)
      result = build_result(duration, error)

      begin
        apply_after_hooks(result)
      rescue StandardError => e
        result = handle_after_hook_error(e, duration)
      end

      result
    end

    # Executes a specific operation step.
    #
    # @param operation [Class<Gaskit::Operation>] The operation to run.
    # @param context [Hash] Execution context for the operation.
    # @param args [Array] Positional arguments.
    # @param kwargs [Hash] Keyword arguments.
    # @return [Gaskit::OperationResult] Result of the operation call.
    def execute_step(operation, context, args, kwargs, &block)
      raise ArgumentError, "Operation must be a subclass of Gaskit::Operation" unless operation <= Gaskit::Operation

      context = @context.merge(context)
      return operation.call!(*args, context: context, **kwargs, &block) if @raise_on_failure

      operation.call(*args, context: context, **kwargs, &block)
    end

    # Times flow execution, including any hooks set.
    #
    # @return [Array<Float, Object>] Execution time and final result.
    def time_execution(&block)
      Helpers.time_execution do
        apply_hooks(:before, :around) do
          if block_given?
            instance_eval(&block)
          else
            @step_sequence.each { next_step }
          end

          [@result, nil]
        end
      rescue StandardError => e
        handle_execution_error(e)
        [nil, e]
      end
    end

    # Merges default and passed context and injects flow metadata.
    #
    # @param context [Hash] User-provided context.
    # @return [Hash] Final context.
    def apply_context(context)
      default_context = Gaskit.configuration.context_provider.call
      context = default_context.merge(
        gaskit_flow: { id: SecureRandom.uuid, name: Gaskit::Helpers.resolve_name(self) },
        **context
      )

      Helpers.deep_compact(context)
    end

    # Builds a step metadata entry.
    #
    # @param operation [Class] Operation class.
    # @param args [Array] Arguments passed.
    # @param kwargs [Hash] Keyword arguments passed.
    # @return [Hash] Metadata about the step.
    def step_entry(operation, args, kwargs)
      {
        operation: operation,
        args: args,
        kwargs: kwargs,
        result: @result.to_h
      }
    end

    # Determines next input tuple based on previous result.
    #
    # @return [Array<Array, Hash>, nil] Tuple of [args, kwargs] or nil if step failed.
    def next_step_input
      case @result&.value
      when Array
        [@result&.value, {}]
      when Hash
        [[], @result&.value]
      else
        [[@result&.value], {}]
      end
    end

    # Builds a FlowResult object.
    #
    # @param duration [Float] Time spent executing.
    # @param error [StandardError, nil] Optional error object.
    # @return [FlowResult] The constructed result object.
    def build_result(duration, error = nil)
      error ||= @result&.error

      FlowResult.new(
        error.nil?,
        @result&.value,
        error,
        steps: @steps,
        duration: duration,
        context: @context
      )
    end

    # Handles a raised exception during execution.
    #
    # @param error [StandardError] The raised error.
    # @return [void]
    # @raise [StandardError] If raise_on_failure is true.
    def handle_execution_error(error)
      log_exception(error)
      raise error if @raise_on_failure
    end

    # Handles a post-hook exception.
    #
    # @param error [StandardError] The raised error.
    # @param duration [Float] Total flow duration.
    # @return [FlowResult] A failed FlowResult.
    def handle_after_hook_error(error, duration)
      log_exception(error)
      raise error if @raise_on_failure

      build_result(duration, error)
    end

    # Logs an exception with context.
    #
    # @param exception [StandardError] Exception to log.
    # @return [void]
    def log_exception(exception)
      logger.error { "[#{exception.class}] #{exception.message}" }
      # logger.error { exception.backtrace&.join("\n") }
    end
  end
end
