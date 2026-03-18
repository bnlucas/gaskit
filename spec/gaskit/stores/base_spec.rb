# frozen_string_literal: true

# Test helper store for base store specs.
class DummyBaseStore < Gaskit::Stores::Base
  attr_reader :writes

  def initialize(namespace, logger:)
    super
    @data = {}
    @writes = 0
  end

  def key_exists?(key)
    @data.key?(key)
  end

  def read!(*keys, **_options)
    return @data[keys.first] if keys.size == 1

    keys.index_with { |k| @data[k] }
  end

  def write!(key, value, **_options) # rubocop:disable Naming/PredicateMethod
    @writes += 1
    @data[key] = value
    true
  end

  def delete!(*keys, **_options)
    keys.count { |key| @data.delete(key) }
  end

  def read_all!(*keys, **_options)
    keys.index_with { |k| @data[k] }
  end

  def write_all!(data, **_options) # rubocop:disable Naming/PredicateMethod
    data.each { |k, v| write!(k, v) }
    true
  end

  def flush_namespace!(**_options) # rubocop:disable Naming/PredicateMethod
    @data.clear
    true
  end
end

RSpec.describe Gaskit::Stores::Base do
  let(:logger) { instance_double(Gaskit::Logger, error: nil) }
  let(:store) { DummyBaseStore.new("ns", logger: logger) }

  it "builds namespaced keys" do
    expect(store.namespace_key("a")).to eq("ns:a")
    expect(store.namespace_pattern("a*")).to eq("ns:a*")
  end

  it "fetches cached values and avoids recomputation unless forced" do
    store.write!("key", 1)
    expect(store.fetch!("key") { 2 }).to eq(1)
    expect(store.fetch!("key", force: true) { 3 }).to eq(3)
    expect(store.writes).to be >= 2
  end

  it "does not write when fetch! block returns nil" do
    initial_writes = store.writes
    result = store.fetch!("missing") { nil }

    expect(result).to be_nil
    expect(store.writes).to eq(initial_writes)
  end

  it "wraps failures via safe operations" do
    allow(store).to receive(:read!).and_raise(StandardError, "boom")
    expect(store.read("key")).to be_nil
    expect(logger).to have_received(:error).with(/\[DummyBaseStore\] StandardError: boom/)
  end

  it "returns false on key_exists? when an error occurs" do
    allow(store).to receive(:key_exists!).and_raise(StandardError)
    expect(store.key_exists?("oops")).to be false
  end

  it "flushes the namespace via flush_namespace!" do
    store.write!("k", 1)
    expect(store.flush_namespace).to be true
    expect(store.read!("k")).to be_nil
  end

  describe "abstract methods" do
    let(:base) { described_class.new("ns") }

    it "raises for strict methods on the base class" do
      expect { base.key_exists?("a") }.to raise_error(NotImplementedError)
      expect { base.read!("a") }.to raise_error(NotImplementedError)
      expect { base.write!("a", 1) }.to raise_error(NotImplementedError)
      expect { base.delete!("a") }.to raise_error(NotImplementedError)
      expect { base.read_all!("a") }.to raise_error(NotImplementedError)
      expect { base.write_all!({ "a" => 1 }) }.to raise_error(NotImplementedError)
      expect { base.flush_namespace! }.to raise_error(NotImplementedError)
    end

    it "returns safe defaults for wrapper methods" do
      store = DummyBaseStore.new("ns", logger: logger)
      allow(store).to receive(:key_exists?).and_raise(StandardError, "boom")
      allow(store).to receive(:delete!).and_raise(StandardError, "boom")
      allow(store).to receive(:read_all!).and_raise(StandardError, "boom")
      allow(store).to receive(:write_all!).and_raise(StandardError, "boom")
      allow(store).to receive(:flush_namespace!).and_raise(StandardError, "boom")

      expect(store.key_exists!("a")).to be false
      expect(store.delete("a")).to be_nil
      expect(store.read_all("a")).to be_nil
      expect(store.write_all({ "a" => 1 })).to be_nil
      expect(store.flush_namespace).to be false
    end
  end
end
