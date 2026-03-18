# frozen_string_literal: true

require "gaskit/flow"

# rubocop:disable Style/Documentation
class SuccessService < Gaskit::Service
  def call(value)
    value
  end
end

class FailureService < Gaskit::Service
  def call(_value)
    raise "boom!"
  end
end
# rubocop:enable Style/Documentation

RSpec.describe Gaskit::Flow do
  let(:dummy_class) { Class.new(described_class) }

  describe ".inherited" do
    let(:parent_class) do
      Class.new(Gaskit::Flow) do
        step SuccessService
      end
    end

    let(:child_class) do
      Class.new(parent_class) do
        step SuccessService
      end
    end

    it "initializes @steps array on the subclass" do
      expect(parent_class.steps.size).to eq(1)
      expect(child_class.steps.size).to eq(2)
    end
  end

  describe ".steps" do
    let(:dummy_class) do
      Class.new(Gaskit::Flow) do
        step SuccessService
        step SuccessService
      end
    end

    it "returns the defined steps array" do
      expect(dummy_class.steps).to eq([[SuccessService, {}, {}], [SuccessService, {}, {}]])
    end
  end

  describe ".step" do
    it "adds a step with operation, context, and kwargs to the steps list" do
      dummy_class.step(SuccessService, test_key: "test_value")
      expect(dummy_class.steps).to eq([[SuccessService, {}, { test_key: "test_value" }]])
    end
  end

  describe ".call" do
    it "executes the flow" do
      dummy_class.step SuccessService
      result = dummy_class.call(1)

      expect(result).to be_a(Gaskit::FlowResult)
      expect(result.success?).to eq(true)
      expect(result.value).to eq(1)
    end

    it "executes the flow and consumes raised errors" do
      dummy_class.step FailureService
      result = dummy_class.call(1)

      expect(result).to be_a(Gaskit::FlowResult)
      expect(result.failure?).to eq(true)
      expect(result.value).to eq(nil)
    end

    context "when a before hook raises an error" do
      it_behaves_like "a failing hook for call", :before
    end

    context "when an around hook raises an error" do
      it_behaves_like "a failing hook for call", :around
    end

    context "when an after hook raises an error" do
      it_behaves_like "a failing hook for call", :after
    end
  end

  describe ".call!" do
    it "executes the flow" do
      dummy_class.step SuccessService
      result = dummy_class.call!(1)

      expect(result).to be_a(Gaskit::FlowResult)
      expect(result.success?).to eq(true)
      expect(result.value).to eq(1)
    end

    it "executes the flow and raises errors" do
      dummy_class.step FailureService
      expect { dummy_class.call!(1) }.to raise_error("boom!")
    end

    context "when a before hook raises an error" do
      it_behaves_like "a failing hook for call!", :before
    end

    context "when an around hook raises an error" do
      it_behaves_like "a failing hook for call!", :around
    end

    context "when an after hook raises an error" do
      it_behaves_like "a failing hook for call!", :after
    end
  end

  describe ".walk" do
    it "returns a flow instance in soft-failure walk mode" do
      dummy_class.step SuccessService
      flow = dummy_class.walk(1)

      expect(flow.next_step).to be_a(Gaskit::OperationResult)
    end
  end

  describe ".walk!" do
    it "returns a flow instance in hard-failure walk mode" do
      dummy_class.step FailureService
      flow = dummy_class.walk!

      expect { flow.next_step(1) }.to raise_error("boom!")
    end
  end

  describe "#has_next_step?" do
    let(:flow) { dummy_class.walk }

    before { dummy_class.step SuccessService }

    it "returns true if more steps remain" do
      expect(flow.next_step?).to eq(true)
    end

    it "returns false if all steps have been executed" do
      flow.next_step(1)
      expect(flow.next_step?).to eq(false)
    end
  end

  describe "#pending_step" do
    let(:flow) { dummy_class.walk }

    before do
      dummy_class.step SuccessService
      dummy_class.step SuccessService
    end

    it "returns the current step details" do
      expect(flow.pending_step).to include(args: [], kwargs: {}, operation: SuccessService)
    end

    it "returns nil if no steps remain" do
      flow.next_step(1)
      flow.next_step

      expect(flow.pending_step).to eq(nil)
    end

    it "returns the pending step with the result of the previous step" do
      first_step = flow.next_step(1)

      expect(flow.pending_step).to include(args: [first_step.value], kwargs: {}, operation: SuccessService)
    end

    it "returns the pending step with argument overrides" do
      flow.next_step(1)
      expect(flow.pending_step(4)).to include(args: [4], kwargs: {}, operation: SuccessService)
    end
  end

  describe "#next_step" do
    let(:flow) { dummy_class.walk }

    before { dummy_class.step SuccessService }

    it "executes the next step and returns its result" do
      operation = flow.pending_step[:operation]
      step = flow.next_step(1)

      expect(step.value).to eq(operation.call(1).value)
    end

    it "returns nil if no steps remain" do
      flow.next_step(1)

      expect(flow.next_step).to eq(nil)
    end
  end

  describe "#step" do
    let(:flow) do
      Class.new(described_class).call(1) do
        step SuccessService
      end
    end

    it "executes a step within an inline flow definition" do
      expect(flow.value).to eq(SuccessService.call(1).value)
    end
  end

  describe "#rewind" do
    let(:flow) { dummy_class.walk }

    before { dummy_class.step SuccessService }

    it "resets the flow to its initial state" do
      flow.next_step(1)
      expect(flow.next_step?).to eq(false)

      flow.rewind
      expect(flow.next_step?).to eq(true)
    end
  end

  describe "#results" do
    let(:flow) { dummy_class.walk }

    before do
      dummy_class.step SuccessService
      dummy_class.step SuccessService
    end

    it "returns the result metadata of each executed step" do
      result_a = flow.next_step(1)
      result_b = flow.next_step(2)

      expect(flow.results).to eq([result_a.to_h, result_b.to_h])
    end
  end

  describe "#next_step_input" do
    let(:flow) { dummy_class.walk }

    it "uses array results as next args" do
      flow.instance_variable_set(:@result, Gaskit::OperationResult.new(true, [1, 2], nil, duration: "0"))

      expect(flow.send(:next_step_input)).to eq([[1, 2], {}])
    end

    it "uses hash results as next kwargs" do
      flow.instance_variable_set(:@result, Gaskit::OperationResult.new(true, { value: 1 }, nil, duration: "0"))

      expect(flow.send(:next_step_input)).to eq([[], { value: 1 }])
    end
  end

  describe "hook processing" do
    let(:hooked_flow) do
      Class.new(described_class) do
        before { self.class.hook_events << "before" }
        around do |block|
          self.class.hook_events << "around before"
          result = block.call
          self.class.hook_events << "around after"

          result
        end
        after { |result| self.class.hook_events << "after: #{result.value}" }

        step SuccessService

        def self.hook_events
          @hook_events ||= []
        end
      end
    end

    before do
      allow(Gaskit::Logger).to receive(:info)
    end

    it "executes the hooks before the operation" do
      result = hooked_flow.call(:ok)

      expect(result).to be_success
      expect(result.value).to eq(:ok)

      events = ["before", "around before", "around after", "after: #{result.value}"]
      expect(hooked_flow.hook_events).to eq(events)
    end
  end
end
