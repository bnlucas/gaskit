# frozen_string_literal: true

require "castkit"
require_relative "types/any"
require_relative "types/symbol"

module Gaskit
  # Sets up Castkit defaults and registers shared Gaskit-specific types.
  module Castkit
    module_function

    def configure
      ::Castkit.configure do |config|
        config.enforce_typing = true
        config.enforce_attribute_access = true
        config.enforce_array_options = true
        config.strict_by_default = true

        config.register_type(:any, Gaskit::Types::Any, aliases: [:object])
        config.register_type(:symbol, Gaskit::Types::Symbol, aliases: [:sym])
      end
    end
  end
end

Gaskit::Castkit.configure
