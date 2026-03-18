# frozen_string_literal: true

require "castkit"

module Gaskit
  module Types
    # Permissive Castkit type that accepts and returns any value untouched.
    # Used for fields like `value` or `error` payloads where callers control the shape.
    class Any < Castkit::Types::Base
      def validate!(value, options: {}, context: {})
        validator = options[:validator]
        return unless validator

        validator.call(value, options: options, context: context)
      end
    end
  end
end
