# frozen_string_literal: true

require "json"
require "zlib"
require_relative "base"

module Gaskit
  module Stores
    # Redis-backed store for Gaskit with namespaced key management, optional TTL,
    # compressed + serialized values, and configurable error handling.
    #
    # This implementation supports both strict (`read!`) and tolerant (`read`) access patterns.
    #
    # @example Basic Usage
    #   store = Gaskit::Stores::RedisStore.new("app", Redis.new)
    #   store.write!("foo", { a: 1 })
    #   store.read!("foo") # => { "a" => 1 }
    #
    class RedisStore < Gaskit::Stores::Base
      final_cattri :connection, nil

      # @param namespace [String] Key namespace prefix
      # @param connection [::Redis] A Redis client instance
      # @param logger [Logger, nil] Optional logger
      # @param serializer [#call, nil] Callable to serialize values (default: JSON)
      # @param deserializer [#call, nil] Callable to deserialize values (default: JSON)
      def initialize(namespace, connection, logger: nil, serializer: nil, deserializer: nil)
        self.connection = connection
        super(namespace, logger: logger)

        @serializer = serializer
        @deserializer = deserializer
      end

      # Safe check if a key exists
      #
      # @param key [String]
      # @return [Boolean]
      def key_exists!(key)
        safe_op { key_exists?(key) } || false
      end

      # Strict check if a key exists
      #
      # @param key [String]
      # @return [Boolean]
      def key_exists?(key)
        connection.exists?(namespace_key(key))
      end

      # Safe read of a single key. Errors are caught and logged.
      #
      # @param key [String]
      # @param purge_on_error [Boolean] Whether to purge corrupted keys
      # @param fail_on_error [Boolean] Whether to raise on deserialization failure (default: false)
      # @return [Object, nil]
      def read(key, purge_on_error: false, **options)
        safe_op { read!(key, purge_on_error: purge_on_error, **options) }
      end

      # Strict read of a single key. Raises on deserialization failure.
      #
      # @param key [String]
      # @param purge_on_error [Boolean] Whether to purge corrupted keys
      # @param fail_on_error [Boolean] Whether to raise on deserialization failure (default: false)
      # @return [Object, nil]
      def read!(key, purge_on_error: false, **options)
        result = read_all!(key, purge_on_error: purge_on_error, **options)
        result.fetch(namespace_key(key))
      end

      # Writes a single key
      #
      # @param key [String]
      # @param value [Object]
      # @return [Boolean]
      def write!(key, value, **options)
        write_all!({ key => value }, **options)
      end

      # Deletes one or more keys
      #
      # @param keys [Array<String>]
      # @return [Integer] Number of keys deleted
      def delete!(*keys, **options)
        keys = namespaced_keys(keys)
        return scan(keys.first, **options) { |found_keys, _| connection.del(*found_keys) } if wildcard_key?(keys)

        connection.del(*keys)
      end

      # Safe read of one or more keys. Errors are caught and logged.
      #
      # @param keys [Array<String>]
      # @param purge_on_error [Boolean] Whether to purge corrupted keys
      # @param fail_on_error [Boolean] Whether to raise on deserialization failure (default: false)
      # @return [Hash{String => Object, nil}]
      def read_all(*keys, purge_on_error: true, **options)
        safe_op { read_all!(*keys, purge_on_error: purge_on_error, **options) }
      end

      # Strict read of one or more keys. Raises on deserialization failure.
      #
      # @param keys [Array<String>]
      # @param purge_on_error [Boolean] Whether to purge corrupted keys
      # @param fail_on_error [Boolean] Whether to raise on deserialization failure (default: false)
      # @return [Hash{String => Object, nil}]
      def read_all!(*keys, purge_on_error: true, **options)
        keys = namespaced_keys(keys)
        results = read_keys(keys, options: options)

        results.each_with_object({}) do |(key, value), hash|
          hash[key] = deserialize(key, value, purge_on_error: purge_on_error, **options)
        end
      end

      # Writes multiple key-value pairs in a single transaction
      #
      # @param data [Hash{String => Object}]
      # @param options [Hash] May include :ttl (seconds)
      # @return [Boolean]
      def write_all!(data, **options)
        flattened = data.flat_map do |key, value|
          [namespace_key(key), serialize(value)]
        end

        status, = connection.multi do |conn|
          conn.mset(*flattened)
          data.each_key { |key| conn.expire(namespace_key(key), options[:ttl]) } if options[:ttl]
        end

        status
      end

      # Deletes all keys in the current namespace
      #
      # @return [void]
      def flush_namespace!(**options)
        delete!("*", **options)
      end

      # Scans Redis keys matching a pattern in batches
      #
      # @param key_pattern [String]
      # @param batch_size [Integer]
      # @yield [keys, results]
      # @yieldparam keys [Array<String>]
      # @yieldparam results [Array<Object>]
      # @return [Array<Object>] Final accumulated results
      def scan(key_pattern, batch_size: 1000, &block)
        cursor = "0"
        results = []

        loop do
          cursor, keys = connection.scan(cursor, match: key_pattern, count: batch_size)
          block.call(keys, results)

          break if cursor == "0"
        end

        results
      end

      private

      # Applies namespacing to a list of keys
      #
      # @param keys [Array<String>]
      # @return [Array<String>]
      def namespaced_keys(keys)
        keys.map { |key| namespace_key(key) }
      end

      # Determines whether a wildcard read is being requested
      #
      # @param keys [Array<String>]
      # @return [Boolean]
      def wildcard_key?(keys)
        keys.size == 1 && keys.first.include?("*")
      end

      def read_keys(keys, options:)
        return keys.zip(connection.mget(*keys)) unless wildcard_key?(keys)

        scan(keys.first, **options) do |found_keys, batch_results|
          values = connection.mget(*found_keys)
          batch_results.concat(found_keys.zip(values))
        end
      end

      # Lazily resolve serializer
      #
      # @return [#call]
      def serializer
        @serializer ||= ->(value) { value.nil? ? value : JSON.dump(value) }
      end

      # Lazily resolve deserializer
      #
      # @return [#call]
      def deserializer
        @deserializer ||= ->(value) { value.nil? ? value : JSON.parse(value) }
      end

      # Serializes and compresses a value
      #
      # @param value [Object, nil]
      # @return [String, nil]
      def serialize(value)
        return nil if value.nil?

        value = value.to_h if value.respond_to?(:to_h)
        Zlib::Deflate.deflate(serializer.call(value))
      end

      # Decompresses and deserializes a value
      #
      # @param key [String] Full Redis key
      # @param value [String, nil]
      # @param fail_on_error [Boolean] Raise error or return nil
      # @param purge_on_error [Boolean] Delete key if deserialization fails
      # @return [Object, nil]
      def deserialize(key, value, fail_on_error: false, purge_on_error: true)
        return nil if value.nil?

        inflated = Zlib::Inflate.inflate(value.to_s)
        deserializer.call(inflated)
      rescue StandardError => e
        if purge_on_error
          logger.warn("[#{self.class}] Purging corrupted key: #{key}")
          connection.del(key)
        end

        raise e if fail_on_error

        nil
      end
    end
  end
end
