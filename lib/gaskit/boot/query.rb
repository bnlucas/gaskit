# frozen_string_literal: true

module Gaskit
  # Represents a result object specific for query-related operations.
  #
  # @example Handling results from a query operation
  #   result = Gaskit::QueryResult.new(true, { records: [] }, nil, duration: 2.45)
  #   if result.success?
  #     puts "Query succeeded with records: #{result.value[:records]}"
  #   else
  #     puts "Query failed: #{result.error}"
  #   end
  class QueryResult < OperationResult; end

  # A base class for query-style operations.
  #
  # @example
  #   class FindUsers < Gaskit::Query
  #     def call
  #       User.active
  #     end
  #   end
  class Query < Operation
  end
end
