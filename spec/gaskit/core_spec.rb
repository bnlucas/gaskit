# frozen_string_literal: true

RSpec.describe Gaskit do
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
