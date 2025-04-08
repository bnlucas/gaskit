# frozen_string_literal: true

module Gaskit
  # OperationExit is a custom exception representing an early exit from an operation.
  #
  # It communicates intent-based flow interruption (e.g., authorization failure, validation issue)
  # and includes a symbolic `key`, optional `message`, and optional `code`.
  #
  # @example Raising an OperationExit with just a key
  #   exit(:unauthorized)
  #
  # @example With a custom message and code
  #   exit(:unauthorized, "Access denied", code: "AUTH-001")
  #
  # @example Handling OperationExit in a flow
  #   begin
  #     MyFlow.call!
  #   rescue Gaskit::OperationExit => e
  #     puts "Exited: #{e.key} - #{e.message} (#{e.code})"
  #   end
  class OperationExit < Gaskit::Error
    # @return [Symbol, String] The symbolic or textual reason for the early exit
    attr_reader :key

    # @return [String, nil] Optional structured code (e.g., "AUTH-001")
    attr_reader :code

    # Initializes an OperationExit.
    #
    # @param key [Symbol, String] The symbolic exit key
    # @param message [String, nil] A human-readable message (defaults to key if not provided)
    # @param code [String, nil] A structured error code for analytics or debugging
    def initialize(key, message = nil, code: nil)
      super(message || key.to_s)
      @key = key
      @code = code
    end
  end
end
