# frozen_string_literal: true

module Gaskit
  # Represents the result of a flow execution, including step-by-step trace
  #
  # @example Checking result and accessing steps
  #   result = MyFlow.call(1, 2)
  #   if result.success?
  #     puts "Total: #{result.value}"
  #   else
  #     puts "Failed at: #{result.steps.last[:operation]}"
  #   end
  class FlowResult < OperationResult
    # @return [Array<Hash>] A list of step data executed during the flow
    attr_reader :steps

    # Initializes a new FlowResult
    # .
    # @param success [Boolean] If the flow was successful or not
    # @param value [Object, nil] The final operation result
    # @param error [StandardError, nil] The error encountered during the operation.
    # @param options [Hash] Keyword arguments
    # @option options [Array<Hash>] :steps Step-by-step execution details
    # @option options [Float, String] :duration Total flow duration
    # @option options [Hash] Execution context
    def initialize(success, value, error = nil, **options)
      super(
        success,
        value,
        error,
        duration: options[:duration],
        context: options[:context]
      )

      @steps = options.fetch(:steps, [])
    end

    def to_h
      super.merge(steps: steps)
    end
  end
end
