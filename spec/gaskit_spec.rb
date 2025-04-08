# frozen_string_literal: true

require "spec_helper"

RSpec.describe Gaskit do
  let(:result_class) { Class.new(Gaskit::OperationResult) }

  it "has a version number" do
    expect(Gaskit::VERSION).not_to be nil
  end

  it "runs an operation end-to-end and logs correctly" do
    logs = StringIO.new

    Gaskit.config do |c|
      c.setup_logger(Logger.new(logs), level: Logger::DEBUG)
      c.context_provider = -> { { global: true } }
      c.disable_logging = false
      c.register_contract(:dummy_type, result_class, override: true)
    end

    klass = Class.new(Gaskit::Operation) do
      use_contract :dummy_type

      def call
        logger.info("Doing something")
        "done"
      end
    end

    result = klass.call

    logs.rewind
    log_output = logs.string

    expect(result.success?).to be true
    expect(result.value).to eq("done")
    expect(log_output).to include("Doing something")
    expect(log_output).to include("global")
  end
end
