# frozen_string_literal: true

module Gaskit
  # Represents a result object specific for service-related operations.
  #
  # @example Handling results from a service operation
  #   result = Gaskit::ServiceResult.new(false, nil, RuntimeError.new("Service failed"), 0.89)
  #   if result.failure?
  #     puts "Service failed: #{result.reason}"
  #   end
  class ServiceResult < OperationResult; end

  Gaskit.contracts.register(:service, ServiceResult)

  # A base class for service-style operations.
  #
  # This uses the `:service` contract, which must be registered with Registry.
  #
  # @example
  #   class MyService < Service
  #     def call
  #       "done"
  #     end
  #   end
  class Service < Operation
    use_contract :service
  end
end
