# frozen_string_literal: true

require "spec_helper"

RSpec.describe Gaskit::OperationExit do
  let(:key) { :unauthorized }
  let(:message) { "User is not allowed" }

  describe "#initialize" do
    it "sets the key and message explicitly" do
      error = described_class.new(key, message)

      expect(error.key).to eq(:unauthorized)
      expect(error.message).to eq("User is not allowed")
    end

    it "uses key as message if message is nil" do
      error = described_class.new(:not_found)

      expect(error.key).to eq(:not_found)
      expect(error.message).to eq("early exit")
    end
  end

  describe "inheritance" do
    it "inherits from Gaskit::Error" do
      expect(described_class < Gaskit::Error).to be true
    end

    it "is a kind of StandardError" do
      expect(described_class.new(:any)).to be_a(StandardError)
    end
  end

  describe "#to_s" do
    it "returns the message" do
      expect(described_class.new(key, message).to_s).to eq("User is not allowed")
    end
  end
end
