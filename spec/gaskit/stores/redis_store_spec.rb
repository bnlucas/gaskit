# frozen_string_literal: true

# Minimal fake Redis client to exercise RedisStore without a real server.
class FakeRedis
  def initialize
    @data = {}
    @ttl = {}
  end

  def exists?(key)
    value = @data[key]
    expires_at = @ttl[key]
    return false if expires_at && Time.now.to_f >= expires_at

    !value.nil?
  end

  def mset(*args)
    args.each_slice(2) do |key, value|
      @data[key] = value
    end
    "OK"
  end

  def mget(*keys)
    keys.map do |key|
      value = @data[key]
      expires_at = @ttl[key]
      expires_at && Time.now.to_f >= expires_at ? nil : value
    end
  end

  def expire(key, ttl) # rubocop:disable Naming/PredicateMethod
    @ttl[key] = Time.now.to_f + ttl
    true
  end

  def del(*keys)
    keys.flatten.each { |key| @data.delete(key) }
    keys.length
  end

  def scan(_cursor, match:, count:)
    pattern = Regexp.new("^#{match.gsub("*", ".*")}$")
    matched = @data.keys.grep(pattern)
    ["0", matched.first(count)]
  end

  def multi
    result = yield(self)
    [result]
  end
end

RSpec.describe Gaskit::Stores::RedisStore do
  let(:redis) { FakeRedis.new }
  let(:store) { described_class.new("ns", redis) }

  it "writes and reads values with namespacing" do
    store.write!("user", { id: 1 })
    expect(store.read!("user")).to eq({ "id" => 1 })
    expect(store.key_exists?("user")).to be true
  end

  it "supports ttl on write_all!" do
    store.write_all!({ "a" => 1 }, ttl: 1)
    expect(store.read!("a")).to eq(1)

    allow(Time).to receive(:now).and_return(Time.at(Time.now.to_i + 2))
    expect(store.read!("a")).to be_nil
  end

  it "deletes keys and wildcards via flush" do
    store.write_all!({ "one" => 1, "two" => 2 })
    expect(store.delete!("one")).to eq(1)

    store.flush_namespace!
    expect(store.read!("two")).to be_nil
  end

  it "supports wildcard reads" do
    store.write_all!({ "one" => 1, "two" => 2 })
    results = store.read_all!("*")

    expect(results).to include("ns:one" => 1, "ns:two" => 2)
  end

  it "purges corrupted data when purge_on_error is true" do
    redis.mset("ns:bad", "junk")

    results = store.read_all!("bad", purge_on_error: true)
    expect(results["ns:bad"]).to be_nil
    expect(redis.exists?("ns:bad")).to be false
  end

  it "raises when fail_on_error is true" do
    redis.mset("ns:bad", "junk")
    expect { store.read_all!("bad", purge_on_error: false, fail_on_error: true) }
      .to raise_error(StandardError)
  end

  it "returns nil for corrupted data when purge_on_error is false" do
    redis.mset("ns:bad", "junk")
    results = store.read_all!("bad", purge_on_error: false, fail_on_error: false)

    expect(results["ns:bad"]).to be_nil
    expect(redis.exists?("ns:bad")).to be true
  end

  it "returns false when key_exists! encounters an error" do
    error_store = Class.new(described_class) do
      def key_exists?(_key)
        raise StandardError, "boom"
      end
    end.new("ns", FakeRedis.new)

    expect(error_store.key_exists!("user")).to be false
  end

  it "returns nil when read encounters an error" do
    allow(store).to receive(:read!).and_raise(StandardError, "boom")

    expect(store.read("user")).to be_nil
  end

  it "returns nil when read_all encounters an error" do
    allow(store).to receive(:read_all!).and_raise(StandardError, "boom")

    expect(store.read_all("user")).to be_nil
  end
end
