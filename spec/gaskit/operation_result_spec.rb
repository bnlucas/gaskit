# frozen_string_literal: true

require "spec_helper"

RSpec.describe Gaskit::OperationResult do
  let(:value)    { "output" }
  let(:error)    { StandardError.new("something went wrong") }
  let(:context)  { { request_id: "abc123" } }
  let(:duration) { 0.123456789 }

  describe "#initialize" do
    it "stores success, value, error, duration, and context" do
      result = described_class.new(true, value, nil, duration: duration, context: context)

      expect(result.success).to be true
      expect(result.value).to eq(value)
      expect(result.error).to be_nil
      expect(result.duration).to eq("0.123457")
      expect(result.context).to eq(context)
    end

    it "accepts string durations" do
      result = described_class.new(true, value, nil, duration: "1.234", context: {})
      expect(result.duration).to eq("1.234000")
    end
  end

  describe "#success?, #failure?, #early_exit?, #status" do
    let(:early_exit) { Gaskit::OperationExit.new(:unauthorized, "blocked", code: "ERR-401") }

    it "returns correct booleans and status for success" do
      result = described_class.new(true, "ok", nil, duration: duration)
      expect(result.success?).to be true
      expect(result.failure?).to be false
      expect(result.early_exit?).to be false
      expect(result.status).to eq(:success)
    end

    it "returns correct booleans and status for failure" do
      result = described_class.new(false, nil, error, duration: duration)
      expect(result.success?).to be false
      expect(result.failure?).to be true
      expect(result.early_exit?).to be false
      expect(result.status).to eq(:failure)
    end

    it "returns correct booleans and status for early exit" do
      result = described_class.new(false, nil, early_exit, duration: duration)
      expect(result.success?).to be false
      expect(result.early_exit?).to be true
      expect(result.status).to eq(:early_exit)
    end
  end

  describe "#inspect" do
    it "returns a string with value and duration" do
      result = described_class.new(true, 42, nil, duration: 0.1)
      expect(result.inspect).to include("status=success")
      expect(result.inspect).to include("value=42")
      expect(result.inspect).to include("duration=0.100000")
    end
  end

  describe "#to_h" do
    it "includes value on success" do
      result = described_class.new(true, "ok", nil, duration: duration, context: context)

      expect(result.to_h).to eq(
        {
          success: true,
          status: :success,
          value: "ok",
          meta: {
            duration: "0.123457",
            context: context
          }
        }
      )
    end

    it "includes exit block on early exit" do
      exit = Gaskit::OperationExit.new(:forbidden, "no access", code: "403")
      result = described_class.new(false, nil, exit, duration: duration, context: context)

      expect(result.to_h).to eq(
        {
          success: false,
          status: :early_exit,
          exit: {
            key: :forbidden,
            message: "no access",
            code: "403"
          },
          meta: {
            duration: "0.123457",
            context: context
          }
        }
      )
    end

    it "includes error details on raised failure" do
      backtrace = ["line 1", "line 2"]
      error.set_backtrace(backtrace)

      result = described_class.new(false, nil, error, duration: duration, context: context)

      expect(result.to_h).to eq(
        {
          success: false,
          status: :failure,
          error: {
            type: "StandardError",
            message: "something went wrong",
            class: "StandardError",
            backtrace: backtrace
          },
          meta: {
            duration: "0.123457",
            context: context
          }
        }
      )
    end
  end
end
