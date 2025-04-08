# frozen_string_literal: true

require "spec_helper"

RSpec.describe Gaskit::Operation do
  before do
    stub_const("TestResult", Class.new(Gaskit::OperationResult))
  end

  describe ".use_contract" do
    it "raises if contract is not a symbol" do
      expect do
        Class.new(described_class) { use_contract("not_a_symbol") }
      end.to raise_error(ArgumentError, /must be called with a symbol/)
    end

    it "assigns result class from explicit class" do
      klass = Class.new(described_class) do
        use_contract result: TestResult
        def call
          :ok
        end
      end

      expect(klass.call.value).to eq(:ok)
      expect(klass.result_class).to eq(TestResult)
    end

    it "inherits result class from parent if not set" do
      parent = Class.new(described_class) do
        use_contract result: TestResult
      end

      child = Class.new(parent) do
        def call
          42
        end
      end

      expect(child.call.value).to eq(42)
      expect(child.result_class).to eq(TestResult)
    end

    it "assigns result class from registered contract" do
      Gaskit.register_contract(:base_op_contract, TestResult, override: true)

      klass = Class.new(described_class) do
        use_contract :base_op_contract
        def call
          123
        end
      end

      expect(klass.call.value).to eq(123)
    end
  end

  describe ".call" do
    it "returns a successful result" do
      klass = Class.new(described_class) do
        use_contract result: TestResult
        def call
          "yay"
        end
      end

      result = klass.call
      expect(result).to be_success
      expect(result.value).to eq("yay")
    end
  end

  describe ".call!" do
    it "raises when failure occurs" do
      klass = Class.new(described_class) do
        use_contract result: TestResult
        def call
          raise "failure!"
        end
      end

      expect { klass.call! }.to raise_error("failure!")
    end
  end

  describe "#exit" do
    it "triggers early exit and returns failure result" do
      klass = Class.new(described_class) do
        use_contract result: TestResult
        def call
          exit(:unauthorized, "not allowed")
        end
      end

      result = klass.call
      expect(result).to be_failure
      expect(result.error).to be_a(Gaskit::OperationExit)
      expect(result.error.key).to eq(:unauthorized)
      expect(result.error.message).to eq("not allowed")
    end
  end

  context "missing contract" do
    it "raises when no contract is defined" do
      klass = Class.new(described_class) do
        def call
          "oops"
        end
      end

      expect do
        klass.call
      end.to raise_error(NotImplementedError, /No result_class defined/)
    end
  end
end
