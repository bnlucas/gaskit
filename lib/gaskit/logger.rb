# frozen_string_literal: true

require "logger"
require "json"
require "time"
require "English"
require "cattri"

require_relative "helpers"

module Gaskit
  # A logger class designed for structured logging with support for JSON, contextual data,
  # and environment-aware formatting.
  #
  # This logger wraps a configurable `Logger` instance and supports:
  #
  # - Structured or human-readable log formatting
  # - Inclusion of global and per-call context (with filtering of sensitive keys)
  # - Support for custom log levels, formatters, and disabling output via `Gaskit.config`
  #
  # By default, logs are pretty-printed in development and JSON-formatted in production.
  # These defaults can be overridden via configuration.
  #
  # @example Basic usage with default formatting
  #   logger = Gaskit::Logger.new('MyOperation', context: { user_id: 42 })
  #
  #   logger.info("Operation started")
  #   logger.debug(context: { details: "debug info" }) { "Deferred message" }
  #
  # @example Using logger within a class
  #   class UserRepository
  #     def self.logger
  #       @logger ||= Gaskit::Logger.new(self)
  #     end
  #
  #     def self.find(id)
  #       logger.info("Looking up user", context: { user_id: id })
  #     end
  #   end
  #
  # @example Customizing the log formatter globally
  #   Gaskit.config do |c|
  #     c.log_formatter = ->(severity, time, _progname, msg) do
  #       message, ctx = msg.is_a?(Array) ? msg : [msg, {}]
  #       "[#{time.strftime('%T')}] #{severity}: #{message} #{ctx.to_json}\n"
  #     end
  #   end
  #
  # @example Configuring JSON or pretty formatters
  #   Gaskit.config do |c|
  #     c.setup_logger(Logger.new($stdout), formatter: Gaskit::Logger.formatter(:json))
  #   end
  #
  #   # or
  #
  #   Gaskit.config do |c|
  #     c.setup_logger(Logger.new($stdout), formatter: Gaskit::Logger.formatter(:pretty))
  #   end
  #
  # @example Disabling logs entirely
  #   Gaskit.config do |c|
  #     c.disable_logging = true
  #   end
  #
  # @see Gaskit::Configuration
  class Logger
    include Cattri

    final_cattri :context, -> { {} }

    SENSITIVE_KEYS = %i[email ip_address password auth_token secret ssn jwt token].freeze

    class << self
      # Returns a built-in log formatter.
      #
      # Use this method to obtain either the JSON or pretty formatter for logs.
      # This is useful when customizing the logger via `Gaskit.config`.
      #
      # @example Use JSON formatter
      #   Gaskit.config do |c|
      #     c.setup_logger(Logger.new($stdout), formatter: Gaskit::Logger.formatter(:json))
      #   end
      #
      # @example Use pretty formatter
      #   Gaskit.config do |c|
      #     c.setup_logger(Logger.new($stdout), formatter: Gaskit::Logger.formatter(:pretty))
      #   end
      #
      # @param formatter [Symbol] The formatter type to use (`:json` or `:pretty`)
      # @return [Proc] A formatter proc suitable for use with `Logger#formatter`
      # @raise [ArgumentError] If an unknown formatter symbol is provided
      def formatter(formatter = :pretty)
        case formatter
        when :json
          json_formatter
        when :pretty
          pretty_formatter
        else
          raise ArgumentError, "Invalid log formatter: #{formatter}"
        end
      end

      # JSON formatter (for production or structured logs)
      #
      # @return [Proc] The formatter callable.
      def json_formatter
        lambda do |severity, time, _progname, msg|
          message, context = extract_message_and_context(msg)

          log_entry = {
            timestamp: time.utc.iso8601,
            level: severity.downcase,
            class: context[:class],
            message: message,
            context: context&.reject { |k| k == :duration }
          }.compact

          log_entry[:duration] = context[:duration] if context&.key?(:duration)

          "#{JSON.dump(log_entry)}\n"
        end
      end

      # Pretty formatter (for dev logs)
      #
      # @return [Proc] The formatter callable.
      def pretty_formatter
        lambda do |severity, time, _progname, msg|
          message, context = extract_message_and_context(msg)
          context ||= {}
          class_name = context.delete(:class)

          tags = %W[[#{time.utc.iso8601}] [#{severity}]]
          tags << "[#{class_name}]" if class_name
          tags += flatten_context(context).map { |k, v| "[#{k}=#{v}]" }

          "#{tags.join(" ")} #{message}\n"
        end
      end

      private

      # Extracts the message and context from a log payload.
      #
      # @param msg [Object] The payload passed to the logger.
      # @return [Array] An array with the message and context.
      def extract_message_and_context(msg)
        return [msg[0], msg[1]] if msg.is_a?(Array) && msg.size == 2

        [msg.to_s, {}]
      end

      # Recursively flattens a nested hash by concatenating keys using underscores.
      #
      # @example
      #   flatten_context({ a: { b: 1, c: { d: 2 } } })
      #   # => { "a_b" => 1, "a_c_d" => 2 }
      #
      # @param hash [Hash] The hash to flatten.
      # @param prefix [String, nil] The prefix to prepend to keys (used during recursion).
      # @return [Hash] A flat hash with underscore-separated keys.
      def flatten_context(hash, prefix = nil)
        result = {}

        hash.each do |key, value|
          full_key = prefix ? "#{prefix}_#{key}" : key.to_s

          if value.is_a?(Hash)
            result.merge!(flatten_context(value, full_key))
          else
            result[full_key] = value
          end
        end

        result
      end
    end

    # Initializes a new logger instance.
    #
    # @param klass [Class, Object, String, Symbol] The name of the class being logged.
    # @param context [Hash] Optional additional context to include in every log entry.
    def initialize(klass, context: {})
      @class_name = Gaskit::Helpers.resolve_name(klass)

      self.context = apply_context(context).merge(class: @class_name)
      @logger = Gaskit.configuration.logger || ::Logger.new($stdout)
    rescue StandardError
      ::Logger.new($stdout).error "Failed to initialize logger: #{$ERROR_INFO}"
      @logger = ::Logger.new(nil) # fallback null logger
    end

    # Logs a debug-level message.
    #
    # @param message [String, nil] The log message (or provide it via the block parameter).
    # @param context [Hash, nil] Additional context for this specific log entry.
    # @yield Block for deferred log message computation.
    def debug(message = nil, context: {}, &block)
      log(:debug, message, context: context, &block)
    end

    # Logs an info-level message.
    #
    # @param message [String, nil] The log message (or provide it via the block parameter).
    # @param context [Hash, nil] Additional context for this specific log entry.
    # @yield Block for deferred log message computation.
    def info(message = nil, context: {}, &block)
      log(:info, message, context: context, &block)
    end

    # Logs a warning-level message.
    #
    # @param message [String, nil] The log message (or provide it via the block parameter).
    # @param context [Hash, nil] Additional context for this specific log entry.
    # @yield Block for deferred log message computation.
    def warn(message = nil, context: {}, &block)
      log(:warn, message, context: context, &block)
    end

    # Logs an error-level message.
    #
    # @param message [String, nil] The log message (or provide it via the block parameter).
    # @param context [Hash, nil] Additional context for this specific log entry.
    # @yield Block for deferred log message computation.
    def error(message = nil, context: {}, &block)
      log(:error, message, context: context, &block)
    end

    # Logs a message at the specified level.
    #
    # @param level [Symbol] The log level (e.g., :debug, :info).
    # @param message [String, nil] The log message (or provide it via the block parameter).
    # @param context [Hash, nil] Additional context for this specific log entry.
    # @yield Block for deferred log message computation.
    def log(level, message, context: {}, &block)
      return if Gaskit.configuration.disable_logging

      combined_context = filtered_context(self.context.merge(context))
      combined_context[:class] ||= @class_name

      msg = message || block&.call
      return unless loggable?(level)

      @logger.public_send(level, [msg, combined_context])
    end

    # Creates a new logger instance with additional merged context.
    #
    # @param extra_context [Hash] Additional context to include.
    # @return [Gaskit::Logger] A new logger instance with the updated context.
    def with_context(extra_context)
      self.class.new(@class_name, context: context.merge(extra_context))
    end

    private

    def apply_context(context)
      default_context = Gaskit.configuration.context_provider.call
      context = default_context.merge(context)

      Helpers.deep_compact(context)
    end

    # Filters out sensitive values from the log context based on predefined keys.
    #
    # This method transforms all context keys to symbols and checks if each key is considered sensitive.
    # If a key matches one of the predefined sensitive keys, its value is replaced with "[FILTERED]".
    #
    # @param context [Hash] The context hash to be filtered.
    # @return [Hash] The filtered context hash with sensitive values masked.
    def filtered_context(context)
      filtered_context = context.transform_keys(&:to_sym).transform_values.with_index do |value, index|
        key = context.keys[index].to_sym
        sensitive_key?(key) ? "[FILTERED]" : value
      end

      Helpers.deep_compact(filtered_context)
    end

    # Determines if a given key is considered sensitive and should be masked in logs.
    #
    # @param key [Symbol, String] The key to evaluate.
    # @return [Boolean] True if the key is sensitive and should be filtered; false otherwise.
    def sensitive_key?(key)
      SENSITIVE_KEYS.include?(key)
    end

    # Determines whether the given log level should be emitted based on the configured logger level.
    #
    # @param level [Symbol] Log level name (e.g., :debug, :info).
    # @return [Boolean] True if the logger is configured to log at this level.
    def loggable?(level)
      return false unless @logger

      severity_index = ::Logger.const_get(level.to_s.upcase)
      severity_index >= @logger.level
    rescue NameError
      false
    end
  end
end
