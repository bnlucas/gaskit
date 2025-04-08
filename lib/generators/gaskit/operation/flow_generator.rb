# frozen_string_literal: true

require "rails/generators/base"

module Gaskit
  module Generators
    # Generates a new Gaskit::Flow class using the class-based DSL.
    #
    # This generator creates a flow subclass using statically defined steps.
    #
    # @example Generates a class like:
    #   class CheckoutFlow < Gaskit::Flow
    #     step AddToCart
    #     step ApplyDiscount
    #     step Finalize
    #   end
    #
    #   CheckoutFlow.call(user_id: 123)
    #
    #   rails generate gaskit:flow Checkout AddToCart ApplyDiscount Finalize
    #
    # @see templates/flow.rb.tt for the ERB template used.
    class FlowGenerator < Rails::Generators::NamedBase
      source_root File.expand_path("templates", __dir__)

      # List of operation steps for the flow
      argument :steps, type: :array, default: [], banner: "StepOne StepTwo"

      def create_flow_file
        template "flow.rb.tt", File.join("app/flows", class_path, "#{file_name}_flow.rb")
      end
    end
  end
end
