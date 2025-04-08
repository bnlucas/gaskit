# frozen_string_literal: true

require "rails/generators/base"

module Gaskit
  module Generators
    # A Rails generator for creating new service classes that inherit from `Gaskit::Service`.
    #
    # This generator supports namespaced services and places them under `app/services`.
    #
    # @example Generate a base operation
    #   rails generate gaskit:service CreateUserService
    #
    # @see templates/operation.rb.tt for the ERB template used.
    class ServiceGenerator < OperationGenerator
      def initialize(*args)
        super
        options[:type] = "service"
      end
    end
  end
end
