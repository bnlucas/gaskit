# frozen_string_literal: true

require "castkit"

module Gaskit
  module Types
    # Castkit type for symbol fields. Coerces via `to_sym` when possible.
    class Symbol < Castkit::Types::Base
      def deserialize(value)
        return if value.nil?
        return value if value.is_a?(::Symbol)

        value.to_sym
      rescue StandardError
        type_error!(:symbol, value)
        nil
      end

      def validate!(value, _options: {}, context: {})
        return if value.nil? || value.is_a?(::Symbol) || value.respond_to?(:to_sym)

        type_error!(:symbol, value, context: context)
      end
    end
  end
end
