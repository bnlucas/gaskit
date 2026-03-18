# frozen_string_literal: true

RSpec.describe Gaskit::Configuration do
  let(:config) { described_class.new }

  describe "#initialize" do
    it "initializes with default values" do
      expect(config.debug).to be false
      expect(config.disable_logging).to be false
      expect(config.logger).to be_a(Logger)
      expect(config.context_provider.call).to eq({})
    end
  end

  describe "#setup_logger" do
    let(:string_io) { StringIO.new }
    let(:custom_logger) { Logger.new(string_io) }

    it "sets a custom logger" do
      config.setup_logger(custom_logger)
      expect(config.logger).to eq(custom_logger)
    end

    it "sets the log level using a symbol" do
      config.setup_logger(custom_logger, level: :warn)
      expect(config.logger.level).to eq(Logger::WARN)
    end

    it "sets the log level using an integer" do
      config.setup_logger(custom_logger, level: Logger::ERROR)
      expect(config.logger.level).to eq(Logger::ERROR)
    end

    it "sets a custom formatter" do
      formatter = ->(_severity, _time, _progname, _msg) { "formatted" }
      config.setup_logger(custom_logger, formatter: formatter)
      expect(config.logger.formatter).to eq(formatter)
    end
  end

  describe "#log_formatter=" do
    it "raises if formatter is not callable" do
      expect { config.log_formatter = "not a proc" }.to raise_error(ArgumentError)
    end
  end

  describe "#context_provider=" do
    it "sets a valid context provider" do
      provider = -> { { user_id: 1 } }
      config.context_provider = provider
      expect(config.context_provider.call).to eq({ user_id: 1 })
    end

    it "raises if provider is not callable" do
      expect { config.context_provider = "not a proc" }.to raise_error(ArgumentError)
    end
  end

  describe "#cache_store" do
    it "configures redis store when requested" do
      store_config = config.cache_store(:redis)

      expect(store_config[:store]).to eq(Gaskit::Stores::RedisStore)
    end

    it "raises for unsupported cache store types" do
      expect { config.cache_store(:unknown) }.to raise_error(ArgumentError, /Unsupported cache_store type/)
    end
  end

  describe "#register_cache_store and #fetch_cache_store" do
    it "registers and fetches a custom store" do
      custom_store = Class.new(Gaskit::Stores::Base) do
        def read_all!(*)
          {}
        end

        def initialize(namespace, logger: nil, **_options)
          super(namespace, logger: logger)
        end
      end

      config.register_cache_store(:custom_spec_store, custom_store)

      expect(config.fetch_cache_store(:custom_spec_store)).to eq(custom_store)
    end
  end

end
