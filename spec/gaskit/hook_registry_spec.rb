# frozen_string_literal: true

RSpec.describe Gaskit::HookRegistry do
  let(:registry) { described_class.new }

  describe "#register" do
    it "registers a before hook with a tag" do
      hook = ->(op) { op }
      registry.register(:before, :audit, hook)

      expect(registry.registered?(:before, :audit)).to be true
      expect(registry.fetch(:before, [:audit])).to include(hook)
    end

    it "registers an after hook with a block" do
      registry.register(:after, :metrics) { puts "hooked" }

      hooks = registry.fetch(:after, [:metrics])
      expect(hooks.size).to eq(1)
      expect(hooks.first).to be_a(Proc)
    end

    it "raises an error if hook is not callable" do
      expect do
        registry.register(:before, :bad, "not callable")
      end.to raise_error(ArgumentError, /respond to #call/)
    end

    it "raises an error if hook type is invalid" do
      expect do
        registry.register(:invalid, :tag) { puts "hooked" }
      end.to raise_error(ArgumentError, /Unknown hook type/)
    end
  end

  describe "#registered?" do
    it "returns true if the tag is registered under the type" do
      registry.register(:before, :logging) { puts "hooked" }
      expect(registry.registered?(:before, :logging)).to be true
    end

    it "returns false for unregistered tags" do
      expect(registry.registered?(:after, :nonexistent)).to be false
    end
  end

  describe "#fetch" do
    let(:hook_one) { ->(_) { :hook_one } }
    let(:hook_two) { ->(_) { :hook_two } }

    before do
      registry.register(:before, :one, hook_one)
      registry.register(:before, :two, hook_two)
    end

    it "returns all hooks when no tags are provided" do
      hooks = registry.fetch(:before)

      expect(hooks).to all(respond_to(:call))
      expect(hooks.map { |h| h.call(nil) }).to contain_exactly(:hook_one, :hook_two)
    end

    it "returns only hooks for specified tags" do
      hooks = registry.fetch(:before, [:one])
      expect(hooks.map { |h| h.call(nil) }).to eq([:hook_one])
    end

    it "returns an empty array if none match" do
      hooks = registry.fetch(:before, [:not_found])
      expect(hooks).to eq([])
    end
  end

  describe "#registered" do
    it "returns all registered tags for the given type" do
      registry.register(:around, :timing) { puts "hooked" }
      registry.register(:around, :trace) { puts "hooked" }

      expect(registry.registered_tags(:around)).to contain_exactly(:timing, :trace)
    end
  end

  describe "#reset!" do
    it "reinitializes hook storage with default buckets" do
      registry.register(:before, :audit) { :ok }
      registry.reset!

      expect(registry.send(:hooks)[:before][:missing]).to eq([])
    end
  end

  describe "lazy hooks initialization" do
    it "builds the default hook buckets when uninitialized" do
      registry.instance_variable_set(:@hooks, nil)
      hooks = registry.send(:hooks)

      expect(hooks[:before][:missing]).to eq([])
      expect(hooks[:after][:missing]).to eq([])
      expect(hooks[:around][:missing]).to eq([])
    end
  end
end
