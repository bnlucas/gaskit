# frozen_string_literal: true

require "gaskit/types/symbol"

RSpec.describe Gaskit::Types::Symbol do
  let(:type) { described_class.new }

  it "deserializes strings to symbols" do
    expect(type.deserialize("foo")).to eq(:foo)
    expect(type.deserialize(:bar)).to eq(:bar)
    expect(type.deserialize(nil)).to be_nil
  end

  it "raises attribute error on invalid input" do
    expect { type.validate!(123) }.to raise_error(Castkit::AttributeError)
  end

  it "raises type error on deserialize when to_sym is unavailable" do
    expect { type.deserialize(Object.new) }.to raise_error(Castkit::AttributeError)
  end

  it "returns nil when deserialize fails and type_error is silenced" do
    allow(type).to receive(:type_error!).and_return(nil)
    expect(type.deserialize(Object.new)).to be_nil
  end
end
