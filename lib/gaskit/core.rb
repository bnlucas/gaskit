# frozen_string_literal: true

require_relative "configuration"
require_relative "core/cacheable"
require_relative "core/hookable"

module Gaskit
  class << self
    # Configures the Gaskit system.
    #
    # This yields the configuration instance, allowing you to modify settings such as logger,
    # global context, log level, and formatting.
    #
    # @yieldparam [Gaskit::Configuration] configuration
    # @return [void]
    def config
      yield(configuration)
    end

    # Retrieves the global Gaskit configuration.
    #
    # @return [Gaskit::Configuration] the configuration instance
    def configuration
      @configuration ||= Configuration.new
    end

    # Returns configuration.debug.
    #
    # @return [Boolean] `true` is Gaskit is set to debug, `false` otherwise.
    def debug?
      Gaskit.configuration.debug
    end

    # Returns configuration.hooks.
    #
    # @return [Gaskit::HookRegistry] The HookRegistry instance.
    def hooks
      configuration.hooks
    end
  end
end
