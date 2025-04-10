# frozen_string_literal: true

require "spec_helper"
require "gaskit/operation"

class DummyResult < Gaskit::OperationResult; end

RSpec.shared_examples "successful operation" do |method|
  it "executes the operation and returns a successful result" do
    result = success_class.public_send(method, 1, 2)

    expect(result).to be_success
    expect(result.value).to eq(3)
    expect(result.error).to be_nil
  end
end

RSpec.shared_examples "a failing hook for call" do |hook_type|
  let(:failing_hook_class) do
    Class.new(described_class) do
      send(hook_type) { raise "hook failed!" }
      use_contract :result_class

      def call(num_a, num_b)
        num_a + num_b
      end
    end
  end

  it "catches the failure result" do
    result = failing_hook_class.call(1, 2, context: context)

    expect(result).to be_failure
    expect(result.error.message).to eq("hook failed!")
  end
end

RSpec.shared_examples "a failing hook for call!" do |hook_type|
  let(:failing_hook_class) do
    Class.new(described_class) do
      send(hook_type) { raise "hook failed!" }
      use_contract :result_class

      def call(num_a, num_b)
        num_a + num_b
      end
    end
  end

  it "raises the error" do
    expect { failing_hook_class.call!(1, 2, context: context) }
      .to raise_error(RuntimeError, "hook failed!")
  end
end

RSpec.shared_examples "operation exit" do |error_key:, expected_key:, expected_message: nil, expected_code: nil|
  let(:dummy_class) do
    Class.new(Gaskit::Operation) do
      use_contract result: DummyResult
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

  it "terminated the operation early with the correct attributes" do
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
  let(:result_class) { DummyResult }
  let(:dummy_class) { Class.new(described_class) }
  let(:operation_instance) { dummy_class.new(false, context: { test_key: "test_value" }) }

  before(:all) do
    Gaskit.contracts.register(:result_class, DummyResult)
  end

  describe "Class Methods" do
    describe ".result_class" do
      let(:superclass) { Class.new(described_class) }
      let(:subclass) { Class.new(superclass) }

      before do
        superclass.use_contract result: result_class
      end

      it "returns the result class for the operation" do
        expect(subclass.result_class).to eq(result_class)
      end

      it "inherits the result class from the superclass if undefined" do
        expect(superclass.result_class).to eq(result_class)
        expect(superclass.result_class).to eq(subclass.result_class)
      end
    end

    describe ".use_contract" do
      it "sets the result class from a registered contract" do
        dummy_class.use_contract :result_class

        expect(dummy_class.result_class).to eq(result_class)
      end

      it "validates the contract argument as a symbol" do
        expect { dummy_class.use_contract "not_a_symbol" }.to raise_error(ArgumentError)
      end

      it "raises an error if the result class is invalid" do
        expect { dummy_class.use_contract result: "not_a_class" }.to raise_error(ArgumentError)
      end
    end

    describe ".error" do
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

    describe ".errors_registry" do
      let(:registered_errors) do
        {
          dummy_error_a: {
            message: "dummy error a", code: 123
          },
          dummy_error_b: {
            message: "dummy error b", code: 321
          }
        }
      end

      before do
        registered_errors.each do |key, value|
          dummy_class.error key, value[:message], code: value[:code]
        end
      end

      it "returns the registry of declared errors" do
        expect(dummy_class.errors_registry).to eq(registered_errors)
      end
    end

    describe ".call" do
      let(:context) { { test_key: "test_value" } }
      let(:success_class) do
        Class.new(described_class) do
          use_contract :result_class

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
            use_contract :result_class

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
            use_contract :result_class

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
          use_contract :result_class

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
            use_contract :result_class

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
          use_contract :result_class
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
      it "raises NotImplementedError if not implemented by subclass" do
        expect { described_class.call }.to raise_error(NotImplementedError)
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
        use_contract :result_class
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

  describe "Private Class Methods" do
    describe ".invoke" do
      let(:context) { { test_key: "test_value" } }
      let(:context_provider) { -> { { global_key: "global_value" } } }

      before do
        allow(Gaskit.configuration).to receive(:context_provider).and_return(context_provider)
      end

      context "when context is provided" do
        let(:operation_class) do
          Class.new(described_class) do
            use_contract :result_class

            def call
              :ok
            end
          end
        end

        it "merges the provided context with the global context" do
          result = operation_class.call(context: context)

          expect(result).to be_success
          expect(result.context).to eq(context.merge(global_key: "global_value"))
        end
      end

      context "when subclass overrides the result contract" do
        let!(:custom_result) { Class.new(Gaskit::OperationResult) }
        let(:parent_operation) do
          Class.new(described_class) do
            use_contract :result_class
          end
        end

        it "uses the result class from the subclass" do
          child_operation = Class.new(parent_operation)
          child_operation.use_contract result: custom_result

          expect(child_operation.result_class).to eq(custom_result)
        end

        it "fails if the result class is not a subclass of Gaskit::OperationResult" do
          child_operation = Class.new(parent_operation)

          expect { child_operation.use_contract(result: Object) }.to raise_error(Gaskit::ResultTypeError)
        end
      end
    end
  end
end
