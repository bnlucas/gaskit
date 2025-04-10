# frozen_string_literal: true

require "spec_helper"
require "stringio"

RSpec.describe Gaskit::ContractRegistry do
  let(:registry) { described_class.new }

  let(:valid_result_class) do
    Class.new(Gaskit::OperationResult)
  end

  let(:invalid_result_class) do
    Class.new
  end

  let(:log_output) { StringIO.new }
  let(:test_logger) { Logger.new(log_output) }

  before do
    Gaskit.configuration.setup_logger(test_logger)
    Gaskit.configuration.debug = true
  end

  describe ".verify_result_class!" do
    it "does not raise when the class inherits from BaseResult" do
      expect do
        described_class.verify_result_class!(valid_result_class)
      end.not_to raise_error
    end

    it "raises ResultTypeError when the class does not inherit from BaseResult" do
      expect do
        described_class.verify_result_class!(invalid_result_class)
      end.to raise_error(Gaskit::ResultTypeError, /#{invalid_result_class}/)
    end
  end

  describe "#register" do
    it "registers a contract with a valid result class and logs the registration" do
      registry.register(:my_contract, valid_result_class)

      expect(registry.registered?(:my_contract)).to be true

      log_output.rewind
      expect(log_output.read).to match(/\[Gaskit\] Registered contract my_contract/)
    end

    it "raises if contract is already registered and override is false" do
      registry.register(:my_contract, valid_result_class)

      expect do
        registry.register(:my_contract, valid_result_class)
      end.to raise_error(Gaskit::ContractError, /already registered/)
    end

    it "overrides a contract if override is true and logs the override" do
      registry.register(:my_contract, valid_result_class)

      new_class = Class.new(Gaskit::OperationResult)
      registry.register(:my_contract, new_class, override: true)

      expect(registry.fetch(:my_contract)).to eq new_class

      log_output.rewind
      log = log_output.read
      expect(log.scan("[Gaskit] Registered contract my_contract").size).to eq 2
    end

    it "raises if result class is invalid" do
      expect do
        registry.register(:bad_contract, invalid_result_class)
      end.to raise_error(Gaskit::ResultTypeError)
    end
  end

  describe "#registered?" do
    it "returns true if contract is registered" do
      registry.register(:my_contract, valid_result_class)
      expect(registry.registered?(:my_contract)).to be true
    end

    it "returns false if contract is not registered" do
      expect(registry.registered?(:not_found)).to be false
    end
  end

  describe "#fetch" do
    it "returns the registered result class" do
      registry.register(:my_contract, valid_result_class)
      expect(registry.fetch(:my_contract)).to eq(valid_result_class)
    end

    it "raises if the contract is not registered" do
      expect do
        registry.fetch(:missing)
      end.to raise_error(Gaskit::ContractError, /not registered/)
    end
  end

  describe "#all" do
    it "returns a duplicate hash of all contracts" do
      registry.register(:one, valid_result_class)
      registry.register(:two, valid_result_class)

      all_contracts = registry.registered
      expect(all_contracts).to include(:one, :two)
      expect(all_contracts[:one]).to eq(valid_result_class)
    end

    it "returns a shallow copy" do
      registry.register(:test, valid_result_class)
      copy = registry.registered
      copy[:test] = :something_else
      expect(registry.fetch(:test)).to eq(valid_result_class)
    end
  end
end
