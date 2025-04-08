# frozen_string_literal: true

module Gaskit
  module Helpers
    class << self
      # Measures the time taken for execution.
      #
      # @yield The block containing the logic to time.
      # @return [Array<Float, Object>] The duration and the result.
      def time_execution
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        result = yield
        duration = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time)

        [format("%.6f", duration), result]
      end

      # Applies deep compat on the provided hash.
      #
      # @param hash [Hash] The original hash to compact.
      # @return [Hash] The compacted hash.
      def deep_compact(hash)
        hash.each_with_object({}) do |(k, v), result|
          compacted = v.is_a?(Hash) ? deep_compact(v) : v
          result[k.to_sym] = compacted unless compacted.nil?
        end
      end
    end
  end
end
