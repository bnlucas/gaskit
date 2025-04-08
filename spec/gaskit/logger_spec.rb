# frozen_string_literal: true

require "spec_helper"

RSpec.describe Gaskit::Logger do
  let(:string_io) { StringIO.new }
  let(:ruby_logger) { Logger.new(string_io) }
  let(:logger) { described_class.new("String", context: { global: "ctx" }) }

  before do
    Gaskit.config do |c|
      c.setup_logger(ruby_logger, formatter: Gaskit::Logger.pretty_formatter)
      c.context_provider = -> { { global: "ctx" } }
    end
  end

  after do
    string_io.rewind
    string_io.truncate(0)
  end

  describe "#initialize" do
    it "sets up the logger with class context" do
      gaskit_logger = described_class.new(String, context: { request_id: "123" })
      expect(gaskit_logger.context).to include(global: "ctx", request_id: "123")
    end
  end

  describe "#log" do
    it "logs a formatted message with merged context" do
      gaskit_logger = described_class.new("TestOp", context: { user_id: 42 })
      gaskit_logger.info("It works", context: { action: "run" })

      last_log_line = string_io.string
      expect(last_log_line).to include("It works")
      expect(last_log_line).to include("user_id=42")
      expect(last_log_line).to include("action=run")
      expect(last_log_line).to include("TestOp")
    end

    it "supports block messages" do
      gaskit_logger = described_class.new("TestOp")
      gaskit_logger.debug(context: { details: "extra" }) { "Deferred log" }

      last_log_line = string_io.string
      expect(last_log_line).to include("Deferred log")
      expect(last_log_line).to include("details=extra")
    end
  end

  describe "#with_context" do
    it "creates a logger with extra merged context" do
      logger1 = described_class.new("Op", context: { a: 1 })
      logger2 = logger1.with_context(b: 2)

      expect(logger2).to be_a(described_class)
      expect(logger2.context).to include(a: 1, b: 2)
    end
  end

  describe ".formatter" do
    it "returns json formatter" do
      formatter = described_class.formatter(:json)
      result = formatter.call("INFO", Time.now, nil, ["Hello", { user_id: 1 }])
      expect(result).to include("\"message\":\"Hello\"")
      expect(result).to include("\"user_id\":1")
    end

    it "returns pretty formatter" do
      formatter = described_class.formatter(:pretty)
      result = formatter.call("INFO", Time.now, nil, ["Hello", { user_id: 1 }])
      expect(result).to include("Hello")
      expect(result).to include("user_id=1")
    end

    it "raises error for unknown formatter" do
      expect do
        described_class.formatter(:foo)
      end.to raise_error(ArgumentError, /Invalid log formatter/)
    end
  end
end
