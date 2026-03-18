# frozen_string_literal: true

require "cattri"

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
    include Cattri

    final_cattri :key, nil
    final_cattri :code, nil

    # Initializes an OperationExit.
    #
    # @param key [Symbol, String] The symbolic exit key
    # @param message [String, nil] A human-readable message (defaults to key if not provided)
    # @param code [String, nil] A structured error code for analytics or debugging
    def initialize(key, message = nil, code: nil)
      super(message || "early exit")
      self.key = key
      self.code = code
    end

    def inspect
      "#<#{self.class} key=#{key.inspect} message=#{message.inspect} code=#{code.inspect}>"
    end
  end
end
