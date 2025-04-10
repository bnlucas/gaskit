# frozen_string_literal: true

require "spec_helper"

RSpec.describe Gaskit do
  let(:result_class) { Class.new(Gaskit::OperationResult) }
  let(:exit_class)   { Class.new(Gaskit::BaseExit) }

  before do
    # ensure clean slate for contracts in config
    Gaskit.configuration.contracts.registered.each_key do |name|
      Gaskit.configuration.contracts.registered.delete(name)
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
end
