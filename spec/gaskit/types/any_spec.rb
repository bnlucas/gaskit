# frozen_string_literal: true

require "gaskit/types/any"

RSpec.describe Gaskit::Types::Any do
  let(:type) { described_class.new }

  it "accepts any value by default" do
    expect { type.validate!("anything") }.not_to raise_error
    expect { type.validate!(nil) }.not_to raise_error
  end

  it "delegates to custom validator when provided" do
    calls = []
    validator = ->(value, options:, context:) { calls << [value, options, context] }

    type.validate!("ok", options: { validator: validator }, context: { key: :value })

    expect(calls.first[0]).to eq("ok")
    expect(calls.first[1][:validator]).to eq(validator)
    expect(calls.first[2]).to eq({ key: :value })
  end
end
