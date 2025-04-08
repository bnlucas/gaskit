# frozen_string_literal: true

require "spec_helper"

RSpec.describe Gaskit do
  let(:result_class) { Class.new(Gaskit::OperationResult) }
  let(:exit_class)   { Class.new(Gaskit::BaseExit) }

  before do
    # ensure clean slate for contracts in config
    Gaskit.configuration.registered_contracts.each_key do |name|
      Gaskit.configuration.registered_contracts.delete(name)
    end
  end

  describe ".configuration" do
    it "returns an Gaskit::Configuration instance" do
      expect(Gaskit.configuration).to be_a(Gaskit::Configuration)
    end

    it "returns the same instance each time" do
      expect(Gaskit.configuration).to equal(Gaskit.configuration)
    end
  end

  describe ".config" do
    it "yields the configuration object for mutation" do
      expect { |b| described_class.config(&b) }.to yield_with_args(Gaskit.configuration)
    end
  end

  describe ".register_contract" do
    it "delegates to Configuration#register_contract" do
      expect(Gaskit.configuration).to receive(:register_contract).with(:foo, result_class, override: false)
      Gaskit.register_contract(:foo, result_class)
    end
  end

  describe ".fetch_contract" do
    it "fetches a registered contract" do
      Gaskit.register_contract(:test_contract, result_class)
      expect(Gaskit.fetch_contract(:test_contract)).to eq(result_class)
    end
  end

  describe ".contract_registered?" do
    it "returns true if contract is registered" do
      Gaskit.register_contract(:existing, result_class)
      expect(Gaskit.contract_registered?(:existing)).to be true
    end

    it "returns false if contract is not registered" do
      expect(Gaskit.contract_registered?(:missing)).to be false
    end
  end

  describe ".registered_contracts" do
    it "returns all contracts from configuration" do
      Gaskit.register_contract(:alpha, result_class)
      expect(Gaskit.registered_contracts.keys).to include(:alpha)
    end
  end
end
