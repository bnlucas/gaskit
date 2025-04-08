# frozen_string_literal: true

module Gaskit
  # Represents a result object specific for query-related operations.
  #
  # @example Handling results from a query operation
  #   result = Gaskit::QueryResult.new(true, { records: [] }, nil, 2.45)
  #   if result.success?
  #     puts "Query succeeded with records: #{result.value[:records]}"
  #   else
  #     puts "Query failed: #{result.reason}"
  #   end
  class QueryResult < OperationResult; end

  Gaskit.register_contract(:query, QueryResult)

  # A base class for query-style operations.
  #
  # This uses the `:query` contract, which must be registered with Gaskit::Registry.
  #
  # @example
  #   class FindUsers < Gaskit::Query
  #     def call
  #       User.active
  #     end
  #   end
  class Query < Operation
    use_contract :query
  end
end
