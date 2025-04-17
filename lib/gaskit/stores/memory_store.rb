# frozen_string_literal: true

require_relative "base"

module Gaskit
  module Stores
    # In-memory cache store for Gaskit, primarily used in tests or ephemeral environments.
    #
    # Implements namespaced keys, optional TTL-based expiration, and basic CRUD operations.
    #
    # @example Basic usage
    #   store = Gaskit::Stores::MemoryStore.new("myapp")
    #   store.write!("foo", { a: 1 }, ttl: 10)
    #   store.read!("foo") # => { a: 1 }
    #   sleep(11)
    #   store.read!("foo") # => nil (expired)
    #
    # @see Gaskit::Stores::Base
    class MemoryStore < Gaskit::Stores::Base
      # @param namespace [String] Namespace for key scoping.
      # @param logger [Logger, nil] Optional logger for debugging (unused).
      def initialize(namespace, logger: nil)
        super
        @store = {}
      end

      # Checks if a key exists and has not expired.
      #
      # @param key [String] The key to check.
      # @return [Boolean] True if the key exists and is not expired.
      def key_exists!(key)
        key = namespace_key(key)
        _, expires_at = @store[key]

        !expired?(expires_at)
      end

      # Reads a single key from the store.
      #
      # @param keys [Array<String>] Keys to read.
      # @param options [Hash] Ignored options for compatibility.
      # @return [Object, nil] A single value or a key-value hash.
      def read!(*keys, **options)
        results = read_all!(*keys, **options)
        results.fetch(key)
      end

      # Writes a single key-value pair into the store.
      #
      # @param key [String] The key to write.
      # @param value [Object] The value to write.
      # @param options [Hash] Additional options, passed to `#write_all!`.
      # @return [void]
      def write!(key, value, **options)
        write_all!({ key => value }, **options)
      end

      # Deletes one or more keys from the store.
      #
      # @param keys [Array<String>] Keys to delete.
      # @param _options [Hash] Ignored options for compatibility.
      # @return [void]
      def delete!(*keys, **_options)
        keys = keys.map { |k| namespace_key(k) }
        keys.each { |key| @store.delete(key) }
      end

      # Reads one or more keys from the store.
      #
      # @param keys [Array<String>] Keys to read.
      # @param _options [Hash] Ignored options for compatibility.
      # @return [Hash<String => Object | nil>] A single value or a key-value hash.
      def read_all!(*keys, **_options)
        keys = keys.map { |k| namespace_key(k) }

        keys.each_with_object({}) do |key, hash|
          value, expires_at = @store[key]
          hash[key] = expired?(expires_at) ? nil : value
        end
      end

      # Writes multiple key-value pairs into the store, optionally with a TTL.
      #
      # @param data [Hash<String, Object>] The data to write.
      # @param ttl [Integer, nil] Time-to-live in seconds.
      # @param _options [Hash] Ignored options for compatibility.
      # @return [Boolean] Always returns true.
      def write_all!(data, ttl: nil, **_options)
        expires_at = ttl ? Time.now.to_f + ttl : nil
        data.each do |key, value|
          @store[namespace_key(key)] = [value, expires_at]
        end

        true
      end

      # Clears all keys within the current namespace.
      #
      # @param _options [Hash] Ignored options for compatibility.
      # @return [Boolean] Always returns true.
      def flush_namespace!(**_options)
        prefix = "#{namespace}:"
        @store.delete_if { |key, _| key.start_with?(prefix) }

        true
      end

      private

      # Determines if a given expiration timestamp is expired.
      #
      # @param expires_at [Float, nil] The expiration time.
      # @return [Boolean] True if expired, false otherwise.
      def expired?(expires_at)
        expires_at && Time.now.to_f >= expires_at
      end
    end
  end
end
