# frozen_string_literal: true

RSpec.describe Gaskit::Stores::MemoryStore do
  let(:store) { described_class.new("ns") }

  it "writes and reads values in the namespace" do
    store.write!("user", 1)
    store.write!("token", "abc")

    expect(store.read!("user")).to eq(1)
    expect(store.read!("token")).to eq("abc")
    expect(store.key_exists?("user")).to be true
  end

  it "supports fetch helpers and force recompute" do
    computed = store.fetch("calc", 10)
    expect(computed).to eq(10)
    expect(store.read!("calc")).to eq(10)

    forced = store.fetch("calc", force: true) { 20 }
    expect(forced).to eq(20)
    expect(store.read!("calc")).to eq(20)
  end

  it "expires keys based on ttl" do
    allow(Time).to receive(:now).and_return(Time.at(1000))
    store.write!("short", "v", ttl: 5)

    allow(Time).to receive(:now).and_return(Time.at(1006))
    expect(store.read!("short")).to be_nil
    expect(store.key_exists?("short")).to be false
  end

  it "flushes only the current namespace" do
    other = described_class.new("other")
    store.write!("a", 1)
    other.write!("a", 2)

    store.flush_namespace!

    expect(store.read!("a")).to be_nil
    expect(other.read!("a")).to eq(2)
  end

  it "deletes keys in the namespace" do
    store.write!("delete_me", 1)

    store.delete!("delete_me")

    expect(store.read!("delete_me")).to be_nil
  end
end
