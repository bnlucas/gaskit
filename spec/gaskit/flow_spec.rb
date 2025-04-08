# frozen_string_literal: true

require "spec_helper"

RSpec.describe Gaskit::Flow do
  let(:context) { { request_id: "abc123" } }

  before do
    stub_const("TestSuccessOp", Class.new(Gaskit::Service) do
      def call(input)
        input + 1
      end
    end)

    stub_const("TestFailureOp", Class.new(Gaskit::Service) do
      def call(_input)
        raise "something went wrong"
      end
    end)

    stub_const("TestExitOp", Class.new(Gaskit::Service) do
      def call(_input)
        exit(:unauthorized, "Not allowed")
      end
    end)
  end

  describe ".call (inline)" do
    it "executes steps and returns a successful result" do
      result = described_class.call(1, context: context) do
        step TestSuccessOp
        step TestSuccessOp
      end

      expect(result).to be_success
      expect(result.value).to eq(3)
      expect(result.steps.size).to eq(2)

      expect(result.steps.first[:args]).to eq([1])
      expect(result.steps.last[:args]).to eq([2])
    end

    it "captures a raised error as failure result (soft mode)" do
      result = described_class.call(1, context: context) do
        step TestSuccessOp
        step TestFailureOp
      end

      expect(result).to be_failure
      expect(result.error).to be_a(StandardError)
      expect(result.steps.size).to eq(2)
    end

    it "halts after early exit and returns exit result" do
      result = described_class.call(1, context: context) do
        step TestSuccessOp
        step TestExitOp
        step TestSuccessOp
      end

      expect(result).to be_failure
      expect(result).to be_early_exit
      expect(result.to_h[:exit]).to include(key: :unauthorized)
      expect(result.steps.size).to eq(2)
    end
  end

  describe ".call! (hard mode)" do
    it "raises on error in hard mode" do
      expect do
        described_class.call!(1, context: context) do
          step TestFailureOp
        end
      end.to raise_error(StandardError, /something went wrong/)
    end
  end

  describe "class-based flow" do
    before do
      stub_const("MyFlow", Class.new(Gaskit::Flow) do
        step TestSuccessOp
        step TestSuccessOp
      end)
    end

    it "executes predefined steps in class" do
      result = MyFlow.call(5, context: context)

      expect(result).to be_success
      expect(result.value).to eq(7)
      expect(result.steps.size).to eq(2)
    end
  end
end
