# frozen_string_literal: true

module Gaskit
  # Represents a result object specific for service-related operations.
  #
  # @example Handling results from a service operation
  #   result = Gaskit::ServiceResult.new(false, nil, RuntimeError.new("Service failed"), duration: 0.89)
  #   if result.failure?
  #     puts "Service failed: #{result.error}"
  #   end
  class ServiceResult < OperationResult; end

  # A base class for service-style operations.
  #
  # @example
  #   class MyService < Service
  #     def call
  #       "done"
  #     end
  #   end
  class Service < Operation
  end
end
