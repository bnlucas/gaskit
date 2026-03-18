# frozen_string_literal: true

RSpec.shared_examples "a failing hook for call" do |hook_type|
  let(:failing_hook_class) do
    Class.new(described_class) do
      send(hook_type) { raise "hook failed!" }

      define_method(:call) do |a = nil, b = nil, **_kwargs|
        if self.class.superclass <= Gaskit::Operation
          (a || 0) + (b || 0)
        else
          a
        end
      end
    end
  end

  it "catches the failure result" do
    args = described_class <= Gaskit::Operation ? [1, 2] : [1]
    result = failing_hook_class.call(*args)

    expect(result).to be_failure
    expect(result.error.message).to eq("hook failed!")
  end
end

RSpec.shared_examples "a failing hook for call!" do |hook_type|
  let(:failing_hook_class) do
    Class.new(described_class) do
      send(hook_type) { raise "hook failed!" }

      define_method(:call) do |a = nil, b = nil, **_kwargs|
        if self.class.superclass <= Gaskit::Operation
          (a || 0) + (b || 0)
        else
          a
        end
      end
    end
  end

  it "raises the error" do
    args = described_class <= Gaskit::Operation ? [1, 2] : [1]
    expect { failing_hook_class.call!(*args) }.to raise_error(RuntimeError, "hook failed!")
  end
end
