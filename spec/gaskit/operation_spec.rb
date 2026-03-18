# frozen_string_literal: true

require "gaskit/operation"

RSpec.shared_examples "successful operation" do |method|
  it "executes the operation and returns a successful result" do
    result = success_class.public_send(method, 1, 2)

    expect(result).to be_success
    expect(result.value).to eq(3)
    expect(result.error).to be_nil
  end
end

RSpec.shared_examples "operation exit" do |error_key:, expected_key:, expected_message: nil, expected_code: nil|
  let(:dummy_class) do
    Class.new(Gaskit::Operation) do
      error :registered_error, "registered error", code: 123

      define_method(:call) do
        if expected_message
          exit(error_key, expected_message)
        else
          exit(error_key)
        end
      end
    end
  end

  it "terminates the operation early with the correct attributes" do
    exit_hash = {
      key: expected_key,
      message: expected_message || "early exit",
      code: expected_code
    }.compact

    result = dummy_class.call

    expect(result).to be_failure
    expect(result.early_exit?).to be_truthy
    expect(result.to_h[:exit]).to eq(exit_hash)
  end
end

RSpec.describe Gaskit::Operation do
  describe "Class Methods" do
    describe ".error" do
      let(:dummy_class) { Class.new(described_class) }

      it "registers an error with the given key, message, and optional code" do
        dummy_class.error :dummy_error, "dummy error", code: 123
        expect(dummy_class.errors_registry).to include(dummy_error: { message: "dummy error", code: 123 })
      end

      it "raises an error if the error key is not a symbol" do
        key = 1
        expect do
          dummy_class.error key, "invalid error key"
        end.to raise_error(ArgumentError, "Error key must be a symbol or a string, received #{key}")
      end

      it "raises an error if invalid error arguments are passed" do
        expect do
          dummy_class.error :dummy_error, nil
        end.to raise_error(ArgumentError, "Error message must be a string")
      end

      it "raises an error if the error key is already registered" do
        dummy_class.error :dummy_error, "dummy error"

        expect do
          dummy_class.error :dummy_error, "new dummy error"
        end.to raise_error(ArgumentError, "Error key :dummy_error is already registered")
      end

      it "allows threads to register errors without interference" do
        threads = []
        3.times do |i|
          threads << Thread.new { dummy_class.error :"error_#{i}", "error #{i}" }
        end
        threads.each(&:join)

        # rubocop:disable Naming/VariableNumber
        expect(dummy_class.errors_registry.keys).to contain_exactly(:error_0, :error_1, :error_2)
        # rubocop:enable Naming/VariableNumber
      end
    end

    describe ".call" do
      let(:context) { { test_key: "test_value" } }
      let(:success_class) do
        Class.new(described_class) do
          def call(num_a, num_b)
            num_a + num_b
          end
        end
      end

      before do
        allow(Gaskit::Helpers).to receive(:time_execution).and_call_original
      end

      context "when the operation is successful" do
        it_behaves_like "successful operation", :call
      end

      context "when the operation fails" do
        let(:failed_class) do
          Class.new(described_class) do
            def call
              raise "boom!"
            end
          end
        end

        it "catches and returns a failure result" do
          result = failed_class.call(context: context)

          expect(result).to be_failure
          expect(result.error).to be_an_instance_of(RuntimeError)
          expect(result.error.message).to eq("boom!")
        end
      end

      context "when hooks are defined" do
        let(:hooked_class) do
          Class.new(described_class) do
            before { self.class.hook_events << "before" }
            around do |block|
              self.class.hook_events << "around before"
              result = block.call
              self.class.hook_events << "around after"

              result
            end
            after { |result| self.class.hook_events << "after: #{result.value}" }

            def call
              :ok
            end

            def self.hook_events
              @hook_events ||= []
            end
          end
        end

        it_behaves_like "successful operation", :call

        it "executes the hooks before the operation" do
          result = hooked_class.call(context: context)

          expect(result).to be_success
          expect(result.value).to eq(:ok)

          events = ["before", "around before", "around after", "after: #{result.value}"]
          expect(hooked_class.hook_events).to eq(events)
        end
      end

      context "when a before hook raises an error" do
        it_behaves_like "a failing hook for call", :before
      end

      context "when an around hook raises an error" do
        it_behaves_like "a failing hook for call", :around
      end

      context "when an after hook raises an error" do
        it_behaves_like "a failing hook for call", :after
      end
    end

    describe ".call!" do
      let(:context) { { test_key: "test_value" } }
      let(:success_class) do
        Class.new(described_class) do
          def call(num_a, num_b)
            num_a + num_b
          end
        end
      end

      before do
        allow(Gaskit::Helpers).to receive(:time_execution).and_call_original
      end

      context "when the operation is successful" do
        it_behaves_like "successful operation", :call!
      end

      context "when the operation fails" do
        let(:failed_class) do
          Class.new(described_class) do
            def call
              raise "boom!"
            end
          end
        end

        it "raises an error on failure if exceptions are unhandled" do
          expect { failed_class.call!(context: context) }.to raise_error(RuntimeError, /boom!/)
        end
      end

      context "when a before hook raises an error" do
        it_behaves_like "a failing hook for call!", :before
      end

      context "when an around hook raises an error" do
        it_behaves_like "a failing hook for call!", :around
      end

      context "when an after hook raises an error" do
        it_behaves_like "a failing hook for call!", :after
      end
    end
  end

  describe "Instance Methods" do
    describe "#initialize" do
      let(:operation) do
        Class.new(described_class) do
          def call
            :ok
          end
        end
      end

      it "sets raise_on_failure to false" do
        instance = operation.new(false)

        expect(instance.raise_on_failure?).to eq(false)
      end

      it "sets raise_on_failure to true" do
        instance = operation.new(true)

        expect(instance.raise_on_failure?).to eq(true)
      end

      it "assigns a logger instance to the operation" do
        instance = operation.new(false)

        expect(instance.logger).to be_a(Gaskit::Logger)
      end
    end

    describe "#call" do
      it "returns a failure result when not implemented by subclass" do
        result = described_class.call

        expect(result).to be_failure
        expect(result.error).to be_a(NotImplementedError)
      end
    end

    describe "#exit" do
      it_behaves_like "operation exit",
                      error_key: :registered_error,
                      expected_key: :registered_error,
                      expected_message: "registered error",
                      expected_code: 123

      it_behaves_like "operation exit",
                      error_key: :registered_error,
                      expected_key: :registered_error,
                      expected_message: "overridden message",
                      expected_code: 123

      it_behaves_like "operation exit",
                      error_key: :unregistered_error,
                      expected_key: :unregistered_error

      it_behaves_like "operation exit",
                      error_key: :unregistered_error,
                      expected_key: :unregistered_error,
                      expected_message: "error message"
    end
  end

  describe "#abort" do
    let(:operation) do
      Class.new(described_class) do
        def call
          abort(:unauthorized, "blocked", code: "ERR-401")
        end
      end
    end

    it "calls exit with the given key and message" do
      result = operation.call

      expect(result).to be_failure
      expect(result.early_exit?).to be_truthy
      expect(result.to_h[:exit]).to eq({
                                         key: :unauthorized,
                                         message: "blocked",
                                         code: "ERR-401"
                                       })
    end
  end
end
