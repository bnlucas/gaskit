# frozen_string_literal: true

require "rails/generators/base"

module Gaskit
  module Generators
    # A Rails generator for creating new operation classes that inherit from `Gaskit::Operation`,
    # `Gaskit::Service`, or `Gaskit::Query`, depending on the specified `--type` option.
    #
    # This generator supports namespaced operations and places them under `app/operations`.
    #
    # @example Generate a base operation
    #   rails generate gaskit:operation CreateUser
    #
    # @example Generate a service operation
    #   rails generate gaskit:operation CreateUser --type=service
    #
    # @example Generate a query operation
    #   rails generate gaskit:operation FetchUsers --type=query
    #
    # @see templates/operation.rb.tt for the ERB template used.
    class OperationGenerator < Rails::Generators::NamedBase
      SUPPORTED_TYPES = %w[base service query].freeze

      source_root File.expand_path("templates", __dir__)

      class_option :type,
                   type: :string,
                   default: "base",
                   desc: "Operation type (base, service, query)"

      def validate_type!
        return if SUPPORTED_TYPES.include?(options["type"])

        raise ArgumentError, "Invalid type: #{options["type"]}. Supported types are: #{SUPPORTED_TYPES.join(", ")}"
      end

      def create_operation_file
        validate_type!

        subdir = case options["type"]
                 when "service" then "services"
                 when "query" then "queries"
                 else "operations"
                 end

        template "operation.rb.tt", File.join("app", subdir, class_path, "#{file_name}.rb")
      end
    end
  end
end
