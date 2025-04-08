# frozen_string_literal: true

require "json"

module Gaskit
  # Represents the result of an operation, encapsulating success/failure, values, errors, and execution duration.
  #
  # @example Using OperationResult to handle success and failure
  #   result = Gaskit::BaseResult.new(true, "data", nil, 1.23)
  #   if result.success?
  #     puts "Operation succeeded with value: #{result.value}"
  #   else
  #     puts "Operation failed with reason: #{result.to_h[:error]}"
  #   end
  class OperationResult
    # @return [Boolean] Whether the operation was successful.
    attr_reader :success

    # @return [Object, nil] The result value of the operation, if any.
    attr_reader :value

    # @return [Exception, nil] The error that occurred during the operation, if any.
    attr_reader :error

    # @return [Float] The duration of the operation in seconds.
    attr_reader :duration

    # @return [Hash] The context used during the operation.
    attr_reader :context

    # Initializes a new instance of OperationResult.
    #
    # @param [Boolean] success Whether the operation was successful.
    # @param [Object, nil] value The value obtained as a result of the operation.
    # @param [Exception, nil] error The error encountered during the operation.
    # @param [Float, String] duration The time taken to complete the operation in seconds.
    # @param [Hash] context Optional context metadata for this operation.
    def initialize(success, value, error, duration:, context: {})
      @success = success
      @value = value
      @error = error
      @duration = format_duration(duration)
      @context = context
    end

    # Provides a human-readable string representation of the result.
    #
    # @return [String] The formatted inspection string.
    def inspect
      "#<#{self.class.name} success=#{success?} value=#{value.inspect} duration=#{duration}>"
    end

    # Indicates whether the operation was successful.
    #
    # @return [Boolean] `true` if the operation was successful, `false` otherwise.
    def success?
      @success
    end

    # Indicates whether the operation failed.
    #
    # @return [Boolean] `true` if the operation failed, `false` otherwise.
    def failure?
      !@success
    end

    # Indicates whether the operation exited early using `exit(:key)`.
    #
    # @return [Boolean] `true` if the operation exited early, `false` otherwise.
    def early_exit?
      !@success && error.is_a?(Gaskit::OperationExit)
    end

    # Returns the status of the operation result.
    #
    # @return [Symbol] :success, :failure, or :early_exit
    def status
      return :early_exit if early_exit?

      success? ? :success : :failure
    end

    # Converts the operation result to a structured hash.
    #
    # - Includes `:value` on success
    # - Includes `:exit` if early_exit?
    # - Includes `:error` if a failure occurred
    # - Always includes `:meta` with duration and context
    #
    # @return [Hash] A nested representation of the result.
    def to_h
      hash = {
        success: success?,
        status: status,
        value: value
      }.compact

      hash = failure_to_hash(hash) if failure?

      hash[:meta] = {
        duration: duration,
        context: context
      }.compact

      hash.freeze
    end

    # Serializes the result to a JSON string.
    #
    # @param options [Hash] Optional hash passed to `JSON.generate`
    # @return [String] JSON representation of the operation result
    def to_json(options = {})
      to_h.to_json(options)
    end

    private

    # Formats duration as a 6-digit string.
    #
    # @param duration [Float, String]
    # @return [String]
    def format_duration(duration)
      duration = duration.to_f
      format("%.6f", duration)
    end

    # Builds the exit section of the result hash.
    #
    # @return [Hash] Details about the early exit, including key and message.
    def exit_to_hash
      {
        key: error.key,
        message: error.message,
        code: error.respond_to?(:code) ? error.code : nil
      }.compact
    end

    # Builds the error section of the result hash.
    #
    # @return [Hash] Details about the raised exception (if any).
    def error_to_hash
      {
        type: error.class.name,
        message: error.message,
        class: error.class.name,
        backtrace: error.backtrace
      }.compact
    end

    def failure_to_hash(hash)
      hash[:exit] = exit_to_hash if early_exit?
      hash[:error] = error_to_hash if failure? && !early_exit? && error

      hash
    end
  end
end
