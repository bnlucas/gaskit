# frozen_string_literal: true

require "rails/generators/base"

module Gaskit
  module Generators
    # A Rails generator for creating new service classes that inherit from `Gaskit::Query`.
    #
    # This generator supports namespaced queries and places them under `app/queries`.
    #
    # @example Generate a base operation
    #   rails generate gaskit:query FetchUserQuery
    #
    # @see templates/operation.rb.tt for the ERB template used.
    class QueryGenerator < OperationGenerator
      def initialize(*args)
        super
        options[:type] = "query"
      end
    end
  end
end
