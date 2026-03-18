# frozen_string_literal: true

# Class for testing cacheable behavior
class CacheableOp
  include Gaskit::Core::Cacheable

  attr_reader :logger

  def initialize
    @logger = Gaskit::Logger.new(self.class)
  end

  cache_store nil, namespace: "cacheable_op"
end

RSpec.describe Gaskit::Core::Cacheable do
  before do
    Gaskit.configuration.cache_store(:memory)
    Gaskit.configuration.enforce_cache_store = false
  end

  let(:operation) { CacheableOp.new }

  it "instantiates a cache store with the configured namespace" do
    expect(operation.cache).to be_a(Gaskit::Stores::MemoryStore)
    operation.cache.write!("key", 1)
    expect(operation.cache.read!("key")).to eq(1)
  end

  it "prefetches keys and serves them from prefetched cache" do
    operation.cache.write!("prefetch", "value")
    operation.cache_prefetch!("prefetch")

    expect(operation.prefetched(operation.cache.namespace_key("prefetch"))).to eq("value")
  end

  it "returns default or block fallback when prefetched key missing" do
    operation.cache_prefetch!("missing")
    key = operation.cache.namespace_key("missing")
    expect(operation.prefetched(key, "default")).to eq("default")
    expect(operation.prefetched(key) { "block" }).to eq("block")
  end

  it "raises when cache is enforced but not configured" do
    CacheableOp.cache_store(:disabled)
    Gaskit.configuration.enforce_cache_store = true

    expect { CacheableOp.new.cache_prefetch!("key") }.to raise_error(Gaskit::Error, /No cache store/)
  ensure
    Gaskit.configuration.enforce_cache_store = false
    Gaskit.configuration.cache_store(:memory)
    CacheableOp.cache_store nil, namespace: "cacheable_op"
  end

  it "reports cache as disabled when configured as :disabled" do
    CacheableOp.cache_store(:disabled)
    expect(CacheableOp.new.cache_enabled?).to be false
  ensure
    CacheableOp.cache_store nil, namespace: "cacheable_op"
  end

  it "treats prefetched nil as a miss and falls back" do
    CacheableOp.reset_cache_store!
    CacheableOp.cache_store nil, namespace: "cacheable_op"
    op = CacheableOp.new
    op.cache_prefetch!("present_nil")
    key = op.cache.namespace_key("present_nil")
    op.prefetch_cache[key] = nil

    expect(op.prefetched(key, "fallback")).to eq("fallback")
    expect(op.prefetched(key) { "block" }).to eq("block")
  end

  it "allows overriding the cache store config" do
    CacheableOp.override_cache_store(name: :memory, namespace: "override", options: {})

    expect(CacheableOp.cache_store).to eq({ name: :memory, namespace: "override", options: {} })
  ensure
    CacheableOp.reset_cache_store!
    CacheableOp.cache_store nil, namespace: "cacheable_op"
  end

  it "logs and rescues errors during cache_prefetch" do
    logger = instance_double(Gaskit::Logger, warn: nil)
    allow(operation).to receive(:logger).and_return(logger)
    allow(operation).to receive(:cache_prefetch!).and_raise(StandardError, "boom")

    operation.cache_prefetch("key")

    expect(logger).to have_received(:warn).with("Cache prefetch failed: boom")
  end

  it "clears prefetched cache" do
    operation.prefetch_cache["key"] = "value"
    operation.clear_prefetched_cache!

    expect(operation.prefetch_cache).to eq({})
  end

  it "returns default store config when configured directly" do
    allow(Gaskit.configuration).to receive(:cache_store).and_return(Gaskit::Stores::MemoryStore)

    store_class, options = operation.send(:resolve_store_config)

    expect(store_class).to eq(Gaskit::Stores::MemoryStore)
    expect(options).to eq({})
  end
end
