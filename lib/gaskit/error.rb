# frozen_string_literal: true

module Gaskit
  class Error < StandardError; end

  class ContractError < Error; end

  # Raised when an operation contract supplies an incorrect result type.
  class ResultTypeError < Error
    # @param [Class] klazz The class that failed the type check.
    def initialize(klazz)
      message = "Expected a Castkit contract or data object, got: #{klazz}"
      super(message)
    end
  end
end
