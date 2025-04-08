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
    #
    # @param result [Gaskit::OperationResult] The final operation result
    # @param steps [Array<Hash>] Step-by-step execution details
    # @param duration [Float, String] Total flow duration
    # @param context [Hash] Execution context
    def initialize(result, steps, duration:, context: {})
      super(
        result.success?,
        result.value,
        result.error,
        duration: duration,
        context: context
      )

      @steps = steps
    end
  end
end
