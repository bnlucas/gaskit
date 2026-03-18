# frozen_string_literal: true

# Class for testing service operations
class AddOneService < Gaskit::Service
  def call(value)
    value + 1
  end
end

# Class for testing service operations
class MultiplyService < Gaskit::Service
  def call(value)
    value * 2
  end
end

# Class for testing service pipelines
class PipelineFlow < Gaskit::Flow
  step AddOneService
  step MultiplyService
end

RSpec.describe Gaskit::Flow do
  it "runs a multi-step flow using service operations" do
    result = PipelineFlow.call(2, context: { correlation_id: "abc" })

    expect(result).to be_success
    expect(result.value).to eq(6)
    expect(result.steps.size).to eq(2)
  end

  it "returns a failing result when a step raises without raising globally" do
    failing_service = Class.new(Gaskit::Service) do
      def call(_value)
        raise "boom"
      end
    end

    flow_class = Class.new(Gaskit::Flow) do
      step failing_service
    end

    result = flow_class.call(1)
    expect(result).to be_failure
    expect(result.error).to be_a(RuntimeError)
  end
end
