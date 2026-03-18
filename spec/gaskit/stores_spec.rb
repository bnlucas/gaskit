# frozen_string_literal: true

require "gaskit/stores"

# Custom store for testing purposes
class DummyStore < Gaskit::Stores::Base
  def key_exists?(_key)
    false
  end

  def read_all!(*_keys, **_options)
    {}
  end

  def write_all!(_data, **_options) # rubocop:disable Naming/PredicateMethod
    true
  end

  def delete!(*_keys, **_options)
    0
  end

  def flush_namespace!(**_options) # rubocop:disable Naming/PredicateMethod
    true
  end
end

RSpec.describe Gaskit::Stores do
  it "fetches default stores" do
    expect(described_class.fetch(:memory)).to eq(Gaskit::Stores::MemoryStore)
    expect(described_class.fetch(:redis)).to eq(Gaskit::Stores::RedisStore)
  end

  it "registers and fetches custom stores" do
    described_class.register(:dummy, DummyStore)
    expect(described_class.fetch(:dummy)).to eq(DummyStore)
  end

  it "raises when registering non-store classes" do
    expect { described_class.register(:bad, Object) }.to raise_error(Gaskit::Error)
  end

  it "raises on unknown store when enforcement enabled" do
    previous = Gaskit.configuration.enforce_cache_store
    Gaskit.configuration.enforce_cache_store = true
    expect { described_class.fetch(:unknown) }.to raise_error(ArgumentError)
  ensure
    Gaskit.configuration.enforce_cache_store = previous
  end

  it "falls back to memory when enforcement disabled" do
    previous = Gaskit.configuration.enforce_cache_store
    Gaskit.configuration.enforce_cache_store = false
    expect(described_class.fetch(:unknown)).to eq(Gaskit::Stores::MemoryStore)
  ensure
    Gaskit.configuration.enforce_cache_store = previous
  end
end
