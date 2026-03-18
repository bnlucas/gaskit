# frozen_string_literal: true

# Class for testing operation contracts
class InputPayload < Castkit::DataObject
  attribute :value, :integer
end

# Class for testing operation contracts
class InputValidatedOp < Gaskit::Operation
  input_contract InputPayload

  def call(payload:)
    payload.value * 2
  end
end

# Class for testing operation contracts
class OutputValidatedOp < Gaskit::Operation
  # Castkit data object for output contract
  class Payload < ::Castkit::DataObject
    attribute :value, :integer
  end

  output_contract Payload

  def call
    { value: 5 }
  end
end

# Class for testing operation contracts
class OutputInvalidOp < OutputValidatedOp
  def call
    { value: "oops" }
  end
end

# Class for testing operation contracts
class EarlyExitOp < Gaskit::Operation
  output_contract OutputValidatedOp::Payload

  def call
    exit(:stop, "stop")
  end
end

RSpec.describe "Operation contracts" do
  it "always returns an OperationResult from call" do
    klass = Class.new(Gaskit::Operation) do
      def call
        :ok
      end
    end

    result = klass.call

    expect(result).to be_a(Gaskit::OperationResult)
  end

  it "validates input contract and returns success for valid payload" do
    result = InputValidatedOp.call(payload: { value: 10 })

    expect(result).to be_success
    expect(result.value).to eq(20)
    expect(result.error).to be_nil
  end

  it "captures input contract errors on call and returns failure result" do
    result = InputValidatedOp.call(payload: { value: "bad" })

    expect(result).to be_failure
    expect(result.error).to be_a(Castkit::ContractError)
  end

  it "raises on invalid input when using call!" do
    expect { InputValidatedOp.call!(payload: { value: "bad" }) }.to raise_error(Castkit::ContractError)
  end

  it "validates output contract with Castkit data object and returns a DTO" do
    result = OutputValidatedOp.call

    expect(result).to be_success
    expect(result.value).to be_a(OutputValidatedOp::Payload)
    expect(result.value.value).to eq(5)
  end

  it "captures output contract errors and returns failure result" do
    result = OutputInvalidOp.call

    expect(result).to be_failure
    expect(result.error).to be_a(Castkit::ContractError)
  end

  it "raises on invalid output when using call!" do
    expect { OutputInvalidOp.call! }.to raise_error(Castkit::ContractError)
  end

  it "bypasses output_contract on early exit" do
    result = EarlyExitOp.call

    expect(result).to be_failure
    expect(result.early_exit?).to be true
    expect(result.error).to be_a(Gaskit::OperationExit)
  end
end
