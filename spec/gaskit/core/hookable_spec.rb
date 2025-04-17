# frozen_string_literal: true

require "concurrent"
require "gaskit/core/hookable"

RSpec.describe Gaskit::Core::Hookable do
  let(:dummy_class) do
    Class.new do
      include Gaskit::Core::Hookable
    end
  end

  describe "ClassMethods" do
    describe ".use_hooks" do
      before { dummy_class.use_hooks :test_hook }

      it "registers hooks with specific tags" do
        expect(dummy_class.registered_hooks).to include(:test_hook)
      end

      it "enables hooks when called" do
        expect(dummy_class.hooks_enabled?).to eq(true)
      end
    end

    describe ".use_hook" do
      it "registers a specific type of hook" do
        block = -> { puts 1 }

        dummy_class.use_hook :before, block
        expect(dummy_class.inline_hooks).to include(before: [block])
      end

      it "validates the hook type" do
        expect { dummy_class.use_hook :foobar, -> { puts 1 } }.to raise_error(ArgumentError)
      end

      it "validates the hook is callable" do
        expect { dummy_class.use_hook :before, 1 }.to raise_error(ArgumentError)
      end
    end

    describe ".before" do
      it "registers a `before` hook" do
        block = -> { puts 1 }
        dummy_class.before block

        expect(dummy_class.inline_hooks).to include(before: [block])
      end
    end

    describe ".around" do
      it "registers an `around` hook" do
        block = -> { puts 1 }
        dummy_class.around block

        expect(dummy_class.inline_hooks).to include(around: [block])
      end
    end

    describe ".after" do
      it "registers an `after` hook" do
        block = -> { puts 1 }
        dummy_class.after block

        expect(dummy_class.inline_hooks).to include(after: [block])
      end
    end

    describe ".hooks_enabled?" do
      it "returns whether hooks are enabled" do
        expect(dummy_class.hooks_enabled?).to eq(false)

        dummy_class.use_hooks :test_hook

        expect(dummy_class.hooks_enabled?).to eq(true)
      end
    end

    describe ".run_all_hooks?" do
      it "returns whether all hooks are set to run" do
        expect(dummy_class.run_all_hooks?).to eq(false)

        dummy_class.use_hooks :test_hook
        expect(dummy_class.run_all_hooks?).to eq(false)

        dummy_class.use_hooks
        expect(dummy_class.run_all_hooks?).to eq(true)
      end
    end

    describe ".registered_hooks" do
      it "returns the registered hooks" do
        expect(dummy_class.registered_hooks).to eq([])

        dummy_class.use_hooks :test_hook
        expect(dummy_class.registered_hooks).to eq([:test_hook])
      end
    end

    describe ".inline_hooks" do
      it "returns the inline hooks" do
        block = -> { puts 1 }

        expect(dummy_class.inline_hooks).to eq({})

        dummy_class.before block
        expect(dummy_class.inline_hooks).to eq({ before: [block] })
      end
    end
  end

  describe "InstanceMethods" do
    let(:instance) { dummy_class.new }

    describe "#apply_hooks" do
      before do
        dummy_class.before { @before_hook_ran = true }
        dummy_class.around do |inner|
          @around_hook_ran = true
          inner.call
        end
        dummy_class.after do |result|
          @after_hook_ran = true
          @after_result = result
        end
        dummy_class.use_hooks :any
      end

      it "applies hooks of specified types" do
        result = instance.apply_hooks(:before, :around, :after) { :ok }

        expect(result).to eq(:ok)
        expect(instance.instance_variable_get(:@before_hook_ran)).to eq(true)
        expect(instance.instance_variable_get(:@around_hook_ran)).to eq(true)
        expect(instance.instance_variable_get(:@after_hook_ran)).to eq(true)
        expect(instance.instance_variable_get(:@after_result)).to eq(:ok)
      end

      it "returns the result of the block" do
        result = instance.apply_hooks(:before, :around, :after) { 42 }
        expect(result).to eq(42)
      end
    end

    describe "#apply_before_hooks" do
      before do
        dummy_class.before { @value = "before!" }
        dummy_class.use_hooks :any
      end

      it "applies all `before` hooks" do
        instance.apply_before_hooks
        expect(instance.instance_variable_get(:@value)).to eq("before!")
      end
    end

    describe "#apply_around_hooks" do
      before do
        dummy_class.around do |block|
          @before_around = true
          result = block.call
          @after_around = true
          result
        end
        dummy_class.use_hooks :any
      end

      it "applies all `around` hooks" do
        result = instance.apply_around_hooks { "core result" }

        expect(result).to eq("core result")
        expect(instance.instance_variable_get(:@before_around)).to eq(true)
        expect(instance.instance_variable_get(:@after_around)).to eq(true)
      end
    end

    describe "#apply_after_hooks" do
      before do
        dummy_class.after do |result|
          @received_result = result
        end
        dummy_class.use_hooks :any
      end

      it "applies all `after` hooks" do
        instance.apply_after_hooks("final-result")
        expect(instance.instance_variable_get(:@received_result)).to eq("final-result")
      end
    end
  end
end
